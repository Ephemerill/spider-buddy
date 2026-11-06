namespace SpiderBuddy.Core;

/// <summary>A scrolling part of a page as the browser extension last described it.</summary>
public sealed class PageScroller
{
    public int Id;
    public int Carrier;
    public Rect Rect;          // page pixels, from the top-left of the page area
    public V2 Offset;          // scroll offset when laid out
}

/// <summary>One page as the extension last described it. Geometry only, never its contents.</summary>
public sealed class PageBridgePage
{
    public int Tab;
    public Rect Window;        // screen pixels, top-left origin (as the browser sees it)
    public SizeD Viewport;     // page area, page pixels
    public double Dpr = 1;
    public Dictionary<int, PageScroller> Scrollers = new();
    public List<Rect> Fixed = new();
    public Dictionary<int, V2> Offsets = new();
    public double LaidOutAt;
}

public static class PageScrollMath
{
    /// <summary>How far a part and everything carrying it has scrolled since a baseline.</summary>
    public static V2 Carried(int id, PageBridgePage page, IReadOnlyDictionary<int, V2> baseline)
    {
        V2 delta = V2.Zero;
        int c = id;
        for (int n = 0; n < 16 && c >= 0; n++)
        {
            var now = page.Offsets.TryGetValue(c, out var o) ? o : V2.Zero;
            var then = baseline.TryGetValue(c, out var b) ? b : now;
            delta += then - now;
            c = page.Scrollers.TryGetValue(c, out var sc) ? sc.Carrier : -1;
        }
        return delta;
    }

    public static Rect Visible(int id, PageBridgePage page, IReadOnlyDictionary<int, V2> baseline,
        double top, double scale)
    {
        if (id < 0 || !page.Scrollers.TryGetValue(id, out var s)) return new Rect(0, 0, double.MaxValue, double.MaxValue);
        V2 d = s.Carrier >= 0 ? Carried(s.Carrier, page, baseline) : V2.Zero;
        return new Rect((s.Rect.X + d.X) * scale, top + (s.Rect.Y + d.Y) * scale,
            s.Rect.W * scale, s.Rect.H * scale);
    }
}
