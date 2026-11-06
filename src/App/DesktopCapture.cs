using System.Diagnostics;
using System.Runtime.InteropServices;
using SpiderBuddy.Core;

namespace SpiderBuddy.App;

/// <summary>Reads real Windows windows and displays into the core's portable desktop model.</summary>
public static class DesktopCapture
{
    delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr p);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder s, int n);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out int value, int size);

    const int GWL_EXSTYLE = -20;
    const int WS_EX_TOOLWINDOW = 0x80;
    const int DWMWA_CLOAKED = 14;

    public static DesktopState Poll()
    {
        var vs = SystemInformation.VirtualScreen;
        Rect ToWorld(Rectangle r) => new(r.X - vs.Left, vs.Bottom - r.Bottom, r.Width, r.Height);

        var desk = new DesktopState
        {
            VirtualBounds = new Rect(0, 0, Math.Max(1, vs.Width), Math.Max(1, vs.Height))
        };

        var screens = Screen.AllScreens;
        for (int i = 0; i < screens.Length; i++)
        {
            var sc = screens[i];
            var frame = ToWorld(sc.Bounds);
            var work = ToWorld(sc.WorkingArea);
            desk.Screens.Add(new ScreenFrame
            {
                Id = $"screen:{i}",
                Frame = frame,
                VisibleFrame = work,
                Main = sc.Primary,
                Dpi = 96
            });

            // The taskbar (or any work-area inset) is the Windows Dock equivalent.
            if (work.MinY > frame.MinY)
                desk.Docks.Add(new DockStrip(Rect.FromLTRB(frame.MinX, frame.MinY, frame.MaxX, work.MinY), EdgeFacing.Down));
            if (work.MaxY < frame.MaxY)
                desk.Docks.Add(new DockStrip(Rect.FromLTRB(frame.MinX, work.MaxY, frame.MaxX, frame.MaxY), EdgeFacing.Up));
            if (work.MinX > frame.MinX)
                desk.Docks.Add(new DockStrip(Rect.FromLTRB(frame.MinX, frame.MinY, work.MinX, frame.MaxY), EdgeFacing.Left));
            if (work.MaxX < frame.MaxX)
                desk.Docks.Add(new DockStrip(Rect.FromLTRB(work.MaxX, frame.MinY, frame.MaxX, frame.MaxY), EdgeFacing.Right));
        }

        uint ownPid = (uint)Environment.ProcessId;
        int depth = 0;
        EnumWindows((hWnd, _) =>
        {
            if (!IsWindowVisible(hWnd) || IsIconic(hWnd)) return true;
            GetWindowThreadProcessId(hWnd, out uint pid);
            if (pid == ownPid) return true;

            int cloaked = 0;
            try { DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, out cloaked, sizeof(int)); } catch { }
            if (cloaked != 0) return true;

            int ex = GetWindowLong(hWnd, GWL_EXSTYLE);
            if ((ex & WS_EX_TOOLWINDOW) != 0) return true;

            var sb = new System.Text.StringBuilder(256);
            GetClassName(hWnd, sb, 256);
            string cls = sb.ToString();
            if (cls is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd") return true;

            if (!GetWindowRect(hWnd, out RECT r)) return true;
            int w = r.Right - r.Left, h = r.Bottom - r.Top;
            if (w <= 0 || h <= 0) return true;
            var frame = ToWorld(new Rectangle(r.Left, r.Top, w, h));
            if (frame.W <= 130 || frame.H <= 90) return true;

            string owner = "";
            try { owner = Process.GetProcessById((int)pid).ProcessName; } catch { }

            desk.Windows.Add(new TrackedWindow
            {
                Id = hWnd.ToInt64(),
                Frame = frame,
                Depth = depth++,
                Owner = owner,
                Pid = (int)pid,
                CornerRadius = 12,
                Maximized = IsZoomed(hWnd)
            });
            return true;
        }, IntPtr.Zero);

        return desk;
    }

    /// <summary>Cheap change detector: geometry and display layout are what the map cares about.</summary>
    public static string Signature(DesktopState d)
    {
        var parts = new List<string> { $"{d.VirtualBounds}" };
        foreach (var s in d.Screens) parts.Add($"{s.Id}:{s.Frame}:{s.VisibleFrame}");
        foreach (var w in d.Windows) parts.Add($"{w.Id}:{w.Frame}:{w.Depth}:{w.Maximized}");
        return string.Join("|", parts);
    }
}
