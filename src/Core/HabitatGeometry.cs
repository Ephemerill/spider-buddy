using System.Text;

namespace SpiderBuddy.Core;

public enum ShapeRole { Bulk, Limb }
public enum AnchorKind { Perch, Tie, Entrance, Refuge, Drink, Bask, Lookout, Feed }

public sealed class ShapePart
{
    public string Name = "body";
    public ShapeRole Role = ShapeRole.Bulk;
    public List<V2> Outline = new();
    public ShapePart() { }
    public ShapePart(string name, ShapeRole role, IEnumerable<V2> outline) { Name = name; Role = role; Outline = outline.ToList(); }
    public ShapePart Clone() => new(Name, Role, Outline);
}

public sealed class ObjectAnchor
{
    public AnchorKind Kind;
    public V2 Point;
    public V2 Normal;
    public ObjectAnchor(AnchorKind kind, V2 point, V2 normal) { Kind = kind; Point = point; Normal = normal; }
}

public sealed class Hollow
{
    public List<V2> Cavity = new();
    public V2 Mouth;
    public V2 Inward;
}

/// <summary>A thing's physical shape in world points: the same parts the picture is painted from.</summary>
public sealed class ObjectGeometry
{
    public List<ShapePart> Parts = new();
    public List<Hollow> Hollows = new();
    public List<ObjectAnchor> Anchors = new();
    public List<List<V2>> Visual = new();

    public bool Walkable => Parts.Count > 0;

    public ObjectGeometry Mirrored(double axisX)
    {
        V2 M(V2 p) => new(2 * axisX - p.X, p.Y);
        List<V2> P(IEnumerable<V2> ps) => ps.Select(M).Reverse().ToList();
        return new ObjectGeometry
        {
            Parts = Parts.Select(p => new ShapePart(p.Name, p.Role, P(p.Outline))).ToList(),
            Hollows = Hollows.Select(h => new Hollow { Cavity = P(h.Cavity), Mouth = M(h.Mouth), Inward = new V2(-h.Inward.X, h.Inward.Y) }).ToList(),
            Anchors = Anchors.Select(a => new ObjectAnchor(a.Kind, M(a.Point), new V2(-a.Normal.X, a.Normal.Y))).ToList(),
            Visual = Visual.Select(P).ToList()
        };
    }

    public ObjectGeometry Mapped(Func<V2, V2> f) => new()
    {
        Parts = Parts.Select(p => new ShapePart(p.Name, p.Role, p.Outline.Select(f))).ToList(),
        Hollows = Hollows.Select(h => new Hollow { Cavity = h.Cavity.Select(f).ToList(), Mouth = f(h.Mouth), Inward = h.Inward }).ToList(),
        Anchors = Anchors.Select(a => new ObjectAnchor(a.Kind, f(a.Point), a.Normal)).ToList(),
        Visual = Visual.Select(v => v.Select(f).ToList()).ToList()
    };

    public Rect Bounds
    {
        get
        {
            Rect r = new(0, 0, 0, 0); bool any = false;
            foreach (var p in Parts)
            {
                var b = Poly.Bounds(p.Outline);
                r = any ? r.Union(b) : b; any = true;
            }
            return any ? r : new Rect(0, 0, 0, 0);
        }
    }

    public double? Top(double lo, double hi)
    {
        double? best = null;
        foreach (var part in Parts)
        {
            var o = part.Outline;
            for (int i = 0; i < o.Count; i++)
            {
                var a = o[i]; var b = o[(i + 1) % o.Count];
                double x0 = Math.Min(a.X, b.X), x1 = Math.Max(a.X, b.X);
                if (x1 < lo || x0 > hi) continue;
                var ys = new List<double>();
                if (a.X >= lo && a.X <= hi) ys.Add(a.Y);
                if (b.X >= lo && b.X <= hi) ys.Add(b.Y);
                if (Math.Abs(b.X - a.X) > 1e-6)
                    foreach (var x in new[] { lo, hi })
                        if (x > x0 && x < x1) ys.Add(a.Y + (b.Y - a.Y) * (x - a.X) / (b.X - a.X));
                if (ys.Count == 0) continue;
                double m = ys.Max();
                if (best is null || m > best) best = m;
            }
        }
        return best;
    }

    public List<List<V2>> TopLines(double step = 6)
    {
        var b = Bounds;
        if (b.W <= 1) return new();
        int n = Math.Max(2, (int)(b.W / step));
        double half = b.W / n * .5;
        var outLines = new List<List<V2>> { new() };
        for (int k = 0; k <= n; k++)
        {
            double x = b.MinX + b.W * k / n;
            var y = Top(x - half, x + half);
            if (y is { } yy) outLines[^1].Add(new V2(x, yy));
            else if (outLines[^1].Count > 0) outLines.Add(new());
        }
        return outLines.Where(l => l.Count >= 2).ToList();
    }

    public bool Contains(V2 p, double slack = 0) =>
        Parts.Any(part => Poly.Contains(part.Outline, p) || (slack > 0 && Poly.Distance(part.Outline, p) < slack)) ||
        Visual.Any(v => Poly.Contains(v, p));

    public ObjectGeometry Clone() => new()
    {
        Parts = Parts.Select(p => p.Clone()).ToList(),
        Hollows = Hollows.Select(h => new Hollow { Cavity = h.Cavity.ToList(), Mouth = h.Mouth, Inward = h.Inward }).ToList(),
        Anchors = Anchors.Select(a => new ObjectAnchor(a.Kind, a.Point, a.Normal)).ToList(),
        Visual = Visual.Select(v => v.ToList()).ToList()
    };
}

public static class Poly
{
    public static List<V2> Dedupe(IEnumerable<V2> pts, double d = .05)
    {
        var o = new List<V2>();
        foreach (var p in pts) if (o.Count == 0 || o[^1].DistanceTo(p) > d) o.Add(p);
        while (o.Count > 2 && o[0].DistanceTo(o[^1]) <= d) o.RemoveAt(o.Count - 1);
        return o;
    }

    public static double Area(IReadOnlyList<V2> pts)
    {
        double s = 0;
        for (int i = 0; i < pts.Count; i++)
        {
            var a = pts[i]; var b = pts[(i + 1) % pts.Count];
            s += a.X * b.Y - b.X * a.Y;
        }
        return s / 2;
    }

    public static List<V2> Clockwise(List<V2> pts) => Area(pts) > 0 ? Enumerable.Reverse(pts).ToList() : pts;

    public static Rect Bounds(IReadOnlyList<V2> pts)
    {
        if (pts.Count == 0) return new Rect(0, 0, 0, 0);
        double x0 = pts[0].X, x1 = x0, y0 = pts[0].Y, y1 = y0;
        foreach (var p in pts) { x0 = Math.Min(x0, p.X); x1 = Math.Max(x1, p.X); y0 = Math.Min(y0, p.Y); y1 = Math.Max(y1, p.Y); }
        return new Rect(x0, y0, x1 - x0, y1 - y0);
    }

    public static List<V2> Simplify(List<V2> pts, double tolerance)
    {
        if (pts.Count <= 4) return pts;
        var keep = new bool[pts.Count];
        int far = 0;
        for (int i = 0; i < pts.Count; i++) if (pts[i].DistanceTo(pts[0]) > pts[far].DistanceTo(pts[0])) far = i;
        void Dp(int i, int j)
        {
            if (j <= i + 1) return;
            int worst = -1; double wd = tolerance;
            for (int k = i + 1; k < j; k++)
            {
                double d = M.ProjectOnSegment(pts[k], pts[i], pts[j % pts.Count]).dist;
                if (d > wd) { wd = d; worst = k; }
            }
            if (worst < 0) return;
            keep[worst] = true; Dp(i, worst); Dp(worst, j);
        }
        keep[0] = true; keep[far] = true; Dp(0, far); Dp(far, pts.Count);
        return pts.Where((_, i) => keep[i]).ToList();
    }

    public static bool Contains(IReadOnlyList<V2> poly, V2 p)
    {
        bool inside = false; int j = poly.Count - 1;
        for (int i = 0; i < poly.Count; i++)
        {
            var a = poly[i]; var b = poly[j];
            if ((a.Y > p.Y) != (b.Y > p.Y) && p.X < (b.X - a.X) * (p.Y - a.Y) / (b.Y - a.Y) + a.X) inside = !inside;
            j = i;
        }
        return inside;
    }

    public static bool Winds(IReadOnlyList<V2> poly, V2 p)
    {
        int w = 0;
        for (int i = 0; i < poly.Count; i++)
        {
            var a = poly[i]; var b = poly[(i + 1) % poly.Count];
            if (a.Y <= p.Y)
            {
                if (b.Y > p.Y && (b - a).Cross(p - a) > 0) w++;
            }
            else if (b.Y <= p.Y && (b - a).Cross(p - a) < 0) w--;
        }
        return w != 0;
    }

    public static double Distance(IReadOnlyList<V2> poly, V2 p)
    {
        double best = double.MaxValue;
        for (int i = 0; i < poly.Count; i++) best = Math.Min(best, M.ProjectOnSegment(p, poly[i], poly[(i + 1) % poly.Count]).dist);
        return best;
    }

    public static List<V2> Clip(List<V2> poly, Rect r)
    {
        if (poly.Count == 0 || r.Contains(Bounds(poly))) return poly;
        var edges = new Func<V2, double>[]
        {
            p => p.X - r.MinX, p => r.MaxX - p.X, p => p.Y - r.MinY, p => r.MaxY - p.Y
        };
        var output = poly.ToList();
        foreach (var inside in edges)
        {
            var input = output; output = new();
            if (input.Count == 0) break;
            for (int i = 0; i < input.Count; i++)
            {
                var a = input[i]; var b = input[(i + 1) % input.Count];
                double da = inside(a), db = inside(b);
                if (da >= 0) output.Add(a);
                if ((da >= 0) != (db >= 0)) output.Add(a + (b - a) * (da / (da - db)));
            }
        }
        return Dedupe(output);
    }

    public static List<V2> Limb(IReadOnlyList<V2> line, double halfWidth)
    {
        if (line.Count < 2) return new();
        var left = new List<V2>(); var right = new List<V2>();
        for (int i = 0; i < line.Count; i++)
        {
            var a = line[Math.Max(i - 1, 0)]; var b = line[Math.Min(i + 1, line.Count - 1)];
            var n = (b - a).Normalized.Perp;
            left.Add(line[i] + n * halfWidth); right.Add(line[i] - n * halfWidth);
        }
        List<V2> Cap(V2 c, V2 d) => Enumerable.Range(1, 3).Select(k => c + d.Rotated(-k / 4.0 * Math.PI) * halfWidth).ToList();
        var d0 = (line[1] - line[0]).Normalized; var d1 = (line[^1] - line[^2]).Normalized;
        var result = new List<V2>(left);
        result.AddRange(Cap(line[^1], new V2(-d1.Y, d1.X)));
        result.AddRange(Enumerable.Reverse(right));
        result.AddRange(Cap(line[0], new V2(d0.Y, -d0.X)));
        return Clockwise(result);
    }

    public static List<V2> Hull(IEnumerable<V2> points)
    {
        var s = points.OrderBy(p => p.X).ThenBy(p => p.Y).ToList();
        if (s.Count <= 2) return s;
        List<V2> Half(IEnumerable<V2> ps)
        {
            var h = new List<V2>();
            foreach (var p in ps)
            {
                while (h.Count >= 2 && (h[^1] - h[^2]).Cross(p - h[^2]) <= 0) h.RemoveAt(h.Count - 1);
                h.Add(p);
            }
            return h;
        }
        var lower = Half(s); var upper = Half(Enumerable.Reverse(s));
        return Clockwise(lower.SkipLast(1).Concat(upper.SkipLast(1)).ToList());
    }

    public static List<V2> Grown(IReadOnlyList<V2> inPoly, double g)
    {
        var pts = Dedupe(inPoly); int n = pts.Count;
        if (n < 3) return pts;
        var output = new List<V2>();
        for (int i = 0; i < n; i++)
        {
            var p = pts[i]; var prev = pts[(i - 1 + n) % n]; var next = pts[(i + 1) % n];
            var d0 = (p - prev).Normalized; var d1 = (next - p).Normalized;
            var n0 = new V2(-d0.Y, d0.X); var n1 = new V2(-d1.Y, d1.X);
            double turn = d0.Cross(d1);
            double angle = Math.Acos(M.Clamp(d0.Dot(d1), -1, 1));
            if (angle < .02) output.Add(p + (n0 + n1).Normalized * g);
            else if (turn < 0)
            {
                int steps = Math.Max(1, (int)Math.Ceiling(angle / .4));
                for (int k = 0; k <= steps; k++) output.Add(p + n0.Rotated(-angle * k / steps) * g);
            }
            else
            {
                double back = g * Math.Tan(angle / 2);
                if (back < .95 * Math.Min(p.DistanceTo(prev), p.DistanceTo(next)))
                    output.Add(p + (n0 + n1) * (g / (1 + n0.Dot(n1))));
                else { output.Add(p + n0 * g); output.Add(p + n1 * g); }
            }
        }
        return Dedupe(output);
    }
}

/// <summary>The shapes the painters and the physics share, generated for all 221 Swift kinds.</summary>
public static class HabitatGeometry
{
    public static ObjectGeometry For(HabitatItem item)
    {
        var r = item.Rect;
        var g = HabitatShapes.Shape(item.Kind, r, item.Seed, item.Unit);
        if (item.Flip) g = g.Mirrored(r.Mid.X);
        double pad = HabitatShapes.Pad(r.W, r.H);
        var painted = r.Inset(-pad, -pad);
        g.Parts = g.Parts.Select(p => new ShapePart(p.Name, p.Role, Poly.Clip(p.Outline, painted)))
            .Where(p => p.Outline.Count >= 3 && Math.Abs(Poly.Area(p.Outline)) > 1).ToList();
        g.Visual = g.Visual.Select(v => Poly.Clip(v, painted)).Where(v => v.Count >= 3).ToList();
        if (item.OnGround)
        {
            double lip = r.MinY + 3;
            g.Parts = g.Parts.Select(p => new ShapePart(p.Name, p.Role,
                p.Outline.Select(q => q.Y < lip ? new V2(q.X, r.MinY - 3) : q))).ToList();
        }
        else if (item.Hangs)
        {
            double lip = r.MaxY - 3;
            g.Parts = g.Parts.Select(p => new ShapePart(p.Name, p.Role,
                p.Outline.Select(q => q.Y > lip ? new V2(q.X, r.MaxY + 3) : q))).ToList();
        }
        return g;
    }

    /// <summary>The shape used by a kind at an arbitrary rect (definitions, thumbnails).</summary>
    public static ObjectGeometry ForKind(HabitatItemKind kind, Rect r, int seed = 0, double unit = 1) =>
        HabitatShapes.Shape(kind, r, seed, unit);
}

public static class HabitatShapes
{
    public static double Rnd(int seed, int i)
    {
        double x = Math.Sin(seed * 12.9898 + i * 78.233) * 43758.5453;
        return x - Math.Floor(x);
    }

    public static double Pad(double w, double h) => Math.Max(10, Math.Min(w, h) * .14);

    static List<V2> Oval(double cx, double cy, double rx, double ry, int n = 22)
    {
        var ps = new List<V2>();
        for (int i = 0; i < n; i++) ps.Add(new V2(cx + Math.Cos(i * M.Tau / n) * rx, cy + Math.Sin(i * M.Tau / n) * ry));
        return Poly.Clockwise(ps);
    }

    static List<V2> Blob(Rect r, int seed, double x0, double x1, double y0, double y1, int n = 18)
    {
        var ps = new List<V2>();
        double cx = r.MinX + r.W * (x0 + x1) / 2, cy = r.MinY + r.H * (y0 + y1) / 2;
        double rx = r.W * (x1 - x0) / 2, ry = r.H * (y1 - y0) / 2;
        for (int i = 0; i < n; i++)
        {
            double a = i * M.Tau / n;
            double j = .92 + Rnd(seed, i) * .16;
            ps.Add(new V2(cx + Math.Cos(a) * rx * j, cy + Math.Sin(a) * ry * j));
        }
        return Poly.Clockwise(ps);
    }

    static List<V2> RectPoly(Rect r)
    {
        var o = new List<V2> { r.TopLeft, r.TopRight, r.BottomRight, r.BottomLeft };
        return Poly.Clockwise(o);
    }

    static List<V2> Line(double x0, double y0, double x1, double y1) => new() { new V2(x0, y0), new V2(x1, y1) };

    static List<V2> ArcLine(double cx, double cy, double rx, double ry, double a0, double a1, int n = 18)
    {
        var l = new List<V2>();
        for (int i = 0; i <= n; i++)
        {
            double a = M.Lerp(a0, a1, i / (double)n);
            l.Add(new V2(cx + Math.Cos(a) * rx, cy + Math.Sin(a) * ry));
        }
        return l;
    }

    static ObjectGeometry G(params ShapePart[] parts) => new() { Parts = parts.ToList() };
    static ShapePart Bulk(List<V2> p, string name = "body") => new(name, ShapeRole.Bulk, p);
    static ShapePart Limb(List<V2> line, double hw, string name = "limb") => new(name, ShapeRole.Limb, Poly.Limb(line, hw));
    static void Visual(ObjectGeometry g, List<V2> p) => g.Visual.Add(p);

    public static ObjectGeometry Shape(HabitatItemKind kind, Rect r, int seed, double u)
    {
        double W = r.W, H = r.H;
        var g = new ObjectGeometry();
        var d = kind.Definition();

        // Foliage and small details.
        switch (kind)
        {
            case HabitatItemKind.Fern: case HabitatItemKind.Grass: case HabitatItemKind.Flower:
            case HabitatItemKind.SmallFern: case HabitatItemKind.LargeFern: case HabitatItemKind.Fiddleheads:
            case HabitatItemKind.GrassClump: case HabitatItemKind.TinyFlowers: case HabitatItemKind.CreepingCover:
            case HabitatItemKind.Petals: case HabitatItemKind.PineNeedles: case HabitatItemKind.Moss:
            case HabitatItemKind.MossCushion: case HabitatItemKind.LeafPile: case HabitatItemKind.LeafHeap:
            case HabitatItemKind.FallenLeaf: case HabitatItemKind.DeadLeaf: case HabitatItemKind.LooseLeaf:
            case HabitatItemKind.Petal: case HabitatItemKind.Feather: case HabitatItemKind.Seed:
            case HabitatItemKind.TinyPebble: case HabitatItemKind.Pebbles: case HabitatItemKind.PebblePile:
            case HabitatItemKind.SmoothStones: case HabitatItemKind.Gravel: case HabitatItemKind.SandDrift:
            case HabitatItemKind.Twigs: case HabitatItemKind.TwigPile: case HabitatItemKind.TinyTwig:
            case HabitatItemKind.ShedBark: case HabitatItemKind.Lichen: case HabitatItemKind.Acorn:
            case HabitatItemKind.PineCone: case HabitatItemKind.SeaShell: case HabitatItemKind.SnailShell:
            case HabitatItemKind.SmallShell: case HabitatItemKind.SeedPod: case HabitatItemKind.Puddle:
            case HabitatItemKind.TinyMushrooms: case HabitatItemKind.MushroomCluster: case HabitatItemKind.Mushrooms:
            case HabitatItemKind.GlowMushrooms: case HabitatItemKind.Crystal: case HabitatItemKind.CrystalCluster:
                return SceneryShape(kind, r, seed, u);

            case HabitatItemKind.Plant: case HabitatItemKind.BroadLeaf: case HabitatItemKind.TrailingPlant:
            case HabitatItemKind.ClimbingVine: case HabitatItemKind.FloweringPlant: case HabitatItemKind.Aloe:
            case HabitatItemKind.JadePlant: case HabitatItemKind.Lithops: case HabitatItemKind.AirPlant:
            case HabitatItemKind.MiniPalm: case HabitatItemKind.DeadPlant: case HabitatItemKind.HangingFoliage:
            case HabitatItemKind.Cactus: case HabitatItemKind.Succulent:
                return PlantShape(kind, r, seed, u);

            case HabitatItemKind.Vine: case HabitatItemKind.ThinVine:
            case HabitatItemKind.ThickVine: case HabitatItemKind.Rope: case HabitatItemKind.HangingRoots:
            case HabitatItemKind.HangingHook: case HabitatItemKind.HangingBranch:
            case HabitatItemKind.HangingLeafShelter:
            case HabitatItemKind.HangingLamp: case HabitatItemKind.Lantern: case HabitatItemKind.Sign:
            case HabitatItemKind.Chandelier: case HabitatItemKind.VineClip:
                return HangingShape(kind, r, seed, u);

            case HabitatItemKind.WaterDish: case HabitatItemKind.RockPool:
                return DishShape(kind, r, seed, u);

            case HabitatItemKind.Bamboo: case HabitatItemKind.BambooPole: case HabitatItemKind.ClimbingRoot:
            case HabitatItemKind.DriedStem: case HabitatItemKind.Post: case HabitatItemKind.VerticalSupport:
            case HabitatItemKind.MetalStrut: case HabitatItemKind.Brace: case HabitatItemKind.WallRail:
            case HabitatItemKind.WallAnchor: case HabitatItemKind.GlassMount: case HabitatItemKind.SuctionCup:
            case HabitatItemKind.BranchBracket: case HabitatItemKind.ShelfBracket: case HabitatItemKind.AngleBracket:
            case HabitatItemKind.Stake: case HabitatItemKind.HorizontalSupport: case HabitatItemKind.CrossBrace:
                return UprightPieceShape(kind, r, seed, u);

            case HabitatItemKind.Branch: case HabitatItemKind.ThinBranch: case HabitatItemKind.MediumBranch:
            case HabitatItemKind.ThickBranch: case HabitatItemKind.ShortBranch: case HabitatItemKind.LongBranch:
            case HabitatItemKind.ForkedBranch: case HabitatItemKind.YBranch: case HabitatItemKind.CrookedBranch:
            case HabitatItemKind.Twig: case HabitatItemKind.Root: case HabitatItemKind.DriftwoodArch:
            case HabitatItemKind.DriftwoodSnag: case HabitatItemKind.BambooSegment: case HabitatItemKind.CorkSlab:
            case HabitatItemKind.BarkLedge: case HabitatItemKind.SlateLedge: case HabitatItemKind.TwistedBranch:
            case HabitatItemKind.ThreeFork: case HabitatItemKind.ExposedRoot: case HabitatItemKind.RootTangle:
            case HabitatItemKind.DriftwoodRoot: case HabitatItemKind.DriftwoodBranch: case HabitatItemKind.LianaLoop:
            case HabitatItemKind.StickRaft: case HabitatItemKind.MossPlatform: case HabitatItemKind.StoneArch:
            case HabitatItemKind.Beam: case HabitatItemKind.Plank: case HabitatItemKind.Plywood:
            case HabitatItemKind.Dowel: case HabitatItemKind.Pipe: case HabitatItemKind.Floorboards:
            case HabitatItemKind.GableRoof: case HabitatItemKind.KneeBrace: case HabitatItemKind.StringLights:
                return BranchShape(kind, r, seed, u);

            case HabitatItemKind.CorkBark: case HabitatItemKind.CorkTube: case HabitatItemKind.LeaningBark:
            case HabitatItemKind.Stump: case HabitatItemKind.Log: case HabitatItemKind.Driftwood:
            case HabitatItemKind.Hide: case HabitatItemKind.Boulder: case HabitatItemKind.Rock:
            case HabitatItemKind.RockSpire: case HabitatItemKind.BaskingStone:
                return LogRockShape(kind, r, seed, u);

            case HabitatItemKind.BarkCave: case HabitatItemKind.RockCrevice: case HabitatItemKind.LogDen:
            case HabitatItemKind.CurledLeafHide: case HabitatItemKind.LeafCanopy: case HabitatItemKind.RootHollow:
            case HabitatItemKind.MossyHide: case HabitatItemKind.Overhang: case HabitatItemKind.ShelterCanopy:
            case HabitatItemKind.CorkTunnel:
                return ShelterShape(kind, r, seed, u);
        }

        if (d.Category == HabitatCategory.Perch) return FurnitureShape(kind, r, seed, u);
        return SceneryShape(kind, r, seed, u);
    }

    static ObjectGeometry SceneryShape(HabitatItemKind kind, Rect r, int seed, double u)
    {
        var g = new ObjectGeometry();
        double W = r.W, H = r.H;
        switch (kind)
        {
            case HabitatItemKind.Puddle:
                g.Visual.Add(Oval(r.Mid.X, r.MinY + H * .22, W * .49, H * .22));
                break;
            case HabitatItemKind.Crystal:
            case HabitatItemKind.CrystalCluster:
            {
                int n = kind == HabitatItemKind.CrystalCluster ? 5 : 3;
                for (int i = 0; i < n; i++)
                {
                    double x = r.MinX + W * (.18 + .64 * i / Math.Max(1, n - 1));
                    double hh = H * (.55 + .45 * Rnd(seed, i));
                    double bw = W / n * .32;
                    var poly = new List<V2> { new(x, r.MinY), new(x - bw, r.MinY + hh * .35), new(x, r.MinY + hh), new(x + bw, r.MinY + hh * .45) };
                    g.Parts.Add(Bulk(Poly.Clockwise(poly), "crystal"));
                }
                break;
            }
            case HabitatItemKind.Mushrooms:
            case HabitatItemKind.Mushroom:
            case HabitatItemKind.MushroomCluster:
            case HabitatItemKind.GlowMushrooms:
            case HabitatItemKind.TinyMushrooms:
            {
                int n = kind is HabitatItemKind.MushroomCluster or HabitatItemKind.Mushrooms or HabitatItemKind.TinyMushrooms ? 3 : 1;
                for (int i = 0; i < n; i++)
                {
                    double cx = r.MinX + W * (n == 1 ? .5 : .24 + .26 * i);
                    double hh = H * (.48 + .42 * Rnd(seed, i));
                    double sw = W / (n + 1) * .18;
                    g.Parts.Add(Limb(Line(cx, r.MinY, cx + (i - 1) * 3, r.MinY + hh * .62), sw, "stem"));
                    g.Visual.Add(Oval(cx, r.MinY + hh * .68, W / (n + 1) * .44, H * .28, 18));
                }
                break;
            }
            case HabitatItemKind.SeaShell: case HabitatItemKind.SnailShell: case HabitatItemKind.SmallShell:
            {
                var c = new V2(r.Mid.X, r.MinY + H * .42);
                var outer = new List<V2>();
                for (int i = 0; i <= 28; i++)
                {
                    double a = i * 2.8 * Math.PI / 28;
                    double rad = W * .48 * (1 - i / 38.0);
                    outer.Add(new V2(c.X + Math.Cos(a) * rad, c.Y + Math.Sin(a) * rad * .62 + H * .08));
                }
                g.Visual.Add(Poly.Clockwise(Poly.Dedupe(outer)));
                break;
            }
            case HabitatItemKind.FallenLeaf: case HabitatItemKind.DeadLeaf: case HabitatItemKind.CurledLeaf:
            case HabitatItemKind.LooseLeaf: case HabitatItemKind.Petal: case HabitatItemKind.Petals:
            case HabitatItemKind.Feather: case HabitatItemKind.Seed:
            {
                var leaf = new List<V2> {
                    new(r.MinX, r.MinY + H*.4), new(r.MinX+W*.3,r.MinY+H*.75), new(r.Mid.X,r.MinY+H*.95),
                    new(r.MaxX-W*.18,r.MinY+H*.6), new(r.MaxX,r.MinY+H*.35), new(r.Mid.X,r.MinY+H*.12)
                };
                g.Visual.Add(Poly.Clockwise(leaf));
                break;
            }
            case HabitatItemKind.PineCone: case HabitatItemKind.Acorn: case HabitatItemKind.SeedPod:
            {
                var o = Blob(r, seed, .18, .82, .12, .88, 14);
                g.Visual.Add(o);
                break;
            }
            case HabitatItemKind.Pebbles: case HabitatItemKind.PebblePile: case HabitatItemKind.SmoothStones:
            case HabitatItemKind.TinyPebble: case HabitatItemKind.Gravel:
            {
                int n = kind == HabitatItemKind.SmoothStones ? 3 : Math.Max(3, (int)(W / 22));
                for (int i = 0; i < n; i++)
                {
                    double cx = r.MinX + W * (i + .5) / n;
                    double cy = r.MinY + H * (.2 + .35 * Rnd(seed, i));
                    var stone = Oval(cx, cy, W / n * .52, H * (.28 + .2 * Rnd(seed, i + 20)), 11);
                    g.Parts.Add(Bulk(stone, "stone"));
                }
                break;
            }
            case HabitatItemKind.Moss: case HabitatItemKind.LeafPile: case HabitatItemKind.LeafHeap:
            case HabitatItemKind.SandDrift: case HabitatItemKind.PineNeedles:
            case HabitatItemKind.Twigs: case HabitatItemKind.TwigPile: case HabitatItemKind.ShedBark:
            case HabitatItemKind.CreepingCover:
            {
                g.Visual.Add(Blob(r, seed, .02, .98, .02, .52, 18));
                break;
            }
            case HabitatItemKind.Lichen:
            {
                for (int i = 0; i < 3; i++) g.Visual.Add(Oval(r.MinX + W * (.2 + i * .28), r.MinY + H * .4, W * .18, H * .25, 10));
                break;
            }
            default:
            {
                g.Visual.Add(Blob(r, seed, .2, .8, .08, .5, 14));
                break;
            }
        }
        return g;
    }

    static ObjectGeometry PlantShape(HabitatItemKind kind, Rect r, int seed, double u)
    {
        var g = new ObjectGeometry();
        double W = r.W, H = r.H;
        if (kind == HabitatItemKind.Lithops)
        {
            g.Parts.Add(Bulk(Blob(r, seed, .1, .9, 0, .65, 12), "body"));
            return g;
        }
        // A pot at the foot and stems/leaves above it. A perch plant has a climbable stem.
        var pot = new List<V2> {
            new(r.Mid.X - W*.22, r.MinY), new(r.Mid.X + W*.22, r.MinY),
            new(r.Mid.X + W*.3, r.MinY+H*.22), new(r.Mid.X - W*.3, r.MinY+H*.22)
        };
        g.Parts.Add(Bulk(Poly.Clockwise(pot), "pot"));
        int stems = kind is HabitatItemKind.Aloe or HabitatItemKind.Succulent or HabitatItemKind.AirPlant ? 5 : 3;
        for (int i = 0; i < stems; i++)
        {
            double bx = r.Mid.X + (i - (stems - 1) / 2.0) * W * .14;
            double topx = bx + (i - (stems - 1) / 2.0) * W * .18 + (Rnd(seed, i) - .5) * W * .12;
            double topy = r.MinY + H * (.42 + .5 * Rnd(seed, i + 7));
            var line = new List<V2> { new(bx, r.MinY + H * .2), new((bx + topx) / 2 + W * .06, (r.MinY + topy) / 2), new(topx, topy) };
            if (kind is HabitatItemKind.Grass or HabitatItemKind.GrassClump or HabitatItemKind.DeadPlant or HabitatItemKind.TinyFlowers)
                g.Visual.Add(Poly.Limb(line, Math.Max(1.5, W * .018)));
            else if (kind == HabitatItemKind.AirPlant)
                g.Visual.Add(Poly.Limb(ArcLine(bx, r.MinY + H * .32, W * .28, H * .2, M.Pi, M.Tau, 10), W * .04));
            else
                g.Parts.Add(Limb(line, Math.Max(2, W * .035), "stem"));
            if (kind is HabitatItemKind.Flower or HabitatItemKind.FloweringPlant or HabitatItemKind.TinyFlowers)
                g.Visual.Add(Oval(topx, topy, W * .12, H * .08, 12));
        }
        // Broad leaves: visual foliage spilling beyond the pot.
        if (kind is HabitatItemKind.Plant or HabitatItemKind.BroadLeaf or HabitatItemKind.MiniPalm or
            HabitatItemKind.Fern or HabitatItemKind.LargeFern or HabitatItemKind.TrailingPlant or
            HabitatItemKind.ClimbingVine or HabitatItemKind.HangingFoliage or HabitatItemKind.JadePlant or
            HabitatItemKind.Aloe)
        {
            int leaves = kind == HabitatItemKind.Aloe ? 6 : 4;
            for (int i = 0; i < leaves; i++)
            {
                double cx = r.MinX + W * (.12 + .76 * i / Math.Max(1, leaves - 1));
                double cy = r.MinY + H * (.3 + .45 * Rnd(seed, i + 30));
                var leaf = new List<V2> {
                    new(r.Mid.X, r.MinY + H*.22), new(cx-W*.18, cy+H*.1), new(cx, cy+H*.24), new(cx+W*.18,cy+H*.08)
                };
                g.Visual.Add(Poly.Clockwise(leaf));
            }
        }
        return g;
    }

    static ObjectGeometry HangingShape(HabitatItemKind kind, Rect r, int seed, double u)
    {
        var g = new ObjectGeometry();
        double W = r.W, H = r.H;
        var line = new List<V2>();
        double x = r.Mid.X;
        for (int i = 0; i <= 12; i++)
        {
            double t = i / 12.0;
            line.Add(new V2(x + Math.Sin(t * 5 * Math.PI + seed) * W * .12, r.MaxY - H * t));
        }
        g.Parts.Add(Limb(line, Math.Max(2.5, W * .16), "vine"));
        if (kind is HabitatItemKind.HangingRoots or HabitatItemKind.HangingFoliage)
        {
            for (int i = 0; i < 3; i++)
                g.Visual.Add(Poly.Limb(ArcLine(r.MinX + W * (.25 + i * .25), r.MinY + H * .45, W * .18, H * .3, M.Pi, M.Tau, 8), W * .035));
        }
        else if (kind is HabitatItemKind.HangingBranch)
        {
            g.Parts.Add(Limb(ArcLine(r.Mid.X, r.MinY + H * .32, W * .4, H * .12, M.Pi * .15, M.Pi * .85, 10), W * .05, "branch"));
            g.Visual.Add(Oval(r.Mid.X, r.MinY + H * .2, W * .1, H * .04, 10));
        }
        else if (kind is HabitatItemKind.HangingLeafShelter)
        {
            g.Visual.Add(Blob(r, seed, .08, .92, .18, .9, 16));
        }
        else if (kind is HabitatItemKind.HangingLamp or HabitatItemKind.Lantern or HabitatItemKind.Chandelier)
        {
            g.Visual.Add(Poly.Clockwise(new List<V2> { new(r.Mid.X - W*.3,r.MinY+H*.2), new(r.Mid.X+W*.3,r.MinY+H*.2), new(r.Mid.X+W*.18,r.MinY+H*.45), new(r.Mid.X-W*.18,r.MinY+H*.45) }));
        }
        else if (kind is HabitatItemKind.Sign)
        {
            g.Visual.Add(RectPoly(new Rect(r.MinX, r.MinY + H * .1, W * .85, H * .32)));
        }
        return g;
    }

    static ObjectGeometry DishShape(HabitatItemKind kind, Rect r, int seed, double u)
    {
        var g = new ObjectGeometry();
        double W = r.W, H = r.H;
        var outer = new List<V2> {
            new(r.MinX + W*.04, r.MinY+H*.05), new(r.MinX + W*.12, r.MinY),
            new(r.MaxX - W*.12, r.MinY), new(r.MaxX - W*.04, r.MinY+H*.05),
            new(r.MaxX - W*.08, r.MinY+H*.75), new(r.Mid.X, r.MinY+H*.9),
            new(r.MinX + W*.08, r.MinY+H*.75)
        };
        g.Parts.Add(Bulk(Poly.Clockwise(outer), "bowl"));
        var water = Oval(r.Mid.X, r.MinY + H * .76, W * .42, H * .12, 22);
        g.Visual.Add(water);
        g.Anchors.Add(new ObjectAnchor(AnchorKind.Drink, new V2(r.MaxX - W * .16, r.MinY + H * .82), new V2(.5, .5).Normalized));
        g.Anchors.Add(new ObjectAnchor(AnchorKind.Perch, new V2(r.Mid.X, r.MinY + H * .88), new V2(0, 1)));
        return g;
    }

    static ObjectGeometry UprightPieceShape(HabitatItemKind kind, Rect r, int seed, double u)
    {
        var g = new ObjectGeometry();
        double W = r.W, H = r.H;
        if (kind is HabitatItemKind.BranchBracket or HabitatItemKind.ShelfBracket or HabitatItemKind.AngleBracket)
        {
            g.Parts.Add(Bulk(RectPoly(new Rect(r.MinX, r.MinY + H * .55, W, H * .45)), "bracket"));
            g.Parts.Add(Limb(Line(r.MinX + W * .2, r.MinY, r.MinX + W * .2, r.MinY + H * .55), Math.Max(2, W * .06), "stem"));
        }
        else if (kind == HabitatItemKind.SuctionCup || kind == HabitatItemKind.GlassMount)
        {
            g.Parts.Add(Bulk(Oval(r.Mid.X, r.MinY + H * .45, W * .38, H * .35, 16), "cup"));
            g.Parts.Add(Limb(Line(r.Mid.X, r.MinY + H * .55, r.Mid.X, r.MinY + H), Math.Max(2, W * .08), "clip"));
        }
        else if (kind == HabitatItemKind.WallAnchor)
        {
            g.Parts.Add(Bulk(RectPoly(r.Inset(W * .25, H * .2)), "anchor"));
        }
        else if (kind == HabitatItemKind.CrossBrace)
        {
            g.Parts.Add(Limb(Line(r.MinX, r.MinY, r.MaxX, r.MaxY), Math.Max(2, W * .04), "brace"));
            g.Parts.Add(Limb(Line(r.MinX, r.MaxY, r.MaxX, r.MinY), Math.Max(2, W * .04), "brace"));
        }
        else
        {
            g.Parts.Add(Limb(Line(r.Mid.X, r.MinY, r.Mid.X + Math.Sin(seed) * W * .05, r.MaxY),
                Math.Max(2.5, W * .38), "stem"));
            if (kind == HabitatItemKind.Stake)
                g.Parts.Add(Limb(Line(r.Mid.X, r.MaxY - H * .08, r.Mid.X + W * .45, r.MaxY - H * .2), Math.Max(2, W * .18), "fork"));
            if (kind is HabitatItemKind.WallRail or HabitatItemKind.HorizontalSupport)
                g.Parts.Add(Limb(Line(r.MinX, r.MinY + H * .5, r.MaxX, r.MinY + H * .5), Math.Max(2, H * .35), "rail"));
        }
        BottomAnchors(g, r);
        return g;
    }

    static ObjectGeometry BranchShape(HabitatItemKind kind, Rect r, int seed, double u)
    {
        var g = new ObjectGeometry();
        double W = r.W, H = r.H;
        bool flat = kind is HabitatItemKind.CorkSlab or HabitatItemKind.BarkLedge or HabitatItemKind.SlateLedge or
            HabitatItemKind.StickRaft or HabitatItemKind.MossPlatform or HabitatItemKind.Beam or
            HabitatItemKind.Plank or HabitatItemKind.Plywood or HabitatItemKind.Dowel or
            HabitatItemKind.Floorboards or HabitatItemKind.StringLights or HabitatItemKind.Pipe;
        if (flat)
        {
            double thick = Math.Max(3, H * .72);
            var p = RectPoly(new Rect(r.MinX, r.MinY + H * .08, W, thick));
            g.Parts.Add(Bulk(p, "platform"));
            g.Anchors.Add(new ObjectAnchor(AnchorKind.Perch, new V2(r.Mid.X, r.MinY + H * .8 + .08 * H), new V2(0, 1)));
            if (kind == HabitatItemKind.GableRoof)
                g.Parts.Add(Bulk(Poly.Clockwise(new List<V2> { new(r.MinX,r.MinY+H*.1), new(r.Mid.X,r.MaxY), new(r.MaxX,r.MinY+H*.1) }), "roof"));
            return g;
        }
        // A bent limb from the lower left to the upper right, with forks.
        var line = new List<V2>
        {
            new(r.MinX + W*.04, r.MinY + H*.12),
            new(r.MinX + W*.32, r.MinY + H*(.42 + .1*Rnd(seed,1))),
            new(r.MinX + W*.62, r.MinY + H*(.56 + .12*Rnd(seed,2))),
            new(r.MaxX - W*.03, r.MinY + H*.76)
        };
        double hw = Math.Max(2, Math.Min(W * .045, H * .16));
        g.Parts.Add(Limb(line, hw, "branch"));
        if (kind is HabitatItemKind.ForkedBranch or HabitatItemKind.YBranch or HabitatItemKind.ThreeFork)
        {
            var fork = line[2];
            g.Parts.Add(Limb(new List<V2> { fork, new(r.MinX + W*.75, r.MaxY - H*.08) }, hw * .8, "fork"));
            if (kind == HabitatItemKind.ThreeFork)
                g.Parts.Add(Limb(new List<V2> { fork, new(r.MinX + W*.48, r.MaxY - H*.12) }, hw * .75, "fork"));
        }
        if (kind is HabitatItemKind.TwistedBranch or HabitatItemKind.RootTangle)
        {
            g.Parts.Add(Limb(new List<V2> { new(r.MinX+W*.12,r.MinY+H*.2), new(r.MinX+W*.55,r.MinY+H*.34), new(r.MaxX-W*.12,r.MinY+H*.6) }, hw*.65, "branch"));
        }
        if (kind is HabitatItemKind.StoneArch)
        {
            g.Parts.Add(Limb(ArcLine(r.Mid.X, r.MinY + H*.05, W*.44, H*.8, M.Pi, M.Tau, 20), Math.Max(4, W*.07), "arch"));
        }
        if (kind is HabitatItemKind.ExposedRoot or HabitatItemKind.DriftwoodRoot)
        {
            g.Parts.Add(Limb(ArcLine(r.Mid.X, r.MinY, W*.4, H*.7, M.Pi*.05, M.Pi*.95, 12), hw, "root"));
        }
        if (kind == HabitatItemKind.KneeBrace)
        {
            g.Parts.Add(Limb(Line(r.MinX, r.MinY, r.MaxX, r.MaxY), hw, "brace"));
        }
        g.Anchors.Add(new ObjectAnchor(AnchorKind.Tie, line[^1], new V2(0, 1)));
        if (kind is HabitatItemKind.Branch or HabitatItemKind.LongBranch or HabitatItemKind.MediumBranch)
            g.Anchors.Add(new ObjectAnchor(AnchorKind.Lookout, line[^1] + new V2(0, 4), new V2(0, 1)));
        return g;
    }

    static ObjectGeometry LogRockShape(HabitatItemKind kind, Rect r, int seed, double u)
    {
        var g = new ObjectGeometry();
        double W = r.W, H = r.H;
        switch (kind)
        {
            case HabitatItemKind.Rock:
            case HabitatItemKind.Boulder:
            case HabitatItemKind.BaskingStone:
            case HabitatItemKind.RockSpire:
            {
                if (kind == HabitatItemKind.RockSpire)
                {
                    double y = r.MinY; int n = 4;
                    for (int i = 0; i < n; i++)
                    {
                        double hh = H / n * 1.15;
                        g.Parts.Add(Bulk(Blob(new Rect(r.MinX + W*(.05+.04*i), y, W*(.9-.08*i), hh), seed+i, .02,.98,0,1, 12), "rock"));
                        y += hh * .72;
                    }
                }
                else
                {
                    g.Parts.Add(Bulk(Blob(r, seed, .02, .98, 0, 1, 22), "rock"));
                }
                g.Anchors.Add(new ObjectAnchor(AnchorKind.Bask, new V2(r.Mid.X, r.MaxY - H*.08), new V2(0,1)));
                break;
            }
            case HabitatItemKind.Log:
            case HabitatItemKind.Driftwood:
            case HabitatItemKind.CorkBark:
            case HabitatItemKind.CorkTube:
            case HabitatItemKind.Hide:
            case HabitatItemKind.Stump:
            case HabitatItemKind.LeaningBark:
            case HabitatItemKind.DriftwoodSnag:
            {
                if (kind is HabitatItemKind.CorkBark or HabitatItemKind.LeaningBark)
                {
                    g.Parts.Add(Bulk(Blob(r, seed, .08, .92, 0, 1, 16), "bark"));
                }
                else if (kind is HabitatItemKind.DriftwoodSnag)
                {
                    g.Parts.Add(Limb(new List<V2>{new(r.MinX+W*.3,r.MinY),new(r.Mid.X,r.MinY+H*.58),new(r.Mid.X+W*.18,r.MaxY)}, W*.18, "snag"));
                    g.Parts.Add(Limb(Line(r.Mid.X,r.MinY+H*.38,r.MaxX-W*.08,r.MinY+H*.72), W*.08, "snag"));
                }
                else if (kind is HabitatItemKind.CorkTube or HabitatItemKind.Driftwood)
                {
                    g.Parts.Add(Bulk(Oval(r.Mid.X, r.MinY + H*.5, W*.47, H*.42, 20), "body"));
                }
                else
                {
                    var body = new List<V2> {
                        new(r.MinX+W*.02,r.MinY+H*.34), new(r.MinX+W*.18,r.MinY+H*.9),
                        new(r.MinX+W*.45,r.MaxY), new(r.MaxX-W*.12,r.MinY+H*.82),
                        new(r.MaxX-W*.02,r.MinY+H*.22), new(r.MinX+W*.3,r.MinY+H*.02)
                    };
                    g.Parts.Add(Bulk(Poly.Clockwise(body), "log"));
                    if (kind == HabitatItemKind.Hide || kind == HabitatItemKind.CorkTube)
                    {
                        var cavity = Poly.Clockwise(new List<V2> {
                            new(r.MinX+W*.2,r.MinY+H*.3), new(r.MinX+W*.3,r.MinY+H*.68),
                            new(r.MaxX-W*.18,r.MinY+H*.64), new(r.MaxX-W*.24,r.MinY+H*.24)
                        });
                        g.Hollows.Add(new Hollow { Cavity = cavity, Mouth = new V2(r.MinX + W*.18, r.MinY + H*.45), Inward = new V2(1,0) });
                        g.Anchors.Add(new ObjectAnchor(AnchorKind.Entrance, new V2(r.MinX + W*.18, r.MinY + H*.45), new V2(-1,0)));
                        g.Anchors.Add(new ObjectAnchor(AnchorKind.Refuge, cavity.Aggregate(V2.Zero,(a,b)=>a+b)/4, new V2(1,0)));
                    }
                }
                break;
            }
        }
        BottomAnchors(g, r);
        return g;
    }

    static ObjectGeometry ShelterShape(HabitatItemKind kind, Rect r, int seed, double u)
    {
        var g = new ObjectGeometry();
        double W = r.W, H = r.H;
        bool rightOpening = kind is HabitatItemKind.RockCrevice or HabitatItemKind.CurledLeafHide or HabitatItemKind.Overhang or HabitatItemKind.ShelterCanopy;
        double mouthX = rightOpening ? r.MaxX - W*.16 : r.MinX + W*.16;
        var shell = new List<V2>();
        int n = 18;
        for (int i = 0; i <= n; i++)
        {
            double a = M.Pi + i / (double)n * M.Pi;
            shell.Add(new V2(r.Mid.X + Math.Cos(a) * W*.47, r.MinY + H*.08 + Math.Sin(a) * H*.84));
        }
        shell.Add(new V2(r.MaxX - W*.06, r.MinY));
        shell.Add(new V2(r.MinX + W*.06, r.MinY));
        g.Parts.Add(Bulk(Poly.Clockwise(shell), "shell"));
        var cavity = new List<V2>();
        for (int i = 0; i <= 12; i++)
        {
            double a = M.Pi + i / 12.0 * M.Pi;
            cavity.Add(new V2(r.Mid.X + Math.Cos(a) * W*.33, r.MinY + H*.12 + Math.Sin(a) * H*.55));
        }
        cavity.Add(new V2(r.Mid.X + W*.2, r.MinY + H*.12));
        cavity.Add(new V2(r.Mid.X - W*.2, r.MinY + H*.12));
        g.Hollows.Add(new Hollow { Cavity = Poly.Clockwise(cavity), Mouth = new V2(mouthX, r.MinY + H*.22), Inward = new V2(rightOpening ? -1 : 1, .2).Normalized });
        g.Anchors.Add(new ObjectAnchor(AnchorKind.Entrance, new V2(mouthX, r.MinY + H*.24), new V2(rightOpening ? -1 : 1, 0)));
        g.Anchors.Add(new ObjectAnchor(AnchorKind.Refuge, new V2(r.Mid.X, r.MinY + H*.36), new V2(0,1)));
        g.Anchors.Add(new ObjectAnchor(AnchorKind.Perch, new V2(r.Mid.X, r.MinY + H*.94), new V2(0,1)));
        return g;
    }

    static ObjectGeometry FurnitureShape(HabitatItemKind kind, Rect r, int seed, double u)
    {
        var g = new ObjectGeometry();
        double W = r.W, H = r.H;
        switch (kind)
        {
            case HabitatItemKind.Door:
            case HabitatItemKind.DoorClosed:
            case HabitatItemKind.Window:
            case HabitatItemKind.WindowOpen:
            {
                double jamb = Math.Max(3, W * .13);
                g.Parts.Add(Bulk(RectPoly(new Rect(r.MinX, r.MinY, jamb, H)), "post"));
                g.Parts.Add(Bulk(RectPoly(new Rect(r.MaxX - jamb, r.MinY, jamb, H)), "post"));
                g.Parts.Add(Bulk(RectPoly(new Rect(r.MinX, r.MaxY - H*.12, W, H*.12)), "lintel"));
                if (kind is HabitatItemKind.DoorClosed or HabitatItemKind.Window)
                    g.Parts.Add(Bulk(RectPoly(new Rect(r.MinX + jamb, r.MinY, W - 2*jamb, H*.88)), "leaf"));
                break;
            }
            case HabitatItemKind.Stairs:
            {
                int n = 5;
                for (int i = 0; i < n; i++)
                    g.Parts.Add(Bulk(RectPoly(new Rect(r.MinX + W*i/n, r.MinY, W/n, H*(i+1)/n)), "step"));
                break;
            }
            case HabitatItemKind.Fence:
            {
                g.Parts.Add(Bulk(RectPoly(new Rect(r.MinX, r.MinY + H*.58, W, H*.16)), "rail"));
                int n = 5;
                for (int i = 0; i < n; i++)
                    g.Parts.Add(Bulk(RectPoly(new Rect(r.MinX + W*(.04+.22*i), r.MinY, W*.06, H*.62)), "picket"));
                break;
            }
            case HabitatItemKind.Bed: case HabitatItemKind.BunkBed: case HabitatItemKind.Sofa:
            case HabitatItemKind.Armchair: case HabitatItemKind.Beanbag: case HabitatItemKind.Chair:
            case HabitatItemKind.Table: case HabitatItemKind.Desk: case HabitatItemKind.Dresser:
            case HabitatItemKind.Wardrobe: case HabitatItemKind.Bookshelf: case HabitatItemKind.Counter:
            case HabitatItemKind.Fridge: case HabitatItemKind.Piano: case HabitatItemKind.Stove:
            case HabitatItemKind.Chest: case HabitatItemKind.Bathtub: case HabitatItemKind.Crate:
            case HabitatItemKind.Fireplace:
            {
                double leg = kind is HabitatItemKind.Table or HabitatItemKind.Desk ? H*.38 : H*.05;
                if (leg > 2)
                {
                    g.Parts.Add(Bulk(RectPoly(new Rect(r.MinX + W*.1, r.MinY, W*.08, leg)), "leg"));
                    g.Parts.Add(Bulk(RectPoly(new Rect(r.MaxX - W*.18, r.MinY, W*.08, leg)), "leg"));
                }
                g.Parts.Add(Bulk(RectPoly(new Rect(r.MinX, r.MinY + leg, W, Math.Max(4, H - leg))), "body"));
                break;
            }
            case HabitatItemKind.Ladder:
            {
                g.Parts.Add(Limb(Line(r.MinX + W*.18, r.MinY, r.MinX + W*.18, r.MaxY), Math.Max(2, W*.06), "rail"));
                g.Parts.Add(Limb(Line(r.MaxX - W*.18, r.MinY, r.MaxX - W*.18, r.MaxY), Math.Max(2, W*.06), "rail"));
                for (int i = 1; i < 6; i++)
                    g.Parts.Add(Limb(Line(r.MinX+W*.18, r.MinY+H*i/6, r.MaxX-W*.18, r.MinY+H*i/6), Math.Max(1.5, W*.04), "rung"));
                break;
            }
            case HabitatItemKind.FloorLamp: case HabitatItemKind.Houseplant: case HabitatItemKind.Spool:
            case HabitatItemKind.Teacup: case HabitatItemKind.Vase: case HabitatItemKind.Globe:
            case HabitatItemKind.Trophy: case HabitatItemKind.Candle: case HabitatItemKind.StringLights:
            case HabitatItemKind.Lantern: case HabitatItemKind.Sconce:
            {
                g.Parts.Add(Bulk(Oval(r.Mid.X, r.MinY + H*.18, W*.35, H*.18, 14), "base"));
                if (kind is HabitatItemKind.FloorLamp) g.Parts.Add(Limb(Line(r.Mid.X, r.MinY+H*.18, r.Mid.X, r.MaxY-H*.15), Math.Max(1.5, W*.06), "stem"));
                g.Visual.Add(Oval(r.Mid.X, r.MaxY - H*.25, W*.28, H*.25, 14));
                break;
            }
            case HabitatItemKind.Picture: case HabitatItemKind.Painting: case HabitatItemKind.Poster:
            case HabitatItemKind.Mirror: case HabitatItemKind.BackWindow: case HabitatItemKind.Dartboard:
            case HabitatItemKind.Clock:
            {
                g.Parts.Add(Bulk(RectPoly(r.Inset(W*.06, H*.06)), "frame"));
                g.Visual.Add(RectPoly(r.Inset(W*.13, H*.13)));
                break;
            }
            case HabitatItemKind.Rug: case HabitatItemKind.Wallpaper: case HabitatItemKind.WoodBacking:
            case HabitatItemKind.BrickBacking: case HabitatItemKind.StoneBacking: case HabitatItemKind.LogBacking:
            case HabitatItemKind.BackPanel: case HabitatItemKind.Pegboard: case HabitatItemKind.Curtains:
            {
                g.Parts.Add(Bulk(RectPoly(r), "backing"));
                break;
            }
            default:
            {
                // A recognisable, climbable box silhouette with a top and a small foot.
                double body = H * .82;
                g.Parts.Add(Bulk(Blob(r, seed, .04, .96, .02, .96, 14), "body"));
                g.Anchors.Add(new ObjectAnchor(AnchorKind.Perch, new V2(r.Mid.X, r.MinY + body), new V2(0,1)));
                break;
            }
        }
        BottomAnchors(g, r);
        return g;
    }

    static void BottomAnchors(ObjectGeometry g, Rect r)
    {
        g.Anchors.Add(new ObjectAnchor(AnchorKind.Perch, new V2(r.Mid.X, r.MaxY - 2), new V2(0, 1)));
        g.Anchors.Add(new ObjectAnchor(AnchorKind.Tie, new V2(r.MinX + r.W * .15, r.MaxY - 2), new V2(0, 1)));
    }
}

/// <summary>The tank's surfaces: loops and the junctions between them.</summary>
public sealed class HabitatSurfaces
{
    public Rect Air;
    public List<SurfaceLoop> Loops = new();
    public List<SurfaceJunction> Junctions = new();
}

public static class HabitatSurfaceBuilder
{
    public static HabitatSurfaces Build(HabitatWorld h, double scale)
    {
        double off = SurfaceMap.StandoffFor(scale);
        var air = h.Air;
        var result = new HabitatSurfaces { Air = air };
        if (air.W <= 2 * off + 40 || air.H <= 2 * off + 40) return result;

        // Ground-level things merge into the tank's floor contour, so it really walks over them.
        var groundItems = h.Items.Where(i => i.Kind.Climbable() && !i.Kind.Hangs() && i.OnGround)
            .OrderBy(i => i.X).ToList();
        var floor = new List<V2> { new(air.MinX, air.MinY) };
        var owners = new List<int>();
        foreach (var it in groundItems)
        {
            var g = HabitatGeometry.For(it);
            var poly = LargestPart(g);
            if (poly.Count < 3) continue;
            var cut = ClipToAbove(poly, air.MinY);
            if (cut.Count < 3) continue;
            var upper = UpperChain(cut, air.MinY);
            if (upper.Count < 2) continue;
            if (upper[0].X > upper[^1].X) upper.Reverse();
            foreach (var p in upper)
            {
                if (p.X <= floor[^1].X + .25) continue;
                floor.Add(new V2(p.X, Math.Max(air.MinY, p.Y)));
            }
        }
        floor.Add(new V2(air.MaxX, air.MinY));

        var rim = new SurfaceLoop
        {
            Id = "screen:0", Kind = SurfaceKind.ScreenBorder, Closed = true, Depth = 1_000_000,
            Rect = air, CornerRadius = 0, IsWindowRect = false
        };
        // Floor runs left to right, then up the right wall, across the lid and down the left wall.
        for (int i = 1; i < floor.Count; i++) AddSeg(rim, floor[i - 1], floor[i], EdgeFacing.Up);
        AddSeg(rim, new V2(air.MaxX - off, air.MinY), new V2(air.MaxX - off, air.MaxY), EdgeFacing.Left);
        AddSeg(rim, new V2(air.MaxX - off, air.MaxY), new V2(air.MinX + off, air.MaxY), EdgeFacing.Down);
        AddSeg(rim, new V2(air.MinX + off, air.MaxY), new V2(air.MinX + off, air.MinY), EdgeFacing.Right);
        rim.Edge.AddRange(floor);
        rim.Edge.Add(new V2(air.MaxX, air.MaxY));
        rim.Edge.Add(new V2(air.MinX, air.MaxY));
        rim.Edge.Add(new V2(air.MinX, air.MinY));
        rim.Owners = new int[rim.Segs.Count];
        result.Loops.Add(rim);

        int owner = 1;
        foreach (var item in h.Items.Where(i => i.Kind.Climbable() && !(i.OnGround && !i.Kind.Hangs())))
        {
            var geo = HabitatGeometry.For(item);
            int partNo = 0;
            foreach (var part in geo.Parts)
            {
                if (part.Outline.Count < 3) continue;
                var grown = Poly.Grown(part.Outline, part.Role == ShapeRole.Bulk ? off : Math.Max(2, off * .7));
                if (grown.Count < 3) continue;
                grown = Poly.Clip(grown, new Rect(air.MinX + 1, air.MinY + 1, air.W - 2, air.H - 2));
                if (grown.Count < 3) continue;
                grown = Poly.Clockwise(Poly.Dedupe(grown));
                var loop = LoopFromPolygon(grown, $"item:{item.Id}" + (partNo > 0 ? $"~{partNo}" : ""), item, owner);
                if (loop.Segs.Count < 2) continue;
                result.Loops.Add(loop);
                partNo++;
            }
            // Inner rooms of covered things: a walkable floor inside the cavity, reachable at the mouth.
            foreach (var hollow in geo.Hollows)
            {
                if (hollow.Cavity.Count < 3) continue;
                var cavity = Poly.Clockwise(Poly.Dedupe(hollow.Cavity));
                var inner = LoopFromPolygon(cavity, $"item:{item.Id}~inside", item, owner);
                if (inner.Segs.Count >= 2)
                {
                    inner.Kind = SurfaceKind.WindowEdge;
                    result.Loops.Add(inner);
                }
            }
            owner++;
        }

        // Junctions: near-touching loop vertices, plus every loop end that meets the rim.
        var all = result.Loops.ToList();
        for (int i = 0; i < all.Count; i++)
        {
            for (int j = i + 1; j < all.Count; j++)
            {
                var a = all[i]; var b = all[j];
                var hit = NearestPair(a, b, off * 2.2);
                if (hit is { } q)
                {
                    result.Junctions.Add(new SurfaceJunction(a.Id, q.Item1, b.Id, q.Item2, (a.Segs[q.Item1].A + b.Segs[q.Item2].A) * .5));
                    result.Junctions.Add(new SurfaceJunction(b.Id, q.Item2, a.Id, q.Item1, (a.Segs[q.Item1].A + b.Segs[q.Item2].A) * .5));
                }
            }
        }
        return result;
    }

    static void AddSeg(SurfaceLoop loop, V2 a, V2 b, EdgeFacing facing)
    {
        if (a.DistanceTo(b) < .2) return;
        loop.Segs.Add(new Seg(a, b, facing));
    }

    static SurfaceLoop LoopFromPolygon(List<V2> pts, string id, HabitatItem item, int owner)
    {
        var loop = new SurfaceLoop
        {
            Id = id, Kind = SurfaceKind.WindowEdge, Closed = true, Depth = Math.Max(0, 10_000 - item.Id),
            Rect = item.Rect, CornerRadius = 0, IsWindowRect = false
        };
        for (int i = 0; i < pts.Count; i++)
        {
            var a = pts[i]; var b = pts[(i + 1) % pts.Count];
            var edge = b - a;
            if (edge.Length < .5) continue;
            var outward = edge.Normalized.Perp;
            var facing = Math.Abs(outward.Y) >= Math.Abs(outward.X)
                ? (outward.Y >= 0 ? EdgeFacing.Up : EdgeFacing.Down)
                : (outward.X >= 0 ? EdgeFacing.Right : EdgeFacing.Left);
            loop.Segs.Add(new Seg(a, b, facing));
        }
        loop.Edge.AddRange(pts);
        loop.Owners = Enumerable.Repeat(owner, loop.Segs.Count).ToArray();
        return loop;
    }

    static (int, int)? NearestPair(SurfaceLoop a, SurfaceLoop b, double within)
    {
        (int, int)? best = null; double bd = within * within;
        for (int i = 0; i < a.Segs.Count; i++)
        {
            var pa = a.Segs[i].A;
            for (int j = 0; j < b.Segs.Count; j++)
            {
                foreach (var pb in new[] { b.Segs[j].A, b.Segs[j].B })
                {
                    double d = pa.DistanceSquaredTo(pb);
                    if (d < bd) { bd = d; best = (i, j); }
                }
            }
        }
        return best;
    }

    static List<V2> LargestPart(ObjectGeometry g) =>
        g.Parts.Count == 0 ? new List<V2>() : g.Parts.OrderByDescending(p => Math.Abs(Poly.Area(p.Outline))).First().Outline;

    static List<V2> ClipToAbove(List<V2> poly, double y)
    {
        var r = Poly.Bounds(poly);
        return Poly.Clip(poly, new Rect(r.MinX - 2, y, r.W + 4, r.MaxY - y + 2));
    }

    static List<V2> UpperChain(List<V2> poly, double baseY)
    {
        if (poly.Count == 0) return new();
        int start = 0; double best = double.MaxValue;
        for (int i = 0; i < poly.Count; i++)
        {
            if (Math.Abs(poly[i].Y - baseY) < best) { best = Math.Abs(poly[i].Y - baseY); start = i; }
        }
        var chain = new List<V2>();
        // Walk both ways to find the upper boundary between the bottom-left and bottom-right extents.
        var left = poly[start]; var right = poly[start];
        foreach (var p in poly) { if (p.X < left.X) left = p; if (p.X > right.X) right = p; }
        foreach (var p in poly)
        {
            if (p.X >= left.X && p.X <= right.X && p.Y > baseY + .3) chain.Add(p);
        }
        var hull = Poly.Hull(chain.Count > 0 ? chain : poly);
        // The upper half of the hull, left to right.
        var upper = hull.Where(p => p.Y > baseY + .2).ToList();
        var b = Poly.Bounds(upper.Count > 0 ? upper : poly);
        var midY = b.MinY + b.H * .35;
        var top = upper.Where(p => p.Y >= midY).OrderBy(p => p.X).ToList();
        if (top.Count < 2) top = upper.OrderBy(p => p.X).ToList();
        return top;
    }
}
