using System.Net.Http;
using System.Text;
using System.Text.Json;
using SpiderBuddy.Core;

namespace SpiderBuddy.App;

/// <summary>
/// Report a Bug from the App page (spec 16.8): a name, what went wrong,
/// optional system details and a screenshot. Reports go to the Worker
/// endpoint in SPIDER_BUG_ENDPOINT; no webhook secret is in the app.
/// </summary>
public sealed class BugReportForm : Form
{
    readonly SpiderLook _look;
    readonly TextBox _name = new() { Width = 420 };
    readonly TextBox _description = new() { Width = 420, Height = 190, Multiline = true, ScrollBars = ScrollBars.Vertical };
    readonly CheckBox _system = new() { Text = "Include system info", Checked = true, AutoSize = true };
    readonly CheckBox _screenshot = new() { Text = "Include a screenshot of this display", Checked = false, AutoSize = true };
    readonly Label _status = new() { AutoSize = false, Width = 420, Height = 42, ForeColor = Color.FromArgb(100, 90, 80) };
    readonly Button _send = new() { Text = "Send Report", Width = 120, Height = 30 };
    readonly Button _cancel = new() { Text = "Cancel", Width = 80, Height = 30 };
    bool _sending;

    public BugReportForm(SpiderLook look)
    {
        _look = look;
        Text = "Report a Bug";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(500, 610);
        BackColor = Color.FromArgb(248, 245, 238);

        Controls.Add(new Label
        {
            Text = "Report a Bug", AutoSize = true, Location = new Point(28, 22),
            Font = new Font("Segoe UI Semibold", 20f)
        });
        Controls.Add(new Label
        {
            Text = "Tell me what happened. Nothing on your screen is read unless you include the screenshot.",
            AutoSize = false, Width = 440, Height = 42, Location = new Point(30, 70),
            ForeColor = Color.FromArgb(100, 90, 80)
        });
        Controls.Add(new Label { Text = "Your name (optional)", AutoSize = true, Location = new Point(30, 122) });
        _name.Location = new Point(30, 146);
        Controls.Add(_name);
        Controls.Add(new Label { Text = "What went wrong?", AutoSize = true, Location = new Point(30, 184) });
        _description.Location = new Point(30, 208);
        Controls.Add(_description);
        _system.Location = new Point(30, 410);
        _screenshot.Location = new Point(30, 438);
        Controls.AddRange(new Control[] { _system, _screenshot });
        var peek = new Button { Text = "See what’s sent", Width = 130, Height = 26, Location = new Point(30, 470) };
        peek.Click += (_, _) => MessageBox.Show(SystemInfoText(), "What’s sent", MessageBoxButtons.OK, MessageBoxIcon.Information);
        Controls.Add(peek);
        _status.Location = new Point(30, 500);
        _status.Text = "";
        Controls.Add(_status);
        _send.Location = new Point(330, 556);
        _cancel.Location = new Point(230, 556);
        _send.Click += async (_, _) => await Send();
        _cancel.Click += (_, _) => Close();
        Controls.AddRange(new Control[] { _send, _cancel });
    }

    async Task Send()
    {
        if (_sending) return;
        string description = _description.Text.Trim();
        if (description.Length == 0)
        {
            _status.Text = "Please describe what went wrong.";
            return;
        }
        string? endpoint = Environment.GetEnvironmentVariable("SPIDER_BUG_ENDPOINT")
            ?? "https://spider-buddy-reports.ephemerill.workers.dev";
        if (string.IsNullOrWhiteSpace(endpoint) || !Uri.TryCreate(endpoint, UriKind.Absolute, out var uri))
        {
            _status.Text = "Bug reports aren’t set up in this copy, so it couldn’t be sent.";
            return;
        }
        _sending = true;
        _send.Enabled = false;
        _status.Text = "Sending…";
        try
        {
            var payload = new
            {
                username = "Spider Buddy",
                allowed_mentions = new { parse = Array.Empty<string>() },
                embeds = new[]
                {
                    new
                    {
                        title = "🐞 Bug report",
                        description = description[..Math.Min(4000, description.Length)],
                        color = 0xD9822B,
                        author = new { name = string.IsNullOrWhiteSpace(_name.Text) ? "Anonymous" : _name.Text.Trim()[..Math.Min(100, _name.Text.Trim().Length)] },
                        fields = _system.Checked
                            ? SystemInfo().Select(kv => new { name = kv.Item1, value = kv.Item2, inline = true }).ToArray()
                            : new[] { new { name = "System info", value = "Not shared", inline = false } },
                        footer = new { text = "Spider Buddy " + UpdateService.CurrentVersion },
                        timestamp = DateTime.UtcNow.ToString("o")
                    }
                }
            };

            using var form = new MultipartFormDataContent();
            form.Add(new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json"), "payload_json");
            if (_screenshot.Checked)
            {
                try
                {
                    var bounds = SystemInformation.VirtualScreen;
                    using var bmp = new Bitmap(bounds.Width, bounds.Height);
                    using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size);
                    using var ms = new MemoryStream();
                    bmp.Save(ms, System.Drawing.Imaging.ImageFormat.Png);
                    form.Add(new ByteArrayContent(ms.ToArray()), "files[0]", "screenshot.png");
                }
                catch { }
            }

            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(180) };
            using var response = await http.PostAsync(uri, form);
            if (response.IsSuccessStatusCode)
            {
                _status.Text = "Sent. Thank you — it really helps.";
                _send.Text = "Done";
                _send.Enabled = true;
                _send.Click += (_, _) => Close();
                return;
            }
            _status.Text = response.StatusCode switch
            {
                System.Net.HttpStatusCode.RequestEntityTooLarge => "The screenshot was too big to send.",
                (System.Net.HttpStatusCode)429 => "Lots of reports are coming in just now. Give it a minute and try again.",
                _ => $"It couldn’t be sent ({(int)response.StatusCode}). Try again in a little while."
            };
        }
        catch (HttpRequestException)
        {
            _status.Text = "It couldn’t be sent: you seem to be offline. Check your connection and try again.";
        }
        catch (TaskCanceledException)
        {
            _status.Text = "It couldn’t be sent in time. Try again in a little while.";
        }
        finally
        {
            _sending = false;
            if (_send.Text != "Done") _send.Enabled = true;
        }
    }

    (string, string)[] SystemInfo() => new[]
    {
        ("App", "Spider Buddy " + UpdateService.CurrentVersion),
        ("Windows", Environment.OSVersion.VersionString),
        ("Machine", Environment.MachineName),
        ("Displays", string.Join(", ", Screen.AllScreens.Select(s => $"{s.Bounds.Width}×{s.Bounds.Height}@{s.Bounds.X},{s.Bounds.Y}"))),
        ("Language", System.Globalization.CultureInfo.CurrentUICulture.Name)
    };

    string SystemInfoText() => string.Join(Environment.NewLine, SystemInfo().Select(kv => $"{kv.Item1}: {kv.Item2}"));
}
