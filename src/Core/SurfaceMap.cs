namespace SpiderBuddy.Core;

/// <summary>
/// Given the live desktop, holds the set of polylines the spider can walk on and keeps them
/// current as windows move, resize, open, close, minimise and get covered (spec Stage 2).
/// Screen rim, taskbar and menu bar are never blocked: the spider walks the rim above everything.
/// </summary>
public sealed class SurfaceMap
{
    public Dictionary<string, SurfaceLoop> Loops { get; } = new(StringComparer.Ordinal);

    /// <summary>Stable iteration order (loops are never iterated in dictionary order — spec 1.6).</summary>
    public List<string> Order { get; } = new();

    /// <summary>Front-to-back rects of every window, for occlusion tests.</summary>
    public List<Rect> Occluders { get; } = new();
    public List<int> OccluderDepths { get; } = new();

    public Rect WorldBounds;
    public List<ScreenFrame> Screens { get; } = new();
    public List<Rect> DockRects { get; } = new();
    public List<Rect> CinemaRects { get; } = new();
    public List<SurfaceJunction> Junctions { get; } = new();

    /// <summary>22 × scale (spec 2.3).</summary>
    public double Standoff { get; private set; } = 22 * 0.78;

    public double Scale { get; private set; } = 0.78;

    /// <summary>Increments on every re-lay-out; the tank caches pathfinding by this (spec 2.4).</summary>
    public int Generation { get; private set; }

    public Rect? Confine { get; private set; }

    public static double StandoffFor(double scale) => 22 * scale;

    public int LoopCount => Order.Count;

    public SurfaceLoop? Loop(string? id) =>
        string.IsNullOrEmpty(id) ? null : Loops.TryGetValue(id, out var l) ? l : null;

    public IEnumerable<SurfaceLoop> AllLoops => Order.Select(id => Loops[id]);

    // =========================================================================== rebuild

    /// <summary>
    /// Lay out the surface model (spec 2.4). Page ledges are appended as loops (Stage 18.2) and are
    /// never blocked, matching the macOS `pathLoop`.
    /// </summary>
    public void Rebuild(DesktopState desk, double scale, IReadOnlyList<SurfaceLoop>? pageLoops = null, Rect? confine = null,
        IReadOnlyCollection<Rect>? pageScreens = null)
    {
        Loops.Clear();
        Order.Clear();
        Occluders.Clear();
        OccluderDepths.Clear();
        Screens.Clear();
        DockRects.Clear();
        CinemaRects.Clear();
        Junctions.Clear();

        Scale = scale;
        Standoff = StandoffFor(scale);
        Confine = confine;
        Generation++;

        Screens.AddRange(desk.Screens);
        WorldBounds = desk.VirtualBounds.IsValid ? desk.VirtualBounds : ComputeBounds(desk);
        foreach (var d in desk.Docks) DockRects.Add(d.Rect);

        // ---- per display
        for (int i = 0; i < desk.Screens.Count; i++)
        {
            var sc = desk.Screens[i];
            bool page = pageScreens?.Any(r => r.Contains(sc.Frame.Mid)) == true;
            bool cinema = !page && desk.CinemaScreens.Any(c => c.Id == sc.Id);
            bool zoomed = !page && desk.ZoomedScreens.Any(c => c.Id == sc.Id);

            if (page) continue;
            if (cinema || zoomed)
            {
                CinemaRects.Add(sc.Frame);
                foreach (var l in CinemaLoops(sc, zoomed, Standoff)) Add(l);
                continue;
            }
            Add(ScreenBorderLoop(sc, Standoff));
        }

        // ---- per window
        foreach (var w in desk.Windows)
        {
            if (pageScreens?.Any(r => r.Contains(w.Frame.Mid)) == true) continue;
            if (w.Widget) { Add(WidgetLoop(w, Standoff)); continue; }
            if (w.Frame.W <= 130 || w.Frame.H <= 90) continue;

            // A maximised window with another window in front of it gets no loop (its edges are the
            // screen's), though it still occludes.
            if (w.Maximized && desk.Windows.Any(o => o.Depth < w.Depth && o.Frame.Intersects(w.Frame))) continue;

            Add(WindowLoop(w, Standoff));
        }

        // ---- page ledges (never blocked; the rim/bar rule applies to them too)
        if (pageLoops is not null)
            foreach (var l in pageLoops) Add(l.Clone());

        // ---- blocks: a window loop is covered where a window in front of it lies
        var byDepth = desk.Windows.OrderBy(w => w.Depth).ToList();
        foreach (var id in Order.ToList())
        {
            var loop = Loops[id];
            if (!loop.Kind.OnWindow()) continue;

            foreach (var w in byDepth)
            {
                if (w.Depth >= loop.Depth) break;           // byDepth is sorted; nothing further is in front
                // Grow the rect of the window IN FRONT by standoff × 1.4 (spec 2.4 Blocks).
                Rect blocker = w.Frame.Inset(Standoff * 1.4);
                if (!blocker.Intersects(loop.Rect)) continue;
                foreach (var s in loop.Segs)
                {
                    if (s.Span(blocker, out double t0, out double t1)) s.Block(t0, t1);
                }
            }
        }

        // ---- occlusion rects (front to back)
        foreach (var w in byDepth)
        {
            Occluders.Add(w.Frame);
            OccluderDepths.Add(w.Depth);
        }

        // ---- the confinement box clips every loop
        if (confine is { } box && box.IsValid) ClipAllTo(box);
    }

    void Add(SurfaceLoop loop)
    {
        if (Loops.ContainsKey(loop.Id)) loop.Id = UniqueId(loop.Id);
        Loops[loop.Id] = loop;
        Order.Add(loop.Id);
    }

    string UniqueId(string id)
    {
        int n = 1;
        while (Loops.ContainsKey($"{id}~{n}")) n++;
        return $"{id}~{n}";
    }

    static Rect ComputeBounds(DesktopState desk)
    {
        if (desk.Screens.Count == 0) return new Rect(0, 0, 1920, 1080);
        Rect r = desk.Screens[0].Frame;
        for (int i = 1; i < desk.Screens.Count; i++) r = r.Union(desk.Screens[i].Frame);
        return r;
    }

    /// <summary>
    /// The screen rim. Windows has no menu bar, so this is the closed rectangle of the **work area**
    /// (display minus taskbar): the floor is the top of the taskbar and the ceiling is the top of the
    /// screen — the "treat the work area as the screen" branch of spec 2.8.
    /// </summary>
    public static SurfaceLoop ScreenBorderLoop(ScreenFrame sc, double standoff)
    {
        // A screen smaller than twice the standoff has nowhere to walk.
        Rect work = sc.VisibleFrame.IsValid && !sc.VisibleFrame.IsEmpty ? sc.VisibleFrame : sc.Frame;
        Rect body = work.Inset(-standoff);   // shrink inward by the standoff (the body rides above the edge)
        var loop = new SurfaceLoop
        {
            Id = sc.Id,
            Kind = SurfaceKind.ScreenBorder,
            Closed = true,
            Depth = 1000,
            Rect = work,
            CornerRadius = 0,
            IsWindowRect = false
        };
        if (body.W > 0 && body.H > 0)
        {
            // The spider stands INSIDE the screen, so the rim's normals point inward:
            // floor faces up, right wall faces left, ceiling faces down, left wall faces right
            // (spec 2.4.3). This is the opposite sense from a window, where it stands outside.
            loop.Segs.Add(new Seg(body.BottomLeft, body.BottomRight, EdgeFacing.Up));      // floor
            loop.Segs.Add(new Seg(body.BottomRight, body.TopRight, EdgeFacing.Left));     // right wall
            loop.Segs.Add(new Seg(body.TopRight, body.TopLeft, EdgeFacing.Down));         // ceiling
            loop.Segs.Add(new Seg(body.TopLeft, body.BottomLeft, EdgeFacing.Right));      // left wall
        }
        loop.Edge.AddRange(new[] { work.TopLeft, work.TopRight, work.BottomRight, work.BottomLeft, work.TopLeft });
        loop.Owners = new int[loop.Segs.Count];
        return loop;
    }

    /// <summary>
    /// Cinema manners (spec 2.7): only a floor and a ceiling exist — no walls, menu bar, taskbar,
    /// dock or windows. For a zoomed (maximised) window the ceiling is the menu bar's lower lip and
    /// the floor is the shown dock's top; on Windows those are the work area's top and bottom.
    /// </summary>
    public List<SurfaceLoop> CinemaLoops(ScreenFrame sc, bool zoomed, double standoff)
    {
        Rect source = zoomed ? (sc.VisibleFrame.IsValid && !sc.VisibleFrame.IsEmpty ? sc.VisibleFrame : sc.Frame) : sc.Frame;
        double floorY = source.MinY + standoff;
        double ceilY = source.MaxY - standoff;
        double x0 = sc.Frame.MinX + standoff;
        double x1 = sc.Frame.MaxX - standoff;

        var result = new List<SurfaceLoop>();

        if (x1 - x0 > 60)
        {
            var floor = new SurfaceLoop
            {
                Id = sc.Id + ":cinema:floor",
                Kind = SurfaceKind.ScreenBorder,
                Closed = false,
                Depth = 1000,
                Rect = Rect.FromLTRB(x0 - standoff, floorY - standoff, x1 + standoff, floorY - standoff)
            };
            floor.Segs.Add(new Seg(new V2(x0, floorY), new V2(x1, floorY), EdgeFacing.Up));
            floor.Edge.AddRange(new[] { new V2(x0 - standoff, floorY - standoff), new V2(x1 + standoff, floorY - standoff) });
            floor.Owners = new int[floor.Segs.Count];
            result.Add(floor);

            var ceil = new SurfaceLoop
            {
                Id = sc.Id + ":cinema:ceiling",
                Kind = SurfaceKind.ScreenBorder,
                Closed = false,
                Depth = 1000,
                Rect = Rect.FromLTRB(x0 - standoff, ceilY + standoff, x1 + standoff, ceilY + standoff)
            };
            ceil.Segs.Add(new Seg(new V2(x1, ceilY), new V2(x0, ceilY), EdgeFacing.Down));
            ceil.Edge.AddRange(new[] { new V2(x1 + standoff, ceilY + standoff), new V2(x0 - standoff, ceilY + standoff) });
            ceil.Owners = new int[ceil.Segs.Count];
            result.Add(ceil);
        }
        return result;
    }

    /// <summary>
    /// A window's edges: walks the top like a shelf, rounds the corner down the side, and hangs
    /// beneath the bottom (spec 2.4).
    /// </summary>
    public static SurfaceLoop WindowLoop(TrackedWindow w, double standoff)
    {
        Rect rect = w.Frame;
        Rect grown = rect.Inset(standoff);
        double cr = Math.Min(Math.Max(0, w.CornerRadius), Math.Min(rect.W, rect.H) / 2);

        var loop = new SurfaceLoop
        {
            Id = "win:" + w.Id,
            Kind = SurfaceKind.WindowEdge,
            Closed = true,
            Depth = w.Depth,
            Rect = rect,
            CornerRadius = cr,
            IsWindowRect = true
        };
        loop.Segs.Add(new Seg(grown.TopLeft, grown.TopRight, EdgeFacing.Up));
        loop.Segs.Add(new Seg(grown.TopRight, grown.BottomRight, EdgeFacing.Right));
        loop.Segs.Add(new Seg(grown.BottomRight, grown.BottomLeft, EdgeFacing.Down));
        loop.Segs.Add(new Seg(grown.BottomLeft, grown.TopLeft, EdgeFacing.Left));
        loop.Edge.AddRange(RoundedRectPolyline(rect, cr));
        loop.Owners = new int[loop.Segs.Count];
        return loop;
    }

    /// <summary>
    /// A path found on a web page (spec 18.2): points are the real edge in the world (y-up);
    /// `facings` says which side the room is on. The body path is those offset lines joined at
    /// their intersections, so corners resolve continuously and flat stretches stay flat.
    /// </summary>
    public static SurfaceLoop? PathLoop(string id, SurfaceKind kind, IReadOnlyList<V2> points,
        IReadOnlyList<EdgeFacing> facings, bool closed, int depth, double standoff)
    {
        if (points.Count < 2 || facings.Count < (closed ? points.Count : points.Count - 1)) return null;
        int sides = closed ? points.Count : points.Count - 1;
        var offsetA = new V2[sides];
        var offsetB = new V2[sides];
        for (int i = 0; i < sides; i++)
        {
            V2 a = points[i], b = points[(i + 1) % points.Count];
            V2 n = facings[i].Normal() * standoff;
            offsetA[i] = a + n;
            offsetB[i] = b + n;
        }
        var loop = new SurfaceLoop
        {
            Id = id, Kind = kind, Closed = closed, Depth = depth, CornerRadius = 0,
            IsWindowRect = false
        };
        for (int i = 0; i < sides; i++)
        {
            V2 a = offsetA[i], b = offsetB[i];
            if (i > 0 || closed)
            {
                int p = (i - 1 + sides) % sides;
                if (LineIntersection(offsetA[p], offsetB[p], a, b) is { } cut) a = cut;
            }
            if (i < sides - 1 || closed)
            {
                int n = (i + 1) % sides;
                if (LineIntersection(a, b, offsetA[n], offsetB[n]) is { } cut) b = cut;
            }
            if (a.DistanceTo(b) > 0.01) loop.Segs.Add(new Seg(a, b, facings[i]));
        }
        if (loop.Segs.Count == 0) return null;
        loop.Edge.AddRange(points);
        if (closed && points[0] != points[^1]) loop.Edge.Add(points[0]);
        loop.Owners = new int[loop.Segs.Count];
        var min = points[0]; var max = points[0];
        foreach (var p in points) { min = V2.Min(min, p); max = V2.Max(max, p); }
        loop.Rect = Rect.FromLTRB(min.X, min.Y, max.X, max.Y);
        return loop;
    }

    static V2? LineIntersection(V2 a, V2 b, V2 c, V2 d)
    {
        V2 r = b - a, s = d - c;
        double den = r.Cross(s);
        if (Math.Abs(den) < 1e-9) return null;
        double t = (c - a).Cross(s) / den;
        return a + r * t;
    }

    /// <summary>A macOS desktop widget: layer behind everything, inset 8, ~26 pt corners (spec 2.1).</summary>
    public static SurfaceLoop WidgetLoop(TrackedWindow w, double standoff)
    {
        var loop = WindowLoop(w, standoff);
        loop.Id = "widget:" + w.Id;
        loop.Depth = 900;
        return loop;
    }

    /// <summary>Sample a rounded rectangle into a polyline (12 points per corner).</summary>
    public static List<V2> RoundedRectPolyline(Rect r, double cr, int perCorner = 12)
    {
        var pts = new List<V2>();
        cr = Math.Max(0, Math.Min(cr, Math.Min(r.W, r.H) / 2));
        if (cr < 0.01)
        {
            pts.AddRange(new[] { r.TopLeft, r.TopRight, r.BottomRight, r.BottomLeft, r.TopLeft });
            return pts;
        }
        // clockwise starting at the top-left tangent point
        void Arc(V2 c, double startAng, double endAng)
        {
            for (int i = 0; i <= perCorner; i++)
            {
                double a = M.Lerp(startAng, endAng, i / (double)perCorner);
                pts.Add(c + new V2(Math.Cos(a), Math.Sin(a)) * cr);
            }
        }
        Arc(new V2(r.MinX + cr, r.MaxY - cr), M.Pi / 2 * 2, M.Pi / 2);      // top-left: 180° → 90°
        Arc(new V2(r.MaxX - cr, r.MaxY - cr), M.Pi / 2, 0);                // top-right: 90° → 0°
        Arc(new V2(r.MaxX - cr, r.MinY + cr), 0, -M.Pi / 2);               // bottom-right: 0 → −90°
        Arc(new V2(r.MinX + cr, r.MinY + cr), -M.Pi / 2, -M.Pi);           // bottom-left: −90 → −180°
        return pts;
    }

    // =========================================================================== confinement

    /// <summary>
    /// Clip every loop to the box (spec 2.4). Segments with under 8 units left are dropped;
    /// surviving runs of connected pieces become open loops named "&lt;id&gt;~k".
    /// </summary>
    void ClipAllTo(Rect box)
    {
        foreach (var id in Order.ToList())
        {
            var loop = Loops[id];
            if (box.Contains(loop.Rect) && loop.Rect.IsValid) continue;   // entirely inside: untouched
            var pieces = ClipLoop(loop, box);
            // Nothing of this loop survives inside the box: drop it entirely.
            Loops.Remove(id);
            Order.Remove(id);
            if (pieces.Count == 0) continue;
            foreach (var p in pieces) Add(p);
        }
        Junctions.Clear();
    }

    List<SurfaceLoop> ClipLoop(SurfaceLoop loop, Rect box)
    {
        var runs = new List<SurfaceLoop>();
        var current = new List<Seg>();
        var currentEdge = new List<V2>();
        int k = 0;

        void Flush()
        {
            if (current.Count == 0) return;
            var nl = new SurfaceLoop
            {
                Id = $"{loop.Id}~{k++}",
                Kind = loop.Kind,
                Closed = false,
                Depth = loop.Depth,
                Rect = loop.Rect,
                CornerRadius = loop.CornerRadius,
                IsWindowRect = loop.IsWindowRect,
                Segs = current,
                Owners = new int[current.Count]
            };
            nl.Edge = currentEdge;
            runs.Add(nl);
            current = new List<Seg>();
            currentEdge = new List<V2>();
        }

        foreach (var s in loop.Segs)
        {
            // Span() reports distance units, so (t1 - t0) is already a length.
            if (s.Span(box, out double t0, out double t1) && (t1 - t0) >= 8)
            {
                var piece = new Seg(s.Point(t0), s.Point(t1), s.Facing);
                // preserve the block structure snapped into the piece's own t space
                double map = piece.Len / Math.Max(1e-9, t1 - t0);
                foreach (var br in s.Blocked)
                {
                    double lo = Math.Max(br.Lo, t0), hi = Math.Min(br.Hi, t1);
                    if (hi > lo) piece.Block((lo - t0) * map, (hi - t0) * map);
                }
                current.Add(piece);
                if (currentEdge.Count == 0) currentEdge.Add(piece.A);
                currentEdge.Add(piece.B);
            }
            else Flush();
        }
        Flush();

        // A closed loop whose first and last runs both touch the seam re-join (spec 2.4).
        if (loop.Closed && runs.Count > 1)
        {
            var first = runs[0];
            var last = runs[^1];
            bool firstTouchesStart = first.Segs[0].A.DistanceTo(loop.Segs[0].A) < 1e-6;
            bool lastTouchesEnd = last.Segs[^1].B.DistanceTo(loop.Segs[^1].B) < 1e-6;
            if (firstTouchesStart && lastTouchesEnd)
            {
                foreach (var s in first.Segs) last.Segs.Add(s);
                for (int i = 1; i < first.Edge.Count; i++) last.Edge.Add(first.Edge[i]);
                last.Owners = new int[last.Segs.Count];
                runs.RemoveAt(0);
            }
        }
        return runs;
    }

    // =========================================================================== resolve

    /// <summary>
    /// A position on the surface (spec 2.5). Straight parts are the segment itself; near a corner of
    /// a rounded window the body path is an arc of radius windowCornerRadius + standoff about the
    /// window's corner centre. Flat segments are untouched — flat walking must be identical to a
    /// build with no corner handling at all.
    /// </summary>
    public SurfacePoint Resolve(Anchor a, double cornerRadius)
    {
        var sp = new SurfacePoint { LoopId = a.LoopId, SegIdx = a.SegIdx, T = a.T };
        var loop = Loop(a.LoopId);
        if (loop is null || a.SegIdx < 0 || a.SegIdx >= loop.Segs.Count) return default;
        var seg = loop.Segs[a.SegIdx];
        sp.Kind = loop.Kind;

        V2 p = seg.Point(a.T);
        V2 tangent = seg.Dir * (a.Dir >= 0 ? 1 : -1);
        V2 normal = seg.Normal;

        if (loop.IsWindowRect)
        {
            double cr = Math.Min(Math.Max(0, loop.CornerRadius), Math.Min(loop.Rect.W, loop.Rect.H) / 2);
            double rr = cr + Standoff;
            if (rr > 0.01)
            {
                V2[] centres =
                {
                    new(loop.Rect.MinX + cr, loop.Rect.MaxY - cr),
                    new(loop.Rect.MaxX - cr, loop.Rect.MaxY - cr),
                    new(loop.Rect.MaxX - cr, loop.Rect.MinY + cr),
                    new(loop.Rect.MinX + cr, loop.Rect.MinY + cr)
                };
                int[] sx = { -1, 1, 1, -1 };
                int[] sy = { 1, 1, -1, -1 };
                for (int i = 0; i < centres.Length; i++)
                {
                    V2 c = centres[i];
                    V2 d = p - c;
                    // Only the outward quadrant belongs to this corner. The other half of the
                    // square is the flat edge leading into it; mapping that half as well made the
                    // body jump from the edge to the 45° point as soon as it entered the square.
                    if (d.X * sx[i] < -1e-9 || d.Y * sy[i] < -1e-9) continue;
                    if (Math.Abs(d.X) <= rr + 1e-9 && Math.Abs(d.Y) <= rr + 1e-9 && d.Length > 1e-9)
                    {
                        V2 n = d.Normalized;
                        p = c + n * rr;
                        normal = n;
                        tangent = seg.Dir;
                        break;
                    }
                }
            }
        }
        else if (cornerRadius > 0.01 && loop.Segs.Count > 1)
        {
            (p, tangent, normal) = RoundCornerQuad(loop, a, p, tangent, normal, cornerRadius);
        }

        sp.Pos = p;
        sp.Tangent = tangent;
        sp.Normal = normal;
        return sp;
    }

    /// <summary>
    /// Quadratic Bézier round-off for everything that is not a rounded window rect (spec 2.5),
    /// with reach from Spider.cornerRadius. A no-op on the flat middles of segments.
    /// </summary>
    (V2 p, V2 tan, V2 nor) RoundCornerQuad(SurfaceLoop loop, Anchor a, V2 p, V2 tan, V2 nor, double reach)
    {
        var seg = loop.Segs[a.SegIdx];
        if (seg.Len < 1e-9) return (p, tan, nor);
        double r = Math.Min(reach, seg.Len / 3);
        if (r < 0.5) return (p, tan, nor);

        bool nearEnd = a.T > seg.Len - r;
        bool nearStart = a.T < r;

        if (nearEnd)
        {
            int ni = a.SegIdx + 1;
            if (ni >= loop.Segs.Count) { if (loop.Closed) ni = 0; else return (p, tan, nor); }
            var next = loop.Segs[ni];
            V2 v = seg.B;
            V2 aPt = v - seg.Dir * r;
            V2 bPt = v + next.Dir * Math.Min(r, next.Len / 3);
            double distPastA = a.T - seg.Len + r;       // arc position measured from aPt
            double total = r * 2;
            double u = M.Clamp01(distPastA / total);
            var (qp, qt) = M.QuadPointTangent(aPt, v, bPt, u);
            V2 nrm = qt.Perp;
            if (nrm.Dot(nor) < 0) nrm = -nrm;
            return (qp, qt, nrm);
        }
        if (nearStart)
        {
            int pi = a.SegIdx - 1;
            if (pi < 0) { if (loop.Closed) pi = loop.Segs.Count - 1; else return (p, tan, nor); }
            var prev = loop.Segs[pi];
            V2 v = seg.A;
            V2 aPt = v - prev.Dir * Math.Min(r, prev.Len / 3);
            V2 bPt = v + seg.Dir * r;
            double distPastA = r + a.T;
            double total = r * 2;
            double u = M.Clamp01(distPastA / total);
            var (qp, qt) = M.QuadPointTangent(aPt, v, bPt, u);
            V2 nrm = qt.Perp;
            if (nrm.Dot(nor) < 0) nrm = -nrm;
            return (qp, qt, nrm);
        }
        return (p, tan, nor);
    }

    // =========================================================================== queries

    public Seg? SegOf(Anchor a)
    {
        var loop = Loop(a.LoopId);
        return loop?.SegAt(a.SegIdx);
    }

    public V2 WorldPoint(Anchor a) => Resolve(a, 38 * Scale).Pos;

    /// <summary>Not hidden by a window in front of the window it stands on (spec 2.6).</summary>
    public bool IsVisible(V2 p, int depth)
    {
        for (int i = 0; i < Occluders.Count; i++)
        {
            if (OccluderDepths[i] >= depth) continue;
            if (Occluders[i].Contains(p)) return false;
        }
        return true;
    }

    /// <summary>Clear of windows in front by a margin.</summary>
    public bool IsClear(V2 p, int depth, double margin)
    {
        for (int i = 0; i < Occluders.Count; i++)
        {
            if (OccluderDepths[i] >= depth) continue;
            if (Occluders[i].Inset(margin).Contains(p)) return false;
        }
        return true;
    }

    /// <summary>
    /// Whether a line may fasten here — never to a covered stretch (spec 7.6). "Covered" is the
    /// block test, which already allows for the 1.4×standoff grow of the window in front.
    /// </summary>
    public bool CanHold(string loopId, int segIdx, double t)
    {
        var loop = Loop(loopId);
        if (loop is null || segIdx < 0 || segIdx >= loop.Segs.Count) return false;
        return loop.Segs[segIdx].IsOpen(t);
    }

    /// <summary>Candidate standing spots across all loops (spec 2.6).</summary>
    public List<Spot> SampleSpots(double spacing = 34, bool visibleOnly = false, double scale = 0.78)
    {
        var spots = new List<Spot>();
        foreach (var id in Order)
        {
            var loop = Loops[id];
            for (int si = 0; si < loop.Segs.Count; si++)
            {
                var seg = loop.Segs[si];
                if (seg.Len < 1e-6) continue;
                int steps = Math.Max(1, (int)Math.Round(seg.Len / spacing));
                for (int k = 0; k <= steps; k++)
                {
                    double t = seg.Len * k / steps;
                    if (!seg.IsOpen(t)) continue;
                    var anchor = new Anchor(id, si, t, 1);
                    V2 p = Resolve(anchor, 38 * scale).Pos;
                    if (visibleOnly && loop.Kind.OnWindow() && !IsVisible(p, loop.Depth)) continue;
                    spots.Add(new Spot(anchor, p, id, loop.Kind, si, loop.Depth));
                }
            }
        }
        return spots;
    }

    /// <summary>Nearest spot to a point within a radius (spec 2.6).</summary>
    public Spot? NearestSpot(V2 to, double within, string? excluding = null, double scale = 0.78)
    {
        Spot? best = null;
        double bestD = within * within;
        foreach (var id in Order)
        {
            if (id == excluding) continue;
            var loop = Loops[id];
            for (int si = 0; si < loop.Segs.Count; si++)
            {
                var seg = loop.Segs[si];
                var (t, _) = M.ProjectOnSegment(to, seg.A, seg.B);
                if (!seg.IsOpen(t)) continue;
                var anchor = new Anchor(id, si, t * seg.Len, 1);
                V2 p = Resolve(anchor, 38 * scale).Pos;
                double d = p.DistanceSquaredTo(to);
                if (d < bestD) { bestD = d; best = new Spot(anchor, p, id, loop.Kind, si, loop.Depth); }
            }
        }
        return best;
    }

    public readonly struct CeilingHit
    {
        public readonly V2 Point;
        public readonly string LoopId;
        public readonly int SegIdx;
        public readonly double T;
        public CeilingHit(V2 p, string id, int seg, double t) { Point = p; LoopId = id; SegIdx = seg; T = t; }
        public bool Found => LoopId is not null;
    }

    /// <summary>The first down-facing edge above p, within maxRise (for lines — spec 2.6).</summary>
    public CeilingHit Ceiling(V2 p, double maxRise = 900)
    {
        V2? best = null;
        string bestId = "";
        int bestSeg = 0;
        double bestT = 0;
        double bestRise = double.MaxValue;

        foreach (var id in Order)
        {
            var loop = Loops[id];
            for (int si = 0; si < loop.Segs.Count; si++)
            {
                var seg = loop.Segs[si];
                if (seg.Facing != EdgeFacing.Down) continue;
                // the seg must be above p and span its x
                double y = seg.A.Y;
                double rise = y - p.Y;
                if (rise <= 1 || rise > maxRise) continue;
                double x0 = Math.Min(seg.A.X, seg.B.X), x1 = Math.Max(seg.A.X, seg.B.X);
                if (p.X < x0 - 1 || p.X > x1 + 1) continue;
                if (!seg.IsOpen(seg.Len / 2)) continue;
                if (rise < bestRise)
                {
                    bestRise = rise;
                    best = new V2(M.Clamp(p.X, x0, x1), y);
                    bestId = id; bestSeg = si;
                    bestT = M.Clamp(p.X - seg.A.X, 0, seg.Len);
                }
            }
        }
        return best is null ? new CeilingHit(V2.Zero, null!, 0, 0) : new CeilingHit(best.Value, bestId, bestSeg, bestT);
    }

    /// <summary>Height of the first standable thing under p (spec 2.6). NaN when nothing.</summary>
    public double LandingBelow(V2 p, double halfWidth = 24, bool includeScreenFloor = true)
    {
        double best = double.NaN;
        foreach (var id in Order)
        {
            var loop = Loops[id];
            for (int si = 0; si < loop.Segs.Count; si++)
            {
                var seg = loop.Segs[si];
                if (seg.Facing != EdgeFacing.Up) continue;
                double y = seg.A.Y;
                if (y > p.Y - 0.5) continue;
                double x0 = Math.Min(seg.A.X, seg.B.X) - halfWidth;
                double x1 = Math.Max(seg.A.X, seg.B.X) + halfWidth;
                if (p.X < x0 || p.X > x1) continue;
                if (!seg.IsOpen(seg.Len / 2)) continue;
                if (double.IsNaN(best) || y > best) best = y;
            }
        }
        return best;
    }

    /// <summary>Depth of the topmost window containing p (0 = frontmost). Large when none.</summary>
    public int DepthAt(V2 p)
    {
        int best = int.MaxValue;
        for (int i = 0; i < Occluders.Count; i++)
            if (OccluderDepths[i] < best && Occluders[i].Contains(p)) best = OccluderDepths[i];
        return best;
    }

    public Rect BoundsAround(V2 p)
    {
        foreach (var id in Order)
        {
            var loop = Loops[id];
            if (loop.Rect.IsValid && loop.Rect.Contains(p)) return loop.Rect;
        }
        return WorldBounds;
    }

    public bool IsOnScreen(V2 p, double slack = 0) =>
        Screens.Count == 0 || Screens.Any(s => s.Frame.Inset(slack).Contains(p));

    public ScreenFrame? ScreenFrameContaining(V2 p) =>
        Screens.FirstOrDefault(s => s.Frame.Contains(p)) ?? Screens.FirstOrDefault(s => s.Main);

    public bool IsCinema(V2 p) => CinemaRects.Any(r => r.Contains(p));

    public IEnumerable<SurfaceJunction> JunctionsFrom(string loopId, V2 at, double within = 20) =>
        Junctions.Where(j => (j.FromLoop == loopId || j.ToLoop == loopId) && j.At.DistanceTo(at) <= within);

    public int OwnerOf(string loopId, int segIdx) => Loop(loopId)?.OwnerOf(segIdx) ?? 0;

    /// <summary>
    /// Install a habitat's already-traced surfaces (spec 17c). The tank does not go through the
    /// desktop window tracker: its furniture shapes are the geometry, and its world is the tank.
    /// </summary>
    public void InstallHabitat(HabitatWorld world, HabitatSurfaces surfaces, double scale)
    {
        Loops.Clear(); Order.Clear(); Occluders.Clear(); OccluderDepths.Clear();
        Screens.Clear(); DockRects.Clear(); CinemaRects.Clear(); Junctions.Clear();
        Scale = scale;
        Standoff = StandoffFor(scale);
        WorldBounds = world.Bounds;
        Confine = null;
        Generation++;
        Screens.Add(new ScreenFrame
        {
            Id = "habitat:screen", Frame = world.Bounds, VisibleFrame = world.Air,
            Main = true, Dpi = 96
        });
        foreach (var loop in surfaces.Loops)
        {
            if (loop.Segs.Count == 0) continue;
            Add(loop.Clone());
        }
        foreach (var j in surfaces.Junctions) Junctions.Add(j);
        foreach (var item in world.Items.OrderByDescending(i => i.Id))
        {
            Occluders.Add(item.Rect);
            OccluderDepths.Add(10_000 - item.Id);
        }
    }

    /// <summary>A copy for background pathfinding (spec 2.6, 17g).</summary>
    public SurfaceMap HabitatCopy()
    {
        var m = new SurfaceMap
        {
            WorldBounds = WorldBounds,
            Standoff = Standoff,
            Scale = Scale,
            Generation = Generation,
            Confine = Confine
        };
        foreach (var id in Order)
        {
            var l = Loops[id].Clone();
            m.Loops[l.Id] = l;
            m.Order.Add(l.Id);
        }
        m.Occluders.AddRange(Occluders);
        m.OccluderDepths.AddRange(OccluderDepths);
        m.Screens.AddRange(Screens);
        m.DockRects.AddRange(DockRects);
        m.CinemaRects.AddRange(CinemaRects);
        m.Junctions.AddRange(Junctions);
        return m;
    }

    /// <summary>Human-readable summary, used by the debug overlay and the harness.</summary>
    public override string ToString() =>
        $"SurfaceMap gen{Generation}: {Order.Count} loops, {Occluders.Count} occluders, standoff {Standoff:0.##}";
}
