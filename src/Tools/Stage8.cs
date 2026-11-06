using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

public static class Stage8
{
    static (SurfaceMap map, Spider s) Scene(double scale = 0.78)
    {
        var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26));
        var map = Synth.Build(desk, scale);
        var s = new Spider(Sheets.DefaultDesign(), map, new Rng(81)) { UserScale = scale, BrainEnabled = false };
        s.SetAnchor("win:1", 0, 220, 1);
        return (map, s);
    }

    static void LineChecks()
    {
        var (map, s) = Scene();
        Harness.Check(s.Mode == Mode.Attached, "starts on the window ledge");
        bool dropped = s.DropOnWeb();
        Harness.Check(dropped && s.Mode == Mode.Dangling && s.WebActive,
            "down on a thread: it hangs from the ceiling above", $"{s.Mode} {s.WebAnchor}");
        Harness.Check(s.WebAnchor.Y > s.Pos.Y + 40, "the anchor is above it, on the ceiling");
        Harness.Check(Math.Abs((s.Pos - s.WebAnchor).Length - s.WebLen) < 3,
            "the body hangs exactly its line length under the grip", $"{(s.Pos - s.WebAnchor).Length:0.0} vs {s.WebLen:0.0}");

        for (int i = 0; i < 90; i++) s.Update(1.0 / 60);
        Harness.Check(Math.Abs((s.Pos - s.WebAnchor).Length - s.WebLen) < 4,
            "and it stays there once settled");

        s.WebPlan.Clear();
        s.WebAngle = 0.45;
        s.WebAngleVel = 0;
        double before = s.WebAngle;
        for (int i = 0; i < 12; i++) s.Update(1.0 / 60);
        Harness.Check(s.WebAngle < before && s.WebAngleVel < 0,
            "a pushed line swings back like a pendulum", $"a{s.WebAngle:0.00} v{s.WebAngleVel:0.00}");

        double target = s.WebLen + 100;
        s.WebPlan.Clear();
        s.WebPlan.Add(WebPlanStep.Descend(target));
        for (int i = 0; i < 180; i++) s.Update(1.0 / 60);
        Harness.Check(Math.Abs(s.WebLen - target) < 5, "it pays line out to the asked length", $"{s.WebLen:0.0} vs {target:0.0}");

        s.WebPlan.Clear();
        s.WebPlan.Add(WebPlanStep.Plan(WebPlanKind.ClimbHome));
        for (int i = 0; i < 300 && s.Mode == Mode.Dangling; i++) s.Update(1.0 / 60);
        Harness.Check(s.Mode != Mode.Dangling && !s.WebActive,
            "hauling in ends with a mantle onto the anchor's surface", $"{s.Mode} {s.Pos}");

        var (_, s2) = Scene();
        s2.ObeyScroll(PointerLineOrder.Down);
        Harness.Check(s2.Mode == Mode.Dangling, "a scroll down on a ledge drops it onto a line");
        s2.ObeyScroll(PointerLineOrder.Up);
        s2.Update(1.0 / 60);
        Harness.Check(s2.WebPlan.Count > 0 && s2.WebPlan[0].Kind == WebPlanKind.ClimbHome,
            "a scroll up on the line hauls it home");
        Harness.Check(s2.LineOrder is null, "the order is consumed once");

        var (_, s3) = Scene();
        s3.ObeyScroll(PointerLineOrder.Up);
        Harness.Check(s3.Mode == Mode.Attached, "scroll up on a ledge is not a line order");
        s3.WebsEnabled = false;
        Harness.Check(!s3.DropOnWeb() && s3.Mode == Mode.Attached, "with silk off it will not drop");

        var (_, s4) = Scene();
        s4.Mode = Mode.Air;
        s4.Pos += new V2(30, 10);
        s4.Velocity = new V2(120, -400);
        bool caught = s4.CatchRescueLine();
        Harness.Check(caught && s4.Mode == Mode.Dangling && !s4.RescueLineRequested,
            "a falling spider catches a rescue line");
        Harness.Check(Math.Abs(s4.WebAngleVel * s4.WebLen - 120) < 40,
            "the catch keeps its sideways speed as a swing", $"{s4.WebAngleVel * s4.WebLen:0.0}");
    }

    static void SwingChecks()
    {
        var (_, s) = Scene();
        s.DropOnWeb(s.WebLen + 160);
        s.StartSwing();
        double maxOmega = 0;
        bool released = false;
        for (int i = 0; i < 60 * 12; i++)
        {
            s.Update(1.0 / 60);
            maxOmega = Math.Max(maxOmega, Math.Abs(s.WebAngleVel));
            if (s.Mode != Mode.Dangling) { released = true; break; }
        }
        Harness.Check(maxOmega > 1.0, "pumping builds the arc pass by pass", $"max ω {maxOmega:0.00}");
        Harness.Check(released, "and it lets go near the top of a swing", $"{s.Mode} {s.Air}");
    }

    static void HammockModelChecks()
    {
        var styles = new[] { HammockStyle.Sling, HammockStyle.Pouch, HammockStyle.Tangle, HammockStyle.Cradle };
        var sag = new[] { 0.42, 0.66, 0.50, 0.34 };
        var strands = new[] { 7, 9, 6, 6 };
        var give = new[] { 10, 16, 8, 12 };
        bool ok = true;
        for (int i = 0; i < 4; i++)
        {
            var info = Hammock.Info(styles[i]);
            ok &= Math.Abs(info.sagShare - sag[i]) < 1e-9 && info.strands == strands[i] && Math.Abs(info.give - give[i]) < 1e-9;
        }
        Harness.Check(ok, "four hammock styles carry the exact sag, strand count and give");

        var h = new Hammock { Exists = true, Box = new Rect(0, 0, 400, 300), Style = HammockStyle.Sling };
        h.Progress = 0.05;
        int a = h.StrandsLaid;
        h.Progress = 0.2;
        int b = h.StrandsLaid;
        h.Progress = 0.95;
        int c = h.StrandsLaid;
        Harness.Check(a == 0 && b == 1 && c == 7, "strands start at the first and finish at all seven", $"{a}/{b}/{c}");

        h.Sway = 0; h.Load = 0; h.Drop = 0;
        V2 bedLight = h.Bed;
        h.Load = 1;
        V2 bedHeavy = h.Bed;
        Harness.Check(bedHeavy.Y < bedLight.Y - 2, "the bed sinks under the spider's weight",
            $"{bedLight.Y:0.0} → {bedHeavy.Y:0.0}");

        var h2 = new Hammock { Exists = true, Box = new Rect(0, 0, 400, 300) };
        Harness.Check(h2.Drape[0] == 0, "a fresh strand starts taut");
        h2.Update(1.2);
        double mid = h2.Drape[0];
        h2.Update(1.2);
        Harness.Check(mid > 0.45 && mid < 0.55 && h2.Drape[0] >= 0.999, "and drapes over 2.4 s", $"{mid:0.00} → {h2.Drape[0]:0.00}");

        var h3 = new Hammock { Exists = true, Box = new Rect(0, 0, 400, 300), Finished = false, Progress = 0.2 };
        h3.Wipe(20);
        Harness.Check(!h3.Exists, "a half-made hammock goes with a single swipe");
        var h4 = new Hammock { Exists = true, Box = new Rect(0, 0, 400, 300), Finished = true };
        h4.Wipe(80);
        bool afterOne = h4.Exists;
        h4.Wipe(80);
        Harness.Check(afterOne && !h4.Exists, "a finished one tears down after a couple of good swipes");
    }

    static void HammockBuildChecks()
    {
        var (_, s) = Scene();
        Harness.Check(s.BuildHammock(HammockStyle.Cradle), "it starts a hammock where it stands");
        for (int i = 0; i < 60 * 14; i++) s.Update(1.0 / 60);
        Harness.Check(s.Hammock.Finished && s.Hammock.Progress >= 0.999, "the full build finishes",
            $"{s.Hammock.Progress:0.00} strands {s.Hammock.StrandsLaid}");
        Harness.Check(s.Hammock.StrandsLaid == s.Hammock.Strands, "with every strand laid", $"{s.Hammock.StrandsLaid}/{s.Hammock.Strands}");
        Harness.Check(!s.BuildHammock(), "a finished hammock is not rebuilt over itself");

        Harness.Check(s.NapInHammock() && s.InHammock, "it can climb in for a nap");
        for (int i = 0; i < 60; i++) s.Update(1.0 / 60);
        Harness.Check(s.Pos.DistanceTo(s.Hammock.Bed) < 1 && s.Hammock.Load > 0.99,
            "the bed bears it through the nap");

        s.WipeHammock(s.Hammock.Bed, 80);
        Harness.Check(s.Hammock.Damage > 0.3 && !s.InHammock, "a partial wipe gets it up gracefully");
        s.WipeHammock(s.Hammock.Bed, 80);
        Harness.Check(!s.Hammock.Exists, "and a second swipe clears it");

        var (_, s2) = Scene();
        s2.BuildHammock();
        for (int i = 0; i < 120; i++) s2.Update(1.0 / 60);
        s2.WipeHammock(s2.Hammock.Bed, 30);
        Harness.Check(!s2.Hammock.Exists, "an unfinished hammock nobody finished fades from a wipe");
    }

    public static int Run(string[] args)
    {
        Harness.Section("stage 8 silk: lines, rappel, climb, swing, mantle, hammock");
        LineChecks();
        SwingChecks();
        HammockModelChecks();
        HammockBuildChecks();
        return Harness.Summarise("stage 8 silk");
    }
}
