using System.Text;
using SpiderBuddy.Core;

namespace SpiderBuddy.Tools;

/// <summary>Stage 19 checks, starting with the shipping cryptography and feed parser.</summary>
public static class Stage19
{
    public static int Run(string[] args)
    {
        Harness.Section("stage 19 packaging, updates and bug reports");

        // RFC 8032 section 7.1 test vectors. A wrong curve constant or scalar
        // encoding shows up here immediately.
        var emptySig = Convert.FromHexString(
            "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155" +
            "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b");
        var seed1 = Convert.FromHexString("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60");
        var pub1 = Convert.FromHexString("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a");
        Harness.Check(Ed25519.PublicKey(seed1).SequenceEqual(pub1), "RFC 8032 public key derives correctly");
        Harness.Check(Ed25519.Sign(seed1, Array.Empty<byte>()).SequenceEqual(emptySig), "RFC 8032 empty signature matches");
        Harness.Check(Ed25519.Verify(pub1, Array.Empty<byte>(), emptySig), "RFC 8032 empty signature verifies");

        var seed2 = Convert.FromHexString("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb");
        var pub2 = Convert.FromHexString("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c");
        var sig2 = Convert.FromHexString(
            "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da" +
            "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00");
        Harness.Check(Ed25519.Sign(seed2, new byte[] { 0x72 }).SequenceEqual(sig2), "RFC 8032 one-byte signature matches");
        Harness.Check(Ed25519.Verify(pub2, new byte[] { 0x72 }, sig2), "RFC 8032 one-byte signature verifies");
        Harness.Check(!Ed25519.Verify(pub2, new byte[] { 0x73 }, sig2), "a changed message is rejected");
        var tampered = (byte[])sig2.Clone();
        tampered[4] ^= 1;
        Harness.Check(!Ed25519.Verify(pub2, new byte[] { 0x72 }, tampered), "a changed signature is rejected");

        var generated = UpdateSigningKey.Create();
        var generatedSeed = Convert.FromBase64String(generated.Seed);
        var generatedPub = Convert.FromBase64String(generated.PublicKey);
        var generatedSig = Ed25519.Sign(generatedSeed, Encoding.UTF8.GetBytes("signed update"));
        Harness.Check(Ed25519.Verify(generatedPub, Encoding.UTF8.GetBytes("signed update"), generatedSig),
            "a generated update key signs and verifies");
        var keyBack = UpdateSigningKey.FromJson(generated.ToJson());
        Harness.Check(keyBack is not null && keyBack.PublicKey == generated.PublicKey, "the release key round-trips");

        // Feed shape, version selection, safe URLs, and the detached feed signature.
        var installerBytes = Encoding.UTF8.GetBytes("an installer, for signing tests");
        var temp = Path.Combine(Path.GetTempPath(), "spider-stage19-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(temp);
        string installerPath = Path.Combine(temp, "SpiderBuddy-1.2.0-setup.exe");
        File.WriteAllBytes(installerPath, installerBytes);
        string installerSig = Convert.ToBase64String(Ed25519.SignFile(generatedSeed, installerPath));
        Harness.Check(Ed25519.VerifyFile(installerPath, generatedPub, Convert.FromBase64String(installerSig)),
            "a downloaded installer verifies without loading it into memory");

        var release = new AppcastRelease("1.2.0", "A new hop.\n\n<!-- install -->\nManual notes.", "https://example.com/SpiderBuddy-1.2.0-setup.exe",
            installerBytes.Length, installerSig);
        var feed = new AppcastFeed(new[] { release }, "");
        var feedSig = Convert.ToBase64String(UpdateFeed.SignFeed(generated.Seed, feed));
        var signedFeed = feed with { FeedSignature = feedSig };
        Harness.Check(UpdateFeed.VerifyFeed(generated.PublicKey, signedFeed), "the appcast feed signature verifies");
        Harness.Check(!UpdateFeed.VerifyFeed(generated.PublicKey, signedFeed with
        {
            Releases = new[] { release with { Notes = "tampered" } }
        }), "changing release notes breaks the feed signature");

        string appcast = $"""
            <?xml version="1.0" encoding="utf-8"?>
            <rss version="2.0" xmlns:sparkle="{UpdateFeed.SparkleNamespace}" xmlns:spider="{UpdateFeed.SpiderNamespace}">
              <channel>
                <title>Spider Buddy for Windows</title>
                <item>
                  <title>Version 1.2.0</title>
                  <description><![CDATA[A new hop.]]></description>
                  <enclosure url="{release.Url}" length="{release.Length}"
                             type="application/octet-stream"
                             sparkle:shortVersionString="1.2.0"
                             sparkle:edSignature="{installerSig}" />
                </item>
                <spider:feedSignature>{feedSig}</spider:feedSignature>
              </channel>
            </rss>
            """;
        var parsed = UpdateFeed.Parse(appcast);
        Harness.Check(parsed.Releases.Count == 1 && parsed.Releases[0].Version == "1.2.0", "the appcast parses a release");
        Harness.Check(parsed.Releases[0].Url == release.Url && parsed.Releases[0].Length == release.Length,
            "the enclosure URL and length survive");
        Harness.Check(parsed.Latest("1.0.1")?.Version == "1.2.0", "a newer item is selected");
        Harness.Check(parsed.Latest("1.2.0") is null, "the current version is not offered again");
        Harness.Check(parsed.Latest("1.10.0") is null, "version comparison is numeric, not textual");
        Harness.Check(UpdateFeed.IsNewer("1.10.0", "1.9.9") && !UpdateFeed.IsNewer("1.0.0", "1.0.0.0"),
            "equivalent four-part versions compare equal");

        string unsafeFeed = appcast.Replace(release.Url, "http://example.com/setup.exe");
        Harness.Check(UpdateFeed.Parse(unsafeFeed).Releases.Count == 0, "a non-loopback HTTP installer is refused");
        Harness.Check(UpdateFeed.Parse(appcast.Replace("sparkle:edSignature=\"" + installerSig + "\"",
            "sparkle:edSignature=\"not-a-signature\"")).Releases.Count == 0,
            "an invalid installer signature is refused");

        // The shipping resources and installer are part of the stage, not
        // something to discover only after a release build.
        string root = FindRoot();
        Harness.Check(root.Length > 0, "the repository root is discoverable");
        string version = File.ReadAllText(Path.Combine(root, "VERSION")).Trim();
        var assemblyVersion = typeof(Stage19).Assembly.GetName().Version;
        Harness.Check(assemblyVersion is not null && assemblyVersion.ToString(3) == version,
            "the built Tools assembly uses the repository VERSION");

        string publicText = File.ReadAllText(Path.Combine(root, "Resources", "WindowsUpdatePublicKey.txt")).Trim();
        byte[] publicBytes;
        try { publicBytes = Convert.FromBase64String(publicText); } catch { publicBytes = Array.Empty<byte>(); }
        Harness.Check(publicBytes.Length == 32, "the separate Windows update public key is a 32-byte Ed25519 key");

        string icon = Path.Combine(root, "Resources", "AppIcon.ico");
        string iconPng = Path.Combine(root, "Resources", "AppIcon-256.png");
        string art = Path.Combine(root, "packaging", "installer-art.bmp");
        string smallArt = Path.Combine(root, "packaging", "installer-small.bmp");
        Harness.Check(new[] { icon, iconPng, art, smallArt }.All(p => File.Exists(p) && new FileInfo(p).Length > 500),
            "the app icon and installer art are present");

        string iss = File.ReadAllText(Path.Combine(root, "packaging", "SpiderBuddy.iss"));
        Harness.Check(iss.Contains("PrivilegesRequired=lowest") &&
            iss.Contains("DefaultDirName={localappdata}\\Programs\\SpiderBuddy"),
            "the installer is per-user and needs no administrator");
        Harness.Check(iss.Contains("SetupIconFile=..\\Resources\\AppIcon.ico") &&
            iss.Contains("WizardImageFile=installer-art.bmp") &&
            iss.Contains("OutputBaseFilename=SpiderBuddy-{#MyAppVersion}-setup"),
            "the installer uses the icon, art and versioned setup name");

        string appProject = File.ReadAllText(Path.Combine(root, "src", "App", "SpiderBuddy.App.csproj"));
        Harness.Check(appProject.Contains("SpiderBuddy.UpdatePublicKey") &&
            appProject.Contains("Extension\\**\\*"),
            "the app embeds the public key and bundles the browser extension");
        string manifest = File.ReadAllText(Path.Combine(root, "src", "App", "app.manifest"));
        Harness.Check(manifest.Contains("level=\"asInvoker\""), "the app manifest does not ask for administrator access");

        string worker = File.ReadAllText(Path.Combine(root, "tools", "report-worker", "src", "index.js")).ToLowerInvariant();
        Harness.Check(!new[] { "sentry", "posthog", "segment", "analytics", "telemetry" }.Any(worker.Contains),
            "the bug-report worker carries no telemetry client");

        string cliKey = Path.Combine(temp, "cli-key.json");
        File.WriteAllText(cliKey, generated.ToJson());
        string cliNotes = Path.Combine(temp, "release-notes.md");
        File.WriteAllText(cliNotes, "Before the marker.\n\n<!-- install -->\nOnly for manual downloaders.");
        string cliFeedPath = Path.Combine(temp, "windows-appcast.xml");
        int cliResult = ReleaseTool.Run(new[]
        {
            "sign-appcast", "--key", cliKey, "--installer", installerPath, "--version", "1.3.0",
            "--url", "https://example.com/SpiderBuddy-1.3.0-setup.exe", "--notes-file", cliNotes,
            "--output", cliFeedPath
        });
        Harness.Check(cliResult == 0 && File.Exists(cliFeedPath), "the release CLI writes a signed appcast");
        var cliFeed = UpdateFeed.Parse(File.ReadAllText(cliFeedPath));
        Harness.Check(UpdateFeed.VerifyFeed(generated.PublicKey, cliFeed) && cliFeed.Releases.Count == 1 &&
            cliFeed.Releases[0].Version == "1.3.0", "the release CLI appcast verifies");
        Harness.Check(cliFeed.Releases[0].Notes.Contains("Before the marker") &&
            !cliFeed.Releases[0].Notes.Contains("manual downloaders"),
            "notes after the install marker stay out of the update window");

        Directory.Delete(temp, true);

        Harness.Check(UpdateFeed.TryVersion("v1.2.3-beta+meta", out var parsedVersion) &&
            parsedVersion == new Version(1, 2, 3, 0), "prerelease and build suffixes do not break versions");
        Harness.Check(!UpdateFeed.TryVersion("latest", out _), "a non-version is refused");

        return Harness.Summarise("stage 19 packaging, updates and bug reports");
    }

    static string FindRoot()
    {
        DirectoryInfo? dir = new(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (File.Exists(Path.Combine(dir.FullName, "VERSION")) &&
                Directory.Exists(Path.Combine(dir.FullName, "src"))) return dir.FullName;
            dir = dir.Parent;
        }
        return "";
    }
}
