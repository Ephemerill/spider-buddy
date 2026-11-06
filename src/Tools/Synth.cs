using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

/// <summary>
/// A synthetic desktop: fake windows, no OS (spec 2.10 and Stage 20). The same `rebuild` the live
/// tracker feeds is fed here, so headless tests exercise exactly the shipping code path.
/// </summary>
public static class Synth
{
    public const double Scale = 0.78;
    public const double Standoff = 22 * Scale;   // 17.16

    /// <summary>A 1920×1080 display with a 40-unit taskbar along the bottom.</summary>
    public static DesktopState Desktop(double w = 1920, double h = 1080, double taskbar = 40)
    {
        var desk = new DesktopState
        {
            VirtualBounds = new Rect(0, 0, w, h)
        };
        desk.Screens.Add(new ScreenFrame
        {
            Id = "screen:0",
            Frame = new Rect(0, 0, w, h),
            VisibleFrame = new Rect(0, taskbar, w, h - taskbar),
            Main = true,
            Dpi = 96
        });
        if (taskbar > 0)
            desk.Docks.Add(new DockStrip(new Rect(0, 0, w, taskbar), EdgeFacing.Up));
        return desk;
    }

    public static TrackedWindow Window(long id, double x, double y, double w, double h,
        int depth = 0, string owner = "app", double corner = 8, bool maximized = false)
        => new()
        {
            Id = id,
            Frame = new Rect(x, y, w, h),
            Depth = depth,
            Owner = owner,
            CornerRadius = corner,
            Pid = (int)id,
            Maximized = maximized
        };

    public static DesktopState With(this DesktopState d, TrackedWindow w)
    {
        d.Windows.Add(w);
        return d;
    }

    public static DesktopState Cinema(this DesktopState d, string screenId = "screen:0")
    {
        var s = d.Screens.First(x => x.Id == screenId);
        d.CinemaScreens.Add(s);
        return d;
    }

    public static DesktopState Zoomed(this DesktopState d, string screenId = "screen:0")
    {
        var s = d.Screens.First(x => x.Id == screenId);
        d.ZoomedScreens.Add(s);
        return d;
    }

    public static SurfaceMap Build(DesktopState d, double scale = Scale, Rect? confine = null)
    {
        var m = new SurfaceMap();
        m.Rebuild(d, scale, null, confine);
        return m;
    }

    /// <summary>Find a loop by prefix (ids may be deduplicated with ~n suffixes).</summary>
    public static SurfaceLoop? LoopStartingWith(SurfaceMap m, string prefix)
        => m.AllLoops.FirstOrDefault(l => l.Id.StartsWith(prefix, StringComparison.Ordinal));
}
