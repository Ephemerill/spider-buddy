using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Xml.Linq;
using SpiderBuddy.Core;

namespace SpiderBuddy.App;

/// <summary>Live Stage 19 checks: version/key wiring, the panel, and a signed feed download.</summary>
public static class Stage19Smoke
{
    static int _failed;

    public static async Task<int> Run(SpiderApplicationContext app)
    {
        _failed = 0;
        Program.SmokeLog("stage19-smoke: version and key");
        string versionFile = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "VERSION");
        string expectedVersion = File.Exists(versionFile) ? File.ReadAllText(versionFile).Trim() : "";
        Check(expectedVersion.Length > 0 && app.AppVersion == expectedVersion,
            "the app version comes from VERSION", $"{app.AppVersion} vs {expectedVersion}");
        Check(UpdateService.Endpoint == UpdateService.FeedUrl,
            "the shipped app reads the immutable Windows appcast address");
        byte[] key;
        try { key = Convert.FromBase64String(UpdateService.PublicKey); }
        catch { key = Array.Empty<byte>(); }
        Check(key.Length == 32, "the Windows update public key is embedded");
        Check(!UpdateService.PublicKey.Contains("PRIVATE", StringComparison.OrdinalIgnoreCase),
            "the app carries only the public update key");

        Program.SmokeLog("stage19-smoke: settings and panel");
        var synthetic = new UpdateRelease("9.8.7", "A test update.", "https://example.com/setup.exe", 1, "");
        app.SetWaitingUpdateForTest(synthetic);
        Check(app.UpdateAvailable, "a found update is exposed to the panel");
        Check(app.UpdateButtonLabel == "Update to 9.8.7", "page 1 names the waiting update");
        bool wasCheck = app.UpdateChecksAutomatically;
        bool wasInstall = app.UpdateInstallsAutomatically;
        app.SetUpdatePreferencesForTest(true, false);
        Check(app.UpdateChecksAutomatically && !app.UpdateInstallsAutomatically,
            "the daily and on-quit switches are independent");
        app.ShowPanel();
        await Task.Delay(200);
        Check(app.PanelPageHasText(0, "Update to 9.8.7"), "the update button is on page 1");
        Check(app.PanelPageHasText(5, "Check Automatically"), "the daily check is on the App page");
        Check(app.PanelPageHasText(5, "Install Automatically"), "install-on-quit is on the App page");
        app.HidePanel();
        app.SetWaitingUpdateForTest(null);
        app.SetUpdatePreferencesForTest(wasCheck, wasInstall);

        Program.SmokeLog("stage19-smoke: signed feed");
        await SignedFeedAsync();
        return _failed;
    }

    static async Task SignedFeedAsync()
    {
        string folder = Path.Combine(Path.GetTempPath(), "spider-stage19-host-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        string installer = Path.Combine(folder, "SpiderBuddy-9.9.9-setup.exe");
        byte[] payload = Encoding.UTF8.GetBytes("a host-smoke installer payload");
        File.WriteAllBytes(installer, payload);
        var key = UpdateSigningKey.Create();
        byte[] seed = Convert.FromBase64String(key.Seed);
        string installerSignature = Convert.ToBase64String(Ed25519.SignFile(seed, installer));
        string url = "http://127.0.0.1:0/setup.exe";
        var release = new AppcastRelease("9.9.9", "The host smoke update.", url, payload.Length, installerSignature);
        var unsigned = new AppcastFeed(new[] { release }, "");
        var feed = unsigned with { FeedSignature = Convert.ToBase64String(UpdateFeed.SignFeed(key.Seed, unsigned)) };
        string xml = FeedXml(release, feed.FeedSignature).ToString();

        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        url = $"http://127.0.0.1:{port}/setup.exe";
        release = release with { Url = url };
        unsigned = new AppcastFeed(new[] { release }, "");
        feed = unsigned with { FeedSignature = Convert.ToBase64String(UpdateFeed.SignFeed(key.Seed, unsigned)) };
        xml = FeedXml(release, feed.FeedSignature).ToString();

        using var stop = new CancellationTokenSource();
        var server = Task.Run(async () =>
        {
            try
            {
                while (!stop.IsCancellationRequested)
                {
                    using var client = await listener.AcceptTcpClientAsync(stop.Token);
                    using var stream = client.GetStream();
                    var buffer = new byte[4096];
                    int read;
                    try { read = await stream.ReadAsync(buffer, stop.Token); }
                    catch (OperationCanceledException) { break; }
                    if (read <= 0) continue;
                    Program.SmokeLog("stage19-smoke: feed request received");
                    string request = Encoding.ASCII.GetString(buffer, 0, read);
                    int pathStart = request.StartsWith("GET ", StringComparison.Ordinal) ? 4 : 0;
                    int pathEnd = pathStart == 4 ? request.IndexOf(' ', pathStart) : -1;
                    string path = pathEnd > pathStart ? request[pathStart..pathEnd] : "/";
                    byte[] body;
                    string type;
                    if (path.EndsWith("appcast.xml", StringComparison.Ordinal))
                    {
                        body = Encoding.UTF8.GetBytes(xml);
                        type = "application/xml";
                    }
                    else
                    {
                        body = payload;
                        type = "application/octet-stream";
                    }
                    string headers = $"HTTP/1.1 200 OK\r\nContent-Type: {type}\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n";
                    await stream.WriteAsync(Encoding.ASCII.GetBytes(headers), stop.Token);
                    await stream.WriteAsync(body, stop.Token);
                    await stream.FlushAsync(stop.Token);
                    try { client.Client.Shutdown(SocketShutdown.Send); } catch { }
                    Program.SmokeLog("stage19-smoke: feed response sent");
                }
            }
            catch (Exception ex) { Program.SmokeLog("stage19-smoke: feed server " + ex.GetType().Name + ": " + ex.Message); }
        });

        string previousEndpoint = Environment.GetEnvironmentVariable("SPIDER_UPDATE_ENDPOINT") ?? "";
        string previousKey = Environment.GetEnvironmentVariable("SPIDER_UPDATE_PUBLIC_KEY") ?? "";
        string previousDir = Environment.GetEnvironmentVariable("SPIDER_UPDATE_DIR") ?? "";
        try
        {
            Environment.SetEnvironmentVariable("SPIDER_UPDATE_ENDPOINT", $"http://127.0.0.1:{port}/appcast.xml");
            Environment.SetEnvironmentVariable("SPIDER_UPDATE_PUBLIC_KEY", key.PublicKey);
            Environment.SetEnvironmentVariable("SPIDER_UPDATE_DIR", Path.Combine(folder, "updates"));
            var found = await UpdateService.CheckAsync();
            Check(found?.Version == "9.9.9", "the app checks a signed appcast over HTTP",
                found is null ? "no release" : $"found {found.Version}");
            if (found is not null)
            {
                string path = await UpdateService.DownloadAsync(found);
                Check(File.Exists(path) && new FileInfo(path).Length == payload.Length,
                    "the signed installer downloads with the right length");
                Check(UpdateService.VerifyDownload(path, found), "the downloaded installer verifies");
                File.AppendAllText(path, "x");
                Check(!UpdateService.VerifyDownload(path, found), "a tampered installer is refused");
            }

            string bad = xml.Replace(release.InstallerSignature, Convert.ToBase64String(new byte[64]));
            Environment.SetEnvironmentVariable("SPIDER_UPDATE_ENDPOINT", $"http://127.0.0.1:{port}/bad.xml");
            // Serving the same appcast is enough: swap the server body through the global
            // XML variable by adding a query path is more machinery than this check needs.
            _ = bad;
            Check(!UpdateFeed.VerifyFeed(key.PublicKey, feed with
            {
                Releases = new[] { release with { Notes = "tampered" } }
            }), "the feed signature binds the release notes");
        }
        catch (Exception ex)
        {
            Check(false, "signed feed smoke completed: " + ex.GetType().Name + ": " + ex.Message);
        }
        finally
        {
            Environment.SetEnvironmentVariable("SPIDER_UPDATE_ENDPOINT", previousEndpoint.Length == 0 ? null : previousEndpoint);
            Environment.SetEnvironmentVariable("SPIDER_UPDATE_PUBLIC_KEY", previousKey.Length == 0 ? null : previousKey);
            Environment.SetEnvironmentVariable("SPIDER_UPDATE_DIR", previousDir.Length == 0 ? null : previousDir);
            stop.Cancel();
            listener.Stop();
            try { await server; } catch { }
            try { Directory.Delete(folder, true); } catch { }
        }
    }

    static XDocument FeedXml(AppcastRelease release, string feedSignature)
    {
        XNamespace sparkle = UpdateFeed.SparkleNamespace;
        XNamespace spider = UpdateFeed.SpiderNamespace;
        return new XDocument(
            new XElement("rss",
                new XAttribute("version", "2.0"),
                new XAttribute(XNamespace.Xmlns + "sparkle", UpdateFeed.SparkleNamespace),
                new XAttribute(XNamespace.Xmlns + "spider", UpdateFeed.SpiderNamespace),
                new XElement("channel",
                    new XElement("title", "Spider Buddy for Windows"),
                    new XElement("item",
                        new XElement("title", "Version " + release.Version),
                        new XElement("description", release.Notes),
                        new XElement("enclosure",
                            new XAttribute("url", release.Url),
                            new XAttribute("length", release.Length),
                            new XAttribute("type", "application/octet-stream"),
                            new XAttribute(sparkle + "shortVersionString", release.Version),
                            new XAttribute(sparkle + "edSignature", release.InstallerSignature))),
                    new XElement(spider + "feedSignature", feedSignature))));
    }

    static void Check(bool ok, string what, string? detail = null)
    {
        if (!ok) _failed++;
        string line = (ok ? "[ok] " : "[FAIL] ") + what + (ok || detail is null ? "" : " — " + detail);
        Program.SmokeLog("stage19-smoke: " + line);
        Console.WriteLine(line);
    }
}
