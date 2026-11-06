using System.Drawing.Drawing2D;
using SpiderBuddy.Core;

namespace SpiderBuddy.App;

/// <summary>
/// The cream pill opened by clicking the spider's bubble (spec 18.1). It is a small topmost
/// tool window beside the spider; Return sends, Esc or clicking elsewhere closes it.
/// </summary>
public sealed class ChatForm : Form
{
    public static readonly Color Ink = Color.FromArgb(56, 36, 20);
    public static readonly Color Paper = Color.FromArgb(255, 250, 240);
    public static readonly Color Rim = Color.FromArgb(77, 46, 23);
    static readonly Color Backdrop = Color.FromArgb(248, 246, 241);

    readonly TextBox _field = new();
    readonly Button _send = new();
    string _name = "Spider";
    bool _waiting;
    bool _tailUp = true;
    int _tailX = 150;

    public event Action<string>? OnSend;
    public event Action? Dismissed;

    public ChatForm()
    {
        Text = "Talk to your spider";
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
        ClientSize = new Size(304, 62);
        BackColor = Paper;
        DoubleBuffered = true;
        Font = new Font("Segoe UI", 10f);

        _field.BorderStyle = BorderStyle.None;
        _field.BackColor = Paper;
        _field.ForeColor = Ink;
        _field.Font = new Font("Segoe UI", 10.5f);
        _field.PlaceholderText = "Say something…";
        _field.MaxLength = 200;
        _field.KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Enter)
            {
                e.SuppressKeyPress = true;
                SendNow();
            }
        };
        _field.TextChanged += (_, _) => RefreshSend();
        Controls.Add(_field);

        _send.FlatStyle = FlatStyle.Flat;
        _send.FlatAppearance.BorderSize = 0;
        _send.BackColor = Paper;
        _send.Cursor = Cursors.Hand;
        _send.TabStop = false;
        _send.Click += (_, _) => SendNow();
        _send.Paint += PaintSend;
        Controls.Add(_send);
        LayoutInside();
    }

    protected override bool ShowWithoutActivation => false;

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
            return cp;
        }
    }

    public void OpenChat(string name, Point anchor, Rectangle? bubble)
    {
        _name = string.IsNullOrWhiteSpace(name) ? "Spider" : name;
        _field.Text = "";
        _waiting = false;
        _field.PlaceholderText = $"Say something to {_name}…";
        _field.Enabled = true;
        RefreshSend();
        Place(anchor, bubble);
        if (!Visible) Show();
        BringToFront();
        Activate();
        BeginInvoke(() => { _field.Focus(); });
    }

    public void SetWaiting(bool waiting)
    {
        _waiting = waiting;
        _field.Enabled = !waiting;
        _field.PlaceholderText = waiting ? $"{_name} is thinking…" : $"Say something to {_name}…";
        RefreshSend();
    }

    public void Dismiss()
    {
        if (!Visible) return;
        Hide();
        _waiting = false;
        Dismissed?.Invoke();
    }

    public void DebugSend(string text)
    {
        _field.Text = text;
        SendNow();
    }

    void SendNow()
    {
        if (_waiting) return;
        string text = _field.Text.Trim();
        if (text.Length == 0) return;
        _field.Text = "";
        OnSend?.Invoke(text);
    }

    void RefreshSend()
    {
        if (_send is null) return;
        _send.Enabled = !_waiting && _field.Text.Trim().Length > 0;
        _send.Invalidate();
    }

    void Place(Point anchor, Rectangle? bubble)
    {
        var screen = Screen.FromPoint(anchor);
        var work = screen.WorkingArea;
        int x = Math.Clamp(anchor.X - ClientSize.Width / 2, work.Left + 6, work.Right - ClientSize.Width - 6);
        int below = anchor.Y + 34;
        bool up = below + ClientSize.Height <= work.Bottom;
        int y = up ? below : Math.Max(work.Top + 4, anchor.Y - ClientSize.Height - 12);
        if (!up && bubble is { } b && b.Top - ClientSize.Height - 6 > work.Top) y = b.Top - ClientSize.Height - 6;
        _tailUp = up;
        int tail = Math.Clamp(anchor.X - x, 28, ClientSize.Width - 28);
        if (tail != _tailX || _tailUp)
        {
            _tailX = tail;
            LayoutInside();
        }
        Bounds = new Rectangle(x, y, ClientSize.Width, ClientSize.Height);
        UpdateRegion();
        Invalidate();
    }

    void LayoutInside()
    {
        int bodyTop = _tailUp ? 10 : 0;
        int bodyHeight = ClientSize.Height - 10;
        int bodyBottom = bodyTop + bodyHeight;
        _send.SetBounds(ClientSize.Width - 45, bodyTop + (bodyHeight - 30) / 2, 30, 30);
        _field.SetBounds(22, bodyTop + (bodyHeight - 24) / 2, ClientSize.Width - 78, 24);
    }

    protected override void OnSizeChanged(EventArgs e)
    {
        base.OnSizeChanged(e);
        if (_field is not null && _send is not null) LayoutInside();
        UpdateRegion();
    }

    void UpdateRegion()
    {
        if (ClientSize.Width <= 0 || ClientSize.Height <= 0) return;
        using var path = BodyPath();
        Region?.Dispose();
        Region = new Region(path);
    }

    GraphicsPath BodyPath()
    {
        int bodyTop = _tailUp ? 10 : 0;
        int bodyHeight = ClientSize.Height - 10;
        var body = new Rectangle(1, bodyTop, ClientSize.Width - 2, bodyHeight - 1);
        var path = new GraphicsPath();
        int r = Math.Max(8, body.Height / 2);
        path.AddArc(body.Left, body.Top, r, r, 180, 90);
        path.AddArc(body.Right - r, body.Top, r, r, 270, 90);
        path.AddArc(body.Right - r, body.Bottom - r, r, r, 0, 90);
        path.AddArc(body.Left, body.Bottom - r, r, r, 90, 90);
        path.CloseFigure();
        if (_tailUp)
        {
            path.AddPolygon(new[]
            {
                new Point(_tailX - 8, bodyTop + 1), new Point(_tailX, 0), new Point(_tailX + 8, bodyTop + 1)
            });
        }
        else
        {
            path.AddPolygon(new[]
            {
                new Point(_tailX - 8, body.Bottom - 1), new Point(_tailX, ClientSize.Height - 1),
                new Point(_tailX + 8, body.Bottom - 1)
            });
        }
        return path;
    }

    protected override void OnPaintBackground(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Backdrop);
        using var path = BodyPath();
        using var fill = new SolidBrush(Paper);
        using var pen = new Pen(Rim, 2.2f);
        e.Graphics.FillPath(fill, path);
        e.Graphics.DrawPath(pen, path);
    }

    void PaintSend(object? sender, PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        var r = new Rectangle(2, 2, _send.Width - 5, _send.Height - 5);
        using var fill = new SolidBrush(_send.Enabled ? Rim : Color.FromArgb(38, Ink));
        g.FillEllipse(fill, r);
        using var pen = new Pen(_send.Enabled ? Paper : Color.FromArgb(180, Paper), 2f)
        {
            StartCap = System.Drawing.Drawing2D.LineCap.Round, EndCap = System.Drawing.Drawing2D.LineCap.Round,
            LineJoin = System.Drawing.Drawing2D.LineJoin.Round
        };
        float cx = r.Left + r.Width / 2f, cy = r.Top + r.Height / 2f;
        g.DrawLine(pen, cx, cy + 6, cx, cy - 6);
        g.DrawLine(pen, cx - 5, cy - 1, cx, cy - 6);
        g.DrawLine(pen, cx + 5, cy - 1, cx, cy - 6);
    }

    protected override void OnDeactivate(EventArgs e)
    {
        base.OnDeactivate(e);
        Dismiss();
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
    {
        if (keyData == Keys.Escape)
        {
            Dismiss();
            return true;
        }
        return base.ProcessCmdKey(ref msg, keyData);
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Dismiss();
            return;
        }
        base.OnFormClosing(e);
    }
}
