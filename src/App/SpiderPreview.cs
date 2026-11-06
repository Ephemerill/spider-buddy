using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using SpiderBuddy.Core;
using SpiderBuddy.Renderer;

namespace SpiderBuddy.App;

/// <summary>
/// The Studio's own little desktop: a live spider on a ledge, not a portrait.
/// It uses the same core and renderer as the desktop but its own SurfaceMap,
/// so dragging or throwing it in the Studio cannot disturb the real spider.
/// </summary>
public sealed class SpiderPreview : Control
{
    readonly SpiderApplicationContext _app;
    readonly SurfaceMap _map = new();
    readonly Spider _spider;
    readonly System.Windows.Forms.Timer _timer = new() { Interval = 16 };
    readonly List<(V2 point, double at)> _samples = new();
    readonly DateTime _start = DateTime.UtcNow;
    bool _held;
    V2 _pressedAt;
    DateTime _pressedAtTime;

    public SpiderPreview(SpiderApplicationContext app)
    {
        _app = app;
        DoubleBuffered = true;
        BackColor = Color.FromArgb(238, 232, 222);
        TabStop = true;
        var desk = new DesktopState { VirtualBounds = new Rect(0, 0, 320, 300) };
        desk.Screens.Add(new ScreenFrame
        {
            Id = "studio:0",
            Frame = new Rect(0, 0, 320, 300),
            VisibleFrame = new Rect(0, 0, 320, 300),
            Main = true
        });
        // A window ledge, then the screen's floor: the same two kinds of
        // surface the real map offers.
        desk.Windows.Add(new TrackedWindow
        {
            Id = 1,
            Frame = new Rect(52, 120, 216, 110),
            Depth = 0,
            Owner = "Studio",
            CornerRadius = 8
        });
        _map.Rebuild(desk, 1.0);
        _spider = new Spider(app.Spider.Design, _map, new Rng(0x5EED));
        _spider.UserScale = 1;
        _spider.Design = app.Spider.Design;
        var spots = _map.SampleSpots(24, true, 1).ToList();
        // Stand on an upward-facing ledge, not the window's underside or the
        // screen floor at the bottom edge.
        bool Up(Spot s) => s.LoopId != "studio:0" && _map.Loop(s.LoopId)?.SegAt(s.SegIdx)?.Facing == EdgeFacing.Up;
        var spot = spots.Where(Up).OrderByDescending(s => s.Point.Y).ThenBy(s => Math.Abs(s.Point.X - 160)).FirstOrDefault();
        if (spot.Anchor.LoopId is null)
            spot = spots.OrderByDescending(s => s.Point.Y).ThenBy(s => Math.Abs(s.Point.X - 160)).FirstOrDefault();
        if (spot.Anchor.LoopId is { } loop) _spider.SetAnchor(loop, spot.Anchor.SegIdx, spot.Anchor.T, spot.Anchor.Dir);
        _spider.IdleFor = 999;
        _timer.Tick += (_, _) => Tick();
        _timer.Start();
    }

    public void ApplyDesign() => _spider.Design = _app.Spider.Design;

    /// <summary>Show one habit in the preview (the Studio's little stage).</summary>
    public void Demo(string name)
    {
        switch (name)
        {
            case "Peek-a-boo": _spider.StartPeekaboo(); break;
            case "Swinging on a line": _spider.Play(Activity.Swing, 2.4); break;
            case "Wiggling": _spider.Play(Activity.Wiggle, 1.8); break;
            case "Dancing": _spider.Play(Activity.Dance, 3); break;
            case "Dancing to music": _spider.Play(Activity.Groove, 3); break;
            case "Rolling over": _spider.Play(Activity.Roll, 1.8); break;
            case "Spinning": _spider.Play(Activity.Spin, 2); break;
            case "Push-ups": _spider.Play(Activity.Pushup, 2.2); break;
            case "Stretching": _spider.Play(Activity.Stretch, 2); break;
            case "Arms up": _spider.Play(Activity.ArmsUp, 2); break;
            case "Looking about": _spider.Play(Activity.Look, 2); break;
            case "Resting": _spider.Play(Activity.Rest, 4); break;
            case "Grooming": _spider.Play(Activity.Groom, 3); break;
            case "Fidgeting": _spider.Play(Activity.Fidget, 2); break;
            case "Scratching": _spider.Play(Activity.Scratch, 2); break;
            case "Peering": _spider.Play(Activity.Peer, 2); break;
            case "Craning at it": _spider.Play(Activity.Curious, 2); break;
            case "Staring": _spider.Play(Activity.Stare, 2); break;
            case "Glancing": _spider.Play(Activity.Glance, 1.5); break;
            case "Greeting": _spider.Celebrate(); break;
            case "Waving": _spider.Play(Activity.Wave, 2.4); break;
            case "Nodding off": _spider.Play(Activity.Sleep, 4); break;
            default: _spider.Play(Activity.Walk, 2.5); break;
        }
    }

    void Tick()
    {
        if (IsDisposed) return;
        _spider.Design = _app.Spider.Design;
        if (!_held) _spider.Update(1.0 / 60.0);
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;

        using (var sky = new System.Drawing.Drawing2D.LinearGradientBrush(ClientRectangle,
                   Color.FromArgb(242, 236, 226), Color.FromArgb(219, 209, 195), 90f))
            g.FillRectangle(sky, ClientRectangle);

        // Furniture, in the core's y-up coordinates.
        var ledge = new Rectangle(52, Height - 230, 216, 110);
        using (var edge = new SolidBrush(Color.FromArgb(180, 168, 153)))
        using (var face = new SolidBrush(Color.FromArgb(228, 219, 205)))
        {
            g.FillRectangle(face, ledge);
            g.FillRectangle(edge, ledge.Left, ledge.Top - 3, ledge.Width, 3);
        }
        using (var floor = new SolidBrush(Color.FromArgb(201, 190, 175)))
            g.FillRectangle(floor, 0, Height - 22, Width, 22);
        using (var line = new Pen(Color.FromArgb(90, 116, 99, 79)))
            g.DrawLine(line, 12, Height - 22, Width - 12, Height - 22);

        try
        {
            var pose = _spider.BuildPose();
            using var sprite = SpriteRaster.Render(pose, _spider.Design.Look, 1);
            using var bmp = BitmapFrom(sprite);
            double side = SpriteRaster.SpriteSide(1);
            float x = (float)(pose.Pos.X - side / 2);
            float y = (float)(Height - pose.Pos.Y - side / 2);
            g.DrawImageUnscaled(bmp, (int)Math.Round(x), (int)Math.Round(y));
        }
        catch (Exception ex) { Program.SmokeLog("preview paint: " + ex.Message + " pos=" + _spider.Pos); }

        using var hint = new SolidBrush(Color.FromArgb(120, 85, 74, 62));
        using var font = new Font("Segoe UI", 7.5f);
        g.DrawString("drag it, throw it", font, hint, 10, Height - 18);
    }

    V2 World(Point p) => new(p.X, Height - p.Y);

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button != MouseButtons.Left) return;
        var p = World(e.Location);
        if (p.DistanceTo(_spider.Pos) > 38) return;
        _held = true;
        _pressedAt = p;
        _pressedAtTime = DateTime.UtcNow;
        _samples.Clear();
        _samples.Add((p, 0));
        _spider.BeginGrab(p);
        Capture = true;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (!_held) return;
        var p = World(e.Location);
        _spider.MoveGrab(p);
        _samples.Add((p, (DateTime.UtcNow - _pressedAtTime).TotalSeconds));
        while (_samples.Count > 2 && _samples[^1].at - _samples[0].at > 0.12) _samples.RemoveAt(0);
        Invalidate();
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (!_held) return;
        _held = false;
        Capture = false;
        var p = World(e.Location);
        V2 v = V2.Zero;
        if (_samples.Count >= 2)
        {
            var a = _samples[0];
            var b = _samples[^1];
            double span = Math.Max(0.02, b.at - a.at);
            v = (b.point - a.point) / span;
        }
        _spider.EndGrab(v);
        if (v.Length < 30 && p.DistanceTo(_pressedAt) < 5 &&
            (DateTime.UtcNow - _pressedAtTime).TotalSeconds < 0.35)
            _spider.Poke();
        Invalidate();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _timer.Dispose();
        base.Dispose(disposing);
    }

    static Bitmap BitmapFrom(SkiaSharp.SKBitmap sk)
    {
        int w = sk.Width, h = sk.Height;
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
        var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
        IntPtr src = sk.GetPixels();
        var row = new byte[w * 4];
        for (int y = 0; y < h; y++)
        {
            Marshal.Copy(src + y * sk.RowBytes, row, 0, row.Length);
            Marshal.Copy(row, 0, data.Scan0 + y * data.Stride, row.Length);
        }
        bmp.UnlockBits(data);
        return bmp;
    }
}

/// <summary>
/// The welcome page's sitting spider: three-quarters round, watching the
/// pointer and blinking, on a soft ledge. It never walks or wanders.
/// </summary>
public sealed class SittingSpiderControl : Control
{
    readonly Spider _spider;
    readonly System.Windows.Forms.Timer _timer = new() { Interval = 16 };
    double _blink;
    double _blinkIn = 2.5;
    double _time;
    V2 _gaze, _gazeVel;

    public SittingSpiderControl(SpiderApplicationContext app)
    {
        DoubleBuffered = true;
        BackColor = Color.FromArgb(243, 237, 228);
        var map = new SurfaceMap();
        var desk = new DesktopState { VirtualBounds = new Rect(0, 0, 380, 340) };
        desk.Screens.Add(new ScreenFrame { Id = "welcome:0", Frame = new Rect(0, 0, 380, 340),
            VisibleFrame = new Rect(0, 0, 380, 340), Main = true });
        map.Rebuild(desk, 1.0);
        _spider = new Spider(app.Spider.Design, map) { UserScale = 2.1 };
        var spot = map.SampleSpots(30, true, 1).FirstOrDefault();
        if (spot.Anchor.LoopId is { } loop) _spider.SetAnchor(loop, spot.Anchor.SegIdx, spot.Anchor.T, spot.Anchor.Dir);
        _timer.Tick += (_, _) => Tick();
        _timer.Start();
    }

    void Tick()
    {
        double dt = 1.0 / 60.0;
        _time += dt;
        _blinkIn -= dt;
        if (_blinkIn <= 0 && _blink <= 0)
        {
            _blink = 0.19;
            _blinkIn = 2.0 + Random.Shared.NextDouble() * 3.6;
        }
        if (_blink > 0) _blink = Math.Max(0, _blink - dt);

        V2 target = V2.Zero;
        if (IsHandleCreated)
        {
            var p = PointToClient(Cursor.Position);
            var body = new V2(Width * 0.55, Height * 0.48);
            var d = new V2(p.X, p.Y) - body;
            target = d.Length < 1 ? V2.Zero : d / d.Length * Math.Clamp(d.Length / 160, 0, 1);
        }
        _gazeVel += ((target - _gaze) * 220 - _gazeVel * 22) * dt;
        _gaze += _gazeVel * dt;
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        int ledgeY = Height - 66;
        using (var ledge = new SolidBrush(Color.FromArgb(26, 77, 68, 58)))
            g.FillRectangle(ledge, 24, ledgeY, Width - 48, 12);
        try
        {
            var pose = _spider.BuildPose();
            pose.Pos = new V2(Width * 0.55, Height * 0.48);
            pose.Look = _gaze.Length > 1 ? _gaze.Normalized : _gaze;
            pose.Blink = _blink > 0 ? Math.Sin((1 - _blink / 0.19) * Math.PI) : 0;
            pose.Time = _time;
            pose.Grounded = 1;
            using var sprite = SpriteRaster.Render(pose, _spider.Design.Look, 2.1);
            using var bmp = BitmapFrom(sprite);
            double side = SpriteRaster.SpriteSide(2.1);
            g.DrawImageUnscaled(bmp, (int)Math.Round(pose.Pos.X - side / 2),
                (int)Math.Round(Height - pose.Pos.Y - side / 2));
        }
        catch (Exception ex) { Program.SmokeLog("sitter paint: " + ex.Message); }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _timer.Dispose();
        base.Dispose(disposing);
    }

    static Bitmap BitmapFrom(SkiaSharp.SKBitmap sk)
    {
        int w = sk.Width, h = sk.Height;
        var bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
        var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppPArgb);
        IntPtr src = sk.GetPixels();
        var row = new byte[w * 4];
        for (int y = 0; y < h; y++)
        {
            Marshal.Copy(src + y * sk.RowBytes, row, 0, row.Length);
            Marshal.Copy(row, 0, data.Scan0 + y * data.Stride, row.Length);
        }
        bmp.UnlockBits(data);
        return bmp;
    }
}
