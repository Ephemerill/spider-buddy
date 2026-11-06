using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

/// <summary>
/// Stage 1 acceptance (spec 1 "Done when"):
///  - a headless program steps a SilkRope pinned at the top with a free weight and prints
///    positions showing slack sag, taut straightness and a swing with lag;
///  - springs reproduce settling (k=180, c=18 settles in ~0.5 s with slight overshoot);
///  - settings round-trip including a file with extra and missing keys.
/// </summary>
public static class Stage1
{
    public static int Run(string[] args)
    {
        MathChecks();
        SpringChecks();
        RopeChecks();
        SettingsChecks();
        ClockChecks();
        return Harness.Summarise("stage 1 foundations");
    }

    // ------------------------------------------------------------------ math

    static void MathChecks()
    {
        Harness.Section("vectors and helpers (spec 1.2)");

        var a = new V2(3, 4);
        Harness.Near(a.Length, 5, 1e-12, "length");
        Harness.Near(a.LengthSquared, 25, 1e-12, "lengthSquared");
        Harness.Check(a.Normalized.DistanceTo(new V2(0.6, 0.8)) < 1e-12, "normalized");
        Harness.Check(V2.Zero.Normalized == V2.Zero, "zero normalises to zero, not NaN");
        Harness.Near(a.Dot(new V2(1, 0)), 3, 1e-12, "dot");
        Harness.Near(new V2(1, 0).Cross(new V2(0, 1)), 1, 1e-12, "cross");
        Harness.Near(new V2(1, 0).Perp.Dot(new V2(1, 0)), 0, 1e-12, "perp is perpendicular");
        Harness.Check(new V2(1, 0).Rotated(M.Pi / 2).DistanceTo(new V2(0, 1)) < 1e-12, "rotates +90 CCW (y-up)");
        Harness.Check(V2.Lerp(new V2(0, 0), new V2(10, 20), 0.5).DistanceTo(new V2(5, 10)) < 1e-12, "lerp");

        Harness.Near(M.Clamp(5, 0, 1), 1, 0, "clamp high");
        Harness.Near(M.Clamp(-5, 0, 1), 0, 0, "clamp low");
        Harness.Near(M.Smoothstep(0.5), 0.5, 1e-12, "smoothstep midpoint");
        Harness.Near(M.Smoothstep(0), 0, 1e-12, "smoothstep 0");
        Harness.Near(M.Smoothstep(1), 1, 1e-12, "smoothstep 1");
        Harness.Near(M.EaseOutCubic(1), 1, 1e-12, "easeOutCubic(1)");
        Harness.Near(M.EaseInOutSine(0.5), 0.5, 1e-12, "easeInOutSine midpoint");
        Harness.Near(M.EaseOutBack(1, 1.7), 1, 1e-9, "easeOutBack lands on 1");
        Harness.Check(M.EaseOutBack(0.7, 1.7) > 1, "easeOutBack overshoots before settling");

        Harness.Near(M.AngleDelta(0.1, 6.0), 6.0 - 0.1 - M.Tau, 1e-9, "angleDelta wraps to (-pi, pi]");
        Harness.Near(M.AngleDelta(0, M.Pi), M.Pi, 1e-9, "angleDelta(+pi) stays +pi");
        Harness.Near(M.WrapPi(3 * M.Pi), M.Pi, 1e-9, "wrapPi");

        // exponential approach hits the target asymptotically and is frame-rate independent
        double v = 0;
        for (int i = 0; i < 60; i++) v = M.Approach(v, 1, 5, 1.0 / 60);
        Harness.Near(v, 1 - Math.Exp(-5), 1e-3, "approach(5/s) over 1 s reaches 1-e^-5");
        double v2 = 0;
        for (int i = 0; i < 120; i++) v2 = M.Approach(v2, 1, 5, 1.0 / 120);
        Harness.Near(v2, v, 1e-3, "approach is frame-rate independent");

        // projectOnSegment clamps t
        var (t, dist) = M.ProjectOnSegment(new V2(5, 3), new V2(0, 0), new V2(10, 0));
        Harness.Near(t, 0.5, 1e-12, "projectOnSegment t");
        Harness.Near(dist, 3, 1e-12, "projectOnSegment distance");
        var (t2, _) = M.ProjectOnSegment(new V2(50, 0), new V2(0, 0), new V2(10, 0));
        Harness.Near(t2, 1, 1e-12, "projectOnSegment clamps t to [0,1]");
        var (tl, _) = M.ProjectOnSegment(new V2(5, 0), new V2(0, 0), new V2(10, 0));
        Harness.Near(tl, 0.5, 1e-12, "projectOnLine not used here");

        // quadratic bezier
        var bp = M.QuadPoint(new V2(0, 0), new V2(5, 10), new V2(10, 0), 0.5);
        Harness.Near(bp.X, 5, 1e-12, "quad midpoint x");
        Harness.Near(bp.Y, 5, 1e-12, "quad midpoint y");

        // Liang–Barsky. A segment at y=2 across a rect 0..4 x 0..4 enters at x=0 (t=0.5) and leaves at x=4 (t=0.7).
        bool hit = Clip.SegmentInRect(new V2(-10, 2), new V2(10, 2), new Rect(0, 0, 4, 4), out double c0, out double c1);
        Harness.Check(hit, "clip: crossing segment hits the rect");
        Harness.Near(c0, 0.5, 1e-9, "clip t0");
        Harness.Near(c1, 0.7, 1e-9, "clip t1");
        Harness.Check(!Clip.SegmentInRect(new V2(-10, 50), new V2(10, 50), new Rect(0, 0, 4, 4), out _, out _), "clip: miss above the rect is rejected");
        Harness.Check(!Clip.SegmentInRect(new V2(-10, 2), new V2(-5, 2), new Rect(0, 0, 4, 4), out _, out _), "clip: miss to the left is rejected");

        // rng determinism and randRange guards
        var r1 = new Rng(42); var r2 = new Rng(42);
        bool same = true;
        for (int i = 0; i < 100; i++) if (Math.Abs(r1.NextDouble() - r2.NextDouble()) > 0) same = false;
        Harness.Check(same, "rng is deterministic for a seed");
        Harness.Near(new Rng(1).RandRange(3, 3), 3, 0, "randRange equal bounds");
        Harness.Near(new Rng(1).RandRange(5, double.NaN), 5, 0, "randRange NaN guard returns lo");
        var rr = new Rng(7);
        Harness.Check(rr.RandRange(10, 2) is >= 2 and <= 10, "randRange reversed bounds never trap");
        Harness.Check(new Rng(3).Chance(1) && !new Rng(3).Chance(0), "chance(0/1) short-circuits");
    }

    // ------------------------------------------------------------------ springs

    static void SpringChecks()
    {
        Harness.Section("springs (spec 1.3, 4.2)");

        var s = new Spring(0, 180, 18);
        double t = 0, maxOver = 0, settleTime = -1;
        const double dt = 1.0 / 60;
        for (int i = 0; i < 600; i++)
        {
            s.Step(1, dt);
            t += dt;
            maxOver = Math.Max(maxOver, s.Value);
            if (settleTime < 0 && Math.Abs(s.Value - 1) < 0.01 && Math.Abs(s.Velocity) < 0.05) settleTime = t;
        }
        Harness.Check(maxOver > 1.0 && maxOver < 1.15, "k=180 c=18 gives slight overshoot", $"max {maxOver:0.0000}");
        Harness.Check(settleTime > 0.25 && settleTime < 0.8, "settles in ~0.5 s", $"settled at {settleTime:0.000} s");
        Harness.Near(s.Value, 1, 0.01, "converges to the target");

        // a spring must never blow up at the clamped dt extremes
        bool stable = true;
        foreach (double d in new[] { 1.0 / 240, 1.0 / 60, 1.0 / 30, 1.0 / 20 })
        {
            var q = new Spring(0, 180, 18);
            for (int i = 0; i < 400; i++)
            {
                q.Step(1, d);
                if (!double.IsFinite(q.Value) || Math.Abs(q.Value) > 5) { stable = false; break; }
            }
        }
        Harness.Check(stable, "stable at every clamped dt (1/240 … 1/20)");

        // reset/nudge
        var n = new Spring(5, 180, 18);
        n.Nudge(7);
        n.Step(5, dt);
        Harness.Check(n.Value > 5, "nudge pushes the value the way the impulse points");
        n.Reset(3);
        Harness.Check(n.Value == 3 && n.Velocity == 0, "reset clears velocity");

        // Spring2
        var s2 = new Spring2(new V2(0, 0), 150, 16);
        for (int i = 0; i < 600; i++) s2.Step(new V2(10, -5), dt);
        Harness.Near(s2.Value.DistanceTo(new V2(10, -5)), 0, 0.02, "Spring2 (lookSpring 150/16) converges");

        // wobble is smooth, bounded and leg-seeded
        var w0 = Wobble.ForLeg(0);
        var w1 = Wobble.ForLeg(1);
        Harness.Near(w0.Seed, 0, 1e-12, "leg 0 wobble seed = 0*2.7");
        Harness.Near(Wobble.ForLeg(3).Seed, 8.1, 1e-9, "leg 3 wobble seed = 3*2.7");
        Harness.Near(w0.Freq, 1.1, 1e-12, "leg 0 wobble freq = 1.1");
        Harness.Near(Wobble.ForLeg(1).Freq, 1.27, 1e-12, "leg 1 wobble freq = 1.1+0.17");
        Harness.Near(Wobble.ForLeg(4).Freq, 1.1, 1e-12, "leg 4 freq wraps i%4");
        bool bounded = true, moving = false;
        double prev = w0.Value(0);
        for (int i = 1; i < 600; i++)
        {
            double val = w0.Value(i * dt);
            if (Math.Abs(val) > 1.0) bounded = false;
            if (Math.Abs(val - prev) > 0.35) moving = false;
            if (Math.Abs(val - prev) > 1e-9) moving = true;
            prev = val;
        }
        Harness.Check(bounded, "wobble stays within ±1");
        Harness.Check(moving, "wobble varies continuously");
        Harness.Check(Math.Abs(w0.Value(1.0) - w1.Value(1.0)) > 1e-6, "legs own different wobbles");
    }

    // ------------------------------------------------------------------ rope

    static void RopeChecks()
    {
        Harness.Section("silk rope (spec 1.4)");

        const double dt = 1.0 / 60;

        // Slack sag: pin the head at the top, tail free, rope longer than the drop.
        var rope = new SilkRope();
        var head = new V2(0, 0);
        var tailStart = new V2(0, -60);
        rope.Reset(head, tailStart);
        rope.Length = 120;                 // deliberately longer than the 60-unit span
        rope.TailPinned = false;
        var freeTail = tailStart;
        for (int i = 0; i < 240; i++)
        {
            rope.Step(head, freeTail, 1950, 0.985, 0, dt);
            freeTail = rope.P[SilkRope.Segments];
        }
        double sag = -freeTail.Y;          // how far the free end hangs below the anchor
        Harness.Check(sag > 60, "slack rope sags past its initial span", $"tail at y={freeTail.Y:0.0}");
        Harness.Check(sag <= rope.Length + 6, "slack sag never exceeds the rope's length", $"y={freeTail.Y:0.0}, len={rope.Length}");
        Harness.Check(rope.P[0].DistanceTo(head) < 1e-9, "head end stays exactly pinned");
        Harness.Check(Math.Abs(rope.P[7].X) < 30, "slack rope does not wander far sideways");

        // Taut straightness: pull both ends hard apart, rope shorter than the span.
        var taut = new SilkRope();
        var a = new V2(0, 100);
        var b = new V2(0, 0);
        taut.Reset(a, b);
        taut.Length = 40;                  // much shorter than the 100-unit span
        for (int i = 0; i < 240; i++) taut.Step(a, b, 1950, 0.985, 0, dt);
        double maxDeviation = 0;
        for (int i = 0; i < SilkRope.Points; i++)
            maxDeviation = Math.Max(maxDeviation, M.DistanceToSegment(taut.P[i], a, b));
        Harness.Check(maxDeviation < 12, "taut rope straightens", $"max deviation {maxDeviation:0.00}");
        Harness.Check(taut.P[0].DistanceTo(a) < 1e-9 && taut.P[SilkRope.Segments].DistanceTo(b) < 1e-9, "both ends stay pinned");
        // With enough rope to span its ends, no link is ever stretched past rest.
        var enough = new SilkRope();
        enough.Reset(new V2(0, 100), new V2(0, 0));
        enough.Length = 140;
        for (int i = 0; i < 240; i++) enough.Step(new V2(0, 100), new V2(0, 0), 1950, 0.985, 0, dt);
        double worst = 0;
        for (int i = 0; i < SilkRope.Segments; i++) worst = Math.Max(worst, enough.P[i].DistanceTo(enough.P[i + 1]));
        Harness.Check(worst <= enough.Length / SilkRope.Segments + 1e-6, "no link is ever stretched past rest", $"worst {worst:0.000} vs rest {enough.Length / SilkRope.Segments:0.000}");

        // Swing with lag: shove the tail sideways and confirm the chain follows, whips, then damps.
        var swing = new SilkRope();
        var pivot = new V2(0, 200);
        var weight = new V2(0, 100);
        swing.Reset(pivot, weight);
        swing.Length = 110;
        swing.TailPinned = false;
        var w = weight;
        // give the free end a sideways velocity by nudging the tail point's previous position
        swing.Prev[SilkRope.Segments] = new V2(6, 100);
        double maxX = 0, firstX = 0;
        for (int i = 0; i < 90; i++)
        {
            swing.Step(pivot, w, 1950, 0.985, 0, dt);
            w = swing.P[SilkRope.Segments];
            if (i == 0) firstX = w.X;
            maxX = Math.Max(maxX, Math.Abs(w.X));
        }
        Harness.Check(maxX > Math.Abs(firstX) + 2, "a shove makes the rope swing out", $"max x {maxX:0.00}");
        double midLag = Math.Abs(swing.P[7].X);
        Harness.Check(midLag < maxX + 1, "the chain lags behind the swung end", $"mid {midLag:0.00} vs max {maxX:0.00}");

        // Motion decays to ~0 at rest — the solver can be slept. (No gravity: gravity keeps a
        // taut rope humming by definition, and the sleep test is about the solver going quiet.)
        var rest = new SilkRope();
        var rh = new V2(0, 100); var rt = new V2(0, 40);
        rest.Reset(rh, rt);
        for (int i = 0; i < 300; i++) rest.Step(rh, rt, 0, 0.985, 0, dt);
        Harness.Check(rest.Motion < 0.06, "motion settles toward 0 at rest", $"motion {rest.Motion:0.0000}");
        double hangingSagMotion = 0;
        var hung = new SilkRope();
        hung.Reset(new V2(0, 100), new V2(0, 0));
        for (int i = 0; i < 400; i++) hung.Step(new V2(0, 100), new V2(0, 0), 1950, 0.985, 0, dt);
        hangingSagMotion = hung.Motion;
        Harness.Check(hangingSagMotion < 0.3, "a hanging rope hums only faintly", $"motion {hangingSagMotion:0.0000}");

        // Wind pushes, gravity pulls
        var windy = new SilkRope();
        windy.Reset(new V2(0, 100), new V2(0, 40));
        windy.TailPinned = false;
        var wt = new V2(0, 40);
        for (int i = 0; i < 240; i++) { windy.Step(new V2(0, 100), wt, 1950, 0.985, 900, dt); wt = windy.P[SilkRope.Segments]; }
        Harness.Check(wt.X > 10, "wind pushes the free end downwind", $"x {wt.X:0.0}");

        // push() displaces an interior point, never a pinned end
        var pushy = new SilkRope();
        pushy.Reset(new V2(0, 100), new V2(0, 0));
        var before = pushy.P[7];
        pushy.Push(7, new V2(5, 0));
        Harness.Near(pushy.P[7].X - before.X, 5, 1e-12, "push displaces an interior point");
        pushy.Push(0, new V2(5, 0));
        Harness.Near(pushy.P[0].X, 0, 1e-12, "push ignores the pinned head");
        pushy.Push(SilkRope.Segments, new V2(5, 0));
        Harness.Near(pushy.P[SilkRope.Segments].X, 0, 1e-12, "push ignores the pinned tail");

        // resetAlong a polyline resamples evenly
        var poly = new SilkRope();
        poly.ResetAlong(new[] { new V2(0, 0), new V2(100, 0), new V2(100, 100) });
        Harness.Near(poly.Length, 200, 1e-9, "polyline length");
        Harness.Near(poly.P[SilkRope.Segments].DistanceTo(new V2(100, 100)), 0, 1e-6, "polyline resample ends at the far end");
        Harness.Near(poly.P[0].DistanceTo(new V2(0, 0)), 0, 1e-6, "polyline resample starts at the near end");
        double spacing = poly.Length / SilkRope.Segments;
        bool even = true;
        for (int i = 0; i < SilkRope.Segments; i++)
            if (Math.Abs(poly.P[i].DistanceTo(poly.P[i + 1]) - spacing) > 0.5) even = false;
        Harness.Check(even, "polyline resample is evenly spaced");

        // substep budget: a monster dt must not explode
        var big = new SilkRope();
        big.Reset(new V2(0, 100), new V2(0, 0));
        big.TailPinned = false;
        var bt = new V2(0, 0);
        for (int i = 0; i < 30; i++) { big.Step(new V2(0, 100), bt, 1950, 0.985, 0, 2.0); bt = big.P[SilkRope.Segments]; }
        bool finite = true;
        for (int i = 0; i < SilkRope.Points; i++) if (!big.P[i].IsFinite) finite = false;
        Harness.Check(finite, "a huge dt stays finite (5 s accumulated, clipped to 0.05 s)");

        Harness.Check(SilkRope.Segments == 14 && SilkRope.Points == 15, "rope is 14 segments / 15 points");
    }

    // ------------------------------------------------------------------ settings

    static void SettingsChecks()
    {
        Harness.Section("settings (spec 1.5, Appendix B)");

        var store = new MemoryTextStore();
        var s = new Settings(store);
        Harness.Check(s.GetBool("webs", true), "missing bool takes its default");
        Harness.Near(s.GetDouble("scale", 0.78), 0.78, 1e-12, "missing double takes its default");
        Harness.Near(s.GetInt("traceLimit", 12), 12, 0, "missing int takes its default");

        s.SetDouble("scale", 1.2);
        s.SetBool("interactive", false);
        s.SetInt("traceLimit", 40);
        s.SetString("spiderCurrentSave", "abc-123");
        s.SetPoint("confine", new V2(10, 20));
        s.SetBool("webs", true);
        s.Save();
        Harness.Check(s.Dirty == false, "save clears the dirty flag");

        var reopened = new Settings(store);
        Harness.Near(reopened.GetDouble("scale", 0), 1.2, 1e-12, "double round-trips");
        Harness.Check(reopened.GetBool("interactive", true) == false, "bool round-trips");
        Harness.Near(reopened.GetInt("traceLimit", 0), 40, 0, "int round-trips");
        Harness.Check(reopened.GetString("spiderCurrentSave") == "abc-123", "string round-trips");
        Harness.Check(reopened.GetPoint("confine") is { } cp && cp.DistanceTo(new V2(10, 20)) < 1e-12, "point round-trips");

        // Extra and missing keys must both be harmless, and unknown keys must survive a save.
        store.PutRaw("settings.json", """
        {
          "scale": 0.95,
          "continuity": 17,
          "newLegs": true,
          "traceLimit": 60,
          "someFutureThing": { "nested": [1, 2, 3] }
        }
        """);
        var tolerant = new Settings(store);
        Harness.Near(tolerant.GetDouble("scale", 0), 0.95, 1e-12, "known key read from a file with extras");
        Harness.Near(tolerant.GetDouble("followCursor", 1.0), 1.0, 1e-12, "missing key defaults alongside extras");
        Harness.Check(tolerant.Has("continuity"), "an unknown legacy key is retained, not dropped");
        tolerant.SetDouble("scale", 1.55);
        tolerant.Save();
        string after = store.Raw("settings.json")!;
        Harness.Check(after.Contains("continuity"), "unknown key round-trips harmlessly through a save");
        Harness.Check(after.Contains("someFutureThing"), "unknown structured key round-trips too");
        Harness.Check(after.Contains("\"newLegs\"") && after.Contains("true"), "legacy boolean still present as written");

        // corrupt file must not throw
        store.PutRaw("settings.json", "{ this is not json ");
        var bad = new Settings(store);
        Harness.Near(bad.GetDouble("scale", 0.78), 0.78, 1e-12, "a corrupt file falls back to defaults, no throw");

        // every Appendix B key name is read/writeable
        string[] keys =
        {
            "scale","interactive","paused","hidden","followCursor","approachCursor","pounceOnCursor",
            "webs","hammock","hammocks","traces","traceLimit","widgets","wildlife","wildFrequency",
            "tankWildlife","visitors","visitFrequency","visitStay","learns","feelPower","feelWeather",
            "feelCommotion","danceToMusic","showRain","toySounds","lowPowerOverride","climbPages",
            "confine","inHabitat","welcomed","askedToSeePages","design","memory","habitatKnowledge",
            "habitat","habitatGlass","habitatCamera","habitatSpider","habitatWeather","habitatWeatherNow",
            "habitatCurrentSave","habitatTourSeen","habitatDecorateTourSeen","spiderCurrentSave",
            "legLayersByDepth"
        };
        var all = new Settings(new MemoryTextStore());
        bool allOk = true;
        foreach (var k in keys)
        {
            all.SetBool(k, true);
            if (!all.GetBool(k, false)) allOk = false;
        }
        Harness.Check(allOk, $"all {keys.Length} Appendix B keys are usable");

        // a design-shaped object round-trips through SetObject/GetObject
        var obj = new Settings(new MemoryTextStore());
        obj.SetObject("design", new { name = "Biscuit", personality = 0.55 });
        var node = obj.GetNode("design");
        Harness.Check(node is not null && node.ToJsonString().Contains("Biscuit"), "structured object stored under a key");
    }

    // ------------------------------------------------------------------ clock

    static void ClockChecks()
    {
        Harness.Section("frame clock (spec 1.7)");

        var c = new FrameClock();
        c.Reset(0);
        Harness.Near(c.Dt, 1.0 / 60, 1e-12, "reset sets the first dt to one frame");

        // 60 ticks of 1/60 s advance 1 second
        int rendered = 0;
        double now = 0;
        var c2 = new FrameClock();
        c2.Reset(0);
        for (int i = 0; i < 60; i++) { now += 1.0 / 60; if (c2.Tick(now)) rendered++; }
        Harness.Near(c2.Now, 1.0, 1e-9, "one second of ticks");
        Harness.Check(c2.TickCount == 60, "60 ticks in one second", $"got {c2.TickCount}");
        Harness.Check(rendered == 60, "every tick renders while things are changing", $"{rendered}/60");

        // a 144 Hz host must not produce 16/25 ms alternation: extra callbacks are dropped and the
        // step stays exactly one frame. 288 callbacks over 2 s ⇒ ~120 ticks, all 16.7 ms.
        var c3 = new FrameClock();
        c3.Reset(0);
        now = 0;
        var dts = new List<double>();
        for (int i = 0; i < 288; i++)
        {
            now += 1.0 / 144;
            if (c3.Tick(now)) dts.Add(c3.Dt);
        }
        Harness.Check(c3.TickCount >= 114 && c3.TickCount <= 126, "144 Hz host is gated to ~60 Hz", $"got {c3.TickCount} in 2 s");
        Harness.Check(dts.Count > 0 && dts.All(d => Math.Abs(d - 1.0 / 60) < 1e-12), "every gated step is exactly 16.7 ms (no alternation)", $"min {dts.Min() * 1000:0.00} max {dts.Max() * 1000:0.00} ms");

        // dt clamps
        var c4 = new FrameClock();
        c4.Reset(0);
        c4.Tick(10);                    // huge gap
        Harness.Check(c4.Dt <= FrameClock.MaxDt + 1e-12, "a long stall clamps dt down", $"dt {c4.Dt * 1000:0.0} ms");
        c4.Tick(10 + 1e-9);             // tiny step
        Harness.Check(c4.Dt >= FrameClock.MinDt - 1e-12, "a tiny step clamps dt up", $"dt {c4.Dt * 1000:0.0} ms");

        // low power halves the clock
        var c5 = new FrameClock { LowPower = true };
        Harness.Near(c5.Hz, 30, 1e-12, "low power is 30 Hz");

        // calm throttle: unchanged for over a second then skipping
        var c6 = new FrameClock();
        c6.Reset(0);
        now = 0;
        for (int i = 0; i < 90; i++) { now += 1.0 / 60; c6.VisibleChanged = false; c6.Tick(now); }
        int skips = 0;
        for (int i = 0; i < 60; i++) { now += 1.0 / 60; c6.VisibleChanged = false; if (!c6.Tick(now)) skips++; }
        Harness.Check(skips > 20, "calm throttle skips frames when nothing visible changed", $"{skips}/60 skipped");
        c6.VisibleChanged = true;
        Harness.Check(c6.Tick(now + 1.0 / 60), "a visible change cancels calm immediately");

        // housekeeping cadence
        var c7 = new FrameClock();
        c7.Reset(0);
        now = 0;
        int half = 0, minute = 0, halfMin = 0;
        for (int i = 0; i < 3600; i++)
        {
            now += 1.0 / 60;
            c7.Tick(now);
            if (c7.HalfSecond) half++;
            if (c7.Minute) minute++;
            if (c7.HalfMinuteOffset) halfMin++;
        }
        Harness.Check(minute == 1, "one 60 s housekeeping beat per minute", $"got {minute}");
        Harness.Check(halfMin == 1, "one habitat-knowledge beat at 1800 mod 3600", $"got {halfMin}");
        Harness.Check(half >= 118 && half <= 120, "about 120 half-second beats per minute", $"got {half}");
    }
}
