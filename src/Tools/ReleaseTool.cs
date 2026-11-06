using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Xml.Linq;
using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

/// <summary>
/// Release-only helpers: create the Windows update key and sign the Windows appcast.
/// The private seed never enters the app; only its public key is embedded at build time.
/// </summary>
public static class ReleaseTool
{
    public static int Run(string[] args)
    {
        string cmd = args.Length > 0 ? args[0].ToLowerInvariant() : "help";
        try
        {
            return cmd switch
            {
                "update-key" => UpdateKey(args),
                "sign-appcast" => SignAppcast(args),
                "verify-appcast" => VerifyAppcast(args),
                _ => Help()
            };
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"release tool: {ex.Message}");
            return 1;
        }
    }

    static int UpdateKey(string[] args)
    {
        string keyPath = Arg(args, "--key") ?? throw new ArgumentException("--key is required");
        string publicPath = Arg(args, "--public-file")
            ?? Path.Combine(Path.GetDirectoryName(keyPath)!, "windows-update-public.txt");
        bool created = false;
        UpdateSigningKey? key = null;
        if (File.Exists(keyPath))
        {
            key = UpdateSigningKey.FromJson(File.ReadAllText(keyPath));
        }
        if (key is null)
        {
            key = UpdateSigningKey.Create();
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(keyPath))!);
            File.WriteAllText(keyPath, key.ToJson(), new UTF8Encoding(false));
            created = true;
        }
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(publicPath))!);
        File.WriteAllText(publicPath, key.PublicKey + Environment.NewLine, new UTF8Encoding(false));
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            created,
            key = Path.GetFullPath(keyPath),
            publicFile = Path.GetFullPath(publicPath),
            publicKey = key.PublicKey
        }, new JsonSerializerOptions { WriteIndented = true }));
        if (created)
            Console.Error.WriteLine("A new Windows update key was created. Back it up; losing it means installed copies can never update.");
        return 0;
    }

    static int SignAppcast(string[] args)
    {
        string keyPath = Arg(args, "--key") ?? throw new ArgumentException("--key is required");
        string installer = Arg(args, "--installer") ?? throw new ArgumentException("--installer is required");
        string version = Arg(args, "--version") ?? throw new ArgumentException("--version is required");
        string url = Arg(args, "--url") ?? throw new ArgumentException("--url is required");
        string output = Arg(args, "--output") ?? throw new ArgumentException("--output is required");
        string notesPath = Arg(args, "--notes-file") ?? "";
        string downloadsUrl = Arg(args, "--downloads-url")
            ?? "https://github.com/Ephemerill/spider-buddy/releases/latest";

        if (!File.Exists(keyPath)) throw new FileNotFoundException("The update key file is missing.", keyPath);
        if (!File.Exists(installer)) throw new FileNotFoundException("The installer is missing.", installer);
        if (!UpdateFeed.TryVersion(version, out _)) throw new ArgumentException("--version is not a version");
        if (!UpdateFeed.IsSafeUpdateUrl(url)) throw new ArgumentException("--url must be HTTPS (or loopback HTTP for tests)");

        var key = UpdateSigningKey.FromJson(File.ReadAllText(keyPath))
            ?? throw new InvalidDataException("The update key file is invalid.");
        byte[] seed = Convert.FromBase64String(key.Seed);
        var info = new FileInfo(installer);
        string signature = Convert.ToBase64String(Ed25519.SignFile(seed, installer));
        string notes = "";
        if (notesPath.Length > 0 && File.Exists(notesPath)) notes = File.ReadAllText(notesPath);
        int marker = notes.IndexOf("<!-- install -->", StringComparison.OrdinalIgnoreCase);
        if (marker >= 0) notes = notes[..marker];
        notes = notes.Trim();
        if (notes.Length == 0) notes = $"What’s new in Spider Buddy {version}.";
        if (notes.Length > UpdateFeed.MostNotes) notes = notes[..UpdateFeed.MostNotes];

        var release = new AppcastRelease(version, notes, url, info.Length, signature);
        var unsigned = new AppcastFeed(new[] { release }, "");
        var feed = unsigned with { FeedSignature = Convert.ToBase64String(UpdateFeed.SignFeed(key.Seed, unsigned)) };

        XNamespace sparkle = UpdateFeed.SparkleNamespace;
        XNamespace spider = UpdateFeed.SpiderNamespace;
        var doc = new XDocument(
            new XDeclaration("1.0", "utf-8", null),
            new XElement("rss",
                new XAttribute("version", "2.0"),
                new XAttribute(XNamespace.Xmlns + "sparkle", UpdateFeed.SparkleNamespace),
                new XAttribute(XNamespace.Xmlns + "spider", UpdateFeed.SpiderNamespace),
                new XElement("channel",
                    new XElement("title", "Spider Buddy for Windows"),
                    new XElement("link", downloadsUrl),
                    new XElement("description", "Signed Windows releases of Spider Buddy."),
                    new XElement("language", "en"),
                    new XElement("item",
                        new XElement("title", $"Version {version}"),
                        new XElement("description", notes),
                        new XElement("pubDate", DateTime.UtcNow.ToString("R", CultureInfo.InvariantCulture)),
                        new XElement("enclosure",
                            new XAttribute("url", url),
                            new XAttribute("length", info.Length.ToString(CultureInfo.InvariantCulture)),
                            new XAttribute("type", "application/octet-stream"),
                            new XAttribute(sparkle + "version", version),
                            new XAttribute(sparkle + "shortVersionString", version),
                            new XAttribute(sparkle + "edSignature", signature))),
                    new XElement(spider + "feedSignature", feed.FeedSignature))));
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!);
        doc.Save(output);
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            output = Path.GetFullPath(output),
            version,
            length = info.Length,
            publicKey = key.PublicKey,
            feedSignature = feed.FeedSignature
        }, new JsonSerializerOptions { WriteIndented = true }));
        return 0;
    }

    static int VerifyAppcast(string[] args)
    {
        string feedPath = Arg(args, "--feed") ?? throw new ArgumentException("--feed is required");
        string keyPath = Arg(args, "--key") ?? throw new ArgumentException("--key is required");
        var key = UpdateSigningKey.FromJson(File.ReadAllText(keyPath))
            ?? throw new InvalidDataException("The update key file is invalid.");
        var feed = UpdateFeed.Parse(File.ReadAllText(feedPath));
        bool ok = UpdateFeed.VerifyFeed(key.PublicKey, feed);
        Console.WriteLine(ok ? "OK: the appcast signature is valid." : "INVALID: the appcast signature is not valid.");
        return ok ? 0 : 1;
    }

    static int Help()
    {
        Console.WriteLine("""
        release tool

          update-key --key <private.json> [--public-file <public.txt>]
          sign-appcast --key <private.json> --installer <setup.exe> --version <x.y.z>
                       --url <https://…/setup.exe> --notes-file <notes.md>
                       --output <windows-appcast.xml> [--downloads-url <url>]
          verify-appcast --feed <windows-appcast.xml> --key <private.json>
        """);
        return 0;
    }

    static string? Arg(string[] args, string name)
    {
        int at = Array.IndexOf(args, name);
        if (at >= 0 && at + 1 < args.Length) return args[at + 1];
        string prefix = name + "=";
        return args.FirstOrDefault(a => a.StartsWith(prefix, StringComparison.Ordinal))?[prefix.Length..];
    }
}
