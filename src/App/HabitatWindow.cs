using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using SkiaSharp;
using SkiaSharp.Views.Desktop;
using SpiderBuddy.Core;
using SpiderBuddy.Renderer;
using WinForms = System.Windows.Forms;

namespace SpiderBuddy.App;

/// <summary>Stage 17 habitat window: glass tank, camera, weather, editor, map and knowledge.</summary>
public sealed class HabitatWindow : Form
{
    readonly SpiderApplicationContext _app;
    readonly WinForms.Timer _timer;
    readonly Label _name;
    readonly Button _decorateButton, _letOutButton, _mapButton, _feedButton, _weatherButton, _helpButton;
    readonly HabitatView _view;
    readonly HabitatDock _panel;
    readonly HabitatKnowledge _knowledge;
    readonly WeatherClock _weather;
    readonly TankMind _mind = new();
    readonly Stack<string> _undo = new(), _redo = new();
    HabitatWorld _world;
    SurfaceMap _map;
    string? _currentSaveId;
    bool _decorating, _closing, _loading, _tourShown, _decorTourShown;
    readonly bool _brainWasEnabled;
    readonly Dictionary<int, double> _doorLeave = new();
    double _last = -1;

    public HabitatWindow(SpiderApplicationContext app, HabitatWorld world)
    {
        Program.SmokeLog("habitat: ctor");
        _app = app;
        _world = world;
        _map = world.BuildMap(app.Spider.Scale);
        _knowledge = HabitatKnowledge.FromJson(app.Settings.GetString(HabitatKnowledge.Key));
        _knowledge.Meet(_world);
        var ws = WeatherSettings.FromJson(app.Settings.GetString(WeatherSettings.Key));
        _weather = new WeatherClock(ws, _world.Biome, Environment.TickCount);
        _weather.Restore(app.Settings.GetString("habitatWeatherNow"));
        _currentSaveId = app.Settings.GetString("habitatCurrentSave");
        _brainWasEnabled = app.Spider.BrainEnabled;
        app.Spider.BrainEnabled = false;
        app.Spider.SetMap(_map);
        app.Spider.InHabitat = true;
        _mind.Refresh(_world, _map, _knowledge, app.Spider.Scale);

        Text = "Habitat";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(1180, 720);
        MinimumSize = new Size(640, 440);
        RestoreGlass();
        BackColor = Color.FromArgb(18, 20, 18);
        ForeColor = Color.FromArgb(234, 227, 209);
        DoubleBuffered = true;

        var lid = new Panel { Dock = DockStyle.Top, Height = 58, BackColor = Color.FromArgb(30, 33, 29), Padding = new Padding(10, 6, 10, 6) };
        _letOutButton = Tool("Let Out", () => Close()); _letOutButton.Location = new Point(10, 15);
        _mapButton = Tool("Map", ShowMap); _mapButton.Location = new Point(100, 15);
        _name = new Label
        {
            Text = world.Name, AutoSize = false, Height = 30, Width = 360, TextAlign = ContentAlignment.MiddleCenter,
            Font = new Font("Segoe UI Semibold", 12f), ForeColor = Color.FromArgb(242, 232, 207),
            Location = new Point(194, 15)
        };
        _name.Click += (_, _) => Rename();
        _feedButton = Tool("Feed", ShowFeed); _feedButton.Anchor = AnchorStyles.Top | AnchorStyles.Right; _feedButton.Location = new Point(ClientSize.Width - 92, 15);
        _weatherButton = Tool("Weather", ShowWeather); _weatherButton.Anchor = AnchorStyles.Top | AnchorStyles.Right; _weatherButton.Location = new Point(ClientSize.Width - 184, 15);
        _decorateButton = Tool("Decorate", ToggleDecorate); _decorateButton.Anchor = AnchorStyles.Top | AnchorStyles.Right; _decorateButton.Location = new Point(ClientSize.Width - 288, 15);
        _helpButton = Tool("?", ShowTour); _helpButton.Anchor = AnchorStyles.Top | AnchorStyles.Right; _helpButton.Location = new Point(ClientSize.Width - 326, 15); _helpButton.Width = 30; _helpButton.Height = 30;
        using (var round = new GraphicsPath()) { round.AddEllipse(0, 0, 28, 28); _helpButton.Region = new Region(round); }
        lid.Controls.AddRange(new Control[] { _letOutButton, _mapButton, _name, _feedButton, _weatherButton, _decorateButton, _helpButton });
        void LayoutLid()
        {
            bool narrow = lid.Width < 960;
            _feedButton.Text = narrow ? "♨" : "Feed"; _weatherButton.Text = narrow ? "☁" : "Weather";
            _decorateButton.Text = narrow ? (_decorating ? "✓" : "✎") : (_decorating ? "Done" : "Decorate");
            _letOutButton.Text = narrow ? "↩" : "Let Out"; _mapButton.Text = narrow ? "▦" : "Map";
            _feedButton.Width = _weatherButton.Width = _decorateButton.Width = _letOutButton.Width = _mapButton.Width = narrow ? 34 : 84;
            _feedButton.Left = lid.Width - _feedButton.Width - 8;
            _weatherButton.Left = _feedButton.Left - _weatherButton.Width - 8;
            _decorateButton.Left = _weatherButton.Left - _decorateButton.Width - 8;
            _helpButton.Left = _decorateButton.Left - 38;
            _name.Left = Math.Max(_mapButton.Right + 10, (lid.Width - _name.Width) / 2);
            _name.Width = Math.Max(80, Math.Min(360, _helpButton.Left - _name.Left - 8));
        }
        lid.Resize += (_, _) => LayoutLid();
        LayoutLid();

        _panel = new HabitatDock(this) { Dock = DockStyle.Right, Width = 318, Visible = false };
        _view = new HabitatView(this, app, _world, _map) { Dock = DockStyle.Fill };
        Controls.Add(_view);
        Controls.Add(_panel);
        Controls.Add(lid);

        _timer = new WinForms.Timer { Interval = 33 };
        _timer.Tick += (_, _) => Tick();
        _timer.Start();
        if (_app.Settings.GetPoint("habitatCamera") is { } savedCamera) _view.SetCamera(savedCamera);
        else _view.SetCameraToSpider();
        Shown += (_, _) =>
        {
            if (_tourShown || TourSuppressed) return;
            _tourShown = true;
            if (!_app.Settings.GetBool(HabitatTourOverlay.SeenKey, false))
            {
                var t = new WinForms.Timer { Interval = 350 };
                t.Tick += (_, _) => { t.Stop(); t.Dispose(); ShowTour(); };
                t.Start();
            }
        };

        FormClosing += (_, _) =>
        {
            if (_closing) return;
            _closing = true;
            _timer.Stop();
            try
            {
                _app.SaveHabitat(_world, _view.CameraOrigin);
                _app.Settings.SetString(HabitatKnowledge.Key, _knowledge.ToJson());
                _app.Settings.SetString(WeatherSettings.Key, _weather.Settings.ToJson());
                _app.Settings.SetString("habitatWeatherNow", _weather.ToJson());
                _app.Settings.SetString("habitatGlass", $"{Left},{Top},{Width},{Height}");
                _app.Settings.Save();
            }
            catch (Exception ex) { Program.SmokeLog("habitat close error: " + ex); }
        };
        FormClosed += (_, _) =>
        {
            _app.Spider.BrainEnabled = _brainWasEnabled;
            _app.HabitatClosed(this);
        };
    }

    public HabitatWorld World => _world;
    public SurfaceMap Map => _map;
    public HabitatView View => _view;
    public HabitatDock Panel => _panel;
    public HabitatKnowledge Knowledge => _knowledge;
    public WeatherClock Weather => _weather;
    public TankMind Mind => _mind;
    public HabitatEcology Ecology => _mind.Ecology;
    public Settings WindowSettings => _app.Settings;
    public bool IsDecorating => _decorating;
    public string? CurrentSaveId => _currentSaveId;

    public static bool TourSuppressed
    {
        get
        {
            if (Environment.GetEnvironmentVariable("SPIDER_HABITAT_TOUR") is not null) return false;
            return Environment.GetEnvironmentVariables().Keys.Cast<string>().Any(k => k.StartsWith("SPIDER_", StringComparison.Ordinal));
        }
    }

    void RestoreGlass()
    {
        string? glass = _app.Settings.GetString("habitatGlass");
        if (string.IsNullOrWhiteSpace(glass)) return;
        var bits = glass.Split(',');
        if (bits.Length != 4 || !int.TryParse(bits[0], out int x) || !int.TryParse(bits[1], out int y) ||
            !int.TryParse(bits[2], out int w) || !int.TryParse(bits[3], out int h)) return;
        if (w < MinimumSize.Width || h < MinimumSize.Height) return;
        var screen = Screen.FromPoint(new Point(x + w / 2, y + h / 2)).WorkingArea;
        if (x + 80 < screen.Left || y + 40 < screen.Top || x > screen.Right - 80 || y > screen.Bottom - 40) return;
        StartPosition = FormStartPosition.Manual;
        Bounds = new Rectangle(x, y, w, h);
    }

    public IReadOnlyList<SavedHabitat> Habitats => HabitatLibrary.All();
    public SavedHabitat? CurrentSaved => HabitatLibrary.Saved(_currentSaveId);
    public bool CurrentChanged
    {
        get
        {
            var saved = CurrentSaved;
            if (saved is null) return true;
            var fitted = saved.Fitted(new SizeD(_world.Width, _world.Height));
            return fitted.ToJson() != _world.ToJson();
        }
    }

    static Button Tool(string text, Action action)
    {
        var b = new Button
        {
            Text = text, Width = 84, Height = 28, FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(48, 52, 46), ForeColor = Color.FromArgb(236, 228, 211),
            FlatAppearance = { BorderColor = Color.FromArgb(82, 88, 76) }, Font = new Font("Segoe UI Semibold", 9f)
        };
        b.Click += (_, _) => action();
        return b;
    }

    void Tick()
    {
        if (_closing) return;
        double now = Environment.TickCount64 / 1000.0;
        double dt = _last < 0 ? 1 / 60.0 : Math.Min(.08, Math.Max(.001, now - _last));
        _last = now;
        _view.Tick(dt);
        KeepDoors(dt);
        _view.Invalidate();
    }

    /// <summary>Open a shut door a step ahead of the spider and shut it again after it leaves.</summary>
    void KeepDoors(double dt)
    {
        if (_decorating) return;
        bool changed = false;
        foreach (var item in _world.Items)
        {
            double away = _app.Spider.Pos.DistanceTo(item.Rect.Mid);
            if (item.Kind == HabitatItemKind.DoorClosed && away < 58 * _app.Spider.Scale)
            {
                item.Kind = HabitatItemKind.Door;
                _doorLeave[item.Id] = 0; changed = true; break;
            }
            if (item.Kind == HabitatItemKind.Door)
            {
                if (away > 105 * _app.Spider.Scale)
                {
                    _doorLeave[item.Id] = _doorLeave.GetValueOrDefault(item.Id) + dt;
                    if (_doorLeave[item.Id] > 2.5) { item.Kind = HabitatItemKind.DoorClosed; changed = true; }
                }
                else _doorLeave[item.Id] = 0;
            }
        }
        if (changed) { Rebuild(); Save(); }
    }

    public void Rebuild()
    {
        _map = _world.BuildMap(_app.Spider.Scale);
        _app.Spider.SetMap(_map);
        _view.SetWorld(_world, _map);
        _knowledge.Meet(_world);
        _mind.Refresh(_world, _map, _knowledge, _app.Spider.Scale);
        _panel.RefreshHabitats();
    }

    public void PushUndo()
    {
        if (_loading) return;
        _undo.Push(_world.ToJson());
        _redo.Clear();
    }

    public void Undo()
    {
        if (_decorating) FinishDragEdit();
        if (_undo.Count == 0) return;
        _redo.Push(_world.ToJson());
        RestoreState(_undo.Pop());
    }

    public void Redo()
    {
        if (_redo.Count == 0) return;
        _undo.Push(_world.ToJson());
        RestoreState(_redo.Pop());
    }

    void RestoreState(string json)
    {
        if (HabitatWorld.FromJson(json) is not { } restored) return;
        _loading = true;
        try
        {
            _world = restored;
            _name.Text = _world.Name;
            _map = _world.BuildMap(_app.Spider.Scale);
            _app.Spider.SetMap(_map);
            _view.SetWorld(_world, _map);
            _knowledge.Meet(_world);
            _mind.Refresh(_world, _map, _knowledge, _app.Spider.Scale);
            _panel.RefreshHabitats();
            Save();
        }
        finally { _loading = false; }
        _view.Invalidate();
    }

    void FinishDragEdit()
    {
        _view.CommitEdit();
    }

    /// <summary>Load a saved habitat, as one undoable edit.</summary>
    public void LoadSaved(string id)
    {
        var saved = HabitatLibrary.Saved(id);
        if (saved is null) return;
        PushUndo();
        var fitted = saved.Fitted(new SizeD(_world.Width, _world.Height));
        _currentSaveId = id;
        _app.Settings.SetString("habitatCurrentSave", id);
        _loading = true;
        try
        {
            _world = fitted; _name.Text = _world.Name;
            _map = _world.BuildMap(_app.Spider.Scale); _app.Spider.SetMap(_map);
            _view.SetWorld(_world, _map); _view.SetCameraToSpider();
            _knowledge.Meet(_world); _mind.Refresh(_world, _map, _knowledge, _app.Spider.Scale);
            _panel.RefreshHabitats(); Save();
        }
        finally { _loading = false; }
    }

    public void SaveCurrent()
    {
        var saved = CurrentSaved;
        if (saved is null) { SaveAsNew(); return; }
        saved.Habitat = _world.Clone();
        saved.Saved = DateTime.UtcNow;
        HabitatLibrary.Store(saved);
        _panel.Status("Saved “" + saved.Name + "”");
        _panel.RefreshHabitats();
    }

    public void SaveAsNew()
    {
        string suggested = HabitatLibrary.FreshName("My " + _world.Biome.Label());
        string? name = Prompt("Save This Habitat", suggested);
        if (string.IsNullOrWhiteSpace(name)) return;
        var saved = new SavedHabitat
        {
            Id = Guid.NewGuid().ToString("D"), Name = name.Trim(), Saved = DateTime.UtcNow, Habitat = _world.Clone()
        };
        if (!HabitatLibrary.Store(saved)) { MessageBox.Show(this, "It couldn’t be saved."); return; }
        _currentSaveId = saved.Id;
        _app.Settings.SetString("habitatCurrentSave", saved.Id);
        _panel.Status("Saved “" + saved.Name + "”"); _panel.RefreshHabitats();
    }

    public void RenameSaved(string id)
    {
        var saved = HabitatLibrary.Saved(id); if (saved is null) return;
        string? name = Prompt("Rename “" + saved.Name + "”", saved.Name);
        if (!string.IsNullOrWhiteSpace(name)) { HabitatLibrary.Rename(id, name.Trim()); _panel.RefreshHabitats(); }
    }

    public void UpdateSaved(string id)
    {
        var saved = HabitatLibrary.Saved(id); if (saved is null) return;
        saved.Habitat = _world.Clone(); saved.Saved = DateTime.UtcNow; HabitatLibrary.Store(saved);
        _currentSaveId = id; _app.Settings.SetString("habitatCurrentSave", id);
        _panel.Status("Updated “" + saved.Name + "”"); _panel.RefreshHabitats();
    }

    public void DeleteSaved(string id)
    {
        var saved = HabitatLibrary.Saved(id); if (saved is null) return;
        if (MessageBox.Show(this, $"Delete “{saved.Name}”? It’s gone for good — the tank stays as it is.",
            "Delete Habitat", MessageBoxButtons.OKCancel, MessageBoxIcon.Warning) != DialogResult.OK) return;
        HabitatLibrary.Delete(id);
        if (_currentSaveId == id) { _currentSaveId = null; _app.Settings.Remove("habitatCurrentSave"); }
        _panel.RefreshHabitats();
    }

    public void ShareSaved(string id)
    {
        var saved = HabitatLibrary.Saved(id); if (saved is null) return;
        using var dialog = new SaveFileDialog
        {
            Filter = "Spider habitat (*.spiderhabitat)|*.spiderhabitat|JSON (*.json)|*.json",
            FileName = saved.Name + ".spiderhabitat", Title = "Share a copy of the habitat"
        };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        try { HabitatLibrary.Export(saved, dialog.FileName); _panel.Status("A copy is ready to pass on"); }
        catch { MessageBox.Show(this, "It couldn’t be written there."); }
    }

    public void ShowSavedInFolder(string id)
    {
        try
        {
            string path = Path.Combine(HabitatLibrary.Folder, id + ".json");
            if (!File.Exists(path)) return;
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
        }
        catch { }
    }

    public void ImportHabitat()
    {
        using var dialog = new OpenFileDialog
        {
            Filter = "Spider habitats (*.spiderhabitat;*.json)|*.spiderhabitat;*.json|All files (*.*)|*.*",
            Title = "Bring in a habitat"
        };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        try { var saved = HabitatLibrary.ImportFile(dialog.FileName); LoadSaved(saved.Id); _panel.Status("Brought in “" + saved.Name + "”"); }
        catch { MessageBox.Show(this, "“" + Path.GetFileName(dialog.FileName) + "” isn’t a habitat this app can read."); }
    }

    public void ApplyBiome(HabitatBiome biome)
    {
        if (_world.Biome == biome) return;
        PushUndo(); _world.Biome = biome; Rebuild(); Save();
    }

    public void StartAfresh(HabitatBiome biome, bool surprise)
    {
        NewWorld(biome, surprise);
    }

    public void EmptyTank()
    {
        PushUndo();
        _world = HabitatWorld.Empty(_world.Bounds);
        _world.Name = "Bare Tank";
        _currentSaveId = null; _app.Settings.Remove("habitatCurrentSave");
        _name.Text = _world.Name; Rebuild(); _view.SetCameraToSpider(); Save();
    }

    public void RememberWindow()
    {
        _app.Settings.SetString("habitatGlass", $"{Left},{Top},{Width},{Height}");
        _app.Settings.Save();
    }

    void Rename()
    {
        string? name = Prompt("Name the habitat", _world.Name);
        if (string.IsNullOrWhiteSpace(name)) return;
        _world.Name = name.Trim(); _name.Text = _world.Name; Save();
    }

    public string? Prompt(string title, string value)
    {
        using var d = new Form { Text = title, ClientSize = new Size(350, 112), FormBorderStyle = FormBorderStyle.FixedDialog, StartPosition = FormStartPosition.CenterParent, BackColor = Color.FromArgb(34, 37, 32), ForeColor = Color.White };
        var t = new TextBox { Text = value, Location = new Point(16, 20), Width = 315, BackColor = Color.FromArgb(25, 28, 24), ForeColor = Color.White, BorderStyle = BorderStyle.FixedSingle };
        var ok = new Button { Text = "Save", DialogResult = DialogResult.OK, Location = new Point(232, 62), Width = 96 };
        d.Controls.Add(t); d.Controls.Add(ok); d.AcceptButton = ok;
        return d.ShowDialog(this) == DialogResult.OK ? t.Text : null;
    }

    void ShowFeed()
    {
        var menu = new ContextMenuStrip { BackColor = Color.FromArgb(39, 43, 37), ForeColor = Color.White };
        foreach (var prey in new[] { PreyKind.Cricket, PreyKind.Moth, PreyKind.Beetle, PreyKind.Ant })
            menu.Items.Add("A " + prey.ToString().ToLowerInvariant(), null, (_, _) =>
            {
                _app.Spider.ReleasePrey(prey, _view.CenterWorld + new V2(0, 60));
                _view.Invalidate();
            });
        menu.Items.Add(new ToolStripSeparator());
        var wild = _app.Settings.GetBool("tankWildlife", true);
        menu.Items.Add((wild ? "✓ " : "") + "Creatures Find Their Own Way In", null, (_, _) =>
        {
            _app.Settings.SetBool("tankWildlife", !wild); _app.Settings.Save();
        });
        menu.Show(_view, _view.Width - 260, 4);
    }

    void ShowWeather()
    {
        var menu = new ContextMenuStrip { BackColor = Color.FromArgb(39, 43, 37), ForeColor = Color.White };
        var now = menu.Items.Add(_weather.Summary(WeatherClock.Now)); now.Enabled = false;
        menu.Items.Add(new ToolStripSeparator());
        foreach (var kind in WeatherKinds.All)
        {
            bool always = _weather.Settings.Mode == WeatherMode.Always && _weather.Settings.Always == kind;
            menu.Items.Add((always ? "✓ " : "") + kind.Label(), null, (_, _) => { _weather.Settings.Mode = WeatherMode.Always; _weather.Settings.Always = kind; _weather.Force(kind); Save(); });
        }
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Bring Weather", null, (_, _) => { _weather.Bring(_weather.Settings.Always); Save(); });
        menu.Items.Add("Something Else", null, (_, _) => { _weather.ChangeNow(); Save(); });
        menu.Items.Add("Clear the Sky", null, (_, _) => { _weather.Force(WeatherKind.Clear); Save(); });
        menu.Items.Add("Let the Scenery Decide", null, (_, _) => { _weather.Settings.Mode = WeatherMode.Changing; _weather.Settle(WeatherClock.Now, true); Save(); });
        menu.Items.Add("Like Outside", null, (_, _) => { _weather.Settings.Mode = WeatherMode.Outside; _weather.Settle(WeatherClock.Now, true); Save(); });
        menu.Show(_view, _view.Width - 250, 4);
    }

    void ToggleDecorate()
    {
        bool entering = !_decorating;
        if (entering)
        {
            bool shut = false;
            foreach (var item in _world.Items)
            {
                if (item.Kind == HabitatItemKind.Door) { item.Kind = HabitatItemKind.DoorClosed; shut = true; }
                else if (item.Kind == HabitatItemKind.WindowOpen) { item.Kind = HabitatItemKind.Window; shut = true; }
            }
            if (shut) Rebuild();
        }
        _decorating = entering;
        _panel.Visible = _decorating;
        _view.Decorating = _decorating;
        _decorateButton.Text = _decorating ? (Width < 960 ? "✓" : "Done") : (Width < 960 ? "✎" : "Decorate");
        _decorateButton.BackColor = _decorating ? Color.FromArgb(154, 119, 66) : Color.FromArgb(48, 52, 46);
        if (_decorating)
        {
            _view.CameraModeFree(); _panel.ShowTab("add"); _panel.RefreshList(); _panel.RefreshHabitats();
            if (!_decorTourShown && !TourSuppressed && !_app.Settings.GetBool(HabitatTourOverlay.DecoratingSeenKey, false))
            {
                _decorTourShown = true;
                BeginInvoke(() => ShowTour());
            }
        }
        else _view.CameraFollow();
        _view.Invalidate();
    }

    public void Save()
    {
        try { _app.SaveHabitat(_world, _view.CameraOrigin); } catch { }
    }

    public void AddItem(HabitatItemKind kind)
    {
        PushUndo();
        var at = _view.CenterWorld;
        var item = _world.AddAt(kind, at);
        _world.Clamp(item);
        Rebuild();
        _view.Select(item);
        Save();
    }

    public void DeleteSelected()
    {
        if (_view.Selected is not { } item) return;
        PushUndo();
        _world.Remove(item);
        _view.Select(null);
        Rebuild();
        Save();
    }

    public void TourAgain() => ShowTour();

    internal void SetWeatherForTest(WeatherKind kind)
    {
        _weather.Force(kind);
        Save();
    }

    void ShowTour()
    {
        _view.CommitEdit();
        using var tour = new HabitatTourOverlay(this, _decorating);
        tour.ShowDialog(this);
        _app.Settings.SetBool(_decorating ? HabitatTourOverlay.DecoratingSeenKey : HabitatTourOverlay.SeenKey, true);
        _app.Settings.Save();
        _view.Focus();
    }

    public Rectangle TourTarget(string which)
    {
        Control? c = which switch
        {
            "map" => _mapButton, "feed" => _feedButton, "weather" => _weatherButton,
            "decorate" => _decorateButton, "help" => _helpButton, "letout" => _letOutButton,
            "glass" => _view, _ => null
        };
        if (c is not null && c.Visible) return c.RectangleToScreen(c.ClientRectangle);
        if (_decorating && which is "add" or "scenery" or "habitats") return _panel.TargetRect(which);
        if (_decorating && which == "inspector") return _view.RectangleToScreen(new Rectangle(_view.Width - 270, _view.Height - 96, 258, 80));
        if (_decorating && which == "undo") return _panel.RectangleToScreen(new Rectangle(10, _panel.Height - 120, _panel.Width - 20, 30));
        return Rectangle.Empty;
    }

    void ShowMap()
    {
        using var map = new HabitatMap(this, _world, _view.CameraOrigin, _app.Spider.Pos, _view.CameraSize, _view.Selected,
            _app.Spider.PreyItems.Where(p => p.State == PreyState.Loose).Select(p => p.Pos).ToList());
        if (map.ShowDialog(this) != DialogResult.OK) return;
        if (map.Moved is { } item && map.MovedTo is { } to)
        {
            item.X = to.X; item.Y = to.Y; _world.Clamp(item); Rebuild(); Save();
        }
        else if (map.Chosen is { } p) _view.GlideTo(p);
    }

    public void NewWorld(HabitatBiome biome, bool surprise)
    {
        if (MessageBox.Show(this, "Replace this tank with a new one? Your current layout is kept in My Habitats.", "New Habitat", MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK) return;
        PushUndo();
        _world = surprise ? HabitatWorld.Surprise(_world.Bounds, biome) : HabitatWorld.Preset(biome, _world.Bounds);
        _name.Text = _world.Name;
        _currentSaveId = null; _app.Settings.Remove("habitatCurrentSave");
        _map = _world.BuildMap(_app.Spider.Scale);
        _app.Spider.SetMap(_map); _app.Spider.SetAnchor("", 0, 0, 1);
        _view.SetWorld(_world, _map);
        _view.SetCameraToSpider();
        Rebuild();
        Save();
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        if (keyData == (Keys.Control | Keys.Z)) { Undo(); return true; }
        if (keyData == (Keys.Control | Keys.Shift | Keys.Z) || keyData == (Keys.Control | Keys.Y)) { Redo(); return true; }
        if (keyData == (Keys.Control | Keys.D) && _decorating) { _view.DuplicateSelected(); return true; }
        if (keyData == Keys.Escape && _decorating)
        {
            if (_view.Selected is not null) { _view.Select(null); _view.Invalidate(); }
            else ToggleDecorate();
            return true;
        }
        if (keyData == Keys.Delete && _decorating) { DeleteSelected(); return true; }
        return base.ProcessCmdKey(ref msg, keyData);
    }
}

public sealed class HabitatView : SKGLControl
{
    readonly HabitatWindow _window;
    readonly SpiderApplicationContext _app;
    HabitatWorld _world;
    SurfaceMap _map;
    readonly HabitatCamera _camera = new();
    bool _draggingGlass, _draggingItem, _resizing;
    Point _dragStart;
    V2 _cameraStart, _grabOffset, _resizeGrab;
    Rect _resizeStartRect;
    double _lastMouse = Environment.TickCount64;
    long _freeUntil;
    double _arrivalClock = 8, _releaseClock, _trackClock;
    readonly List<(V2 at, double age, bool snow)> _tracks = new();
    HabitatItem? _selected;
    string _hint = "";
    public bool Decorating;
    public bool ShowGeometry = Environment.GetEnvironmentVariable("SPIDER_HABITAT_GEOMETRY") == "1";
    readonly List<HabitatParticle> _particles = new();
    double _particleClock, _frameDt = 1.0 / 30;
    double _shake;
    WeatherConditions _paintWeather = new();

    public HabitatView(HabitatWindow window, SpiderApplicationContext app, HabitatWorld world, SurfaceMap map)
    {
        _window = window; _app = app; _world = world; _map = map;
        SetStyle(ControlStyles.ResizeRedraw, true);
        BackColor = Color.FromArgb(20, 23, 20);
        _camera.SetWorld(new SizeD(world.Bounds.W, world.Bounds.H));
        _camera.SetView(new SizeD(Width, Height));
    }

    public V2 CameraOrigin => _camera.Origin;
    public SizeD CameraSize => _camera.View;
    public V2 CenterWorld => new(_camera.Origin.X + Width / 2.0, _camera.Origin.Y + Height / 2.0);
    public HabitatItem? Selected => _selected;

    public void SetWorld(HabitatWorld world, SurfaceMap map)
    {
        _world = world; _map = map; _selected = null;
        _camera.SetWorld(new SizeD(world.Bounds.W, world.Bounds.H));
        _camera.Jump(_camera.Origin);
        _tracks.Clear();
        SceneChanged();
    }
    public void SetCameraToSpider()
    {
        _camera.SetView(new SizeD(Width, Height));
        _camera.Jump(_camera.Centring(_app.Spider.Pos));
    }
    public void SetCamera(V2 origin)
    {
        _camera.SetView(new SizeD(Width, Height));
        _camera.Jump(origin);
    }
    public void GlideTo(V2 p) => _camera.Glide(p, false);

    public void CommitEdit()
    {
        if (!_draggingItem && !_resizing) return;
        _draggingItem = false; _resizing = false; Capture = false;
        _window.Rebuild(); _window.Save(); Invalidate();
    }

    public void DuplicateSelected()
    {
        if (_selected is not { } item) return;
        _window.PushUndo();
        var c = item.Clone(); c.Id = _window.World.NextId++;
        c.Uid = Guid.NewGuid().ToString("D"); c.X += 24; if (item.Hangs) c.Y += 24;
        _window.World.Items.Add(c); _window.Rebuild(); _window.Save(); Select(c); Invalidate();
    }
    public void CameraModeFree() { _camera.BeginPan(); _camera.Touch(); }
    public void CameraFollow() { _camera.Glide(_app.Spider.Pos, true); }
    public void Select(HabitatItem? item) { _selected = item; SceneChanged(); }

    static readonly bool ProfileTick = Environment.GetEnvironmentVariable("SPIDER_HABITAT_PROFILE") == "1";
    double _tickProfileAt;

    public void Tick(double dt)
    {
        if (Width < 2 || Height < 2) return;
        var sw = ProfileTick ? System.Diagnostics.Stopwatch.StartNew() : null;
        _frameDt = dt;
        _camera.SetView(new SizeD(Width, Height));
        if (_app.Spider.InHabitat) _app.Spider.Update(dt);
        double tSpider = sw?.Elapsed.TotalMilliseconds ?? 0;
        var conditions = _window.Weather.Conditions(WeatherClock.Now, _camera.Clock);
        _window.Mind.Update(dt, _app.Spider, conditions, _window.Knowledge, _app.Spider.Scale);
        _window.Ecology.Update(dt, conditions, _app.Spider.Scale);
        LiveEcology(dt, conditions);
        LiveTracks(dt, conditions);
        double tMind = sw?.Elapsed.TotalMilliseconds ?? 0;
        _camera.Update(dt, _app.Spider.Pos, !Decorating);
        foreach (var it in _world.Items)
            if (it.Kind.Traits().Loose is { } lb)
            {
                // loose bodies lean and drift in wind, never leave their painted place entirely
                double wind = conditions.WindNow;
                double dx = wind * lb.WindCatch * Math.Sin(_camera.Clock * .7 + it.Seed);
                it.X += dx * dt * .18;
                it.Y += Math.Abs(dx) * dt * .03;
                _world.Clamp(it);
            }
        if (_selected is not null) _hint = _selected.Kind.Label() + "  ·  " + _selected.Kind.Traits().Material;
        spawn(dt);
        _shake = Math.Max(0, _shake - dt * 2);
        if (sw is not null && _camera.Clock - _tickProfileAt > 1)
        {
            _tickProfileAt = _camera.Clock;
            Program.SmokeLog($"tick: spider {tSpider:0.0} mind+eco {tMind - tSpider:0.0} rest {sw.Elapsed.TotalMilliseconds - tMind:0.0} ms");
        }
    }

    void LiveTracks(double dt, WeatherConditions weather)
    {
        for (int i = _tracks.Count - 1; i >= 0; i--)
        {
            var t = _tracks[i];
            t.age -= dt;
            if (t.age <= 0) _tracks.RemoveAt(i); else _tracks[i] = t;
        }
        _trackClock -= dt;
        if (_trackClock > 0) return;
        _trackClock = .16;
        bool snow = weather.Mix.Snow > .25;
        if (!snow && !(weather.Mix.Rain > .2 && _window.Mind.Wet > .15)) return;
        if (_app.Spider.Speed < 8 || _app.Spider.Mode != Mode.Attached) return;
        if (_tracks.Count < 140) _tracks.Add((_app.Spider.Pos + new V2(0, -2), snow ? 22 : 9, snow));
    }

    void LiveEcology(double dt, WeatherConditions weather)
    {
        bool wildlife = _window.WindowSettings.GetBool("tankWildlife", true);
        if (wildlife)
        {
            _arrivalClock -= dt;
            if (_arrivalClock <= 0)
            {
                _arrivalClock = Math.Max(9, _window.Ecology.ArrivalGap(weather));
                if (_window.Mind.Survey is not null) _window.Ecology.AddArrival();
            }
        }
        else _arrivalClock = 6;
        _releaseClock += dt;
        if (_releaseClock >= 1.2)
        {
            _releaseClock = 0;
            foreach (var arrival in _window.Ecology.Arrivals.Where(a => !a.Landed).Take(2).ToList())
            {
                arrival.Landed = true;
                var prey = _app.Spider.ReleasePrey(arrival.Kind, arrival.Spot.Point);
                if (prey is not null) { prey.Pos = arrival.Spot.Point; prey.OnSurface = !Prey.Info(arrival.Kind).Flies; }
                _window.Knowledge.Place("eco:" + arrival.Kind).Sightings++;
            }
            _window.Ecology.Arrivals.RemoveAll(a => a.Landed);
        }
    }

    void spawn(double dt)
    {
        var c = _window.Weather.Conditions(WeatherClock.Now, _camera.Clock);
        _particleClock += dt;
        if (_particleClock < .03) return;
        _particleClock = 0;
        int n = c.Mix.Rain > .1 ? (int)(14 * c.Mix.Rain) : c.Mix.Hail > .1 ? (int)(11 * c.Mix.Hail) : c.Mix.Snow > .1 ? (int)(8 * c.Mix.Snow) : c.Mix.Sand > .1 ? 4 : 0;
        for (int i = 0; i < n && _particles.Count < 190; i++)
            _particles.Add(new HabitatParticle
            {
                X = _camera.Origin.X + Random.Shared.NextDouble() * Width,
                Y = _camera.Origin.Y + Height + 8,
                Vx = c.WindNow * 18, Vy = -300 - Random.Shared.NextDouble() * 160,
                Life = 1.2 + Random.Shared.NextDouble(), Kind = c.Mix.Hail > .1 ? 3 : c.Mix.Snow > .1 ? 1 : c.Mix.Sand > .1 ? 2 : 0
            });
        if (c.Mix.Lightning > .6 && Random.Shared.NextDouble() < .006) { _shake = 1; _flash = .5; }
        _flash = Math.Max(0, _flash - dt * 1.7);
    }
    double _flash;

    protected override void OnMouseDown(MouseEventArgs e)
    {
        Focus();
        var p = WorldAt(e.Location);
        if (e.Button == MouseButtons.Right && Decorating) { Select(null); Invalidate(); return; }
        if (e.Button != MouseButtons.Left) return;
        if (Decorating)
        {
            if (_selected is { } chosen && NearResizeHandle(chosen, p))
            {
                _window.PushUndo();
                _resizing = true; _resizeStartRect = chosen.Rect; _resizeGrab = p;
                Capture = true; Invalidate(); return;
            }
            var hit = Hit(p);
            if (hit is not null)
            {
                _window.PushUndo();
                Select(hit);
                _draggingItem = true;
                _grabOffset = new V2(p.X - hit.X, p.Y - (hit.Hangs ? hit.Y - hit.H : hit.Y));
                Capture = true;
                Invalidate();
                return;
            }
        }
        _draggingGlass = true; _dragStart = e.Location; _cameraStart = _camera.Origin;
        _camera.BeginPan(); Capture = true;
        if (!Decorating) _camera.Touch();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (_resizing && _selected is not null)
        {
            var p = WorldAt(e.Location);
            double dw = p.X - _resizeGrab.X, dh = p.Y - _resizeGrab.Y;
            _selected.W = Math.Max(12, _resizeStartRect.W + dw);
            _selected.H = Math.Max(12, _resizeStartRect.H + (e.Button == MouseButtons.Left ? -dh : dh));
            _window.World.Clamp(_selected);
            Invalidate(); return;
        }
        if (_draggingItem && _selected is not null)
        {
            var p = WorldAt(e.Location);
            if (_selected.Hangs)
            {
                _selected.Y = p.Y + _grabOffset.Y;
            }
            else
            {
                _selected.X = p.X - _grabOffset.X;
                _selected.Y = Math.Max(0, p.Y - _grabOffset.Y);
            }
            _world.Clamp(_selected);
            Invalidate();
            // dragging to the glass edge takes the view along
            if (e.X < 24) _camera.Pan(new V2(-8, 0));
            else if (e.X > Width - 24) _camera.Pan(new V2(8, 0));
            else if (e.Y < 24) _camera.Pan(new V2(0, 8));
            else if (e.Y > Height - 24) _camera.Pan(new V2(0, -8));
            return;
        }
        if (_draggingGlass)
        {
            var d = new V2(e.X - _dragStart.X, -(e.Y - _dragStart.Y));
            _camera.Pan(d);
            Invalidate();
        }
        else if (Decorating) _hint = Hit(WorldAt(e.Location))?.Kind.Label() ?? "";
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        if (_draggingItem || _resizing)
        {
            _draggingItem = false; _resizing = false; Capture = false;
            _window.Rebuild(); _window.Save(); Invalidate(); return;
        }
        if (!_draggingGlass) return;
        _draggingGlass = false; Capture = false;
        _camera.EndPan(new V2(0, 0));
        _freeUntil = Environment.TickCount64 + 1000;
    }

    protected override void OnMouseDoubleClick(MouseEventArgs e)
    {
        if (!Decorating) return;
        var item = Hit(WorldAt(e.Location));
        if (item is null) return;
        Select(item);
        _window.PushUndo();
        using var inspector = new HabitatInspector(_window, item);
        inspector.ShowDialog(FindForm());
        _window.Rebuild(); _window.Save(); Invalidate();
    }

    protected override void OnMouseWheel(MouseEventArgs e)
    {
        if (Decorating && _selected is not null && (ModifierKeys & Keys.Shift) != 0)
        {
            _window.PushUndo();
            double k = e.Delta > 0 ? 1.07 : .935;
            _selected.W = Math.Max(12, _selected.W * k);
            _selected.H = Math.Max(12, _selected.H * k);
            _world.Clamp(_selected); _window.Rebuild(); _window.Save(); Invalidate();
            return;
        }
        _camera.Pan(new V2(-e.Delta * .55, 0));
        Invalidate();
    }

    protected override bool IsInputKey(Keys keyData) => keyData is Keys.Left or Keys.Right or Keys.Up or Keys.Down || base.IsInputKey(keyData);
    protected override void OnKeyDown(KeyEventArgs e)
    {
        double step = (ModifierKeys & Keys.Shift) != 0 ? 90 : 26;
        if (e.KeyCode == Keys.Left) _camera.Pan(new V2(-step, 0));
        else if (e.KeyCode == Keys.Right) _camera.Pan(new V2(step, 0));
        else if (e.KeyCode == Keys.Up) _camera.Pan(new V2(0, step));
        else if (e.KeyCode == Keys.Down) _camera.Pan(new V2(0, -step));
        else if (e.KeyCode == Keys.F) _camera.Glide(_app.Spider.Pos, true);
        else if (e.KeyCode == Keys.G) ShowGeometry = !ShowGeometry;
        else return;
        Invalidate();
        e.Handled = true;
    }

    protected override void OnResize(EventArgs e) { base.OnResize(e); _camera.SetView(new SizeD(Width, Height)); }

    V2 WorldAt(Point p) => new(_camera.Origin.X + p.X, _camera.Origin.Y + Height - p.Y);
    PointF P(double x, double y) => new((float)(x - _camera.Origin.X), (float)(Height - (y - _camera.Origin.Y)));

    bool NearResizeHandle(HabitatItem item, V2 p)
    {
        double r = 15 / Math.Max(.3, _app.Spider.Scale);
        return item.Rect.BottomRight.DistanceTo(p) < r || item.Rect.BottomLeft.DistanceTo(p) < r;
    }

    HabitatItem? Hit(V2 p)
    {
        foreach (var it in _world.Items.OrderByDescending(i => i.InFront).ThenByDescending(i => i.Id))
        {
            var r = it.Rect.Inset(-8, -8);
            if (r.Contains(p)) return it;
            if (it.Kind.IsBacking() && it.Rect.Contains(p)) return it;
        }
        return null;
    }

    Bitmap? _staticScene;
    SKImage? _staticGpu, _frontGpu;
    V2 _staticOrigin;
    WeatherKind? _staticShown;
    double _staticAt;
    bool _staticDirty = true;

    public void SceneChanged() { _staticDirty = true; Invalidate(); }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _staticScene?.Dispose();
            _staticGpu?.Dispose();
            _frontGpu?.Dispose();
        }
        base.Dispose(disposing);
    }

    static void Sketch(Graphics g)
    {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.InterpolationMode = InterpolationMode.Bilinear;
        g.PixelOffsetMode = PixelOffsetMode.HighSpeed;
        g.CompositingQuality = CompositingQuality.HighSpeed;
    }

    void BuildStaticScene(WeatherConditions conditions)
    {
        _staticScene?.Dispose();
        _staticScene = new Bitmap(Math.Max(1, Width), Math.Max(1, Height), PixelFormat.Format32bppPArgb);
        using (var sg = Graphics.FromImage(_staticScene))
        {
            Sketch(sg);
            DrawBackdrop(sg, conditions);
            DrawScenery(sg, conditions);
            DrawGround(sg);
            foreach (var item in _world.Items.Where(i => i.Kind.AtBack()).OrderBy(i => i.Id)) DrawItem(sg, item);
            foreach (var item in _world.Items.Where(i => !i.Kind.AtBack() && !i.InFront).OrderBy(i => i.Id)) DrawItem(sg, item);
        }
        _staticGpu?.Dispose();
        _staticGpu = ToGpu(_staticScene);

        using var front = new Bitmap(Math.Max(1, Width), Math.Max(1, Height), PixelFormat.Format32bppPArgb);
        using (var fg = Graphics.FromImage(front))
        {
            Sketch(fg);
            foreach (var item in _world.Items.Where(i => i.InFront).OrderBy(i => i.Id)) DrawItem(fg, item);
        }
        _frontGpu?.Dispose();
        _frontGpu = ToGpu(front);

        _staticOrigin = _camera.Origin;
        _staticAt = _camera.Clock;
        _staticShown = conditions.Shown;
        _staticDirty = false;
    }

    static SKImage ToGpu(Bitmap bmp)
    {
        var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
        try
        {
            var info = new SKImageInfo(bmp.Width, bmp.Height, SKColorType.Bgra8888, SKAlphaType.Premul);
            return SKImage.FromPixelCopy(info, data.Scan0, data.Stride);
        }
        finally { bmp.UnlockBits(data); }
    }

    static readonly bool ProfilePaint = Environment.GetEnvironmentVariable("SPIDER_HABITAT_PROFILE") == "1";
    double _profileAt;

    SKPoint S(double x, double y) => new((float)(x - _camera.Origin.X), (float)(Height - (y - _camera.Origin.Y)));
    static SKColor C(Color c) => new(c.R, c.G, c.B, c.A);
    SKRect SRect(Rect r) { var p = S(r.MinX, r.MaxY); return new SKRect(p.X, p.Y, p.X + (float)r.W, p.Y + (float)r.H); }

    protected override void OnPaintSurface(SKPaintGLSurfaceEventArgs e)
    {
        base.OnPaintSurface(e);
        var sw = ProfilePaint ? System.Diagnostics.Stopwatch.StartNew() : null;
        var canvas = e.Surface.Canvas;
        canvas.ResetMatrix();
        float scaleX = e.BackendRenderTarget.Width / (float)Math.Max(1, Width);
        float scaleY = e.BackendRenderTarget.Height / (float)Math.Max(1, Height);
        canvas.Clear(new SKColor(20, 23, 20));
        canvas.Scale(scaleX, scaleY);
        canvas.Save();
        var conditions = _paintWeather = _window.Weather.Conditions(WeatherClock.Now, _camera.Clock);
        var shift = _shake > 0 ? new V2(Math.Sin(_camera.Clock * 90) * _shake * 4, Math.Cos(_camera.Clock * 77) * _shake * 2) : V2.Zero;
        canvas.Translate((float)shift.X, (float)shift.Y);

        bool canCache = !Decorating && !ShowGeometry && _shake <= .01;
        bool needsStatic = !canCache || _staticGpu is null || _staticDirty ||
            _staticScene?.Width != Width || _staticScene?.Height != Height ||
            _staticShown != conditions.Shown || _camera.Clock - _staticAt > 2.0 ||
            _staticOrigin.DistanceTo(_camera.Origin) > Math.Max(Width, Height) * .7;
        if (needsStatic) BuildStaticScene(conditions);
        double tScene = sw?.Elapsed.TotalMilliseconds ?? 0;

        float dx = (float)(_staticOrigin.X - _camera.Origin.X);
        float dy = (float)(_camera.Origin.Y - _staticOrigin.Y);
        if (_staticGpu is not null) canvas.DrawImage(_staticGpu, dx, dy, SKSamplingOptions.Default, null);
        DrawSpiderSk(canvas);
        if (_frontGpu is not null) canvas.DrawImage(_frontGpu, dx, dy, SKSamplingOptions.Default, null);
        double tSpider = sw?.Elapsed.TotalMilliseconds ?? 0;
        DrawWeatherSk(canvas, conditions);
        DrawEcologySk(canvas, conditions);
        DrawParticlesSk(canvas);
        double tWeather = sw?.Elapsed.TotalMilliseconds ?? 0;
        if (_selected is not null) DrawSelectionSk(canvas, _selected);
        if (ShowGeometry) DrawGeometrySk(canvas);
        DrawGlassSk(canvas);
        if (_flash > 0)
            using (var b = new SKPaint { Color = new SKColor(245, 247, 255, (byte)Math.Clamp((int)(_flash * 120), 0, 255)) })
                canvas.DrawRect(0, 0, Width, Height, b);
        DrawHintSk(canvas);
        canvas.Restore();
        SaveGpuShot(e.Surface, canvas);
        if (sw is not null && _camera.Clock - _profileAt > 1)
        {
            _profileAt = _camera.Clock;
            Program.SmokeLog($"gpu paint: scene {tScene:0.0} spider {tSpider - tScene:0.0} weather {tWeather - tSpider:0.0} finish {sw.Elapsed.TotalMilliseconds - tWeather:0.0} ms");
        }
    }

    bool _shotSaved;
    void SaveGpuShot(SKSurface surface, SKCanvas canvas)
    {
        if (_shotSaved) return;
        string? path = Environment.GetEnvironmentVariable("SPIDER_HABITAT_SHOT");
        if (string.IsNullOrWhiteSpace(path)) return;
        try
        {
            canvas.Flush();
            using var image = surface.Snapshot();
            using var png = image.Encode(SKEncodedImageFormat.Png, 94);
            string? folder = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(folder)) Directory.CreateDirectory(folder);
            File.WriteAllBytes(path, png.ToArray());
            _shotSaved = true;
            Program.SmokeLog("gpu shot: " + path);
        }
        catch (Exception ex) { Program.SmokeLog("gpu shot failed: " + ex.Message); }
    }

    void DrawSpiderSk(SKCanvas canvas)
    {
        try
        {
            var pose = _app.Spider.BuildPose();
            var center = S(pose.Pos.X, pose.Pos.Y);
            canvas.Save();
            canvas.Translate(center.X, center.Y);
            canvas.Scale(1, -1);
            var local = pose.Clone();
            local.Pos = V2.Zero;
            local.Scale = _app.Spider.Scale;
            SpiderRenderer.Draw(new SkiaDraw(canvas), local, _app.Spider.Design.Look, drawNameTag: false);
            canvas.Restore();
            double wet = _window.Mind.Wet;
            if (wet > .15)
            {
                using var sheen = new SKPaint { Color = new SKColor(202, 229, 234, (byte)Math.Clamp(40 + wet * 85, 0, 255)), IsAntialias = true };
                double side = SpriteRaster.SpriteSide(_app.Spider.Scale);
                for (int i = 0; i < 5; i++)
                {
                    float ax = center.X + (float)(side * (.24 + .13 * ((i * 37) % 7)));
                    float ay = center.Y + (float)(side * (.18 + .12 * ((i * 53) % 6)));
                    canvas.DrawCircle(ax, ay, 1.3f, sheen);
                }
            }
        }
        catch { }
    }

    void DrawWeatherSk(SKCanvas canvas, WeatherConditions c)
    {
        int alpha = (int)((c.Mix.Dark * 90) + (c.Mix.Storm * 50));
        if (c.Mix.Fog > .04)
            using (var fog = new SKPaint { Color = new SKColor(226, 233, 227, (byte)Math.Clamp((int)(c.Mix.Fog * 36), 0, 255)) })
                canvas.DrawRect(0, 0, Width, Height, fog);
        if (alpha > 0)
            using (var shade = new SKPaint { Color = new SKColor(15, 24, 27, (byte)Math.Clamp(alpha, 0, 255)) })
                canvas.DrawRect(0, 0, Width, Height, shade);
        if (c.Mix.Cloud > .05)
        {
            using var cloud = new SKPaint { Color = new SKColor(225, 227, 216, (byte)Math.Clamp((int)(c.Mix.Cloud * 50), 0, 255)), IsAntialias = false };
            for (int i = 0; i < 8; i++)
            {
                float x = (float)((i * 340 - _camera.Clock * 9) % (Width + 500)) - 200;
                canvas.DrawOval(new SKRect(x, 30 + (i % 3) * 36, x + 390, 30 + (i % 3) * 36 + 66), cloud);
            }
        }
    }

    void DrawEcologySk(SKCanvas canvas, WeatherConditions c)
    {
        var eco = _window.Ecology;
        using var bead = new SKPaint { Color = new SKColor(190, 225, 231, 165), IsAntialias = true };
        using var shine = new SKPaint { Color = new SKColor(250, 255, 255, 190), IsAntialias = true };
        foreach (var d in eco.Drops)
        {
            if (!OnGlass(d.Point, 30)) continue;
            var p = S(d.Point.X, d.Point.Y);
            float r = (float)Math.Max(1, d.Size * 2.2);
            canvas.DrawCircle(p.X, p.Y, r, bead);
            canvas.DrawCircle(p.X - r * .15f, p.Y - r * .15f, Math.Max(.6f, r * .3f), shine);
        }
        using var shell = new SKPaint { Color = new SKColor(74, 59, 40, 160), Style = SKPaintStyle.Stroke, StrokeWidth = 1.4f, IsAntialias = true };
        foreach (var remains in eco.Remains)
        {
            if (!OnGlass(remains.Point, 20)) continue;
            var p = S(remains.Point.X, remains.Point.Y);
            canvas.DrawOval(new SKRect(p.X - 3, p.Y - 1.5f, p.X + 3, p.Y + 1.5f), shell);
            canvas.DrawLine(p.X - 3, p.Y, p.X + 4, p.Y - 1, shell);
        }
        foreach (var arrival in eco.Arrivals)
        {
            var p = S(arrival.Patch.X, arrival.Patch.Y);
            var col = arrival.Kind switch
            {
                PreyKind.Moth => new SKColor(224, 216, 188, 205),
                PreyKind.Beetle => new SKColor(58, 48, 38, 230),
                PreyKind.Ladybug => new SKColor(176, 55, 44, 230),
                PreyKind.Worm => new SKColor(183, 143, 142, 220),
                PreyKind.Ant => new SKColor(48, 34, 29, 220),
                PreyKind.Mosquito => new SKColor(83, 74, 60, 200),
                PreyKind.Cricket => new SKColor(98, 125, 58, 220),
                _ => new SKColor(170, 140, 70, 210)
            };
            using var body = new SKPaint { Color = col, IsAntialias = true };
            float wing = (float)(3 + Math.Sin(_camera.Clock * 18) * 2);
            if (Prey.Info(arrival.Kind).Flies)
                using (var w = new SKPaint { Color = new SKColor(236, 235, 220, 90), IsAntialias = true })
                    canvas.DrawOval(new SKRect(p.X - 5, p.Y - wing, p.X + 4, p.Y + 1), w);
            canvas.DrawOval(new SKRect(p.X - 2.5f, p.Y - 2, p.X + 2.5f, p.Y + 2), body);
        }
        using var snowPrint = new SKPaint { Color = new SKColor(118, 128, 132, 94), IsAntialias = true };
        using var wetPrint = new SKPaint { Color = new SKColor(39, 48, 42, 64), IsAntialias = true };
        foreach (var track in _tracks)
        {
            if (!OnGlass(track.at, 20)) continue;
            var tp = S(track.at.X, track.at.Y);
            canvas.DrawOval(new SKRect(tp.X - 2.6f, tp.Y - 1, tp.X + 2.6f, tp.Y + 1.2f), track.snow ? snowPrint : wetPrint);
        }
        if (c.Mix.Snow > .12)
        {
            using var cap = new SKPaint { Color = new SKColor(244, 249, 250, (byte)Math.Clamp((int)(130 + c.Mix.Snow * 110), 0, 255)), Style = SKPaintStyle.Stroke, StrokeWidth = 2.2f, IsAntialias = true };
            foreach (var item in _world.Items.Where(i => !i.InFront && PlaceSurvey.Counts(i)))
            {
                if (!OnGlass(item.Rect.Mid, 200)) continue;
                foreach (var part in HabitatGeometry.For(item).Visual)
                    for (int i = 0; i + 1 < part.Count; i++)
                    {
                        var a = part[i]; var b = part[i + 1];
                        if (Math.Abs(a.Y - b.Y) > 3 || a.Y < item.Rect.Mid.Y) continue;
                        var mid = V2.Lerp(a, b, .5);
                        if (eco.Sky.OpenAt(mid) < .45) continue;
                        var pa = S(a.X, a.Y); var pb = S(b.X, b.Y);
                        canvas.DrawLine(pa.X, pa.Y - 1, pb.X, pb.Y - 1, cap);
                    }
            }
        }
        if (c.Mix.Rain > .08 && _window.Mind.Survey is { } survey)
        {
            using var ring = new SKPaint { Color = new SKColor(220, 239, 239, 100), Style = SKPaintStyle.Stroke, StrokeWidth = 1, IsAntialias = true };
            foreach (var water in survey.Water)
            {
                if (eco.Sky.OpenAt(water.Surface.Mid) < .4) continue;
                var p = S(water.Surface.Mid.X, water.Surface.MinY);
                double phase = (_camera.Clock * 1.7 + water.Id) % 1;
                canvas.DrawOval(new SKRect(p.X - (float)(phase * 16), p.Y - (float)(phase * 5), p.X + (float)(phase * 16), p.Y + (float)(phase * 5)), ring);
            }
        }
    }

    void DrawParticlesSk(SKCanvas canvas)
    {
        using var rain = new SKPaint { Color = new SKColor(203, 225, 233, 130), Style = SKPaintStyle.Stroke, StrokeWidth = 1, IsAntialias = true };
        using var snow = new SKPaint { Color = new SKColor(244, 248, 250, 210), IsAntialias = true };
        using var hail = new SKPaint { Color = new SKColor(241, 247, 249, 225), IsAntialias = true };
        using var sand = new SKPaint { Color = new SKColor(210, 181, 121, 95), IsAntialias = true };
        double dt = Math.Clamp(_frameDt, .01, .08);
        for (int i = _particles.Count - 1; i >= 0; i--)
        {
            var p = _particles[i]; p.X += p.Vx * dt; p.Y += p.Vy * dt; p.Life -= dt;
            if (p.Life <= 0 || p.Y < _camera.Origin.Y - 40) { _particles.RemoveAt(i); continue; }
            var s = S(p.X, p.Y);
            if (p.Kind == 0) canvas.DrawLine(s.X, s.Y, s.X - 3, s.Y + 12, rain);
            else if (p.Kind == 1) canvas.DrawCircle(s.X, s.Y, 1.5f, snow);
            else if (p.Kind == 3) canvas.DrawCircle(s.X, s.Y, 2f, hail);
            else canvas.DrawCircle(s.X, s.Y, 1f, sand);
        }
    }

    void DrawSelectionSk(SKCanvas canvas, HabitatItem item)
    {
        var r = SRect(item.Rect);
        using var effect = SKPathEffect.CreateDash(new[] { 5f, 4f }, 0);
        using var pen = new SKPaint { Color = new SKColor(248, 215, 144, 225), Style = SKPaintStyle.Stroke, StrokeWidth = 1.5f, PathEffect = effect, IsAntialias = true };
        canvas.DrawRect(r, pen);
        using var handle = new SKPaint { Color = new SKColor(248, 215, 144, 245), IsAntialias = true };
        canvas.DrawRect(new SKRect(r.Right - 4, r.Bottom - 4, r.Right + 4, r.Bottom + 4), handle);
    }

    void DrawGeometrySk(SKCanvas canvas)
    {
        using var part = new SKPaint { Color = new SKColor(101, 230, 211, 180), Style = SKPaintStyle.Stroke, StrokeWidth = 1, IsAntialias = true };
        using var loop = new SKPaint { Color = new SKColor(245, 183, 96, 135), Style = SKPaintStyle.Stroke, StrokeWidth = 1, IsAntialias = true };
        foreach (var it in _world.Items)
        {
            var geo = HabitatGeometry.For(it);
            foreach (var shape in geo.Parts)
            {
                using var path = new SKPath();
                for (int i = 0; i < shape.Outline.Count; i++) { var p = S(shape.Outline[i].X, shape.Outline[i].Y); if (i == 0) path.MoveTo(p); else path.LineTo(p); }
                path.Close(); canvas.DrawPath(path, part);
            }
        }
        foreach (var l in _map.AllLoops)
            foreach (var seg in l.Segs)
            {
                var a = S(seg.A.X, seg.A.Y); var b = S(seg.B.X, seg.B.Y);
                canvas.DrawLine(a, b, loop);
            }
    }

    void DrawGlassSk(SKCanvas canvas)
    {
        using var frame = new SKPaint { Color = new SKColor(9, 12, 10, 150), Style = SKPaintStyle.Stroke, StrokeWidth = 10, IsAntialias = true };
        canvas.DrawRect(new SKRect(5, 5, Width - 5, Height - 5), frame);
        using var shine = new SKPaint { Color = new SKColor(255, 255, 255, 30), Style = SKPaintStyle.Stroke, StrokeWidth = 2, IsAntialias = true };
        canvas.DrawLine(14, 14, 14, Height - 14, shine);
        canvas.DrawLine(14, 14, Width - 14, 14, shine);
        using var edge = new SKPaint { Color = new SKColor(0, 0, 0, 34) };
        canvas.DrawRect(0, 0, Width, 13, edge); canvas.DrawRect(0, Height - 13, Width, 13, edge);
        canvas.DrawRect(0, 0, 13, Height, edge); canvas.DrawRect(Width - 13, 0, 13, Height, edge);
    }

    void DrawHintSk(SKCanvas canvas)
    {
        if (string.IsNullOrEmpty(_hint) || !Decorating) return;
        using var back = new SKPaint { Color = new SKColor(15, 18, 15, 215), IsAntialias = true };
        canvas.DrawRect(14, Height - 32, Math.Max(100, _hint.Length * 7 + 14), 22, back);
        using var typeface = SKTypeface.FromFamilyName("Segoe UI");
        using var font = new SKFont(typeface, 10);
        using var text = new SKPaint { Color = new SKColor(220, 220, 220), IsAntialias = true };
        canvas.DrawText(_hint, 21, Height - 16, SKTextAlign.Left, font, text);
    }

    void PaintGdiReference(PaintEventArgs e)
    {
        var sw = ProfilePaint ? System.Diagnostics.Stopwatch.StartNew() : null;
        var g = e.Graphics;
        Sketch(g);
        var conditions = _paintWeather = _window.Weather.Conditions(WeatherClock.Now, _camera.Clock);
        var shift = _shake > 0 ? new V2(Math.Sin(_camera.Clock * 90) * _shake * 4, Math.Cos(_camera.Clock * 77) * _shake * 2) : V2.Zero;
        g.TranslateTransform((float)shift.X, (float)shift.Y);
        double tBack = sw?.Elapsed.TotalMilliseconds ?? 0;
        bool canCache = !Decorating && !ShowGeometry && _shake <= .01;
        bool cached = canCache && _staticScene is not null && !_staticDirty &&
            _staticScene.Width == Width && _staticScene.Height == Height &&
            _staticOrigin.DistanceTo(_camera.Origin) < .6 && _camera.Clock - _staticAt < 2.0 &&
            _staticShown == conditions.Shown;
        if (cached) g.DrawImageUnscaled(_staticScene!, 0, 0);
        else
        {
            DrawBackdrop(g, conditions);
            DrawScenery(g, conditions);
            DrawGround(g);
            foreach (var item in _world.Items.Where(i => i.Kind.AtBack()).OrderBy(i => i.Id)) DrawItem(g, item);
            foreach (var item in _world.Items.Where(i => !i.Kind.AtBack() && !i.InFront).OrderBy(i => i.Id)) DrawItem(g, item);
            if (canCache) BuildStaticScene(conditions);
        }
        double tScene = sw?.Elapsed.TotalMilliseconds ?? 0;
        DrawSpider(g);
        double tSpider = sw?.Elapsed.TotalMilliseconds ?? 0;
        foreach (var item in _world.Items.Where(i => i.InFront).OrderBy(i => i.Id)) DrawItem(g, item);
        DrawWeather(g, conditions);
        DrawEcology(g, conditions);
        DrawParticles(g);
        double tWeather = sw?.Elapsed.TotalMilliseconds ?? 0;
        if (_selected is not null) DrawSelection(g, _selected);
        if (ShowGeometry) DrawGeometry(g);
        DrawGlass(g);
        if (_flash > 0) using (var b = new SolidBrush(Color.FromArgb((int)(_flash * 120), 245, 247, 255))) g.FillRectangle(b, ClientRectangle);
        if (!string.IsNullOrEmpty(_hint) && Decorating)
        {
            using var font = new Font("Segoe UI", 9); using var b = new SolidBrush(Color.FromArgb(215, 15, 18, 15));
            var size = g.MeasureString(_hint, font); g.FillRectangle(b, 14, Height - 32, size.Width + 14, 22);
            g.DrawString(_hint, font, Brushes.Gainsboro, 21, Height - 29);
        }
        g.ResetTransform();
        if (sw is not null && _camera.Clock - _profileAt > 1)
        {
            _profileAt = _camera.Clock;
            Program.SmokeLog($"paint: back {tBack:0.0} scene {tScene - tBack:0.0} spider {tSpider - tScene:0.0} weather {tWeather - tSpider:0.0} finish {sw.Elapsed.TotalMilliseconds - tWeather:0.0} ms");
        }
    }

    void DrawBackdrop(Graphics g, WeatherConditions c)
    {
        var (top, bottom) = _world.Biome switch
        {
            HabitatBiome.Jungle => (Color.FromArgb(34, 72, 55), Color.FromArgb(141, 164, 118)),
            HabitatBiome.Desert => (Color.FromArgb(214, 157, 94), Color.FromArgb(247, 217, 169)),
            HabitatBiome.Cave => (Color.FromArgb(21, 30, 29), Color.FromArgb(62, 71, 61)),
            HabitatBiome.Beach => (Color.FromArgb(102, 170, 196), Color.FromArgb(226, 220, 184)),
            HabitatBiome.Tundra => (Color.FromArgb(113, 146, 166), Color.FromArgb(211, 224, 226)),
            HabitatBiome.Moonlit => (Color.FromArgb(11, 17, 33), Color.FromArgb(37, 52, 76)),
            HabitatBiome.Meadow => (Color.FromArgb(99, 151, 183), Color.FromArgb(207, 211, 149)),
            HabitatBiome.Empty => (Color.FromArgb(44, 48, 43), Color.FromArgb(91, 95, 82)),
            _ => (Color.FromArgb(77, 121, 117), Color.FromArgb(189, 202, 164))
        };
        double dim = Math.Max(c.Mix.Dark * .55, c.Mix.Storm * .35);
        top = Shade(top, 1 - dim - c.Mix.Night * .55); bottom = Shade(bottom, 1 - dim - c.Mix.Night * .45);
        using var brush = new LinearGradientBrush(ClientRectangle, top, bottom, 90f);
        g.FillRectangle(brush, ClientRectangle);
        double sx = P(_world.Bounds.W * .72, _world.Bounds.H * .78).X, sy = P(_world.Bounds.W * .72, _world.Bounds.H * .78).Y;
        int sun = c.Mix.Night > .4 ? 0 : c.Mix.Sun > .2 ? 2 : 1;
        if (sun == 2) { using var glow = new SolidBrush(Color.FromArgb(215, 255, 229, 159)); g.FillEllipse(glow, (float)sx - 38, (float)sy - 38, 76, 76); }
        if (c.Mix.Stars > .1 || _world.Biome == HabitatBiome.Moonlit)
            using (var star = new SolidBrush(Color.FromArgb((int)(120 + c.Mix.Stars * 120), 241, 240, 209)))
                for (int i = 0; i < 70; i++) g.FillEllipse(star, (float)P((i * 227) % _world.Bounds.W, 850 + (i * 97) % (int)(_world.Bounds.H - 900)).X, (float)P((i * 227) % _world.Bounds.W, 850 + (i * 97) % (int)(_world.Bounds.H - 900)).Y, 2, 2);
        if (c.Mix.Rainbow > .1)
        {
            using var rb = new Pen(Color.FromArgb((int)(c.Mix.Rainbow * 90), 228, 193, 116), 8);
            g.DrawArc(rb, Width * .55f, Height * .08f, Width * .6f, Height * 1.1f, 180, 180);
        }
    }

    void DrawScenery(Graphics g, WeatherConditions c)
    {
        using var far = new Pen(Color.FromArgb(38, 25, 32, 25), 2);
        using var near = new Pen(Color.FromArgb(58, 23, 31, 22), 4);
        if (_world.Biome is HabitatBiome.Forest or HabitatBiome.Jungle or HabitatBiome.Meadow)
        {
            for (int i = 0; i < 18; i++)
            {
                double x = i * _world.Bounds.W / 17.0 + 30;
                double h = 280 + (i * 79) % 320;
                g.DrawLine(far, P(x, 70), P(x + 10, 70 + h));
                g.DrawLine(near, P(x + 30, 70), P(x + 18, 250));
            }
        }
        if (_world.Biome == HabitatBiome.Beach)
        {
            using var sea = new SolidBrush(Color.FromArgb(120, 73, 145, 164));
            float y = P(0, 130).Y; g.FillRectangle(sea, 0, y, Width, Height - y);
            using var foam = new Pen(Color.FromArgb(170, 225, 238, 226), 3); g.DrawLine(foam, 0, y, Width, y);
        }
        if (_world.Biome == HabitatBiome.Cave)
        {
            using var crystal = new SolidBrush(Color.FromArgb(70, 106, 191, 194));
            for (int i = 0; i < 12; i++) { var p = P(i * 360, 80); g.FillPolygon(crystal, new[] { new PointF(p.X, p.Y), new PointF(p.X + 24, p.Y - 130), new PointF(p.X + 44, p.Y) }); }
        }
    }

    void DrawGround(Graphics g)
    {
        double gy = _world.GroundY;
        float y = P(0, gy).Y;
        var c1 = _world.Biome is HabitatBiome.Desert or HabitatBiome.Beach ? Color.FromArgb(177, 139, 91) : _world.Biome == HabitatBiome.Moonlit ? Color.FromArgb(38, 47, 48) : Color.FromArgb(66, 55, 37);
        using var soil = new SolidBrush(c1); g.FillRectangle(soil, 0, y, Width, Height - y);
        using var lip = new Pen(Shade(c1, 1.4), 3); g.DrawLine(lip, 0, y, Width, y);
        using var speck = new SolidBrush(Color.FromArgb(55, 255, 240, 200));
        for (int i = 0; i < 120; i++) g.FillEllipse(speck, (i * 83) % Math.Max(1, Width), y + 8 + (i * 47) % Math.Max(1, (int)(Height - y)), 2, 2);
    }

    void DrawItem(Graphics g, HabitatItem item)
    {
        var geo = HabitatGeometry.For(item);
        var baseColor = Palette(item.Kind.Traits().Material);
        if (item == _selected) baseColor = Shade(baseColor, 1.16);
        using var fill = new SolidBrush(baseColor);
        using var edge = new Pen(Shade(baseColor, .65), Math.Max(1, (float)(1.5 * item.Unit)));
        var d = item.Kind.Definition();
        double wind = _paintWeather.WindNow;
        double sway = !Decorating && Math.Abs(wind) > .15 ? wind * (d.Sway + d.WindLean * .35) * 9 : 0;
        int index = 0;
        foreach (var shape in geo.Visual)
        {
            if (shape.Count < 3) continue;
            var pts = shape.Select(p =>
            {
                double k = item.Hangs ? (item.Rect.MaxY - p.Y) / Math.Max(20, item.H) : (p.Y - item.Rect.MinY) / Math.Max(20, item.H);
                return P(p.X + sway * Math.Sin(_camera.Clock * 1.7 + item.Seed) * Math.Clamp(k, 0, 1), p.Y);
            }).ToArray();
            g.FillPolygon(fill, pts);
            g.DrawPolygon(edge, pts);
            if (index++ % 3 == 0)
            {
                var high = Shade(baseColor, 1.26);
                using var hi = new SolidBrush(Color.FromArgb(75, high));
                var shifted = pts.Select(p => new PointF(p.X + 3, p.Y + 4)).ToArray();
                g.FillPolygon(hi, shifted);
            }
        }
        if (geo.Visual.Count == 0)
        {
            var r = Screen(item.Rect); using var fb = new SolidBrush(baseColor); g.FillRectangle(fb, r);
        }
        // anchors are visible only in the geometry overlay
        if (ShowGeometry)
        {
            using var ap = new Pen(Color.FromArgb(220, 249, 197, 87), 1);
            foreach (var a in geo.Anchors) { var p = P(a.Point.X, a.Point.Y); g.DrawEllipse(ap, p.X - 3, p.Y - 3, 6, 6); }
        }
    }

    RectangleF Screen(Rect r) { var p = P(r.MinX, r.MaxY); return new RectangleF(p.X, p.Y, (float)r.W, (float)r.H); }

    Color Palette(HabitatMaterial m) => m switch
    {
        HabitatMaterial.Wood or HabitatMaterial.Bark => Color.FromArgb(123, 84, 51),
        HabitatMaterial.Root => Color.FromArgb(105, 76, 52),
        HabitatMaterial.Driftwood => Color.FromArgb(155, 131, 101),
        HabitatMaterial.Bamboo or HabitatMaterial.Stem => Color.FromArgb(162, 169, 91),
        HabitatMaterial.Leaf => Color.FromArgb(79, 127, 65),
        HabitatMaterial.Moss => Color.FromArgb(78, 115, 61),
        HabitatMaterial.Fungus => Color.FromArgb(177, 113, 93),
        HabitatMaterial.Stone => Color.FromArgb(110, 113, 106),
        HabitatMaterial.Crystal => Color.FromArgb(101, 170, 181),
        HabitatMaterial.Sand => Color.FromArgb(191, 162, 112),
        HabitatMaterial.Soil => Color.FromArgb(95, 72, 49),
        HabitatMaterial.Water => Color.FromArgb(70, 131, 145),
        HabitatMaterial.Shell => Color.FromArgb(210, 190, 169),
        HabitatMaterial.Seed => Color.FromArgb(142, 118, 68),
        HabitatMaterial.Feather => Color.FromArgb(206, 195, 166),
        _ => Color.FromArgb(137, 116, 83)
    };

    static Color Shade(Color c, double k) => Color.FromArgb(c.A, (int)Math.Clamp(c.R * k, 0, 255), (int)Math.Clamp(c.G * k, 0, 255), (int)Math.Clamp(c.B * k, 0, 255));

    void DrawSpider(Graphics g)
    {
        try
        {
            var pose = _app.Spider.BuildPose();
            using var sk = SpriteRaster.Render(pose, _app.Spider.Design.Look, _app.Spider.Scale);
            using var bmp = BitmapFrom(sk);
            double side = SpriteRaster.SpriteSide(_app.Spider.Scale);
            var p = P(pose.Pos.X - side / 2, pose.Pos.Y + side / 2);
            g.DrawImageUnscaled(bmp, (int)Math.Round(p.X), (int)Math.Round(p.Y));
            double wet = _window.Mind.Wet;
            if (wet > .15)
            {
                using var sheen = new SolidBrush(Color.FromArgb((int)(40 + wet * 85), 202, 229, 234));
                for (int i = 0; i < 5; i++)
                {
                    double ax = p.X + side * (.24 + .13 * ((i * 37) % 7));
                    double ay = p.Y + side * (.18 + .12 * ((i * 53) % 6));
                    g.FillEllipse(sheen, (float)ax, (float)ay, 2.6f, 2.6f);
                }
            }
        }
        catch { }
    }

    void DrawWeather(Graphics g, WeatherConditions c)
    {
        int alpha = (int)((c.Mix.Dark * 90) + (c.Mix.Storm * 50));
        if (c.Mix.Fog > .04)
        {
            using var fog = new SolidBrush(Color.FromArgb((int)(c.Mix.Fog * 36), 226, 233, 227));
            g.FillRectangle(fog, ClientRectangle);
        }
        if (alpha > 0) using (var b = new SolidBrush(Color.FromArgb(alpha, 15, 24, 27))) g.FillRectangle(b, ClientRectangle);
        if (c.Mix.Cloud > .05)
        {
            var smooth = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.None;
            using var cloud = new SolidBrush(Color.FromArgb((int)(c.Mix.Cloud * 50), 225, 227, 216));
            for (int i = 0; i < 8; i++) g.FillEllipse(cloud, (float)((i * 340 - _camera.Clock * 9) % (Width + 500)) - 200, 30 + (i % 3) * 36, 390, 66);
            g.SmoothingMode = smooth;
        }
    }

    void DrawEcology(Graphics g, WeatherConditions c)
    {
        var eco = _window.Ecology;
        // Water beaded on the leaves, and drops shaken loose.
        using var bead = new SolidBrush(Color.FromArgb(165, 190, 225, 231));
        using var shine = new SolidBrush(Color.FromArgb(190, 250, 255, 255));
        foreach (var d in eco.Drops)
        {
            if (!OnGlass(d.Point, 30)) continue;
            var p = P(d.Point.X, d.Point.Y);
            float r = (float)Math.Max(1, d.Size * 2.2);
            g.FillEllipse(bead, p.X - r, p.Y - r, r * 2, r * 2);
            g.FillEllipse(shine, p.X - r * .45f, p.Y - r * .45f, Math.Max(1, r * .6f), Math.Max(1, r * .6f));
        }
        // What is left of a meal.
        using var shell = new Pen(Color.FromArgb(160, 74, 59, 40), 1.6f);
        foreach (var remains in eco.Remains)
        {
            if (!OnGlass(remains.Point, 20)) continue;
            var p = P(remains.Point.X, remains.Point.Y);
            g.DrawEllipse(shell, p.X - 3, p.Y - 1.5f, 6, 3);
            g.DrawLine(shell, p.X - 3, p.Y, p.X + 4, p.Y - 1);
        }
        // Visitors on their way in.
        foreach (var arrival in eco.Arrivals)
        {
            var p = P(arrival.Patch.X, arrival.Patch.Y);
            double t = _camera.Clock;
            using var body = new SolidBrush(arrival.Kind switch
            {
                PreyKind.Moth => Color.FromArgb(205, 224, 216, 188),
                PreyKind.Beetle => Color.FromArgb(230, 58, 48, 38),
                PreyKind.Ladybug => Color.FromArgb(230, 176, 55, 44),
                PreyKind.Worm => Color.FromArgb(220, 183, 143, 142),
                PreyKind.Ant => Color.FromArgb(220, 48, 34, 29),
                PreyKind.Mosquito => Color.FromArgb(200, 83, 74, 60),
                PreyKind.Cricket => Color.FromArgb(220, 98, 125, 58),
                _ => Color.FromArgb(210, 170, 140, 70)
            });
            float wing = (float)(3 + Math.Sin(t * 18) * 2);
            if (Prey.Info(arrival.Kind).Flies)
            {
                using var w = new SolidBrush(Color.FromArgb(90, 236, 235, 220));
                g.FillEllipse(w, p.X - 5, p.Y - wing, 9, wing);
            }
            g.FillEllipse(body, p.X - 2.5f, p.Y - 2, 5, 4);
        }
        // Snow lies only where the sky is open, and is brushed off the tops of things.
        // Footprints pressed into the snow, or a wet trail on the floor.
        using var snowPrint = new SolidBrush(Color.FromArgb(94, 118, 128, 132));
        using var wetPrint = new SolidBrush(Color.FromArgb(64, 39, 48, 42));
        foreach (var track in _tracks)
        {
            if (!OnGlass(track.at, 20)) continue;
            var tp = P(track.at.X, track.at.Y);
            g.FillEllipse(track.snow ? snowPrint : wetPrint, tp.X - 2.6f, tp.Y - 1, 5.2f, 2.2f);
        }
        if (c.Mix.Snow > .12)
        {
            using var cap = new Pen(Color.FromArgb((int)(130 + c.Mix.Snow * 110), 244, 249, 250), 2.2f);
            foreach (var item in _world.Items.Where(i => !i.InFront && PlaceSurvey.Counts(i)))
            {
                if (!OnGlass(item.Rect.Mid, 200)) continue;
                foreach (var part in HabitatGeometry.For(item).Visual)
                {
                    for (int i = 0; i + 1 < part.Count; i++)
                    {
                        var a = part[i]; var b = part[i + 1];
                        if (Math.Abs(a.Y - b.Y) > 3 || a.Y < item.Rect.Mid.Y) continue;
                        var mid = V2.Lerp(a, b, .5);
                        if (eco.Sky.OpenAt(mid) < .45) continue;
                        var pa = P(a.X, a.Y); var pb = P(b.X, b.Y);
                        g.DrawLine(cap, pa.X, pa.Y - 1, pb.X, pb.Y - 1);
                    }
                }
            }
        }
        // A drop of rain rings a dish or pool left out under the sky.
        if (c.Mix.Rain > .08 && _window.Mind.Survey is { } survey)
        {
            using var ring = new Pen(Color.FromArgb(100, 220, 239, 239), 1);
            foreach (var water in survey.Water)
            {
                if (eco.Sky.OpenAt(water.Surface.Mid) < .4) continue;
                var p = P(water.Surface.Mid.X, water.Surface.MinY);
                double phase = (_camera.Clock * 1.7 + water.Id) % 1;
                g.DrawEllipse(ring, p.X - (float)(phase * 16), p.Y - (float)(phase * 5), (float)(phase * 32), (float)(phase * 10));
            }
        }
    }

    bool OnGlass(V2 p, double margin)
    {
        var o = _camera.Origin;
        return p.X >= o.X - margin && p.X <= o.X + Width + margin && p.Y >= o.Y - margin && p.Y <= o.Y + Height + margin;
    }

    void DrawParticles(Graphics g)
    {
        using var rain = new Pen(Color.FromArgb(130, 203, 225, 233), 1);
        using var snow = new SolidBrush(Color.FromArgb(210, 244, 248, 250));
        using var hail = new SolidBrush(Color.FromArgb(225, 241, 247, 249));
        using var sand = new SolidBrush(Color.FromArgb(95, 210, 181, 121));
        double dt = Math.Clamp(_frameDt, .01, .08);
        for (int i = _particles.Count - 1; i >= 0; i--)
        {
            var p = _particles[i]; p.X += p.Vx * dt; p.Y += p.Vy * dt; p.Life -= dt;
            if (p.Life <= 0 || p.Y < _camera.Origin.Y - 40) { _particles.RemoveAt(i); continue; }
            var s = P(p.X, p.Y);
            if (p.Kind == 0) g.DrawLine(rain, s.X, s.Y, s.X - 3, s.Y + 12);
            else if (p.Kind == 1) g.FillEllipse(snow, s.X, s.Y, 3, 3);
            else if (p.Kind == 3) g.FillEllipse(hail, s.X, s.Y, 4, 4);
            else g.FillEllipse(sand, s.X, s.Y, 2, 2);
        }
    }

    void DrawSelection(Graphics g, HabitatItem item)
    {
        var r = Screen(item.Rect);
        using var pen = new Pen(Color.FromArgb(225, 248, 215, 144), 1.5f) { DashStyle = DashStyle.Dash };
        g.DrawRectangle(pen, r.X, r.Y, r.Width, r.Height);
        using var handle = new SolidBrush(Color.FromArgb(245, 248, 215, 144));
        g.FillRectangle(handle, r.Right - 4, r.Bottom - 4, 8, 8);
    }

    void DrawGeometry(Graphics g)
    {
        using var part = new Pen(Color.FromArgb(180, 101, 230, 211), 1);
        using var loop = new Pen(Color.FromArgb(135, 245, 183, 96), 1);
        foreach (var it in _world.Items)
        {
            var geo = HabitatGeometry.For(it);
            foreach (var p in geo.Parts) g.DrawPolygon(part, p.Outline.Select(v => P(v.X, v.Y)).ToArray());
        }
        foreach (var l in _map.AllLoops)
        {
            var pts = l.Segs.SelectMany(s => new[] { s.A, s.B }).Select(v => P(v.X, v.Y)).ToArray();
            if (pts.Length > 1) g.DrawLines(loop, pts);
        }
    }

    void DrawGlass(Graphics g)
    {
        using var frame = new Pen(Color.FromArgb(150, 9, 12, 10), 10); g.DrawRectangle(frame, 5, 5, Width - 10, Height - 10);
        using var shine = new Pen(Color.FromArgb(30, 255, 255, 255), 2);
        g.DrawLine(shine, 14, 14, 14, Height - 14);
        g.DrawLine(shine, 14, 14, Width - 14, 14);
        using var edge = new SolidBrush(Color.FromArgb(34, 0, 0, 0));
        g.FillRectangle(edge, 0, 0, Width, 13); g.FillRectangle(edge, 0, Height - 13, Width, 13);
        g.FillRectangle(edge, 0, 0, 13, Height); g.FillRectangle(edge, Width - 13, 0, 13, Height);
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

    sealed class HabitatParticle { public double X, Y, Vx, Vy, Life; public int Kind; }
}

/// <summary>Decorate panel shown beside the tank.</summary>
public sealed class HabitatPanel : Panel
{
    readonly HabitatWindow _window;
    readonly TextBox _search;
    readonly ListBox _list;
    readonly ComboBox _shelf;
    readonly Label _status;
    readonly List<HabitatItemKind> _shown = new();

    public HabitatPanel(HabitatWindow window)
    {
        _window = window;
        BackColor = Color.FromArgb(33, 36, 31); ForeColor = Color.FromArgb(234, 226, 207);
        _search = new TextBox { Dock = DockStyle.Top, Height = 28, BackColor = Color.FromArgb(24, 27, 23), ForeColor = Color.White, BorderStyle = BorderStyle.FixedSingle, PlaceholderText = "Search everything…" };
        _shelf = new ComboBox { Dock = DockStyle.Top, Height = 28, DropDownStyle = ComboBoxStyle.DropDownList, BackColor = Color.FromArgb(43, 47, 40), ForeColor = Color.White };
        _shelf.Items.Add("All shelves"); foreach (var s in HabitatShelves.All) _shelf.Items.Add(s.Heading());
        _shelf.SelectedIndex = 0;
        _list = new ListBox { Dock = DockStyle.Fill, IntegralHeight = false, BackColor = Color.FromArgb(27, 30, 26), ForeColor = Color.FromArgb(229, 221, 202), BorderStyle = BorderStyle.None, ItemHeight = 24 };
        var bottom = new Panel { Dock = DockStyle.Bottom, Height = 92, Padding = new Padding(8) };
        var add = new Button { Text = "Add to the tank", Dock = DockStyle.Top, Height = 32, FlatStyle = FlatStyle.Flat, BackColor = Color.FromArgb(128, 103, 62), ForeColor = Color.White };
        add.Click += (_, _) => { if (_list.SelectedIndex >= 0 && _list.SelectedIndex < _shown.Count) _window.AddItem(_shown[_list.SelectedIndex]); };
        _status = new Label { Dock = DockStyle.Bottom, Height = 34, TextAlign = ContentAlignment.MiddleLeft, ForeColor = Color.FromArgb(170, 165, 150) };
        bottom.Controls.Add(add); bottom.Controls.Add(_status);
        var head = new Label { Dock = DockStyle.Top, Height = 28, Text = "DECORATE", TextAlign = ContentAlignment.MiddleLeft, Font = new Font("Segoe UI Semibold", 9f), ForeColor = Color.FromArgb(188, 171, 123) };
        Controls.Add(_list); Controls.Add(bottom); Controls.Add(_shelf); Controls.Add(_search); Controls.Add(head);
        _search.TextChanged += (_, _) => RefreshList();
        _shelf.SelectedIndexChanged += (_, _) => RefreshList();
        _list.SelectedIndexChanged += (_, _) => { if (_list.SelectedIndex >= 0 && _list.SelectedIndex < _shown.Count) { _status.Text = _shown[_list.SelectedIndex].Definition().Note; _window.View.Select(null); } };
        _list.DoubleClick += (_, _) => { if (_list.SelectedIndex >= 0 && _list.SelectedIndex < _shown.Count) _window.AddItem(_shown[_list.SelectedIndex]); };
        RefreshList();
    }

    public void RefreshList()
    {
        _shown.Clear(); _list.Items.Clear();
        string query = _search.Text.Trim();
        var shelf = _shelf.SelectedIndex <= 0 ? (HabitatShelf?)null : HabitatShelves.All[_shelf.SelectedIndex - 1];
        foreach (var kind in Enum.GetValues<HabitatItemKind>())
        {
            if (shelf is { } sh && kind.Definition().Shelf != sh) continue;
            if (query.Length > 0 && !kind.Matches(query)) continue;
            _shown.Add(kind); _list.Items.Add(kind.Label() + "   ·   " + kind.Definition().Category);
        }
        _status.Text = _shown.Count + " things";
    }
}

public sealed class HabitatInspector : Form
{
    public HabitatInspector(HabitatWindow window, HabitatItem item)
    {
        Text = item.Kind.Label(); ClientSize = new Size(350, 372); StartPosition = FormStartPosition.CenterParent; FormBorderStyle = FormBorderStyle.FixedDialog;
        BackColor = Color.FromArgb(35, 38, 33); ForeColor = Color.White;
        var title = new Label { Text = item.Kind.Label(), Font = new Font("Segoe UI Semibold", 13f), Location = new Point(16, 14), AutoSize = true };
        var body = new Label
        {
            Text = $"{item.Definition.Note}\n\nMaterial: {item.Kind.Traits().Material}\nPlacement: {item.Definition.Placement}\nLayer: {(item.Kind.AtBack() ? "behind everything" : item.InFront ? "in front of the spider" : "among the furniture")}",
            Location = new Point(16, 48), Size = new Size(316, 92)
        };
        var widthLabel = new Label { Text = "Width", Location = new Point(16, 150), AutoSize = true };
        var width = new NumericUpDown { Minimum = 1, Maximum = 3000, Value = (decimal)Math.Clamp(item.W, 1, 3000), Location = new Point(66, 146), Width = 78, BackColor = Color.FromArgb(25, 28, 24), ForeColor = Color.White };
        var heightLabel = new Label { Text = "Height", Location = new Point(160, 150), AutoSize = true };
        var height = new NumericUpDown { Minimum = 1, Maximum = 3000, Value = (decimal)Math.Clamp(item.H, 1, 3000), Location = new Point(214, 146), Width = 78, BackColor = Color.FromArgb(25, 28, 24), ForeColor = Color.White };
        width.ValueChanged += (_, _) => { item.W = (double)width.Value; window.World.Clamp(item); };
        height.ValueChanged += (_, _) => { item.H = (double)height.Value; window.World.Clamp(item); };
        var flip = new Button { Text = "Mirror", Location = new Point(16, 188), Width = 88 };
        flip.Click += (_, _) => { window.PushUndo(); item.Flip = !item.Flip; };
        var layer = new Button { Text = item.InFront ? "Send behind" : "Bring forward", Location = new Point(112, 188), Width = 104, Enabled = item.Kind.CanGoInFront() };
        layer.Click += (_, _) => { window.PushUndo(); item.Front = !item.Front; layer.Text = item.Front ? "Send behind" : "Bring forward"; };
        var dup = new Button { Text = "Duplicate", Location = new Point(224, 188), Width = 88 };
        dup.Click += (_, _) =>
        {
            window.PushUndo(); var c = item.Clone(); c.Id = window.World.NextId++; c.Uid = Guid.NewGuid().ToString("D");
            c.X += 24; if (item.Hangs) c.Y += 24; window.World.Items.Add(c); window.Rebuild(); window.Save();
        };
        bool isDoor = item.Kind is HabitatItemKind.Door or HabitatItemKind.DoorClosed;
        var door = new Button
        {
            Text = item.Kind == HabitatItemKind.DoorClosed ? "Open Door" : "Shut Door",
            Location = new Point(16, 228), Width = 104, Visible = isDoor,
            BackColor = Color.FromArgb(64, 80, 61)
        };
        door.Click += (_, _) =>
        {
            window.PushUndo();
            item.Kind = item.Kind == HabitatItemKind.DoorClosed ? HabitatItemKind.Door : HabitatItemKind.DoorClosed;
            door.Text = item.Kind == HabitatItemKind.DoorClosed ? "Open Door" : "Shut Door";
            window.Rebuild(); window.Save();
        };
        bool isWindow = item.Kind is HabitatItemKind.Window or HabitatItemKind.WindowOpen;
        var pane = new Button
        {
            Text = item.Kind == HabitatItemKind.WindowOpen ? "Shut Window" : "Open Window",
            Location = new Point(126, 228), Width = 104, Visible = isWindow,
            BackColor = Color.FromArgb(64, 80, 61)
        };
        pane.Click += (_, _) =>
        {
            window.PushUndo();
            item.Kind = item.Kind == HabitatItemKind.WindowOpen ? HabitatItemKind.Window : HabitatItemKind.WindowOpen;
            pane.Text = item.Kind == HabitatItemKind.WindowOpen ? "Shut Window" : "Open Window";
            window.Rebuild(); window.Save();
        };
        var del = new Button { Text = "Remove", Location = new Point(16, 274), Width = 88, BackColor = Color.FromArgb(104, 54, 45) };
        del.Click += (_, _) =>
        {
            window.PushUndo(); window.World.Remove(item); window.View.Select(null); window.Rebuild(); window.Save(); Close();
        };
        var done = new Button { Text = "Done", DialogResult = DialogResult.OK, Location = new Point(238, 274), Width = 88 };
        var hint = new Label { Text = "Pieces click together where they meet. Drag a corner to resize.", Location = new Point(16, 314), Size = new Size(316, 36), ForeColor = Color.FromArgb(160, 156, 140) };
        Controls.AddRange(new Control[] { title, body, widthLabel, width, heightLabel, height, flip, layer, dup, door, pane, del, done, hint });
    }
}

public sealed class HabitatMap : Form
{
    readonly HabitatWorld _world;
    V2 _camera;
    readonly V2 _spider;
    readonly SizeD _view;
    readonly IReadOnlyList<V2> _loose;
    HabitatItem? _selected;
    V2? _drag, _frameGrab;
    public V2? Chosen { get; private set; }
    public HabitatItem? Moved => _selected;
    public V2? MovedTo { get; private set; }

    public HabitatMap(HabitatWindow owner, HabitatWorld world, V2 camera, V2 spider, SizeD view, HabitatItem? selected,
        IReadOnlyList<V2>? loose = null)
    {
        _world = world; _camera = camera; _spider = spider; _view = view; _selected = selected;
        _loose = loose ?? Array.Empty<V2>();
        Text = "Map — the whole tank"; ClientSize = new Size(860, 470); StartPosition = FormStartPosition.CenterParent; DoubleBuffered = true;
        BackColor = Color.FromArgb(22, 25, 21);
        Paint += Draw;
        MouseDown += (_, e) =>
        {
            var p = WorldAt(e.Location);
            var frame = new Rect(_camera.X, _camera.Y, _view.Width, _view.Height).Inset(-8 / Scale);
            var hit = SelectedHit(p);
            if (hit is not null) { _selected = hit; _drag = new V2(p.X - hit.X, p.Y - (hit.Hangs ? hit.Y - hit.H : hit.Y)); Invalidate(); return; }
            if (frame.Contains(p) && !_world.Items.Any(i => i.Rect.Inset(8 / Scale).Contains(p)))
            {
                _frameGrab = new V2(p.X - _camera.X, p.Y - _camera.Y); Invalidate(); return;
            }
            Chosen = p; DialogResult = DialogResult.OK; Close();
        };
        MouseMove += (_, e) =>
        {
            var p = WorldAt(e.Location);
            if (_frameGrab is { } grab)
            {
                _camera = new V2(p.X - grab.X, p.Y - grab.Y); Invalidate(); return;
            }
            if (_drag is not { } d || _selected is null) return;
            if (_selected.Hangs) _selected.Y = p.Y + d.Y; else { _selected.X = p.X - d.X; _selected.Y = Math.Max(0, p.Y - d.Y); }
            _world.Clamp(_selected); MovedTo = new V2(_selected.X, _selected.Y); Invalidate();
        };
        MouseUp += (_, _) =>
        {
            if (_frameGrab is not null)
            {
                _frameGrab = null; Chosen = new V2(_camera.X + _view.Width / 2, _camera.Y + _view.Height / 2);
                DialogResult = DialogResult.OK; Close(); return;
            }
            if (_drag is not null) { _drag = null; _selected = null; }
        };
    }

    new double Scale => Math.Min((ClientSize.Width - 40) / _world.Bounds.W, (ClientSize.Height - 66) / _world.Bounds.H);
    double Ox => (ClientSize.Width - _world.Bounds.W * Scale) / 2;
    double Oy => (ClientSize.Height - _world.Bounds.H * Scale) / 2;
    V2 WorldAt(Point p) => new((p.X - Ox) / Scale, (ClientSize.Height - p.Y - Oy) / Scale);
    PointF P(V2 p) => new((float)(Ox + p.X * Scale), (float)(ClientSize.Height - Oy - p.Y * Scale));
    RectangleF R(Rect r) => new((float)(Ox + r.MinX * Scale), (float)(ClientSize.Height - Oy - r.MaxY * Scale), (float)(r.W * Scale), (float)(r.H * Scale));

    HabitatItem? SelectedHit(V2 p)
    {
        foreach (var it in _world.Items.AsEnumerable().Reverse()) if (it.Rect.Inset(-12 / Scale, -12 / Scale).Contains(p)) return it;
        return null;
    }

    void Draw(object? sender, PaintEventArgs e)
    {
        var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
        using var bg = new SolidBrush(Color.FromArgb(48, 57, 45)); g.FillRectangle(bg, R(_world.Bounds));
        using var ground = new SolidBrush(Color.FromArgb(76, 65, 45)); g.FillRectangle(ground, (float)Ox, (float)(ClientSize.Height - Oy - 74 * Scale), (float)(_world.Bounds.W * Scale), (float)(74 * Scale));
        using var item = new SolidBrush(Color.FromArgb(115, 95, 61));
        foreach (var it in _world.Items)
        {
            if (it.Kind.AtBack()) g.FillRectangle(new SolidBrush(Color.FromArgb(55, 52, 44)), R(it.Rect));
            else if (it.Kind.Climbable()) g.FillRectangle(item, R(it.Rect));
            else g.FillRectangle(new SolidBrush(Color.FromArgb(72, 96, 66)), R(it.Rect));
        }
        using var glass = new Pen(Color.FromArgb(242, 223, 175), 2);
        g.DrawRectangle(glass, (float)(Ox + _camera.X * Scale), (float)(ClientSize.Height - Oy - (_camera.Y + _view.Height) * Scale), (float)(_view.Width * Scale), (float)(_view.Height * Scale));
        using var spider = new SolidBrush(Color.FromArgb(244, 159, 80));
        var sp = P(_spider); g.FillEllipse(spider, sp.X - 6, sp.Y - 6, 12, 12);
        using var loose = new SolidBrush(Color.FromArgb(204, 196, 165));
        foreach (var p in _loose) { var lp = P(p); g.FillEllipse(loose, lp.X - 2, lp.Y - 2, 4, 4); }
        using var font = new Font("Segoe UI Semibold", 10f);
        g.DrawString(_world.Name + "   ·   click anywhere to look there; drag a thing to move it", font, Brushes.Gainsboro, 16, 14);
    }
}

public sealed class HabitatTour : Form
{
    int _step;
    readonly Label _text;
    readonly bool _decorating;
    static readonly string[] Steps =
    {
        "This is the tank: the glass follows the spider, or drag it yourself. The Map shows the whole thing.",
        "Feed is for live food — or let creatures find their own way in. Weather is the sky over the tank.",
        "Decorate opens the shelf beside the tank. Search, add, and drag things about.",
        "Drag a thing to move it; Shift+wheel resizes it; double-click for Mirror, Duplicate and Remove.",
        "Click the tank name to rename it. Press F to find the spider and Esc to finish decorating."
    };
    public HabitatTour(HabitatWindow owner, bool decorating)
    {
        _decorating = decorating;
        Text = "A tour of the habitat"; ClientSize = new Size(470, 210); StartPosition = FormStartPosition.CenterParent; FormBorderStyle = FormBorderStyle.FixedDialog;
        BackColor = Color.FromArgb(34, 37, 32); ForeColor = Color.White;
        _text = new Label { Location = new Point(22, 24), Size = new Size(426, 106), Font = new Font("Segoe UI", 10.5f) };
        var back = new Button { Text = "Back", Location = new Point(22, 154), Width = 90 };
        var next = new Button { Text = "Next", Location = new Point(358, 154), Width = 90 };
        var close = new Button { Text = "Close", DialogResult = DialogResult.Cancel, Location = new Point(260, 154), Width = 90 };
        back.Click += (_, _) => { _step = Math.Max(0, _step - 1); Show(); };
        next.Click += (_, _) => { if (_step >= Steps.Length - 1) Close(); else { _step++; Show(); } };
        Controls.AddRange(new Control[] { _text, back, next, close });
        Show();
    }
    new void Show() { _text.Text = Steps[Math.Clamp(_step, 0, Steps.Length - 1)]; }
}
