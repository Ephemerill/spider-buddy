using System.Diagnostics;
using System.Net.Http;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using SpiderBuddy.Core;

namespace SpiderBuddy.App;

/// <summary>A release found in the signed Windows appcast.</summary>
public sealed record UpdateRelease(string Version, string Notes, string Url, long Length, string Signature);

/// <summary>A downloaded, signature-checked installer waiting to run.</summary>
public sealed record PreparedUpdate(UpdateRelease Release, string Path);

/// <summary>
/// The signed Windows update feed. This is deliberately the same shape as the Mac's
/// Sparkle appcast, with a separate Windows Ed25519 key. The appcast binds its version,
/// installer URL, length, signature and notes; the installer itself is also Ed25519-signed.
/// The feed address is baked in and must never move.
/// </summary>
public static class UpdateService
{
    public const string FeedUrl = "https://ephemerill.github.io/spider-buddy/windows-appcast.xml";
    const string FeedResource = "SpiderBuddy.UpdatePublicKey";
    const int MostFeedBytes = UpdateFeed.MostFeedBytes;
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(25) };
    static readonly Lazy<string> BakedPublicKey = new(LoadBakedPublicKey, LazyThreadSafetyMode.ExecutionAndPublication);

    public static string CurrentVersion { get; } = ReadCurrentVersion();
    public static string PublicKey => Environment.GetEnvironmentVariable("SPIDER_UPDATE_PUBLIC_KEY") is { Length: > 0 } key
        ? key.Trim()
        : BakedPublicKey.Value;
    public static string Endpoint =>
        Environment.GetEnvironmentVariable("SPIDER_UPDATE_ENDPOINT") is { Length: > 0 } endpoint
            ? endpoint
            : FeedUrl;
    public static bool Testing => Environment.GetEnvironmentVariable("SPIDER_UPDATE_TEST") == "1";
    public static string UpdatesFolder
    {
        get
        {
            string dir = Environment.GetEnvironmentVariable("SPIDER_UPDATE_DIR")
                ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SpiderBuddy", "Updates");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static async Task<UpdateRelease?> CheckAsync(CancellationToken token = default)
    {
        if (!UpdateFeed.IsSafeUpdateUrl(Endpoint))
            throw new InvalidDataException("The update feed address is not a secure HTTPS address.");
        using var request = new HttpRequestMessage(HttpMethod.Get, Endpoint);
        request.Headers.UserAgent.ParseAdd("SpiderBuddy/" + CurrentVersion + " (Windows)");
        request.Headers.Accept.ParseAdd("application/xml, text/xml");
        request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };
        using var response = await Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength is > MostFeedBytes)
            throw new InvalidDataException("The update feed is too large.");
        string xml = await response.Content.ReadAsStringAsync(token);
        if (xml.Length > MostFeedBytes) throw new InvalidDataException("The update feed is too large.");
        var feed = UpdateFeed.Parse(xml);
        if (!UpdateFeed.VerifyFeed(PublicKey, feed))
            throw new InvalidDataException("The update feed signature is not valid.");
        var latest = feed.Latest(CurrentVersion);
        return latest is null ? null : new UpdateRelease(latest.Version, latest.Notes, latest.Url, latest.Length, latest.InstallerSignature);
    }

    /// <summary>Download to the update folder and verify the signed enclosure.</summary>
    public static async Task<string> DownloadAsync(UpdateRelease release, IProgress<double>? progress = null, CancellationToken token = default)
    {
        if (!UpdateFeed.IsSafeUpdateUrl(release.Url)) throw new InvalidDataException("The installer URL is not secure.");
        string version = new string(release.Version.Where(c => char.IsDigit(c) || c == '.').ToArray());
        if (version.Length == 0) throw new InvalidDataException("The update version is invalid.");
        string path = Path.Combine(UpdatesFolder, $"SpiderBuddy-{version}-setup.exe");
        if (File.Exists(path) && VerifyDownload(path, release)) { progress?.Report(1); return path; }

        string temp = path + ".part";
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, release.Url);
            request.Headers.UserAgent.ParseAdd("SpiderBuddy/" + CurrentVersion + " (Windows)");
            using var response = await Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            response.EnsureSuccessStatusCode();
            long total = response.Content.Headers.ContentLength ?? release.Length;
            if (total < 0 || total > UpdateFeed.MostInstallerBytes)
                throw new InvalidDataException("The installer is too large.");
            await using (var input = await response.Content.ReadAsStreamAsync(token))
            await using (var output = new FileStream(temp, FileMode.Create, FileAccess.Write, FileShare.None, 128 * 1024, true))
            {
                var buffer = new byte[128 * 1024];
                long done = 0;
                int read;
                while ((read = await input.ReadAsync(buffer, token)) > 0)
                {
                    done += read;
                    if (done > UpdateFeed.MostInstallerBytes) throw new InvalidDataException("The installer is too large.");
                    await output.WriteAsync(buffer.AsMemory(0, read), token);
                    if (total > 0) progress?.Report(Math.Clamp(done / (double)total, 0, 1));
                }
                if (release.Length > 0 && done != release.Length)
                    throw new InvalidDataException("The installer length does not match the signed feed.");
            }
            if (!VerifyDownload(temp, release))
                throw new InvalidDataException("The installer signature is not valid.");
            File.Move(temp, path, overwrite: true);
            progress?.Report(1);
            return path;
        }
        finally
        {
            try { if (File.Exists(temp)) File.Delete(temp); } catch { }
        }
    }

    public static bool VerifyDownload(string path, UpdateRelease release)
    {
        try
        {
            if (!File.Exists(path)) return false;
            if (release.Length > 0 && new FileInfo(path).Length != release.Length) return false;
            byte[] key = Convert.FromBase64String(PublicKey);
            byte[] signature = Convert.FromBase64String(release.Signature);
            return Ed25519.VerifyFile(path, key, signature);
        }
        catch { return false; }
    }

    /// <summary>Run the per-user Inno installer silently. The caller exits the spider immediately after.</summary>
    public static bool LaunchInstaller(string path)
    {
        try
        {
            if (!File.Exists(path) || !string.Equals(Path.GetExtension(path), ".exe", StringComparison.OrdinalIgnoreCase))
                return false;
            return Process.Start(new ProcessStartInfo(path)
            {
                Arguments = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART",
                WorkingDirectory = Path.GetDirectoryName(path) ?? AppContext.BaseDirectory,
                UseShellExecute = true
            }) is not null;
        }
        catch { return false; }
    }

    public static string? Sha256(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            return Convert.ToHexString(SHA256.HashData(stream));
        }
        catch { return null; }
    }

    static string ReadCurrentVersion()
    {
        try
        {
            string? informational = typeof(UpdateService).Assembly
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
            if (!string.IsNullOrWhiteSpace(informational) &&
                UpdateFeed.TryVersion(informational, out var version))
                return version.ToString(3);
            var assembly = typeof(UpdateService).Assembly.GetName().Version;
            if (assembly is not null) return UpdateFeed.TryVersion(assembly.ToString(), out var v) ? v.ToString(3) : "1.0.1";
        }
        catch { }
        return "1.0.1";
    }

    static string LoadBakedPublicKey()
    {
        try
        {
            using var stream = typeof(UpdateService).Assembly.GetManifestResourceStream(FeedResource);
            if (stream is null) return "";
            using var reader = new StreamReader(stream, Encoding.UTF8);
            return reader.ReadToEnd().Trim();
        }
        catch { return ""; }
    }
}

/// <summary>The release-notes dialog. The caller decides whether to download and install.</summary>
public sealed class UpdateDialog : Form
{
    public bool InstallRequested { get; private set; }
    public bool OpenPageRequested { get; private set; }

    public UpdateDialog(UpdateRelease release)
    {
        Text = "Spider Buddy Update";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(500, 460);
        BackColor = Color.FromArgb(248, 245, 238);

        Controls.Add(new Label
        {
            Text = $"A new Spider Buddy is ready: {release.Version}",
            Font = new Font("Segoe UI Semibold", 16f), AutoSize = true, Location = new Point(26, 22)
        });
        Controls.Add(new Label
        {
            Text = $"You have {UpdateService.CurrentVersion}. The release notes are below.",
            AutoSize = true, Location = new Point(28, 58), ForeColor = Color.FromArgb(105, 96, 88)
        });
        var notes = new TextBox
        {
            Text = string.IsNullOrWhiteSpace(release.Notes) ? "No release notes were provided." : release.Notes,
            Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, WordWrap = true,
            Location = new Point(28, 88), Size = new Size(444, 258), BackColor = Color.FromArgb(255, 252, 246)
        };
        Controls.Add(notes);
        var install = new Button
        {
            Text = "Install Now", Width = 120, Height = 32, Location = new Point(26, 390),
            BackColor = Color.FromArgb(217, 130, 43), ForeColor = Color.White, FlatStyle = FlatStyle.Flat
        };
        install.FlatAppearance.BorderSize = 0;
        install.Click += (_, _) => { InstallRequested = true; DialogResult = DialogResult.OK; Close(); };
        var page = new Button { Text = "Open Download Page", Width = 160, Height = 32, Location = new Point(156, 390) };
        page.Click += (_, _) =>
        {
            try
            {
                if (!string.IsNullOrWhiteSpace(release.Url))
                    Process.Start(new ProcessStartInfo(release.Url) { UseShellExecute = true });
            }
            catch { }
        };
        var later = new Button { Text = "Not Now", Width = 90, Height = 32, Location = new Point(374, 390), DialogResult = DialogResult.Cancel };
        Controls.AddRange(new Control[] { install, page, later });
        AcceptButton = install;
        CancelButton = later;
    }
}

/// <summary>A tiny modal progress window for a verified update download.</summary>
public sealed class UpdateProgressForm : Form
{
    readonly UpdateRelease _release;
    readonly Label _label = new() { AutoSize = false, Width = 400, Height = 42, Location = new Point(24, 22) };
    readonly ProgressBar _bar = new() { Minimum = 0, Maximum = 100, Value = 0, Width = 400, Height = 18, Location = new Point(24, 72) };
    readonly Button _cancel = new() { Text = "Cancel", Width = 80, Height = 28, Location = new Point(344, 108) };
    readonly CancellationTokenSource _stop = new();
    string? _path;
    Exception? _error;

    public string? InstallerPath => _path;
    public Exception? Error => _error;

    public UpdateProgressForm(UpdateRelease release)
    {
        _release = release;
        Text = "Spider Buddy Update";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        StartPosition = FormStartPosition.CenterParent;
        MaximizeBox = false;
        MinimizeBox = false;
        ClientSize = new Size(450, 150);
        BackColor = Color.FromArgb(248, 245, 238);
        _label.Text = $"Downloading Spider Buddy {release.Version}…";
        _label.ForeColor = Color.FromArgb(90, 80, 70);
        _cancel.Click += (_, _) => { _stop.Cancel(); Close(); };
        Controls.AddRange(new Control[] { _label, _bar, _cancel });
        Shown += async (_, _) => await Download();
    }

    async Task Download()
    {
        try
        {
            var progress = new Progress<double>(p => _bar.Value = Math.Clamp((int)Math.Round(p * 100), 0, 100));
            _path = await UpdateService.DownloadAsync(_release, progress, _stop.Token);
            DialogResult = DialogResult.OK;
            Close();
        }
        catch (OperationCanceledException) { DialogResult = DialogResult.Cancel; Close(); }
        catch (Exception ex)
        {
            _error = ex;
            DialogResult = DialogResult.Abort;
            Close();
        }
    }
}
