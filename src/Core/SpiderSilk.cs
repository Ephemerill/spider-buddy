namespace SpiderBuddy.Core;

public enum WebStyle { Hang, Swing }
public enum WebPlanKind { Descend, Linger, ClimbHome, ToFloor, Swing, JumpOff, SwingOff }

public struct WebPlanStep
{
    public WebPlanKind Kind;
    public double Length;
    public double Seconds;
    public double Remaining;
    public static WebPlanStep Descend(double len) => new() { Kind = WebPlanKind.Descend, Length = len };
    public static WebPlanStep Linger(double sec) => new() { Kind = WebPlanKind.Linger, Seconds = sec, Remaining = sec };
    public static WebPlanStep Plan(WebPlanKind kind, double len = 0) => new() { Kind = kind, Length = len };
}

public enum HammockStyle { Sling, Pouch, Tangle, Cradle }

/// <summary>The hammock model of spec 8.8: four styles, strands that drape over 2.4 s, a bed under load.</summary>
public sealed class Hammock
{
    public bool Exists;
    public bool Finished;
    public HammockStyle Style = HammockStyle.Sling;
    public Rect Box;
    public bool Left = true;
    public double Progress;
    public double Damage;
    public double Load;
    public double LoadU = 0.5;
    public double Sway;
    public double Drop;
    public readonly double[] Drape = new double[13];

    public static (double sagShare, int strands, double give) Info(HammockStyle s) => s switch
    {
        HammockStyle.Sling => (0.42, 7, 10),
        HammockStyle.Pouch => (0.66, 9, 16),
        HammockStyle.Tangle => (0.50, 6, 8),
        _ => (0.34, 6, 12),
    };

    public V2 WallAnchor => new(Left ? Box.MinX + 2 : Box.MaxX - 2, Box.MaxY - Box.H * 0.62);
    public V2 CeilAnchor => new(Left ? Box.MaxX - 4 : Box.MinX + 4, Box.MaxY - 2);
    public double Sag => Box.H * Info(Style).sagShare;
    public int Strands => Info(Style).strands;

    /// <summary>The centre line: a quadratic from the wall anchor to the ceiling anchor.</summary>
    public V2 PointAt(double u)
    {
        u = M.Clamp01(u);
        V2 a = WallAnchor, b = CeilAnchor;
        V2 c = (a + b) * 0.5 + new V2(0, -(Sag + Drop + Load * Info(Style).give) * 2);
        double mu = 1 - u;
        V2 p = a * (mu * mu) + c * (2 * mu * u) + b * (u * u);
        double bell = M.Smoothstep(1 - Math.Abs(u - M.Clamp(LoadU, 0.15, 0.85)) / 0.32);
        p.Y -= Load * Info(Style).give * 1.6 * bell * 0.6;
        p += new V2(Sway, Math.Abs(Sway) * 0.12) * Math.Sin(Math.PI * u);
        return p;
    }

    public V2 Bed => PointAt(M.Clamp(LoadU, 0.15, 0.85));

    /// <summary>0 below 0.1, 1 up to 0.30, then one every completed stretch (spec 8.8).</summary>
    public int StrandsLaid
    {
        get
        {
            if (Progress < 0.1) return 0;
            if (Progress <= 0.30) return 1;
            return 1 + (int)Math.Floor(M.Remap(Progress, 0.36, 0.88, 0, Strands - 1));
        }
    }

    public void Update(double dt)
    {
        for (int i = 0; i < Drape.Length; i++)
            if (Drape[i] < 1) Drape[i] = Math.Min(1, Drape[i] + dt / 2.4);
        Sway *= Math.Exp(-1.6 * dt);
        Drop = M.Approach(Drop, Load * Info(Style).give * 0.4, 6, dt);
        if (Damage >= 1) Clear();
    }

    public void Wipe(double movement)
    {
        if (!Exists) return;
        // A half-made hammock goes with a single good swipe; a finished one takes a couple.
        if (!Finished) { Clear(); return; }
        Damage = Math.Min(1, Damage + movement / 140.0);
        if (Damage >= 1) Clear();
    }

    void Clear()
    {
        Exists = false;
        Finished = false;
        Progress = 0;
        Damage = 0;
        Load = 0;
        Invalidate();
    }

    void Invalidate() { }
}

/// <summary>
/// Stage 8 — silk. One line state (spec 8.1), pendulum physics, plans, paying out and hauling in,
/// mantle, scroll orders, rescue catches and the hammock.
/// </summary>
public sealed partial class Spider
{
    public bool WebsEnabled = true;
    public bool WebActive;
    public V2 WebAnchor;
    public double WebLen = 60, WebLenTarget = 60;
    public double WebAngle, WebAngleVel;
    public WebStyle WebStyle;
    public readonly List<WebPlanStep> WebPlan = new();
    public PointerLineOrder? LineOrder;
    public double LineTop, FloorLen;
    public readonly SilkRope Rope = new();
    public double WebShootT;
    public bool WebSlingshot;
    public bool InHammock;
    public readonly Hammock Hammock = new();

    public bool IsOnLine => Mode == Mode.Dangling;

    /// <summary>Fire a line at the ceiling above and hang from it (spec 8.3).</summary>
    public bool DropOnWeb(double? length = null, WebStyle style = WebStyle.Hang)
    {
        if (!WebsEnabled) return false;
        if (Cinema) return false;
        var ceiling = Map.Ceiling(Pos, 1200);
        if (!ceiling.Found) return false;

        WebActive = true;
        WebStyle = style;
        WebAnchor = ceiling.Point;
        LineTop = ceiling.Point.Y;
        double below = Map.LandingBelow(WebAnchor, 30 * Scale);
        FloorLen = double.IsNaN(below) ? 400 * Scale : Math.Max(40, WebAnchor.Y - below - 8 * Scale);

        V2 r = Pos - WebAnchor;
        WebLen = Math.Max(24, r.Length);
        WebAngle = Math.Atan2(r.X, -r.Y);
        WebAngleVel = 0;
        WebLenTarget = length ?? WebLen;
        Mode = Mode.Dangling;
        Air = AirKind.Rappel;
        Velocity = V2.Zero;
        NoAttachFor = 0.2;
        RescueLineRequested = false;
        LineOrder = null;
        Rope.Reset(WebAnchor, Pos);

        WebPlan.Clear();
        if (length is null)
        {
            double drop = M.Clamp(Math.Abs(WebAnchor.Y - Pos.Y) * 0.35, 50, 400 * Scale);
            WebPlan.Add(WebPlanStep.Descend(WebLen + drop));
            WebPlan.Add(WebPlanStep.Linger(Rng.Range(4, 9)));
            WebPlan.Add(WebPlanStep.Plan(WebPlanKind.ClimbHome));
        }
        Play(Activity.Rappel, 1.0);
        return true;
    }

    /// <summary>A line caught on the way down (spec 7.1/8.3).</summary>
    public bool CatchRescueLine()
    {
        if (!WebsEnabled) return false;
        var ceiling = Map.Ceiling(Pos, 1200);
        if (!ceiling.Found) return false;

        WebActive = true;
        WebStyle = WebStyle.Hang;
        WebAnchor = ceiling.Point;
        V2 r = Pos - WebAnchor;
        WebLen = Math.Max(24, r.Length);
        WebLenTarget = WebLen;
        WebAngle = Math.Atan2(r.X, -r.Y);
        WebAngleVel = r.Length > 1 ? Velocity.Dot(new V2(-r.Y, r.X).Normalized) / WebLen : 0;
        Mode = Mode.Dangling;
        Air = AirKind.Rappel;
        Velocity = V2.Zero;
        RescueLineRequested = false;
        LineOrder = null;
        Rope.Reset(WebAnchor, Pos);
        WebPlan.Clear();
        WebPlan.Add(WebPlanStep.Linger(1.2));
        WebPlan.Add(WebPlanStep.Plan(WebPlanKind.ClimbHome));
        Play(Activity.Rappel, 0.8);
        return true;
    }

    /// <summary>A frame on the thread: pendulum, pay out, follow the plan (spec 8.2/8.6).</summary>
    void UpdateDangling(double dt)
    {
        WebShootT += dt;

        // An order from a scroll overrides the plan, at once and once.
        if (LineOrder is { } order)
        {
            LineOrder = null;
            WebPlan.Clear();
            WebPlan.Add(WebPlanStep.Plan(order == PointerLineOrder.Up ? WebPlanKind.ClimbHome : WebPlanKind.ToFloor));
        }

        double g = Gravity;
        double len = Math.Max(WebLen, 12);
        double acc = -(g / len) * Math.Sin(WebAngle) - 1.15 * WebAngleVel;
        WebAngleVel += acc * dt;
        WebAngle += WebAngleVel * dt;
        if (Math.Abs(WebAngle) > 1.35) { WebAngle = M.Clamp(WebAngle, -1.35, 1.35); WebAngleVel *= -0.35; }

        WebLen = M.Approach(WebLen, WebLenTarget, 2.4, dt);

        V2 r = new(Math.Sin(WebAngle) * WebLen, -Math.Cos(WebAngle) * WebLen);
        Pos = WebAnchor + r;
        Heading = M.Clamp(WebAngle, -0.6, 0.6);
        _airFacing = WebAngle >= 0 ? 1 : -1;

        Rope.HeadPinned = true;
        Rope.TailPinned = true;
        Rope.Step(WebAnchor, Pos, g, 0.5, 0, dt);

        if (WebPlan.Count == 0) return;
        var step = WebPlan[0];
        bool done = false;
        switch (step.Kind)
        {
            case WebPlanKind.Descend:
                WebLenTarget = step.Length;
                done = Math.Abs(WebLen - step.Length) < 2.5;
                break;
            case WebPlanKind.Linger:
                step.Remaining -= dt;
                WebPlan[0] = step;
                done = step.Remaining <= 0;
                break;
            case WebPlanKind.ClimbHome:
                WebLenTarget = 24 * Math.Max(0.6, Scale);
                if (WebLen < 26 * Math.Max(0.6, Scale)) { MantleUp(); return; }
                break;
            case WebPlanKind.ToFloor:
                WebLenTarget = Math.Max(24, FloorLen);
                if (WebLen >= FloorLen - 6) { StepOffLine(); return; }
                break;
            case WebPlanKind.Swing:
                // Pump: drive it the way it is already moving, pass after pass, until the arc is big.
                if (Math.Abs(WebAngleVel) < 3.0)
                {
                    double dir = Math.Abs(WebAngleVel) < 0.05
                        ? Math.Sign(WebAngle == 0 ? 1 : WebAngle)
                        : Math.Sign(WebAngleVel);
                    WebAngleVel += dir * dt * 4.2;
                }
                if (Math.Abs(WebAngleVel) >= 2.6 && Math.Abs(WebAngle) > 0.55) { ReleaseSwing(); return; }
                break;
            case WebPlanKind.JumpOff:
                ReleaseSwing();
                return;
            case WebPlanKind.SwingOff:
                WebLenTarget = step.Length;
                if (Math.Abs(WebLen - step.Length) < 4) { ReleaseSwing(); return; }
                break;
        }
        if (done) WebPlan.RemoveAt(0);
    }

    /// <summary>Haul up onto whatever the line hangs from (spec 8.5).</summary>
    public bool MantleUp()
    {
        var spot = Map.NearestSpot(WebAnchor, 70 * Scale, null, Scale);
        if (spot is not { } target) return false;
        WebActive = false;
        WebPlan.Clear();
        Mode = Mode.Air;
        Air = AirKind.Mantle;
        Pos = target.Point + new V2(0, 6 * Scale);
        Velocity = new V2(0, 40);
        NoAttachFor = 0.12;
        _airFacing = 1;
        return true;
    }

    public bool StepOffLine()
    {
        var spot = Map.NearestSpot(Pos + new V2(0, -4), 44 * Scale, null, Scale);
        WebActive = false;
        WebPlan.Clear();
        if (spot is { } target) { LandOn(target); return true; }
        Mode = Mode.Air;
        Air = AirKind.Fall;
        NoAttachFor = 0.1;
        return false;
    }

    /// <summary>Let go near the top of a swing and fly (spec 8.7).</summary>
    public void ReleaseSwing()
    {
        if (!WebActive) return;
        V2 tangent = new V2(Math.Cos(WebAngle), Math.Sin(WebAngle)) * WebAngleVel * WebLen;
        if (LeaveTraces && Rng.Chance(TraceSwingChance)) AddStrand(WebAnchor, Pos);
        WebActive = false;
        WebPlan.Clear();
        Mode = Mode.Air;
        Air = AirKind.Swing;
        AirTime = 0;
        Velocity = tangent + new V2(0, 120);
        NoAttachFor = 0.12;
        _airFacing = Velocity.X >= 0 ? 1 : -1;
        Play(Activity.Pounce, 0.4);
    }

    /// <summary>Start swinging on the line it is already on (spec 8.7).</summary>
    public void StartSwing()
    {
        if (!IsOnLine) return;
        if (Cinema) return;
        if (Confined) return;
        WebStyle = WebStyle.Swing;
        WebPlan.Clear();
        WebPlan.Add(WebPlanStep.Plan(WebPlanKind.Swing));
        Play(Activity.Swing, 6);
    }

    /// <summary>Scroll orders are obeyed without reversing (spec 8.5).</summary>
    public void ObeyScroll(PointerLineOrder order)
    {
        if (Mode == Mode.Dangling) { LineOrder = order; return; }
        if (Mode == Mode.Attached && order == PointerLineOrder.Down && WebsEnabled) DropOnWeb();
    }

    // ------------------------------------------------------------------ hammock

    public bool BuildHammock(HammockStyle? style = null)
    {
        if (Cinema) return false;
        if (Confined) return false;
        if (Hammock.Exists && Hammock.Finished) return false;
        var loop = Map.Loop(Anchor.LoopId);
        Rect rect = loop?.Rect is { IsValid: true } r ? r : Map.BoundsAround(Pos);
        Hammock.Exists = true;
        Hammock.Finished = false;
        Hammock.Progress = Math.Max(Hammock.Progress, 0.02);
        Hammock.Style = style ?? (HammockStyle)Rng.WeightedIndex(new double[] { 1, 1, 1, 1 });
        Hammock.Box = rect;
        Hammock.Left = Rng.Chance(0.5);
        Hammock.Damage = 0;
        Play(Activity.Build, 12);
        return true;
    }

    public bool NapInHammock()
    {
        if (!Hammock.Exists || !Hammock.Finished) return false;
        InHammock = true;
        Pos = Hammock.Bed;
        Hammock.Load = 1;
        Play(Activity.Sleep, Rng.Range(40, 120));
        return true;
    }

    public void LeaveHammock()
    {
        if (!InHammock) return;
        InHammock = false;
        Hammock.Load = 0;
        Pos = Hammock.WallAnchor;
        Play(Activity.Stretch, 1.2);
    }

    public void WipeHammock(V2 at, double movement)
    {
        if (!Hammock.Exists) return;
        if (at.DistanceTo(Hammock.Bed) > 40 * Scale && at.DistanceTo(Pos) > 40 * Scale) return;
        Hammock.Wipe(movement);
        if (InHammock && (Hammock.Damage > 0.3 || !Hammock.Exists)) LeaveHammock();
    }

    void UpdateHammock(double dt)
    {
        Hammock.Update(dt);
        if (Hammock.Exists && Activity == Activity.Build)
        {
            int was = Hammock.StrandsLaid;
            Hammock.Progress = Math.Min(1, Hammock.Progress + dt / 12);
            if (Hammock.StrandsLaid != was) Hammock.Sway += 0.25;
            if (Hammock.Progress >= 1) { Hammock.Finished = true; Hammock.Damage = 0; }
        }
        if (InHammock)
        {
            Pos = Hammock.Bed;
            Hammock.Load = 1;
        }
    }
}
