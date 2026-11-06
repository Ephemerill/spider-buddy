using System.Diagnostics;
using SpiderBuddy.Core;

namespace SpiderBuddy.App;

/// <summary>
/// Stage 18.2 — climbing web pages. Picks the browser window filling a screen, looks at it every
/// second and a half, reads its card/bar edges, and installs them as web ledges. Exact scrolling
/// comes free from the extension when connected; without it, a small patch round the feet is
/// followed and every other ledge is put aside until the page is still.
/// </summary>
public sealed class PageWatcher
{
    sealed class Page
    {
        public TrackedWindow Window = new();
        public ScreenFrame Screen = new();
        public bool PageScreen;
        public List<(int id, PageChain chain)> Chains = new();
        public double ReadW, ReadH;
        public double PxPerPt = 1;
        public int PageTop;
        public int NextId = 1;
        public ulong[]? Fingerprint;
        public double LastLook = -100;
        public double DueAt;
        public bool Force = true;
        public bool Busy;
        public int Restless;
        public bool Playing;
        public long? TitleHash;
        public double LastScroll = -100;
        public double Scrolled;
        public int? Tracked;
        public double Shift;
        public Patch? Patch;
        public bool Tracking;
        public double LastTrack = -100;
        public double Gain;
        public bool GainKnown;
        public bool Measured;
        public V2 Foot;
        public Dictionary<int, V2> Baseline = new();
        public Dictionary<int, V2>? PendingBaseline;
        public Dictionary<int, int> Carriers = new();
        public bool Still;
    }

    sealed class Patch
    {
        public uint[] Pixels = Array.Empty<uint>();
        public int Width, Height, X, Y;
    }

    sealed class LookResult
    {
        public ulong[] Fingerprint = Array.Empty<ulong>();
        public double Changed;
        public List<(int id, PageChain chain)>? Chains;
        public int PageTop;
        public double PxPerPt;
        public double Width, Height;
        public double Ms;
        public bool Forced;
    }

    readonly Dictionary<long, Page> _pages = new();
    List<TrackedWindow> _windowsFront = new();
    List<ScreenFrame> _screens = new();
    int _shotCount;

    public readonly PageBridge Bridge = new();
    public bool Enabled
    {
        get => _enabled;
        set
        {
            if (_enabled == value) return;
            _enabled = value;
            if (value) Bridge.Start();
            else
            {
                Bridge.Stop();
                _pages.Clear();
            }
        }
    }
    bool _enabled;

    public bool Paused;
    public double Scale = 0.78;
    public double Standoff = 22 * 0.78;
    public bool LowPower;
    public Func<(string? loopId, V2 ground)> SpiderAt = () => (null, V2.Zero);
    public event Action<bool>? OnChange;
    public Action<Action> Dispatch = action => action();
    public readonly Dictionary<string, V2> Moved = new();
    public bool Log = Environment.GetEnvironmentVariable("SPIDER_PAGE_LOG") == "1";
    public string? ShotDirectory = Environment.GetEnvironmentVariable("SPIDER_PAGE_SHOT");
    public static readonly double ScrollQuiet = 0.3;
    public (double looking, double laying, int looks, int readings) Spent;

    public PageWatcher()
    {
        Bridge.OnScroll += tab => Dispatch(() =>
        {
            foreach (var p in _pages.Values)
                if (Bridge.PageIn(p.Window.Frame)?.Tab == tab) { p.LastScroll = Now; p.Still = false; }
            OnChange?.Invoke(false);
        });
        Bridge.OnChange += tab => Dispatch(() =>
        {
            foreach (var p in _pages.Values)
            {
                if (Bridge.PageIn(p.Window.Frame)?.Tab != tab) continue;
                p.DueAt = Math.Min(p.DueAt, Now + 0.15);
                p.Restless = 0;
                var e = Bridge.PageIn(p.Window.Frame);
                if (e is not null && p.Baseline.Count == 0 && p.Still && p.Chains.Count > 0
                    && Now - p.LastScroll > ScrollQuiet)
                {
                    p.Baseline = new Dictionary<int, V2>(e.Offsets);
                    p.Carriers = Carriers(p.Chains, e, ViewOf(e, p));
                }
            }
        });
    }

    public static double Now => Environment.TickCount64 / 1000.0;
    public bool ExtensionConnected => Bridge.Connected;
    public IReadOnlyList<Rect> PageScreens => _pages.Values.Where(p => p.PageScreen && !p.Playing).Select(p => p.Screen.Frame).ToList();
    public IReadOnlyList<Rect> FilmScreens => _pages.Values.Where(p => p.PageScreen && p.Playing).Select(p => p.Screen.Frame).ToList();
    public IReadOnlyList<string> Browsers => _pages.Values.Select(p => p.Window.Owner).Distinct().ToList();
    public bool CanSee => true;
    public bool WantsLeave => false;

    public string? Summary
    {
        get
        {
            if (!Enabled) return null;
            var live = _pages.Values.Where(p => !p.Playing && p.Chains.Count > 0).ToList();
            if (live.Count == 0) return null;
            var p = live.OrderByDescending(q => q.Chains.Count).First();
            int n = live.Sum(q => q.Chains.Count);
            return $"Climbing about {BrowserName(p.Window.Owner)}: {(n == 1 ? "one ledge" : n + " ledges")} on the page.";
        }
    }

    void Say(string m) { if (Log) Console.Error.WriteLine("pages: " + m); }

    public void Update(DesktopState desk)
    {
        _windowsFront = desk.Windows.OrderBy(w => w.Depth).ToList();
        _screens = desk.Screens;
        if (!Enabled) return;
        var found = new Dictionary<long, (TrackedWindow window, ScreenFrame screen, bool pageScreen)>();
        foreach (var w in _windowsFront)
        {
            if (!IsBrowser(w.Owner)) continue;
            var sc = _screens.FirstOrDefault(s => s.Frame.Intersects(w.Frame));
            if (sc is null) continue;
            Rect vis = sc.VisibleFrame.IsValid && !sc.VisibleFrame.IsEmpty ? sc.VisibleFrame : sc.Frame;
            Rect i = w.Frame.Intersection(vis);
            bool fills = i.W >= vis.W - 40 && i.H >= vis.H - 40;
            if (!fills) continue;
            if (!found.ContainsKey(w.Id)) found[w.Id] = (w, sc, true);
        }

        bool changed = false, moved = false;
        foreach (var id in _pages.Keys.Where(id => !found.ContainsKey(id)).ToList())
        {
            _pages.Remove(id);
            changed = true;
            Say($"page {id} gone");
        }
        foreach (var (id, item) in found)
        {
            var (w, screen, pageScreen) = item;
            if (!_pages.TryGetValue(id, out var p))
            {
                _pages[id] = new Page
                {
                    Window = w, Screen = screen, PageScreen = pageScreen, TitleHash = w.TitleHash,
                    DueAt = Now, Force = true
                };
                Say($"page {id}: {w.Owner} {w.Frame.W:0}×{w.Frame.H:0}");
                changed = true;
                continue;
            }
            if (Math.Abs(w.Frame.W - p.Window.Frame.W) > 0.5 || Math.Abs(w.Frame.H - p.Window.Frame.H) > 0.5)
            {
                p.Chains.Clear();
                p.Force = true;
                p.DueAt = Now + 0.4;
                p.Patch = null;
                p.Tracked = null;
                changed = true;
            }
            long? title = IsBrowser(w.Owner) ? PageCapture.TitleHash(new IntPtr(w.Id)) : null;
            if (title is > 0 && title != p.TitleHash)
            {
                p.TitleHash = title;
                p.Force = true;
                p.DueAt = Math.Min(p.DueAt, Now + 0.25);
                p.Restless = 0;
                Say($"page {id}: title changed");
            }
            if (!w.Frame.ApproximatelyEquals(p.Window.Frame, 0.5) || w.Depth != p.Window.Depth) moved = true;
            p.Window = w;
            p.Screen = screen;
            p.PageScreen = pageScreen;
        }
        Bridge.Want(_pages.Values.Select(p => p.Window.Frame).ToList());
        if (changed) OnChange?.Invoke(true);
        else if (moved) OnChange?.Invoke(false);
    }

    public void Tick(double? nowArg = null)
    {
        if (!Enabled || Paused) return;
        double now = nowArg ?? Now;
        foreach (var (id, p) in _pages.ToList())
        {
            if (p.Busy) continue;
            bool scrolling = now - p.LastScroll < ScrollQuiet;
            var ext = Bridge.PageIn(p.Window.Frame);
            if (p.Tracking || (p.Tracked is not null && ext is null && scrolling))
            {
                if (!p.Tracking && now - p.LastTrack > 1.0 / 30)
                    Follow(id, p, now);
                continue;
            }
            if (scrolling) continue;
            if (p.Tracked is not null)
            {
                p.DueAt = now;
                p.Force = true;
            }
            if (now >= p.DueAt) Look(id, p, now);
        }
    }

    void Look(long id, Page p, double now)
    {
        p.Busy = true;
        p.PendingBaseline = Bridge.PageIn(p.Window.Frame)?.Offsets;
        var before = p.Fingerprint;
        bool force = p.Force || p.Chains.Count == 0 && p.LastLook < 0;
        double scale = Scale;
        double full = p.PageScreen ? 1 : 0;
        bool film = p.Playing;
        var frame = p.Window.Frame;
        var hwnd = new IntPtr(p.Window.Id);
        p.Force = false;
        double started = Now;
        var context = SynchronizationContext.Current;
        Task.Run(() =>
        {
            var look = PageCapture.Capture(hwnd, frame);
            if (look is null) return new LookResult { Forced = force, Ms = (Now - started) * 1000 };
            var r = new LookResult
            {
                Fingerprint = look.Value.Fingerprint,
                Changed = PageCapture.Difference(before, look.Value.Fingerprint),
                Width = frame.W, Height = frame.H, Forced = force,
                Ms = (Now - started) * 1000
            };
            if (force || r.Changed > 0.004 && !film)
            {
                var pic = look.Value.Picture;
                double pxPerPt = pic.Width / Math.Max(1, frame.W);
                var settings = PageReader.Settings.ForScale(scale * pxPerPt);
                int within = (int)Math.Min(full > 0 ? 160 : 240, pic.Height / 3);
                int top = PageReader.PageTop(pic, within, settings);
                int y0 = Math.Max(top - 3, 0);
                var edges = PageReader.Edges(pic, settings,
                    new Rect(0, y0, pic.Width, pic.Height - y0));
                var chains = PageReader.Chains(edges, trim: settings.Trim);
                r.Chains = chains.Select((c, i) => (i + 1, c)).ToList();
                r.PageTop = top;
                r.PxPerPt = pxPerPt;
                if (ShotDirectory is { Length: > 0 } dir)
                {
                    try
                    {
                        Directory.CreateDirectory(dir);
                        DrawReading(pic, chains, top, Path.Combine(dir, $"page-{id}-{++_shotCount}.png"));
                    }
                    catch { }
                }
            }
            return r;
        }).ContinueWith(t =>
        {
            void Apply() => Looked(id, t.IsCompletedSuccessfully ? t.Result : null);
            if (context is not null) context.Post(_ => Apply(), null); else Dispatch(Apply);
        });
    }

    void Looked(long id, LookResult? r)
    {
        if (!_pages.TryGetValue(id, out var p)) return;
        double now = Now;
        Moved.Clear();
        p.Busy = false;
        p.LastLook = now;
        Spent.looks++;
        if (r is null || r.Fingerprint.Length == 0)
        {
            p.DueAt = now + 3;
            return;
        }
        p.Fingerprint = r.Fingerprint;
        bool busy = r.Changed > 0.004 && !r.Forced;
        p.Restless = busy ? p.Restless + 1 : 0;
        bool wasPlaying = p.Playing;
        if (p.PageScreen)
        {
            if (r.Changed > 0.25 && !r.Forced) p.Playing = p.Playing || p.Restless >= 2;
            else if (!busy) p.Playing = false;
        }
        else p.Playing = false;
        bool settled = p.Playing != wasPlaying;

        if (r.Chains is not null && Math.Abs(r.Width - p.Window.Frame.W) < 1.5 && Math.Abs(r.Height - p.Window.Frame.H) < 1.5)
        {
            Spent.readings++;
            var ext = Bridge.PageIn(p.Window.Frame);
            PageView vf = default;
            if (ext is not null) vf = ViewOf(ext, p);
            var old = p.Chains.Select(entry =>
            {
                V2 d = V2.Zero;
                if (ext is not null && p.Carriers.TryGetValue(entry.id, out int carrier))
                {
                    V2 m = PageScrollMath.Carried(carrier, ext, p.Baseline);
                    d = new V2(m.X * vf.Scale, m.Y * vf.Scale);
                }
                else if (entry.id == p.Tracked) d.Y = p.Shift;
                var chain = d.LengthSquared < 1e-9 ? entry.chain : Shift(entry.chain, d);
                return (entry.id, chain);
            }).ToList();
            var named = Name(r.Chains, old, ref p.NextId);
            foreach (var n in named)
                if (Math.Abs(n.moved) > 0.01)
                    Moved[$"page:{id}:{n.id}"] = new V2(0, -n.moved / Math.Max(r.PxPerPt, 0.1));
            p.Chains = named.Select(n => (n.id, n.chain)).ToList();
            p.PageTop = r.PageTop;
            p.PxPerPt = r.PxPerPt;
            p.ReadW = p.Window.Frame.W;
            p.ReadH = p.Window.Frame.H;
            p.Still = true;
            p.Baseline = new Dictionary<int, V2>();
            p.Carriers = new Dictionary<int, int>();
            if (ext is not null && p.PendingBaseline is not null)
            {
                p.Baseline = new Dictionary<int, V2>(p.PendingBaseline);
                p.Carriers = Carriers(p.Chains, ext, ViewOf(ext, p));
            }
            p.Tracked = null;
            p.Tracking = false;
            p.Shift = 0;
            p.Patch = null;
            p.Scrolled = 0;
            p.Gain = 0;
            p.GainKnown = false;
            p.Measured = false;
            settled = true;
            Say($"page {id}: read {named.Count} ledges, top {r.PageTop}, {(r.Changed * 100):0.0}% changed");
        }

        double every = LowPower ? 4 : 1.5;
        var spider = SpiderAt();
        if (!p.Screen.Frame.Inset(-40).Contains(spider.ground)) every *= 3;
        if (p.Restless > 2) every *= Math.Min(p.Restless - 1, 4);
        if (p.Playing) every = 1;
        p.DueAt = Math.Max(p.DueAt, now + every);
        if (p.DueAt < now) p.DueAt = now + every;
        if (settled) OnChange?.Invoke(true);
    }

    public List<SurfaceLoop> Loops(double? nowArg = null)
    {
        var output = new List<SurfaceLoop>();
        if (!Enabled || Paused) return output;
        double now = nowArg ?? Now;
        double started = Stopwatch.GetTimestamp() * 1000.0 / Stopwatch.Frequency;
        foreach (var (wid, p) in _pages)
        {
            if (p.Playing || p.Chains.Count == 0) continue;
            var f = p.Window.Frame;
            if (Math.Abs(f.W - p.ReadW) > 1 || Math.Abs(f.H - p.ReadH) > 1) continue;
            var ext = Bridge.PageIn(f);
            var view = ext is null ? default : ViewOf(ext, p);
            bool scrolling = ext is null && (p.Tracking || p.LastLook < p.LastScroll || now - p.LastScroll < ScrollQuiet);
            double k = 1 / Math.Max(p.PxPerPt, 0.1);
            double top = p.PageTop, bottom = f.H * p.PxPerPt;
            foreach (var (id, chain) in p.Chains)
            {
                double dx = 0, dy = 0;
                if (ext is not null && p.Carriers.TryGetValue(id, out int carrier))
                {
                    var d = PageScrollMath.Carried(carrier, ext, p.Baseline);
                    dx = d.X * view.Scale;
                    dy = d.Y * view.Scale;
                    if (dx != 0 || dy != 0)
                    {
                        var clip = PageScrollMath.Visible(carrier, ext, p.Baseline, view.Top, view.Scale).Inset(2);
                        if (chain.Points.Any(q => !clip.Contains(new V2(q.X + dx, q.Y + dy)))) continue;
                    }
                }
                else if (id == p.Tracked) dy = p.Shift + p.Gain * p.Scrolled * p.PxPerPt;
                else if (scrolling) continue;
                if (dy != 0 && chain.Points.Any(q => q.Y + dy < top - 1 || q.Y + dy > bottom - 2)) continue;
                var points = chain.Points.Select(q => new V2(
                    f.MinX + (q.X + dx) * k, f.MaxY - (q.Y + dy) * k)).ToList();
                var facings = chain.Sides.Select(s => s.Facing()).ToList();
                if (SurfaceMap.PathLoop($"page:{wid}:{id}", SurfaceKind.WebLedge, points, facings,
                        chain.Closed, p.PageScreen ? 0 : p.Window.Depth, Standoff) is { } loop)
                    output.Add(loop);
            }
        }
        Spent.laying += Stopwatch.GetTimestamp() * 1000.0 / Stopwatch.Frequency - started;
        return output;
    }

    struct PageView { public double Top, Scale; }

    PageView ViewOf(PageBridgePage e, Page p)
    {
        double scale = Math.Max(0.25, e.Dpr) * p.PxPerPt;
        return new PageView { Top = p.Window.Frame.H * p.PxPerPt - e.Viewport.Height * scale, Scale = scale };
    }

    Dictionary<int, int> Carriers(List<(int id, PageChain chain)> chains, PageBridgePage e, PageView v)
    {
        var output = new Dictionary<int, int>();
        foreach (var (id, ch) in chains)
        {
            var b = ch.Bounds;
            V2 c = new(b.Mid.X / Math.Max(v.Scale, 0.01), (b.Mid.Y - v.Top) / Math.Max(v.Scale, 0.01));
            if (e.Fixed.Any(r => r.Inset(2).Contains(c))) { output[id] = -1; continue; }
            var inner = e.Scrollers.Values.Where(s => s.Id != 0 && s.Rect.Inset(2).Contains(c))
                .OrderBy(s => s.Rect.W * s.Rect.H).FirstOrDefault();
            output[id] = inner?.Id ?? 0;
        }
        return output;
    }

    public void Scrolled(V2 at, double dy, bool precise = false, double? nowArg = null)
    {
        if (!Enabled || Paused) return;
        double now = nowArg ?? Now;
        long? id = PageAt(at);
        if (id is null || !_pages.TryGetValue(id.Value, out var p)) return;
        bool wasStill = p.LastLook >= p.LastScroll && now - p.LastScroll > ScrollQuiet && !p.Tracking;
        p.LastScroll = now;
        p.Scrolled += dy;
        p.Still = false;
        var ext = Bridge.PageIn(p.Window.Frame);
        if (ext is not null && p.Baseline.Count > 0) return;
        if (wasStill)
        {
            var spider = SpiderAt();
            string prefix = $"page:{id}:";
            p.Tracked = spider.loopId is { } loop && loop.StartsWith(prefix, StringComparison.Ordinal)
                && int.TryParse(loop[prefix.Length..], out int n) && p.Chains.Any(c => c.id == n) ? n : null;
            p.Foot = spider.ground;
            p.Shift = 0;
            p.Patch = null;
            p.Scrolled = 0;
            p.Measured = false;
            Say($"page {id}: scrolling, following ledge {p.Tracked?.ToString() ?? "none"}");
            OnChange?.Invoke(false);
        }
    }

    public void Clicked(V2 at, double? nowArg = null)
    {
        if (!Enabled || Paused) return;
        double now = nowArg ?? Now;
        if (PageAt(at) is not { } id || !_pages.TryGetValue(id, out var p)) return;
        p.DueAt = Math.Min(p.DueAt, now + 0.3);
        p.Force = true;
        p.Restless = 0;
        var captured = id;
        var timer = new System.Windows.Forms.Timer { Interval = 1200 };
        timer.Tick += (_, _) =>
        {
            timer.Stop(); timer.Dispose();
            if (_pages.TryGetValue(captured, out var q)) q.DueAt = Math.Min(q.DueAt, Now);
        };
        timer.Start();
    }

    long? PageAt(V2 p)
    {
        foreach (var (id, pg) in _pages)
        {
            if (!pg.Window.Frame.Contains(p)) continue;
            if (pg.PageScreen) return id;
            var front = _windowsFront.FirstOrDefault(w => w.Frame.Contains(p));
            if (front is null || front.Id == id) return id;
        }
        return null;
    }

    void Follow(long id, Page p, double now)
    {
        if (p.Tracked is null) return;
        p.Tracking = true;
        p.LastTrack = now;
        var frame = p.Window.Frame;
        double k = p.PxPerPt;
        int fx = (int)Math.Round((p.Foot.X - frame.MinX) * k);
        int fy = (int)Math.Round((frame.MaxY - p.Foot.Y) * k);
        int picW = (int)Math.Round(frame.W * k), picH = (int)Math.Round(frame.H * k);
        double predicted = p.GainKnown ? p.Gain * p.Scrolled * k : 0;
        var patch = p.Patch;
        double scrolledThen = p.Scrolled;
        var hwnd = new IntPtr(p.Window.Id);
        var context = SynchronizationContext.Current;
        Task.Run(() =>
        {
            PagePicture? pic;
            double moved = 0;
            Patch? fresh = patch;
            if (patch is null)
            {
                pic = PageCapture.Capture(hwnd, frame)?.Picture;
                if (pic is null) return ((double, Patch?)?)null;
                int x0 = Math.Max(fx - 90, 0), x1 = Math.Min(fx + 90, pic.Width);
                int r0 = Math.Max(fy - 26, p.PageTop), r1 = Math.Min(fy + 26, pic.Height);
                if (x1 - x0 < 20 || r1 - r0 < 16) return ((double, Patch?)?)null;
                var px = new uint[(x1 - x0) * (r1 - r0)];
                int at = 0;
                for (int r = r0; r < r1; r++) for (int c = x0; c < x1; c++) px[at++] = pic.At(c, r);
                fresh = new Patch { Pixels = px, Width = x1 - x0, Height = r1 - r0, X = x0, Y = r0 };
            }
            else
            {
                int want = patch.Y + (int)Math.Round(predicted);
                const int reach = 170;
                int y0 = Math.Max(want - reach, p.PageTop);
                int y1 = Math.Min(want + patch.Height + reach, picH);
                if (y1 - y0 <= patch.Height + 4) return ((double, Patch?)?)null;
                var rect = new Rect(frame.MinX + patch.X / k, frame.MaxY - y1 / k,
                    patch.Width / k, (y1 - y0) / k);
                pic = PageCapture.CaptureWorldRect(rect);
                if (pic is null) return ((double, Patch?)?)null;
                int sw = Math.Min(pic.Width, patch.Width), rows = pic.Height - patch.Height;
                if (sw <= 20 || rows < 0) return ((double, Patch?)?)null;
                int best = int.MaxValue, bestRow = -1;
                int wantRow = want - y0;
                for (int r0 = 0; r0 <= rows; r0++)
                {
                    int sad = 0, row = 0;
                    for (; row < patch.Height && sad <= best; row++)
                    {
                        int sr = (r0 + row) * pic.Width, pr = row * patch.Width;
                        for (int c = 1; c < sw; c += 3)
                            sad += PageReader.Dist(pic.Pixels[sr + c], patch.Pixels[pr + c]);
                    }
                    if (sad < best || sad == best && Math.Abs(r0 - wantRow) < Math.Abs(bestRow - wantRow))
                    { best = sad; bestRow = r0; }
                }
                int samples = Math.Max(patch.Height * (sw / 3), 1);
                if (bestRow < 0 || best / samples > 14) return ((double, Patch?)?)null;
                var np = new uint[sw * patch.Height];
                int nAt = 0;
                for (int r = bestRow; r < bestRow + patch.Height; r++)
                    for (int c = 0; c < sw; c++) np[nAt++] = pic.At(c, r);
                fresh = new Patch { Pixels = np, Width = sw, Height = patch.Height, X = patch.X, Y = y0 + bestRow };
                moved = fresh.Y - patch.Y;
            }
            return (moved, fresh);
        }).ContinueWith(t =>
        {
            void Apply() => Followed(id, t.IsCompletedSuccessfully ? t.Result : null, scrolledThen);
            if (context is not null) context.Post(_ => Apply(), null); else Dispatch(Apply);
        });
    }

    void Followed(long id, (double moved, Patch? patch)? result, double scrolledThen)
    {
        if (!_pages.TryGetValue(id, out var p)) return;
        p.Tracking = false;
        if (p.Tracked is null) return;
        if (result is null)
        {
            Say($"page {id}: lost the ledge it was riding");
            p.Chains.RemoveAll(c => c.id == p.Tracked);
            p.Tracked = null;
            p.Patch = null;
            OnChange?.Invoke(true);
            return;
        }
        var (moved, patch) = result.Value;
        if (Math.Abs(scrolledThen) > 2)
        {
            double gain = Math.Clamp(moved / (scrolledThen * p.PxPerPt), -2, 2);
            p.Gain = p.GainKnown && p.Measured ? p.Gain * 0.6 + gain * 0.4 : gain;
            p.GainKnown = true;
            p.Measured = true;
        }
        p.Shift += moved;
        p.Scrolled -= scrolledThen;
        p.Patch = patch;
        OnChange?.Invoke(false);
    }

    static PageChain Shift(PageChain chain, V2 d) =>
        new(chain.Points.Select(p => p + d).ToList(), new List<PageSide>(chain.Sides), chain.Closed);

    sealed class Stretch
    {
        public bool Horizontal;
        public double Pos, Lo, Hi;
        public PageSide Side;
    }

    static List<Stretch> Stretches(PageChain c)
    {
        var output = new List<Stretch>();
        for (int i = 0; i < c.Sides.Count; i++)
        {
            var a = c.Points[i];
            var b = c.Points[c.Closed ? (i + 1) % c.Points.Count : i + 1];
            bool horizontal = Math.Abs(a.Y - b.Y) < 0.5;
            output.Add(new Stretch
            {
                Horizontal = horizontal,
                Pos = horizontal ? a.Y : a.X,
                Lo = horizontal ? Math.Min(a.X, b.X) : Math.Min(a.Y, b.Y),
                Hi = horizontal ? Math.Max(a.X, b.X) : Math.Max(a.Y, b.Y),
                Side = c.Sides[i]
            });
        }
        return output;
    }

    static List<(int id, PageChain chain, double moved)> Name(List<(int id, PageChain chain)> fresh,
        List<(int id, PageChain chain)> old, ref int next)
    {
        var oldStretches = old.Select(o => Stretches(o.chain)).ToList();
        var freshStretches = fresh.Select(f => Stretches(f.chain)).ToList();
        var votes = new Dictionary<int, int>();
        for (int oi = 0; oi < oldStretches.Count; oi++)
            foreach (var b in oldStretches[oi].Where(s => s.Horizontal))
                for (int fi = 0; fi < freshStretches.Count; fi++)
                    foreach (var a in freshStretches[fi].Where(s => s.Horizontal && s.Side == b.Side
                        && s.Pos != b.Pos && Math.Abs(s.Pos - b.Pos) < 600))
                    {
                        double overlap = Math.Min(a.Hi, b.Hi) - Math.Max(a.Lo, b.Lo);
                        double shorter = Math.Min(a.Hi - a.Lo, b.Hi - b.Lo);
                        double longer = Math.Max(a.Hi - a.Lo, b.Hi - b.Lo);
                        if (overlap >= 0.8 * shorter && shorter >= 0.85 * longer)
                        {
                            int k = (int)Math.Round(a.Pos - b.Pos);
                            votes[k] = (votes.TryGetValue(k, out int v) ? v : 0) + 1;
                        }
                    }
        int? best = null; int support = 0;
        foreach (var k in votes.Keys)
        {
            int s = (votes.TryGetValue(k - 1, out int a) ? a : 0) + votes[k] + (votes.TryGetValue(k + 1, out int b) ? b : 0);
            if (s > support) { support = s; best = k; }
        }
        double[] moves = best is not null && support >= 3 ? new double[] { 0, best.Value } : new double[] { 0 };
        var scores = new List<(int fresh, int old, double score, double moved)>();
        for (int i = 0; i < freshStretches.Count; i++)
        {
            double total = freshStretches[i].Sum(s => s.Hi - s.Lo);
            for (int j = 0; j < oldStretches.Count; j++)
            {
                double theirTotal = oldStretches[j].Sum(s => s.Hi - s.Lo);
                foreach (double dy in moves)
                {
                    double shared = 0;
                    foreach (var a in freshStretches[i])
                        foreach (var b in oldStretches[j].Where(s => s.Horizontal == a.Horizontal && s.Side == a.Side))
                        {
                            double pos = b.Horizontal ? b.Pos + dy : b.Pos;
                            double lo = b.Horizontal ? b.Lo : b.Lo + dy;
                            double hi = b.Horizontal ? b.Hi : b.Hi + dy;
                            if (Math.Abs(a.Pos - pos) > 3) continue;
                            shared += Math.Max(0, Math.Min(a.Hi, hi) - Math.Max(a.Lo, lo));
                        }
                    if (shared >= 0.5 * Math.Min(total, theirTotal))
                        scores.Add((i, j, shared, dy));
                }
            }
        }
        scores.Sort((p, q) => p.score != q.score ? q.score.CompareTo(p.score) : Math.Abs(p.moved).CompareTo(Math.Abs(q.moved)));
        var given = new (int id, double moved)?[fresh.Count];
        var taken = new HashSet<int>();
        foreach (var s in scores)
        {
            if (given[s.fresh] is not null || taken.Contains(s.old)) continue;
            given[s.fresh] = (old[s.old].id, s.moved);
            taken.Add(s.old);
        }
        var output = new List<(int id, PageChain chain, double moved)>();
        for (int i = 0; i < fresh.Count; i++)
        {
            if (given[i] is { } g) output.Add((g.id, fresh[i].chain, g.moved));
            else output.Add((next++, fresh[i].chain, 0));
        }
        return output;
    }

    public static bool IsBrowser(string owner)
    {
        string p = owner.ToLowerInvariant();
        return p.Contains("chrome") || p.Contains("msedge") || p.Contains("brave") || p.Contains("vivaldi")
            || p.Contains("opera") || p.Contains("firefox") || p.Contains("arc") || p.Contains("zen")
            || p.Contains("chromium") || p.Contains("librewolf") || p.Contains("waterfox")
            || p.Contains("floorp") || p.Contains("duckduckgo") || p.Contains("yandex")
            || p.Contains("thorium") || p.Contains("tor") || p.Contains("comet");
    }

    public static string BrowserName(string owner)
    {
        string p = owner.ToLowerInvariant();
        if (p.Contains("msedge")) return "Edge";
        if (p.Contains("brave")) return "Brave";
        if (p.Contains("vivaldi")) return "Vivaldi";
        if (p.Contains("opera")) return "Opera";
        if (p.Contains("firefox")) return "Firefox";
        if (p.Contains("zen")) return "Zen";
        if (p.Contains("chromium")) return "Chromium";
        if (p.Contains("arc")) return "Arc";
        if (p.Contains("duckduckgo")) return "DuckDuckGo";
        if (p.Contains("chrome")) return "Chrome";
        return string.IsNullOrWhiteSpace(owner) ? "your browser" : owner;
    }

    public static (string name, string address)? ExtensionsPage(string owner)
    {
        string p = owner.ToLowerInvariant();
        if (p.Contains("msedge")) return ("Edge", "edge://extensions");
        if (p.Contains("brave")) return ("Brave", "brave://extensions");
        if (p.Contains("vivaldi")) return ("Vivaldi", "vivaldi://extensions");
        if (p.Contains("opera")) return ("Opera", "opera://extensions");
        if (p.Contains("chromium")) return ("Chromium", "chrome://extensions");
        if (p.Contains("arc")) return ("Arc", "arc://extensions");
        if (p.Contains("chrome")) return ("Chrome", "chrome://extensions");
        return null;
    }

    static void DrawReading(PagePicture pic, List<PageChain> chains, int top, string path)
    {
        int w = pic.Width, h = pic.Height;
        using var bmp = new System.Drawing.Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                uint c = pic.At(x, y);
                var col = System.Drawing.Color.FromArgb(255, (int)((c >> 16) & 255), (int)((c >> 8) & 255), (int)(c & 255));
                bmp.SetPixel(x, y, System.Drawing.Color.FromArgb(128, col));
            }
        using (var g = System.Drawing.Graphics.FromImage(bmp))
        {
            g.DrawLine(System.Drawing.Pens.Gray, 0, top, w, top);
            foreach (var ch in chains)
            {
                for (int i = 0; i < ch.Sides.Count; i++)
                {
                    var a = ch.Points[i];
                    var b = ch.Points[ch.Closed ? (i + 1) % ch.Points.Count : i + 1];
                    var pen = ch.Sides[i] switch
                    {
                        PageSide.Above => System.Drawing.Pens.LimeGreen,
                        PageSide.Below => System.Drawing.Pens.RoyalBlue,
                        PageSide.Left => System.Drawing.Pens.Orange,
                        _ => System.Drawing.Pens.Magenta
                    };
                    using var thick = new System.Drawing.Pen(pen.Color, 3);
                    g.DrawLine(thick, (float)a.X, h - (float)a.Y, (float)b.X, h - (float)b.Y);
                }
            }
        }
        bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    }
}

/// <summary>Global wheel/click observation for page scrolling (never key presses or text).</summary>
public sealed class PageInputHook : IDisposable
{
    delegate IntPtr HookProc(int code, IntPtr wParam, IntPtr lParam);
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    struct POINT { public int X, Y; }
    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    struct MSLLHOOKSTRUCT { public POINT pt; public uint mouseData; public uint flags; public uint time; public IntPtr extra; }

    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr SetWindowsHookEx(int id, HookProc proc, IntPtr module, uint thread);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr w, IntPtr l);
    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern IntPtr GetModuleHandle(string? name);

    readonly HookProc _proc;
    IntPtr _hook;
    readonly Action<V2, double> _scrolled;
    readonly Action<V2> _clicked;
    const int WH_MOUSE_LL = 14, WM_MOUSEWHEEL = 0x020A, WM_LBUTTONUP = 0x0202;

    public PageInputHook(Action<V2, double> scrolled, Action<V2> clicked)
    {
        _scrolled = scrolled; _clicked = clicked; _proc = Callback;
        _hook = SetWindowsHookEx(WH_MOUSE_LL, _proc, GetModuleHandle(null), 0);
    }

    IntPtr Callback(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            var m = System.Runtime.InteropServices.Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
            var vs = System.Windows.Forms.SystemInformation.VirtualScreen;
            var p = new V2(m.pt.X - vs.Left, vs.Bottom - m.pt.Y);
            int id = wParam.ToInt32();
            if (id == WM_MOUSEWHEEL)
            {
                double delta = (short)((m.mouseData >> 16) & 0xFFFF);
                _scrolled(p, delta);
            }
            else if (id == WM_LBUTTONUP) _clicked(p);
        }
        return CallNextHookEx(_hook, code, wParam, lParam);
    }

    public void Dispose()
    {
        if (_hook != IntPtr.Zero) { UnhookWindowsHookEx(_hook); _hook = IntPtr.Zero; }
    }
}
