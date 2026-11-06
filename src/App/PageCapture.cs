using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using SpiderBuddy.Core;

namespace SpiderBuddy.App;

/// <summary>Pictures of a browser window for the page reader. Geometry only; nothing is stored.</summary>
public static class PageCapture
{
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);

    const uint PW_RENDERFULLCONTENT = 2;

    public readonly record struct Look(PagePicture Picture, ulong[] Fingerprint, int Width, int Height, double Ms);

    public static Look? Capture(IntPtr hwnd, Rect frame)
    {
        int w = Math.Max(1, (int)Math.Round(frame.W)), h = Math.Max(1, (int)Math.Round(frame.H));
        if (w < 20 || h < 20) return null;
        long started = Environment.TickCount64;
        PagePicture? pic = null;
        try
        {
            using var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                IntPtr dc = g.GetHdc();
                bool ok;
                try { ok = PrintWindow(hwnd, dc, PW_RENDERFULLCONTENT); }
                finally { g.ReleaseHdc(dc); }
                if (!ok || LooksBlank(bmp)) CaptureScreen(g, frame, w, h);
            }
            pic = FromBitmap(bmp);
        }
        catch { }
        if (pic is null)
        {
            try
            {
                using var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
                using var g = Graphics.FromImage(bmp);
                CaptureScreen(g, frame, w, h);
                pic = FromBitmap(bmp);
            }
            catch { }
        }
        if (pic is null) return null;
        return new Look(pic, Fingerprint(pic), pic.Width, pic.Height, Environment.TickCount64 - started);
    }

    static void CaptureScreen(Graphics g, Rect frame, int w, int h)
    {
        var vs = System.Windows.Forms.SystemInformation.VirtualScreen;
        g.CopyFromScreen((int)Math.Round(vs.Left + frame.MinX), (int)Math.Round(vs.Bottom - frame.MaxY),
            0, 0, new Size(w, h), CopyPixelOperation.SourceCopy);
    }

    /// <summary>Capture a rectangle of the screen in world coordinates (used by the scroll patch).</summary>
    public static PagePicture? CaptureWorldRect(Rect world)
    {
        int w = Math.Max(1, (int)Math.Round(world.W)), h = Math.Max(1, (int)Math.Round(world.H));
        if (w < 12 || h < 8) return null;
        var vs = System.Windows.Forms.SystemInformation.VirtualScreen;
        int x = Math.Max(vs.Left, (int)Math.Round(vs.Left + world.MinX));
        int y = Math.Max(vs.Top, (int)Math.Round(vs.Bottom - world.MaxY));
        int right = Math.Min(vs.Right, x + w), bottom = Math.Min(vs.Bottom, y + h);
        w = Math.Max(1, right - x); h = Math.Max(1, bottom - y);
        try
        {
            using var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
                g.CopyFromScreen(x, y, 0, 0, new Size(w, h), CopyPixelOperation.SourceCopy);
            return FromBitmap(bmp);
        }
        catch { return null; }
    }

    static PagePicture? FromBitmap(Bitmap bmp)
    {
        var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var bytes = new byte[data.Stride * bmp.Height];
            Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
            return PagePicture.FromBgra(bytes, bmp.Width, bmp.Height, data.Stride);
        }
        finally { bmp.UnlockBits(data); }
    }

    static bool LooksBlank(Bitmap bmp)
    {
        try
        {
            uint first = 0;
            int same = 0, samples = 0;
            for (int y = 4; y < bmp.Height; y += Math.Max(12, bmp.Height / 24))
                for (int x = 4; x < bmp.Width; x += Math.Max(12, bmp.Width / 24))
                {
                    var c = bmp.GetPixel(x, y);
                    uint v = ((uint)c.R << 16) | ((uint)c.G << 8) | c.B;
                    if (samples == 0) first = v;
                    if (v == first) same++;
                    samples++;
                }
            return samples > 0 && same >= samples * 0.985;
        }
        catch { return true; }
    }

    public static ulong[] Fingerprint(PagePicture pic)
    {
        const int step = 12;
        var output = new List<ulong> { (ulong)pic.Width, (ulong)pic.Height };
        for (int y = step / 2; y < pic.Height; y += step)
            for (int x = step / 2; x < pic.Width; x += step)
                output.Add(pic.At(x, y));
        return output.ToArray();
    }

    public static double Difference(ulong[]? a, ulong[] b)
    {
        if (a is null || a.Length != b.Length || a.Length <= 2 || a[0] != b[0] || a[1] != b[1]) return 1;
        int changed = 0;
        for (int i = 2; i < a.Length; i++)
        {
            uint x = (uint)a[i], y = (uint)b[i];
            if (PageReader.Dist(x, y) > 10) changed++;
        }
        return changed / (double)(a.Length - 2);
    }

    /// <summary>A hash of a browser window's title — a number only, never the title itself.</summary>
    public static long TitleHash(IntPtr hwnd)
    {
        try
        {
            int n = GetWindowTextLength(hwnd);
            if (n <= 0 || n > 4096) return 0;
            var s = new StringBuilder(n + 2);
            GetWindowText(hwnd, s, s.Capacity);
            ulong h = 1469598103934665603UL;
            foreach (char c in s.ToString())
            {
                h ^= c;
                h *= 1099511628211UL;
            }
            return (long)(h & 0x7FFFFFFFFFFFFFFF);
        }
        catch { return 0; }
    }
}
