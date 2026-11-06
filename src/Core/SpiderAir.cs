namespace SpiderBuddy.Core;

/// <summary>
/// Stage 7 — air. Minimum-energy leap arcs (corrected for drag), flight, edge bounces, landing on a
/// surface, falls and the escape when a window comes over it.
/// </summary>
public sealed partial class Spider
{
    public const double Gravity = 1950;
    public const double MaxJumpSpeed = 1250;
    public const double AirDrag = 0.22;

    public double AirTime;
    public double Tumble, TumbleVel;
    public bool LandDrop;
    public double LandedAt = -99;
    public double EscapeUntil = -99;
    public V2? PendingJump { get; private set; }
    /// <summary>The launch as it left the legs, before the first frame of gravity (spec 7.1).</summary>
    public V2 LaunchVelocity { get; private set; }
    public bool Bounced { get; private set; }
    public double BounceRestitution => M.Lerp(0.28, 0.72, Design.Gait.Bounciness);

    double _coveredFor;
    bool _lineAsked;
    double _airFacing = 1;

    // ------------------------------------------------------------------ ballistics

    /// <summary>
    /// Spec 7.1: the minimum-energy launch for the distance, then corrected for air drag by flying
    /// the arc and nudging the launch until it lands on the mark. A jump that needs more than
    /// `maxJumpSpeed` is refused outright — never silently short.
    /// </summary>
    public bool Arc(V2 to, out V2 velocity) => Arc(Pos, to, out velocity, null);

    public static bool Arc(V2 from, V2 to, out V2 velocity) => Arc(from, to, out velocity, null);

    public bool Arc(V2 to, out V2 velocity, V2? surfaceNormal) => Arc(Pos, to, out velocity, surfaceNormal);

    /// <summary>
    /// Spec 7.1: the minimum-energy launch, taking the flatter of the two parabolas that land on the
    /// mark — but never one that starts into the surface it is standing on. Drag is corrected for by
    /// flying the arc; an arc that would need more than `maxJumpSpeed` is refused.
    /// </summary>
    public static bool Arc(V2 from, V2 to, out V2 velocity, V2? surfaceNormal)
    {
        velocity = V2.Zero;
        V2 d = to - from;
        double vMin = Math.Sqrt(Gravity * (d.Y + d.Length));
        if (!double.IsFinite(vMin) || vMin <= 0)
        {
            // Straight down onto a point below: the slowest way is a drop.
            if (d.Y < 0 && Math.Abs(d.X) < 0.5)
            {
                double speed = Math.Min(MaxJumpSpeed, Math.Sqrt(2 * Gravity * -d.Y));
                var drop = new V2(0, -speed);
                if (surfaceNormal is { } dn && drop.Dot(dn) < -0.15) return false;
                velocity = drop;
                return true;
            }
            return false;
        }
        if (vMin > MaxJumpSpeed) return false;

        double v = Math.Min(vMin * 1.06, MaxJumpSpeed);
        if (!Roots(v, d, out V2 flat, out V2 steep)) return false;

        // Flatter first; if that one starts into the surface, the steeper parabola may clear it.
        foreach (var seed in new[] { flat, steep })
        {
            if (!CorrectForDrag(from, seed, to, out V2 candidate)) continue;
            if (candidate.Length > MaxJumpSpeed) continue;
            if (surfaceNormal is { } n && candidate.Dot(n) < -0.15) continue;
            velocity = candidate;
            return true;
        }
        return false;
    }

    /// <summary>
    /// Drag pulls the shot short in both axes. Fly the arc, measure how near the mark it came, and
    /// nudge the launch along that miss a few times — a wall or a ceiling is hit where it is hit.
    /// </summary>
    static bool CorrectForDrag(V2 from, V2 seed, V2 to, out V2 velocity)
    {
        velocity = seed;
        V2 c = seed;
        for (int i = 0; i < 8; i++)
        {
            V2 closest = SimulateClosest(from, c, to, out double flight);
            V2 miss = to - closest;
            if (miss.Length < 0.1) break;
            c += miss / Math.Max(flight, 0.1);
            if (!double.IsFinite(c.X) || !double.IsFinite(c.Y)) return false;
        }
        velocity = c;
        return true;
    }

    static V2 SimulateClosest(V2 from, V2 velocity, V2 target, out double flight)
    {
        const double h = 1.0 / 240;
        V2 p = from, v = velocity;
        double t = 0, best = p.DistanceTo(target), bestT = 0;
        V2 bestP = p;
        for (int i = 0; i < 1440; i++)
        {
            v += new V2(0, -Gravity) * h;
            v *= Math.Exp(-AirDrag * h);
            p += v * h;
            t += h;
            double dist = p.DistanceTo(target);
            if (dist < best) { best = dist; bestP = p; bestT = t; }
            if (dist < 0.8) break;
            if (i > 20 && dist > best + 40) break;
        }
        flight = bestT;
        return bestP;
    }

    /// <summary>The two vacuum parabolas that land on the target: flatter first, then the lob.</summary>
    static bool Roots(double v, V2 d, out V2 flat, out V2 steep)
    {
        flat = steep = V2.Zero;
        double dx = Math.Abs(d.X);
        if (dx < 1e-6)
        {
            if (d.Y < 0) return false;
            double vy = Math.Sqrt(Math.Max(0, 2 * Gravity * d.Y));
            flat = steep = new V2(0, vy);
            return true;
        }
        double v2 = v * v;
        double raw = v2 * v2 - Gravity * (Gravity * dx * dx + 2 * d.Y * v2);
        if (raw < -1e-6) return false;
        double s = Math.Sqrt(Math.Max(0, raw));
        double denom = Gravity * dx;
        double u1 = (v2 - s) / denom;
        double u2 = (v2 + s) / denom;
        double vx1 = v / Math.Sqrt(1 + u1 * u1);
        double vx2 = v / Math.Sqrt(1 + u2 * u2);
        double sg = Math.Sign(d.X);
        flat = new V2(sg * vx1, u1 * vx1);
        steep = new V2(sg * vx2, u2 * vx2);
        return true;
    }

    /// <summary>Fly a candidate launch until it next crosses `landY` downward.</summary>
    static V2 Simulate(V2 from, V2 velocity, double landY, out double flight)
    {
        const double dt = 1.0 / 240;
        V2 p = from, v = velocity;
        flight = 0;
        for (int i = 0; i < 2400; i++)
        {
            V2 prev = p;
            v += new V2(0, -Gravity) * dt;
            v *= Math.Exp(-AirDrag * dt);
            p += v * dt;
            flight += dt;
            if (i > 3 && prev.Y >= landY && p.Y <= landY && v.Y < 0)
            {
                double f = (prev.Y - landY) / Math.Max(1e-9, prev.Y - p.Y);
                return V2.Lerp(prev, p, M.Clamp01(f));
            }
        }
        return p;
    }

    // ------------------------------------------------------------------ jumping

    /// <summary>Crouch, then launch at a target (spec 7.1). False when the target is out of reach.</summary>
    V2? SurfaceNormalHere
    {
        get
        {
            var seg = Map.Loop(Anchor.LoopId)?.SegAt(Anchor.SegIdx);
            return seg is { } s && s.Normal.LengthSquared > 0.1 ? s.Normal : null;
        }
    }

    public bool StartJump(V2 target)
    {
        if (Cinema) return false;
        if (Box is { } box && !box.Contains(target)) return false;
        if (!Arc(target, out V2 v, SurfaceNormalHere)) return false;
        // A drop straight down a wall is not a leap onto it.
        var seg = Map.Loop(Anchor.LoopId)?.SegAt(Anchor.SegIdx);
        if (seg is { } s0 && Math.Abs(v.X) < 1 && Math.Abs(s0.Normal.Y) < 0.5) return false;
        // A leap that would come back down on the ledge it set off from, or run into anything else
        // on the way, is never attempted (spec 7.1: a jump either looks like a jump or is not made).
        if (WouldStrikeOwnSurface(target, v) || ArcBlocked(target, v)) return false;
        PendingJump = target;
        Play(Activity.Crouch, 0.45);
        return true;
    }

    /// <summary>A pounce launches at once, aimed at its mark (spec 10.3).</summary>
    public bool LeapAt(V2 target)
    {
        if (Mode != Mode.Attached || !StartJump(target)) return false;
        PendingJump = null;
        LaunchJump(target);
        return true;
    }

    /// <summary>True when something solid crosses the arc before the mark.</summary>
    bool ArcBlocked(V2 target, V2 velocity)
    {
        const double h = 1.0 / 120;
        V2 p = Pos, v = velocity;
        for (int step = 0; step < 360; step++)
        {
            V2 prev = p;
            v += new V2(0, -Gravity) * h;
            v *= Math.Exp(-AirDrag * h);
            p += v * h;
            foreach (var loop in Map.AllLoops)
            {
                foreach (var seg in loop.Segs)
                {
                    if (seg.Normal.LengthSquared < 0.1) continue;
                    double d0 = (prev - seg.A).Dot(seg.Normal);
                    double d1 = (p - seg.A).Dot(seg.Normal);
                    if (!(d0 >= 0 && d1 <= 0) || Math.Abs(d0 - d1) < 1e-9) continue;
                    double f = M.Clamp01(d0 / (d0 - d1));
                    V2 cross = V2.Lerp(prev, p, f);
                    var (t, _) = M.ProjectOnSegment(cross, seg.A, seg.B);
                    if (t <= 0.001 || t >= 0.999) continue;
                    if (cross.DistanceTo(target) > 18) return true;
                    return false;   // this is the landing
                }
            }
            if (p.DistanceTo(target) < 8) return false;
        }
        return false;
    }

    /// <summary>True when the arc lands back on the launch ledge, short of its mark (spec 7.1).</summary>
    bool WouldStrikeOwnSurface(V2 target, V2 velocity)
    {
        var loop = Map.Loop(Anchor.LoopId);
        if (loop is null || Anchor.SegIdx >= loop.Segs.Count) return false;
        var seg = loop.Segs[Anchor.SegIdx];
        if (seg.Normal.LengthSquared < 0.1) return false;

        const double h = 1.0 / 240;
        V2 p = Pos, v = velocity;
        double before = (p - seg.A).Dot(seg.Normal);
        for (int i = 0; i < 2400; i++)
        {
            v += new V2(0, -Gravity) * h;
            v *= Math.Exp(-AirDrag * h);
            p += v * h;
            double now = (p - seg.A).Dot(seg.Normal);
            if (before >= 0 && now <= 0)
            {
                var (t, _) = M.ProjectOnSegment(p, seg.A, seg.B);
                double along = t * seg.Len;
                bool onLedge = along > 0.5 && along < seg.Len - 0.5;
                if (onLedge && p.DistanceTo(target) > 20) return true;
                return false;
            }
            before = now;
            if (p.DistanceTo(target) < 10) return false;
            if (v.Y < 0 && p.Y < Math.Min(Pos.Y, target.Y) - 80) break;
        }
        return false;
    }

    public void LaunchJump(V2 target)
    {
        V2? normal = SurfaceNormalHere;
        if (!Arc(target, out V2 v, normal) || WouldStrikeOwnSurface(target, v))
        {
            // A launch that would go into its own surface: let go and push away instead.
            DetachAndFall(normal is { } n ? n * 45 : V2.Zero);
            return;
        }
        _launchPos = Pos;
        Mode = Mode.Air;
        Air = AirKind.Leap;
        AirTime = 0;
        _anchorLoopAtLaunch = Anchor.LoopId;
        Velocity = v;
        LaunchVelocity = v;
        NoAttachFor = 0.12;
        _lineAsked = false;
        _airFacing = v.X >= 0 ? 1 : -1;
        Tumble = 0;
        TumbleVel = 0;
        Play(Activity.Pounce, 0.4);
    }

    public void DetachAndFall(V2? push = null)
    {
        Mode = Mode.Air;
        Air = AirKind.Fall;
        AirTime = 0;
        Velocity = push ?? V2.Zero;
        LaunchVelocity = Velocity;
        NoAttachFor = 0.1;
        _lineAsked = false;
        _airFacing = Velocity.X >= 0 ? 1 : -1;
    }

    /// <summary>One frame in flight (spec 7.1): gravity, drag, edges, landing, rescue.</summary>
    void UpdateAir(double dt)
    {
        AirTime += dt;
        // A pounce snaps at whatever the fangs pass in the air (spec 10.3).
        if (PreyHunt == HuntStage.Pounce) SnapAtPrey(6);
        NoAttachFor = Math.Max(0, NoAttachFor - dt);
        Bounced = false;

        // Integrate in swept substeps: at throw speed a single frame's travel is longer than the
        // landing radius, and one big step would skip straight past the ledge it was aimed at.
        int steps = (int)M.Clamp(Math.Ceiling(Velocity.Length * dt / 4.0), 1, 16);
        double h = dt / steps;
        for (int k = 0; k < steps; k++)
        {
            V2 before = Pos;
            Velocity += new V2(0, -Gravity) * h;
            Velocity *= Math.Exp(-AirDrag * h);
            if (TumbleVel != 0) { Tumble += TumbleVel * h; TumbleVel *= Math.Exp(-1.1 * h); }

            Pos += Velocity * h;
            BounceOffScreens();

            if (NoAttachFor <= 0 && AirTime > 0.03)
            {
                string? excluding = AirTime < 0.28 ? _anchorLoopAtLaunch : null;
                double reach = Math.Max(18 * Scale, Velocity.Length * h * 1.2);
                var spot = Map.NearestSpot(Pos, reach, excluding, Scale);
                if (spot is { } hit)
                {
                    var loop = Map.Loop(hit.LoopId);
                    bool visible = loop is null || !loop.Kind.OnWindow() || Map.IsVisible(hit.Point, loop.Depth);
                    if (!visible) continue;
                    var seg = loop?.SegAt(hit.SegIdx);
                    bool take = seg is null;
                    if (seg is { } sg && sg.Normal.LengthSquared > 0.1)
                    {
                        // Take hold on crossing the face — not while merely flying above it.
                        double d0 = (before - sg.A).Dot(sg.Normal);
                        double d1 = (Pos - sg.A).Dot(sg.Normal);
                        // Only on crossing the face: flying along above a ledge is not landing on it.
                        take = d0 >= -1e-6 && d1 <= 0;
                    }
                    // A pounce grabs nothing until near its mark, past it falling, or late (spec 10.3).
                    if (take && PreyHunt == HuntStage.Pounce && Air == AirKind.Leap
                        && PounceMark is { } mark && AirTime <= 1.6)
                    {
                        bool near = Pos.DistanceTo(mark) < 34 * Scale;
                        bool past = LaunchVelocity.LengthSquared > 1
                            && (Pos - mark).Dot(LaunchVelocity.Normalized) > 0 && Velocity.Y < 0;
                        if (!near && !past) take = false;
                    }
                    if (take)
                    {
                        // Land on the exact point where the path crossed the face, not wherever the
                        // body happened to be at the end of the substep.
                        if (seg is { } plane && plane.Normal.LengthSquared > 0.1)
                        {
                            double d0 = (before - plane.A).Dot(plane.Normal);
                            double d1 = (Pos - plane.A).Dot(plane.Normal);
                            if (d0 >= -1e-6 && d1 <= 0 && Math.Abs(d0 - d1) > 1e-9)
                            {
                                double f = M.Clamp01(d0 / (d0 - d1));
                                V2 cross = V2.Lerp(before, Pos, f);
                                var (tc, _) = M.ProjectOnSegment(cross, plane.A, plane.B);
                                var anchor = new Anchor(hit.LoopId, hit.SegIdx, tc * plane.Len, hit.Anchor.Dir);
                                var resolved = Map.Resolve(anchor, 38 * Scale);
                                hit = new Spot(anchor, resolved.Pos, hit.LoopId, hit.Kind, hit.SegIdx, hit.Depth);
                            }
                        }
                        LandOn(hit);
                        return;
                    }
                }
            }
        }

        // Pitch into the arc, never past about 50° — beyond that it reads as tumbling.
        if (Velocity.Length > 12)
        {
            double ang = Math.Atan2(Velocity.Y, Velocity.X);
            if (Math.Cos(ang) >= 0)
            {
                _airFacing = 1;
                Heading = M.Clamp(ang, -0.85, 0.85);
            }
            else
            {
                _airFacing = -1;
                Heading = M.Clamp(M.WrapPi(ang - Math.PI), -0.85, 0.85);
            }
        }

        // Dropped too far to catch anything: ask for a rescue line (caught in Stage 8).
        if (!_lineAsked && Velocity.Y < -250 && AirTime > 0.45)
        {
            double below = Map.LandingBelow(Pos, 40 * Scale);
            if (double.IsNaN(below) || Pos.Y - below > 320 * Scale)
            {
                _lineAsked = true;
                RescueLineRequested = true;
            }
        }
    }

    string? _anchorLoopAtLaunch;
    V2 _launchPos;

    void BounceOffScreens()
    {
        var screen = Map.ScreenFrameContaining(Pos);
        if (screen is null) return;
        var r = screen.Frame;
        double e = BounceRestitution;
        bool hit = false;
        if (Pos.X < r.MinX) { Pos = new V2(r.MinX, Pos.Y); if (Velocity.X < 0) { Velocity = new V2(-Velocity.X * e, Velocity.Y); hit = true; } }
        else if (Pos.X > r.MaxX) { Pos = new V2(r.MaxX, Pos.Y); if (Velocity.X > 0) { Velocity = new V2(-Velocity.X * e, Velocity.Y); hit = true; } }
        if (Pos.Y > r.MaxY) { Pos = new V2(Pos.X, r.MaxY); if (Velocity.Y > 0) { Velocity = new V2(Velocity.X, -Velocity.Y * e); hit = true; } }
        else if (Pos.Y < r.MinY) { Pos = new V2(Pos.X, r.MinY); if (Velocity.Y < 0) { Velocity = new V2(Velocity.X, -Velocity.Y * e); hit = true; } }
        if (hit)
        {
            Bounced = true;
            // Only a real impact spins it; resting against an edge must not keep adding to the tumble.
            if (Velocity.Length > 30) TumbleVel += (Velocity.X >= 0 ? 1 : -1) * 1.4;
        }
    }

    void LandOn(Spot spot)
    {
        bool wasLeap = Air == AirKind.Leap;
        SetAnchor(spot.Anchor.LoopId, spot.Anchor.SegIdx, spot.Anchor.T, spot.Anchor.Dir);
        Mode = Mode.Attached;
        Air = AirKind.Fall;
        AirTime = 0;
        Tumble = 0;
        TumbleVel = 0;
        Velocity = V2.Zero;
        LaunchVelocity = V2.Zero;
        NoAttachFor = 0;
        LandDrop = true;
        LandedAt = Time;
        Lift.Value = Math.Max(Lift.Value, 14 * Scale);
        Lift.Velocity = -60;
        Crouch.Velocity += 4;
        RescueLineRequested = false;
        Play(Activity.Idle, 1);
        if (wasLeap && LeaveTraces && Rng.Chance(TraceLeapChance))
            AddStrand(_launchPos, spot.Point, _anchorLoopAtLaunch, spot.LoopId);
        _anchorLoopAtLaunch = null;
        DecisionIn = Math.Max(DecisionIn, Rng.Range(1.2, 2.4));
    }

    /// <summary>Finish a landing: the legs take the blow and give under the rest (spec 7.1).</summary>
    void UpdateLandDrop(double dt)
    {
        if (!LandDrop) return;
        Lift.Value += Lift.Velocity * dt;
        if (Lift.Value <= 0 || Time - LandedAt > 0.5)
        {
            Lift.Value = Math.Min(Lift.Value, 0);
            Lift.Velocity *= 0.35;
            LandDrop = false;
        }
    }

    /// <summary>Always recoverable: "Bring to the Middle" (spec 7.6).</summary>
    public bool BringToMiddle()
    {
        var screen = Map.ScreenFrameContaining(Pos) ?? Map.Screens.FirstOrDefault();
        if (screen is null) return false;
        V2 middle = screen.VisibleFrame.Mid;
        var spot = Map.NearestSpot(middle, 1e6, null, Scale)
                   ?? Map.SampleSpots(34, true, Scale).FirstOrDefault();
        if (spot.Point == V2.Zero && spot.LoopId is null) return false;
        LandOn(spot);
        return true;
    }

    // ------------------------------------------------------------------ being covered (7.6)

    /// <summary>
    /// A window's edge that slides over it: out from under within two polls, never by walking along
    /// the covered edge (spec 7.6).
    /// </summary>
    void UpdateCovered(double dt)
    {
        // Peek-a-boo is deliberately behind a window; do not bolt from the hiding place (spec 9).
        if (Peek != PeekPhase.None) { _coveredFor = 0; return; }
        if (Mode != Mode.Attached || string.IsNullOrEmpty(Anchor.LoopId)) { _coveredFor = 0; return; }
        var loop = Map.Loop(Anchor.LoopId);
        if (loop is null || !loop.Kind.OnWindow()) { _coveredFor = 0; return; }
        bool covered = !Map.IsVisible(Pos, loop.Depth) || !loop.Segs[Anchor.SegIdx].IsOpen(Anchor.T);
        if (!covered) { _coveredFor = 0; return; }
        _coveredFor += dt;
        if (_coveredFor < 0.05 || Time < EscapeUntil) return;
        EscapeOcclusion();
    }

    public void EscapeOcclusion()
    {
        if (Mode != Mode.Attached) return;
        EscapeUntil = Time + 2.0;
        _coveredFor = 0;
        PendingJump = null;
        Startled.Velocity = 6;

        // A clear spot nearby is a leap; otherwise a line up or simply letting go.
        Spot? best = null;
        foreach (var spot in Map.SampleSpots(38, true, Scale))
        {
            var loop = Map.Loop(spot.LoopId);
            if (loop is not null && loop.Kind.OnWindow() && !Map.IsVisible(spot.Point, loop.Depth)) continue;
            double d = spot.Point.DistanceTo(Pos);
            if (d < 24 || d > 520 * Scale) continue;
            if (best is null || d < best.Value.Point.DistanceTo(Pos)) best = spot;
        }
        if (best is { } target && Arc(target.Point, out _)) { LaunchJump(target.Point); return; }
        DetachAndFall(new V2(0, 40));
    }
}
