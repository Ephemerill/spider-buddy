using System.Drawing.Drawing2D;
using WinForms = System.Windows.Forms;

namespace SpiderBuddy.App;

/// <summary>A dimmed, borderless spotlight tour over the tank (Swift HabitatTour).</summary>
public sealed class HabitatTourOverlay : Form
{
    public const string SeenKey = "habitatTourSeen";
    public const string DecoratingSeenKey = "habitatDecorateTourSeen";

    readonly HabitatWindow _owner;
    readonly bool _decorating;
    readonly TourStep[] _steps;
    int _index;
    Rectangle? _spot;
    Rectangle _card;
    Rectangle _next, _back, _skip;

    sealed record TourStep(string Title, string Text, string Symbol, string? Target);

    static readonly TourStep[] TankSteps =
    {
        new("Welcome to the habitat", "This is your spider’s very own tank — a little world, much bigger than the window. In here it explores, climbs, hunts, shelters from the weather and sleeps, all on its own.", "✦", null),
        new("Look around", "Drag the glass to look round the tank, scroll sideways, or use the arrow keys. You can pick your spider up, too.", "✥", "glass"),
        new("The map", "The whole tank at a glance. Click anywhere on it to go there — your spider is marked, so you can always find it.", "▦", "map"),
        new("Feeding time", "Let a fly, a cricket or a moth loose for your spider to hunt. Creatures find their own way in now and then, too — what comes depends on what’s in the tank.", "♨", "feed"),
        new("Weather", "The tank has weather of its own, and your spider feels it: it gets soaked in the rain and runs for cover when it pours.", "☁", "weather"),
        new("Make it yours", "Decorate the tank: change the scenery, add plants, rocks, logs and even a little house — and save your habitats to come back to later.", "✎", "decorate"),
        new("Letting it out", "When you’re done, let your spider back out onto your desktop. Closing the window does the same — the tank stays just as you left it.", "↩", "letout")
    };

    static readonly TourStep[] DecoratingSteps =
    {
        new("Add things", "Pick something here to drop it into the tank — plants, rocks, logs, shelters, even furniture for a little house. Search for something, or show just one kind.", "＋", "add"),
        new("Move things about", "Click anything in the tank to pick it. Drag it to move it; drag a corner to make it bigger or smaller.", "☞", "glass"),
        new("Change what you picked", "The inspector flips it, makes another, puts it in front of your spider or behind it, opens and shuts doors, or takes it out.", "☰", "inspector"),
        new("Scenery", "The backdrop behind the glass — a forest, a desert, a beach… Everything in the tank stays where it is.", "▣", "scenery"),
        new("My Habitats", "Save the tank as it is, and come back to it whenever you like — have a few, and swap between them. Or start afresh from a ready-made one.", "▤", "habitats"),
        new("Changed your mind?", "Undo takes anything back (Ctrl+Z). Redo puts it forward again (Ctrl+Shift+Z).", "↶", "undo"),
        new("All done?", "Click Done when you’re happy. The tank keeps itself just as you leave it.", "✓", "decorate")
    };

    public HabitatTourOverlay(HabitatWindow owner, bool decorating)
    {
        _owner = owner; _decorating = decorating;
        _steps = decorating ? DecoratingSteps : TankSteps;
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        BackColor = Color.Black;
        DoubleBuffered = true;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
        Bounds = owner.Bounds;
        KeyPreview = true;
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        Bounds = _owner.Bounds;
        if (_decorating)
        {
            _owner.Panel.ShowTab("add");
            _owner.Panel.Visible = true;
        }
        ShowStep(0);
    }

    void ShowStep(int index)
    {
        _index = Math.Clamp(index, 0, _steps.Length - 1);
        if (_decorating)
        {
            string tab = _steps[_index].Target is "scenery" or "habitats" ? _steps[_index].Target! : "add";
            _owner.Panel.ShowTab(tab);
        }
        var target = _steps[_index].Target;
        _spot = null;
        if (target is not null)
        {
            var screen = _owner.TourTarget(target);
            if (!screen.IsEmpty)
            {
                var topLeft = PointToClient(screen.Location);
                _spot = new Rectangle(topLeft, screen.Size);
                _spot = Rectangle.Inflate(_spot.Value, 7, 7);
            }
        }
        LayoutCard();
        Invalidate();
    }

    void LayoutCard()
    {
        int w = Math.Min(360, Math.Max(280, Width - 32));
        int h = 226;
        _card = new Rectangle(Width - w - 26, Height - h - 30, w, h);
        if (_spot is { } spot && Math.Abs((spot.Top + spot.Height / 2) - (_card.Top + _card.Height / 2)) < 170)
            _card = new Rectangle(26, Height - h - 30, w, h);
        _next = new Rectangle(_card.Right - 104, _card.Bottom - 46, 88, 31);
        _back = new Rectangle(_card.Left + 16, _card.Bottom - 46, 76, 31);
        _skip = new Rectangle(_card.Left + 100, _card.Bottom - 42, 100, 26);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        using (var dim = new GraphicsPath { FillMode = FillMode.Winding })
        {
            dim.AddRectangle(ClientRectangle);
            if (_spot is { } hole) dim.AddEllipse(hole);
            using var shade = new SolidBrush(Color.FromArgb(170, 4, 7, 5));
            g.FillPath(shade, dim);
        }
        if (_spot is { } spot)
        {
            using var glow = new Pen(Color.FromArgb(220, 243, 193, 102), 3);
            g.DrawEllipse(glow, spot);
            using var halo = new Pen(Color.FromArgb(45, 243, 193, 102), 13);
            g.DrawEllipse(halo, spot);
        }
        using (var card = new LinearGradientBrush(_card, Color.FromArgb(242, 43, 47, 40), Color.FromArgb(246, 30, 33, 28), 90f))
            g.FillRectangle(card, _card);
        using var edge = new Pen(Color.FromArgb(120, 205, 172, 104), 1);
        g.DrawRectangle(edge, _card);

        var s = _steps[_index];
        using var iconFont = new Font("Segoe UI Symbol", 17f);
        using var iconBrush = new SolidBrush(Color.FromArgb(234, 197, 121));
        g.DrawString(s.Symbol, iconFont, iconBrush, _card.Left + 20, _card.Top + 16);
        using var titleFont = new Font("Segoe UI Semibold", 13f);
        using var titleBrush = new SolidBrush(Color.FromArgb(248, 235, 205));
        g.DrawString(s.Title, titleFont, titleBrush, _card.Left + 56, _card.Top + 17);
        using var bodyFont = new Font("Segoe UI", 10f);
        using var bodyBrush = new SolidBrush(Color.FromArgb(220, 214, 199));
        var body = new Rectangle(_card.Left + 20, _card.Top + 58, _card.Width - 40, 104);
        g.DrawString(s.Text, bodyFont, bodyBrush, body);
        using var count = new SolidBrush(Color.FromArgb(150, 147, 133));
        g.DrawString($"{_index + 1} / {_steps.Length}", bodyFont, count, _card.Left + 20, _card.Bottom - 36);
        DrawButton(g, _back, "Back", _index > 0);
        DrawButton(g, _next, _index == _steps.Length - 1 ? "Done" : "Next", true);
        DrawButton(g, _skip, "Skip Tour", true);
        using var hint = new Font("Segoe UI", 8.5f);
        g.DrawString("Return / → next   ·   ← back   ·   Esc skip", hint,
            new SolidBrush(Color.FromArgb(130, 139, 137, 124)), _card.Left + 20, _card.Bottom - 18);
    }

    static void DrawButton(Graphics g, Rectangle r, string text, bool on)
    {
        using var fill = new SolidBrush(on ? Color.FromArgb(70, 75, 61) : Color.FromArgb(45, 48, 41));
        g.FillRectangle(fill, r);
        using var edge = new Pen(on ? Color.FromArgb(158, 143, 104) : Color.FromArgb(75, 78, 69));
        g.DrawRectangle(edge, r);
        TextRenderer.DrawText(g, text, new Font("Segoe UI Semibold", 9f), r,
            on ? Color.FromArgb(245, 236, 215) : Color.FromArgb(130, 128, 118),
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter);
    }

    void Next() { if (_index >= _steps.Length - 1) Finish(); else ShowStep(_index + 1); }
    void Back() { if (_index > 0) ShowStep(_index - 1); }
    void Finish() { DialogResult = DialogResult.OK; Close(); }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        if (keyData is Keys.Escape) { Finish(); return true; }
        if (keyData is Keys.Right or Keys.Enter or Keys.Space) { Next(); return true; }
        if (keyData is Keys.Left) { Back(); return true; }
        return base.ProcessCmdKey(ref msg, keyData);
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (_next.Contains(e.Location)) Next();
        else if (_back.Contains(e.Location)) Back();
        else if (_skip.Contains(e.Location)) Finish();
        else if (_spot is { } spot && !spot.Contains(e.Location) && !_card.Contains(e.Location)) Next();
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        LayoutCard();
    }
}
