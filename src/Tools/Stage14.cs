using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

public static class Stage14
{
    static (SurfaceMap map, Spider s) Scene(ulong seed = 141)
    {
        var map = Synth.Build(Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26)));
        var s = new Spider(Sheets.DefaultDesign(), map, new Rng(seed)) { BrainEnabled = false };
        s.SetAnchor("win:1", 0, 220, 1);
        return (map, s);
    }

    public static int Run(string[] args)
    {
        Harness.Section("stage 14 sensing the machine");

        var (_, s) = Scene();
        var prey = s.ReleasePrey(PreyKind.Cricket)!;
        prey.Pos = s.Pos + new V2(120, 0);
        prey.OnSurface = true;
        s.EnterCinema(new Rect(0, 0, 1920, 1080));
        Harness.Check(s.Cinema && s.CinemaSeat.X > 0, "a full display puts it in cinema manners",
            $"cinema={s.Cinema} seat={s.CinemaSeat} screen={s.CinemaScreen}");
        Harness.Check(!s.StartHunt(prey) && !s.StartJump(s.Pos + new V2(160, 0))
            && !s.DropOnWeb() && !s.BuildHammock(),
            "cinema manners refuse hunting, leaping, silk and hammocks");
        s.BeginGrab(s.Pos + new V2(4, 0));
        Harness.Check(!s.IsHeld, "the pointer is ignored during cinema");
        for (int i = 0; i < 120; i++) s.Update(1.0 / 60);
        Harness.Check(s.Activity is Activity.Walk or Activity.Watch, "it settles down to watch the picture",
            s.Activity.ToString());
        s.ExitCinema();
        Harness.Check(!s.Cinema && s.StartJump(s.Pos + new V2(160, 0)),
            "when the picture ends it can leap again");

        var (_, p) = Scene(142);
        p.SetLowPower(true);
        Harness.Check(p.LowPower && p.ClockHz == 30 && p.Drowsy >= 0.4,
            "Low Power halves the clock and makes it drowsy");
        p.SetLowPower(false);
        Harness.Check(!p.LowPower && p.ClockHz == 60, "leaving Low Power restores the clock");

        var (_, c) = Scene(143);
        c.PlugIn();
        Harness.Check(c.OnCharger && c.ChargePerkUntil > c.Time, "the charger perks it up");
        c.Unplug();
        Harness.Check(!c.OnCharger, "unplugging is noticed");

        var (_, w) = Scene(144);
        w.SetWeather(61, 12, false, 9);
        Harness.Check(w.Raining && w.RainThoughtUntil > w.Time && w.WeatherCode == 61,
            "rain puts rain on its mind");
        w.SetWeather(0, 2, true, 21);
        Harness.Check(!w.Raining && w.WeatherIsDay, "clear weather clears the rain");

        var (_, b) = Scene(145);
        b.OnBanner();
        Harness.Check(b.BannerCount == 1 && b.Activity == Activity.Hop, "a notification banner makes it jump");
        b.OnCommotion(Commotion.Louder);
        Harness.Check(b.CommotionCount == 1 && b.Activity == Activity.Look,
            "a volume change only makes it look up");
        b.FeelCommotion = false;
        int before = b.BannerCount;
        b.OnBanner();
        Harness.Check(b.BannerCount == before + 1 && b.Activity == Activity.Look,
            "with Notice Pop-ups off it still counts but does not react");

        var (_, m) = Scene(146);
        m.SetMusic(true, 120, 0.9);
        for (int i = 0; i < 210; i++) m.Update(1.0 / 60);
        Harness.Check(m.DanceCount == 1 && m.Activity == Activity.Groove,
            "music starts exactly one dance after three steady seconds", $"{m.DanceCount} {m.Activity}");
        m.SetMusic(false, 0, 0);
        for (int i = 0; i < 60 * 31; i++) m.Update(1.0 / 60);
        m.SetMusic(true, 120, 0.9);
        for (int i = 0; i < 30; i++) m.Update(1.0 / 60);
        Harness.Check(m.DanceCount == 1, "the dance cooldown prevents an immediate repeat", $"{m.DanceCount}");

        var (_, noDance) = Scene(147);
        noDance.DanceToMusic = false;
        noDance.SetMusic(true, 120, 0.9);
        for (int i = 0; i < 240; i++) noDance.Update(1.0 / 60);
        Harness.Check(noDance.DanceCount == 0, "Dance to Music off means no dance");

        var (_, dial) = Scene(148);
        dial.Design.Habits.DanceMusic = 0;
        dial.SetMusic(true, 120, 0.9);
        for (int i = 0; i < 240; i++) dial.Update(1.0 / 60);
        Harness.Check(dial.DanceCount == 0, "a zero music-habit dial also means no dance");

        var (_, l) = Scene(149);
        l.SetLocked(true);
        Harness.Check(l.Dormant && l.Activity == Activity.Sleep, "locking the screen puts it to bed");
        l.Update(1.0 / 60);
        l.SetLocked(false);
        Harness.Check(!l.Dormant && l.Activity == Activity.Greet, "unlocking wakes it with a greeting");

        return Harness.Summarise("stage 14 sensing");
    }
}
