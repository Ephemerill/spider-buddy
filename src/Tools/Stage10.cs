using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

public static class Stage10
{
    static (SurfaceMap map, Spider s) Scene(double scale = 0.78)
    {
        var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26));
        var map = Synth.Build(desk, scale);
        var s = new Spider(Sheets.DefaultDesign(), map, new Rng(101)) { UserScale = scale, BrainEnabled = false };
        s.SetAnchor("win:1", 0, 220, 1);
        return (map, s);
    }

    static void KindChecks()
    {
        var kinds = new[]
        {
            (PreyKind.Cricket, 22.0, 5.5, 0.55, 4.0, 1.0),
            (PreyKind.Worm, 24.0, 6.5, 0.60, 2.5, 1.0),
            (PreyKind.FruitFly, 20.0, 3.2, 0.30, 3.0, 1.0),
            (PreyKind.Moth, 26.0, 5.0, 0.50, 2.5, 0.45),
            (PreyKind.Beetle, 22.0, 7.5, 0.70, 3.0, 1.0),
            (PreyKind.Ant, 17.0, 2.4, 0.25, 2.5, 1.0),
            (PreyKind.Mosquito, 17.0, 2.2, 0.25, 4.5, 1.5),
            (PreyKind.Ladybug, 19.0, 1.4, 0.00, 2.5, 0.6),
        };
        bool ok = true;
        foreach (var k in kinds)
        {
            var i = Prey.Info(k.Item1);
            ok &= Math.Abs(i.CatchRadius - k.Item2) < 1e-9 && Math.Abs(i.MealTime - k.Item3) < 1e-9
                && Math.Abs(i.Nourishment - k.Item4) < 1e-9 && Math.Abs(i.Clearance - k.Item5) < 1e-9
                && Math.Abs(i.Wariness - k.Item6) < 1e-9;
        }
        Harness.Check(ok, "all eight kinds carry the exact catch radius, meal time, nourishment and wariness");
        Harness.Check(Prey.Info(PreyKind.Moth).Flies && Prey.Info(PreyKind.Ant).Climbs
            && Prey.Info(PreyKind.Beetle).Armoured && Prey.Info(PreyKind.Ladybug).Bitter,
            "flight, climbing, armour and taste are on the right creatures");

        var rng = new Rng(5);
        int nightMoth = 0, dayLady = 0, rainWorm = 0;
        for (int i = 0; i < 4000; i++)
        {
            if (Prey.WanderingIn(true, false, rng) == PreyKind.Moth) nightMoth++;
            if (Prey.WanderingIn(false, false, rng) == PreyKind.Ladybug) dayLady++;
            if (Prey.WanderingIn(false, true, rng) == PreyKind.Worm) rainWorm++;
        }
        Harness.Check(nightMoth > dayLady && rainWorm > 1200, "wildlife odds favour moths at night and worms in rain",
            $"moth {nightMoth}, lady {dayLady}, worm {rainWorm}");
    }

    static void ReleaseChecks()
    {
        var (_, s) = Scene();
        var cricket = s.ReleasePrey(PreyKind.Cricket);
        var fly = s.ReleasePrey(PreyKind.FruitFly);
        Harness.Check(cricket is { OnSurface: true }, "a cricket is put down on a ledge");
        Harness.Check(fly is { OnSurface: false }, "a fruit fly is let go in the air");
        for (int i = 0; i < 6; i++) s.ReleasePrey(PreyKind.Worm);
        Harness.Check(s.LoosePrey <= 4, "no more than four things are loose at once", $"{s.LoosePrey}");
        s.ClearPrey();
        Harness.Check(s.PreyItems.Count == 0, "everything can be cleared away");
    }

    static void BehaviourChecks()
    {
        var (_, s) = Scene();
        var cricket = s.ReleasePrey(PreyKind.Cricket)!;
        cricket.Pos = s.Pos + new V2(50, 0);
        cricket.OnSurface = true;
        cricket.Timer = 0;
        bool hopped = false;
        for (int i = 0; i < 60 * 12 && !hopped; i++)
        {
            s.Update(1.0 / 60);
            hopped = !cricket.OnSurface && cricket.Vel.Y > 100;
        }
        Harness.Check(hopped, "a cricket hops away when the spider comes close");
        s.ClearPrey();

        var (_, s2) = Scene();
        var worm = s2.ReleasePrey(PreyKind.Worm)!;
        worm.Pos = s2.Pos + new V2(140, 0);
        worm.OnSurface = true;
        worm.Heading = 0;
        worm.Timer = 20;
        V2 w0 = worm.Pos;
        for (int i = 0; i < 60; i++) s2.Update(1.0 / 60);
        double slow = worm.Pos.DistanceTo(w0);
        worm.Pos = s2.Pos + new V2(90, 0);
        V2 w1 = worm.Pos;
        for (int i = 0; i < 60; i++) s2.Update(1.0 / 60);
        double fast = worm.Pos.DistanceTo(w1);
        Harness.Check(fast > slow * 1.25, "a worm inches along and hurries when something big is near",
            $"{slow:0.0} → {fast:0.0}");
        s2.ClearPrey();

        var (_, s3) = Scene();
        s3.SetCursor(s3.Pos + new V2(300, 60));
        var moth = s3.ReleasePrey(PreyKind.Moth)!;
        moth.Pos = s3.Pos + new V2(0, 140);
        moth.Age = 0;
        double before = moth.Pos.DistanceTo(s3.Cursor);
        for (int i = 0; i < 120; i++) s3.Update(1.0 / 60);
        Harness.Check(moth.Pos.DistanceTo(s3.Cursor) < before - 40,
            "a moth is drawn to the pointer like a lamp", $"{before:0.0} → {moth.Pos.DistanceTo(s3.Cursor):0.0}");
        s3.ClearPrey();

        var (_, s4) = Scene();
        var beetle = s4.ReleasePrey(PreyKind.Beetle)!;
        beetle.Pos = s4.Pos + new V2(14, 0);
        beetle.OnSurface = true;
        for (int i = 0; i < 30; i++) s4.Update(1.0 / 60);
        Harness.Check(beetle.Shelled, "a beetle shuts itself in its shell when approached");
        Harness.Check(!s4.TryCatch(beetle) && beetle.Knocks == 1, "and fangs skid off the shell");
        s4.ClearPrey();

        var (_, s5) = Scene();
        var still = s5.ReleasePrey(PreyKind.Mosquito)!;
        still.Pos = s5.Pos + new V2(5, 0);
        still.Vel = V2.Zero;
        bool stillCaught = s5.TryCatch(still);
        var darting = s5.ReleasePrey(PreyKind.Mosquito)!;
        darting.Pos = s5.Pos + new V2(5, 0);
        darting.Vel = new V2(200, 0);
        Harness.Check(stillCaught && !s5.TryCatch(darting),
            "a mosquito is only catchable while it hangs still");
        s5.ClearPrey();

        var (_, s6) = Scene();
        var lady = s6.ReleasePrey(PreyKind.Ladybug)!;
        lady.Pos = s6.Pos + new V2(6, 0);
        lady.OnSurface = true;
        double fedBefore = s6.Fed;
        Harness.Check(s6.TryCatch(lady), "the first ladybug is caught");
        s6.BeginEat(lady);
        for (int i = 0; i < 60 * 3; i++) s6.Update(1.0 / 60);
        Harness.Check(lady.State == PreyState.Loose && lady.Spurned && s6.LearnedBitter && s6.Fed <= fedBefore,
            "tasted and spat out none the worse — and remembered");
        bool caughtAgain = false;
        var lady2 = s6.ReleasePrey(PreyKind.Ladybug)!;
        lady2.Pos = s6.Pos + new V2(6, 0);
        caughtAgain = s6.TryCatch(lady2);
        Harness.Check(!caughtAgain && lady2.Spurned, "afterwards it only watches ladybugs");
        s6.ClearPrey();
    }

    static void HuntChecks()
    {
        var (_, s) = Scene();
        var prey = s.ReleasePrey(PreyKind.Cricket)!;
        prey.Pos = s.Pos + new V2(200, 0);
        prey.OnSurface = true;
        prey.Noticed = true;
        Harness.Check(s.StartHunt(prey), "a noticed creature starts a hunt");
        var seen = new HashSet<HuntStage>();
        for (int i = 0; i < 60 * 30 && prey.State != PreyState.Eaten; i++)
        {
            s.Update(1.0 / 60);
            seen.Add(s.PreyHunt);
        }
        Harness.Check(seen.Contains(HuntStage.Watch) && seen.Contains(HuntStage.Approach),
            "it watches, then walks round to the quarry", string.Join(",", seen));
        Harness.Check(seen.Contains(HuntStage.Stalk), "and stalks the last stretch low and slow");
        Harness.Check(prey.State == PreyState.Eaten, "the catch is carried off and eaten", $"{prey.State} {s.PreyHunt}");
        Harness.Check(s.Fed >= 0.5, "a good meal leaves it well fed", $"{s.Fed:0.00}");
        Harness.Check(s.Fed > 0 && s.Hunger == 0, "feeding in the house leaves the tank's hunger gauge alone");
    }

    static void AmbushChecks()
    {
        var (_, s) = Scene();
        var ant = s.ReleasePrey(PreyKind.Ant)!;
        ant.Pos = s.Pos + new V2(170, 0);
        ant.OnSurface = true;
        ant.Heading = M.Pi;
        ant.Noticed = true;
        s.StartHunt(ant);
        bool ambushed = false, left = false;
        for (int i = 0; i < 60 * 20 && ant.State is PreyState.Loose; i++)
        {
            s.Update(1.0 / 60);
            ambushed |= s.PreyHunt == HuntStage.Ambush;
            left |= s.Mode != Mode.Attached;
        }
        Harness.Check(ambushed && ant.State is PreyState.Caught or PreyState.Eaten,
            "an ant is ambushed from its path, not chased", $"{ambushed} {ant.State} {s.PreyHunt}");
        Harness.Check(!left, "the ambush is made from the ledge, not by leaping");
        s.ClearPrey();

        var (_, b) = Scene();
        var beetle = b.ReleasePrey(PreyKind.Beetle)!;
        beetle.Pos = b.Pos + new V2(100, 0);
        beetle.OnSurface = true;
        beetle.Noticed = true;
        b.StartHunt(beetle);
        bool shelled = false;
        for (int i = 0; i < 60 * 35 && beetle.State != PreyState.Eaten; i++)
        {
            b.Update(1.0 / 60);
            shelled |= beetle.Shelled;
        }
        Harness.Check(shelled && beetle.State == PreyState.Eaten,
            "a beetle clams up; the spider waits it out and eats", $"{shelled} {beetle.State} {b.PreyHunt}");
        b.ClearPrey();
    }

    static void WildlifeChecks()
    {
        var (_, s) = Scene();
        s.WildlifeEnabled = true;
        s.WildlifeFrequency = 600;
        s.WildlifeIn = 0.1;
        s.IdleFor = 40;
        for (int i = 0; i < 120; i++) s.Update(1.0 / 60);
        Harness.Check(s.PreyItems.Count > 0, "with wildlife on, a creature wanders in", $"{s.PreyItems.Count}");

        s.ClearPrey();
        s.UserIdleFor = 600;
        s.WildlifeIn = 0.05;
        for (int i = 0; i < 180; i++) s.Update(1.0 / 60);
        Harness.Check(s.PreyItems.Count == 0, "nothing wanders in while nobody is at the machine");

        s.UserIdleFor = 0;
        var ants = s.ReleaseWildlife(PreyKind.Ant);
        Harness.Check(ants.Count >= 3 && ants.All(a => a.Kind == PreyKind.Ant),
            "ants come in a little line", $"{ants.Count}");
        s.ClearPrey();

        var moth = s.ReleaseWildlife(PreyKind.Moth).First();
        var bounds = s.Map.WorldBounds;
        bool atSide = Math.Abs(moth.Pos.X - bounds.MinX) < 12 || Math.Abs(moth.Pos.X - bounds.MaxX) < 12;
        Harness.Check(atSide && !moth.OnSurface, "a wild flier enters through the side of the screen", $"{moth.Pos}");

        s.WildlifeEnabled = false;
        moth.LeaveAfter = 10;
        moth.Age = 11;
        s.Update(1.0 / 60);
        Harness.Check(!s.PreyItems.Contains(moth), "an uncaught creature eventually leaves");
        s.ClearPrey();
    }

    public static int Run(string[] args)
    {
        Harness.Section("stage 10 prey: eight kinds, the hunt, feeding, wildlife");
        KindChecks();
        ReleaseChecks();
        BehaviourChecks();
        HuntChecks();
        AmbushChecks();
        WildlifeChecks();
        return Harness.Summarise("stage 10 prey");
    }
}
