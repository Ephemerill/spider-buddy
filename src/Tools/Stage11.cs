using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

public static class Stage11
{
    static (SurfaceMap map, Spider s) Scene(double scale = 0.78)
    {
        var desk = Synth.Desktop()
            .With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26))
            .With(Synth.Window(2, 100, 100, 1400, 300, 1, "lower", corner: 20));
        var map = Synth.Build(desk, scale);
        var s = new Spider(Sheets.DefaultDesign(), map, new Rng(111)) { UserScale = scale, BrainEnabled = false };
        s.SetAnchor("win:1", 0, 220, 1);
        return (map, s);
    }

    static void TableChecks()
    {
        var b = ToyTable.For(ToyKind.Ball);
        var f = ToyTable.For(ToyKind.Feather);
        var bell = ToyTable.For(ToyKind.Bell);
        var bug = ToyTable.For(ToyKind.Bug);
        bool ok = b.Radius == 7 && b.Restitution == 0.72 && b.Mass == 1 && b.EdgeDrag == 0.6 && b.Brake == 30
            && b.GravityShare == 1 && b.AirDrag == 0.12 && b.Rolls && b.Tether == 0 && b.Lure == 1
            && b.LoftMin == 0.15 && b.LoftMax == 0.7;
        ok &= f.Radius == 9 && f.Restitution == 0.05 && f.Mass == 0.35 && f.EdgeDrag == 6 && f.Brake == 220
            && f.GravityShare == 0.09 && f.AirDrag == 2.6 && !f.Rolls && f.Tether == 105 && f.Lure == 1.15
            && f.LoftMin == 0.9 && f.LoftMax == 1.3;
        ok &= bell.Radius == 6.5 && bell.Restitution == 0.42 && bell.Mass == 1.7 && bell.EdgeDrag == 0.9
            && bell.Brake == 40 && bell.GravityShare == 1 && bell.Rolls && bell.Lure == 0.9
            && bell.LoftMin == 0.05 && bell.LoftMax == 0.35;
        ok &= bug.Radius == 7.5 && bug.Restitution == 0.22 && bug.Mass == 1.3 && bug.EdgeDrag == 4
            && bug.Brake == 160 && bug.GravityShare == 1 && !bug.Rolls && bug.Lure == 1.1
            && bug.LoftMin == 0 && bug.LoftMax == 0.15;
        Harness.Check(ok, "all four toy bodies carry the exact Stage 11.2 numbers");
        Harness.Check(ToyTable.For(ToyKind.Laser).Radius < 4, "the laser dot is a small point, not a body");
    }

    static void HandChecks()
    {
        var (_, s) = Scene();
        bool menu = false;
        s.ContextMenuRequested += () => menu = true;
        s.PickToy(ToyKind.Bell);
        s.PickToy(ToyKind.Ball);
        Harness.Check(s.HandToy == ToyKind.Ball && s.HandObject?.Kind == ToyKind.Ball,
            "picking a second toy leaves exactly one in hand");
        Harness.Check(s.ToyCatchesPointer, "a toy on the pointer catches clicks");
        s.RightClick();
        Harness.Check(s.HandToy == ToyKind.None && !menu && !s.ToyCatchesPointer,
            "right-click puts the toy away instead of opening the menu");

        s.PickToy(ToyKind.Laser);
        Harness.Check(s.HandToy == ToyKind.Laser && s.LaserPos == s.Cursor, "the red dot sits on the pointer");
        s.Escape();
        Harness.Check(s.HandToy == ToyKind.None && s.ToyPuzzledUntil > s.Time,
            "Esc puts it away and the spider is left puzzled");
    }

    static void LaserChecks()
    {
        var (_, s) = Scene();
        s.SetCursor(s.Pos + new V2(210, 0));
        s.PickToy(ToyKind.Laser);
        var start = s.Pos;
        bool scurried = false;
        for (int i = 0; i < 180; i++)
        {
            s.Update(1.0 / 60);
            scurried |= s.Activity == Activity.Scurry;
        }
        Harness.Check(s.Pos.DistanceTo(start) > 100, "the spider races after the laser dot",
            $"{s.Pos.DistanceTo(start):0.0}");
        Harness.Check(scurried, "it scurries along its edge to get there");
        Harness.Check(s.ToyPats > 0, "and pats at the dot when it arrives", $"{s.ToyPats}");
        s.PutAwayToy();
        Harness.Check(s.Emote == PointerEmote.Question && s.ToyPuzzledUntil > s.Time,
            "put away, it looks about for the dot, puzzled");
    }

    static void FeatherChecks()
    {
        var (_, s) = Scene();
        s.SetCursor(s.Pos + new V2(120, 100));
        s.PickToy(ToyKind.Feather);
        for (int i = 0; i < 60; i++) s.Update(1.0 / 60);
        double d1 = s.HandObject!.Pos.DistanceTo(s.Cursor);
        Harness.Check(d1 <= 105 * s.Scale + 1 && d1 > 20, "the feather dangles on its 105-unit string",
            $"{d1:0.0}");
        V2 before = s.HandObject.Pos;
        s.SetCursor(s.Cursor + new V2(140, 20));
        for (int i = 0; i < 45; i++) s.Update(1.0 / 60);
        Harness.Check(s.HandObject.Pos != before && s.HandObject.Pos.DistanceTo(s.Cursor) <= 105 * s.Scale + 1,
            "it trails behind as the pointer moves");

        var (_, f) = Scene();
        var feather = f.AddToy(ToyKind.Feather, new V2(600, 1000));
        var ball = f.AddToy(ToyKind.Ball, new V2(700, 1000));
        V2 f0 = feather.Pos, b0 = ball.Pos;
        for (int i = 0; i < 12; i++) f.Update(1.0 / 60);
        Harness.Check(feather.Pos.DistanceTo(f0) < ball.Pos.DistanceTo(b0) * 0.6,
            "the feather floats down far slower than the ball",
            $"{feather.Pos.DistanceTo(f0):0.0} vs {ball.Pos.DistanceTo(b0):0.0}");
    }

    static void BallChecks()
    {
        var (_, s) = Scene();
        double top = s.Pos.Y;
        var ball = s.AddToy(ToyKind.Ball, new V2(600, 1100));
        bool bounced = false;
        double highest = 0;
        for (int i = 0; i < 360; i++)
        {
            s.Update(1.0 / 60);
            if (ball.Vel.Y > 20) { bounced = true; highest = Math.Max(highest, ball.Vel.Y); }
        }
        Harness.Check(ball.OnSurface && Math.Abs(ball.Pos.Y - top) < 3,
            "a ball falls onto the window top and settles", $"{ball.Pos} {ball.OnSurface}");
        Harness.Check(bounced, "it bounces on impact", $"{highest:0.0}");

        var (_, r) = Scene();
        var roller = r.AddToy(ToyKind.Ball, new V2(600, 800));
        roller.OnSurface = true;
        roller.Vel = new V2(300, 0);
        for (int i = 0; i < 30; i++) r.Update(1.0 / 60);
        Harness.Check(Math.Abs(roller.Vel.X) < 300 && roller.OnSurface, "edge drag and brake slow a rolling ball",
            $"{roller.Vel.X:0.0}");

        // Roll it off the nearest end of the window top; the lower window catches it.
        var (_, e) = Scene();
        var edge = e.AddToy(ToyKind.Ball, new V2(1000, 800));
        edge.OnSurface = true;
        var spot = e.Map.NearestSpot(edge.Pos, 20, null, e.Scale) ?? throw new Exception("no ledge under the ball");
        var seg = e.Map.Loop(spot.LoopId)!.SegAt(spot.SegIdx);
        V2 tangent = (seg.B - seg.A).Normalized;
        edge.Pos = tangent.X > 0 ? new V2(1000, 800) : new V2(300, 800);
        edge.Vel = tangent * 300;
        bool onLower = false;
        for (int i = 0; i < 60 * 8; i++)
        {
            e.Update(1.0 / 60);
            if (edge.Pos.Y > 380 && edge.Pos.Y < 500) onLower = true;
        }
        Harness.Check(onLower, "a ball rolls off a window top and bounces onto the ledge below", $"{edge.Pos}");

        var (_, t) = Scene();
        var thrown = t.AddToy(ToyKind.Ball, new V2(600, 900));
        t.ThrowToy(thrown, new V2(5000, 100));
        Harness.Check(thrown.Vel.Length <= Spider.MaxThrowSpeed + 1e-6, "a flick cannot throw a toy faster than the cap",
            $"{thrown.Vel.Length:0}");
        Harness.Check(t.PickToy(ToyKind.Ball), "the ball can be picked up again");
        t.PlaceToy();
        Harness.Check(t.HandToy == ToyKind.None && t.Toys.Count > 0, "a click puts the hand toy down");
    }

    static void BellBugChecks()
    {
        var (_, s) = Scene();
        int chimes = 0;
        s.ToySound += k => { if (k == ToyKind.Bell) chimes++; };
        var bell = s.AddToy(ToyKind.Bell, new V2(600, 1200));
        for (int i = 0; i < 240; i++) s.Update(1.0 / 60);
        Harness.Check(chimes > 0, "the bell jingles when it lands", $"{chimes}");

        int muted = 0;
        s.ToySounds = false;
        s.ToySound += _ => muted++;
        s.PokeToy(bell);
        Harness.Check(muted == 0, "Bell Sound off keeps it quiet");

        var (_, b) = Scene();
        var bug = b.AddToy(ToyKind.Bug, new V2(600, 800));
        bug.OnSurface = true;
        bug.Wound = 8;
        double x0 = bug.Pos.X;
        for (int i = 0; i < 60; i++) b.Update(1.0 / 60);
        Harness.Check(Math.Abs(bug.Pos.X - x0) > 20 && bug.Wound < 8,
            "the wind-up bug scuttles off on its own", $"{bug.Pos.X - x0:0.0} {bug.Wound:0.0}");
        for (int i = 0; i < 60 * 10; i++) b.Update(1.0 / 60);
        Harness.Check(bug.Wound == 0, "and runs down");

        var (_, bat) = Scene();
        var toy = bat.AddToy(ToyKind.Ball, bat.Pos + new V2(40, 0));
        bool swung = bat.BatToy(toy);
        double loft = Math.Atan2(toy.Vel.Y, Math.Abs(toy.Vel.X));
        Harness.Check(swung && loft >= 0.14 && loft <= 0.71 && toy.Vel.Y > 0,
            "a pat lofts the ball within its bat range", $"{loft:0.00}");
        Harness.Check(bat.FavouriteToy == "toy.Ball", "playing remembers a favourite toy");
        Harness.Check(bat.PreyItems.Count == 0 && bat.FindQuarry() is null, "toys are never prey");
    }

    public static int Run(string[] args)
    {
        Harness.Section("stage 11 toys: hand, laser, feather, ball, bell, bug");
        TableChecks();
        HandChecks();
        LaserChecks();
        FeatherChecks();
        BallChecks();
        BellBugChecks();
        return Harness.Summarise("stage 11 toys");
    }
}
