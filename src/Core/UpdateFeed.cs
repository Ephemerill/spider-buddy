using System.Globalization;
using System.Xml;
using System.Xml.Linq;

namespace SpiderBuddy.Core;

/// <summary>
/// One release in the Windows appcast. The enclosure is signed with Ed25519, and the
/// channel's feedSignature binds the version, URL, length, installer signature and
/// release notes together. That is the Windows equivalent of Sparkle's signed appcast.
/// </summary>
public sealed record AppcastRelease(
    string Version,
    string Notes,
    string Url,
    long Length,
    string InstallerSignature);

public sealed record AppcastFeed(IReadOnlyList<AppcastRelease> Releases, string FeedSignature)
{
    public AppcastRelease? Latest(string currentVersion)
    {
        AppcastRelease? best = null;
        foreach (var release in Releases)
        {
            if (!UpdateFeed.IsNewer(release.Version, currentVersion)) continue;
            if (best is null || UpdateFeed.IsNewer(release.Version, best.Version)) best = release;
        }
        return best;
    }
}

/// <summary>Reading and signing the small, human-inspectable Windows appcast.</summary>
public static class UpdateFeed
{
    public const string SparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle";
    public const string SpiderNamespace = "https://spiderbuddy.app/update";
    public const int MostFeedBytes = 1_000_000;
    public const long MostInstallerBytes = 512L * 1024 * 1024;
    public const int MostNotes = 100_000;

    /// <summary>Canonical feed signature input. Never reorder these fields.</summary>
    public static string Canonical(AppcastRelease release) =>
        string.Join("\n", release.Version, release.Url, release.Length.ToString(CultureInfo.InvariantCulture),
            release.InstallerSignature, release.Notes);

    public static string Canonical(AppcastFeed feed) =>
        string.Join("\n", feed.Releases.Select(Canonical));

    public static byte[] SignFeed(string seedBase64, AppcastFeed feed)
    {
        byte[] seed = Convert.FromBase64String(seedBase64);
        return Ed25519.Sign(seed, System.Text.Encoding.UTF8.GetBytes(Canonical(feed)));
    }

    public static bool VerifyFeed(string publicKeyBase64, AppcastFeed feed)
    {
        try
        {
            byte[] key = Convert.FromBase64String(publicKeyBase64);
            byte[] signature = Convert.FromBase64String(feed.FeedSignature);
            return Ed25519.Verify(key, System.Text.Encoding.UTF8.GetBytes(Canonical(feed)), signature);
        }
        catch { return false; }
    }

    public static AppcastFeed Parse(string xml)
    {
        if (string.IsNullOrWhiteSpace(xml)) throw new FormatException("The update feed is empty.");
        if (xml.Length > MostFeedBytes) throw new FormatException("The update feed is too large.");

        var settings = new XmlReaderSettings
        {
            DtdProcessing = DtdProcessing.Prohibit,
            XmlResolver = null,
            MaxCharactersInDocument = MostFeedBytes,
            IgnoreComments = true,
            IgnoreWhitespace = false
        };
        XDocument doc;
        using (var reader = XmlReader.Create(new StringReader(xml), settings))
            doc = XDocument.Load(reader, LoadOptions.None);

        XNamespace sparkle = SparkleNamespace;
        XNamespace spider = SpiderNamespace;
        var channel = doc.Root?.Element("channel")
            ?? throw new FormatException("The feed has no channel.");
        string feedSignature = (string?)channel.Element(spider + "feedSignature") ?? "";

        var releases = new List<AppcastRelease>();
        foreach (var item in channel.Elements("item"))
        {
            var enclosure = item.Element("enclosure");
            if (enclosure is null) continue;
            string version = ((string?)enclosure.Attribute(sparkle + "shortVersionString")
                ?? (string?)enclosure.Attribute(sparkle + "version")
                ?? (string?)item.Element(sparkle + "shortVersionString")
                ?? (string?)item.Element(sparkle + "version")
                ?? "").Trim();
            if (!TryVersion(version, out _)) continue;

            string url = ((string?)enclosure.Attribute("url") ?? "").Trim();
            string installerSignature = ((string?)enclosure.Attribute(sparkle + "edSignature") ?? "").Trim();
            string lengthText = (string?)enclosure.Attribute("length") ?? "0";
            long.TryParse(lengthText, NumberStyles.Integer, CultureInfo.InvariantCulture, out long length);
            string notes = (string?)item.Element("description") ?? "";
            if (notes.Length > MostNotes) notes = notes[..MostNotes];

            if (!IsSafeUpdateUrl(url)) continue;
            if (length < 0 || length > MostInstallerBytes) continue;
            if (!IsBase64Size(installerSignature, Ed25519.SignatureBytes)) continue;

            releases.Add(new AppcastRelease(version, notes, url, length, installerSignature));
        }

        return new AppcastFeed(releases.OrderByDescending(r => VersionOf(r.Version)).ToList(), feedSignature);
    }

    public static bool IsSafeUpdateUrl(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)) return false;
        if (uri.Scheme == Uri.UriSchemeHttps) return true;
        // Local loopback HTTP is only for the update self-test.
        return uri.Scheme == Uri.UriSchemeHttp && uri.IsLoopback;
    }

    public static bool IsNewer(string candidate, string current)
    {
        if (!TryVersion(candidate, out var c) || !TryVersion(current, out var n)) return false;
        return c > n;
    }

    public static bool TryVersion(string text, out Version version)
    {
        version = new Version(0, 0);
        string s = text.Trim();
        if (s.StartsWith('v') || s.StartsWith('V')) s = s[1..];
        int cut = s.IndexOfAny(new[] { '-', '+', ' ' });
        if (cut >= 0) s = s[..cut];
        if (!Version.TryParse(s, out var parsed)) return false;
        version = Normalize(parsed);
        return true;
    }

    static Version VersionOf(string text) => TryVersion(text, out var v) ? v : new Version(0, 0);

    static Version Normalize(Version v) =>
        new(v.Major, Math.Max(0, v.Minor), Math.Max(0, v.Build), Math.Max(0, v.Revision));

    static bool IsBase64Size(string text, int bytes)
    {
        try { return Convert.FromBase64String(text).Length == bytes; }
        catch { return false; }
    }
}
