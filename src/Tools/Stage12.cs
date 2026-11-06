using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

public static class Stage12
{
    static (SurfaceMap map, Spider s) Scene(double scale = 0.78)
    {
        var desk = Synth.Desktop()
            .With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26))
            .With(Synth.Window(2, 100, 100, 1200, 300, 1, "lower", corner: 20));
        var map = Synth.Build(desk, scale);
        var s = new Spider(Sheets.DefaultDesign(), map, new Rng(121)) { UserScale = scale, BrainEnabled = false };
        s.SetAnchor("win:1", 0, 220, 1);
        return (map, s);
    }

    public static int Run(string[] args)
    {
        Harness.Section("stage 12 traces: silk, webs, leftovers");

        var (_, s) = Scene();
        Harness.Check(!s.LeaveTraces && s.AddStrand(s.Pos, s.Pos + new V2(60, -40)) is null,
            "traces are off by default and leave nothing");

        s.LeaveTraces = true;
        var strand = s.AddStrand(s.Pos, s.Pos + new V2(80, -50));
        Harness.Check(strand is not null && strand.Kind == TraceKind.Strand
            && strand.Length > 0 && strand.LoopA is not null,
            "a strand joins two real edges and has a rope length");
        var web = s.AddWeb(s.Pos + new V2(40, -20));
        Harness.Check(web is not null && web.Threads.Count >= 20,
            "a little web is a sheet of criss-crossed threads", $"{web?.Threads.Count}");

        s.TidyTraces();
        s.SetTraceLimit(3);
        for (int i = 0; i < 6; i++) s.AddStrand(s.Pos, s.Pos + new V2(30 + i, -20));
        Harness.Check(s.TraceLimit == 3 && s.Traces.Count == 3,
            "Most at Once keeps only the newest few", $"{s.Traces.Count}");

        s.SetTraceLimit(60);
        Harness.Check(s.TraceUnlimited, "the top of the slider is Unlimited");
        for (int i = 0; i < 4; i++) s.AddStrand(s.Pos, s.Pos + new V2(20 + i, 10));
        Harness.Check(s.Traces.Count > 3, "unlimited keeps everything until it fades", $"{s.Traces.Count}");

        s.SetTraceLimit(24);
        s.TidyTraces();
        var fade = s.AddStrand(s.Pos, s.Pos + new V2(40, 20));
        fade!.Life = 0.5;
        for (int i = 0; i < 45; i++) s.Update(1.0 / 60);
        Harness.Check(!s.Traces.Contains(fade), "a trace fades away on its own");

        s.AddWeb(s.Pos + new V2(10, -10));
        int beforeTidy = s.Traces.Count;
        s.TidyTraces();
        Harness.Check(s.Traces.Count == 0 && beforeTidy > 0, "Tidy Up clears everything");

        s.AddStrand(s.Pos, s.Pos + new V2(40, 20));
        s.LeaveTraces = false;
        Harness.Check(s.Traces.Count == 0, "turning Leave Traces off clears what is out");
        s.LeaveTraces = true;

        s.InBox = true;
        bool boxed = s.AddStrand(s.Pos, s.Pos + new V2(30, 20)) is null;
        s.InBox = false;
        Harness.Check(boxed && s.Traces.Count == 0, "nothing is left while it is in a box");

        s.TidyTraces();
        var fly = s.ReleasePrey(PreyKind.FruitFly)!;
        fly.Pos = s.Pos;
        s.BeginEat(fly);
        for (int i = 0; i < 60 * 6; i++) s.Update(1.0 / 60);
        Harness.Check(s.Traces.Any(t => t.Kind == TraceKind.Leftover && t.Prey == PreyKind.FruitFly),
            "a meal leaves wings behind");

        s.TidyTraces();
        s.TraceLeapChance = 1;
        bool launched = s.LeapAt(s.Pos + new V2(160, 0));
        for (int i = 0; i < 180 && s.Mode != Mode.Attached; i++) s.Update(1.0 / 60);
        Harness.Check(launched && s.Traces.Any(t => t.Kind == TraceKind.Strand),
            "a leap now and then trails a strand from the ledge it left");

        s.TidyTraces();
        s.TraceSwingChance = 1;
        s.WebActive = true;
        s.WebAnchor = s.Pos + new V2(0, 300);
        s.WebLen = 300;
        s.WebAngle = 0;
        s.WebAngleVel = 1;
        s.ReleaseSwing();
        Harness.Check(s.Traces.Any(t => t.Kind == TraceKind.Strand),
            "a swing let go is left hanging");

        s.TidyTraces();
        var flick = s.AddStrand(s.Pos, s.Pos + new V2(40, 10))!;
        int before = s.Traces.Count;
        s.FlickTrace(s.Pos, 900);
        Harness.Check(s.Traces.Count < before, "a quick pointer swipe tears a strand");

        s.SetTraceLimit(1);
        bool clampedLow = s.TraceLimit == 3;
        s.SetTraceLimit(100);
        Harness.Check(clampedLow && s.TraceUnlimited, "the limit clamps to 3 and tops out at Unlimited");

        return Harness.Summarise("stage 12 traces");
    }
}
