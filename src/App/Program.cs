using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using SpiderBuddy.Core;
using SpiderBuddy.Renderer;
using WinForms = System.Windows.Forms;

namespace SpiderBuddy.App;

static class Program
{
    static Mutex? _singleInstance;

    const uint ES_CONTINUOUS = 0x80000000;
    const uint ES_SYSTEM_REQUIRED = 0x00000001;
    const uint ES_DISPLAY_REQUIRED = 0x00000002;

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint SetThreadExecutionState(uint esFlags);

    [DllImport("kernel32.dll")]
    static extern bool QueryUnbiasedInterruptTime(out ulong unbiasedTime);

    [STAThread]
    static void Main(string[] args)
    {
        var launch = Stopwatch.StartNew();
        try
        {
            _singleInstance = new Mutex(true, "Local\\SpiderBuddy.SingleInstance", out bool created);
            if (!created)
            {
                MessageBox.Show("Spider Buddy is already running — look for it in the notification area.",
                    "Spider Buddy", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            ApplicationConfiguration.Initialize();
            if (args.Contains("--update-public-key"))
            {
                Console.WriteLine(UpdateService.PublicKey);
                return;
            }
            if (args.Contains("--update-check"))
            {
                try
                {
                    var release = UpdateService.CheckAsync().GetAwaiter().GetResult();
                    SmokeLog(release is null
                        ? $"update: current ({UpdateService.CurrentVersion})"
                        : $"update: {release.Version} available ({release.Url})");
                }
                catch (Exception ex)
                {
                    SmokeLog("update: failed " + ex.GetType().Name + ": " + ex.Message);
                }
                return;
            }
            SmokeLog("context: constructing");
            var context = new SpiderApplicationContext(args.Contains("--no-welcome"));
            SmokeLog("context: constructed");
            if (FrameStats.OpenTiming)
                SmokeLog($"open: app context ready in {launch.Elapsed.TotalMilliseconds:0.0} ms");
            if (args.Contains("--ui-shots"))
            {
                string dir = Path.Combine(AppContext.BaseDirectory, "ui-shots");
                context.CaptureUi(dir);
                context.Quit();
                return;
            }
            if (args.Contains("--habitat-cycles"))
            {
                int total = ArgInt(args, "--habitat-cycles", 50);
                int done = 0;
                var cycle = new WinForms.Timer { Interval = 350 };
                cycle.Tick += (_, _) =>
                {
                    if (context.HabitatOpen)
                    {
                        context.CloseHabitat();
                        Program.SmokeLog($"cycles: closed {done}/{total}");
                        if (done >= total) { cycle.Stop(); cycle.Dispose(); context.Quit(); }
                        return;
                    }
                    done++;
                    context.OpenHabitat();
                    Program.SmokeLog($"cycles: opened {done}/{total}");
                };
                cycle.Start();
            }
            else if (args.FirstOrDefault(a => a.StartsWith("--habitat-soak", StringComparison.Ordinal)) is { } soakArg)
            {
                int seconds = ArgInt(args, "--habitat-soak", 60);
                var soakStart = DateTime.UtcNow;
                var quiet = new WinForms.Timer { Interval = 600 };
                quiet.Tick += (_, _) =>
                {
                    quiet.Stop(); quiet.Dispose();
                    context.OpenHabitat();
                    context.SetHabitatWeather(WeatherKind.Storm);
                };
                quiet.Start();
                var done = new WinForms.Timer { Interval = Math.Max(1000, seconds * 1000) };
                done.Tick += (_, _) =>
                {
                    done.Stop(); done.Dispose();
                    double wall = Math.Max(1, (DateTime.UtcNow - soakStart).TotalSeconds);
                    var cpu = System.Diagnostics.Process.GetCurrentProcess().TotalProcessorTime.TotalSeconds;
                    Program.SmokeLog($"soak: {wall:0.0}s storm, cpu {cpu / wall * 100:0.0}% of one core");
                    context.CloseHabitat();
                    context.Quit();
                };
                done.Start();
            }
            else if (args.FirstOrDefault(a => a.StartsWith("--desktop-soak", StringComparison.Ordinal)) is { } desktopSoak)
            {
                int seconds = ArgInt(args, "--desktop-soak", 60);
                var started = DateTime.UtcNow;
                ulong activeStart = ActiveInterruptTime();
                bool sleepBlocked = SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED) != 0;
                Program.SmokeLog($"soak: desktop armed {seconds}s, sleep-block {(sleepBlocked ? "on" : "off")}");
                var done = new WinForms.Timer { Interval = 1000 };
                bool finishing = false;
                done.Tick += (_, _) =>
                {
                    if (finishing) return;
                    double active = (ActiveInterruptTime() - activeStart) / 10_000_000.0;
                    if (active < seconds) return;
                    finishing = true;
                    done.Stop(); done.Dispose();
                    SetThreadExecutionState(ES_CONTINUOUS);
                    double wall = Math.Max(1, (DateTime.UtcNow - started).TotalSeconds);
                    double slept = Math.Max(0, wall - active);
                    var cpu = Process.GetCurrentProcess().TotalProcessorTime.TotalSeconds;
                    string status = slept > 2.0 ? " FAILED: host slept" : "";
                    Program.SmokeLog($"soak: desktop {active:0.0}s active, {wall:0.0}s wall, slept {slept:0.0}s, cpu {cpu / active * 100:0.0}% of one core{status}");
                    if (slept > 2.0)
                    {
                        Environment.ExitCode = 2;
                        Program.SmokeLog("soak: desktop FAILED");
                    }
                    FrameStats.ReportStats(context.Spider);
                    var watchdog = new Thread(() =>
                    {
                        Thread.Sleep(20_000);
                        Program.SmokeLog("soak: desktop FAILED: process did not exit within 20s");
                        Environment.Exit(3);
                    }) { IsBackground = true, Name = "soak shutdown watchdog" };
                    watchdog.Start();
                    context.Quit();
                };
                done.Start();
            }
            else if (args.Contains("--panel-smoke"))
            {
                var panelTimer = new WinForms.Timer { Interval = 900 };
                panelTimer.Tick += (_, _) =>
                {
                    panelTimer.Stop();
                    context.ShowPanel();
                    var quit = new WinForms.Timer { Interval = 1200 };
                    quit.Tick += (_, _) => { quit.Stop(); context.Quit(); };
                    quit.Start();
                };
                panelTimer.Start();
            }
            if (args.Contains("--stage18-smoke"))
            {
                context.StartStage18Smoke();
            }
            else if (args.Contains("--stage19-smoke"))
            {
                context.StartStage19Smoke();
            }
            else if (args.Contains("--stage20-smoke"))
            {
                context.StartStage20Smoke();
            }
            else if (args.Contains("--box-smoke"))
            {
                context.KeepInBox();
                context.SaveAll(force: true);
                context.Quit();
                return;
            }
            if (args.Contains("--smoke") || args.Contains("--habitat-smoke"))
            {
                if (args.Contains("--habitat-smoke")) { SmokeLog("habitat: opening"); context.OpenHabitat(); SmokeLog("habitat: opened"); }
                var quit = new WinForms.Timer { Interval = args.Contains("--habitat-smoke") ? 6500 : 4500 };
                quit.Tick += (_, _) => { SmokeLog("timer: quitting"); quit.Stop(); context.Quit(); SmokeLog("timer: quit returned"); };
                quit.Start();
                SmokeLog("smoke: running");
            }
            Application.Run(context);
            GC.KeepAlive(_singleInstance);
        }
        catch (Exception ex)
        {
            try
            {
                string dir = Environment.GetEnvironmentVariable("SPIDER_DATA")
                    ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SpiderBuddy");
                Directory.CreateDirectory(dir);
                File.WriteAllText(Path.Combine(dir, "startup-error.log"), ex.ToString());
            }
            catch { }
            if (!args.Contains("--smoke") && !args.Contains("--habitat-smoke") && !args.Contains("--box-smoke") && !args.Contains("--ui-shots") && !args.Contains("--stage19-smoke") && !args.Contains("--stage20-smoke") && !args.Any(a => a.StartsWith("--desktop-soak", StringComparison.Ordinal)))
                MessageBox.Show(ex.Message, "Spider Buddy could not start", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    internal static int ArgInt(string[] args, string name, int fallback)
    {
        string? value = args.FirstOrDefault(a => a.StartsWith(name + "=", StringComparison.Ordinal))?[(name.Length + 1)..];
        int at = Array.IndexOf(args, name);
        if (value is null && at >= 0 && at + 1 < args.Length && !args[at + 1].StartsWith("--")) value = args[at + 1];
        return int.TryParse(value, out int n) ? Math.Clamp(n, 1, 7200) : fallback;
    }

    static ulong ActiveInterruptTime()
    {
        if (QueryUnbiasedInterruptTime(out ulong value)) return value;
        return (ulong)(Stopwatch.GetTimestamp() * (10_000_000.0 / Stopwatch.Frequency));
    }

    internal static void SmokeLog(string message)
    {
        try
        {
            string? dir = Environment.GetEnvironmentVariable("SPIDER_DATA");
            if (string.IsNullOrEmpty(dir)) return;
            Directory.CreateDirectory(dir);
            File.AppendAllText(Path.Combine(dir, "smoke.log"), DateTime.Now.ToString("HH:mm:ss.fff") + " " + message + Environment.NewLine);
        }
        catch { }
    }
}

/// <summary>A small atomic text store under %APPDATA%\SpiderBuddy (the core stays host-free).</summary>
public sealed class DiskStore : ITextFileStore
{
    public readonly string Root;

    public DiskStore(string? root = null)
    {
        Root = root ?? Environment.GetEnvironmentVariable("SPIDER_DATA")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SpiderBuddy");
        Directory.CreateDirectory(Root);
    }

    string P(string folder, string name) =>
        Path.Combine(Root, string.IsNullOrEmpty(folder) ? name : Path.Combine(folder, name));

    public string? Read(string name) => ReadIn("", name);

    public void Write(string name, string contents) => WriteIn("", name, contents);

    public string? ReadIn(string folder, string name)
    {
        try
        {
            string p = P(folder, name);
            return File.Exists(p) ? File.ReadAllText(p) : null;
        }
        catch { return null; }
    }

    public void WriteIn(string folder, string name, string contents)
    {
        string p = P(folder, name);
        Directory.CreateDirectory(Path.GetDirectoryName(p)!);
        string tmp = p + ".tmp";
        File.WriteAllText(tmp, contents);
        File.Move(tmp, p, overwrite: true);
    }

    public void DeleteIn(string folder, string name)
    {
        try { File.Delete(P(folder, name)); } catch { }
    }

    public IEnumerable<string> List(string folder)
    {
        try
        {
            string p = P(folder, "");
            if (!Directory.Exists(p)) return Array.Empty<string>();
            return Directory.GetFiles(p).Select(Path.GetFileName).Where(n => n is not null).Cast<string>().ToArray();
        }
        catch { return Array.Empty<string>(); }
    }

    public string Describe() => Root;
}

/// <summary>The tray app: owns the spider, the desktop map, the overlay and the panel.</summary>
public sealed class SpiderApplicationContext : ApplicationContext
{
    readonly DiskStore _store;
    readonly Settings _settings;
    readonly SurfaceMap _map = new();
    readonly Spider _spider;
    readonly SpiderOverlay _overlay;
    readonly DisplayTicker _timer;
    readonly NotifyIcon _tray;
    readonly ContextMenuStrip _menu;
    readonly PanelForm _panel;
    readonly Stopwatch _clock = Stopwatch.StartNew();
    readonly List<(V2 point, double at)> _samples = new();
    readonly SpiderLibrary _library;
    readonly PageWatcher _pageWatch = new();
    PageInputHook? _pageHook;
    ChatForm? _chat;
    DesktopState? _desk;
    bool _chatBusy;
    bool _pageMapQueued;
    readonly List<(string you, string it)> _chatLog = new();

    double _lastFrame, _lastCapture;
    string _lastSignature = "";
    bool _paused;
    bool _hidden;
    bool _quitting;
    bool _welcomeOpen;
    EntranceRun? _entrance;
    WinForms.Timer? _trayWiggle;
    WinForms.Timer? _updateTimer;
    UpdateRelease? _waitingUpdate;
    PreparedUpdate? _preparedUpdate;
    Task? _updatePrepare;
    bool _updateLaunched;
    bool _testUpdateScheduled;
    DateTimeOffset _updateRetryAfter;
    ToolStripMenuItem? _updateMenuItem;
    HabitatWorld? _habitatWorld;
    HabitatWindow? _habitatWindow;
    bool _leftDown, _rightDown, _pressed, _dragging;
    V2 _pressedAt;
    double _pressedAtTime;
    double _lastClickAt = -99;
    V2 _lastClickPoint;

    public SpiderApplicationContext(bool skipWelcome = false)
    {
        _store = new DiskStore();
        _settings = new Settings(_store);

        string? savedDesign = _settings.GetString("design");
        var design = string.IsNullOrWhiteSpace(savedDesign) ? new SpiderDesign() : SpiderDesign.FromJson(savedDesign);
        if (string.IsNullOrWhiteSpace(design.Name)) design.Name = "Mochi";
        _spider = new Spider(design, _map, new Rng((ulong)Math.Max(1, DateTime.Now.Ticks)));
        _spider.UserScale = M.Clamp(_settings.GetDouble("scale", 0.78), 0.5, 2.0);
        Spider.Words ??= new BuiltInSpiderWords((ulong)Math.Max(1, DateTime.Now.Ticks));
        _pageWatch.Dispatch = BeginInvokeOnUi;
        _pageWatch.SpiderAt = () => (_spider.Anchor.IsValid ? _spider.Anchor.LoopId : null, _spider.Pos);
        _pageWatch.OnChange += _ => QueuePageMap();
        _library = new SpiderLibrary(_store, _settings);
        _library.Seed(design);
        _habitatWorld = HabitatWorld.FromJson(_settings.GetString("habitat"));
        ApplySettings();
        StartupManager.Set(_settings.GetBool("launchAtLogin", false));
        _spider.PointerRemembered += _ => SaveAll(quiet: true);
        _spider.ScrollOrdered += order => _spider.ObeyScroll(order);

        RebuildMap(initial: true);
        LoadHammock();
        _overlay = new SpiderOverlay();
        _overlay.Show();
        _overlay.SetHidden(_hidden);

        _panel = new PanelForm(this);
        _panel.WarmUp();
        _menu = BuildMenu();
        _tray = new NotifyIcon
        {
            Icon = MakeTrayIcon(_hidden),
            Text = "Spider Buddy",
            Visible = true,
            ContextMenuStrip = _menu
        };
        _tray.MouseClick += (_, e) =>
        {
            if (e.Button == MouseButtons.Left) ShowPanel();
        };

        _timer = new DisplayTicker(Frame, action => _overlay.BeginInvoke(action));
        _lastFrame = _clock.Elapsed.TotalSeconds;
        _timer.Start();

        ScheduleUpdateCheck();

        if (!skipWelcome && !_settings.GetBool("welcomed", false)) BeginInvokeOnUi(() => BeginWelcome());
        else if (_settings.GetBool("inHabitat", false)) BeginInvokeOnUi(OpenHabitat);
    }

    public Spider Spider => _spider;
    public Settings Settings => _settings;
    public SpiderLibrary Library => _library;
    public bool Paused => _paused;
    public bool Hidden => _hidden;
    public bool Quitting => _quitting;
    public bool IsWelcomed => _settings.GetBool("welcomed", false);
    public bool WelcomeOpen => _welcomeOpen;
    public bool HabitatOpen => _habitatWindow is not null;

    public void CloseHabitat() => _habitatWindow?.Close();

    static Rect HabitatScreenBounds()
    {
        var area = WinForms.Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1470, 920);
        double w = Math.Clamp(Math.Round(area.Width * 2.75), 3000, 5600);
        double h = Math.Clamp(Math.Round(area.Height * 1.35), 1050, 1600);
        return new Rect(0, 0, w, h);
    }

    public void SetHabitatWeather(WeatherKind kind) => _habitatWindow?.SetWeatherForTest(kind);
    public string AppVersion => UpdateService.CurrentVersion;
    public bool UpdateAvailable => _waitingUpdate is not null;
    public string UpdateButtonLabel => _waitingUpdate is { } r ? $"Update to {r.Version}" : "Check Now";
    public bool UpdateChecksAutomatically => _settings.GetBool("updateCheck", true);
    public bool UpdateInstallsAutomatically => _settings.GetBool("updateInstall", false);
    public string? PreparedUpdatePath => _preparedUpdate?.Path;
    public string UpdateSummary => _waitingUpdate is { } r
        ? $"Version {UpdateService.CurrentVersion} — update {r.Version} is ready."
        : $"Version {UpdateService.CurrentVersion}.";

    void ApplySettings()
    {
        var s = _spider;
        s.FollowCursor = _settings.GetBool("followCursor", true);
        s.ApproachCursor = _settings.GetBool("approachCursor", false);
        s.PounceOnCursor = _settings.GetBool("pounceOnCursor", true);
        s.ClickToPickUp = _settings.GetBool("interactive", true);
        s.WebsEnabled = _settings.GetBool("webs", true);
        s.LeaveTraces = _settings.GetBool("traces", true);
        s.SetTraceLimit(_settings.GetInt("traceLimit", 24));
        s.Memory.LearnFromExperience = _settings.GetBool("learns", true);
        s.WildlifeEnabled = _settings.GetBool("wildlife", false);
        s.WildlifeFrequency = _settings.GetDouble("wildFrequency", 5400);
        s.VisitorsEnabled = _settings.GetBool("visitors", false);
        s.VisitFrequency = _settings.GetDouble("visitFrequency", 3600);
        s.VisitStay = _settings.GetDouble("visitStay", 300);
        s.FeelWeather = _settings.GetBool("feelWeather", true);
        s.FeelCommotion = _settings.GetBool("feelCommotion", true);
        s.DanceToMusic = _settings.GetBool("danceToMusic", true);
        s.ShowRain = _settings.GetBool("showRain", false);
        s.LowPowerOverride = _settings.GetBool("lowPowerOverride", false);
        s.ToySounds = _settings.GetBool("toySounds", true);
        _paused = _settings.GetBool("paused", false);
        _hidden = _settings.GetBool("hidden", false);
        var box = _settings.GetRect("confine");
        if (box is { } b) s.SetBox(b);

        _pageWatch.Scale = s.UserScale;
        _pageWatch.Standoff = 22 * s.UserScale;
        _pageWatch.LowPower = s.LowPower;
        _pageWatch.Paused = _paused || _hidden;
        _pageWatch.Enabled = _settings.GetBool("climbPages", false);
        SyncPageHook();
    }

    void SyncPageHook()
    {
        bool wanted = _pageWatch.Enabled && !_paused && !_hidden;
        if (wanted && _pageHook is null)
            _pageHook = new PageInputHook(
                (p, dy) => _pageWatch.Dispatch(() => _pageWatch.Scrolled(p, dy)),
                p => _pageWatch.Dispatch(() => _pageWatch.Clicked(p)));
        else if (!wanted && _pageHook is not null)
        {
            _pageHook.Dispose();
            _pageHook = null;
        }
    }

    public void ApplyScale(double scale)
    {
        _spider.UserScale = M.Clamp(scale, 0.5, 2.0);
        _settings.SetDouble("scale", _spider.UserScale);
        RebuildMap(force: true);
        SaveAll(quiet: true);
        _panel.MarkDirty();
    }

    public void SetEnergy(double energy)
    {
        _spider.Design.Personality.Energy = M.Clamp01((energy - 0.45) / (2.4 - 0.45));
        _settings.SetDouble("liveliness", energy);
        SaveAll(quiet: true);
        _panel.MarkDirty();
    }

    public void SetPaused(bool paused)
    {
        _paused = paused;
        _settings.SetBool("paused", paused);
        _pageWatch.Paused = paused || _hidden;
        SyncPageHook();
        _panel.MarkDirty();
    }

    public bool ClimbPages => _settings.GetBool("climbPages", false);
    public bool PagesConnected => _pageWatch.ExtensionConnected;
    public string VoiceSummary => Spider.Words is { } words
        ? $"{words.StatusLabel} · {words.Status}"
        : "No voice backend";
    public bool ChatReady => CanChat;
    public bool ChatOpen => _chat is { Visible: true };
    public bool Listening => _spider.Listening;
    public string LastThoughtText => _spider.CurrentThoughtText ?? "";
    public bool PageBridgeRunning => _pageWatch.Bridge.Running;

    public void CloseChat() => _chat?.Dismiss();

    public void SetPageWatchForTest(bool on)
    {
        _pageWatch.Enabled = on;
        if (!on) _pageWatch.Paused = true;
    }

    public void StartStage18Smoke()
    {
        var timer = new WinForms.Timer { Interval = 350 };
        timer.Tick += async (_, _) =>
        {
            timer.Stop();
            timer.Dispose();
            int failures = await Stage18Smoke.Run(this);
            Environment.ExitCode = failures == 0 ? 0 : 1;
            Program.SmokeLog(failures == 0 ? "stage18-smoke: all ok" : $"stage18-smoke: {failures} failed");
            Quit();
        };
        timer.Start();
    }

    public void StartStage19Smoke()
    {
        var timer = new WinForms.Timer { Interval = 350 };
        timer.Tick += async (_, _) =>
        {
            timer.Stop();
            timer.Dispose();
            int failures = await Stage19Smoke.Run(this);
            Environment.ExitCode = failures == 0 ? 0 : 1;
            Program.SmokeLog(failures == 0 ? "stage19-smoke: all ok" : $"stage19-smoke: {failures} failed");
            _updateLaunched = true; // never install a synthetic test update on quit
            Quit();
        };
        timer.Start();
    }

    public void StartStage20Smoke()
    {
        var timer = new WinForms.Timer { Interval = 350 };
        timer.Tick += async (_, _) =>
        {
            timer.Stop();
            timer.Dispose();
            int failures = await Stage20Smoke.Run(this);
            Environment.ExitCode = failures == 0 ? 0 : 1;
            Program.SmokeLog(failures == 0 ? "stage20-smoke: all ok" : $"stage20-smoke: {failures} failed");
            Quit();
        };
        timer.Start();
    }
    public string PagesStatus => !ClimbPages
        ? "Web-page climbing is off."
        : _pageWatch.Summary ?? (_pageWatch.ExtensionConnected
            ? "Extension connected. Open a browser filling a screen."
            : "Watching for a browser filling a screen.");
    public int PageLedgeCount => _pageWatch.Loops().Count;

    public void SetClimbPages(bool on)
    {
        if (on && !_settings.GetBool("askedToSeePages", false))
        {
            var answer = MessageBox.Show(
                "Spider Buddy will look at browser windows that fill a screen so its little spider can climb " +
                "the edges of cards and bars. Pictures are only read on this PC and are never saved or sent.\n\n" +
                "Turn this on?", "Climb web pages", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            _settings.SetBool("askedToSeePages", true);
            if (answer != DialogResult.Yes) { _panel.MarkDirty(); return; }
        }
        _settings.SetBool("climbPages", on);
        ApplySettings();
        RebuildMap(force: true);
        SaveAll(quiet: true);
        _panel.MarkDirty();
    }

    public void AddBrowserExtension()
    {
        string source = Path.Combine(AppContext.BaseDirectory, "Extension");
        string target = Path.Combine(_store.Root, "Extension");
        try
        {
            if (Directory.Exists(source))
            {
                Directory.CreateDirectory(target);
                foreach (var file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
                {
                    string rel = Path.GetRelativePath(source, file);
                    string dest = Path.Combine(target, rel);
                    Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
                    File.Copy(file, dest, overwrite: true);
                }
            }
            string? owner = _pageWatch.Browsers.FirstOrDefault();
            var page = PageWatcher.ExtensionsPage(owner ?? "chrome");
            try { Clipboard.SetText(page?.address ?? "chrome://extensions"); } catch { }
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
            MessageBox.Show(
                "The extension folder is open and the browser's extensions address is on the clipboard.\n\n" +
                "1. Open the extensions page in your browser.\n" +
                "2. Turn on Developer mode.\n" +
                "3. Choose Load unpacked and pick this Extension folder.\n\n" +
                "Then reload the page you are on.", "Add to browser", MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show("The extension folder could not be opened.\n\n" + ex.Message,
                "Add to browser", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    public void OpenExtensionFolder()
    {
        string target = Path.Combine(_store.Root, "Extension");
        if (!Directory.Exists(target)) target = Path.Combine(AppContext.BaseDirectory, "Extension");
        try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); } catch { }
    }

    public void TogglePaused() => SetPaused(!_paused);

    public void SetHidden(bool hidden)
    {
        _hidden = hidden;
        _overlay.SetHidden(hidden);
        _settings.SetBool("hidden", hidden);
        _pageWatch.Paused = _paused || hidden;
        SyncPageHook();
        _tray.Text = hidden ? "Spider Buddy (hidden)" : "Spider Buddy";
        var old = _tray.Icon;
        _tray.Icon = MakeTrayIcon(hidden);
        old?.Dispose();
        if (_menu.Items.Count > 0)
            _menu.Items[0].Text = (hidden ? "Show " : "Hide ") + SpiderName;
        _panel.MarkDirty();
    }

    public void ToggleHidden() => SetHidden(!_hidden);

    public void ShowPanel()
    {
        var started = Stopwatch.StartNew();
        _panel.RefreshIfDirty();
        _panel.ShowNearTray();
        _panel.BringToFront();
        Program.SmokeLog($"panel: opened in {started.Elapsed.TotalMilliseconds:0.0} ms");
    }

    public void PanelDirty() => _panel.MarkDirty();
    public bool PanelPageHasText(int index, string text) => _panel.PageHasText(index, text);
    public void HidePanel() => _panel.Hide();

    /// <summary>Debug-only visual check: renders the three Stage 16 windows.</summary>
    public void CaptureUi(string dir)
    {
        Directory.CreateDirectory(dir);
        void Save(Control c, string name)
        {
            c.PerformLayout();
            Application.DoEvents();
            using var bmp = new Bitmap(Math.Max(1, c.Width), Math.Max(1, c.Height));
            c.DrawToBitmap(bmp, new Rectangle(0, 0, bmp.Width, bmp.Height));
            bmp.Save(Path.Combine(dir, name), System.Drawing.Imaging.ImageFormat.Png);
        }

        var started = Stopwatch.StartNew();
        _panel.Show();
        _panel.RefreshIfDirty();
        Application.DoEvents();
        Program.SmokeLog($"panel: capture opened in {started.Elapsed.TotalMilliseconds:0.0} ms");
        for (int i = 0; i < _panel.PageCount; i++)
        {
            _panel.SelectPage(i);
            Application.DoEvents();
            Save(_panel, $"panel-{i}.png");
        }
        _panel.Hide();
        using (var studio = new StudioForm(this))
        {
            studio.Show();
            Application.DoEvents();
            Thread.Sleep(160);
            Application.DoEvents();
            Save(studio, "studio-body.png");
            studio.ShowTabForCapture(2);
            Application.DoEvents();
            Save(studio, "studio-hats.png");
            studio.ShowTabForCapture(10);
            Application.DoEvents();
            Save(studio, "studio-thoughts.png");
            studio.ShowTabForCapture(11);
            Application.DoEvents();
            Save(studio, "studio-library.png");
            studio.Close();
        }
        using (var welcome = new WelcomeForm(this))
        {
            welcome.Show();
            Application.DoEvents();
            Thread.Sleep(160);
            Application.DoEvents();
            Save(welcome, "welcome-hello.png");
            welcome.ShowPageForCapture(1);
            Application.DoEvents();
            Save(welcome, "welcome-menu.png");
            welcome.ShowPageForCapture(2);
            Application.DoEvents();
            Save(welcome, "welcome-rules.png");
            welcome.Close();
        }
        Program.SmokeLog("ui-shots: saved " + dir);
    }


    public void OpenStudio()
    {
        using var studio = new StudioForm(this);
        studio.ShowDialog();
        _panel.MarkDirty();
    }

    public async void CheckForUpdates() => await CheckForUpdatesAsync(manual: true);

    public async Task<UpdateRelease?> CheckForUpdatesAsync(bool manual)
    {
        try
        {
            var release = _waitingUpdate ?? await UpdateService.CheckAsync();
            MarkUpdateChecked();
            _updateRetryAfter = DateTimeOffset.MinValue;
            if (release is null)
            {
                _waitingUpdate = null;
                _preparedUpdate = null;
                RefreshUpdateUi();
                if (manual)
                    MessageBox.Show($"You are running the latest version ({UpdateService.CurrentVersion}).",
                        "Spider Buddy", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return null;
            }
            _waitingUpdate = release;
            RefreshUpdateUi();
            if (UpdateInstallsAutomatically) StartPreparingUpdate();
            if (manual)
            {
                using var dialog = new UpdateDialog(release);
                if (dialog.ShowDialog() == DialogResult.OK && dialog.InstallRequested)
                    await InstallUpdateAsync(release);
            }
            return release;
        }
        catch (Exception ex)
        {
            _updateRetryAfter = DateTimeOffset.UtcNow.AddHours(1);
            Program.SmokeLog("update: failed " + ex.GetType().Name + ": " + ex.Message);
            if (manual)
                MessageBox.Show("The update check couldn't be completed.\n\n" + ex.Message,
                    "Spider Buddy", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return null;
        }
        finally
        {
            ScheduleUpdateCheck();
        }
    }

    public async void InstallWaitingUpdate()
    {
        if (_waitingUpdate is not { } release)
        {
            CheckForUpdates();
            return;
        }
        await InstallUpdateAsync(release);
    }

    async Task InstallUpdateAsync(UpdateRelease release)
    {
        if (_updatePrepare is not null)
        {
            try { await _updatePrepare; } catch { }
        }
        if (_preparedUpdate is { } prepared && UpdateService.VerifyDownload(prepared.Path, release))
        {
            if (UpdateService.LaunchInstaller(prepared.Path))
            {
                _updateLaunched = true;
                Quit();
            }
            return;
        }
        using var progress = new UpdateProgressForm(release);
        progress.ShowDialog();
        if (progress.InstallerPath is null)
        {
            if (progress.Error is { } error)
                MessageBox.Show("The update could not be downloaded.\n\n" + error.Message,
                    "Spider Buddy", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        _preparedUpdate = new PreparedUpdate(release, progress.InstallerPath);
        if (UpdateService.LaunchInstaller(progress.InstallerPath))
        {
            _updateLaunched = true;
            Quit();
        }
    }

    void ScheduleUpdateCheck(bool soon = false)
    {
        _updateTimer?.Stop();
        _updateTimer?.Dispose();
        _updateTimer = null;
        bool test = UpdateService.Testing;
        if (!test && !UpdateChecksAutomatically) return;
        if (test && _testUpdateScheduled) return;
        if (test) _testUpdateScheduled = true;

        TimeSpan delay = test ? TimeSpan.FromMilliseconds(800)
            : soon ? TimeSpan.FromSeconds(2)
            : UpdateCheckDue() ? TimeSpan.FromSeconds(5)
            : TimeUntilUpdateDue();
        delay = TimeSpan.FromMilliseconds(Math.Clamp(delay.TotalMilliseconds, 1000, 24 * 60 * 60 * 1000));
        var timer = new WinForms.Timer { Interval = (int)delay.TotalMilliseconds };
        timer.Tick += async (_, _) =>
        {
            timer.Stop();
            timer.Dispose();
            if (_updateTimer == timer) _updateTimer = null;
            await CheckForUpdatesAsync(manual: false);
        };
        _updateTimer = timer;
        timer.Start();
    }

    bool UpdateCheckDue()
    {
        var now = DateTimeOffset.UtcNow;
        if (now < _updateRetryAfter) return false;
        string? text = _settings.GetString("updateLastCheck");
        if (!DateTimeOffset.TryParse(text, out var last)) return true;
        return now - last >= TimeSpan.FromHours(24);
    }

    TimeSpan TimeUntilUpdateDue()
    {
        var now = DateTimeOffset.UtcNow;
        DateTimeOffset next = _updateRetryAfter > now ? _updateRetryAfter : now;
        if (DateTimeOffset.TryParse(_settings.GetString("updateLastCheck"), out var last))
            next = last.AddHours(24) > next ? last.AddHours(24) : next;
        return next > now ? next - now : TimeSpan.FromSeconds(1);
    }

    void MarkUpdateChecked()
    {
        _settings.SetString("updateLastCheck", DateTimeOffset.UtcNow.ToString("O"));
        SaveAll(quiet: true);
    }

    public void SetUpdateAutoCheck(bool on)
    {
        _settings.SetBool("updateCheck", on);
        SaveAll(quiet: true);
        ScheduleUpdateCheck(soon: on);
        _panel.MarkDirty();
    }

    public void SetUpdateAutoInstall(bool on)
    {
        _settings.SetBool("updateInstall", on);
        SaveAll(quiet: true);
        if (on) StartPreparingUpdate();
        _panel.MarkDirty();
    }

    void StartPreparingUpdate()
    {
        if (_waitingUpdate is not { } release || _preparedUpdate is not null || _updatePrepare is not null) return;
        _updatePrepare = Task.Run(async () =>
        {
            try
            {
                string path = await UpdateService.DownloadAsync(release);
                BeginInvokeOnUi(() =>
                {
                    if (_waitingUpdate?.Version == release.Version)
                        _preparedUpdate = new PreparedUpdate(release, path);
                    RefreshUpdateUi();
                });
            }
            catch (Exception ex)
            {
                Program.SmokeLog("update: download failed " + ex.GetType().Name + ": " + ex.Message);
            }
            finally
            {
                BeginInvokeOnUi(() => _updatePrepare = null);
            }
        });
    }

    void RefreshUpdateUi()
    {
        if (_updateMenuItem is not null)
            _updateMenuItem.Text = _waitingUpdate is { } r ? $"Update to {r.Version}…" : "Check for Updates…";
        _panel.MarkDirty();
        if (_panel.Visible) _panel.RefreshIfDirty();
    }

    public void SetWaitingUpdateForTest(UpdateRelease? release)
    {
        _waitingUpdate = release;
        RefreshUpdateUi();
    }

    public void SetUpdatePreferencesForTest(bool check, bool install)
    {
        _settings.SetBool("updateCheck", check);
        _settings.SetBool("updateInstall", install);
        SaveAll(quiet: true);
    }

    public void OpenBugReport()
    {
        using var report = new BugReportForm(_spider.Design.Look);
        report.ShowDialog();
    }

    public void InviteVisitor()
    {
        if (!_spider.VisitorsEnabled || _spider.Visitors.Count >= _spider.MaxVisitors) return;
        _spider.SpawnVisitor();
        SaveAll(quiet: true);
    }

    public void OpenHabitat()
    {
        Program.SmokeLog("open: enter");
        if (_habitatWindow is not null)
        {
            _habitatWindow.Activate();
            return;
        }
        if (_welcomeOpen) return;
        _habitatWorld ??= HabitatWorld.Preset(HabitatBiome.Forest, HabitatScreenBounds());
        Program.SmokeLog("open: world " + _habitatWorld.Bounds.W + "x" + _habitatWorld.Bounds.H + " items " + _habitatWorld.Items.Count);
        _timer.Stop();
        _overlay.Hide();
        _spider.FreeBox();
        Program.SmokeLog("open: building map");
        _spider.SetMap(_habitatWorld.BuildMap(_spider.Scale));
        Program.SmokeLog("open: map built");
        _spider.InHabitat = true;
        Program.SmokeLog("open: constructing window");
        var window = new HabitatWindow(this, _habitatWorld);
        Program.SmokeLog("open: window constructed");
        _habitatWindow = window;
        window.Show();
        Program.SmokeLog("open: shown");
        window.Activate();
    }

    public void HabitatClosed(HabitatWindow window)
    {
        if (_habitatWindow != window) return;
        _habitatWindow = null;
        _spider.InHabitat = false;
        _spider.SetMap(_map);
        RebuildMap(force: true);
        _overlay.SetHidden(_hidden);
        _clock.Restart();
        _lastFrame = 0;
        _timer.Start();
        SaveAll(quiet: true);
    }

    public void SaveHabitat(HabitatWorld world, V2 camera)
    {
        Program.SmokeLog("save: begin");
        _habitatWorld = world;
        _settings.SetString("habitat", world.ToJson());
        Program.SmokeLog("save: json set");
        _settings.SetPoint("habitatCamera", camera);
        _settings.Save();
        Program.SmokeLog("save: done");
    }

    public void ComeHere()
    {
        _spider.ApproachCursor = true;
        _spider.SetCursor(PointerWorld());
        _spider.Nod();
    }

    public void TossIt()
    {
        if (_spider.IsHeld) _spider.EndGrab(new V2(650, 720));
        else
        {
            _spider.BeginGrab(_spider.Pos);
            _spider.EndGrab(new V2(650, 720));
        }
    }

    public void Swing()
    {
        if (!_spider.DropOnWeb()) _spider.Celebrate();
    }

    public void Feed(PreyKind kind) => _spider.ReleasePrey(kind);

    public void FeedWildlife() => _spider.ReleaseWildlife();

    public void ToggleVisitors(bool on)
    {
        _spider.VisitorsEnabled = on;
        _settings.SetBool("visitors", on);
        if (on && _spider.SpawnVisitor() is not null) { }
        SaveAll(quiet: true);
    }

    public void DismissVisitors() => _spider.DismissVisitors();

    public void BuildHammock()
    {
        if (!_spider.BuildHammock()) _spider.Celebrate();
        SaveAll(quiet: true);
    }

    public void NapHammock() => _spider.NapInHammock();

    public void ClearHammock()
    {
        _spider.LeaveHammock();
        _spider.Hammock.Exists = false;
        _spider.Hammock.Finished = false;
        _spider.Hammock.Progress = 0;
    }

    public void Peekaboo() => _spider.StartPeekaboo();

    public void SayHi() => _spider.Celebrate();

    public void KeepInBox()
    {
        var r = new Rect(_spider.Pos.X - 360, _spider.Pos.Y - 180, 720, 360);
        _spider.SetBox(r);
        _settings.SetRect("confine", r);
        SaveAll(quiet: true);
    }

    public void FreeBox()
    {
        _spider.FreeBox();
        _settings.Remove("confine");
        SaveAll(quiet: true);
    }

    public void ResetEverything()
    {
        if (MessageBox.Show("Restart Spider Buddy? Your spider, its things and your settings are kept.", "Spider Buddy",
                MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
        SaveAll(force: true);
        try
        {
            string? exe = Environment.ProcessPath;
            if (!string.IsNullOrWhiteSpace(exe))
                Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true, WorkingDirectory = AppContext.BaseDirectory });
        }
        catch { }
        Quit();
    }

    public void Quit()
    {
        if (_quitting) return;
        _quitting = true;
        Program.SmokeLog("quit: enter");
        if (!_updateLaunched && UpdateInstallsAutomatically && _preparedUpdate is { } pending &&
            File.Exists(pending.Path) && UpdateService.VerifyDownload(pending.Path, pending.Release) &&
            UpdateService.LaunchInstaller(pending.Path))
        {
            _updateLaunched = true;
            Program.SmokeLog("quit: launching prepared update");
        }
        if (_habitatWindow is { } habitat)
        {
            _habitatWindow = null;
            Program.SmokeLog("quit: closing habitat");
            habitat.Close();
            Program.SmokeLog("quit: habitat closed");
        }
        FrameStats.ReportStats(_spider);
        Program.SmokeLog("quit: save all");
        try
        {
            SaveAll(force: true);
            Program.SmokeLog("quit: save done");
        }
        catch (Exception ex)
        {
            Program.SmokeLog("quit: save failed " + ex.GetType().Name + ": " + ex.Message);
        }
        _timer.Stop();
        _timer.Dispose();
        _trayWiggle?.Stop();
        _trayWiggle?.Dispose();
        _trayWiggle = null;
        _updateTimer?.Stop();
        _updateTimer?.Dispose();
        _updateTimer = null;
        _tray.Visible = false;
        _tray.Dispose();
        Program.SmokeLog("quit: tray disposed");
        _pageWatch.Enabled = false;
        _pageHook?.Dispose();
        _pageHook = null;
        _chat?.Dispose();
        _chat = null;
        _overlay.Close();
        Program.SmokeLog("quit: overlay closed");
        _panel.Dispose();
        Program.SmokeLog("quit: panel disposed");
        ExitThread();
        Program.SmokeLog("quit: exit thread returned");
    }

    public void SaveAll(bool force = false, bool quiet = false)
    {
        _settings.SetString("design", _spider.Design.ToJson());
        _spider.Memory.Save(_settings);
        _settings.SetDouble("scale", _spider.UserScale);
        _settings.SetBool("followCursor", _spider.FollowCursor);
        _settings.SetBool("approachCursor", _spider.ApproachCursor);
        _settings.SetBool("pounceOnCursor", _spider.PounceOnCursor);
        _settings.SetBool("interactive", _spider.ClickToPickUp);
        _settings.SetBool("webs", _spider.WebsEnabled);
        _settings.SetBool("traces", _spider.LeaveTraces);
        _settings.SetInt("traceLimit", _spider.TraceLimit);
        _settings.SetBool("learns", _spider.Memory.LearnFromExperience);
        _settings.SetBool("wildlife", _spider.WildlifeEnabled);
        _settings.SetDouble("wildFrequency", _spider.WildlifeFrequency);
        _settings.SetBool("visitors", _spider.VisitorsEnabled);
        _settings.SetDouble("visitFrequency", _spider.VisitFrequency);
        _settings.SetDouble("visitStay", _spider.VisitStay);
        _settings.SetBool("feelWeather", _spider.FeelWeather);
        _settings.SetBool("feelCommotion", _spider.FeelCommotion);
        _settings.SetBool("danceToMusic", _spider.DanceToMusic);
        _settings.SetBool("showRain", _spider.ShowRain);
        _settings.SetBool("lowPowerOverride", _spider.LowPowerOverride);
        _settings.SetBool("feelPower", _settings.GetBool("feelPower", true));
        _settings.SetBool("launchAtLogin", _settings.GetBool("launchAtLogin", false));
        _settings.SetBool("updateCheck", _settings.GetBool("updateCheck", true));
        _settings.SetBool("updateInstall", _settings.GetBool("updateInstall", false));
        // _settings preserves updateLastCheck; writing it here would reset the daily timer.
        _settings.SetBool("tankWildlife", _settings.GetBool("tankWildlife", true));
        _settings.SetBool("widgets", _settings.GetBool("widgets", false));
        _settings.SetBool("climbPages", _settings.GetBool("climbPages", false));
        _settings.SetBool("askedToSeePages", _settings.GetBool("askedToSeePages", false));
        _settings.SetBool("toySounds", _spider.ToySounds);
        _settings.SetBool("paused", _paused);
        _settings.SetBool("hidden", _hidden);
        if (_habitatWorld is not null) _settings.SetString("habitat", _habitatWorld.ToJson());
        _settings.SetBool("inHabitat", _habitatWindow is not null);
        _settings.SetRect("confine", _spider.Box);
        SaveHammock();
        _settings.Save(force);
    }

    public void SetLaunchAtLogin(bool on)
    {
        _settings.SetBool("launchAtLogin", on);
        StartupManager.Set(on);
        SaveAll(quiet: true);
    }

    public void ApplyWelcome(bool wildlife, bool visitors, bool traces, bool learns, bool weather, bool login)
    {
        _spider.WildlifeEnabled = wildlife;
        _spider.VisitorsEnabled = visitors;
        _spider.LeaveTraces = traces;
        _spider.Memory.LearnFromExperience = learns;
        _spider.FeelWeather = weather;
        _settings.SetBool("welcomed", true);
        SetLaunchAtLogin(login);
        SaveAll(force: true);
    }

    public void BeginWelcome(bool replay = false)
    {
        if (_welcomeOpen) return;
        _welcomeOpen = true;
        _timer.Stop();
        var welcome = new WelcomeForm(this);
        welcome.FormClosed += (_, _) =>
        {
            _welcomeOpen = false;
            if (welcome.DialogResult == DialogResult.OK)
            {
                using var studio = new StudioForm(this);
                studio.ShowDialog();
            }
            if (!replay) StartEntrance();
            _clock.Restart();
            _lastFrame = 0;
            _timer.Start();
            welcome.Dispose();
        };
        welcome.Show();
    }

    void SaveHammock()
    {
        int side = !_spider.Hammock.Exists ? 0 : _spider.Hammock.Left ? 1 : 2;
        _settings.SetInt("hammock", side);
        _settings.SetInt("hammockStyle", (int)_spider.Hammock.Style);
        _settings.SetRect("hammockBox", _spider.Hammock.Box);
        _settings.SetBool("hammockFinished", _spider.Hammock.Finished);
        _settings.SetDouble("hammockProgress", _spider.Hammock.Progress);
        _settings.SetBool("hammockIn", _spider.InHammock);
    }

    void LoadHammock()
    {
        int side = _settings.GetInt("hammock", 0);
        if (side % 10 is not (1 or 2)) return;
        var box = _settings.GetRect("hammockBox");
        if (box is not { } b) return;
        _spider.Hammock.Box = b;
        _spider.Hammock.Exists = true;
        _spider.Hammock.Finished = _settings.GetBool("hammockFinished", true);
        _spider.Hammock.Left = side % 10 == 1;
        _spider.Hammock.Style = (HammockStyle)Math.Clamp(_settings.GetInt("hammockStyle", 0), 0, 3);
        _spider.Hammock.Progress = Math.Clamp(_settings.GetDouble("hammockProgress", 1), 0, 1);
        _spider.InHammock = _settings.GetBool("hammockIn", false) && _spider.Hammock.Finished;
    }

    void StartEntrance()
    {
        if (_entrance is not null || _hidden) return;
        var bounds = _map.WorldBounds;
        double top = bounds.MaxY;
        double x = Math.Max(bounds.MinX + 120, bounds.MaxX - 260);
        _entrance = new EntranceRun
        {
            X = x, Y = top + 150, TopY = top, BarY = top,
            FloorY = Math.Max(60, bounds.MinY + 46),
            Depth = M.Clamp((top - bounds.MinY) * 0.36, 160 * _spider.Scale, 520 * _spider.Scale)
        };
        WiggleTrayIcon();
    }

    void UpdateEntrance(double dt)
    {
        if (_entrance is not { } e) return;
        e.T += dt;
        e.PhaseT += dt;
        switch (e.Phase)
        {
            case 0:
                e.Y = e.TopY + 150;
                if (e.PhaseT > 1.4) { e.Phase = 1; e.PhaseT = 0; }
                break;
            case 1:
                e.Y = M.Lerp(e.TopY + 150, e.TopY - e.Depth * 0.14, M.EaseOutCubic(Math.Clamp(e.PhaseT / 0.9, 0, 1)));
                if (e.PhaseT > 0.95) { e.Phase = 2; e.PhaseT = 0; }
                break;
            case 2:
                e.Y = e.TopY - e.Depth * 0.14;
                if (e.PhaseT > 1.3) { e.Phase = 3; e.PhaseT = 0; }
                break;
            case 3:
                e.Y = e.TopY - e.Depth * 0.14 + 9 * _spider.Scale * M.EaseOutCubic(Math.Clamp(e.PhaseT / 0.7, 0, 1));
                if (e.PhaseT > 0.85) { e.Phase = 4; e.PhaseT = 0; e.DropFrom = e.Y; }
                break;
            case 4:
                e.Y = M.Lerp(e.DropFrom, e.FloorY + 40, M.EaseOutCubic(Math.Clamp(e.PhaseT / 2.0, 0, 1)));
                if (e.PhaseT > 2.1) { e.Phase = 5; e.PhaseT = 0; _spider.Celebrate(); }
                break;
            default:
                e.Y = e.FloorY + 40;
                if (e.PhaseT > 3.2) FinishEntrance(e);
                break;
        }
    }

    void FinishEntrance(EntranceRun e)
    {
        var spot = _map.NearestSpot(new V2(e.X, e.FloorY), 2400 * _spider.Scale, null, _spider.Scale);
        if (spot is { } s) _spider.SetAnchor(s.Anchor.LoopId, s.Anchor.SegIdx, s.Anchor.T, s.Anchor.Dir);
        else PlaceSpider();
        _spider.Nod();
        _entrance = null;
    }

    void WiggleTrayIcon()
    {
        _trayWiggle?.Stop();
        _trayWiggle?.Dispose();
        var timer = new WinForms.Timer { Interval = 95 };
        int ticks = 0;
        timer.Tick += (_, _) =>
        {
            ticks++;
            var old = _tray.Icon;
            _tray.Icon = MakeTrayIcon(_hidden, ticks % 2 == 1);
            old?.Dispose();
            if (ticks < 10) return;
            timer.Stop();
            _trayWiggle = null;
            timer.Dispose();
            var last = _tray.Icon;
            _tray.Icon = MakeTrayIcon(_hidden);
            last?.Dispose();
        };
        _trayWiggle = timer;
        timer.Start();
    }

    void RebuildMap(bool initial = false, bool force = false)
    {
        var desk = DesktopCapture.Poll();
        _desk = desk;
        _pageWatch.Update(desk);
        string signature = DesktopCapture.Signature(desk);
        if (!initial && !force && signature == _lastSignature) return;
        _lastSignature = signature;
        LayoutMap(desk);
    }

    void QueuePageMap()
    {
        if (_pageMapQueued) return;
        _pageMapQueued = true;
        BeginInvokeOnUi(() =>
        {
            _pageMapQueued = false;
            RebuildPageMap();
        });
    }

    /// <summary>A page look or scroll arrived: lay out only its ledges, not the whole desktop.</summary>
    void RebuildPageMap()
    {
        if (!_pageWatch.Enabled || _pageWatch.Paused || _hidden || _welcomeOpen || _habitatWindow is not null) return;
        var desk = _desk ?? DesktopCapture.Poll();
        _desk = desk;
        LayoutMap(desk);
    }

    void LayoutMap(DesktopState desk)
    {
        foreach (var film in _pageWatch.FilmScreens)
        {
            var screen = desk.Screens.FirstOrDefault(s => s.Frame.Contains(film.Mid));
            if (screen is not null && !desk.CinemaScreens.Any(c => c.Id == screen.Id)) desk.CinemaScreens.Add(screen);
        }
        bool pages = _pageWatch.Enabled && !_pageWatch.Paused;
        var old = _spider.Anchor;
        _map.Rebuild(desk, _spider.Scale, pages ? _pageWatch.Loops() : null, _spider.Box,
            pages ? _pageWatch.PageScreens : null);
        if (old.IsValid && _map.Loop(old.LoopId) is { } loop && loop.Segs.Count > 0)
        {
            int seg = Math.Min(old.SegIdx, loop.Segs.Count - 1);
            _spider.SetAnchor(old.LoopId, seg, Math.Min(old.T, loop.Segs[seg].Len), old.Dir);
        }
        else if (old.LoopId?.StartsWith("page:", StringComparison.Ordinal) == true)
            _spider.DetachAndFall(new V2(0, 24));
        else PlaceSpider();
    }

    Point ScreenPointOf(V2 world)
    {
        var vs = SystemInformation.VirtualScreen;
        return new Point((int)Math.Round(vs.Left + world.X), (int)Math.Round(vs.Bottom - world.Y));
    }

    Rectangle BubbleScreenRect()
    {
        var r = SpiderRenderer.ThoughtBubbleRect(_spider.BuildPose());
        var vs = SystemInformation.VirtualScreen;
        return Rectangle.FromLTRB(
            (int)Math.Round(vs.Left + r.MinX), (int)Math.Round(vs.Bottom - r.MaxY),
            (int)Math.Round(vs.Left + r.MaxX), (int)Math.Round(vs.Bottom - r.MinY));
    }

    bool BubbleAt(V2 p)
    {
        if (!_spider.ThoughtShowing) return false;
        var vs = SystemInformation.VirtualScreen;
        var r = SpiderRenderer.ThoughtBubbleRect(_spider.BuildPose());
        return r.Inset(5).Contains(p);
    }

    bool CanChat => _spider.Design.Intelligence && Spider.Words is { Status: VoiceStatus.Ready };

    public void OpenChat()
    {
        if (_hidden || _welcomeOpen || _habitatWindow is not null || !CanChat) return;
        if (_chat is null)
        {
            _chat = new ChatForm();
            _chat.OnSend += SendChat;
            _chat.Dismissed += () =>
            {
                _spider.EndListening();
                _chatBusy = false;
            };
        }
        _spider.BeginListening();
        var bubble = _spider.ThoughtShowing ? BubbleScreenRect() : (Rectangle?)null;
        _chat.OpenChat(SpiderName, ScreenPointOf(_spider.Pos), bubble);
    }

    async void SendChat(string message)
    {
        if (_chatBusy || Spider.Words is not { } words) return;
        _chatBusy = true;
        _chat?.SetWaiting(true);
        var history = _chatLog.TakeLast(8).ToList();
        try
        {
            var answer = await words.ReplyAsync(_spider.Design, _spider.Situation(), message, history);
            if (answer is WordsAnswer.Said said)
            {
                _spider.Speak(said.Text, said.Feeling);
                _chatLog.Add((message, said.Text));
                while (_chatLog.Count > 12) _chatLog.RemoveAt(0);
            }
            else if (answer is WordsAnswer.Declined)
                _spider.Speak("I'd rather just sit with you for a bit.", Feeling.Shy);
            else
                _spider.Speak("my words got tangled. tell me again?", Feeling.Curious);
        }
        catch
        {
            _spider.Speak("my words got tangled. tell me again?", Feeling.Curious);
        }
        finally
        {
            _chatBusy = false;
            if (_chat is { Visible: true }) _chat.SetWaiting(false);
        }
    }

    public void ChatForTest(string message)
    {
        OpenChat();
        if (!CanChat || _chat is null) return;
        _chat.DebugSend(message);
    }

    string SpiderName => string.IsNullOrWhiteSpace(_spider.Design.Name) ? "Your spider" : _spider.Design.Name;

    static Icon MakeTrayIcon(bool dim, bool wiggle = false)
    {
        using var bmp = new Bitmap(16, 16);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            if (wiggle) g.TranslateTransform(1.2f, 0);
            var ink = dim ? Color.FromArgb(105, 100, 94) : Color.FromArgb(45, 40, 35);
            using var brush = new SolidBrush(ink);
            using var pen = new Pen(ink, 1.6f);
            g.FillEllipse(brush, 4.5f, 6.5f, 6.5f, 7f);
            g.FillEllipse(brush, 5.8f, 3.8f, 4.2f, 4.4f);
            g.DrawLine(pen, 5.5f, 7f, 1.5f, 3.5f);
            g.DrawLine(pen, 5f, 9f, 1f, 9f);
            g.DrawLine(pen, 5.2f, 11f, 2f, 14.5f);
            g.DrawLine(pen, 10f, 7f, 14.5f, 3.5f);
            g.DrawLine(pen, 10.5f, 9f, 15f, 9f);
            g.DrawLine(pen, 10.3f, 11f, 14f, 14.5f);
        }
        IntPtr h = bmp.GetHicon();
        try
        {
            using var temporary = Icon.FromHandle(h);
            return (Icon)temporary.Clone();
        }
        finally { DestroyIcon(h); }
    }

    void PlaceSpider()
    {
        var spots = _map.SampleSpots(48, true, _spider.Scale);
        if (spots.Count == 0) spots = _map.SampleSpots(24, false, _spider.Scale);
        if (spots.Count > 0)
        {
            var spot = spots.OrderBy(s => s.Point.DistanceTo(new V2(320, SystemInformation.VirtualScreen.Height * 0.72))).First();
            _spider.SetAnchor(spot.Anchor.LoopId, spot.Anchor.SegIdx, spot.Anchor.T, spot.Anchor.Dir);
        }
        else
        {
            var loop = _map.AllLoops.FirstOrDefault(l => l.Segs.Count > 0);
            if (loop is not null) _spider.SetAnchor(loop.Id, 0, 0, 1);
        }
    }

    void Frame()
    {
        double now = _clock.Elapsed.TotalSeconds;
        double dt = Math.Clamp(now - _lastFrame, 0, 0.1);
        double gap = Math.Max(0, now - _lastFrame);
        _lastFrame = now;
        if (_welcomeOpen) return;
        if (_entrance is not null) { UpdateEntrance(dt); Draw(); return; }
        var meter = FrameStats.Enabled ? Stopwatch.StartNew() : null;
        if (now - _lastCapture > 0.55)
        {
            _lastCapture = now;
            RebuildMap();
        }

        UpdateMouse(now);
        _pageWatch.Tick();
        if (!_paused && !_hidden && _spider.InHabitat == false)
            _spider.Update(dt);
        double updateMs = meter?.Elapsed.TotalMilliseconds ?? 0;
        Draw();
        if (meter is not null)
            FrameStats.Record(meter.Elapsed.TotalMilliseconds, updateMs,
                meter.Elapsed.TotalMilliseconds - updateMs, gap * 1000);
    }

    void UpdateMouse(double now)
    {
        V2 p = PointerWorld();
        _spider.SetCursor(p);
        bool over = p.DistanceTo(_spider.Pos) <= (Spider.GrabRadius + 8) * _spider.Scale;
        bool left = (GetAsyncKeyState(0x01) & 0x8000) != 0;
        bool right = (GetAsyncKeyState(0x02) & 0x8000) != 0;

        if (left && !_leftDown)
        {
            _leftDown = true;
            _pressed = over && !_hidden;
            _pressedAt = p;
            _pressedAtTime = now;
            _dragging = false;
            if (_pressed && _spider.ClickToPickUp && !_spider.Cinema)
            {
                _spider.BeginGrab(p);
                _dragging = true;
            }
            else if (_pressed) _spider.Poke();
            else if (!_hidden && CanChat && BubbleAt(p)) OpenChat();
        }
        else if (left && _leftDown && _dragging)
        {
            _spider.MoveGrab(p);
            _samples.Add((p, now));
            while (_samples.Count > 2 && now - _samples[0].at > 0.12) _samples.RemoveAt(0);
        }
        else if (!left && _leftDown)
        {
            _leftDown = false;
            if (_dragging)
            {
                V2 v = V2.Zero;
                if (_samples.Count >= 2)
                {
                    var a = _samples[0];
                    var b = _samples[^1];
                    double span = Math.Max(0.02, b.at - a.at);
                    v = (b.point - a.point) / span;
                }
                _samples.Clear();
                _spider.EndGrab(v);
                if (v.Length < 30 && p.DistanceTo(_pressedAt) < 5 && now - _pressedAtTime < 0.35)
                    _spider.Poke();
            }
            _dragging = false;
        }

        if (right && !_rightDown)
        {
            _rightDown = true;
            if (!_hidden && CanChat && (over || BubbleAt(p))) OpenChat();
            else if (over)
            {
                _menu.Show(Cursor.Position);
            }
        }
        else if (!right) _rightDown = false;

        if (!left && !right)
        {
            // double-click celebration is measured on release so it never interrupts a drag
            if (_pressed && now - _lastClickAt < 0.38 && p.DistanceTo(_lastClickPoint) < 9)
            {
                _spider.Celebrate();
                _lastClickAt = -99;
            }
            else if (_pressed && now - _pressedAtTime < 0.35 && p.DistanceTo(_pressedAt) < 5)
            {
                _lastClickAt = now;
                _lastClickPoint = p;
            }
            _pressed = false;
        }
    }

    V2 PointerWorld()
    {
        var vs = SystemInformation.VirtualScreen;
        var p = Cursor.Position;
        return new V2(p.X - vs.Left, vs.Bottom - p.Y);
    }

    void Draw()
    {
        if (_hidden) return;
        if (_entrance is { } e)
        {
            var entrancePose = _spider.BuildPose();
            entrancePose.Pos = new V2(e.X, e.Y);
            entrancePose.Grounded = 0;
            entrancePose.Look = e.Phase switch
            {
                1 => new V2(0.25, -0.2),
                2 => new V2(-0.35, 0.15),
                3 => new V2(0.6, -0.25),
                _ => V2.Zero
            };
            entrancePose.Startled = e.Phase == 3 ? 1 : 0;
            entrancePose.Happy = e.Phase >= 5 ? 1 : 0;
            entrancePose.Emote = e.Phase >= 5 ? EmoteKind.Heart : EmoteKind.None;
            entrancePose.EmoteT = e.Phase >= 5 ? Math.Clamp((float)(e.PhaseT / 1.4), 0, 1) : 0;
            using var entranceSprite = SpriteRaster.Render(entrancePose, _spider.Design.Look, _spider.Scale);
            _overlay.Draw(_spider, entrancePose, entranceSprite, _map.WorldBounds.MaxY);
            return;
        }
        var pose = _spider.BuildPose();
        using var sprite = SpriteRaster.Render(pose, _spider.Design.Look, _spider.Scale);
        _overlay.Draw(_spider, pose, sprite);
    }

    ContextMenuStrip BuildMenu()
    {
        var m = new ContextMenuStrip();
        string name = string.IsNullOrWhiteSpace(_spider.Design.Name) ? "Your spider" : _spider.Design.Name;
        m.Items.Add(_hidden ? $"Show {name}" : $"Hide {name}", null, (_, _) => ToggleHidden());
        m.Items.Add("To the Middle", null, (_, _) => BringToMiddle());
        m.Items.Add("Spider Studio…", null, (_, _) => OpenStudio());
        m.Items.Add("Come Here", null, (_, _) => ComeHere());
        var talk = m.Items.Add("Talk to " + name + "…", null, (_, _) => OpenChat());
        talk.Enabled = CanChat;
        m.Items.Add("Open Habitat", null, (_, _) => OpenHabitat());

        var feed = new ToolStripMenuItem("Feed");
        foreach (var kind in Enum.GetValues<PreyKind>())
        {
            var k = kind;
            feed.DropDownItems.Add("Release a " + k + "…", null, (_, _) => Feed(k));
        }

        var behavior = new ToolStripMenuItem("Behavior");
        behavior.DropDownItems.Add("Say Hi", null, (_, _) => SayHi());
        behavior.DropDownItems.Add("Toss It", null, (_, _) => TossIt());
        behavior.DropDownItems.Add("Swing!", null, (_, _) => Swing());
        behavior.DropDownItems.Add("Peek-a-boo", null, (_, _) => Peekaboo());
        behavior.DropDownItems.Add(feed);
        behavior.DropDownItems.Add("Build a Hammock", null, (_, _) => BuildHammock());
        behavior.DropDownItems.Add("Nap in It", null, (_, _) => NapHammock());
        behavior.DropDownItems.Add("Clear It Away", null, (_, _) => ClearHammock());
        behavior.DropDownItems.Add("Keep in a Box…", null, (_, _) => KeepInBox());
        behavior.DropDownItems.Add("Let It Out of the Box", null, (_, _) => FreeBox());
        m.Items.Add(behavior);

        feed.DropDownItems.Add(new ToolStripSeparator());
        feed.DropDownItems.Add(CheckItem("Let Creatures Wander In", () => _spider.WildlifeEnabled,
            v => { _spider.WildlifeEnabled = v; SaveAll(quiet: true); }));

        var size = new ToolStripMenuItem("Size");
        foreach (var (label, value) in new[] { ("Tiny", 0.62), ("Small", 0.78), ("Medium", 0.95), ("Large", 1.2), ("Chonky", 1.55) })
            size.DropDownItems.Add(label, null, (_, _) => ApplyScale(value));
        m.Items.Add(size);

        var energy = new ToolStripMenuItem("Energy");
        foreach (var (label, value) in new[] { ("Sleepy", 0.5), ("Calm", 0.8), ("Normal", 1.0), ("Playful", 1.5), ("Caffeinated", 2.4) })
            energy.DropDownItems.Add(label, null, (_, _) => SetEnergy(value));
        m.Items.Add(energy);

        m.Items.Add(new ToolStripSeparator());
        var toggles = new ToolStripMenuItem("Toggles");
        toggles.DropDownItems.Add(CheckItem("Follow the Cursor", () => _spider.FollowCursor, v => { _spider.FollowCursor = v; SaveAll(quiet: true); }));
        toggles.DropDownItems.Add(CheckItem("Pounce on the Cursor", () => _spider.PounceOnCursor, v => { _spider.PounceOnCursor = v; SaveAll(quiet: true); }));
        toggles.DropDownItems.Add(CheckItem("Shoot Webs", () => _spider.WebsEnabled, v => { _spider.WebsEnabled = v; SaveAll(quiet: true); }));
        toggles.DropDownItems.Add(CheckItem("Click to Pick Up", () => _spider.ClickToPickUp, v => { _spider.ClickToPickUp = v; SaveAll(quiet: true); }));
        toggles.DropDownItems.Add(CheckItem("Build Hammocks", () => _spider.Design.Habits.Hammock > 0.05,
            v => { _spider.Design.Habits.Hammock = v ? 0.5 : 0; SaveAll(quiet: true); }));
        toggles.DropDownItems.Add(CheckItem("Leave Traces", () => _spider.LeaveTraces, v => { _spider.LeaveTraces = v; SaveAll(quiet: true); }));
        toggles.DropDownItems.Add(CheckItem("Climb Web Pages", () => ClimbPages, v => SetClimbPages(v)));
        toggles.DropDownItems.Add(CheckItem("Pause", () => _paused, v => SetPaused(v)));
        toggles.DropDownItems.Add(CheckItem("Launch at Login", () => _settings.GetBool("launchAtLogin", false), v => SetLaunchAtLogin(v)));
        m.Items.Add(toggles);

        _updateMenuItem = new ToolStripMenuItem(_waitingUpdate is { } update ? $"Update to {update.Version}…" : "Check for Updates…");
        _updateMenuItem.Click += (_, _) => CheckForUpdates();
        m.Items.Add(_updateMenuItem);
        m.Items.Add("Report a Bug…", null, (_, _) => OpenBugReport());
        m.Items.Add("Bring " + name + " to the Middle", null, (_, _) => BringToMiddle());
        m.Items.Add(new ToolStripSeparator());
        m.Items.Add("Reset Everything…", null, (_, _) => ResetEverything());
        m.Items.Add("Quit Spider Buddy", null, (_, _) => Quit());
        return m;
    }

    ToolStripMenuItem CheckItem(string text, Func<bool> get, Action<bool> set)
    {
        var item = new ToolStripMenuItem(text) { Checked = get() };
        item.Click += (_, _) => { set(!get()); item.Checked = get(); };
        return item;
    }

    public void BringToMiddle()
    {
        if (_spider.BringToMiddle()) return;
        var r = _map.WorldBounds;
        var target = new V2(r.Min.X + r.W / 2, r.Min.Y + r.H * 0.6);
        var spot = _map.NearestSpot(target, 800 * _spider.Scale, null, _spider.Scale);
        if (spot is { } s)
        {
            _spider.SetAnchor(s.Anchor.LoopId, s.Anchor.SegIdx, s.Anchor.T, s.Anchor.Dir);
            _spider.Nod();
        }
    }

    void BeginInvokeOnUi(Action action)
    {
        if (_overlay is not { IsHandleCreated: true }) return;
        _overlay.BeginInvoke(action);
    }

    [DllImport("user32.dll")]
    static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    static extern bool DestroyIcon(IntPtr hIcon);
}

/// <summary>Paces the real app at the display's composition clock instead of the
/// 15.6 ms WM_TIMER quantum. DwmFlush blocks until the next composition, so the
/// UI thread receives one posted frame at a time and never builds a backlog.</summary>
sealed class DisplayTicker : IDisposable
{
    readonly Action _tick;
    readonly Action<Action> _post;
    Thread? _thread;
    volatile bool _running;
    int _pending;
    bool _disposed;

    public DisplayTicker(Action tick, Action<Action> post)
    {
        _tick = tick;
        _post = post;
    }

    public void Start()
    {
        if (_disposed || _running) return;
        _running = true;
        _thread = new Thread(Loop) { IsBackground = true, Name = "display ticker" };
        _thread.Start();
    }

    public void Stop()
    {
        _running = false;
        var thread = _thread;
        _thread = null;
        if (thread is not null && thread.IsAlive && thread != Thread.CurrentThread)
            thread.Join(500);
    }

    public void Dispose()
    {
        _disposed = true;
        Stop();
    }

    void Loop()
    {
        while (_running)
        {
            int hr;
            try { hr = DwmFlush(); }
            catch { hr = -1; }
            if (hr != 0) Thread.Sleep(16);
            if (!_running) break;
            if (Interlocked.Exchange(ref _pending, 1) != 0) continue;
            try
            {
                _post(() =>
                {
                    Interlocked.Exchange(ref _pending, 0);
                    if (_running) _tick();
                });
            }
            catch
            {
                Interlocked.Exchange(ref _pending, 0);
                _running = false;
            }
        }
    }

    [DllImport("dwmapi.dll")]
    static extern int DwmFlush();
}

sealed class EntranceRun
{
    public int Phase;
    public double PhaseT;
    public double T;
    public double X, Y;
    public double TopY, FloorY, DropFrom, BarY, Depth;
}

public sealed partial class SpiderOverlay : Form
{
    const int WS_EX_LAYERED = 0x80000, WS_EX_TRANSPARENT = 0x20, WS_EX_NOACTIVATE = 0x08000000,
        WS_EX_TOOLWINDOW = 0x80;

    const int SpritePad = 6;

    Bitmap _canvas;
    Graphics _g;
    readonly int _screenLeft, _screenTop, _screenHeight;
    IntPtr _memDc, _bitmap;
    bool _hidden;

    public SpiderOverlay()
    {
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        TopMost = true;
        var screen = SystemInformation.VirtualScreen;
        _screenLeft = screen.Left;
        _screenTop = screen.Top;
        _screenHeight = screen.Height;
        Bounds = new Rectangle(screen.Left, screen.Top, 1, 1);
        _canvas = new Bitmap(1, 1, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
        _g = Graphics.FromImage(_canvas);
        ConfigureGraphics(_g);
        _memDc = CreateCompatibleDC(GetDC(IntPtr.Zero));
    }

    static void ConfigureGraphics(Graphics g)
    {
        g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
        g.CompositingQuality = System.Drawing.Drawing2D.CompositingQuality.HighSpeed;
        g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
        g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighSpeed;
    }

    void EnsureCanvas(int width, int height)
    {
        if (_canvas.Width == width && _canvas.Height == height) return;
        _g.Dispose();
        _canvas.Dispose();
        _canvas = new Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
        _g = Graphics.FromImage(_canvas);
        ConfigureGraphics(_g);
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
            return cp;
        }
    }

    protected override void OnPaintBackground(PaintEventArgs e) { }
    protected override void OnPaint(PaintEventArgs e) { }

    public void SetHidden(bool hidden)
    {
        _hidden = hidden;
        if (hidden) Hide(); else Show();
    }

    public void Draw(Spider spider, SpiderPose pose, SkiaSharp.SKBitmap sprite, double silkTopWorld = double.NaN)
    {
        if (_hidden || !IsHandleCreated) return;
        double side = SpriteRaster.SpriteSide(spider.Scale);
        int spriteSide = (int)Math.Ceiling(side);
        int width = spriteSide + SpritePad * 2;
        int left = (int)Math.Round(pose.Pos.X - side / 2) - SpritePad;
        int spriteTop = (int)Math.Round(_screenHeight - pose.Pos.Y - side / 2) - SpritePad;
        int top = spriteTop;
        int height = spriteSide + SpritePad * 2;
        if (double.IsFinite(silkTopWorld))
        {
            int lineTop = (int)Math.Floor(_screenHeight - silkTopWorld);
            int lineBottom = (int)Math.Ceiling(_screenHeight - pose.Pos.Y + 24);
            top = Math.Min(top, lineTop);
            height = Math.Max(spriteTop + height, lineBottom) - top;
        }
        EnsureCanvas(width, height);
        _g.Clear(Color.Transparent);
        if (double.IsFinite(silkTopWorld))
        {
            using var pen = new Pen(Color.FromArgb(235, 232, 226, 216), 1.4f);
            float lineX = (float)(pose.Pos.X - left);
            _g.DrawLine(pen, lineX, (float)(_screenHeight - silkTopWorld - top), lineX,
                (float)(_screenHeight - pose.Pos.Y + 24 - top));
        }
        using var bmp = BitmapFrom(sprite);
        _g.DrawImageUnscaled(bmp, SpritePad, spriteTop - top);
        _g.Flush();
        PushLayered(_screenLeft + left, _screenTop + top, width, height);
    }

    static Bitmap BitmapFrom(SkiaSharp.SKBitmap sk)
    {
        int w = sk.Width, h = sk.Height;
        var bmp = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
        var data = bmp.LockBits(new Rectangle(0, 0, w, h), System.Drawing.Imaging.ImageLockMode.WriteOnly,
            System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
        IntPtr src = sk.GetPixels();
        int srcStride = sk.RowBytes;
        var row = new byte[w * 4];
        for (int y = 0; y < h; y++)
        {
            Marshal.Copy(src + y * srcStride, row, 0, row.Length);
            Marshal.Copy(row, 0, data.Scan0 + y * data.Stride, row.Length);
        }
        bmp.UnlockBits(data);
        return bmp;
    }

    void PushLayered(int left, int top, int width, int height)
    {
        IntPtr screenDc = GetDC(IntPtr.Zero);
        _bitmap = _canvas.GetHbitmap(Color.FromArgb(0));
        IntPtr old = SelectObject(_memDc, _bitmap);
        var dst = new POINT { X = left, Y = top };
        var size = new SIZE { CX = width, CY = height };
        var src = new POINT { X = 0, Y = 0 };
        var blend = new BLENDFUNCTION
        {
            BlendOp = 0, BlendFlags = 0, SourceConstantAlpha = 255, AlphaFormat = 1
        };
        UpdateLayeredWindow(Handle, screenDc, ref dst, ref size, _memDc, ref src, 0, ref blend, 2);
        SelectObject(_memDc, old);
        DeleteObject(_bitmap);
        ReleaseDC(IntPtr.Zero, screenDc);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { _g.Dispose(); _canvas.Dispose(); DeleteDC(_memDc); }
        base.Dispose(disposing);
    }

    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct SIZE { public int CX, CY; }
    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }

    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hWnd, IntPtr hDc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("user32.dll", SetLastError = true)]
    static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize,
        IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);
}
