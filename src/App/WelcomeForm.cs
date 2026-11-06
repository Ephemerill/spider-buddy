namespace SpiderBuddy.App;

/// <summary>
/// The first-run tour: a hello with the spider sitting on its ledge, where
/// its panel lives, and the house rules, then on to the Studio (spec 16.6).
/// The same 920×600 frame as the Studio, and the same generic copy for
/// everyone.
/// </summary>
public sealed class WelcomeForm : Form
{
    readonly SpiderApplicationContext _app;
    readonly Label _title = new();
    readonly Label _body = new();
    readonly FlowLayoutPanel _rules = new();
    readonly Button _skip = new() { Text = "Skip", Width = 90 };
    readonly Button _next = new() { Text = "Next", Width = 190 };
    readonly Panel _visual = new();
    readonly SittingSpiderControl _sitter;
    readonly PictureBox _panelPicture = new() { Dock = DockStyle.Fill, SizeMode = PictureBoxSizeMode.Zoom };
    readonly Label _dots = new() { AutoSize = false, Width = 100, Height = 20, TextAlign = ContentAlignment.MiddleCenter };
    readonly CheckBox _wildlife;
    readonly CheckBox _visitors;
    readonly CheckBox _traces;
    readonly CheckBox _learn;
    readonly CheckBox _weather;
    readonly CheckBox _login;
    readonly Label _smallPrint = new() { AutoSize = false, Width = 405, Height = 34, ForeColor = Color.Gray };
    int _page;

    public WelcomeForm(SpiderApplicationContext app)
    {
        _app = app;
        Text = "Welcome";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterScreen;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(920, 600);
        BackColor = Color.FromArgb(248, 245, 238);

        _wildlife = new CheckBox { Text = "Wandering bugs", AutoSize = false, Width = 178, Height = 22, Checked = app.Spider.WildlifeEnabled };
        _visitors = new CheckBox { Text = "Visiting spiders", AutoSize = false, Width = 178, Height = 22, Checked = app.Spider.VisitorsEnabled };
        _traces = new CheckBox { Text = "Traces", AutoSize = false, Width = 178, Height = 22, Checked = app.Spider.LeaveTraces };
        _learn = new CheckBox { Text = "Learns as it goes", AutoSize = false, Width = 178, Height = 22, Checked = app.Spider.Memory.LearnFromExperience };
        _weather = new CheckBox { Text = "Notices the weather", AutoSize = false, Width = 178, Height = 22, Checked = app.Spider.FeelWeather };
        _login = new CheckBox { Text = "Open at login", AutoSize = false, Width = 178, Height = 22, Checked = app.Settings.GetBool("launchAtLogin", false) };

        _visual.Location = new Point(28, 34);
        _visual.Size = new Size(405, 470);
        _visual.BackColor = Color.FromArgb(243, 237, 228);
        _sitter = new SittingSpiderControl(app) { Dock = DockStyle.Fill };
        _visual.Controls.Add(_sitter);
        _panelPicture.Visible = false;
        _visual.Controls.Add(_panelPicture);
        try
        {
            using var snap = new PanelForm(app).Snapshot();
            _panelPicture.Image = new Bitmap(snap);
        }
        catch { }

        _title.Font = new Font("Segoe UI Semibold", 23f);
        _title.AutoSize = true;
        _title.MaximumSize = new Size(405, 0);
        _title.Location = new Point(468, 72);
        _title.Size = new Size(405, 110);
        _body.Location = new Point(470, 208);
        _body.AutoSize = true;
        _body.MaximumSize = new Size(405, 0);
        _body.Size = new Size(405, 110);
        _body.Font = new Font("Segoe UI", 9.5f);
        _body.ForeColor = Color.FromArgb(90, 82, 74);

        _rules.Location = new Point(470, 286);
        _rules.Size = new Size(410, 292);
        _rules.FlowDirection = FlowDirection.LeftToRight;
        _rules.WrapContents = true;
        Control RuleCard(CheckBox check, string detail)
        {
            check.Location = new Point(7, 5);
            check.AutoSize = false;
            check.Width = 178;
            check.Height = 24;
            check.Font = new Font("Segoe UI", 8f);
            var card = new Panel
            {
                Width = 194, Height = 78, Margin = new Padding(0, 0, 4, 4),
                BackColor = Color.FromArgb(255, 252, 246), BorderStyle = BorderStyle.FixedSingle
            };
            var text = new Label
            {
                Text = detail, Location = new Point(7, 30), Size = new Size(178, 42),
                ForeColor = Color.FromArgb(116, 105, 94), Font = new Font("Segoe UI", 7.5f)
            };
            card.Controls.AddRange(new Control[] { check, text });
            return card;
        }
        _rules.Controls.Add(RuleCard(_wildlife, "Little creatures wander in."));
        _rules.Controls.Add(RuleCard(_visitors, "Other spiders visit, up to five."));
        _rules.Controls.Add(RuleCard(_traces, "A faint silk line behind it."));
        _rules.Controls.Add(RuleCard(_learn, "It remembers places and you."));
        _rules.Controls.Add(RuleCard(_weather, "It notices rain and sunshine."));
        _rules.Controls.Add(RuleCard(_login, "Start with Windows, already home."));
        _smallPrint.Text = "Visitors are opt-in and capped at five; they never bring an energy alert.";
        _smallPrint.Width = 405;
        _smallPrint.Height = 22;
        _smallPrint.Margin = new Padding(0, 2, 0, 2);
        _smallPrint.Visible = _visitors.Checked;
        _visitors.CheckedChanged += (_, _) => _smallPrint.Visible = _visitors.Checked;
        _rules.Controls.Add(_smallPrint);

        _skip.Location = new Point(28, 548);
        _skip.Height = 34;
        _next.Location = new Point(700, 548);
        _next.Height = 38;
        _dots.Location = new Point(410, 560);
        _skip.Click += (_, _) => { DialogResult = DialogResult.Cancel; Close(); };
        _next.Click += (_, _) =>
        {
            if (_page < 2) { _page++; ShowPage(); }
            else Finish();
        };
        Controls.AddRange(new Control[] { _visual, _title, _body, _rules, _skip, _next, _dots });
        ShowPage();
    }

    void ShowPage()
    {
        _visual.Visible = _page < 2;
        _sitter.Visible = _page == 0;
        _panelPicture.Visible = _page == 1;
        _rules.Visible = _page == 2;
        _rules.Location = new Point(470, _page == 2 ? 274 : 208);
        _body.Visible = _page < 2;
        _skip.Visible = _page < 2;
        _next.Text = _page == 2 ? "Design Your Spider" : "Next";
        _dots.Text = _page == 0 ? "● ○ ○" : _page == 1 ? "○ ● ○" : "○ ○ ●";
        switch (_page)
        {
            case 0:
                _title.Text = "Say hello to your spider.";
                _body.Text = "A little jumping spider is about to move onto your screen. It walks along the edges of "
                    + "your windows, leaps between them, swings on silk, naps in a hammock it spins itself, and "
                    + "keeps an eye on you the whole time.\n\nYou can pick it up and throw it, stroke it with the "
                    + "pointer, feed it, or just let it get on with its day.";
                break;
            case 1:
                _title.Text = "It’ll live in your notification area.";
                _body.Text = "Down by the clock there’s a little spider. Click it and a panel opens with everything "
                    + "it can do, a page for each.\n\nSpider, Play and Feed · Behavior, Visitors and Your PC. "
                    + "Spider Studio sits at the bottom: how it looks, how it walks, and who it is.\n\n"
                    + "Right-click the spider for a quick menu, right where it is. Any moment now, it’ll "
                    + "let itself down and move in.";
                break;
            default:
                _title.Text = "But first, a few house rules.";
                _body.Visible = true;
                _body.Text = "How lively would you like things? Pick what suits you, and it’ll move in just so.";
                break;
        }
    }

    void Finish()
    {
        _app.ApplyWelcome(_wildlife.Checked, _visitors.Checked, _traces.Checked,
            _learn.Checked, _weather.Checked, _login.Checked);
        DialogResult = DialogResult.OK;
        Close();
    }

    public void ShowPageForCapture(int page)
    {
        _page = Math.Clamp(page, 0, 2);
        ShowPage();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        _sitter.Dispose();
        if (DialogResult == DialogResult.OK) base.OnFormClosing(e);
        else { DialogResult = DialogResult.Cancel; base.OnFormClosing(e); }
    }
}
