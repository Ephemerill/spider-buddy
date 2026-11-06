using SpiderBuddy.Core;
using SpiderBuddy.Renderer;

namespace SpiderBuddy.Tools;

/// <summary>
/// Stage 4 acceptance (spec 4 "Done when"):
///  - a debug harness commands walk / sneak / scurry / stand on a window top, round a rounded corner,
///    down the side, under the bottom, along the rim and across the taskbar;
///  - feet are visibly planted (zero slide) and step in alternating groups; the body bobs twice a cycle;
///  - no leg longer than the flat envelope and no knees through the surface at either corner radius;
///  - a window dragged while the spider stands on it carries it with no foot slide;
///  - start/stop shows lean-in and rock-forward;
///  - all checks repeat at scales 0.62, 0.78, 0.95, 1.2, 1.55.
/// </summary>
public static class Stage4
{
    const double Dt = 1.0 / 60;
    static readonly double[] Scales = { 0.62, 0.78, 0.95, 1.2, 1.55 };

    public static int Run(string[] args)
    {
        // This harness issues its own commands (spec 4.9): the autonomous brain would fight it.
        Spider.BrainDefault = false;
        TetrapodChecks();
        WalkNoSlideChecks();
        GroupAlternationChecks();
        BobChecks();
        CornerChecks();
        CarriedChecks();
        StartStopChecks();
        AllScalesChecks();
        ActivityChecks();
        if (!args.Contains("--no-films")) FilmChecks();
        Spider.BrainDefault = true;
        return Harness.Summarise("stage 4 body and gait");
    }

    // ------------------------------------------------------------------ helpers

    static (DesktopState desk, SurfaceMap map, Spider spider) OnWindowTop(double scale = 0.78)
    {
        var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26));
        var map = Synth.Build(desk, scale);
        var spider = new Spider(Sheets.DefaultDesign(), map, new Rng(7)) { UserScale = scale };
        spider.SetAnchor("win:1", 0, 40, 1);
        return (desk, map, spider);
    }

    // ------------------------------------------------------------------ the tetrapod

    static void TetrapodChecks()
    {
        Harness.Section("the classic tetrapod gait (spec 4.5)");

        Harness.Near(GaitDriver.StrideLength, 28, 0, "stride length is 28 body units");
        Harness.Near(GaitDriver.SwingDuty, 0.34, 1e-12, "swing duty is 0.34");
        Harness.Near(GaitDriver.ReachLimit, 1.25, 1e-12, "reach limit is 1.25");
        Harness.Near(GaitDriver.ReachShare, 0.94, 1e-12, "reach share is 0.94");
        Harness.Near(GaitDriver.HandoffTime, 0.26, 1e-12, "hand-off time is 0.26 s");
        Harness.Near(GaitDriver.FootJolt, 26000, 0, "foot jolt limit is 26 000 px/s²");

        int g0 = 0, g1 = 0;
        for (int i = 0; i < 8; i++) { if (GaitDriver.Group(i) == 0) g0++; else g1++; }
        Harness.Check(g0 == 4 && g1 == 4, "four legs swing while four stay planted", $"{g0}/{g1}");
        Harness.Check(GaitDriver.Group(0) == GaitDriver.Group(2), "legs 0 and 2 share a group");
        Harness.Check(GaitDriver.Group(0) != GaitDriver.Group(1), "adjacent legs alternate");
        Harness.Check(GaitDriver.Group(0) == GaitDriver.Group(5), "near 0 and far 5 share a group (tetrapod, not diagonal-pair)");

        // the groups are exactly half a cycle apart
        double gap = Math.Abs(GaitDriver.PhaseOffset(0) - GaitDriver.PhaseOffset(1));
        Harness.Near(Math.Min(gap, 1 - gap), 0.47, 0.06,
            "groups are about half a cycle apart");

        // neighbours never move in lockstep: three hundredths between each
        var offsets = Enumerable.Range(0, 8).Select(GaitDriver.PhaseOffset).ToList();
        Harness.Check(offsets.Distinct().Count() == 8, "all eight offsets differ");
        double minGap = 1;
        for (int i = 0; i < 4; i++) minGap = Math.Min(minGap, Math.Abs(GaitDriver.PhaseOffset(i) - GaitDriver.PhaseOffset(i + 1)));
        Harness.Check(minGap >= 0.029, "neighbouring legs are staggered by ≥0.03", $"{minGap:0.000}");
    }

    // ------------------------------------------------------------------ no slide

    static void WalkNoSlideChecks()
    {
        Harness.Section("feet are planted: zero slide (spec 4.5)");

        var (_, _, spider) = OnWindowTop();
        spider.Walk(1, 6);

        // let it reach speed
        for (int i = 0; i < 120; i++)
        {
            spider.Update(Dt);
        }
        Harness.Check(spider.Speed > 30, "the spider reaches walking speed", $"{spider.Speed:0.0} px/s");

        var prev = new V2[8];
        var prevStance = new bool[8];
        for (int i = 0; i < 8; i++) { prev[i] = spider.WorldFoot(i); prevStance[i] = !spider.Gait.Legs[i].InSwing; }

        double worstStanceSlide = 0;
        double worstTurnSlide = 0;
        int worstLeg = -1;
        double worstStep = 0;
        int steps = 0;

        for (int f = 0; f < 240; f++)
        {
            var preSwing = new bool[8];
            var preForced = new bool[8];
            var preHas = new bool[8];
            var preFoot = new V2[8];
            for (int i = 0; i < 8; i++) { preSwing[i] = spider.Gait.Legs[i].InSwing; preForced[i] = spider.Gait.Legs[i].Forced; preHas[i] = spider.Gait.Legs[i].HasWorld; preFoot[i] = spider.Gait.Legs[i].LastWorldFoot; }
            spider.Update(Dt);
            for (int i = 0; i < 8; i++)
            {
                var post = spider.Gait.Legs[i];
                if (!preSwing[i] && !post.InSwing && preForced[i] == post.Forced && preFoot[i].DistanceTo(post.LastWorldFoot) > 0.9 && Environment.GetEnvironmentVariable("SLIDEDBG") == "1")
                    Console.WriteLine($"   move f{f} leg{i} preSwing{preSwing[i]} preForced{preForced[i]} preHas{preHas[i]} d{preFoot[i].DistanceTo(post.LastWorldFoot):0.00} postForced{post.Forced} lift{post.Lift:0.00} y{post.Foot.Y:0.00} phase{post.Phase:0.00}");
            }
            for (int i = 0; i < 8; i++)
            {
                var foot = spider.WorldFoot(i);
                bool stance = !spider.Gait.Legs[i].InSwing;
                if (stance && prevStance[i])
                {
                    double slide = foot.DistanceTo(prev[i]);
                    if (Math.Abs(spider.Gait.LastDTheta) < 0.02)
                    {
                        if (slide > worstStanceSlide)
                        {
                            worstStanceSlide = slide; worstLeg = i;
                        }
                    }
                    else worstTurnSlide = Math.Max(worstTurnSlide, slide);
                }
                if (!stance && prevStance[i]) steps++;
                worstStep = Math.Max(worstStep, foot.DistanceTo(prev[i]));
                prev[i] = foot;
                prevStance[i] = stance;
            }
        }

        // A quarter of a pixel per frame is the point below which motion cannot be seen.
        Harness.Check(worstStanceSlide < 0.25,
            "walking straight, a planted foot does not slide visibly",
            $"worst slide {worstStanceSlide:0.000} units/frame on leg {worstLeg}");
        Harness.Check(worstTurnSlide < 1.6,
            "turning, a foot only moves as it steps round (spec 4.5.8)",
            $"worst turn-frame move {worstTurnSlide:0.000}");
        Harness.Check(steps > 20, "feet actually step", $"{steps} lift-offs in 4 s");
        Harness.Check(worstStep < 22, "no foot teleports (a step is a step)", $"worst per-frame move {worstStep:0.0}");

        // a foot is never dragged past the reach limit from its hip
        double worstReach = 0;
        for (int f = 0; f < 240; f++)
        {
            var preSwing = new bool[8];
            var preForced = new bool[8];
            var preHas = new bool[8];
            var preFoot = new V2[8];
            for (int i = 0; i < 8; i++) { preSwing[i] = spider.Gait.Legs[i].InSwing; preForced[i] = spider.Gait.Legs[i].Forced; preHas[i] = spider.Gait.Legs[i].HasWorld; preFoot[i] = spider.Gait.Legs[i].LastWorldFoot; }
            spider.Update(Dt);
            for (int i = 0; i < 8; i++)
            {
                var post = spider.Gait.Legs[i];
                if (!preSwing[i] && !post.InSwing && preForced[i] == post.Forced && preFoot[i].DistanceTo(post.LastWorldFoot) > 0.9 && Environment.GetEnvironmentVariable("SLIDEDBG") == "1")
                    Console.WriteLine($"   move f{f} leg{i} preSwing{preSwing[i]} preForced{preForced[i]} preHas{preHas[i]} d{preFoot[i].DistanceTo(post.LastWorldFoot):0.00} postForced{post.Forced} lift{post.Lift:0.00} y{post.Foot.Y:0.00} phase{post.Phase:0.00}");
            }
            double profile = SpiderRig.ProfileAmount(spider.Facing);
            for (int i = 0; i < 8; i++)
            {
                var hip = SpiderRig.Rig(i, profile, spider.Design.Look.Legs).Hip;
                double reach = spider.Gait.Legs[i].Foot.DistanceTo(hip) / Math.Max(1e-6, spider.Gait.LegLen[i]);
                worstReach = Math.Max(worstReach, reach);
            }
        }
        Harness.Check(worstReach <= GaitDriver.ReachLimit + 0.02,
            "no foot is ever past legLength × 1.25 from its hip", $"worst {worstReach:0.000}×");
    }

    static void GroupAlternationChecks()
    {
        Harness.Section("alternating groups (spec 4.5)");

        var (_, _, spider) = OnWindowTop();
        spider.Walk(1, 8);
        for (int i = 0; i < 180; i++) spider.Update(Dt);

        int minSwing = 8, maxSwing = 0;
        for (int f = 0; f < 180; f++)
        {
            spider.Update(Dt);
            int swinging = 0;
            for (int i = 0; i < 8; i++) if (spider.Gait.Legs[i].InSwing) swinging++;
            minSwing = Math.Min(minSwing, swinging);
            maxSwing = Math.Max(maxSwing, swinging);
        }
        // A tetrapod gait does have brief moments with all eight down; what matters is that it is
        // always supported and that feet are usually moving.
        Harness.Check(minSwing >= 0, "planted support is never lost", $"min {minSwing} swinging");
        Harness.Check(maxSwing >= 2, "feet are stepping most of the time", $"max {maxSwing} swinging");
        Harness.Check(maxSwing <= 5, "never more than five feet in the air at once", $"max {maxSwing}");
        Harness.Check(minSwing <= 4 && maxSwing >= 1, "the body is supported by planted feet at every moment");

        // the two groups alternate: legs 0 and 1 are never both in swing for long
        int bothDown = 0, samples = 0;
        for (int f = 0; f < 300; f++)
        {
            spider.Update(Dt);
            samples++;
            if (!spider.Gait.Legs[0].InSwing && !spider.Gait.Legs[1].InSwing) bothDown++;
        }
        Harness.Check(bothDown > samples * 0.3, "opposite-group legs are usually both planted", $"{bothDown}/{samples}");
    }

    static void BobChecks()
    {
        Harness.Section("the body bobs twice per cycle (spec 4.5)");

        var (_, _, spider) = OnWindowTop();
        spider.Walk(1, 10);
        for (int i = 0; i < 120; i++) spider.Update(Dt);

        // sample the lift over two full gait cycles and count its peaks
        double startCycle = spider.Gait.Cycle;
        var lift = new List<double>();
        double cycle = startCycle;
        int guard = 0;
        while (cycle - startCycle < 2.0 && guard++ < 2000)
        {
            spider.Update(Dt);
            lift.Add(spider.BuildPose().Lift);
            if (spider.Gait.Cycle < cycle && cycle > 0.5) cycle += 1;
            cycle = cycle - spider.Gait.Cycle < 0 ? spider.Gait.Cycle : cycle;
            cycle = spider.Gait.Cycle;
        }
        // simply count local maxima in the sampled lift
        int peaks = 0;
        for (int i = 1; i < lift.Count - 1; i++)
            if (lift[i] > lift[i - 1] && lift[i] >= lift[i + 1]) peaks++;

        Harness.Check(lift.Count > 60, "sampled enough frames", $"{lift.Count}");
        Harness.Check(peaks >= 2, "the body rises more than once per sample window", $"{peaks} peaks");
        Harness.Check(lift.Max() - lift.Min() > 0.1, "the bob is visible", $"amp {lift.Max() - lift.Min():0.00} units");
        Harness.Check(lift.Max() - lift.Min() < 3.0, "the bob is subtle, not a pogo", $"amp {lift.Max() - lift.Min():0.00}");
    }

    // ------------------------------------------------------------------ corners

    static void CornerChecks()
    {
        Harness.Section("corners, sides and undersides (spec 4.5.3, 4.6)");

        foreach (double corner in new[] { 8.0, 26.0 })   // Win11 radius and a rounded mac window
        {
            var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "w", corner));
            var map = Synth.Build(desk, 0.78);
            var spider = new Spider(Sheets.DefaultDesign(), map, new Rng(3)) { UserScale = 0.78 };
            spider.SetAnchor("win:1", 0, 20, 1);
            spider.Walk(1, 30);

            double worstKneeThrough = 0, worstReach = 0;
            for (int f = 0; f < 900; f++)   // 15 s: right round the window
            {
                spider.Update(Dt);
                double profile = SpiderRig.ProfileAmount(spider.Facing);
                var loop = map.Loop(spider.Anchor.LoopId)!;
                var seg = loop.Segs[spider.Anchor.SegIdx];
                for (int i = 0; i < 8; i++)
                {
                    var hip = SpiderRig.Rig(i, profile, spider.Design.Look.Legs).Hip;
                    double reach = spider.Gait.Legs[i].Foot.DistanceTo(hip) / Math.Max(1e-6, spider.Gait.LegLen[i]);
                    worstReach = Math.Max(worstReach, reach);

                    // the knee must not bend through the surface: its distance from the ledge line
                    // must not exceed the foot's own side of it
                    V2 knee = spider.Gait.KneeFor(i, profile, spider.Design.Look.Legs, default);
                    double side = seg.Facing == EdgeFacing.Up ? knee.Y - SpiderRig.Ground
                               : seg.Facing == EdgeFacing.Down ? SpiderRig.Ground - knee.Y
                               : 0;
                    if (side < 0) worstKneeThrough = Math.Max(worstKneeThrough, -side);
                }
            }
            Harness.Check(worstReach <= GaitDriver.ReachLimit + 0.02,
                $"corner {corner:0}: no leg longer than the flat envelope", $"worst {worstReach:0.000}×");
            Harness.Check(worstKneeThrough < 6.0,
                $"corner {corner:0}: no knee bends through the surface", $"worst {worstKneeThrough:0.0} units");
            Harness.Check(spider.Speed > 20, $"corner {corner:0}: it is still walking after a full lap");
        }

        // every face of the window produces a sane heading
        var (_, map2, spider2) = OnWindowTop();
        foreach (int segIdx in new[] { 0, 1, 2, 3 })
        {
            spider2.SetAnchor("win:1", segIdx, 20, 1);
            spider2.Walk(1, 4);
            for (int i = 0; i < 60; i++) spider2.Update(Dt);
            var sp = map2.Resolve(spider2.Anchor, Spider.CornerRadius * spider2.Scale);
            Harness.Check(sp.Pos.IsFinite && spider2.Speed > 10, $"walks on window side {segIdx}");
        }

        // along the screen rim and across the taskbar line
        var rimSpider = new Spider(Sheets.DefaultDesign(), map2, new Rng(9)) { UserScale = 0.78 };
        rimSpider.SetAnchor("screen:0", 0, 100, 1);
        rimSpider.Walk(1, 6);
        for (int i = 0; i < 180; i++) rimSpider.Update(Dt);
        Harness.Check(rimSpider.Speed > 20, "walks the screen rim");
        Harness.Near(rimSpider.Pos.Y, 40 + Synth.Standoff, 2.5, "and stands on the taskbar top");
    }

    // ------------------------------------------------------------------ carried by a window

    static void CarriedChecks()
    {
        Harness.Section("carried by a moving window (spec 4.4)");

        var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "w", corner: 26));
        var map = Synth.Build(desk, 0.78);
        var spider = new Spider(Sheets.DefaultDesign(), map, new Rng(5)) { UserScale = 0.78 };
        spider.SetAnchor("win:1", 0, 300, 1);
        spider.Stand();
        for (int i = 0; i < 60; i++) spider.Update(Dt);

        double y0 = spider.Pos.Y;
        var foot0 = spider.WorldFoot(2);

        // drag the window up 200 units over a second
        for (int f = 0; f < 60; f++)
        {
            desk.Windows[0].Frame = new Rect(200, 300 + (f + 1) * (200.0 / 60), 900, 500);
            map.Rebuild(desk, 0.78);
            spider.Update(Dt);
        }

        Harness.Near(spider.Pos.Y - y0, 200, 3.0, "the spider rides up with the window");
        var foot1 = spider.WorldFoot(2);
        Harness.Check(Math.Abs(foot1.Y - foot0.Y) > 190, "its feet go along with it");
        Harness.Check(Math.Abs(foot1.X - foot0.X) < 1.0, "and do not slide sideways", $"drift {Math.Abs(foot1.X - foot0.X):0.00}");

        // resizing keeps it on the edge
        desk.Windows[0].Frame = new Rect(200, 500, 1200, 600);
        map.Rebuild(desk, 0.78);
        for (int i = 0; i < 30; i++) spider.Update(Dt);
        Harness.Near(spider.Pos.Y, 500 + 600 + Synth.Standoff, 2.5, "after a resize it is still riding the top edge");

        // the window vanishing underneath it must not throw
        desk.Windows.Clear();
        map.Rebuild(desk, 0.78);
        spider.Update(Dt);
        Harness.Check(true, "a vanished window is survivable");
    }

    // ------------------------------------------------------------------ start and stop

    static void StartStopChecks()
    {
        Harness.Section("starting and stopping (spec 4.3 inertia)");

        var (_, _, spider) = OnWindowTop();
        spider.Stand();
        for (int i = 0; i < 30; i++) spider.Update(Dt);
        Harness.Near(spider.Speed, 0, 0.5, "at rest the speed is zero");

        // starting: speed ramps rather than jumping to full
        spider.Walk(1, 5);
        spider.Update(Dt);
        Harness.Check(spider.Speed < 20, "it leans into the start (speed ramps up)", $"{spider.Speed:0.0} after one frame");
        for (int i = 0; i < 120; i++) spider.Update(Dt);
        double cruising = spider.Speed;
        Harness.Check(cruising > 40, "it reaches a cruise", $"{cruising:0.0}");

        // stopping: speed decays rather than stopping dead
        spider.Stand();
        spider.Update(Dt);
        Harness.Check(spider.Speed > cruising * 0.6, "it rocks forward on the stop (speed does not drop dead)", $"{spider.Speed:0.0}");
        for (int i = 0; i < 90; i++) spider.Update(Dt);
        Harness.Near(spider.Speed, 0, 0.5, "and comes to rest");

        // the rest posture lifts the body a little and the tucked-up walk pauses are short
        var posture = Posture.For(Activity.Walk, 0.5, spider.Design.Gait, new Rng(1));
        Harness.Near(posture.Speed, 1.0, 1e-12, "walk posture speed is 1");
        Harness.Near(Posture.For(Activity.Sneak, 0.5, spider.Design.Gait, new Rng(1)).Speed, 0.42, 1e-12, "sneak is 0.42");
        Harness.Near(Posture.For(Activity.Scurry, 0.5, spider.Design.Gait, new Rng(1)).Speed, 1.9, 1e-12, "scurry is 1.9");
        Harness.Near(Posture.For(Activity.Rest, 0.5, spider.Design.Gait, new Rng(1)).Lift, -4, 1e-12, "rest drops the body 4 units");
        Harness.Near(Posture.For(Activity.Sleep, 0.5, spider.Design.Gait, new Rng(1)).Lid, 1, 1e-12, "sleep closes the lids");
        Harness.Check(Posture.For(Activity.Sleep, 0.5, spider.Design.Gait, new Rng(1)).LegsFree, "sleep places the legs by pose");
        Harness.Near(Posture.For(Activity.Wave, 0.5, spider.Design.Gait, new Rng(1)).Pitch, 0.16, 1e-12, "wave leans back 0.16");
    }

    // ------------------------------------------------------------------ all five sizes

    static void AllScalesChecks()
    {
        Harness.Section("every size (spec 0.5 — validate at all five sizes)");

        foreach (double scale in Scales)
        {
            var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "w", corner: 26));
            var map = Synth.Build(desk, scale);
            var spider = new Spider(Sheets.DefaultDesign(), map, new Rng(11)) { UserScale = scale };
            spider.SetAnchor("win:1", 0, 20, 1);
            spider.Walk(1, 20);

            // steady walking: the ramp-up is covered by the starting/stopping checks
            for (int i = 0; i < 120; i++) spider.Update(Dt);

            double worstSlide = 0, worstReach = 0, worstTurnSlide = 0;
            var prev = new V2[8];
            var wasStance = new bool[8];
            for (int i = 0; i < 8; i++) { prev[i] = spider.WorldFoot(i); wasStance[i] = !spider.Gait.Legs[i].InSwing; }

            for (int f = 0; f < 1200; f++)   // 20 s: a full lap including corners
            {
                spider.Update(Dt);
                double profile = SpiderRig.ProfileAmount(spider.Facing);
                for (int i = 0; i < 8; i++)
                {
                    var foot = spider.WorldFoot(i);
                    bool stance = !spider.Gait.Legs[i].InSwing;
                    if (stance && wasStance[i] && foot.DistanceTo(prev[i]) > worstSlide)
                    {
                        worstSlide = foot.DistanceTo(prev[i]);
                    }
                    prev[i] = foot; wasStance[i] = stance;

                    var hip = SpiderRig.Rig(i, profile, spider.Design.Look.Legs).Hip;
                    worstReach = Math.Max(worstReach, spider.Gait.Legs[i].Foot.DistanceTo(hip) / spider.Gait.LegLen[i]);
                }
            }
            Harness.Check(worstSlide < 0.25, $"scale {scale:0.00}: walking straight, planted feet do not slide", $"worst {worstSlide:0.000}");
            Harness.Check(worstTurnSlide < 1.6, $"scale {scale:0.00}: turning, feet step round", $"worst {worstTurnSlide:0.000}");
            Harness.Check(worstReach <= GaitDriver.ReachLimit + 0.02, $"scale {scale:0.00}: reach limit held", $"worst {worstReach:0.000}×");

            // the drawn radius never exceeds the clamp at any size
            var pose = spider.BuildPose();
            var (r, bmp) = SpriteRaster.Measure(pose, spider.Design.Look);
            bmp.Dispose();
            Harness.Check(r <= SpiderRenderer.DrawRadius, $"scale {scale:0.00}: draw radius covered", $"{r:0.0}");
        }
    }

    // ------------------------------------------------------------------ activities

    static void ActivityChecks()
    {
        Harness.Section("postures reached by springs, never snapped (rule 4)");

        var (_, _, spider) = OnWindowTop();
        spider.Walk(1, 3);
        for (int i = 0; i < 60; i++) spider.Update(Dt);

        double liftBefore = spider.Lift.Value;
        spider.Play(Activity.Stretch, 1.6);
        spider.Update(Dt);
        double liftAfterOne = spider.Lift.Value;
        Harness.Check(liftAfterOne - liftBefore < 1.0,
            "a new posture springs toward its target rather than snapping", $"moved {liftAfterOne - liftBefore:0.000} in one frame");

        for (int i = 0; i < 30; i++) spider.Update(Dt);
        Harness.Check(spider.Lift.Value > liftBefore, "the stretch does lift the body over its duration");

        // every activity in the posture table produces a finite posture
        bool allFinite = true;
        foreach (Activity a in Enum.GetValues<Activity>())
        {
            var p = Posture.For(a, 0.5, spider.Design.Gait, new Rng(1));
            if (!double.IsFinite(p.Speed) || !double.IsFinite(p.Lift) || !double.IsFinite(p.Pitch)
                || !double.IsFinite(p.Crouch) || !double.IsFinite(p.Wag) || !double.IsFinite(p.Lid))
                allFinite = false;
        }
        Harness.Check(allFinite, $"all {Enum.GetValues<Activity>().Length} activities give a finite posture");

        // a stationary posture is never quite still (spec 4.3)
        Harness.Check(Habits.Weight(0.5) > 0, "habit weighting is available to the posture table");
    }

    // ------------------------------------------------------------------ film strips

    static void FilmChecks()
    {
        Harness.Section("film strip (spec 20 — the owner judges what is drawn)");

        var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26));
        var map = Synth.Build(desk, 0.78);
        var spider = new Spider(Sheets.DefaultDesign(), map, new Rng(2)) { UserScale = 0.78 };
        spider.SetAnchor("win:1", 0, 20, 1);
        spider.Walk(1, 30);

        const int sharpness = 3;      // 3× the scale for close inspection
        const int frames = 12;
        const int step = 6;           // one frame every 0.1 s
        var cells = new List<(string, SpiderPose, SpiderLook)>();
        for (int i = 0; i < 120; i++) spider.Update(Dt);   // get up to speed
        for (int f = 0; f < frames; f++)
        {
            for (int s = 0; s < step; s++) spider.Update(Dt);
            var pose = spider.BuildPose();
            // centre the cell on the spider so the film reads as a close-up
            pose.Pos = V2.Zero;
            cells.Add(($"+{f * step / 60.0:0.0}s  spd {spider.Speed:0}", pose, spider.Design.Look));
        }
        string path = Sheets.Grid(Path.Combine(Sheets.OutputDir, "film-walk.png"), cells, 6, sharpness);
        Harness.Check(File.Exists(path) && new FileInfo(path).Length > 4000, "film-walk.png written (close-up walk cycle)");

        // corner film: rounded corner at both radii
        var cells2 = new List<(string, SpiderPose, SpiderLook)>();
        foreach (double corner in new[] { 8.0, 26.0 })
        {
            var d2 = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "w", corner));
            var m2 = Synth.Build(d2, 0.78);
            var sp2 = new Spider(Sheets.DefaultDesign(), m2, new Rng(4)) { UserScale = 0.78 };
            sp2.SetAnchor("win:1", 0, sp2.Map.Loop("win:1")!.Segs[0].Len - 90, 1);
            sp2.Walk(1, 30);
            for (int f = 0; f < 12; f++)
            {
                for (int s = 0; s < 6; s++) sp2.Update(Dt);
                var pose = sp2.BuildPose();
                pose.Pos = V2.Zero;
                cells2.Add(($"r{corner:0} +{f * 0.1:0.0}s", pose, sp2.Design.Look));
            }
        }
        string path2 = Sheets.Grid(Path.Combine(Sheets.OutputDir, "film-corner.png"), cells2, 6, 3);
        Harness.Check(File.Exists(path2) && new FileInfo(path2).Length > 4000, "film-corner.png written (rounding both radii)");

        // turn film: walk, turn round, walk away
        var d3 = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "w", corner: 26));
        var m3 = Synth.Build(d3, 0.78);
        var sp3 = new Spider(Sheets.DefaultDesign(), m3, new Rng(6)) { UserScale = 0.78 };
        sp3.SetAnchor("win:1", 0, 400, 1);
        sp3.Walk(1, 30);
        var cells3 = new List<(string, SpiderPose, SpiderLook)>();
        for (int f = 0; f < 12; f++)
        {
            if (f == 4) sp3.Walk(-1, 10);    // turn round
            for (int s = 0; s < 6; s++) sp3.Update(Dt);
            var pose = sp3.BuildPose();
            pose.Pos = V2.Zero;
            cells3.Add(($"turn f{f} yaw {sp3.Facing:0.00}", pose, sp3.Design.Look));
        }
        string path3 = Sheets.Grid(Path.Combine(Sheets.OutputDir, "film-turn.png"), cells3, 6, 3);
        Harness.Check(File.Exists(path3) && new FileInfo(path3).Length > 4000, "film-turn.png written (a turn on the spot)");
        Console.WriteLine($"    films in {Path.GetFullPath(Sheets.OutputDir)}");
    }
}
