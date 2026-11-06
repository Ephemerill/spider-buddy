namespace SpiderBuddy.Core;

/// <summary>
/// The spider on the desktop: where it stands, how it moves along a surface, and the pose it hands
/// to the renderer. Stages 4–9 grow here; the frame order of spec 4.1 is preserved as methods are
/// added so nothing has to be re-ordered later.
/// </summary>
public sealed partial class Spider
{
    public const double WalkSpeed = 62;          // px/s at scale 1
    public const double CornerRadius = 38;       // spider cornering constant (spec 4.7)
    public const double CrouchDrop = 7.5;        // units at crouch 1
    public const double GrabRadius = 30;         // × scale

    // ---------------------------------------------------------------- identity

    public SpiderDesign Design;
    public double UserScale = 0.78;             // the Size setting
    public double Scale => UserScale;           // (× unitsPerPoint on a monitor, Stage 2.9)
    public readonly Rng Rng;

    public Spider(SpiderDesign design, SurfaceMap map, Rng? rng = null)
    {
        Design = design;
        Map = map;
        Rng = rng ?? new Rng(12345);
        Gait.Stride = 1;
        PointerRemembered += OnPointerMemory;
    }

    public SurfaceMap Map { get; private set; }
    public void SetMap(SurfaceMap map) => Map = map;

    // ---------------------------------------------------------------- state

    public Mode Mode = Mode.Attached;
    public AirKind Air = AirKind.Fall;
    public Activity Activity = Activity.Idle;
    public double ActivityTime, ActivityDur = 1;
    public double ActivityU => ActivityDur <= 1e-9 ? 1 : M.Clamp01(ActivityTime / ActivityDur);

    public Anchor Anchor;
    public int WalkDir = 1;                       // ±1 along the segment

    /// <summary>The yaw sign: which way along the surface it is looking. +1 → −1 through a turn.</summary>
    public double Facing = 1;

    public V2 Pos;
    public double Heading;                        // surface heading (not the facing)

    public double Speed;                          // world units/s
    public double TargetSpeed;
    public double WalkSpeedScale = 1;             // per-bout multiplier

    public Spring Lift = new(0, 140, 21);
    public Spring Pitch = new(0, 120, 20);
    public Spring Crouch = new(0, 200, 25);
    public Spring Wag = new(0, 90, 12);
    public Spring HeadingSpring = new(0, 190, 21);

    string _lastLoop = "";
    public Spring Yaw = new(1, 150, 20);
    public Spring Happy = new(0, 120, 14);
    public Spring Startled = new(0, 190, 17);
    public Spring GroundedSpring = new(1, 120, 18);
    public Spring Lid = new(0, 60, 13);
    public Spring Stretch = new(1, 320, 20);
    public Spring Fatten = new(1, 320, 20);
    public Spring NameTag = new(0, 60, 12);
    public Spring Grasped = new(0, 200, 18);

    public readonly GaitDriver Gait = new();

    public double Time;
    public double Odometer;
    public double Blink;
    public double BlinkTimer = 2.5;
    public double HeadTurn;
    public double AbdomenTilt;
    public double BodyPitchExtra;
    public V2 Look;
    public double IdleFor;

    /// <summary>How long since the last direction change — the heading commitment (spec 6.2).</summary>
    public double KeepHeadingFor;

    public bool Grounded => Mode == Mode.Attached;
    public bool OnSurface => Anchor.IsValid && Map.Loop(Anchor.LoopId) is not null;

    /// <summary>Distance the surface itself moved under it this frame (a dragged window).</summary>
    public V2 SurfaceMotion;

    /// <summary>
    /// The gait bob, applied straight off the cycle rather than through a spring: a two-per-cycle
    /// oscillation is far faster than the lift spring can follow, and the spec asks for a visible
    /// bob that the planted legs flex against (spec 4.5).
    /// </summary>
    public double BobOffset { get; private set; }

    /// <summary>The body height the pose and the foot-planting maths both use.</summary>
    public double BodyLift => Lift.Value + BobOffset;
    V2 _lastPos;
    double _lastLift;
    double _lastHeadingDrawn;

    // ---------------------------------------------------------------- placement

    public void SetAnchor(string loopId, int segIdx, double t, int dir)
    {
        Anchor = new Anchor(loopId, segIdx, t, dir);
        WalkDir = dir >= 0 ? 1 : -1;
        Facing = WalkDir;
        Heading = HeadingForAnchor(Anchor);
        HeadingSpring.Reset(Heading);
        Yaw.Reset(Facing);
        var sp = Map.Resolve(Anchor, CornerRadius * Scale);
        Pos = sp.Pos;
        if (Anchor.IsValid) { Pos = Map.Resolve(Anchor, CornerRadius * Scale).Pos; }
        _lastPos = Pos;
        _lastHeadingDrawn = HeadingSpring.Value;
        double profile = SpiderRig.ProfileAmount(Facing);
        Gait.PlantAtRest(profile, Design.Look.Legs, default);
    }

    double HeadingForAnchor(Anchor a)
    {
        var loop = Map.Loop(a.LoopId);
        var seg = loop?.SegAt(a.SegIdx);
        if (seg is null) return Heading;
        return seg.Dir.Angle;
    }

    /// <summary>Advance along the surface by a distance, turning at the ends (spec 4.4).</summary>
    public void AdvanceAlong(double dist)
    {
        var loop = Map.Loop(Anchor.LoopId);
        if (loop is null || Anchor.SegIdx >= loop.Segs.Count) return;

        int segIdx = Anchor.SegIdx;
        double t = Anchor.T;
        int dir = WalkDir;
        int guard = 0;

        while (dist > 1e-9 && guard++ < 64)
        {
            var seg = loop.Segs[segIdx];
            double room = dir > 0 ? seg.Len - t : t;
            if (room > dist)
            {
                t += dir * dist;
                dist = 0;
                break;
            }
            dist -= room;
            t = dir > 0 ? seg.Len : 0;
            if (loop.Closed)
            {
                segIdx = dir > 0 ? (segIdx + 1) % loop.Segs.Count : (segIdx - 1 + loop.Segs.Count) % loop.Segs.Count;
                t = dir > 0 ? 0 : loop.Segs[segIdx].Len;
            }
            else
            {
                // At an open run's end it must turn back (or jump, in later stages).
                dir = -dir;
                WalkDir = dir;
                segIdx = dir > 0 ? (segIdx + 1) % loop.Segs.Count : (segIdx - 1 + loop.Segs.Count) % loop.Segs.Count;
                t = dir > 0 ? 0 : loop.Segs[segIdx].Len;
                if (loop.Segs.Count == 1) { t = dir > 0 ? 0 : seg.Len; }
            }
        }

        Anchor = new Anchor(Anchor.LoopId, segIdx, M.Clamp(t, 0, loop.Segs[segIdx].Len), dir);
    }

    // ---------------------------------------------------------------- frame

    /// <summary>
    /// One frame. The order is the spec's (4.1), so later stages slot in without churn.
    /// </summary>
    public void Update(double dt)
    {
        dt = Math.Min(dt, 1.0 / 30);
        Time += dt;

        UpdatePointer(dt);
        UpdateWatch(dt);
        UpdateActivity(dt);
        UpdateMemory(dt);
        UpdateSensing(dt);

        // Peek-a-boo runs on its own clock and holds the body at the edge (spec 9).
        if (Peek != PeekPhase.None)
        {
            UpdatePeek(dt);
            UpdateBodySprings(dt);
            UpdateBlink(dt);
            _lastPos = Pos;
            return;
        }

        // A crouch that has run its course launches the leap it was gathering for (spec 7.1).
        if (Mode == Mode.Attached && PendingJump is { } jump && Activity == Activity.Crouch
            && ActivityTime >= ActivityDur)
        {
            PendingJump = null;
            LaunchJump(jump);
        }

        switch (Mode)
        {
            case Mode.Attached: UpdateAttached(dt); break;
            case Mode.Held: UpdateHeld(dt); break;
            case Mode.Air: UpdateAir(dt); break;
            case Mode.Clinging: UpdateCling(dt); break;
            case Mode.Dangling: UpdateDangling(dt); break;
        }

        UpdateHeading(dt);
        UpdateBodySprings(dt);
        UpdateLandDrop(dt);
        UpdateHammock(dt);
        UpdatePrey(dt);
        UpdateWildlife(dt);
        UpdateToys(dt);
        UpdateTraces(dt);
        UpdateVisitors(dt);
        if (Mode == Mode.Held) UpdateHeldLegs();
        else if (Mode == Mode.Clinging) UpdateClingLegs();
        else if (Mode == Mode.Attached) UpdateLegs(dt);
        UpdateBlink(dt);

        Odometer += Speed * dt;
        if (Mode == Mode.Attached && Anchor.IsValid && !InHammock) { Pos = Map.Resolve(Anchor, CornerRadius * Scale).Pos; }
        _lastPos = Pos;
    }

    void UpdateActivity(double dt)
    {
        ActivityTime += dt;
        if (Activity != Activity.Walk && Activity != Activity.Sneak && Activity != Activity.Scurry)
            IdleFor += dt;
        else IdleFor = 0;
    }

    void UpdateAttached(double dt)
    {
        if (Cinema)
        {
            UpdateCinema(dt);
            return;
        }
        if (InHammock)
        {
            Pos = Hammock.Bed;
            Hammock.Load = 1;
            Speed = 0;
            TargetSpeed = 0;
            return;
        }
        if (PreyHunt == HuntStage.None && HandToy == ToyKind.None) UpdateBrain(dt);
        var posture = Posture.For(Activity, ActivityU, Design.Gait, Rng);

        // target speed = walkSpeed × posture × bout (spec 4.3)
        bool walking = posture.Speed > 0.001;
        TargetSpeed = walking ? WalkSpeed * posture.Speed * WalkSpeedScale : 0;

        // Speed approaches the target with an acceleration spring: gets going over a few steps,
        // stops short, leaning into starts and rocking forward on stops (spec 4.3 inertia).
        Speed = M.Approach(Speed, TargetSpeed, 7, dt);
        if (Math.Abs(Speed) < 0.4 && TargetSpeed == 0) Speed = 0;

        if (Speed > 1e-6)
        {
            V2 before = Pos;
            AdvanceAlong(Speed * dt);
            var sp = Map.Resolve(Anchor, CornerRadius * Scale);
            Heading = HeadingForAnchor(Anchor);
            Pos = sp.Pos;
            SurfaceMotion = Pos - _lastPos - (sp.Pos - before);
            if (SurfaceMotion.Length > 400) SurfaceMotion = V2.Zero;   // a different display: not a ride

            // A hand-off onto another surface (a window edge, the screen rim, the desk): the feet
            // ease from where they were to their places on the new one (spec 4.5.7).
            _lastLoop = Anchor.LoopId;
        }

        // posture targets drive the springs; nothing is ever assigned directly (spec 4.2)
        BobOffset = Bob();
        Lift.Step(posture.Lift, dt);
        Pitch.Step(posture.Pitch + BodyPitchExtra, dt);
        Crouch.Step(posture.Crouch, dt);
        Wag.Step(posture.Wag, dt);
        Lid.Step(posture.Lid, dt);

        UpdateCovered(dt);
    }

    /// <summary>The body bobs twice per gait cycle while walking (spec 4.5).</summary>
    double Bob()
    {
        if (Speed < 1) return 0;
        double amp = 0.9 * M.Clamp01(Speed / WalkSpeed);
        return amp * (0.5 - 0.5 * Math.Cos(4 * M.Pi * Gait.Cycle));
    }

    void UpdateHeading(double dt)
    {
        // In the air (and hanging off the pointer) the body pitches into the arc rather than following
        // a surface tangent (spec 7.1).
        if (Mode is Mode.Air or Mode.Clinging)
        {
            HeadingSpring.Value = M.WrapPi(HeadingSpring.Value
                + M.AngleDelta(HeadingSpring.Value, Heading) * (1 - Math.Exp(-18 * dt)));
            HeadingSpring.Velocity = 0;
            Facing = _airFacing;
            Yaw.Reset(_airFacing);
            return;
        }

        double soft = 1.0;
        if (Mode == Mode.Dangling) soft = 0.4;
        double err = M.AngleDelta(HeadingSpring.Value, Heading);
        HeadingSpring.Velocity += (err * 190 * soft - HeadingSpring.Velocity * 21 * Math.Sqrt(soft)) * dt;
        HeadingSpring.Value += HeadingSpring.Velocity * dt;
        // The body's drawn rotation is the surface heading plus the facing yaw's half-turn handled
        // by the renderer's mirror, so the spring value IS the surface heading.
        HeadingSpring.Value = M.WrapPi(HeadingSpring.Value);

        // Turning: facing follows walkDir through the front view (spec 4.7). Watching the pointer
        // the legs come round to it too, but only once it is well round (spec 5.5).
        double targetFacing = WalkDir >= 0 ? 1 : -1;
        if (Mode == Mode.Attached && Speed < 1 && Interest > 0.5)
            targetFacing = M.Clamp(InterestYawTarget, -1, 1);
        Yaw.Step(targetFacing, dt);
        Facing = Yaw.Value;
    }

    void UpdateBodySprings(double dt)
    {
        Happy.Step(0, dt);
        Startled.Step(0, dt);
        GroundedSpring.Step(Mode == Mode.Attached ? 1 : 0, dt);
        Stretch.Step(IsHeld ? 1.05 : 1, dt);
        double wantFatten = 1 / Math.Max(0.6, Stretch.Value);
        Fatten.Step(wantFatten, dt);
        NameTag.Step(PointerNameVisible ? 1 : 0, dt);
        Grasped.Step(IsHeld ? 1 : 0, dt);

        // head and abdomen have their own gently-lagging tilt (spec 4.7)
        AbdomenTilt = M.Approach(AbdomenTilt, -Pitch.Value * 0.7 - _interestNose.Value * 0.55, 8, dt);
        // The head turns to the pointer at once; the legs come round after it (spec 5.5).
        double headWanted = Mode == Mode.Attached && Interest > 0.5
            ? M.Clamp(HeadYawTarget - Yaw.Value, -0.6, 0.6) * Interest
            : 0;
        HeadTurn = M.Approach(HeadTurn, headWanted, 15, dt);
    }

    void UpdateLegs(double dt)
    {
        double profile = SpiderRig.ProfileAmount(Facing);
        bool walking = Speed > 1.0;

        // The body's full motion includes the lift bob: a planted foot stays put while the body
        // bobs over it, and the legs flex (spec 4.5). Without the lift term the feet bounce.
        // The compensation must use the DRAWN heading (the spring), not the target: at a corner the
        // target jumps by a right angle while the sprite is still turning, and mixing the two makes
        // planted feet appear to jump.
        double drawnHeading = HeadingSpring.Value;
        double dThetaDrawn = M.WrapPi(drawnHeading - _lastHeadingDrawn);
        _lastHeadingDrawn = drawnHeading;

        V2 motion = (Pos + OffsetWorld(BodyLift)) - (_lastPos + OffsetWorld(_lastLift));
        _lastLift = BodyLift;

        // A dragged window takes its planted feet with it (spec 4.4).
        if (SurfaceMotion.LengthSquared > 1e-12)
            for (int i = 0; i < 8; i++)
                if (Gait.Legs[i].HasWorld) Gait.Legs[i].LastWorldFoot += SurfaceMotion;

        double fs = Facing < 0 ? -1 : 1;
        V2 bodyOrigin = Pos + OffsetWorld(BodyLift);

        Gait.Update(Speed * dt, motion, dThetaDrawn, SurfaceMotion, bodyOrigin, drawnHeading, Facing,
            profile, Design.Look.Legs, default, Scale, walking, dt);

        // Keep every foot's world position current: steps and hand-offs are anchored in the world.
        // The gait is in body units, so the sprite scale belongs here, exactly as the renderer applies it.
        for (int i = 0; i < 8; i++)
        {
            ref var leg = ref Gait.Legs[i];
            V2 local = leg.Foot * Scale;
            if (fs < 0) local = new V2(-local.X, local.Y);
            leg.LastWorldFoot = bodyOrigin + local.Rotated(drawnHeading);
            leg.HasWorld = true;
        }
    }

    void UpdateBlink(double dt)
    {
        BlinkTimer -= dt;
        if (BlinkTimer <= 0)
        {
            Blink = 1;
            BlinkTimer = Rng.Range(2.2, 6.5);
        }
        Blink = M.Approach(Blink, 0, 14, dt);
    }

    // ---------------------------------------------------------------- activities

    public void Play(Activity a, double dur)
    {
        Activity = a;
        ActivityTime = 0;
        ActivityDur = Math.Max(0.05, dur);
    }

    /// <summary>Start walking in a direction along the surface.</summary>
    public void Walk(int dir = 0, double seconds = 3.0)
    {
        if (dir != 0 && dir != WalkDir) WalkDir = dir >= 0 ? 1 : -1;
        Play(Activity.Walk, seconds);
    }

    public void Stand()
    {
        // Deliberately does NOT zero the speed: it should rock forward as it stops (spec 4.3).
        Play(Activity.Idle, 1);
    }

    // ---------------------------------------------------------------- pose

    /// <summary>The complete drawable state for this frame (spec 3.5).</summary>
    public SpiderPose BuildPose()
    {
        double profile = SpiderRig.ProfileAmount(Facing);
        var pose = new SpiderPose
        {
            Pos = Pos,
            Lift = BodyLift - Crouch.Value * CrouchDrop,
            Heading = HeadingSpring.Value,
            Facing = M.Clamp(Facing, -1, 1),
            Scale = Scale,
            Grounded = GroundedSpring.Value,
            Stretch = Stretch.Value,
            Fatten = Fatten.Value,
            Blink = Math.Max(Blink, SlowBlinkNow),
            Happy = M.Clamp01(Happy.Value),
            Startled = M.Clamp01(Startled.Value),
            Grabbed = M.Clamp01(Grasped.Value),
            Emote = ThoughtShowing ? EmoteKind.Thought : Emote switch
            {
                PointerEmote.Hearts => EmoteKind.Heart,
                PointerEmote.Sparkle => EmoteKind.Sparkle,
                PointerEmote.Note => EmoteKind.Note,
                PointerEmote.Surprise => EmoteKind.Surprise,
                PointerEmote.Question => EmoteKind.Question,
                _ => EmoteKind.None
            },
            EmoteT = ThoughtShowing
                ? ThoughtT
                : M.Clamp01((Time - _emoteFrom) / Math.Max(EmoteUntil - _emoteFrom, 0.001)),
            EmoteClock = Time - _emoteFrom,
            Thought = CurrentThought,
            ThoughtText = CurrentThoughtText,
            Sleep = Activity == Activity.Sleep ? 1 : 0,
            AbdomenSway = Math.Sin(Time * (6 + Wag.Value * 4)) * Wag.Value,
            Time = Time,
            Name = string.IsNullOrEmpty(Design.Name) ? null : Design.Name,
            NameTag = NameTag.Value,
            Odometer = Odometer,
            BodyPitch = Pitch.Value,
            Look = Look,
            HeadTilt = Pitch.Value * 0.85 + NodNow + _interestNose.Value * 0.6,
            AbdomenTilt = AbdomenTilt,
            HeadTurn = HeadTurn + ShakeNow,
            Chew = Activity == Activity.Eat ? 0.5 + 0.5 * Math.Sin(Time * 18) : 0,
            Lid = Lid.Value
        };

        for (int i = 0; i < 8; i++)
        {
            pose.Legs[i] = new LegPose(
                SpiderRig.Rig(i, profile, Design.Look.Legs).Hip,
                Gait.KneeFor(i, profile, Design.Look.Legs, default),
                Gait.Legs[i].Foot,
                Gait.Legs[i].Lift);
        }

        if (Peek != PeekPhase.None)
        {
            if (_peekHidden) pose.HiddenBy.Add(PeekRect);
            pose.PeekGrip.Add(PeekEdge + new V2(_peekSide * 2, 4 * Scale));
            pose.PeekGrip.Add(PeekEdge + new V2(_peekSide * 2, -4 * Scale));
        }
        return pose;
    }

    /// <summary>Where a foot actually is in the world — the no-slide check uses this.</summary>
    public V2 WorldFoot(int i)
    {
        if (Gait.Legs[i].HasWorld) return Gait.Legs[i].LastWorldFoot;
        var local = Gait.Legs[i].Foot * Scale;
        double facing = Facing < 0 ? -1 : 1;
        V2 mirrored = new(local.X * facing, local.Y);
        return Pos + OffsetWorld(_lastLift) + Rotate(mirrored, HeadingSpring.Value);
    }

    static V2 Rotate(V2 v, double a) => new(v.X * Math.Cos(a) - v.Y * Math.Sin(a), v.X * Math.Sin(a) + v.Y * Math.Cos(a));

    /// <summary>A body-local offset converted into world space at the current heading.</summary>
    V2 OffsetWorld(double lift) => Rotate(new V2(0, lift), HeadingSpring.Value);

    /// <summary>A pick-up test: is the pointer within grabRadius of the body? (spec 3.1)</summary>
    public bool HitTest(V2 p) => ClickToPickUp && Mode != Mode.Clinging
        && p.DistanceTo(Pos) <= GrabRadius * Scale + 1e-9;
}
