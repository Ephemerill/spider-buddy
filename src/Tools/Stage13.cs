using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

public static class Stage13
{
    static Spider Make(Personality? p = null, ulong seed = 131)
    {
        var map = Synth.Build(Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26)));
        var design = new SpiderDesign { Personality = p ?? Personality.Preset(Temperament.Friendly) };
        var s = new Spider(design, map, new Rng(seed)) { BrainEnabled = false };
        s.SetAnchor("win:1", 0, 220, 1);
        return s;
    }

    public static int Run(string[] args)
    {
        Harness.Section("stage 13 memory: experiences shape a bounded personality");

        var s = Make();
        var baseP = s.Design.Personality.Clone();
        Harness.Check(s.Memory.Entries.Count == 0 && s.Memory.LearnFromExperience,
            "a new spider starts with no memories and learning on");

        s.Memory.Record(ExperienceKind.Petted, baseP);
        var entry = s.Memory.Entries[ExperienceKind.Petted];
        Harness.Check(entry.Feeling > 0 && entry.Lesson > 0 && s.Memory.Entries.Count == 1,
            "a petted experience leaves a feeling and a lesson");
        Harness.Check(s.ActivePersonality.Affection > baseP.Affection,
            "affection drifts toward the stroke", $"{s.ActivePersonality.Affection:0.000}");
        Harness.Check(Math.Abs(s.Design.Personality.Affection - baseP.Affection) < 1e-12,
            "the Studio's personality itself never moves");

        for (int i = 0; i < 200; i++) s.Memory.Record(ExperienceKind.Petted, baseP);
        double drift = s.ActivePersonality.Affection - baseP.Affection;
        Harness.Check(drift <= 0.2 + 1e-9 && drift > 0.05,
            "no trait moves more than a fifth of the way", $"{drift:0.000}");

        var shy = Make(Personality.Preset(Temperament.Shy));
        for (int i = 0; i < 80; i++) shy.Memory.Record(ExperienceKind.Startled, shy.Design.Personality);
        Harness.Check(shy.ActivePersonality.Bravery < shy.Design.Personality.Bravery - 0.1,
            "a run of frights leaves it warier", $"{shy.ActivePersonality.Bravery:0.00}");

        var brave = Make(Personality.Preset(Temperament.ShowOff));
        var timid = Make(Personality.Preset(Temperament.Shy));
        for (int i = 0; i < 50; i++)
        {
            brave.Memory.Record(ExperienceKind.Thrown, brave.Design.Personality);
            timid.Memory.Record(ExperienceKind.Thrown, timid.Design.Personality);
        }
        Harness.Check(brave.ActivePersonality.Playfulness > brave.Design.Personality.Playfulness
            && timid.ActivePersonality.Bravery < timid.Design.Personality.Bravery,
            "the same fling is a thrill to a bold spider and a fright to a timid one");

        var hunter = Make();
        for (int i = 0; i < 60; i++) hunter.Memory.Record(ExperienceKind.HuntWon, hunter.Design.Personality);
        Harness.Check(hunter.Memory.ProwessOffset(hunter.Design.Personality) > 0.15,
            "good hunts make it surer", $"{hunter.Memory.ProwessOffset(hunter.Design.Personality):0.00}");

        var loner = Make();
        for (int i = 0; i < 60; i++) loner.Memory.Record(ExperienceKind.Alone, loner.Design.Personality);
        Harness.Check(loner.Memory.HabitLean("Wander", loner.Design.Personality) > 1.1,
            "hours alone lean it toward wandering");

        var decay = Make();
        decay.Memory.Record(ExperienceKind.Petted, decay.Design.Personality);
        double feeling0 = decay.Memory.Entries[ExperienceKind.Petted].Feeling;
        double lesson0 = decay.Memory.Entries[ExperienceKind.Petted].Lesson;
        decay.Memory.Update(15 * 60);
        double feeling1 = decay.Memory.Entries[ExperienceKind.Petted].Feeling;
        double lesson1 = decay.Memory.Entries[ExperienceKind.Petted].Lesson;
        Harness.Check(feeling1 < feeling0 * 0.6 && lesson1 > lesson0 * 0.99,
            "feeling passes within the hour while the lesson lingers", $"{feeling1:0.00} {lesson1:0.000}");

        var offline30 = Make();
        offline30.Memory.Record(ExperienceKind.Played, offline30.Design.Personality);
        offline30.Memory.AdvanceOffline(30 * 86400);
        var after30 = offline30.Memory.Entries[ExperienceKind.Played].Lesson;
        var offline3 = Make();
        offline3.Memory.Record(ExperienceKind.Played, offline3.Design.Personality);
        offline3.Memory.AdvanceOffline(3 * 86400);
        var after3 = offline3.Memory.Entries[ExperienceKind.Played].Lesson;
        Harness.Check(Math.Abs(after30 - after3) < after3 * 0.02 + 1e-9,
            "closed time counts toward forgetting, but only three days", $"{after30:0.000} {after3:0.000}");

        var off = Make();
        off.Memory.Record(ExperienceKind.Petted, off.Design.Personality);
        off.Memory.LearnFromExperience = false;
        Harness.Check(Math.Abs(off.ActivePersonality.Affection - off.Design.Personality.Affection) < 1e-12
            && off.Memory.Entries.Count == 1,
            "Learn From Experience off keeps the memories but uses the Studio personality");

        var forget = Make();
        forget.Memory.Record(ExperienceKind.Petted, forget.Design.Personality);
        forget.Memory.RememberPlace(forget.Pos, 0.8);
        forget.Memory.ForgetAll();
        Harness.Check(forget.Memory.Entries.Count == 0 && forget.Memory.Places.Count == 0,
            "Forget It All wipes feelings, lessons and places");

        var place = Make();
        place.Memory.RememberPlace(place.Pos + new V2(50, 0), 0.9);
        place.Memory.RememberPlace(place.Pos, 0.2);
        Harness.Check(place.Memory.FavouritePlace is { } fp && fp.DistanceTo(place.Pos + new V2(50, 0)) < 1,
            "favourite places remember where comfort was");

        var settings = new Settings(new MemoryTextStore());
        var save = Make();
        for (int i = 0; i < 7; i++) save.Memory.Record(ExperienceKind.Played, save.Design.Personality);
        save.Memory.Save(settings);
        var loaded = SpiderMemory.Load(settings);
        Harness.Check(loaded.Entries.TryGetValue(ExperienceKind.Played, out var loadedEntry)
            && Math.Abs(loadedEntry.Lesson - save.Memory.Entries[ExperienceKind.Played].Lesson) < 1e-9,
            "memories survive a settings round-trip");

        var summary = Make();
        summary.Memory.Record(ExperienceKind.Petted, summary.Design.Personality);
        Harness.Check(summary.Memory.Summary.Contains("petted"), "the panel can say how it has been shaped",
            summary.Memory.Summary);

        var hooked = Make();
        hooked.Poke();
        Harness.Check(hooked.Memory.Entries.ContainsKey(ExperienceKind.Greeted),
            "a poke reaches the memory through the pointer event");

        return Harness.Summarise("stage 13 memory");
    }
}
