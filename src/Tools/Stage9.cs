using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

public static class Stage9
{
    static (SurfaceMap map, Spider s) Scene(double scale = 0.78)
    {
        var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26));
        var map = Synth.Build(desk, scale);
        var s = new Spider(Sheets.DefaultDesign(), map, new Rng(91)) { UserScale = scale, BrainEnabled = false };
        s.SetAnchor("win:1", 0, 220, 1);
        return (map, s);
    }

    static void SequenceChecks()
    {
        var (_, s) = Scene();
        var start = s.Pos;
        Harness.Check(s.StartPeekaboo(600), "it finds a window edge to hide behind");
        Harness.Check(s.Peek == PeekPhase.Approach, "and creeps up to it");
        var edge = s.PeekEdge;

        for (int i = 0; i < 40; i++) s.Update(1.0 / 60);
        Harness.Check(s.Pos.DistanceTo(edge) < start.DistanceTo(edge) - 4,
            "closer to the edge after the creep", $"{start.DistanceTo(edge):0.0} → {s.Pos.DistanceTo(edge):0.0}");

        bool hidden = false, cutOut = false, grip = false;
        int bursts = 0;
        var prev = s.Peek;
        for (int i = 0; i < 60 * 14 && s.Peek != PeekPhase.None; i++)
        {
            s.Update(1.0 / 60);
            if (s.PeekHiddenNow)
            {
                hidden = true;
                var pose = s.BuildPose();
                cutOut |= pose.HiddenBy.Count > 0;
                grip |= pose.PeekGrip.Count == 2 && pose.PeekGrip[0].DistanceTo(s.PeekEdge) < 12;
            }
            if (s.Peek == PeekPhase.Burst && prev != PeekPhase.Burst) bursts++;
            prev = s.Peek;
        }

        Harness.Check(hidden, "it slips behind the edge and waits");
        Harness.Check(cutOut, "the pose is cut out by the window it hides behind");
        Harness.Check(grip, "two front feet grip the edge as dots");
        Harness.Check(bursts >= 2 && bursts <= 4, "it bursts out two to four times", $"{bursts}");
        Harness.Check(s.Peek == PeekPhase.None && s.Activity == Activity.Wiggle,
            "and finishes with a happy wiggle", $"{s.Peek} {s.Activity}");

        var (_, s2) = Scene();
        s2.StartPeekaboo(600);
        s2.AbortPeek();
        Harness.Check(s2.Peek == PeekPhase.None, "an aborted peek leaves it visible again");
    }

    static void TriggerChecks()
    {
        var (_, s) = Scene();
        s.SetCursor(new V2(5000, 5000));
        s.PeekWantsUntil = 0;
        Harness.Check(!s.MaybePeekaboo() && s.Peek == PeekPhase.None,
            "with nobody about it does not start a game");

        var (_, s2) = Scene();
        s2.SetCursor(new V2(5000, 5000));
        s2.PeekWantsUntil = s2.Time + 10;
        Harness.Check(s2.MaybePeekaboo() && s2.Peek != PeekPhase.None,
            "asked for peek-a-boo it plays even with the pointer away");

        var (_, s3) = Scene();
        s3.SetCursor(s3.Pos + new V2(40, 0));
        bool ever = false;
        for (int i = 0; i < 4000 && !ever; i++)
        {
            s3.Think();
            ever = s3.Peek != PeekPhase.None;
            if (!ever) s3.DecisionIn = 0.01;
            s3.Update(1.0 / 60);
        }
        Harness.Check(ever, "a pointer close by can start it on a decision");
    }

    public static int Run(string[] args)
    {
        Harness.Section("stage 9 peek-a-boo: creep, hide, burst, wiggle");
        SequenceChecks();
        TriggerChecks();
        return Harness.Summarise("stage 9 peek-a-boo");
    }
}
