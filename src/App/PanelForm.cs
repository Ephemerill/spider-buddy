using SpiderBuddy.Core;

namespace SpiderBuddy.App;

/// <summary>The rounded popup under the tray icon: seven pages, all built when it opens.</summary>
public sealed class PanelForm : Form
{
    readonly SpiderApplicationContext _app;
    readonly TabControl _tabs = new()
    {
        Dock = DockStyle.Fill, Appearance = TabAppearance.Normal,
        SizeMode = TabSizeMode.Fixed, ItemSize = new Size(76, 24)
    };
    bool _dirty;

    public PanelForm(SpiderApplicationContext app)
    {
        _app = app;
        Text = "Spider Buddy";
        FormBorderStyle = FormBorderStyle.FixedToolWindow;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        Size = new Size(600, 650);
        MinimizeBox = false;
        MaximizeBox = false;
        Controls.Add(_tabs);
        Build();
    }

    public void Sync()
    {
        int selected = _tabs.SelectedIndex;
        _tabs.TabPages.Clear();
        Build();
        if (selected >= 0 && selected < _tabs.TabPages.Count) _tabs.SelectedIndex = selected;
        _dirty = false;
    }

    public void MarkDirty() => _dirty = true;

    public int PageCount => _tabs.TabPages.Count;

    public bool PageHasText(int index, string text)
    {
        if (index < 0 || index >= _tabs.TabPages.Count) return false;
        return Descendants(_tabs.TabPages[index]).Any(c => c.Text.Contains(text, StringComparison.Ordinal));
    }

    static IEnumerable<Control> Descendants(Control parent)
    {
        foreach (Control child in parent.Controls)
        {
            yield return child;
            foreach (var grandchild in Descendants(child)) yield return grandchild;
        }
    }

    public void SelectPage(int index)
    {
        if (index >= 0 && index < _tabs.TabPages.Count) _tabs.SelectedIndex = index;
    }

    public void RefreshIfDirty()
    {
        if (_dirty) Sync();
    }

    public void ShowNearTray()
    {
        var wa = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1280, 800);
        Location = new Point(Math.Max(wa.Left + 8, wa.Right - Width - 12), Math.Max(wa.Top + 8, wa.Bottom - Height - 12));
        Show();
        Activate();
    }

    public void WarmUp()
    {
        CreateControl();
        // Lay the popup out once while the spider is still starting. Later
        // opens only move and show an already-measured window.
        Opacity = 0;
        Location = new Point(-32000, -32000);
        Show();
        Application.DoEvents();
        Hide();
        Opacity = 1;
    }

    /// <summary>A picture of the real panel for the welcome tour (spec 16.6).</summary>
    public Bitmap Snapshot()
    {
        using var panel = new PanelForm(_app);
        panel.CreateControl();
        panel.Opacity = 0;
        panel.Location = new Point(-32000, -32000);
        panel.Show();
        panel.RefreshIfDirty();
        Application.DoEvents();
        panel.Size = new Size(600, 650);
        panel.PerformLayout();
        var bmp = new Bitmap(panel.Width, panel.Height);
        panel.DrawToBitmap(bmp, new Rectangle(0, 0, bmp.Width, bmp.Height));
        return bmp;
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
            return;
        }
        base.OnFormClosing(e);
    }

    void Build()
    {
        _tabs.TabPages.Add(Page("Spider", BuildSpider()));
        _tabs.TabPages.Add(Page("Feed", BuildFeed()));
        _tabs.TabPages.Add(Page("Behavior", BuildBehavior()));
        _tabs.TabPages.Add(Page("Play", BuildPlay()));
        _tabs.TabPages.Add(Page("Your PC", BuildPc()));
        _tabs.TabPages.Add(Page("App", BuildApp()));
        _tabs.TabPages.Add(Page("Visitors", BuildVisitors()));
    }

    static TabPage Page(string title, Control content)
    {
        var page = new TabPage(title) { BackColor = Color.FromArgb(247, 244, 238), Padding = new Padding(0) };
        content.Dock = DockStyle.Fill;
        page.Controls.Add(content);
        return page;
    }

    static FlowLayoutPanel PagePanel()
    {
        return new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoScroll = true,
            Padding = new Padding(14, 12, 14, 16),
            BackColor = Color.FromArgb(247, 244, 238)
        };
    }

    static Label Heading(string text) => new()
    {
        Text = text.ToUpperInvariant(),
        AutoSize = true,
        Font = new Font("Segoe UI", 7.5f, FontStyle.Bold),
        ForeColor = Color.FromArgb(120, 110, 100),
        Margin = new Padding(0, 10, 0, 2)
    };

    static Label Note(string text, int width = 540) => new()
    {
        Text = text,
        AutoSize = true,
        MaximumSize = new Size(width, 0),
        Width = width,
        ForeColor = Color.FromArgb(110, 100, 90),
        Font = new Font("Segoe UI", 8f),
        Margin = new Padding(0, 2, 0, 6)
    };

    Label Status(string text) => new()
    {
        Text = text,
        AutoSize = false,
        Width = 540,
        Height = 44,
        ForeColor = Color.FromArgb(90, 80, 70),
        Margin = new Padding(0, 2, 0, 6)
    };

    Button Btn(string text, Action action)
    {
        var b = new Button
        {
            Text = text,
            AutoSize = false,
            Width = 540,
            Height = 30,
            TextAlign = ContentAlignment.MiddleLeft,
            FlatStyle = FlatStyle.System,
            Margin = new Padding(0, 2, 0, 4)
        };
        b.Click += (_, _) =>
        {
            action();
            if (_app.Quitting) return;
            _app.SaveAll(quiet: true);
            _dirty = true;
        };
        return b;
    }

    CheckBox Check(string text, bool value, Action<bool> set)
    {
        var c = new CheckBox
        {
            Text = text,
            Checked = value,
            AutoSize = false,
            Width = 540,
            Height = 26,
            Margin = new Padding(0, 1, 0, 1)
        };
        c.CheckedChanged += (_, _) => { set(c.Checked); _app.SaveAll(quiet: true); _dirty = true; };
        return c;
    }

    Control Choice(string title, string[] items, int selected, Action<int> set)
    {
        var row = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            AutoSize = true,
            Margin = new Padding(0, 1, 0, 1)
        };
        row.Controls.Add(new Label { Text = title, Width = 120, Height = 24, TextAlign = ContentAlignment.MiddleLeft });
        var box = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 400 };
        box.Items.AddRange(items);
        box.SelectedIndex = Math.Clamp(selected, 0, items.Length - 1);
        box.SelectedIndexChanged += (_, _) => { set(box.SelectedIndex); _app.SaveAll(quiet: true); _dirty = true; };
        row.Controls.Add(box);
        return new ComboBoxHost(row, box);
    }

    /// <summary>A ComboBox with its label, exposed as a control for the flow layout.</summary>
    sealed class ComboBoxHost : UserControl
    {
        public ComboBoxHost(Control row, ComboBox box)
        {
            Width = 550;
            Height = 28;
            row.Dock = DockStyle.Fill;
            Controls.Add(row);
            Box = box;
        }
        public ComboBox Box { get; }
    }

    Control Slider(string title, double min, double max, double value, Action<double> set, out Label valueLabel)
    {
        var panel = new Panel { Width = 550, Height = 48, Margin = new Padding(0, 1, 0, 3) };
        var label = new Label { Text = title, AutoSize = true, Location = new Point(0, 0) };
        var shown = new Label
        {
            Text = value.ToString("0.##"), AutoSize = true, ForeColor = Color.FromArgb(110, 100, 90),
            Location = new Point(350, 0)
        };
        valueLabel = shown;
        var bar = new TrackBar
        {
            Minimum = 0, Maximum = 100, TickStyle = TickStyle.None,
            Location = new Point(0, 18), Width = 540,
            Value = (int)Math.Round((value - min) / Math.Max(0.0001, max - min) * 100)
        };
        bar.ValueChanged += (_, _) =>
        {
            double v = min + (max - min) * bar.Value / 100.0;
            shown.Text = v.ToString("0.##");
            set(v);
        };
        bar.MouseUp += (_, _) => _app.SaveAll(quiet: true);
        panel.Controls.Add(label);
        panel.Controls.Add(shown);
        panel.Controls.Add(bar);
        return panel;
    }

    Control BuildSpider()
    {
        var p = PagePanel();
        string name = string.IsNullOrWhiteSpace(_app.Spider.Design.Name) ? "Your spider" : _app.Spider.Design.Name;
        if (_app.UpdateAvailable) p.Controls.Add(Btn(_app.UpdateButtonLabel, _app.InstallWaitingUpdate));
        p.Controls.Add(Btn(_app.Hidden ? $"Show {name}" : $"Hide {name}", _app.ToggleHidden));
        p.Controls.Add(Btn("To the Middle", _app.BringToMiddle));
        p.Controls.Add(Btn("Spider Studio…", _app.OpenStudio));
        p.Controls.Add(Btn("Come Here", _app.ComeHere));
        p.Controls.Add(Check("Pause", _app.Paused, _app.SetPaused));
        p.Controls.Add(Heading("Size"));
        var sizes = new[] { "Tiny 0.62", "Small 0.78", "Medium 0.95", "Large 1.2", "Chonky 1.55" };
        var sizeValues = new[] { 0.62, 0.78, 0.95, 1.2, 1.55 };
        int sizeIndex = Array.FindIndex(sizeValues, v => Math.Abs(v - _app.Spider.UserScale) < 0.01);
        p.Controls.Add(Choice("Size", sizes, sizeIndex < 0 ? 1 : sizeIndex, i => _app.ApplyScale(sizeValues[i])));
        p.Controls.Add(Heading("Energy"));
        var energies = new[] { "Sleepy 0.5", "Calm 0.8", "Normal 1.0", "Playful 1.5", "Caffeinated 2.4" };
        var energyValues = new[] { 0.5, 0.8, 1.0, 1.5, 2.4 };
        double liveliness = _app.Spider.Design.Personality.Liveliness;
        int eIndex = 0;
        for (int i = 0; i < energyValues.Length; i++)
            if (energyValues[i] <= liveliness + 0.15) eIndex = i;
        p.Controls.Add(Choice("Energy", energies, eIndex, i => _app.SetEnergy(energyValues[i])));
        p.Controls.Add(Heading("Growing up"));
        p.Controls.Add(Check("Learn From Experience", _app.Spider.Memory.LearnFromExperience, v => _app.Spider.Memory.LearnFromExperience = v));
        p.Controls.Add(Status(_app.Spider.Memory.LearnFromExperience
            ? $"{name} is {_app.Spider.Memory.Summary}, always close to the Studio."
            : "Its personality is fixed for now."));
        if (_app.Spider.Memory.LearnFromExperience)
            p.Controls.Add(Btn("Forget It All", () => _app.Spider.Memory.ForgetAll()));
        return p;
    }

    Control BuildFeed()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Let Something Loose"));
        p.Controls.Add(Note("It hunts whatever you let go, each kind its own way. You can pick them up and move them about yourself."));
        var grid = new FlowLayoutPanel { Width = 550, Height = 76, WrapContents = true, Margin = new Padding(0), AutoSize = false };
        foreach (var kind in Enum.GetValues<PreyKind>())
        {
            var b = new Button { Text = "A " + kind.ToString(), Width = 126, Height = 28, Margin = new Padding(0, 2, 3, 2) };
            b.Click += (_, _) => { _app.Feed(kind); _app.SaveAll(quiet: true); };
            grid.Controls.Add(b);
        }
        p.Controls.Add(grid);
        p.Controls.Add(Heading("Wildlife"));
        p.Controls.Add(Check("Let Creatures Wander In", _app.Spider.WildlifeEnabled, v => _app.Spider.WildlifeEnabled = v));
        double freq = _app.Spider.WildlifeFrequency;
        double f = Math.Log(freq / 5400.0) / Math.Log(600.0 / 5400.0);
        p.Controls.Add(Slider("How Often They Come", 0, 1, f, v =>
        {
            _app.Spider.WildlifeFrequency = 5400 * Math.Pow(600.0 / 5400.0, v);
        }, out var freqLabel));
        freqLabel.Text = $"about one every {Math.Max(1, Math.Round(freq / 60))} min";
        p.Controls.Add(Status(_app.Spider.WildlifeEnabled
            ? $"Rarely…now and then · one every {Math.Max(1, Math.Round(_app.Spider.WildlifeFrequency / 60))} minutes"
            : "Wildlife is off."));
        p.Controls.Add(Check("Creatures Live in the Habitat", _app.Settings.GetBool("tankWildlife", true), v => _app.Settings.SetBool("tankWildlife", v)));
        p.Controls.Add(Heading("Appetite"));
        double fed = _app.Spider.Fed;
        string n = string.IsNullOrWhiteSpace(_app.Spider.Design.Name) ? "Your spider" : _app.Spider.Design.Name;
        p.Controls.Add(Status(fed > 0.66 ? $"{n} is stuffed." : fed > 0.2 ? $"{n} is content." : $"{n} could eat."));
        p.Controls.Add(Note("The eight kinds above are the same ones that can wander in. Prey is capped at four loose."));
        return p;
    }

    Control BuildBehavior()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("The pointer"));
        p.Controls.Add(Check("Watch the Cursor", _app.Spider.FollowCursor, v => _app.Spider.FollowCursor = v));
        p.Controls.Add(Check("Come to the Cursor", _app.Spider.ApproachCursor, v => _app.Spider.ApproachCursor = v));
        p.Controls.Add(Check("Pounce on the Cursor", _app.Spider.PounceOnCursor, v => _app.Spider.PounceOnCursor = v));
        p.Controls.Add(Check("Click to Pick Up", _app.Spider.ClickToPickUp, v => _app.Spider.ClickToPickUp = v));
        p.Controls.Add(Heading("Silk"));
        p.Controls.Add(Check("Shoot Webs", _app.Spider.WebsEnabled, v => _app.Spider.WebsEnabled = v));
        p.Controls.Add(Check("Build Hammocks", _app.Spider.Design.Habits.Hammock > 0.05, v => _app.Spider.Design.Habits.Hammock = v ? 0.5 : 0));
        string name = string.IsNullOrWhiteSpace(_app.Spider.Design.Name) ? "Your spider" : _app.Spider.Design.Name;
        p.Controls.Add(Status(_app.Spider.Hammock.Exists ? $"{name} has a hammock in the corner." : _app.Spider.Design.Habits.Hammock > 0.05 ? "No hammock yet." : "Turn on Build Hammocks for one."));
        p.Controls.Add(Btn("Build One", _app.BuildHammock));
        p.Controls.Add(Btn("Nap in It", _app.NapHammock));
        p.Controls.Add(Btn("Clear It Away", _app.ClearHammock));
        p.Controls.Add(Heading("Traces"));
        p.Controls.Add(Check("Leave Traces", _app.Spider.LeaveTraces, v => _app.Spider.LeaveTraces = v));
        var limits = new[] { "A few (6)", "Some (12)", "Plenty (24)", "Lots (40)", "Unlimited (60)" };
        var vals = new[] { 6, 12, 24, 40, 60 };
        int li = Array.FindIndex(vals, v => v >= _app.Spider.TraceLimit);
        p.Controls.Add(Choice("Most at Once", limits, li < 0 ? 2 : li, i => _app.Spider.SetTraceLimit(vals[i])));
        p.Controls.Add(Btn("Tidy Up", _app.Spider.TidyTraces));
        p.Controls.Add(Note("A drawn box still suppresses traces. They fade on their own after a few minutes."));
        return p;
    }

    Control BuildPlay()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Ask it to"));
        p.Controls.Add(Btn("Say Hi", _app.SayHi));
        p.Controls.Add(Btn("Toss It", _app.TossIt));
        p.Controls.Add(Btn("Swing!", _app.Swing));
        p.Controls.Add(Btn("Peek-a-boo", _app.Peekaboo));
        p.Controls.Add(Btn("Come Here", _app.ComeHere));
        p.Controls.Add(Btn("Keep in a Box…", _app.KeepInBox));
        p.Controls.Add(Heading("Toys"));
        var toys = new FlowLayoutPanel { Width = 550, Height = 72, WrapContents = true, Margin = new Padding(0) };
        foreach (var kind in Enum.GetValues<ToyKind>())
        {
            if (kind == ToyKind.None) continue;
            var b = new Button { Text = kind.ToString(), Width = 96, Height = 28, Margin = new Padding(0, 2, 3, 2) };
            b.Click += (_, _) => { _app.Spider.PickToy(kind); _app.SaveAll(quiet: true); };
            toys.Controls.Add(b);
        }
        p.Controls.Add(toys);
        p.Controls.Add(Btn("Put Away", () => _app.Spider.PutAwayToy()));
        p.Controls.Add(Check("Bell Sound", _app.Spider.ToySounds, v => _app.Spider.ToySounds = v));
        p.Controls.Add(Heading("Places"));
        p.Controls.Add(Btn("Open Habitat", _app.OpenHabitat));
        return p;
    }

    Control BuildPc()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("This PC"));
        p.Controls.Add(Check("Low Power Mode", _app.Spider.LowPowerOverride, v => _app.Spider.LowPowerOverride = v));
        p.Controls.Add(Check("Feel the Battery", _app.Settings.GetBool("feelPower", true), v => _app.Settings.SetBool("feelPower", v)));
        p.Controls.Add(Check("Notice the Weather", _app.Spider.FeelWeather, v => _app.Spider.FeelWeather = v));
        p.Controls.Add(Check("Notice Pop-ups", _app.Spider.FeelCommotion, v => _app.Spider.FeelCommotion = v));
        p.Controls.Add(Check("Dance to Music", _app.Spider.DanceToMusic, v => _app.Spider.DanceToMusic = v));
        p.Controls.Add(Status(_app.Spider.MusicPlaying ? $"Listening · {_app.Spider.MusicBpm:0} BPM" : "No music detected."));
        p.Controls.Add(Check("Rain on the Screen", _app.Spider.ShowRain, v => _app.Spider.ShowRain = v));
        p.Controls.Add(Heading("Web pages"));
        p.Controls.Add(Check("Climb Web Pages", _app.ClimbPages, _app.SetClimbPages));
        p.Controls.Add(Status(_app.PagesStatus));
        p.Controls.Add(Btn("Add to Browser…", _app.AddBrowserExtension));
        p.Controls.Add(Btn("Open Extension Folder", _app.OpenExtensionFolder));
        p.Controls.Add(Note("Only a browser window that fills a screen becomes a page to climb. The extension helps with scrolling; without it the spider follows the page by pictures. Nothing on the page is read or sent."));
        return p;
    }

    Control BuildApp()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Startup"));
        p.Controls.Add(Check("Launch at Login", _app.Settings.GetBool("launchAtLogin", false), v =>
        {
            _app.SetLaunchAtLogin(v);
        }));
        p.Controls.Add(Heading("Updates"));
        var checkUpdates = Check("Check Automatically (daily)", _app.UpdateChecksAutomatically, _app.SetUpdateAutoCheck);
        p.Controls.Add(checkUpdates);
        var installUpdates = Check("Install Automatically (on quit)", _app.UpdateInstallsAutomatically, _app.SetUpdateAutoInstall);
        p.Controls.Add(installUpdates);
        installUpdates.Enabled = _app.UpdateChecksAutomatically;
        checkUpdates.CheckedChanged += (_, _) => installUpdates.Enabled = checkUpdates.Checked;
        p.Controls.Add(Btn("Check Now", _app.CheckForUpdates));
        p.Controls.Add(Status(_app.UpdateSummary));
        p.Controls.Add(Note("The Windows installer is signed and every download is checked against the app’s update key before it runs. An update found in the background waits on the Spider page."));
        p.Controls.Add(Note($"Windows version {_app.AppVersion}."));
        p.Controls.Add(Heading("Start Over"));
        p.Controls.Add(Note("Lost it, or something looks stuck? This starts the app afresh. Its looks and settings are kept."));
        p.Controls.Add(Btn("Reset Everything", _app.ResetEverything));
        p.Controls.Add(Heading("Help"));
        p.Controls.Add(Btn("Welcome Tour", () => _app.BeginWelcome(replay: true)));
        p.Controls.Add(Btn("Report a Bug…", _app.OpenBugReport));
        p.Controls.Add(Heading("Support"));
        p.Controls.Add(Note("Spider Buddy is completely free and I want to keep it that way. If you enjoy having it around, consider supporting the continued development :)"));
        p.Controls.Add(Btn("Buy Me a Coffee", () =>
        {
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("https://buymeacoffee.com/ephemeril") { UseShellExecute = true }); } catch { }
        }));
        return p;
    }

    Control BuildVisitors()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Other spiders"));
        p.Controls.Add(Check("Let Other Spiders Visit", _app.Spider.VisitorsEnabled, v => _app.ToggleVisitors(v)));
        p.Controls.Add(Heading("Visits"));
        double vf = Math.Log(Math.Max(1, _app.Spider.VisitFrequency) / 5400.0) / Math.Log(600.0 / 5400.0);
        p.Controls.Add(Slider("How Often", 0, 1, Math.Clamp(vf, 0, 1), v =>
        {
            _app.Spider.VisitFrequency = 5400 * Math.Pow(600.0 / 5400.0, v);
        }, out var freqLabel));
        freqLabel.Text = $"about one every {Math.Max(1, Math.Round(_app.Spider.VisitFrequency / 60))} min";
        p.Controls.Add(Slider("How Long They Stay", 30, 900, _app.Spider.VisitStay, v => _app.Spider.VisitStay = v, out var stayLabel));
        stayLabel.Text = $"{Math.Round(_app.Spider.VisitStay)} s";
        p.Controls.Add(Btn("Dismiss Visitors", _app.DismissVisitors));
        p.Controls.Add(Btn("Invite One Now", _app.InviteVisitor));
        p.Controls.Add(Note("Visitors arrive through the same desktop, hang about for a while, and leave on their own. No energy or alerts."));
        return p;
    }
}
