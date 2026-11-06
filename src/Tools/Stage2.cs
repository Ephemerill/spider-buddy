using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

/// <summary>
/// Stage 2 acceptance (spec 2 "Done when"):
///  - loops follow windows live with no drift;
///  - a window dragged in front blocks exactly the covered stretches (+1.4×standoff grow);
///  - a maximised front window produces cinema loops (floor + ceiling only), and with a second
///    window in front it produces no loop but still occludes;
///  - a synthetic desktop feeds the same rebuild.
/// Plus the model facts of 2.3, the resolve rules of 2.5 and the queries of 2.6.
/// </summary>
public static class Stage2
{
    public static int Run(string[] args)
    {
        SegChecks();
        ScreenLoopChecks();
        WindowLoopChecks();
        BlockChecks();
        ResolveChecks();
        QueryChecks();
        CinemaChecks();
        ConfineChecks();
        DriftChecks();
        return Harness.Summarise("stage 2 surfaces");
    }

    // ------------------------------------------------------------------ seg model

    static void SegChecks()
    {
        Harness.Section("seg model (spec 2.3)");

        // The ordering rule: normal == dir rotated +90 CCW, else the endpoints swap.
        foreach (var (a, b, facing) in new[]
        {
            (new V2(0, 10), new V2(10, 10), EdgeFacing.Up),
            (new V2(10, 10), new V2(10, 0), EdgeFacing.Right),
            (new V2(10, 0), new V2(0, 0), EdgeFacing.Down),
            (new V2(0, 0), new V2(0, 10), EdgeFacing.Left),
        })
        {
            var s = new Seg(a, b, facing);
            Harness.Check(Math.Abs(s.Dir.Perp.Dot(s.Normal) - 1) < 1e-9,
                $"normal == dir rotated +90 CCW ({facing})", $"dot {s.Dir.Perp.Dot(s.Normal):0.###}");
            Harness.Check(s.Normal == facing.Normal(), $"normal points {facing}");
        }

        // Reversed input must be fixed by swapping, not silently left upside down.
        var backwards = new Seg(new V2(10, 10), new V2(0, 10), EdgeFacing.Up);
        Harness.Check(backwards.Dir.Perp.Dot(backwards.Normal) > 0, "reversed endpoints are swapped to fix the frame");
        Harness.Check(backwards.A.DistanceTo(new V2(0, 10)) < 1e-9, "swap moved A to the correct end");

        var seg = new Seg(new V2(0, 0), new V2(100, 0), EdgeFacing.Up);
        Harness.Near(seg.Len, 100, 1e-9, "seg length");
        Harness.Check(seg.Point(50).DistanceTo(new V2(50, 0)) < 1e-9, "seg.point(t)");
        Harness.Check(seg.Point(-10).DistanceTo(new V2(0, 0)) < 1e-9, "seg.point clamps t low");
        Harness.Check(seg.Point(500).DistanceTo(new V2(100, 0)) < 1e-9, "seg.point clamps t high");
        Harness.Near(seg.Limit(20, 1), 80, 1e-9, "limit forward from 20");
        Harness.Near(seg.Limit(20, -1), 20, 1e-9, "limit backward from 20");

        seg.Block(30, 50);
        Harness.Check(seg.IsBlocked, "block marks the seg");
        Harness.Near(seg.Limit(10, 1), 20, 1e-9, "limit stops at the block");
        Harness.Near(seg.Limit(70, -1), 20, 1e-9, "limit backward stops at the block");
        Harness.Check(!seg.IsOpen(40), "a blocked t is closed");
        Harness.Check(seg.IsOpen(20) && seg.IsOpen(60), "t either side is open");

        // ranges are sorted and merged
        seg.Block(10, 20);
        seg.Block(20, 25);
        Harness.Check(seg.Blocked.Count == 2, "overlapping blocks merge", $"got {seg.Blocked.Count}");
        Harness.Near(seg.Blocked[0].Lo, 10, 1e-9, "merged block starts at the lowest");
        Harness.Near(seg.Blocked[0].Hi, 25, 1e-9, "merged block ends at the highest");
        Harness.Check(seg.IsOpen(27), "the gap after a merged block is open");

        // span() clips into a rect
        var longSeg = new Seg(new V2(-50, 50), new V2(150, 50), EdgeFacing.Up);
        longSeg.Span(new Rect(0, 0, 100, 100), out double t0, out double t1);
        Harness.Near(t0, 50, 1e-6, "span t0");
        Harness.Near(t1, 150, 1e-6, "span t1");

        Harness.Near(SurfaceMap.StandoffFor(1.0), 22, 1e-12, "standoff at scale 1 is 22");
        Harness.Near(SurfaceMap.StandoffFor(0.62), 13.64, 1e-9, "standoff at Tiny");
        Harness.Near(SurfaceMap.StandoffFor(1.55), 34.1, 1e-9, "standoff at Chonky");
        Harness.Near(SurfaceKind.WindowEdge.Appeal(), 1.7, 0, "windowEdge appeal");
        Harness.Near(SurfaceKind.ScreenBorder.Appeal(), 1.0, 0, "screenBorder appeal");
        Harness.Check(SurfaceKind.WindowEdge.OnWindow() && !SurfaceKind.ScreenBorder.OnWindow(), "only window edges can be covered");
        Harness.Check(!SurfaceKind.MenuBar.OnWindow() && !SurfaceKind.Dock.OnWindow(), "menu bar and dock are glass in front of everything");
    }

    // ------------------------------------------------------------------ screen rim

    static void ScreenLoopChecks()
    {
        Harness.Section("the screen rim (spec 2.4.3, 2.8)");

        var m = Synth.Build(Synth.Desktop());
        Harness.Check(m.LoopCount == 1, "one loop for one screen", $"got {m.LoopCount}");
        var loop = Synth.LoopStartingWith(m, "screen:0")!;
        Harness.Check(loop is not null, "screen border loop exists");
        Harness.Check(loop.Closed, "the Windows rim is a closed rectangle (no menu bar)");
        Harness.Check(loop.Segs.Count == 4, "four sides", $"got {loop.Segs.Count}");
        Harness.Check(loop.Kind == SurfaceKind.ScreenBorder, "kind is screenBorder");
        Harness.Near(m.Standoff, Synth.Standoff, 1e-9, "standoff = 22 × 0.78");

        // Layout order on the rim is floor, right wall, ceiling, left wall (spec 2.4.3).
        var floor = loop.Segs[0];
        Harness.Near(floor.A.Y, 40 + Synth.Standoff, 1e-9, "floor sits one standoff above the taskbar top");
        Harness.Check(floor.Facing == EdgeFacing.Up, "floor faces up");
        Harness.Near(Math.Min(floor.A.X, floor.B.X), Synth.Standoff, 1e-9, "floor starts one standoff in");
        Harness.Near(Math.Max(floor.A.X, floor.B.X), 1920 - Synth.Standoff, 1e-9, "floor ends one standoff in");

        // walls and ceiling — rim normals point INWARD (the spider stands inside the screen)
        var right = loop.Segs[1];
        var ceiling = loop.Segs[2];
        var left = loop.Segs[3];
        Harness.Check(right.Facing == EdgeFacing.Left, "right wall faces left (inward)");
        Harness.Check(ceiling.Facing == EdgeFacing.Down, "ceiling faces down (a place to hang from)");
        Harness.Check(left.Facing == EdgeFacing.Right, "left wall faces right (inward)");
        Harness.Near(right.A.X, 1920 - Synth.Standoff, 1e-9, "right wall rides one standoff inside the edge");
        Harness.Near(left.A.X, Synth.Standoff, 1e-9, "left wall rides one standoff inside the edge");
        Harness.Near(ceiling.A.Y, 1080 - Synth.Standoff, 1e-9, "ceiling is one standoff below the screen top");

        // consecutive segs share a vertex exactly (no drift round the rim)
        for (int i = 0; i < loop.Segs.Count; i++)
        {
            var a = loop.Segs[i].B;
            var b = loop.Segs[(i + 1) % loop.Segs.Count].A;
            Harness.Check(a.DistanceTo(b) < 1e-9, $"seg {i} joins seg {(i + 1) % 4} exactly");
        }

        // renderer frame check: the sprite's +x is the seg dir and +y the outward normal
        Harness.Check(Math.Abs(floor.Dir.Cross(floor.Normal) - 1) < 1e-9, "sprite frame is right-handed (dir × normal = +1)");

        // the rim is never blocked, whatever windows are about
        var desk = Synth.Desktop().With(Synth.Window(1, 0, 0, 1920, 1080));
        var m2 = Synth.Build(desk);
        var rim2 = Synth.LoopStartingWith(m2, "screen:0")!;
        Harness.Check(rim2.Segs.All(s => !s.IsBlocked), "a window covering the screen never blocks the rim");

        // a tiny screen has nowhere to walk
        var tiny = Synth.Desktop(30, 24);
        var m3 = Synth.Build(tiny);
        var tinyLoop = Synth.LoopStartingWith(m3, "screen:0")!;
        Harness.Check(tinyLoop.Segs.Count == 0, "a screen smaller than 2×standoff produces no rim");
    }

    // ------------------------------------------------------------------ window loops

    static void WindowLoopChecks()
    {
        Harness.Section("window loops (spec 2.4)");

        var desk = Synth.Desktop().With(Synth.Window(7, 200, 300, 600, 400, 0, "notepad", corner: 26));
        var m = Synth.Build(desk);
        var loop = m.Loop("win:7")!;
        Harness.Check(loop is not null, "a window produces a loop");
        Harness.Check(loop.Closed, "window loop is closed");
        Harness.Check(loop.Segs.Count == 4, "four sides");
        Harness.Check(loop.Depth == 0, "depth is carried through");
        Harness.Near(loop.CornerRadius, 26, 1e-9, "corner radius carried through");
        Harness.Check(loop.IsWindowRect, "marked as a rounded window rect");

        // grown outward by the standoff
        var top = loop.Segs[0];
        Harness.Near(top.A.Y, 300 + 400 + Synth.Standoff, 1e-9, "top seg rides one standoff above the window top");
        Harness.Near(Math.Min(top.A.X, top.B.X), 200 - Synth.Standoff, 1e-9, "top seg starts one standoff left");
        Harness.Near(Math.Max(top.A.X, top.B.X), 800 + Synth.Standoff, 1e-9, "top seg ends one standoff right");
        Harness.Check(top.Facing == EdgeFacing.Up, "top is a shelf");
        Harness.Check(loop.Segs[2].Facing == EdgeFacing.Down, "bottom is a ceiling to hang from");

        // the real edge exists and is rounded
        Harness.Check(loop.Edge.Count > 8, "edge polyline is sampled", $"{loop.Edge.Count} points");
        Harness.Check(loop.Edge.All(p => p.X >= 200 - 1e-6 && p.X <= 800 + 1e-6), "edge stays on the real window");
        Harness.Near(Math.Round(loop.Edge.Max(p => p.Y), 6), 700, 1e-6, "edge reaches the real top");

        // corner radius is clamped to half the window
        var squat = Synth.Build(Synth.Desktop().With(Synth.Window(8, 0, 100, 200, 120, 0, "x", corner: 500)));
        var squatLoop = squat.Loop("win:8");
        Harness.Check(squatLoop is not null, "a 200×120 window is furniture");
        if (squatLoop is not null) Harness.Near(squatLoop.CornerRadius, 60, 1e-9, "corner radius clamped to min(w,h)/2");

        // windows under 130×90 are decoration
        var small = Synth.Build(Synth.Desktop().With(Synth.Window(9, 10, 10, 120, 80)));
        Harness.Check(small.Loop("win:9") is null, "a window under 130×90 is not furniture");
        var bigEnough = Synth.Build(Synth.Desktop().With(Synth.Window(10, 10, 10, 131, 91)));
        Harness.Check(bigEnough.Loop("win:10") is not null, "131×91 is furniture");

        // up to 28 windows, front to back, all kept
        var many = Synth.Desktop();
        for (int i = 0; i < 28; i++) many.With(Synth.Window(100 + i, i * 3, 100 + i * 2, 400, 300, i));
        var mm = Synth.Build(many);
        int windowLoops = mm.AllLoops.Count(l => l.Kind == SurfaceKind.WindowEdge);
        Harness.Check(windowLoops == 28, "all 28 windows are kept", $"got {windowLoops}");
    }

    // ------------------------------------------------------------------ blocks / occlusion

    static void BlockChecks()
    {
        Harness.Section("occlusion and blocks (spec 2.4)");

        // A in front (depth 0) covering the left part of B (depth 1).
        var desk = Synth.Desktop()
            .With(Synth.Window(1, 100, 100, 400, 300, 0, "front"))
            .With(Synth.Window(2, 300, 100, 400, 300, 1, "back"));
        var m = Synth.Build(desk);
        var back = m.Loop("win:2")!;
        var topSeg = back.Segs[0];

        Harness.Check(topSeg.IsBlocked, "the back window's top edge is blocked by the window in front");

        // grown rect of A by standoff*1.4 = 24.024 → right edge at 500 + 24.024
        double grownRight = 500 + Synth.Standoff * 1.4;
        double segStart = 300 - Synth.Standoff;
        double expected = grownRight - segStart;
        Harness.Near(topSeg.Blocked[0].Lo, 0, 1e-6, "the block starts at the seg's start");
        Harness.Near(topSeg.Blocked[0].Hi, expected, 0.01, "the block ends at the 1.4×standoff grown edge");

        // The far end of the same edge is open.
        Harness.Check(topSeg.IsOpen(topSeg.Len - 1), "the uncovered end of the edge stays open");

        // The front window's own loop is not blocked by anything.
        var front = m.Loop("win:1")!;
        Harness.Check(m.Loop("win:1")!.Segs.All(s => !s.IsBlocked), "the frontmost window's edges are clear");

        // A point of the back window that lies under the window in front is not visible.
        Harness.Check(!m.IsVisible(new V2(200, 200), 1), "a point under the front window is not visible to the back window");
        Harness.Check(m.IsVisible(new V2(700, 200), 1), "a point clear of the front window is visible");
        Harness.Check(m.IsVisible(new V2(200, 200), 0), "the front window sees everything on itself");
        Harness.Check(!m.IsClear(new V2(520, 200), 1, 30), "isClear rejects points within a margin of a window in front");

        // No line may fasten to a covered stretch (spec 7.6).
        Harness.Check(!m.CanHold("win:2", 0, 10), "a line cannot fasten to a covered stretch");
        Harness.Check(m.CanHold("win:2", 0, topSeg.Len - 10), "a line can fasten to an open stretch");
        Harness.Check(m.CanHold("screen:0", 0, 100), "a line can always fasten to the rim");
        Harness.Check(!m.CanHold("win:2", 9, 0), "an out-of-range seg cannot hold a line");

        // Occluders are front-to-back.
        Harness.Check(m.Occluders.Count == 2 && m.OccluderDepths[0] == 0, "occluders are ordered front to back");
        Harness.Check(m.DepthAt(new V2(150, 200)) == 0, "depth at a point inside the front window");
        Harness.Check(m.DepthAt(new V2(1500, 200)) == int.MaxValue, "depth outside every window is unbounded");
    }

    // ------------------------------------------------------------------ resolve

    static void ResolveChecks()
    {
        Harness.Section("resolve — a position on the surface (spec 2.5)");

        var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 600, 400, 0, "w", corner: 26));
        var m = Synth.Build(desk);
        var loop = m.Loop("win:1")!;
        double crReach = 38 * Synth.Scale;

        // Flat middles are untouched: the resolved point equals the segment point exactly.
        var anchor = new Anchor("win:1", 0, loop.Segs[0].Len / 2, 1);
        var sp = m.Resolve(anchor, crReach);
        Harness.Check(sp.Pos.DistanceTo(loop.Segs[0].Point(loop.Segs[0].Len / 2)) < 1e-12, "flat middle is byte-identical to the straight path");
        Harness.Near(sp.Normal.Y, 1, 1e-12, "flat middle normal is straight up");
        Harness.Check(sp.Tangent.DistanceTo(loop.Segs[0].Dir) < 1e-12, "flat middle tangent is the seg direction");

        // At the corner the body path is an arc of radius windowCornerRadius + standoff about the
        // window's corner centre.
        double rr = 26 + Synth.Standoff;
        var cornerAnchor = new Anchor("win:1", 0, loop.Segs[0].Len, 1);     // the very corner (top-right)
        var cp = m.Resolve(cornerAnchor, crReach);
        V2 centre = new(800 - 26, 700 - 26);
        Harness.Near(cp.Pos.DistanceTo(centre), rr, 1e-6, "corner body path is at windowCornerRadius + standoff from the corner centre");
        Harness.Check(cp.Normal.Length is > 0.99 and < 1.01, "corner normal is a unit vector");

        // The arc must not lift the body beyond the standoff off the real edge (the 1.6× bug).
        Harness.Check(cp.Pos.DistanceTo(loop.Segs[0].Point(loop.Segs[0].Len)) < 20,
            "the corner arc stays near the corner, not 1.6× out");

        // The last anchor of one side and the first of the next resolve to the same place.
        var endOfTop = m.Resolve(new Anchor("win:1", 0, loop.Segs[0].Len, 1), crReach).Pos;
        var startOfRight = m.Resolve(new Anchor("win:1", 1, 0, 1), crReach).Pos;
        Harness.Check(endOfTop.DistanceTo(startOfRight) < 1e-6, "the corner joins without a jump");

        // Feet land on the real edge, not the body path.
        var edgePoint = loop.SnapToEdge(new V2(200 - 5, 500));
        Harness.Near(edgePoint.X, 200, 1e-6, "snapToEdge puts feet back on the real edge");
        var roundedEdge = loop.OnRoundedCorner(new V2(200, 700));
        Harness.Near(roundedEdge.point.DistanceTo(new V2(200 + 26, 700 - 26)), 26, 1e-6, "onRoundedCorner projects onto the real corner arc");

        // Turning: the tangent flips with the walking direction.
        var back = m.Resolve(new Anchor("win:1", 0, 100, -1), crReach);
        var fwd = m.Resolve(new Anchor("win:1", 0, 100, 1), crReach);
        Harness.Check(back.Tangent.DistanceTo(-fwd.Tangent) < 1e-12, "anchor direction flips the tangent");
        Harness.Check(back.Normal.DistanceTo(fwd.Normal) < 1e-12, "anchor direction does not change the normal");

        // An open-run (cinema floor) resolves without corner rounding.
        var cinema = Synth.Build(Synth.Desktop().Cinema());
        var floorLoop = cinema.AllLoops.First(l => l.Id.Contains("cinema:floor"));
        var fp = cinema.Resolve(new Anchor(floorLoop.Id, 0, 1, 1), crReach);
        Harness.Near(fp.Pos.Y, 0 + Synth.Standoff, 1e-6, "cinema floor is one standoff above the display bottom");

        // Hanging under a window: the normal points down, so the sprite frame is rotated by pi.
        var under = m.Resolve(new Anchor("win:1", 2, 100, 1), crReach);
        Harness.Near(under.Normal.Y, -1, 1e-12, "under the window the normal points down");
        Harness.Near(Math.Abs(M.WrapPi(under.Normal.Angle - M.Pi / 2)), M.Pi, 1e-9, "the frame is upside down on an underside");
        Harness.Check(Math.Abs(under.Tangent.Y) < 1e-12, "the tangent stays along the edge when hanging");

        // Degenerate anchors never throw or produce NaN.
        Harness.Check(!m.Resolve(new Anchor("nope", 0, 0, 1), crReach).IsValid, "unknown loop resolves to an invalid point");
        var badSeg = m.Resolve(new Anchor("win:1", 99, 0, 1), crReach);
        Harness.Check(!badSeg.IsValid || badSeg.Pos.IsFinite, "out-of-range seg index is survivable");
    }

    // ------------------------------------------------------------------ queries

    static void QueryChecks()
    {
        Harness.Section("queries the spider needs (spec 2.6)");

        var desk = Synth.Desktop().With(Synth.Window(1, 400, 400, 800, 500, 0, "w"));
        var m = Synth.Build(desk);

        // sampleSpots
        var spots = m.SampleSpots(34, false, Synth.Scale);
        Harness.Check(spots.Count > 20, "sampleSpots finds many spots", $"{spots.Count}");
        Harness.Check(spots.All(s => s.LoopId.Length > 0 && s.Point.IsFinite), "every spot is finite and owned");
        Harness.Check(spots.Any(s => s.Kind == SurfaceKind.WindowEdge), "window spots are offered");
        Harness.Check(spots.Any(s => s.Kind == SurfaceKind.ScreenBorder), "rim spots are offered");

        // spacing: consecutive interior spots on the longest seg are about 34 apart
        // (the two end spots are pulled in by corner rounding, so they are excluded)
        var topSpots = spots.Where(s => s.LoopId == "win:1" && s.SegIdx == 0).Select(s => s.Point).ToList();
        Harness.Check(topSpots.Count >= 3, "the window top is sampled");
        bool spaced = true;
        for (int i = 2; i < topSpots.Count - 1; i++)
            if (topSpots[i].DistanceTo(topSpots[i - 1]) > 36 || topSpots[i].DistanceTo(topSpots[i - 1]) < 32) spaced = false;
        Harness.Check(spaced, "spot spacing is ~34 units");

        // nearestSpot
        var near = m.NearestSpot(new V2(800, 917), 60, null, Synth.Scale);
        Harness.Check(near is not null, "nearestSpot finds a spot on the window top");
        Harness.Check(near!.Value.Point.Y > 890, "the nearest spot is on the top edge", $"{near.Value.Point}");

        // ceiling: the window's underside is a hangable ceiling above a point under it
        var ceil = m.Ceiling(new V2(800, 100), 900);
        Harness.Check(ceil.Found, "ceiling above a point under the window is found");
        Harness.Near(ceil.Point.Y, 400 - Synth.Standoff, 1e-6, "the ceiling is the window's underside");
        Harness.Check(!m.Ceiling(new V2(800, 100), 100).Found, "maxRise limits the search");
        var noneAbove = m.Ceiling(new V2(800, 900), 900);
        Harness.Check(noneAbove.LoopId.Length > 0, "the screen ceiling is found above the window");

        // landingBelow: the window top is what you land on from above
        Harness.Near(m.LandingBelow(new V2(800, 950)), 900 + Synth.Standoff, 1e-6, "landing below a point above the window is the window top");
        Harness.Near(m.LandingBelow(new V2(100, 950)), 40 + Synth.Standoff, 1e-6, "landing beside the window is the floor");
        Harness.Near(m.LandingBelow(new V2(800, 300)), 40 + Synth.Standoff, 1e-6, "below the window you land on the floor");
        Harness.Check(double.IsNaN(m.LandingBelow(new V2(800, 50))), "below the floor there is nothing to land on");

        // screen helpers
        Harness.Check(m.IsOnScreen(new V2(800, 500)), "a point on screen");
        Harness.Check(!m.IsOnScreen(new V2(5000, 500)), "a point off screen");
        Harness.Check(m.ScreenFrameContaining(new V2(800, 500))?.Id == "screen:0", "screen frame containing a point");
        Harness.Check(!m.IsCinema(new V2(800, 500)), "not cinema by default");

        // owner
        Harness.Check(m.OwnerOf("win:1", 0) == 0, "desktop loops have owner 0");

        // bounds
        Harness.Check(m.BoundsAround(new V2(800, 500)).W > 700, "bounds around a point on the window");

        // habitatCopy is deep
        var copy = m.HabitatCopy();
        copy.Loop("win:1")!.Segs[0].Block(0, 10);
        Harness.Check(!m.Loop("win:1")!.Segs[0].IsBlocked, "habitatCopy is a deep copy");
        Harness.Check(copy.Generation == m.Generation, "generation is carried into the copy");
    }

    // ------------------------------------------------------------------ cinema

    static void CinemaChecks()
    {
        Harness.Section("cinema manners (spec 2.7, 2.4)");

        var cinema = Synth.Build(Synth.Desktop().Cinema());
        var loops = cinema.AllLoops.ToList();
        Harness.Check(loops.Count == 2, "cinema leaves only a floor and a ceiling", $"got {loops.Count}");
        var floor = loops.First(l => l.Id.Contains("floor"));
        var ceil = loops.First(l => l.Id.Contains("ceiling"));
        Harness.Check(!floor.Closed && !ceil.Closed, "cinema loops are open runs");
        Harness.Check(floor.Segs.Count == 1 && ceil.Segs.Count == 1, "one seg each");
        Harness.Check(floor.Segs[0].Facing == EdgeFacing.Up, "cinema floor faces up");
        Harness.Check(ceil.Segs[0].Facing == EdgeFacing.Down, "cinema ceiling faces down");
        Harness.Near(ceil.Segs[0].A.Y, 1080 - Synth.Standoff, 1e-6, "cinema ceiling is at the display top");
        Harness.Near(floor.Segs[0].A.Y, Synth.Standoff, 1e-6, "cinema floor is at the display bottom (over the taskbar)");
        Harness.Check(cinema.Loop("screen:0") is null, "no screen rim while in cinema");
        Harness.Check(cinema.IsCinema(new V2(800, 500)), "isCinema inside the display");

        // A zoomed (maximised) window uses the work area: ceiling at its top, floor on the taskbar top.
        var zoomed = Synth.Build(Synth.Desktop().Zoomed());
        var zLoops = zoomed.AllLoops.ToList();
        Harness.Check(zLoops.Count == 2, "zoomed leaves floor + ceiling", $"got {zLoops.Count}");
        Harness.Near(zLoops.First(l => l.Id.Contains("ceiling")).Segs[0].A.Y, 1080 - Synth.Standoff, 1e-6, "zoomed ceiling is the work-area top");
        Harness.Near(zLoops.First(l => l.Id.Contains("floor")).Segs[0].A.Y, 40 + Synth.Standoff, 1e-6, "zoomed floor is the taskbar top");

        // A maximised front window with a second window in front of it: no loop, still occludes.
        var desk = Synth.Desktop()
            .With(Synth.Window(1, 0, 40, 1920, 1040, 0, "front"))
            .With(Synth.Window(2, 0, 40, 1920, 1040, 1, "maximized", maximized: true));
        var m = Synth.Build(desk);
        Harness.Check(m.Loop("win:2") is null, "a maximised window behind another gets no loop");
        Harness.Check(m.Loop("win:1") is not null, "the window in front keeps its loop");
        Harness.Check(m.Occluders.Count == 2, "the maximised window still occludes", $"{m.Occluders.Count}");

        // On its own, a maximised window keeps its edges (the app promotes it to cinema instead).
        var alone = Synth.Build(Synth.Desktop().With(Synth.Window(3, 0, 40, 1920, 1040, 0, "max", maximized: true)));
        Harness.Check(alone.Loop("win:3") is not null, "a lone maximised window still has edges unless promoted to cinema");
    }

    // ------------------------------------------------------------------ confine

    static void ConfineChecks()
    {
        Harness.Section("the confinement box clips the map (spec 2.4, 15.1)");

        // The window body path is (182.84, 282.84)…(817.16, 717.16). This box cuts across the top edge only.
        var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 600, 400, 0, "w"));
        var box = new Rect(300, 700, 400, 100);
        var m = Synth.Build(desk, Synth.Scale, box);

        Harness.Check(m.Confine is not null, "the box is recorded");
        int totalSegs = m.AllLoops.Sum(l => l.Segs.Count);
        Harness.Check(totalSegs > 0, "the box keeps the stretch that runs through it", $"{totalSegs} segs");
        foreach (var loop in m.AllLoops)
        {
            foreach (var s in loop.Segs)
            {
                Harness.Check(box.Inset(1).Contains(s.A) && box.Inset(1).Contains(s.B),
                    $"loop {loop.Id} seg stays inside the box", $"{s.A}→{s.B}");
            }
        }
        var kept = m.AllLoops.FirstOrDefault(l => l.Kind == SurfaceKind.WindowEdge);
        Harness.Check(kept is not null, "the clipped window edge survives as an open run");
        if (kept is not null)
        {
            Harness.Check(!kept.Closed, "clipped loops are open runs");
            // box is 400 wide and fully inside the window's top edge, so the run is exactly 400 long
            Harness.Near(kept.Segs[0].Len, 400, 0.01, "the run is the clipped length");
            Harness.Near(Math.Min(kept.Segs[0].A.X, kept.Segs[0].B.X), 300, 1e-6, "the run starts at the box edge");
        }

        // Everything outside the box is gone, including the rim.
        Harness.Check(m.Loop("screen:0") is null, "the rim is dropped when it lies outside the box");

        // A box in a far corner leaves nothing to stand on at all — a legitimate state (15.1 hangs in on a line).
        var empty = new Rect(1000, 900, 200, 100);
        var m2 = Synth.Build(desk, Synth.Scale, empty);
        Harness.Check(m2.LoopCount == 0, "a box with nothing to stand on yields an empty map", $"{m2.LoopCount} loops");

        // Junctions are discarded when clipped.
        Harness.Check(m.Junctions.Count == 0, "junction tables are discarded when clipped");
    }

    // ------------------------------------------------------------------ stability

    static void DriftChecks()
    {
        Harness.Section("no drift, instant removal (spec 2 Done-when)");

        var desk = Synth.Desktop()
            .With(Synth.Window(1, 100, 100, 400, 300, 0))
            .With(Synth.Window(2, 700, 500, 500, 400, 1));
        var m = new SurfaceMap();
        m.Rebuild(desk, Synth.Scale);
        int gen1 = m.Generation;
        static List<string> Fingerprint(SurfaceMap map) =>
            map.AllLoops
               .SelectMany(l => new[] { l.Id }.Concat(l.Segs.SelectMany(s => new[] { s.A.ToString(), s.B.ToString() })))
               .ToList();
        var first = Fingerprint(m);

        // Rebuilding the same state must be identical (a live 30 Hz poll must not creep).
        for (int i = 0; i < 30; i++) m.Rebuild(desk, Synth.Scale);
        var second = Fingerprint(m);
        Harness.Check(first.SequenceEqual(second), "30 rebuilds of the same desktop are byte-identical");
        Harness.Check(m.Generation == gen1 + 30, "generation increments on every re-layout");

        // Moving a window moves its loop with it.
        var moved = Synth.Desktop().With(Synth.Window(1, 100, 100, 400, 300, 0));
        var mm = new SurfaceMap();
        mm.Rebuild(moved, Synth.Scale);
        double y1 = mm.Loop("win:1")!.Segs[0].A.Y;
        moved.Windows[0].Frame = new Rect(100, 200, 400, 300);
        mm.Rebuild(moved, Synth.Scale);
        double y2 = mm.Loop("win:1")!.Segs[0].A.Y;
        Harness.Near(y2 - y1, 100, 1e-9, "the loop follows the window exactly (no drift)");

        // A minimised (vanished) window is gone from the map at once.
        var gone = Synth.Desktop().With(Synth.Window(1, 100, 100, 400, 300, 0));
        var m3 = new SurfaceMap();
        m3.Rebuild(gone, Synth.Scale);
        Harness.Check(m3.Loop("win:1") is not null, "window present before minimising");
        gone.Windows.Clear();
        m3.Rebuild(gone, Synth.Scale);
        Harness.Check(m3.Loop("win:1") is null, "a minimised window vanishes from the map immediately");
        Harness.Check(m3.Occluders.Count == 0, "and stops occluding");

        // Rebuild clears stale state: blocks do not accumulate across calls.
        var b = new SurfaceMap();
        var d1 = Synth.Desktop().With(Synth.Window(1, 100, 100, 400, 300, 0)).With(Synth.Window(2, 300, 100, 400, 300, 1));
        b.Rebuild(d1, Synth.Scale);
        int blocked1 = b.Loop("win:2")!.Segs.Sum(s => s.Blocked.Count);
        b.Rebuild(d1, Synth.Scale);
        int blocked2 = b.Loop("win:2")!.Segs.Sum(s => s.Blocked.Count);
        Harness.Check(blocked1 == blocked2, "blocks do not accumulate across rebuilds", $"{blocked1} vs {blocked2}");
    }
}

static class SurfaceMapExt
{
    public static bool LoopStartingWithExists(this SurfaceMap m, string prefix)
        => m.AllLoops.Any(l => l.Id.StartsWith(prefix, StringComparison.Ordinal));
}
