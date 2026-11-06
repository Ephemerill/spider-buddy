using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

public static class Stage15
{
    static (SurfaceMap map, Spider s) Scene(ulong seed = 151)
    {
        var desk = Synth.Desktop()
            .With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26))
            .With(Synth.Window(2, 700, 600, 500, 300, 1, "outside", corner: 20));
        var map = Synth.Build(desk);
        var s = new Spider(Sheets.DefaultDesign(), map, new Rng(seed)) { BrainEnabled = false };
        s.SetAnchor("win:1", 0, 220, 1);
        return (map, s);
    }

    public static int Run(string[] args)
    {
        Harness.Section("stage 15 box, visitors and thoughts");

        var (_, s) = Scene();
        var box = new Rect(180, 700, 600, 160);
        s.SetBox(box);
        Harness.Check(s.Confined && s.InBox && Math.Abs(s.Chill - 0.4) < 1e-9 && !s.HangOnly,
            "a drawn box confines it and chills it");
        Harness.Check(s.BoxDecisionScale < 0.5, "boxed decisions come about half as often");
        Harness.Check(!s.StartJump(new V2(1500, 900)), "it will not leap outside the box");
        Harness.Check(s.StartJump(s.Pos + new V2(80, 0)), "it still leaps to a spot inside");
        Harness.Check(!s.BuildHammock(), "it gives up hammocks in a box");

        var prey = s.ReleasePrey(PreyKind.Cricket, new V2(1500, 100));
        Harness.Check(prey is not null && box.Contains(prey.Pos), "prey released in a box appears inside",
            $"{prey?.Pos}");
        Harness.Check(s.AddStrand(s.Pos, s.Pos + new V2(20, 0)) is null, "no traces are left in a box");

        s.FreeBox();
        Harness.Check(!s.Confined && !s.InBox && Math.Abs(s.Chill - 1) < 1e-9,
            "freeing it restores the ordinary desktop");

        s.SetBox(new Rect(500, 500, 20, 20));
        Harness.Check(s.HangOnly, "a box with nothing to stand on is hang-only");
        s.FreeBox();

        var (_, r) = Scene(152);
        r.SetBox(new Rect(180, 700, 600, 160));
        r.SetAnchor("win:2", 0, 100, 1);
        bool cameBack = r.ReturnToBox();
        Harness.Check(cameBack && r.BoxReturns > 0, "outside the box, getting back is first on its mind");

        var (_, v) = Scene(153);
        Harness.Check(!v.VisitorsEnabled && v.SpawnVisitor() is null, "visitors are opt-in");
        v.VisitorsEnabled = true;
        for (int i = 0; i < 7; i++) v.SpawnVisitor();
        Harness.Check(v.Visitors.Count == 5 && v.MaxVisitors == 5, "at most five visitors are admitted",
            $"{v.Visitors.Count}");
        for (int i = 0; i < 120; i++) v.Update(1.0 / 60);
        Harness.Check(v.Visitors.Count > 0 && v.Visitors.All(x => x.Greeted),
            "a visitor arrives and says hello");
        v.VisitStay = 2;
        for (int i = 0; i < 60 * 8; i++) v.Update(1.0 / 60);
        Harness.Check(v.Visitors.Count == 0, "a visitor leaves after its stay");

        v.SpawnVisitor();
        v.DismissVisitors();
        Harness.Check(v.Visitors.All(x => x.Phase == VisitorPhase.Leaving && x.Dismissed),
            "Dismiss Visitors sends them off");
        for (int i = 0; i < 60 * 4; i++) v.Update(1.0 / 60);
        Harness.Check(v.Visitors.Count == 0, "dismissed visitors actually go");

        var (_, t) = Scene(154);
        t.ThinkOf(ThoughtKind.Heart);
        Harness.Check(t.ThoughtShowing, "it can think a thought on demand");
        t.EnterCinema(new Rect(0, 0, 1920, 1080));
        Harness.Check(!t.ThoughtShowing, "thought bubbles are suppressed in cinema");
        t.ExitCinema();
        Harness.Check(t.ThoughtShowing, "and return when the picture ends");
        t.ThinkOf(ThoughtKind.Text, "hello");
        Harness.Check(t.CurrentThought == ThoughtKind.Text && t.CurrentThoughtText == "hello",
            "a custom thought reaches the renderer fields");

        return Harness.Summarise("stage 15 box and visitors");
    }
}
