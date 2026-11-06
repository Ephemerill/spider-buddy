using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

public static class Stage7
{
    static Spot Pick(Rng r, List<Spot> spots) => spots[Math.Min(spots.Count - 1, (int)r.Range(0, spots.Count))];

    static (SurfaceMap map, Spider s) Scene(double scale = 0.78)
    {
        var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26));
        var map = Synth.Build(desk, scale);
        var s = new Spider(Sheets.DefaultDesign(), map, new Rng(21)) { UserScale = scale, BrainEnabled = false };
        return (map, s);
    }

    static void ArcChecks()
    {
        var (map, s) = Scene();
        var spots = map.SampleSpots(40, true, 0.78);
        var rng = new Rng(31);
        int launched = 0, landedOk = 0, throughSurface = 0;
        double worst = 0;
        string detail = "";
        for (int trial = 0; trial < 1000; trial++)
        {
            var a = Pick(rng, spots);
            var b = Pick(rng, spots);
            if (a.Point.DistanceTo(b.Point) < 70) continue;
            s.SetAnchor(a.LoopId, a.SegIdx, a.Anchor.T, 1);
            s.Mode = Mode.Attached;
            s.AirTime = 0;
            s.Velocity = V2.Zero;
            s.NoAttachFor = 0;
            if (!s.StartJump(b.Point)) continue;
            bool flew = false;
            for (int i = 0; i < 360; i++)
            {
                s.Update(1.0 / 60);
                if (s.Mode == Mode.Air) flew = true;
                if (flew && s.Mode == Mode.Attached) break;
            }
            if (!flew || s.Mode != Mode.Attached) continue;
            launched++;
            double err = s.Pos.DistanceTo(b.Point);
            if (err > 12 && detail.Length < 240)
                detail += $" [{a.Point}->{b.Point} landed {s.Pos} err {err:0.0}]";
            worst = Math.Max(worst, err);
            if (err <= 12) landedOk++;
            var seg = map.Loop(a.LoopId)?.SegAt(a.SegIdx);
            if (seg is not null && s.Air == AirKind.Leap) throughSurface++;
        }
        Harness.Check(launched >= 60, "enough leaps were actually in range", $"{launched}");
        double rate = landedOk / (double)Math.Max(1, launched);
        Harness.Check(rate >= 0.95, "95% of random leaps land on the mark (±12 units)",
            $"{rate:P1} of {launched}, worst {worst:0.0}{detail}");
    }

    static void ThroughSurfaceChecks()
    {
        var (map, s) = Scene();
        var spots = map.SampleSpots(40, true, 0.78);
        var rng = new Rng(41);
        bool through = false;
        string worstDot = "";
        double lowest = 0;
        int checkedLaunches = 0;
        for (int trial = 0; trial < 200 && checkedLaunches < 40; trial++)
        {
            var a = Pick(rng, spots);
            var b = Pick(rng, spots);
            s.SetAnchor(a.LoopId, a.SegIdx, a.Anchor.T, 1);
            s.Mode = Mode.Attached;
            s.AirTime = 0;
            s.Velocity = V2.Zero;
            s.NoAttachFor = 0;
            if (!s.StartJump(b.Point)) continue;
            for (int i = 0; i < 40 && s.Mode == Mode.Attached; i++) s.Update(1.0 / 60);
            if (s.Mode != Mode.Air || s.Air != AirKind.Leap) continue;
            checkedLaunches++;
            var seg = map.Loop(a.LoopId)?.SegAt(a.SegIdx);
            if (seg is not null && s.LaunchVelocity.Dot(seg.Normal) < -0.2)
            {
                through = true;
                if (s.LaunchVelocity.Dot(seg.Normal) < lowest)
                {
                    lowest = s.LaunchVelocity.Dot(seg.Normal);
                    worstDot = $"{a.LoopId}#{a.SegIdx} n{seg.Normal} v{s.LaunchVelocity} dot {lowest:0.00}";
                }
            }
        }
        Harness.Check(checkedLaunches > 10, "launches were inspected", $"{checkedLaunches}");
        Harness.Check(!through, "no leap starts through its own surface", worstDot);

        // A target beyond reach is refused outright, not flown short.
        var far = s.Pos + new V2(6000, 5000);
        Harness.Check(!s.StartJump(far), "a leap out of range is refused, never flown short");
    }

    static void BounceChecks()
    {
        var (map, s) = Scene();
        var screen = map.ScreenFrameContaining(new V2(0, 0))!;
        s.Mode = Mode.Air;
        s.Air = AirKind.Thrown;
        s.Pos = new V2(screen.Frame.MaxX - 40, screen.Frame.Mid.Y);
        s.Velocity = new V2(1600, 0);
        s.NoAttachFor = 10;
        bool bounced = false;
        for (int i = 0; i < 60; i++)
        {
            s.Update(1.0 / 60);
            bounced |= s.Bounced;
        }
        Harness.Check(bounced, "a hard throw bounces off the screen edge");
        Harness.Check(s.Pos.X <= screen.Frame.MaxX + 1e-6, "and never leaves the screen");
        Harness.Check(map.IsOnScreen(s.Pos, 2), "the thrown body stays on the desktop");

        // Every edge and corner: never lost.
        foreach (var dir in new[] { new V2(1, 0), new V2(-1, 0), new V2(0, 1), new V2(0, -1),
                                    new V2(1, 1).Normalized, new V2(-1, -1).Normalized })
        {
            var t = new Spider(Sheets.DefaultDesign(), map, new Rng(51)) { UserScale = 0.78, BrainEnabled = false };
            t.SetAnchor("win:1", 0, 300, 1);
            t.Mode = Mode.Air;
            t.Air = AirKind.Thrown;
            t.Pos = new V2(screen.Frame.Mid.X, screen.Frame.Mid.Y);
            t.Velocity = dir * 2700;
            t.NoAttachFor = 10;
            for (int i = 0; i < 300; i++) t.Update(1.0 / 60);
            Harness.Check(map.IsOnScreen(t.Pos, 2), $"thrown at {dir}: still on the desktop");
        }

        // Bring to the Middle always recovers, even from far outside.
        var lost = new Spider(Sheets.DefaultDesign(), map, new Rng(52)) { UserScale = 0.78, BrainEnabled = false };
        lost.Mode = Mode.Air;
        lost.Pos = new V2(-9000, -9000);
        lost.Velocity = new V2(0, -800);
        lost.Update(1.0 / 60);
        Harness.Check(lost.BringToMiddle(), "Bring to the Middle finds it a perch");
        Harness.Check(lost.Mode == Mode.Attached && map.IsOnScreen(lost.Pos, 2), "and puts it back on the desktop");
    }

    static void LandingChecks()
    {
        var (map, s) = Scene();
        s.SetAnchor("win:1", 0, 40, 1);
        s.DetachAndFall();
        Harness.Check(s.Mode == Mode.Air, "a drop enters the air");
        for (int i = 0; i < 240 && s.Mode != Mode.Attached; i++) s.Update(1.0 / 60);
        Harness.Check(s.Mode == Mode.Attached, "a fall lands on what is below");
        Harness.Check(s.LandDrop || s.Time - s.LandedAt < 1, "the landing gives on its legs");
        for (int i = 0; i < 60; i++) s.Update(1.0 / 60);
        Harness.Check(!s.LandDrop, "the landing settles");

        // noAttachFor stops an instant re-grab after a throw.
        var n = new Spider(Sheets.DefaultDesign(), map, new Rng(61)) { UserScale = 0.78, BrainEnabled = false };
        n.SetAnchor("win:1", 0, 40, 1);
        n.BeginGrab(n.Pos);
        n.EndGrab(new V2(300, 400));
        double t0 = n.NoAttachFor;
        Harness.Check(t0 > 0, "a release forbids an immediate grab");
        n.Update(1.0 / 60);
        Harness.Check(n.Mode == Mode.Air, "and it is still in the air one frame later");
    }

    static void CoveredChecks()
    {
        var back = Synth.Desktop().With(Synth.Window(1, 300, 300, 800, 500, 1, "back", corner: 8));
        var map = Synth.Build(back, 0.78);
        var s = new Spider(Sheets.DefaultDesign(), map, new Rng(71)) { UserScale = 0.78, BrainEnabled = false };
        s.SetAnchor("win:1", 0, 200, 1);
        Harness.Check(s.Mode == Mode.Attached, "standing on the back window");
        var covered = back.With(Synth.Window(2, 100, 200, 1300, 700, 0, "front", corner: 8));
        s.SetMap(Synth.Build(covered, 0.78));
        for (int i = 0; i < 12 && s.Mode == Mode.Attached; i++) s.Update(1.0 / 60);
        Harness.Check(s.Mode != Mode.Attached, "a window over it puts it out from under within two polls");
        Harness.Check(s.Mode == Mode.Air || map.IsOnScreen(s.Pos, 2), "and it does not perch on the glass");
    }

    static void TumbleChecks()
    {
        var (map, s) = Scene();
        s.Mode = Mode.Air;
        s.Air = AirKind.Thrown;
        s.TumbleVel = 3;
        s.NoAttachFor = 10;
        s.Pos = new V2(900, 1040);
        s.Velocity = new V2(0, 500);
        for (int i = 0; i < 50; i++) s.Update(1.0 / 60);
        Harness.Check(Math.Abs(s.TumbleVel) < 2.0 && Math.Abs(s.TumbleVel) > 0.05,
            "a tumble slows and rights itself", $"{s.TumbleVel:0.00} {s.Mode}");
    }

    public static int Run(string[] args)
    {
        Harness.Section("stage 7 air: leaps, falling, throws, landing");
        ArcChecks();
        ThroughSurfaceChecks();
        BounceChecks();
        LandingChecks();
        CoveredChecks();
        TumbleChecks();
        return Harness.Summarise("stage 7 air");
    }
}
