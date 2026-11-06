using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

public static class Stage6
{
    static Spider Make(Personality? p = null, ulong seed = 1, SurfaceMap? map = null)
    {
        map ??= Synth.Build(Synth.Desktop().With(Synth.Window(1, 100, 200, 1200, 500)));
        var design = new SpiderDesign();
        if (p is not null) design.Personality = p;
        var s = new Spider(design, map, new Rng(seed));
        s.SetAnchor("win:1", 0, 250, 1);
        return s;
    }

    /// <summary>Run for a while, returning (activity, seconds) bouts in order.</summary>
    static List<(Activity a, double dur)> Sim(Spider s, double seconds, Action<Spider>? each = null)
    {
        var bouts = new List<(Activity, double)>();
        Activity last = s.Activity;
        double since = 0;
        int frames = (int)(seconds * 60);
        for (int i = 0; i < frames; i++)
        {
            each?.Invoke(s);
            s.Update(1.0 / 60);
            if (s.Activity != last)
            {
                bouts.Add((last, since));
                last = s.Activity;
                since = 0;
            }
            since += 1.0 / 60;
        }
        bouts.Add((last, since));
        return bouts;
    }

    static void PersonalityChecks()
    {
        var hyper = Make(Personality.Preset(Temperament.Hyper), 3);
        var lazy = Make(Personality.Preset(Temperament.Lazy), 3);
        var hyperBouts = Sim(hyper, 150);
        var lazyBouts = Sim(lazy, 150);
        Harness.Check(hyperBouts.Count > lazyBouts.Count * 1.4,
            "hyper lives faster than lazy", $"{hyperBouts.Count} vs {lazyBouts.Count}");
        Harness.Check(lazyBouts.Any(b => b.a == Activity.Sleep), "lazy nods off within 150 s");
        Harness.Check(lazyBouts.Count(b => b.a is Activity.Rest or Activity.Sleep) > 0, "lazy rests");

        var show = Make(Personality.Preset(Temperament.ShowOff), 4);
        var grump = Make(Personality.Preset(Temperament.Grumpy), 4);
        var showBouts = Sim(show, 150);
        var grumpBouts = Sim(grump, 150);
        int showShow = showBouts.Count(b => b.a is Activity.Dance or Activity.Wiggle or Activity.ArmsUp or Activity.Drum or Activity.Spin);
        int grumpShow = grumpBouts.Count(b => b.a is Activity.Dance or Activity.Wiggle or Activity.ArmsUp or Activity.Drum or Activity.Spin);
        Harness.Check(showShow > grumpShow, "a show-off shows off more than a grump", $"{showShow} vs {grumpShow}");
    }

    static void HabitChecks()
    {
        // Every dial at zero except one: only that behaviour may happen (spec 6.8).
        var s = Make(Personality.Preset(Temperament.Chill), 5);
        foreach (var (_, _, set) in s.Design.Habits.Dials) set(0);
        s.Design.Habits.Rest = 1;
        var bouts = Sim(s, 60);
        var real = bouts.Where(b => b.a != Activity.Idle).Select(b => b.a).Distinct().ToList();
        Harness.Check(real.All(a => a == Activity.Rest), "a habit at zero is never drawn",
            string.Join(",", real));
        Harness.Check(bouts.Count(b => b.a == Activity.Rest) >= 3, "a habit at one dominates");

        var none = Make(Personality.Preset(Temperament.Chill), 6);
        foreach (var (_, _, set) in none.Design.Habits.Dials) set(0);
        none.Design.Habits.Sleep = 0;
        var idle = Sim(none, 45);
        Harness.Check(idle.Where(b => b.a != Activity.Idle).ToList().Count == 0,
            "all dials at zero leaves it sitting still");
    }

    static void AttentionChecks()
    {
        var s = Make(Personality.Preset(Temperament.Friendly), 7);
        s.FollowCursor = true;
        s.SetCursor(s.Pos + new V2(60, 10));
        for (int i = 0; i < 40; i++) s.Update(1.0 / 60);
        Harness.Check(s.Interest > 0.85, "the pointer has its attention");
        s.Think();
        Harness.Check(s.Activity is Activity.Look or Activity.Stare or Activity.Curious or Activity.Greet
            or Activity.ArmsUp or Activity.Wave or Activity.Fidget or Activity.Peer,
            "with attention on the pointer only the attention set is offered", s.Activity.ToString());

        // A pointer trip: come to the cursor when asked to.
        var a = Make(Personality.Preset(Temperament.Curious), 8);
        a.ApproachCursor = true;
        a.SetCursor(a.Pos + new V2(150, 30));
        for (int i = 0; i < 60; i++) a.Update(1.0 / 60);
        a.Think();
        Harness.Check(a.Activity == Activity.Walk && Math.Sign(a.WalkDir) == Math.Sign(a.Cursor.X - a.Pos.X),
            "Come to the Cursor walks toward it", a.Activity.ToString());
    }

    static void MoodChecks()
    {
        var s = Make(Personality.Preset(Temperament.Chill), 9);
        s.SetMood(Mood.Potter);
        Harness.Check(s.Linger >= 1.4 && s.Linger <= 2.2, "pottering things last longer");
        s.SetMood(Mood.Roam);
        Harness.Check(s.Linger == 1, "roaming keeps the usual lengths");

        // Pottering walks less and sits more.
        var roam = Make(Personality.Preset(Temperament.Friendly), 10);
        roam.SetMood(Mood.Roam);
        int roamWalks = 0, roamSits = 0;
        foreach (var b in Sim(roam, 90))
        {
            if (b.a is Activity.Walk or Activity.Sneak or Activity.Scurry) roamWalks++;
            if (b.a is Activity.Look or Activity.Rest or Activity.Groom or Activity.Peer) roamSits++;
        }
        var pot = Make(Personality.Preset(Temperament.Friendly), 10);
        pot.SetMood(Mood.Potter);
        int potWalks = 0, potSits = 0;
        foreach (var b in Sim(pot, 90))
        {
            if (b.a is Activity.Walk or Activity.Sneak or Activity.Scurry) potWalks++;
            if (b.a is Activity.Look or Activity.Rest or Activity.Groom or Activity.Peer) potSits++;
        }
        Harness.Check(potWalks <= roamWalks && potSits >= roamSits,
            "pottering is more sitting and less walking", $"{potWalks}/{roamWalks}, {potSits}/{roamSits}");
    }

    static void HeadingChecks()
    {
        var s = Make(Personality.Preset(Temperament.Friendly), 11);
        var bouts = Sim(s, 240);
        double flipsPerMin = s.DirectionFlips / 4.0;
        double quickPerMin = s.QuickReturns / 4.0;
        Harness.Check(flipsPerMin < 8, "direction flips stay rare", $"{flipsPerMin:0.0}/min");
        Harness.Check(quickPerMin < 1.0, "it does not turn back right away", $"{quickPerMin:0.00}/min");

        // While walking, the body faces the way it walks.
        var w = Make(Personality.Preset(Temperament.Hyper), 12);
        bool backwards = false;
        for (int i = 0; i < 60 * 60; i++)
        {
            w.Update(1.0 / 60);
            if (w.Activity is Activity.Walk or Activity.Sneak or Activity.Scurry && w.ActivityTime > 0.4
                && Math.Sign(w.Facing) != Math.Sign(w.WalkDir) && Math.Abs(w.Facing) > 0.2)
                backwards = true;
        }
        Harness.Check(!backwards, "it never walks backwards");

        var t = Make();
        t.TurnTo(-t.WalkDir);
        Harness.Check(t.DirectionFlips == 1 && !t.MayTurnBack, "a turn commits the heading");
        Harness.Check(t.WanderWay() == t.WalkDir, "while committed it keeps its heading");
    }

    static void LongRunChecks()
    {
        var s = Make(Personality.Preset(Temperament.Friendly), 13);
        var bouts = Sim(s, 240);
        var kinds = bouts.Where(b => b.a != Activity.Idle).Select(b => b.a).Distinct().ToList();
        Harness.Check(kinds.Count >= 6, "four minutes are varied", string.Join(",", kinds));

        var shortOnes = bouts.Where(b => b.a != s.Activity && b.dur > 0 && b.dur < 0.45 && b.a != Activity.Idle).ToList();
        Harness.Check(shortOnes.Count == 0, "no one-second changes of mind",
            string.Join(",", shortOnes.Select(b => $"{b.a}:{b.dur:0.00}")));

        // Walking comes in bursts with pauses: there are sits between walks.
        int walks = bouts.Count(b => b.a is Activity.Walk or Activity.Sneak or Activity.Scurry);
        int sits = bouts.Count(b => b.a is Activity.Look or Activity.Rest or Activity.Groom or Activity.Peer
            or Activity.Glance or Activity.Fidget);
        Harness.Check(walks > 3 && sits > walks, "walking comes in bursts with pauses", $"{walks} walks, {sits} sits");

        // Thoughts come up, and clear again.
        var m = Make(Personality.Preset(Temperament.Curious), 14);
        bool thought = false;
        for (int i = 0; i < 60 * 120 && !thought; i++)
        {
            m.Update(1.0 / 60);
            if (m.ThoughtShowing && m.BuildPose().Emote == EmoteKind.Thought) thought = true;
        }
        Harness.Check(thought, "it thinks, and the bubble reaches the renderer");
    }

    public static int Run(string[] args)
    {
        Harness.Section("stage 6 the brain: decisions, moods, repertoire");
        PersonalityChecks();
        HabitChecks();
        AttentionChecks();
        MoodChecks();
        HeadingChecks();
        LongRunChecks();
        return Harness.Summarise("stage 6 brain");
    }
}
