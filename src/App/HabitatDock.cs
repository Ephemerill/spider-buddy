using SpiderBuddy.Core;
using WinForms = System.Windows.Forms;

namespace SpiderBuddy.App;

/// <summary>The Decorate dock: Add, Scenery and My Habitats, beside the glass.</summary>
public sealed class HabitatDock : Panel
{
    readonly HabitatWindow _window;
    readonly WinForms.TabControl _tabs;
    readonly TextBox _search;
    readonly ComboBox _shelf;
    readonly ListBox _list;
    readonly ListBox _habitats;
    readonly Button _save;
    readonly Label _status;
    readonly List<HabitatItemKind> _shown = new();
    readonly List<SavedHabitat> _shownHabitats = new();
    readonly WinForms.Timer _statusTimer;
    int _selectedTab;

    public HabitatDock(HabitatWindow window)
    {
        _window = window;
        BackColor = Color.FromArgb(33, 36, 31);
        ForeColor = Color.FromArgb(234, 226, 207);
        Padding = new Padding(0);

        _tabs = new WinForms.TabControl
        {
            Dock = DockStyle.Fill, Appearance = TabAppearance.Normal,
            DrawMode = TabDrawMode.OwnerDrawFixed, ItemSize = new Size(88, 27), SizeMode = TabSizeMode.Fixed,
            Font = new Font("Segoe UI Semibold", 9f)
        };
        _tabs.DrawItem += (_, e) =>
        {
            var g = e.Graphics;
            bool chosen = e.Index == _tabs.SelectedIndex;
            using var back = new SolidBrush(chosen ? Color.FromArgb(55, 60, 51) : Color.FromArgb(29, 32, 28));
            g.FillRectangle(back, e.Bounds);
            string text = _tabs.TabPages[e.Index].Text;
            TextRenderer.DrawText(g, text, _tabs.Font, e.Bounds,
                chosen ? Color.FromArgb(241, 228, 192) : Color.FromArgb(173, 168, 152),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
        };

        var add = new WinForms.TabPage { Text = "Add", BackColor = Color.FromArgb(30, 33, 29) };
        _search = new TextBox
        {
            Dock = DockStyle.Top, Height = 30, BackColor = Color.FromArgb(24, 27, 23),
            ForeColor = Color.White, BorderStyle = BorderStyle.FixedSingle, PlaceholderText = "Search everything…"
        };
        _shelf = new ComboBox
        {
            Dock = DockStyle.Top, Height = 30, DropDownStyle = ComboBoxStyle.DropDownList,
            BackColor = Color.FromArgb(43, 47, 40), ForeColor = Color.White
        };
        _shelf.Items.Add("All shelves");
        foreach (var s in HabitatShelves.All) _shelf.Items.Add(s.Heading());
        _shelf.SelectedIndex = 0;
        _list = new ListBox
        {
            Dock = DockStyle.Fill, IntegralHeight = false, BackColor = Color.FromArgb(27, 30, 26),
            ForeColor = Color.FromArgb(229, 221, 202), BorderStyle = BorderStyle.None, ItemHeight = 24
        };
        var addFoot = new Panel { Dock = DockStyle.Bottom, Height = 60, Padding = new Padding(8) };
        var addButton = new Button
        {
            Text = "Add to the tank", Dock = DockStyle.Top, Height = 34, FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(128, 103, 62), ForeColor = Color.White
        };
        addButton.FlatAppearance.BorderColor = Color.FromArgb(170, 143, 92);
        addButton.Click += (_, _) => AddSelected();
        addFoot.Controls.Add(addButton);
        add.Controls.Add(_list); add.Controls.Add(addFoot); add.Controls.Add(_shelf); add.Controls.Add(_search);
        _search.TextChanged += (_, _) => RefreshList();
        _shelf.SelectedIndexChanged += (_, _) => RefreshList();
        _list.SelectedIndexChanged += (_, _) =>
        {
            if (_list.SelectedIndex >= 0 && _list.SelectedIndex < _shown.Count)
                Status(_shown[_list.SelectedIndex].Definition().Note);
        };
        _list.DoubleClick += (_, _) => AddSelected();

        var scenery = new WinForms.TabPage { Text = "Scenery", BackColor = Color.FromArgb(30, 33, 29) };
        var scenes = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false,
            AutoScroll = true, Padding = new Padding(8), BackColor = Color.FromArgb(30, 33, 29)
        };
        var biomes = new[]
        {
            HabitatBiome.Forest, HabitatBiome.Jungle, HabitatBiome.Desert, HabitatBiome.Meadow,
            HabitatBiome.Cave, HabitatBiome.Beach, HabitatBiome.Tundra, HabitatBiome.Moonlit
        };
        foreach (var biome in biomes)
        {
            var button = new Button
            {
                Text = BiomeTile(biome), Width = 272, Height = 52, FlatStyle = FlatStyle.Flat,
                TextAlign = ContentAlignment.MiddleLeft, Padding = new Padding(12, 0, 0, 0),
                BackColor = BiomeColor(biome), ForeColor = Color.White,
                Font = new Font("Segoe UI Semibold", 9.5f)
            };
            button.FlatAppearance.BorderColor = Color.FromArgb(95, 99, 83);
            button.Click += (_, _) => _window.ApplyBiome(biome);
            scenes.Controls.Add(button);
        }
        var sceneryNote = new Label
        {
            Text = "The backdrop behind the glass. Everything in the tank stays where it is.",
            AutoSize = false, Width = 272, Height = 54, ForeColor = Color.FromArgb(170, 165, 150)
        };
        scenes.Controls.Add(sceneryNote);
        scenery.Controls.Add(scenes);

        var habitats = new WinForms.TabPage { Text = "My Habitats", BackColor = Color.FromArgb(30, 33, 29) };
        var habitTop = new Panel { Dock = DockStyle.Top, Height = 92, Padding = new Padding(8) };
        _save = new Button
        {
            Dock = DockStyle.Top, Height = 34, FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(128, 103, 62), ForeColor = Color.White
        };
        _save.Click += (_, _) => SavePressed();
        var newSave = new Button
        {
            Text = "Save as New…", Dock = DockStyle.Bottom, Height = 30, FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(49, 54, 46), ForeColor = Color.White
        };
        newSave.Click += (_, _) => _window.SaveAsNew();
        var bringIn = new Button
        {
            Text = "Bring In a Habitat…", Dock = DockStyle.Bottom, Height = 30, FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(44, 48, 42), ForeColor = Color.White
        };
        bringIn.Click += (_, _) => _window.ImportHabitat();
        habitTop.Controls.Add(newSave); habitTop.Controls.Add(bringIn); habitTop.Controls.Add(_save);
        _habitats = new ListBox
        {
            Dock = DockStyle.Fill, IntegralHeight = false, BackColor = Color.FromArgb(27, 30, 26),
            ForeColor = Color.FromArgb(229, 221, 202), BorderStyle = BorderStyle.None, ItemHeight = 38
        };
        _habitats.DrawMode = DrawMode.OwnerDrawFixed;
        _habitats.DrawItem += DrawHabitatRow;
        _habitats.DoubleClick += (_, _) => LoadSelected();
        var habitFoot = new Panel { Dock = DockStyle.Bottom, Height = 114, Padding = new Padding(8) };
        var put = new Button
        {
            Text = "Put in the Tank", Dock = DockStyle.Top, Height = 32, FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(64, 80, 61), ForeColor = Color.White
        };
        put.Click += (_, _) => LoadSelected();
        var more = new Button
        {
            Text = "⋯  Rename · Update · Share · Delete", Dock = DockStyle.Top, Height = 30, FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(43, 47, 40), ForeColor = Color.FromArgb(220, 212, 193)
        };
        more.Click += (_, _) => ShowSavedMenu();
        var afresh = new Button
        {
            Text = "Start Afresh…", Dock = DockStyle.Top, Height = 30, FlatStyle = FlatStyle.Flat,
            BackColor = Color.FromArgb(43, 47, 40), ForeColor = Color.FromArgb(220, 212, 193)
        };
        afresh.Click += (_, _) => ShowAfreshMenu(afresh);
        habitFoot.Controls.Add(afresh); habitFoot.Controls.Add(more); habitFoot.Controls.Add(put);
        habitats.Controls.Add(_habitats); habitats.Controls.Add(habitFoot);
        habitats.Controls.Add(habitTop);

        _tabs.TabPages.Add(add); _tabs.TabPages.Add(scenery); _tabs.TabPages.Add(habitats);
        _tabs.SelectedIndexChanged += (_, _) => { _selectedTab = _tabs.SelectedIndex; RefreshHabitats(); };
        _status = new Label
        {
            Dock = DockStyle.Bottom, Height = 34, TextAlign = ContentAlignment.MiddleLeft,
            Padding = new Padding(10, 0, 4, 0), ForeColor = Color.FromArgb(170, 165, 150),
            BackColor = Color.FromArgb(27, 30, 26)
        };
        Controls.Add(_tabs); Controls.Add(_status);
        _statusTimer = new WinForms.Timer { Interval = 3200 };
        _statusTimer.Tick += (_, _) => { _statusTimer.Stop(); Status(_shown.Count + " things"); };
        RefreshList();
        RefreshHabitats();
    }

    void AddSelected()
    {
        if (_list.SelectedIndex >= 0 && _list.SelectedIndex < _shown.Count) _window.AddItem(_shown[_list.SelectedIndex]);
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
        if (_shown.Count == 0) Status("Nothing matches “" + query + "”");
        else Status(_shown.Count + " things");
    }

    public void RefreshHabitats()
    {
        if (_habitats is null) return;
        _shownHabitats.Clear(); _habitats.Items.Clear();
        foreach (var saved in HabitatLibrary.All())
        {
            _shownHabitats.Add(saved);
            bool current = saved.Id == _window.CurrentSaveId;
            _habitats.Items.Add((current ? "● " : "   ") + saved.Name + "\n     " + saved.When);
        }
        if (_habitats.Items.Count == 0) _habitats.Items.Add("   Nothing saved yet");
        var cur = _window.CurrentSaved;
        _save.Text = cur is null ? "Save This Habitat…" : (_window.CurrentChanged ? "Save Changes" : "Save as New…");
        if (_selectedTab == 2) Status(_shownHabitats.Count == 0 ? "Save the tank to come back to it" : _shownHabitats.Count + " habitats kept");
    }

    void DrawHabitatRow(object? sender, DrawItemEventArgs e)
    {
        using var bg = new SolidBrush(e.Index == _habitats.SelectedIndex ? Color.FromArgb(56, 62, 52) : Color.FromArgb(27, 30, 26));
        e.Graphics.FillRectangle(bg, e.Bounds);
        if (e.Index < 0 || e.Index >= _habitats.Items.Count) return;
        string text = _habitats.Items[e.Index]?.ToString() ?? "";
        var parts = text.Split('\n');
        using var name = new Font("Segoe UI Semibold", 9.5f);
        TextRenderer.DrawText(e.Graphics, parts[0], name, new Rectangle(e.Bounds.X + 6, e.Bounds.Y + 2, e.Bounds.Width - 10, 18),
            Color.FromArgb(235, 225, 203), TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
        if (parts.Length > 1)
            TextRenderer.DrawText(e.Graphics, parts[1].Trim(), Font, new Rectangle(e.Bounds.X + 12, e.Bounds.Y + 19, e.Bounds.Width - 16, 16),
                Color.FromArgb(154, 151, 135), TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
    }

    void SavePressed()
    {
        var current = _window.CurrentSaved;
        if (current is not null && _window.CurrentChanged) _window.SaveCurrent();
        else if (current is null) _window.SaveAsNew();
        else _window.SaveAsNew();
    }

    void LoadSelected()
    {
        if (_habitats.SelectedIndex < 0 || _habitats.SelectedIndex >= _shownHabitats.Count) return;
        _window.LoadSaved(_shownHabitats[_habitats.SelectedIndex].Id);
    }

    void ShowSavedMenu()
    {
        if (_habitats.SelectedIndex < 0 || _habitats.SelectedIndex >= _shownHabitats.Count) return;
        var saved = _shownHabitats[_habitats.SelectedIndex];
        var menu = new ContextMenuStrip { BackColor = Color.FromArgb(39, 43, 37), ForeColor = Color.White };
        menu.Items.Add("Put in the Tank", null, (_, _) => _window.LoadSaved(saved.Id));
        menu.Items.Add("Update to the Tank as It Is Now", null, (_, _) => _window.UpdateSaved(saved.Id));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Rename…", null, (_, _) => _window.RenameSaved(saved.Id));
        menu.Items.Add("Share a Copy…", null, (_, _) => _window.ShareSaved(saved.Id));
        menu.Items.Add("Show in File Explorer", null, (_, _) => _window.ShowSavedInFolder(saved.Id));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Delete…", null, (_, _) => _window.DeleteSaved(saved.Id));
        menu.Show(_habitats, new Point(10, Math.Max(0, _habitats.GetItemRectangle(_habitats.SelectedIndex).Bottom)));
    }

    void ShowAfreshMenu(Control anchor)
    {
        var menu = new ContextMenuStrip { BackColor = Color.FromArgb(39, 43, 37), ForeColor = Color.White };
        menu.Items.Add("Surprise Me", null, (_, _) => _window.StartAfresh(HabitatBiome.Forest, true));
        menu.Items.Add("Empty the Tank", null, (_, _) => _window.EmptyTank());
        menu.Items.Add(new ToolStripSeparator());
        foreach (var biome in new[]
        {
            HabitatBiome.Forest, HabitatBiome.Jungle, HabitatBiome.Desert, HabitatBiome.Meadow,
            HabitatBiome.Cave, HabitatBiome.Beach, HabitatBiome.Tundra, HabitatBiome.Moonlit
        })
            menu.Items.Add(biome.Label(), null, (_, _) => _window.StartAfresh(biome, false));
        menu.Items.Add("Bare Tank", null, (_, _) => _window.EmptyTank());
        menu.Show(anchor, new Point(0, anchor.Height));
    }

    public void Status(string text)
    {
        _status.Text = "  " + text;
        _statusTimer.Stop(); _statusTimer.Start();
    }

    public void ShowTab(int index)
    {
        if (index >= 0 && index < _tabs.TabPages.Count) _tabs.SelectedIndex = index;
    }

    public void ShowTab(string which)
    {
        ShowTab(which switch { "scenery" => 1, "habitats" => 2, _ => 0 });
    }

    public Rectangle TargetRect(string which) => which switch
    {
        "add" => _tabs.GetTabRect(0),
        "scenery" => _tabs.GetTabRect(1),
        "habitats" => _tabs.GetTabRect(2),
        _ => _tabs.RectangleToScreen(_tabs.ClientRectangle)
    };

    static Color BiomeColor(HabitatBiome biome) => biome switch
    {
        HabitatBiome.Forest => Color.FromArgb(47, 76, 50),
        HabitatBiome.Jungle => Color.FromArgb(33, 87, 58),
        HabitatBiome.Desert => Color.FromArgb(145, 105, 60),
        HabitatBiome.Meadow => Color.FromArgb(91, 121, 63),
        HabitatBiome.Cave => Color.FromArgb(45, 50, 51),
        HabitatBiome.Beach => Color.FromArgb(58, 111, 132),
        HabitatBiome.Tundra => Color.FromArgb(93, 121, 135),
        HabitatBiome.Moonlit => Color.FromArgb(28, 38, 65),
        _ => Color.FromArgb(52, 56, 49)
    };

    static string BiomeTile(HabitatBiome biome) => biome switch
    {
        HabitatBiome.Forest => "Forest   ·   moss, bark and quiet green",
        HabitatBiome.Jungle => "Jungle   ·   deep leaves and wet air",
        HabitatBiome.Desert => "Desert   ·   sand, stone and sun",
        HabitatBiome.Meadow => "Meadow   ·   flowers and open sky",
        HabitatBiome.Cave => "Cave   ·   cool stone and crystal",
        HabitatBiome.Beach => "Beach   ·   sea, sand and driftwood",
        HabitatBiome.Tundra => "Snowfall   ·   snow, pines and aurora",
        HabitatBiome.Moonlit => "Moonlit   ·   night, stars and silver",
        _ => "Bare"
    };
}
