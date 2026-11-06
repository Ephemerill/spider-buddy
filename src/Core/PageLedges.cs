namespace SpiderBuddy.Core;

// Stage 18.2 — ledges in a picture of a page.
//
// A browser that fills its screen leaves no desktop to climb, so the spider climbs the page:
// edges of cards, bars and boxes. This is pure pixels-in, geometry-out. Rows run from the top;
// one pixel is one point at scale 1. Nothing on the page is read or kept.

/// <summary>A picture of a page: rows from the top, each pixel 0x00RRGGBB.</summary>
public sealed class PagePicture
{
    public readonly int Width, Height;
    public readonly uint[] Pixels;

    public PagePicture(int width, int height, uint[] pixels)
    {
        if (pixels.Length < width * height) throw new ArgumentException("not enough pixels", nameof(pixels));
        Width = width; Height = height; Pixels = pixels;
    }

    public uint At(int x, int y) => Pixels[y * Width + x];

    /// <summary>Copy the readable pixels from BGRA/BGRX bytes (Windows captures are rows from the top).</summary>
    public static PagePicture? FromBgra(byte[] bytes, int width, int height, int stride)
    {
        if (width <= 8 || height <= 8 || stride < width * 4 || bytes.Length < stride * height) return null;
        var px = new uint[width * height];
        for (int y = 0; y < height; y++)
        {
            int row = y * stride;
            for (int x = 0; x < width; x++)
            {
                int i = row + x * 4;
                px[y * width + x] = ((uint)bytes[i + 2] << 16) | ((uint)bytes[i + 1] << 8) | bytes[i];
            }
        }
        return new PagePicture(width, height, px);
    }
}

/// <summary>Which side of a line the room is on, and so how the spider is on it.</summary>
public enum PageSide { Above, Below, Left, Right }

/// <summary>A straight edge in a picture, with room on one side.</summary>
public struct PageEdge
{
    public bool Horizontal;
    public int Pos;
    public int Lo, Hi;
    public PageSide Side;
    public int Room;
    public int Contrast;

    public int Length => Hi - Lo;

    public PageEdge(bool horizontal, int pos, int lo, int hi, PageSide side, int room, int contrast)
    {
        Horizontal = horizontal; Pos = pos; Lo = lo; Hi = hi; Side = side; Room = room; Contrast = contrast;
    }
}

public static class PageReader
{
    public sealed class Settings
    {
        public int Need = 34;
        public int Slot = 55;
        public int MinLength = 50;
        public int Trim = 12;
        public int Contrast = 6;
        public int Flat = 5;
        public int Drift = 28;
        public int SoftBand = 7;
        public int SoftStep = 9;
        public int Sharp = 32;
        public double Busy = 0.1;
        public int MaxRoom = 160;
        public int Gap = 2;
        public int Seed = 24;
        public int Most = 120;

        public static Settings ForScale(double scale)
        {
            return new Settings
            {
                Need = (int)Math.Round(44 * scale),
                Slot = (int)Math.Round(70 * scale),
                MinLength = (int)Math.Round(Math.Max(40, 64 * scale)),
                Trim = (int)Math.Round(16 * scale)
            };
        }
    }

    public static int Dist(uint a, uint b)
    {
        if (a == b) return 0;
        int dr = Math.Abs((int)((a >> 16) & 0xFF) - (int)((b >> 16) & 0xFF));
        int dg = Math.Abs((int)((a >> 8) & 0xFF) - (int)((b >> 8) & 0xFF));
        int db = Math.Abs((int)(a & 0xFF) - (int)(b & 0xFF));
        return Math.Max(dr, Math.Max(dg, db));
    }

    /// <summary>Where the page starts under the browser's own bars: the lowest line right across the top.</summary>
    public static int PageTop(PagePicture pic, int within = 200, Settings? settings = null)
    {
        var s = settings ?? new Settings();
        int top = 0;
        var reader = new Reader(pic, s, 0, pic.Width, 0, pic.Height);
        var ax = reader.AcrossAxis;
        int margin = pic.Width / 40;
        int span = pic.Width - margin * 2;
        for (int c = 4; c < Math.Min(within, pic.Height - 4); c++)
        {
            int hits = 0;
            for (int a = margin; a < pic.Width - margin; a += 2)
                if (reader.Strength(ax, a, c) > 0) hits++;
            if (hits * 2 * 10 >= span * 9) top = c;
        }
        return top;
    }

    /// <summary>Every edge in the picture that is a line with room beside it.</summary>
    public static List<PageEdge> Edges(PagePicture pic, Settings? settings = null, Rect? area = null)
    {
        var s = settings ?? new Settings();
        var full = new Rect(0, 0, pic.Width, pic.Height);
        Rect r = area is { } a ? a.Intersection(full) : full;
        int x0 = (int)Math.Round(r.MinX), y0 = (int)Math.Round(r.MinY);
        int x1 = (int)Math.Round(r.MaxX), y1 = (int)Math.Round(r.MaxY);
        x0 = Math.Clamp(x0, 0, pic.Width); x1 = Math.Clamp(x1, 0, pic.Width);
        y0 = Math.Clamp(y0, 0, pic.Height); y1 = Math.Clamp(y1, 0, pic.Height);
        var output = new List<PageEdge>();
        if (x1 - x0 <= 16 || y1 - y0 <= 16) return output;
        var reader = new Reader(pic, s, x0, x1, y0, y1);
        reader.Across(output);
        reader.Upright(output);
        output = Merged(output);
        if (output.Count > s.Most)
            output = output.OrderByDescending(e => e.Length * Math.Min(e.Room, 80)).Take(s.Most).ToList();
        return output;
    }

    sealed class Reader
    {
        readonly PagePicture _pic;
        readonly int _width, _height;
        readonly Settings _s;
        readonly int _x0, _x1, _y0, _y1;
        readonly int[] _rooms;
        readonly bool[] _valid;

        public Reader(PagePicture pic, Settings s, int x0, int x1, int y0, int y1)
        {
            _pic = pic; _width = pic.Width; _height = pic.Height; _s = s;
            _x0 = x0; _x1 = x1; _y0 = y0; _y1 = y1;
            _rooms = new int[Math.Max(pic.Width, pic.Height)];
            _valid = new bool[Math.Max(pic.Width, pic.Height)];
        }

        public struct Axis
        {
            public bool Horizontal;
            public int SA, SC;
            public int ALo, AHi, CLo, CHi;
        }

        public Axis AcrossAxis => new()
        {
            Horizontal = true, SA = 1, SC = _width, ALo = _x0, AHi = _x1, CLo = _y0, CHi = _y1
        };

        public Axis UprightAxis => new()
        {
            Horizontal = false, SA = _width, SC = 1, ALo = _y0, AHi = _y1, CLo = _x0, CHi = _x1
        };

        uint P(Axis ax, int a, int c) => _pic.Pixels[a * ax.SA + c * ax.SC];

        static int Channel(uint v, int shift) => (int)((v >> shift) & 0xFF);

        /// <summary>Strength of a line boundary before c, at a along it; 0 when not a line.</summary>
        public int Strength(Axis ax, int a, int c)
        {
            uint p0 = P(ax, a, c - 1), p1 = P(ax, a, c);
            if (p0 == p1) return 0;
            int dr = Channel(p1, 16) - Channel(p0, 16);
            int dg = Channel(p1, 8) - Channel(p0, 8);
            int db = Channel(p1, 0) - Channel(p0, 0);
            int shift = 16, d = dr;
            if (Math.Abs(dg) > Math.Abs(d)) { shift = 8; d = dg; }
            if (Math.Abs(db) > Math.Abs(d)) { shift = 0; d = db; }
            int m = Math.Abs(d);
            int q = Math.Max(_s.Contrast / 3, 2);
            if (m < q) return 0;
            int counts = Math.Max(q, m / 3);
            int total = m, width = 1;
            uint prev = p0;
            int k = c - 2;
            while (k >= ax.CLo && width <= 3)
            {
                uint v = P(ax, a, k);
                int e = Channel(prev, shift) - Channel(v, shift);
                if (e * d <= 0 || Math.Abs(e) < counts) break;
                if (Math.Abs(e) >= m) return 0;
                total += Math.Abs(e); width++;
                prev = v; k--;
            }
            prev = p1; k = c + 1;
            while (k < ax.CHi && width <= 3)
            {
                uint v = P(ax, a, k);
                int e = Channel(v, shift) - Channel(prev, shift);
                if (e * d <= 0 || Math.Abs(e) < counts) break;
                if (Math.Abs(e) > m) return 0;
                total += Math.Abs(e); width++;
                prev = v; k++;
            }
            if (width > 3) return 0;
            return total >= _s.Contrast ? total : 0;
        }

        public void Across(List<PageEdge> output)
        {
            var ax = AcrossAxis;
            for (int c = Math.Max(ax.CLo, 3); c < Math.Min(ax.CHi, _height - 3); c++)
            {
                int start = -1, last = -100, peak = 0;
                for (int a = ax.ALo; a < ax.AHi; a++)
                {
                    int st = Strength(ax, a, c);
                    if (st <= 0) continue;
                    if (start < 0 || a - last > _s.Gap + 1)
                    {
                        if (start >= 0 && last + 1 - start >= _s.Seed) Examine(ax, c, start, last + 1, peak, output);
                        start = a; peak = 0;
                    }
                    last = a;
                    peak = Math.Max(peak, st);
                }
                if (start >= 0 && last + 1 - start >= _s.Seed) Examine(ax, c, start, last + 1, peak, output);
            }
        }

        public void Upright(List<PageEdge> output)
        {
            var ax = UprightAxis;
            int cLo = Math.Max(ax.CLo, 3), cHi = Math.Min(ax.CHi, _width - 3);
            if (cHi <= cLo) return;
            var start = new int[_width];
            var last = new int[_width];
            var peak = new int[_width];
            Array.Fill(start, -1);
            Array.Fill(last, -100);
            for (int a = ax.ALo; a < ax.AHi; a++)
            {
                for (int c = cLo; c < cHi; c++)
                {
                    int st = Strength(ax, a, c);
                    if (st > 0)
                    {
                        if (start[c] < 0 || a - last[c] > _s.Gap + 1)
                        {
                            if (start[c] >= 0 && last[c] + 1 - start[c] >= _s.Seed)
                                Examine(ax, c, start[c], last[c] + 1, peak[c], output);
                            start[c] = a; peak[c] = 0;
                        }
                        last[c] = a; peak[c] = Math.Max(peak[c], st);
                    }
                    else if (start[c] >= 0 && a - last[c] > _s.Gap + 1)
                    {
                        if (last[c] + 1 - start[c] >= _s.Seed)
                            Examine(ax, c, start[c], last[c] + 1, peak[c], output);
                        start[c] = -1;
                    }
                }
            }
            for (int c = cLo; c < cHi; c++)
                if (start[c] >= 0 && last[c] + 1 - start[c] >= _s.Seed)
                    Examine(ax, c, start[c], last[c] + 1, peak[c], output);
        }

        int Room(Axis ax, int c, int a, bool before, int most)
        {
            int dir = before ? -1 : 1;
            int first = before ? c - 1 : c;
            int k = first, start = -1;
            for (int step = 0; step < _s.SoftBand; step++)
            {
                int k1 = k + dir, k2 = k + 2 * dir;
                if (k2 < ax.CLo || k2 >= ax.CHi) return 0;
                uint v0 = P(ax, a, k), v1 = P(ax, a, k1), v2 = P(ax, a, k2);
                int d01 = Dist(v0, v1);
                if (d01 <= _s.Flat && Dist(v1, v2) <= _s.Flat) { start = k; break; }
                if (step > 0 && d01 > _s.SoftStep) return 0;
                k = k1;
            }
            if (start < 0) return 0;

            uint @ref = P(ax, a, start);
            uint prev = @ref;
            int r = start;
            int end = before ? Math.Max(first - most, ax.CLo - 1) : Math.Min(first + most, ax.CHi);
            bool hasBefore = a > ax.ALo, hasAfter = a < ax.AHi - 1;
            while (r != end)
            {
                uint v = P(ax, a, r);
                if (Dist(v, prev) > _s.Flat || Dist(v, @ref) > _s.Drift) break;
                if (hasBefore && Dist(v, P(ax, a - 1, r)) > _s.Flat) break;
                if (hasAfter && Dist(v, P(ax, a + 1, r)) > _s.Flat) break;
                prev = v;
                r += dir;
            }
            return Math.Abs(r - first);
        }

        bool EvenAlong(Axis ax, int c, int a0, int a1, bool roomBefore)
        {
            int[] rows = roomBefore ? new[] { c + 1, c + 2 } : new[] { c - 2, c - 3 };
            int strokes = 0;
            foreach (int r in rows)
            {
                if (r < ax.CLo || r >= ax.CHi) continue;
                uint prev = P(ax, a0, r);
                for (int a = a0 + 1; a < a1; a++)
                {
                    uint v = P(ax, a, r);
                    if (Dist(v, prev) > _s.Sharp) strokes++;
                    prev = v;
                }
            }
            return strokes <= (a1 - a0) * _s.Busy * rows.Length + 1;
        }

        bool Steady(Axis ax, int c, int a0, int a1)
        {
            var hist = new int[33];
            for (int a = a0; a < a1; a++) hist[Math.Min(Strength(ax, a, c) / 8, 32)]++;
            int n = a1 - a0;
            int seen = 0, median = 0;
            for (int i = 0; i < hist.Length; i++)
            {
                seen += hist[i];
                if (seen * 2 >= n) { median = i * 8 + 4; break; }
            }
            int floor = Math.Max(_s.Contrast, median / 2);
            int weak = 0;
            for (int a = a0; a < a1; a++) if (Strength(ax, a, c) < floor) weak++;
            return weak * 100 <= n * 15;
        }

        void Examine(Axis ax, int c, int a0, int a1, int contrast, List<PageEdge> output)
        {
            if (!Steady(ax, c, a0, a1)) return;
            foreach (bool before in new[] { true, false })
            {
                if (!EvenAlong(ax, c, a0, a1, before)) continue;
                bool any = false;
                for (int a = a0 + 3; a < a1; a += 8)
                    if (Room(ax, c, a, before, _s.Need) >= _s.Need) { any = true; break; }
                if (!any) continue;

                int most = Math.Min(Math.Max(_s.Slot, _s.Need) + 2, _s.MaxRoom);
                for (int a = a0; a < a1; a++) _rooms[a] = Room(ax, c, a, before, most);

                const int w = 12;
                for (int a = a0; a < a1; a++)
                {
                    int r = _rooms[a];
                    if (r < _s.Need) { _valid[a] = false; continue; }
                    if (r >= _s.Slot) { _valid[a] = true; continue; }
                    int lo = Math.Max(a0, a - w), hi = Math.Min(a1, a + w + 1);
                    int same = 0;
                    for (int b = lo; b < hi; b++) if (Math.Abs(_rooms[b] - r) <= 1) same++;
                    _valid[a] = same * 10 < (hi - lo) * 8;
                }

                int start = a0;
                while (start < a1)
                {
                    if (!_valid[start]) { start++; continue; }
                    int e = start, least = int.MaxValue;
                    while (e < a1)
                    {
                        if (_valid[e]) { least = Math.Min(least, _rooms[e]); e++; continue; }
                        if (e + 1 < a1 && _valid[e + 1] && e > start) { e++; continue; }
                        break;
                    }
                    int lo = start, hi = e;
                    if (lo > a0) lo += _s.Trim;
                    if (hi < a1) hi -= _s.Trim;
                    if (hi - lo >= _s.MinLength)
                    {
                        PageSide side = ax.Horizontal
                            ? (before ? PageSide.Above : PageSide.Below)
                            : (before ? PageSide.Left : PageSide.Right);
                        output.Add(new PageEdge(ax.Horizontal, c, lo, hi, side,
                            least == int.MaxValue ? 0 : least, contrast));
                    }
                    start = Math.Max(e, start + 1);
                }
            }
        }
    }

    static List<PageEdge> Merged(List<PageEdge> edges)
    {
        var output = new List<PageEdge>();
        foreach (var e in edges.OrderBy(e => e.Pos).ThenBy(e => e.Lo))
        {
            int at = -1;
            for (int i = output.Count - 1; i >= 0; i--)
            {
                var o = output[i];
                if (o.Side == e.Side && o.Horizontal == e.Horizontal && Math.Abs(o.Pos - e.Pos) <= 4
                    && o.Lo < e.Hi && e.Lo < o.Hi) { at = i; break; }
            }
            if (at < 0) { output.Add(e); continue; }
            var merged = output[at];
            bool keepFirst = e.Side is PageSide.Above or PageSide.Left;
            merged.Pos = keepFirst ? Math.Min(merged.Pos, e.Pos) : Math.Max(merged.Pos, e.Pos);
            merged.Lo = Math.Min(merged.Lo, e.Lo);
            merged.Hi = Math.Max(merged.Hi, e.Hi);
            merged.Room = Math.Min(merged.Room, e.Room);
            merged.Contrast = Math.Max(merged.Contrast, e.Contrast);
            output[at] = merged;
        }
        return output;
    }

    /// <summary>Edges that meet at corners, joined into one path the spider can walk.</summary>
    public static List<PageChain> Chains(List<PageEdge> edges, double radius = 24, double trim = 12)
    {
        int n = edges.Count;
        V2 Corner(PageEdge a, PageEdge b) => a.Horizontal ? new V2(b.Pos, a.Pos) : new V2(a.Pos, b.Pos);

        var joins = new List<(int from, int to, double cost)>();
        for (int i = 0; i < n; i++)
        {
            var a = edges[i];
            for (int j = 0; j < n; j++)
            {
                if (j == i) continue;
                var b = edges[j];
                if (a.Horizontal == b.Horizontal) continue;
                V2 c = Corner(a, b);
                var ta = a.Side.Travel();
                var tb = b.Side.Travel();
                V2 ae = a.End(), bs = b.Start();
                double pastA = (c.X - ae.X) * ta.dx + (c.Y - ae.Y) * ta.dy;
                double beforeB = (bs.X - c.X) * tb.dx + (bs.Y - c.Y) * tb.dy;
                if (pastA < -2 || beforeB < -2) continue;
                bool rounded = pastA <= radius && beforeB <= radius && Math.Abs(pastA - beforeB) <= 8;
                bool inside = ta.dx * tb.dy - ta.dy * tb.dx < 0;
                if (!rounded && !(inside && pastA <= trim + 4 && beforeB <= trim + 4)) continue;
                joins.Add((i, j, Math.Max(pastA, 0) + Math.Max(beforeB, 0)));
            }
        }
        joins.Sort((x, y) => x.cost.CompareTo(y.cost));
        var next = new int?[n];
        var prev = new int?[n];
        foreach (var j in joins)
        {
            if (next[j.from] is null && prev[j.to] is null) { next[j.from] = j.to; prev[j.to] = j.from; }
        }

        var used = new bool[n];
        var output = new List<PageChain>();
        void Build(List<int> order, bool closed)
        {
            var points = new List<V2>();
            var sides = order.Select(i => edges[i].Side).ToList();
            if (closed)
            {
                for (int k = 0; k < order.Count; k++)
                    points.Add(Corner(edges[order[(k + order.Count - 1) % order.Count]], edges[order[k]]));
            }
            else
            {
                points.Add(edges[order[0]].Start());
                for (int k = 1; k < order.Count; k++) points.Add(Corner(edges[order[k - 1]], edges[order[k]]));
                points.Add(edges[order[^1]].End());
            }
            output.Add(new PageChain(points, sides, closed));
        }

        for (int i = 0; i < n; i++)
        {
            if (prev[i] is not null) continue;
            var order = new List<int> { i };
            used[i] = true;
            int k = i;
            while (next[k] is int m && !used[m]) { order.Add(m); used[m] = true; k = m; }
            Build(order, false);
        }
        for (int i = 0; i < n; i++)
        {
            if (used[i]) continue;
            var order = new List<int> { i };
            used[i] = true;
            int k = i;
            while (next[k] is int m && !used[m]) { order.Add(m); used[m] = true; k = m; }
            Build(order, next[k] == i);
        }
        return output;
    }
}

/// <summary>A path made from page edges. Points are picture pixels, y down.</summary>
public sealed class PageChain
{
    public readonly List<V2> Points;
    public readonly List<PageSide> Sides;
    public readonly bool Closed;

    public PageChain(List<V2> points, List<PageSide> sides, bool closed)
    {
        Points = points; Sides = sides; Closed = closed;
    }

    public Rect Bounds
    {
        get
        {
            if (Points.Count == 0) return Rect.Zero;
            double l = Points[0].X, r = l, b = Points[0].Y, t = b;
            foreach (var p in Points)
            {
                l = Math.Min(l, p.X); r = Math.Max(r, p.X);
                b = Math.Min(b, p.Y); t = Math.Max(t, p.Y);
            }
            return Rect.FromLTRB(l, b, r, t);
        }
    }

    public override string ToString() => $"PageChain({Points.Count} points, {Sides.Count} sides, closed={Closed})";
}

public static class PageSideExtensions
{
    /// <summary>The way along a line with room on the left, clockwise round a box (picture y-down).</summary>
    public static (double dx, double dy) Travel(this PageSide s) => s switch
    {
        PageSide.Above => (1, 0),
        PageSide.Right => (0, 1),
        PageSide.Below => (-1, 0),
        _ => (0, -1)
    };

    public static V2 Start(this PageEdge e)
    {
        var t = e.Side.Travel();
        if (e.Horizontal) return new V2(t.dx > 0 ? e.Lo : e.Hi, e.Pos);
        return new V2(e.Pos, t.dy > 0 ? e.Lo : e.Hi);
    }

    public static V2 End(this PageEdge e)
    {
        var t = e.Side.Travel();
        if (e.Horizontal) return new V2(t.dx > 0 ? e.Hi : e.Lo, e.Pos);
        return new V2(e.Pos, t.dy > 0 ? e.Hi : e.Lo);
    }

    public static EdgeFacing Facing(this PageSide s) => s switch
    {
        PageSide.Above => EdgeFacing.Up,
        PageSide.Below => EdgeFacing.Down,
        PageSide.Left => EdgeFacing.Left,
        _ => EdgeFacing.Right
    };
}
