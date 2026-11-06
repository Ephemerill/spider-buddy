using SpiderBuddy.Core;
using SpiderBuddy.Renderer;

namespace SpiderBuddy.App;

/// <summary>Spider Studio (spec 16.5): twelve tabs over the live design, with a live preview.</summary>
public sealed class StudioForm : Form
{
    readonly SpiderApplicationContext _app;
    readonly TabControl _tabs = new()
    {
        Dock = DockStyle.Fill, SizeMode = TabSizeMode.Fixed, ItemSize = new Size(1, 1),
        Appearance = TabAppearance.FlatButtons
    };
    readonly FlowLayoutPanel _tabBar = new()
    {
        Dock = DockStyle.Bottom, Height = 48, WrapContents = true,
        FlowDirection = FlowDirection.LeftToRight, BackColor = Color.FromArgb(255, 252, 246),
        Padding = new Padding(8, 2, 8, 2)
    };
    readonly SpiderPreview _preview;
    readonly TextBox _name = new() { Width = 150 };
    readonly SpiderDesign _original;
    readonly Label _kept = new() { AutoSize = true, Location = new Point(14, 74), ForeColor = Color.FromArgb(105, 96, 88), Font = new Font("Segoe UI", 8.5f) };
    readonly Button _save;
    readonly Button _revert;
    readonly Button _startOver;
    bool _throwaway;
    SpiderDesign Design => _app.Spider.Design;

    public StudioForm(SpiderApplicationContext app)
    {
        _app = app;
        _preview = new SpiderPreview(app) { Dock = DockStyle.Fill };
        _original = app.Library.Current?.Design.Clone() ?? app.Spider.Design.Clone();
        Text = "Spider Studio";
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(920, 600);
        MinimumSize = new Size(760, 560);
        BackColor = Color.FromArgb(248, 245, 238);

        var header = new Panel { Dock = DockStyle.Top, Height = 158, BackColor = Color.FromArgb(255, 252, 246), Padding = new Padding(14, 10, 14, 8) };
        var title = new Label { Text = "Spider Studio", Font = new Font("Segoe UI Semibold", 16f), AutoSize = true, Location = new Point(14, 8) };
        var nameLabel = new Label { Text = "Name", AutoSize = true, Location = new Point(14, 46) };
        nameLabel.Width = 50;
        nameLabel.TextAlign = ContentAlignment.MiddleLeft;
        _name.Location = new Point(78, 42);
        _name.Width = 132;
        _name.Text = Design.Name;
        _name.TextChanged += (_, _) => { Design.Name = _name.Text.Trim(); _throwaway = false; RefreshKept(); };
        var dice = new Button { Text = "Dice", Location = new Point(218, 42), Width = 70, Height = 24 };
        _save = new Button { Text = "Save", Location = new Point(360, 12), Width = 76, Height = 30 };
        _revert = new Button { Text = "Revert", Location = new Point(438, 12), Width = 80, Height = 30 };
        var surprise = new Button { Text = "Surprise Me", Location = new Point(504, 12), Width = 102, Height = 30 };
        _startOver = new Button { Text = "Start Over", Location = new Point(612, 12), Width = 112, Height = 30 };
        var done = new Button { Text = "Done", Location = new Point(706, 12), Width = 70, Height = 30 };
        _save.Click += (_, _) => SaveCurrent();
        _revert.Click += (_, _) => RevertCurrent();
        surprise.Click += (_, _) => SurpriseMe();
        dice.Click += (_, _) => RandomName();
        _startOver.Click += (_, _) => StartOver();
        done.Click += (_, _) => Close();
        header.Controls.AddRange(new Control[] { title, nameLabel, _name, dice, _kept });
        var actions = new FlowLayoutPanel
        {
            Dock = DockStyle.Right, Width = 500, FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false, Padding = new Padding(0, 8, 0, 0), BackColor = Color.Transparent
        };
        foreach (var b in new[] { _save, _revert, surprise, _startOver, done })
        {
            b.Margin = new Padding(4, 0, 0, 0);
            actions.Controls.Add(b);
        }
        header.Controls.Add(actions);
        _tabBar.Dock = DockStyle.None;
        _tabBar.Location = new Point(14, 106);
        _tabBar.Size = new Size(540, 48);
        header.Controls.Add(_tabBar);
        var previewPanel = new Panel { Dock = DockStyle.Right, Width = 300, Padding = new Padding(8, 8, 8, 0) };
        previewPanel.Controls.Add(_preview);
        previewPanel.Controls.Add(new Label
        {
            Text = "LIVE TERRARIUM", Dock = DockStyle.Top, Height = 22, TextAlign = ContentAlignment.MiddleLeft,
            Font = new Font("Segoe UI", 7.5f, FontStyle.Bold), ForeColor = Color.FromArgb(120, 110, 100)
        });

        Controls.Add(_tabs);
        Controls.Add(previewPanel);
        Controls.Add(header);
        BuildTabs();
        RefreshKept();
        FormClosed += (_, _) => { _app.SaveAll(quiet: true); _app.PanelDirty(); };
    }

    void BuildTabs()
    {
        for (int i = _tabs.TabPages.Count - 1; i >= 0; i--) _tabs.TabPages[i].Dispose();
        _tabs.TabPages.Add(Page("Body", BuildBody()));
        _tabs.TabPages.Add(Page("Face", BuildFace()));
        _tabs.TabPages.Add(Page("Hats", BuildHats()));
        _tabs.TabPages.Add(Page("Extras", BuildExtras()));
        _tabs.TabPages.Add(Page("Legs", BuildLegs()));
        _tabs.TabPages.Add(Page("Colours", BuildColours()));
        _tabs.TabPages.Add(Page("Markings", BuildMarkings()));
        _tabs.TabPages.Add(Page("Personality", BuildPersonality()));
        _tabs.TabPages.Add(Page("Gait", BuildGait()));
        _tabs.TabPages.Add(Page("Habits", BuildHabits()));
        _tabs.TabPages.Add(Page("Thoughts", BuildThoughts()));
        _tabs.TabPages.Add(Page("My Spiders", BuildLibrary()));
        RebuildTabBar();
    }

    void RebuildTabBar()
    {
        _tabBar.Controls.Clear();
        for (int i = 0; i < _tabs.TabPages.Count; i++)
        {
            int index = i;
            var b = new Button
            {
                Text = _tabs.TabPages[i].Text, Width = 84, Height = 21, Margin = new Padding(0, 0, 2, 2),
                FlatStyle = FlatStyle.System, Font = new Font("Segoe UI", 7.4f), Tag = index,
                TextAlign = ContentAlignment.MiddleCenter, AutoEllipsis = true
            };
            b.Click += (_, _) => SelectTab(index);
            _tabBar.Controls.Add(b);
        }
        SelectTab(Math.Clamp(_tabs.SelectedIndex, 0, Math.Max(0, _tabs.TabPages.Count - 1)));
    }

    void SelectTab(int index)
    {
        if (index < 0 || index >= _tabs.TabPages.Count) return;
        _tabs.SelectedIndex = index;
        foreach (Control c in _tabBar.Controls)
            if (c is Button b) b.Font = new Font("Segoe UI", 7.4f, b.Tag is int tag && tag == index ? FontStyle.Bold : FontStyle.Regular);
    }

    static TabPage Page(string title, Control content)
    {
        var page = new TabPage(title) { BackColor = Color.FromArgb(247, 244, 238), Padding = new Padding(4) };
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
            Padding = new Padding(12, 10, 12, 14),
            BackColor = Color.FromArgb(247, 244, 238)
        };
    }

    static Label Heading(string text) => new()
    {
        Text = text.ToUpperInvariant(),
        AutoSize = true,
        Font = new Font("Segoe UI", 7.5f, FontStyle.Bold),
        ForeColor = Color.FromArgb(120, 110, 100),
        Margin = new Padding(0, 9, 0, 2)
    };

    static Label Note(string text) => new()
    {
        Text = text,
        AutoSize = true,
        MaximumSize = new Size(390, 0),
        Width = 390,
        ForeColor = Color.FromArgb(110, 100, 90),
        Font = new Font("Segoe UI", 8f),
        Margin = new Padding(0, 2, 0, 5)
    };

    Control Combo<T>(string title, T value, Action<T> set) where T : struct, Enum
    {
        var row = new FlowLayoutPanel { FlowDirection = FlowDirection.LeftToRight, WrapContents = false, AutoSize = true, Margin = new Padding(0, 2, 0, 2) };
        row.Controls.Add(new Label { Text = title, Width = 120, Height = 24, TextAlign = ContentAlignment.MiddleLeft });
        var values = Enum.GetValues<T>();
        var box = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 250 };
        box.Items.AddRange(values.Select(v => (object)v.ToString()!).ToArray());
        int index = Array.FindIndex(values, v => EqualityComparer<T>.Default.Equals(v, value));
        box.SelectedIndex = Math.Max(0, index);
        box.SelectedIndexChanged += (_, _) =>
        {
            if (box.SelectedIndex >= 0) set(values[box.SelectedIndex]);
        };
        row.Controls.Add(box);
        var host = new Panel { Width = 400, Height = 30, Margin = new Padding(0, 1, 0, 1) };
        row.Dock = DockStyle.Fill;
        host.Controls.Add(row);
        return host;
    }

    Control Grid<T>(string title, T value, Action<T> set) where T : struct, Enum
    {
        var values = Enum.GetValues<T>();
        var host = new Panel { Width = 400, Height = 26 + (int)Math.Ceiling(values.Length / 4.0) * 28, Margin = new Padding(0, 1, 0, 3) };
        host.Controls.Add(new Label { Text = title, AutoSize = true, Location = new Point(0, 0) });
        var buttons = new List<Button>();
        for (int i = 0; i < values.Length; i++)
        {
            var v = values[i];
            var b = new Button
            {
                Text = v.ToString(), Width = 94, Height = 24, FlatStyle = FlatStyle.System,
                Location = new Point((i % 4) * 98, 20 + (i / 4) * 28), Tag = v,
                Font = new Font("Segoe UI", 7.5f, EqualityComparer<T>.Default.Equals(v, value) ? FontStyle.Bold : FontStyle.Regular),
                AutoEllipsis = true, TextAlign = ContentAlignment.MiddleCenter
            };
            if (EqualityComparer<T>.Default.Equals(v, value)) b.BackColor = Color.FromArgb(232, 221, 204);
            b.Click += (_, _) =>
            {
                set(v);
                foreach (var other in buttons)
                {
                    bool on = ReferenceEquals(other, b);
                    other.Font = new Font("Segoe UI", 7.5f, on ? FontStyle.Bold : FontStyle.Regular);
                    other.BackColor = on ? Color.FromArgb(232, 221, 204) : SystemColors.Control;
                }
            };
            buttons.Add(b);
            host.Controls.Add(b);
        }
        return host;
    }

    Control Slider(string title, double value, Action<double> set, Action? play = null)
    {
        var host = new Panel { Width = 400, Height = 46, Margin = new Padding(0, 1, 0, 2) };
        host.Controls.Add(new Label { Text = title, AutoSize = true, Location = new Point(0, 1) });
        var valueLabel = new Label { Text = value.ToString("0.00"), AutoSize = true, Location = new Point(300, 1), ForeColor = Color.FromArgb(110, 100, 90) };
        var bar = new TrackBar { Minimum = 0, Maximum = 100, TickStyle = TickStyle.None, Location = new Point(0, 18), Width = play is null ? 390 : 352, Value = (int)Math.Round(M.Clamp01(value) * 100) };
        bar.ValueChanged += (_, _) =>
        {
            double v = bar.Value / 100.0;
            valueLabel.Text = v.ToString("0.00");
            set(v);
        };
        host.Controls.Add(valueLabel);
        host.Controls.Add(bar);
        if (play is not null)
        {
            var b = new Button { Text = "▶", Location = new Point(360, 14), Width = 28, Height = 27, TabStop = false };
            b.Click += (_, _) => play();
            host.Controls.Add(b);
        }
        return host;
    }

    Control Tune(string title, double value, double min, double max, Action<double> set, Action? play = null)
    {
        double span = Math.Max(0.0001, max - min);
        return Slider(title, (value - min) / span, v => set(min + v * span), play);
    }

    CheckBox Check(string text, bool value, Action<bool> set)
    {
        var c = new CheckBox { Text = text, Checked = value, AutoSize = false, Width = 390, Height = 26, Margin = new Padding(0, 1, 0, 1) };
        c.CheckedChanged += (_, _) => set(c.Checked);
        return c;
    }

    Control BuildBody()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Shape"));
        p.Controls.Add(Grid("Body", Design.Look.Body, v => Design.Look.Body = v));
        p.Controls.Add(Grid("Fluff", Design.Look.Fuzz, v => Design.Look.Fuzz = v));
        p.Controls.Add(Heading("Fine tuning"));
        p.Controls.Add(Slider("Width", (Design.Look.BodyTune[0] - 0.6) / 1.0, v => Design.Look.BodyTune[0] = 0.6 + v));
        p.Controls.Add(Slider("Height", (Design.Look.BodyTune[1] - 0.6) / 1.0, v => Design.Look.BodyTune[1] = 0.6 + v));
        p.Controls.Add(Slider("Head", (Design.Look.BodyTune[2] - 0.6) / 1.0, v => Design.Look.BodyTune[2] = 0.6 + v));
        p.Controls.Add(Note("The sliders only bite when the body shape is Custom. A big head is adorable; use it responsibly."));
        p.Controls.Add(Heading("Size"));
        p.Controls.Add(Tune("Size", _app.Spider.UserScale, 0.6, 1.6, v => _app.ApplyScale(v)));
        p.Controls.Add(Note("Tiny to Chonky. The live terrarium on the right has its own floor and ledge: drag the spider about or throw it."));
        return p;
    }

    Control BuildFace()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Eyes"));
        p.Controls.Add(Grid("Eyes", Design.Look.Eyes, v => Design.Look.Eyes = v));
        p.Controls.Add(Grid("Brows", Design.Look.Brows, v => Design.Look.Brows = v));
        p.Controls.Add(Grid("Fangs", Design.Look.Fangs, v => Design.Look.Fangs = v));
        p.Controls.Add(Check("Face in front of the legs", Design.Look.FaceOverLegs, v => Design.Look.FaceOverLegs = v));
        p.Controls.Add(Note("Eyes carry most of the personality. Try Wide with soft brows for a permanent gentle surprise."));
        return p;
    }

    Control BuildHats()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Something on its head"));
        p.Controls.Add(Grid("Hat", Design.Look.Hat, v => Design.Look.Hat = v));
        p.Controls.Add(Note("Hats are deliberately a little too big. That is the point."));
        return p;
    }

    Control BuildExtras()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Something else"));
        p.Controls.Add(Grid("Accessory", Design.Look.Accessory, v => Design.Look.Accessory = v));
        p.Controls.Add(Check("Face in front of the legs", Design.Look.FaceOverLegs, v => Design.Look.FaceOverLegs = v));
        p.Controls.Add(Note("Some accessories are lopsided; the spider will keep its face on the sensible side."));
        return p;
    }

    Control BuildLegs()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Legs"));
        p.Controls.Add(Grid("Leg Style", Design.Look.Legs, v => Design.Look.Legs = v));
        p.Controls.Add(Grid("Motion", Design.Gait.Motion, v => Design.Gait.Motion = v));
        p.Controls.Add(Check("New leg rig", Design.Gait.NewLegs, v => Design.Gait.NewLegs = v));
        p.Controls.Add(Check("Face in front of the legs", Design.Look.FaceOverLegs, v => Design.Look.FaceOverLegs = v));
        return p;
    }

    Control BuildColours()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Coat"));
        p.Controls.Add(Grid("Coat", Design.Look.Coat, v => Design.Look.Coat = v));
        p.Controls.Add(Grid("Gradient", Design.Look.Gradient, v => Design.Look.Gradient = v));
        p.Controls.Add(Check("Living colour", Design.Look.Living, v => Design.Look.Living = v));
        p.Controls.Add(Check("Shimmer", Design.Look.Shimmer, v => Design.Look.Shimmer = v));
        p.Controls.Add(Heading("Custom colours"));
        p.Controls.Add(Btn("Body colour…", () => PickColour(c => Design.Look.CustomBody = c)));
        p.Controls.Add(Btn("Leg colour…", () => PickColour(c => Design.Look.CustomLeg = c)));
        p.Controls.Add(Btn("Accent colour…", () => PickColour(c => Design.Look.CustomAccent = c)));
        p.Controls.Add(Note("Living coats move on their own. Custom colours are used when the coat or accent is set to Custom."));
        return p;
    }

    Control BuildMarkings()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Markings"));
        p.Controls.Add(Grid("Pattern", Design.Look.Pattern, v => Design.Look.Pattern = v));
        p.Controls.Add(Check("Camouflage markings", Design.Look.CamoMarkings, v => Design.Look.CamoMarkings = v));
        p.Controls.Add(Note("Markings sit on the abdomen and pick up the accent colour. Camouflage blends them into the coat."));
        return p;
    }

    Control BuildPersonality()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Temperament"));
        p.Controls.Add(Combo("Preset", Temperament.Custom, t =>
        {
            if (t == Temperament.Custom) return;
            var preset = Personality.Preset(t);
            Design.Personality = preset;
            BuildTabs();
        }));
        p.Controls.Add(Heading("Six dials"));
        p.Controls.Add(Slider("Energy", Design.Personality.Energy, v => Design.Personality.Energy = v));
        p.Controls.Add(Slider("Curiosity", Design.Personality.Curiosity, v => Design.Personality.Curiosity = v));
        p.Controls.Add(Slider("Bravery", Design.Personality.Bravery, v => Design.Personality.Bravery = v));
        p.Controls.Add(Slider("Playfulness", Design.Personality.Playfulness, v => Design.Personality.Playfulness = v));
        p.Controls.Add(Slider("Affection", Design.Personality.Affection, v => Design.Personality.Affection = v));
        p.Controls.Add(Slider("Laziness", Design.Personality.Laziness, v => Design.Personality.Laziness = v));
        return p;
    }

    Control BuildGait()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Walk"));
        p.Controls.Add(Combo("Preference", Design.Gait.Preference, v => Design.Gait.Preference = v));
        p.Controls.Add(Slider("Pace", Design.Gait.Pace, v => Design.Gait.Pace = v));
        p.Controls.Add(Slider("Stride", Design.Gait.Stride, v => Design.Gait.Stride = v));
        p.Controls.Add(Slider("Bounce", Design.Gait.Bounce, v => Design.Gait.Bounce = v));
        p.Controls.Add(Slider("Stance", Design.Gait.Stance, v => Design.Gait.Stance = v));
        p.Controls.Add(Slider("Bounciness", Design.Gait.Bounciness, v => Design.Gait.Bounciness = v));
        p.Controls.Add(Combo("Leg Motion", Design.Gait.Motion, v => Design.Gait.Motion = v));
        p.Controls.Add(Check("New leg rig", Design.Gait.NewLegs, v => Design.Gait.NewLegs = v));
        return p;
    }

    Control BuildHabits()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("How often?"));
        p.Controls.Add(Note("0 = never · 0.5 = as usual · 1 = every chance it gets. The ▶ button shows it in the live terrarium where it can."));
        var dials = Design.Habits.Dials;
        string[] groups = { "Getting About", "Antics", "Quiet Moments", "With You" };
        int[] ends = { 7, 16, 23, dials.Count };
        int start = 0;
        for (int g = 0; g < groups.Length; g++)
        {
            p.Controls.Add(Heading(groups[g]));
            for (; start < ends[g]; start++)
            {
                var local = dials[start];
                string name = local.name;
                p.Controls.Add(Slider(name, local.get(), v => local.set(v), () => DemoHabit(name)));
            }
        }
        return p;
    }

    Control BuildThoughts()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("Inner life"));
        p.Controls.Add(Check("Let it think and chat", Design.Intelligence, v => Design.Intelligence = v));
        p.Controls.Add(new Label
        {
            Text = "Voice: " + _app.VoiceSummary, AutoSize = true, MaximumSize = new Size(390, 0),
            ForeColor = Color.FromArgb(90, 80, 70), Margin = new Padding(0, 2, 0, 5)
        });
        p.Controls.Add(Btn("Talk to it now…", _app.OpenChat));
        p.Controls.Add(Btn("Try a chat (hello)", () => _app.ChatForTest("hello")));
        p.Controls.Add(Note("The built-in companion voice is always ready and runs entirely on this PC. It is not a language model; its replies are written here, and a cloud or local model can take its place later."));
        p.Controls.Add(Check("Voice pictures into words", Design.VoicePictures, v => Design.VoicePictures = v));
        p.Controls.Add(Slider("How often it thinks out loud", Design.Habits.Muse, v => Design.Habits.Muse = v,
            () => _app.Spider.ThinkOf(ThoughtKind.Text, "hmm")));
        p.Controls.Add(new Label { Text = "Manner", AutoSize = true, Margin = new Padding(0, 7, 0, 2) });
        var manner = new TextBox { Width = 390, Height = 54, Multiline = true, Text = Design.Manner };
        manner.TextChanged += (_, _) => Design.Manner = manner.Text;
        p.Controls.Add(manner);
        var chips = new FlowLayoutPanel { Width = 400, Height = 30, WrapContents = false, Margin = new Padding(0) };
        foreach (var idea in new[] { "Cheerful", "Silly", "Shy", "Dramatic", "Sleepy", "Pirate" })
        {
            var b = new Button { Text = idea, Width = 62, Height = 24, Margin = new Padding(0, 0, 4, 0), Tag = idea };
            b.Click += (_, _) =>
            {
                var parts = Design.Manner.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).ToList();
                if (!parts.Remove(idea)) parts.Add(idea.ToLowerInvariant());
                Design.Manner = string.Join(", ", parts);
                manner.Text = Design.Manner;
            };
            chips.Controls.Add(b);
        }
        p.Controls.Add(chips);
        p.Controls.Add(Heading("Thought packs"));
        foreach (var pack in new[] { "chitchat", "nature", "food", "home", "weather", "spider", "sleepy" })
        {
            var local = pack;
            p.Controls.Add(Check(local, Design.Packs.Contains(local), v =>
            {
                if (v && !Design.Packs.Contains(local)) Design.Packs.Add(local);
                if (!v) Design.Packs.Remove(local);
            }));
        }
        p.Controls.Add(Heading("Custom phrases"));
        var phrases = new TextBox { Width = 390, Height = 80, Multiline = true, Text = string.Join(Environment.NewLine, Design.CustomPhrases) };
        phrases.TextChanged += (_, _) => Design.CustomPhrases = phrases.Lines.Where(x => !string.IsNullOrWhiteSpace(x)).ToList();
        p.Controls.Add(phrases);
        p.Controls.Add(Btn("Think Something Now", () => _app.Spider.ThinkOf(ThoughtKind.Heart)));
        return p;
    }

    Control BuildLibrary()
    {
        var p = PagePanel();
        p.Controls.Add(Heading("My Spiders"));
        p.Controls.Add(Note("Spiders you've kept. Click a card to bring it out. Changes in the Studio go to the spider that's out, and only reach its card here when you press Save."));
        var cards = new FlowLayoutPanel
        {
            Width = 390, Height = 190, FlowDirection = FlowDirection.TopDown, WrapContents = false,
            AutoScroll = true, Margin = new Padding(0, 2, 0, 6), BackColor = Color.Transparent
        };
        void RefreshCards()
        {
            cards.Controls.Clear();
            var saved = _app.Library.All().ToList();
            if (saved.Count == 0)
            {
                cards.Controls.Add(new Label
                {
                    Text = "No spiders kept yet. Design one, then press Save.", Width = 360, Height = 40,
                    ForeColor = Color.FromArgb(120, 110, 100), Margin = new Padding(2, 8, 0, 0)
                });
            }
            foreach (var s in saved)
            {
                var local = s;
                bool current = s.Id == _app.Library.CurrentID;
                var card = new Panel
                {
                    Width = 368, Height = 58, Margin = new Padding(0, 0, 0, 5), Cursor = Cursors.Hand,
                    BackColor = current ? Color.FromArgb(241, 231, 214) : Color.FromArgb(255, 252, 246),
                    BorderStyle = BorderStyle.FixedSingle
                };
                var swatch = new Panel
                {
                    Location = new Point(9, 10), Size = new Size(36, 36),
                    BackColor = current ? Color.FromArgb(184, 151, 111) : Color.FromArgb(207, 193, 172)
                };
                var name = new Label
                {
                    Text = s.Name + (current ? "  · out now" : ""), Location = new Point(54, 8), Width = 280, Height = 20,
                    Font = new Font("Segoe UI Semibold", 9.5f), ForeColor = Color.FromArgb(63, 54, 46)
                };
                var meta = new Label
                {
                    Text = $"{s.Design.Look.Body} · {s.Design.Look.Hat} · {s.Design.Look.Eyes}",
                    Location = new Point(54, 29), Width = 300, Height = 18,
                    ForeColor = Color.FromArgb(118, 106, 94), Font = new Font("Segoe UI", 7.8f)
                };
                var menu = new ContextMenuStrip();
                menu.Items.Add("Bring Out", null, (_, _) => BringOut(local.Id));
                menu.Items.Add("Make a Copy", null, (_, _) =>
                {
                    _app.Library.Create(local.Design);
                    RefreshCards();
                    RefreshKept();
                });
                menu.Items.Add("Delete…", null, (_, _) =>
                {
                    if (MessageBox.Show($"Delete {local.Name} from My Spiders?", "Spider Buddy",
                            MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
                    _app.Library.Delete(local.Id);
                    RefreshCards();
                    RefreshKept();
                });
                void Choose() => BringOut(local.Id);
                card.Click += (_, _) => Choose();
                foreach (var child in new Control[] { swatch, name, meta })
                {
                    child.Cursor = Cursors.Hand;
                    child.Click += (_, _) => Choose();
                    child.ContextMenuStrip = menu;
                }
                card.ContextMenuStrip = menu;
                card.Controls.AddRange(new Control[] { swatch, name, meta });
                cards.Controls.Add(card);
            }
        }
        RefreshCards();
        p.Controls.Add(cards);
        p.Controls.Add(Btn("Save as a New Spider", SaveAsNew));
        p.Controls.Add(Btn("Start Over From Scratch", StartOver));
        p.Controls.Add(Note("Right-click a card to bring it out, copy it, or delete it. Memories are shared by every saved spider. Surprise Me and Start Over make a new spider, so saving can never overwrite the old one by accident."));
        return p;
    }

    bool NeedsKeeping => !_throwaway && (_app.Library.Current is not { } cur || !cur.Matches(Design));

    void RefreshKept()
    {
        if (_save is null) return;
        var cur = _app.Library.Current;
        bool same = cur?.Matches(Design) ?? false;
        _kept.Text = cur is null ? "Not saved in My Spiders" : same ? "✓ Saved in My Spiders" : "Changed since you saved it";
        _save.Enabled = cur is null || !same;
        _revert.Enabled = cur is not null && !same;
    }

    bool ConfirmLose(string before)
    {
        if (!NeedsKeeping) return true;
        string name = string.IsNullOrWhiteSpace(Design.Name) ? "your spider" : Design.Name;
        var result = MessageBox.Show($"Save {name} before {before}?\n\nIf you don't, it won't be in My Spiders.",
            "Spider Buddy", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
        if (result == DialogResult.Cancel) return false;
        if (result == DialogResult.Yes) SaveCurrent();
        return true;
    }

    void SaveCurrent()
    {
        var cur = _app.Library.Current;
        if (cur is null) { SaveAsNew(); return; }
        cur.Design = Design.Clone();
        _app.Library.Store(cur);
        _throwaway = false;
        _app.SaveAll(force: true);
        RefreshKept();
    }

    void SaveAsNew()
    {
        var s = _app.Library.Create(Design);
        if (s is null) return;
        Design.Name = s.Design.Name;
        _name.Text = Design.Name;
        _app.Library.CurrentID = s.Id;
        _throwaway = false;
        _app.SaveAll(force: true);
        RefreshKept();
        BuildTabs();
    }

    void RevertCurrent()
    {
        var saved = _app.Library.Current;
        var motion = Design.Gait.Motion;
        var d = saved?.Design.Clone() ?? _original.Clone();
        d.Gait.Motion = motion;
        _app.Spider.Design = d;
        _name.Text = d.Name;
        _throwaway = false;
        _app.SaveAll(quiet: true);
        BuildTabs();
    }

    void BringOut(string id)
    {
        if (id == _app.Library.CurrentID) return;
        if (!ConfirmLose("bringing out another spider")) return;
        var s = _app.Library.Saved(id);
        if (s is null) return;
        var motion = Design.Gait.Motion;
        var d = s.Design.Clone();
        d.Gait.Motion = motion;
        _app.Library.CurrentID = id;
        _app.Spider.Design = d;
        _name.Text = d.Name;
        _throwaway = false;
        _app.SaveAll(quiet: true);
        _app.Spider.Celebrate();
        BuildTabs();
    }

    void SurpriseMe()
    {
        if (!ConfirmLose("trying a new one")) return;
        var motion = Design.Gait.Motion;
        var newLegs = Design.Gait.NewLegs;
        var name = Design.Name;
        var random = SpiderDesign.Random(new Rng((ulong)Math.Max(1, DateTime.Now.Ticks)));
        random.Gait.Motion = motion;
        random.Gait.NewLegs = newLegs;
        random.Name = name;
        _app.Spider.Design = random;
        _app.Library.CurrentID = null;
        _name.Text = name;
        _throwaway = true;
        _app.SaveAll(quiet: true);
        _app.Spider.Celebrate();
        BuildTabs();
        RefreshKept();
    }

    void StartOver()
    {
        if (!ConfirmLose("starting over")) return;
        var name = Design.Name;
        var fresh = new SpiderDesign { Name = name };
        _app.Spider.Design = fresh;
        _app.Library.CurrentID = null;
        _name.Text = name;
        _throwaway = true;
        _app.SaveAll(quiet: true);
        BuildTabs();
        RefreshKept();
    }

    Button Btn(string text, Action action)
    {
        var b = new Button { Text = text, Width = 390, Height = 28, TextAlign = ContentAlignment.MiddleLeft, Margin = new Padding(0, 2, 0, 2) };
        b.Click += (_, _) => action();
        return b;
    }

    void PickColour(Action<Rgba> set)
    {
        using var dialog = new ColorDialog { FullOpen = true };
        var current = Design.Look.CustomAccent ?? Design.Look.Accent;
        dialog.Color = Color.FromArgb((int)(current.R * 255), (int)(current.G * 255), (int)(current.B * 255));
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        set(new Rgba(dialog.Color.R / 255.0, dialog.Color.G / 255.0, dialog.Color.B / 255.0, 1));
    }

    static readonly string[] RandomNames =
    {
        "Mochi", "Pebble", "Juniper", "Noodle", "Saffron", "Ink", "Pickle", "Moth",
        "Cocoa", "Sprout", "Tofu", "Marble", "Poppy", "Biscuit", "Clover", "Waffle",
        "Fig", "Miso", "Olive", "Pip", "Sesame", "Thimble", "Nettle", "Dumpling"
    };

    void RandomName()
    {
        var name = RandomNames[Random.Shared.Next(RandomNames.Length)];
        var used = new HashSet<string>(_app.Library.All().Select(s => s.Name), StringComparer.OrdinalIgnoreCase);
        if (used.Contains(name)) name += " " + Random.Shared.Next(2, 99);
        Design.Name = name;
        _name.Text = name;
        RefreshKept();
    }

    void DemoHabit(string name)
    {
        if (name is "Building a hammock" or "Napping in the hammock")
        {
            if (name == "Building a hammock") _app.BuildHammock(); else _app.NapHammock();
            return;
        }
        _preview.Demo(name);
    }

    public void ShowTabForCapture(int index) => SelectTab(index);
}
