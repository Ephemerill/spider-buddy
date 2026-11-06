namespace SpiderBuddy.Core;

/// <summary>What kind of furniture a loop came from, and how much the spider likes jumping there (spec 2.3).</summary>
public enum SurfaceKind
{
    ScreenBorder,
    WindowEdge,
    Dock,
    MenuBar,
    WebLedge
}

public static class SurfaceKinds
{
    public static double Appeal(this SurfaceKind k) => k switch
    {
        SurfaceKind.ScreenBorder => 1.0,
        SurfaceKind.WindowEdge => 1.7,
        SurfaceKind.Dock => 1.35,
        SurfaceKind.MenuBar => 1.25,
        SurfaceKind.WebLedge => 1.6,
        _ => 1.0
    };

    /// <summary>Can be covered by a window in front of the one it belongs to.</summary>
    public static bool OnWindow(this SurfaceKind k) => k is SurfaceKind.WindowEdge or SurfaceKind.WebLedge;
}

/// <summary>Which way a segment's outward normal points (spec 2.3).</summary>
public enum EdgeFacing { Up, Down, Left, Right }

public static class EdgeFacings
{
    public static V2 Normal(this EdgeFacing f) => f switch
    {
        EdgeFacing.Up => new V2(0, 1),
        EdgeFacing.Down => new V2(0, -1),
        EdgeFacing.Left => new V2(-1, 0),
        _ => new V2(1, 0)
    };
}

/// <summary>A covered stretch of a segment, in t units along it.</summary>
public readonly struct BlockRange
{
    public readonly double Lo, Hi;
    public BlockRange(double lo, double hi) { Lo = lo; Hi = hi; }
    public override string ToString() => $"[{Lo:0.##}..{Hi:0.##}]";
}

/// <summary>
/// One straight piece of a walkable loop (spec 2.3).
/// The constructor orders its endpoints so that the facing normal equals `dir` rotated +90°
/// (counter-clockwise, y-up). That guarantees the sprite frame (+x along the edge, +y along the
/// outward normal) is never upside down.
/// </summary>
public sealed class Seg
{
    public V2 A;
    public V2 B;
    public EdgeFacing Facing;
    public V2 Dir;
    public double Len;
    public readonly List<BlockRange> Blocked = new();

    public V2 Normal => Facing.Normal();
    public V2 Mid => (A + B) * 0.5;

    public Seg(V2 a, V2 b, EdgeFacing facing)
    {
        V2 raw = b - a;
        double len = raw.Length;
        if (len < 1e-9)
        {
            A = a; B = b; Len = 0; Dir = new V2(1, 0); Facing = facing;
            return;
        }
        V2 dir = raw / len;
        // normal == dir rotated +90 CCW ⇒ if it does not match, swap the endpoints.
        if (dir.Perp.Dot(facing.Normal()) < 0)
        {
            (a, b) = (b, a);
            dir = -dir;
        }
        A = a; B = b; Dir = dir; Len = len; Facing = facing;
    }

    public V2 Point(double t) => A + Dir * M.Clamp(t, 0, Len);

    /// <summary>How far you can walk from t before a blocked stretch or the end (always ≥ 0).</summary>
    public double Limit(double t, int dir)
    {
        if (dir >= 0)
        {
            double best = Len - t;
            foreach (var r in Blocked)
                if (r.Lo >= t - 1e-9 && r.Lo - t < best) best = Math.Max(0, r.Lo - t);
            return Math.Max(0, best);
        }
        else
        {
            double best = t;
            foreach (var r in Blocked)
                if (r.Hi <= t + 1e-9 && t - r.Hi < best) best = Math.Max(0, t - r.Hi);
            return Math.Max(0, best);
        }
    }

    /// <summary>Add a covered t-range; kept sorted and merged.</summary>
    public void Block(double lo, double hi)
    {
        if (hi < lo) (lo, hi) = (hi, lo);
        lo = M.Clamp(lo, 0, Len);
        hi = M.Clamp(hi, 0, Len);
        if (hi - lo <= 1e-9) return;

        Blocked.Add(new BlockRange(lo, hi));
        Blocked.Sort((x, y) => x.Lo.CompareTo(y.Lo));
        // merge
        var merged = new List<BlockRange>();
        foreach (var r in Blocked)
        {
            if (merged.Count > 0 && r.Lo <= merged[^1].Hi + 1e-9)
            {
                var last = merged[^1];
                merged[^1] = new BlockRange(last.Lo, Math.Max(last.Hi, r.Hi));
            }
            else merged.Add(r);
        }
        Blocked.Clear();
        Blocked.AddRange(merged);
    }

    public bool IsOpen(double t) => !Blocked.Any(r => t > r.Lo && t < r.Hi);

    public bool IsBlocked => Blocked.Count > 0;

    /// <summary>Fraction of the segment that is blocked, 0…1.</summary>
    public double BlockedShare
    {
        get
        {
            double total = 0;
            foreach (var r in Blocked) total += r.Hi - r.Lo;
            return Len <= 1e-9 ? 0 : M.Clamp01(total / Len);
        }
    }

    /// <summary>
    /// The t-range of this segment inside a rect, in distance units along the seg (0…Len).
    /// Liang–Barsky works in normalised 0…1, so the result is scaled here.
    /// </summary>
    public bool Span(Rect inside, out double t0, out double t1)
    {
        if (!Clip.SegmentInRect(A, B, inside, out double u0, out double u1) || u1 <= u0 + 1e-12)
        {
            t0 = t1 = 0;
            return false;
        }
        t0 = u0 * Len;
        t1 = u1 * Len;
        return t1 > t0 + 1e-9;
    }

    public void ClearBlocks() => Blocked.Clear();

    public Seg Clone()
    {
        var s = new Seg(A, B, Facing);
        s.Blocked.AddRange(Blocked);
        return s;
    }

    public override string ToString() => $"Seg{A}→{B} {Facing} len={Len:0.#} blocked={Blocked.Count}";
}

/// <summary>
/// A walkable polyline (spec 2.3): `Segs` is the BODY path (offset from the real edge by the
/// standoff), `Edge` is the real edge where feet go.
/// </summary>
public sealed class SurfaceLoop
{
    public string Id = "";
    public SurfaceKind Kind;
    public List<Seg> Segs = new();
    public bool Closed;
    public int Depth;

    /// <summary>The furniture rect this loop came from (Zero for page ledges).</summary>
    public Rect Rect;

    /// <summary>Radius of the *real* corner, before the standoff is added.</summary>
    public double CornerRadius;

    /// <summary>Real-edge polyline (feet land here). Closed loops repeat the first point at the end.</summary>
    public List<V2> Edge = new();

    /// <summary>Per-seg owner id (0 = the tank / no owner). Used by the habitat (17c).</summary>
    public int[] Owners = Array.Empty<int>();

    /// <summary>Only window loops get arc-accurate corner rounding in resolve().</summary>
    public bool IsWindowRect;

    public bool IsOpenRun => !Closed;

    public double Length
    {
        get { double l = 0; foreach (var s in Segs) l += s.Len; return l; }
    }

    /// <summary>Anchor for the start of the loop.</summary>
    public Anchor Start => new(Id, 0, 0, 1);

    public Seg? SegAt(int i) => i >= 0 && i < Segs.Count ? Segs[i] : null;

    /// <summary>Whether the loop's edge is blocked at this anchor's position (spec 7.6 covered test).</summary>
    public bool IsOpenAt(Anchor a)
    {
        var s = SegAt(a.SegIdx);
        if (s is null) return false;
        double t = a.Dir >= 0 ? a.T : s.Len - a.T;
        return s.IsOpen(t);
    }

    public int OwnerOf(int segIdx) => segIdx >= 0 && segIdx < Owners.Length ? Owners[segIdx] : 0;

    /// <summary>
    /// Project a point on the square outline onto the real rounded corner (spec 2.5),
    /// returning the point and its outward normal.
    /// </summary>
    public (V2 point, V2 normal) OnRoundedCorner(V2 p)
    {
        if (!IsWindowRect || CornerRadius <= 0.01) return (p, (p - Rect.Mid).Normalized);
        double cr = Math.Min(CornerRadius, Math.Min(Rect.W, Rect.H) / 2);
        if (cr <= 0.01) return (p, (p - Rect.Mid).Normalized);

        // the four arc centres, each inset cr from its window corner
        Span<V2> centres = stackalloc V2[4];
        centres[0] = new V2(Rect.MinX + cr, Rect.MaxY - cr); // top-left
        centres[1] = new V2(Rect.MaxX - cr, Rect.MaxY - cr); // top-right
        centres[2] = new V2(Rect.MaxX - cr, Rect.MinY + cr); // bottom-right
        centres[3] = new V2(Rect.MinX + cr, Rect.MinY + cr); // bottom-left

        foreach (var c in centres)
        {
            if (Math.Abs(p.X - c.X) <= cr + 1e-6 && Math.Abs(p.Y - c.Y) <= cr + 1e-6)
            {
                V2 d = p - c;
                if (d.LengthSquared < 1e-18) continue;
                V2 n = d.Normalized;
                return (c + n * cr, n);
            }
        }
        return (p, (p - Rect.Mid).Normalized);
    }

    /// <summary>Nearest point on the true edge (wrapping onto the next side around a corner).</summary>
    public V2 SnapToEdge(V2 p)
    {
        if (Edge.Count >= 2)
        {
            double best = double.MaxValue;
            V2 bestPt = p;
            for (int i = 0; i < Edge.Count - 1; i++)
            {
                var (t, _) = M.ProjectOnSegment(p, Edge[i], Edge[i + 1]);
                V2 q = V2.Lerp(Edge[i], Edge[i + 1], t);
                double d = p.DistanceSquaredTo(q);
                if (d < best) { best = d; bestPt = q; }
            }
            if (Closed && Edge.Count > 1)
            {
                var (t, _) = M.ProjectOnSegment(p, Edge[^1], Edge[0]);
                V2 q = V2.Lerp(Edge[^1], Edge[0], t);
                if (p.DistanceSquaredTo(q) < best) bestPt = q;
            }
            return bestPt;
        }
        return OnRoundedCorner(p).point;
    }

    public SurfaceLoop Clone()
    {
        var l = new SurfaceLoop
        {
            Id = Id, Kind = Kind, Closed = Closed, Depth = Depth, Rect = Rect,
            CornerRadius = CornerRadius, IsWindowRect = IsWindowRect,
            Owners = (int[])Owners.Clone()
        };
        foreach (var s in Segs) l.Segs.Add(s.Clone());
        l.Edge = new List<V2>(Edge);
        return l;
    }

    public Rect Bounds
    {
        get
        {
            Rect r = new(Rect.Zero.X, Rect.Zero.Y, 0, 0);
            bool any = false;
            foreach (var s in Segs)
            {
                foreach (var p in new[] { s.A, s.B })
                {
                    if (!any) { r = new Rect(p.X, p.Y, 0, 0); any = true; }
                    else r = r.Union(new Rect(p.X, p.Y, 0, 0));
                }
            }
            return r;
        }
    }

    public override string ToString() => $"Loop({Id}, {Kind}, {Segs.Count} segs, closed={Closed}, depth={Depth})";
}

/// <summary>Where the spider is standing (spec 2.3).</summary>
public struct Anchor : IEquatable<Anchor>
{
    public string LoopId;
    public int SegIdx;
    public double T;
    public int Dir;   // +1 toward seg.B, -1 toward seg.A

    public Anchor(string loopId, int segIdx, double t, int dir)
    {
        LoopId = loopId; SegIdx = segIdx; T = t; Dir = dir == 0 ? 1 : Math.Sign(dir);
    }

    public Anchor With(int segIdx, double t) => new(LoopId, segIdx, t, Dir);

    public bool IsValid => !string.IsNullOrEmpty(LoopId);

    public bool Equals(Anchor o) => LoopId == o.LoopId && SegIdx == o.SegIdx && Dir == o.Dir && Math.Abs(T - o.T) < 1e-9;
    public override bool Equals(object? obj) => obj is Anchor a && Equals(a);
    public override int GetHashCode() => HashCode.Combine(LoopId, SegIdx, T, Dir);
    public override string ToString() => $"{LoopId}#{SegIdx}@{T:0.#}{Dir:+0;-0}";
}

/// <summary>A resolved position on the surface: where the body goes, and which way it faces.</summary>
public struct SurfacePoint
{
    public V2 Pos;
    public V2 Tangent;
    public V2 Normal;
    public string LoopId;
    public int SegIdx;
    public double T;
    public SurfaceKind Kind;

    public bool IsValid => !string.IsNullOrEmpty(LoopId);
    public double Angle => Math.Atan2(Normal.Y, Normal.X);
    public override string ToString() => $"{Pos} tan{Tan2Str(Tangent)} n{Normal}";
    static string Tan2Str(V2 v) => $"({v.X:0.##},{v.Y:0.##})";
}

/// <summary>A candidate standing spot (spec 2.6 sampleSpots).</summary>
public readonly struct Spot
{
    public readonly Anchor Anchor;
    public readonly V2 Point;
    public readonly string LoopId;
    public readonly SurfaceKind Kind;
    public readonly int SegIdx;
    public readonly int Depth;

    public Spot(Anchor anchor, V2 point, string loopId, SurfaceKind kind, int segIdx, int depth)
    {
        Anchor = anchor; Point = point; LoopId = loopId; Kind = kind; SegIdx = segIdx; Depth = depth;
    }

    public override string ToString() => $"{LoopId}#{SegIdx} {Point}";
}

/// <summary>A place where two loops meet and the spider may cross (habitat, spec 2.3).</summary>
public readonly struct SurfaceJunction
{
    public readonly string FromLoop;
    public readonly int FromVertex;
    public readonly string ToLoop;
    public readonly int ToVertex;
    public readonly V2 At;

    public SurfaceJunction(string fromLoop, int fromVertex, string toLoop, int toVertex, V2 at)
    {
        FromLoop = fromLoop; FromVertex = fromVertex; ToLoop = toLoop; ToVertex = toVertex; At = at;
    }
}

// ---------------------------------------------------------------------------------------------
// Window / display input types (the core never polls the OS itself; the platform layer fills these)
// ---------------------------------------------------------------------------------------------

/// <summary>A window that counts as furniture (spec 2.1). Geometry only — titles never read.</summary>
public sealed class TrackedWindow
{
    public long Id;
    public Rect Frame;                 // y-up global coords
    public int Depth;                  // front-to-back, 0 = frontmost
    public string Owner = "";
    public double CornerRadius = 26;
    public int Pid;
    public string BundleId = "";
    /// <summary>Browsers only, opt-in, a number — never the title itself.</summary>
    public long? TitleHash;
    public bool Maximized;
    /// <summary>macOS desktop widget (no Windows equivalent).</summary>
    public bool Widget;

    public override string ToString() => $"Win({Id}, {Owner}, {Frame}, d{Depth})";
}

/// <summary>One display: its full frame and its work area (frame minus the taskbar).</summary>
public sealed class ScreenFrame
{
    public string Id = "screen:0";
    public Rect Frame;         // full display, y-up
    public Rect VisibleFrame;  // work area (macOS: minus menu bar and dock)
    public bool Main;
    public double Dpi = 96;

    /// <summary>macOS menu-bar height; on Windows > 12 only when a taskbar is docked at the top.</summary>
    public double MenuBarHeight => Math.Max(0, Frame.MaxY - VisibleFrame.MaxY);

    public double UnitsPerPoint => Dpi / 96.0;

    public override string ToString() => $"Screen({Id}, {Frame}, vis {VisibleFrame})";
}

/// <summary>A taskbar-style strip (the macOS Dock equivalent).</summary>
public readonly struct DockStrip
{
    public readonly Rect Rect;
    public readonly EdgeFacing Edge;
    public readonly bool AutoHidden;

    public DockStrip(Rect rect, EdgeFacing edge, bool autoHidden = false)
    {
        Rect = rect; Edge = edge; AutoHidden = autoHidden;
    }
}

/// <summary>Everything one poll of the desktop produced (spec 2.1 onUpdate).</summary>
public sealed class DesktopState
{
    public List<TrackedWindow> Windows = new();
    public List<ScreenFrame> Screens = new();
    public List<DockStrip> Docks = new();
    public List<ScreenFrame> CinemaScreens = new();
    public List<ScreenFrame> ZoomedScreens = new();
    public Rect VirtualBounds = Rect.Zero;

    public DesktopState Clone()
    {
        var d = new DesktopState { VirtualBounds = VirtualBounds };
        foreach (var w in Windows) d.Windows.Add(w);
        foreach (var s in Screens) d.Screens.Add(s);
        d.Docks.AddRange(Docks);
        d.CinemaScreens.AddRange(CinemaScreens);
        d.ZoomedScreens.AddRange(ZoomedScreens);
        return d;
    }
}
