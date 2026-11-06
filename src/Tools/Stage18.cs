using System.Text.Json;
using SpiderBuddy.Core;
using SpiderBuddy.Renderer;

namespace SpiderBuddy.Tools;

/// <summary>
/// Stage 18 checks: the talking spider, the pixel page reader, page geometry/scroll maths, and the
/// extension that feeds exact scroll positions. These are headless checks; the App smoke test
/// covers the host bridge and chat window.
/// </summary>
public static class Stage18
{
    public static int Run(string[] args)
    {
        Harness.Section("stage 18 talking spider and web pages");

        // ---------------------------------------------------------------- voice
        var design = Sheets.DefaultDesign();
        design.Name = "Mochi";
        design.Intelligence = true;
        design.Manner = "dry wit, loves puns";
        design.Packs = new List<string> { "chitchat", "verses" };
        design.CustomPhrases = new List<string> { "little steps" };

        string persona = SpiderVoiceText.Persona(design);
        Harness.Check(persona.Contains("Mochi"), "the voice knows the spider's name");
        Harness.Check(persona.Contains("tiny jumping spider"), "the voice carries the spider persona");
        Harness.Check(persona.Contains("never say you are an AI"), "the voice forbids assistant/AI talk");
        Harness.Check(persona.Contains("dry wit"), "the manner reaches the prompt");
        Harness.Check(persona.Contains("little steps"), "the person's own phrases reach the prompt");

        Harness.Check(SpiderVoiceText.FeelingOf("yay! that is great!") == Feeling.Happy,
            "an excited line feels happy");
        Harness.Check(SpiderVoiceText.FeelingOf("hehe, look at my little dance") == Feeling.Playful,
            "a silly line feels playful");
        Harness.Check(SpiderVoiceText.FeelingOf("hmm, I wonder what that is?") == Feeling.Curious,
            "a wondering line feels curious");
        Harness.Check(SpiderVoiceText.FeelingOf("tiny spider hug!") == Feeling.Loving,
            "a hug feels loving");
        var tagged = SpiderVoiceText.FeelingIn("[sleepy] night night");
        Harness.Check(tagged.feeling == Feeling.Sleepy && tagged.text == "night night",
            "a model's feeling tag is understood and removed");
        Harness.Check(Enum.GetValues<Feeling>().Length == 10, "all ten reply feelings exist");

        string? cleaned = SpiderVoiceText.Clean("  \"hello\" 😊 #spider *waves*  ", "Mochi", 80);
        Harness.Check(cleaned is { Length: > 0 } && !cleaned.Contains("😊") && !cleaned.Contains('#')
            && !cleaned.Contains('*') && !cleaned.Contains('"'), "typing is cleaned of emoji, hash and actions");

        var verses = new SpiderDesign { Packs = new List<string> { "verses" } };
        var verse = SpiderPhrases.RandomLine(verses, new Rng(18), versesOnly: true);
        Harness.Check(verse is not null && (verse.Contains("Psalm") || verse.Contains("Proverbs") || verse.Contains("Corinthians")
            || verse.Contains("Thessalonians")), "a verse pack shows a verse exactly as written");
        Harness.Check(SpiderPhrases.Packs.ContainsKey("chitchat") && SpiderPhrases.Packs.ContainsKey("spider"),
            "the shared phrase packs are present");

        var words = new BuiltInSpiderWords(1801);
        Harness.Check(words.Status == VoiceStatus.Ready, "the built-in voice is honestly ready");
        Harness.Check(words.StatusLabel.Contains("Built-in"), "the built-in voice says what it is");
        var muse = words.MuseAsync(design, "music", Array.Empty<string>()).GetAwaiter().GetResult();
        Harness.Check(muse is { Length: > 4 } && (muse.Contains("song") || muse.Contains("dance") || muse.Contains("tap")),
            "a music spark gets a sensible, simple line");

        var reply = words.ReplyAsync(design, "on a screen edge", "hello", Array.Empty<(string, string)>())
            .GetAwaiter().GetResult();
        Harness.Check(reply is WordsAnswer.Said { Text.Length: > 0 }, "the built-in voice answers a hello");
        if (reply is WordsAnswer.Said said)
            Harness.Check(said.Feeling == Feeling.Happy || said.Feeling == Feeling.Playful,
                "the answer comes back with a body feeling");
        var loveReply = words.ReplyAsync(design, "on a screen edge", "do you love me", Array.Empty<(string, string)>())
            .GetAwaiter().GetResult();
        Harness.Check(loveReply is WordsAnswer.Said { Feeling: Feeling.Loving },
            "an affectionate answer drives an affectionate feeling");

        // ---------------------------------------------------------------- talking state
        var map = BasicMap();
        var spider = new Spider(design, map, new Rng(1818)) { BrainEnabled = true };
        Spider.Words = words;
        var anchors = map.SampleSpots(8, true, spider.Scale);
        if (anchors.Count > 0)
        {
            var anchor = anchors[0];
            spider.SetAnchor(anchor.Anchor.LoopId, anchor.Anchor.SegIdx, anchor.Anchor.T, anchor.Anchor.Dir);
        }
        Harness.Check(spider.CanTalk, "the talking switch and ready voice enable chat");

        spider.BeginListening();
        Harness.Check(spider.Listening && spider.HoldStillToTalk, "opening the chat makes it listen and hold still");
        int decisions = spider.Decisions;
        spider.DecisionIn = 0;
        for (int i = 0; i < 240; i++) spider.Update(1.0 / 60);
        Harness.Check(spider.Decisions == decisions, "it holds its decisions while listening");

        spider.Speak("hello! you came to see me!", Feeling.Happy);
        Harness.Check(spider.CurrentThought == ThoughtKind.Text && spider.CurrentThoughtText == "hello! you came to see me!",
            "a reply is written into its thought bubble");
        var pose = spider.BuildPose();
        var bubble = SpiderRenderer.ThoughtBubbleRect(pose);
        Harness.Check(bubble.W > 0 && bubble.H > 0, "the text bubble has a real rectangle");
        Harness.Check(bubble.Contains(new V2(bubble.Mid.X, bubble.MinY + 2)), "the bubble rectangle can be hit-tested");
        Harness.Check(spider.Situation().Length > 0, "the reply background is always available");
        Harness.Check(spider.Spark().Length > 0, "a passing thought has one concrete spark");

        spider.EndListening();
        Harness.Check(!spider.Listening, "closing the chat lets it go again");

        // ---------------------------------------------------------------- page reader
        var page = SyntheticPage();
        var readerSettings = PageReader.Settings.ForScale(0.9);
        int top = PageReader.PageTop(page, 180, readerSettings);
        Harness.Check(top >= 35 && top <= 55, "the browser's own bar is found as the page top", $"top {top}");
        var edges = PageReader.Edges(page, readerSettings, new Rect(0, Math.Max(0, top + 2), page.Width, page.Height - top - 2));
        Harness.Check(edges.Count >= 4, "the card's edges are found", $"{edges.Count} edges");
        Harness.Check(edges.Any(e => e.Horizontal), "horizontal card edges are found");
        Harness.Check(edges.Any(e => !e.Horizontal), "upright card edges are found");
        Harness.Check(edges.All(e => e.Length >= readerSettings.MinLength), "every found edge is long enough to stand on");
        var chains = PageReader.Chains(edges, readerSettings.Trim, readerSettings.Trim);
        Harness.Check(chains.Count > 0, "edges join into a path the spider can walk", $"{chains.Count} chains");
        Harness.Check(chains.Any(c => c.Points.Count >= 2), "a page chain has real points");
        var sameFingerprint = PageReader.Edges(page, readerSettings).Count;
        Harness.Check(sameFingerprint == PageReader.Edges(page, readerSettings).Count, "reading the same picture twice gives the same edges");

        // ---------------------------------------------------------------- page scroll + map
        var bridgePage = new PageBridgePage
        {
            Tab = 7, Window = new Rect(0, 0, 1920, 1080), Viewport = new SizeD(1920, 1080), Dpr = 1
        };
        bridgePage.Scrollers[0] = new PageScroller { Id = 0, Carrier = -1, Rect = new Rect(0, 0, 1920, 1080), Offset = new V2(0, 100) };
        bridgePage.Scrollers[2] = new PageScroller { Id = 2, Carrier = 0, Rect = new Rect(100, 100, 800, 500), Offset = new V2(0, 50) };
        bridgePage.Offsets[0] = new V2(0, 100);
        bridgePage.Offsets[2] = new V2(0, 50);
        var baseline = new Dictionary<int, V2> { [0] = new V2(0, 20), [2] = new V2(0, 10) };
        var carried = PageScrollMath.Carried(2, bridgePage, baseline);
        Harness.Near(carried.X, 0, 0.001, "horizontal scroll is carried exactly");
        Harness.Near(carried.Y, -120, 0.001, "a nested scroller adds its carrier's scroll");
        var visible = PageScrollMath.Visible(2, bridgePage, baseline, 40, 1.5);
        Harness.Check(visible.Contains(new V2(visible.Mid.X, visible.Mid.Y)), "a scroller has a visible rectangle");

        var desk = new DesktopState { VirtualBounds = new Rect(0, 0, 1920, 1080) };
        var screen = new ScreenFrame
        {
            Id = "screen:0", Frame = new Rect(0, 0, 1920, 1080), VisibleFrame = new Rect(0, 0, 1920, 1040), Main = true, Dpi = 96
        };
        desk.Screens.Add(screen);
        desk.Windows.Add(new TrackedWindow
        {
            Id = 90, Frame = new Rect(0, 0, 1920, 1080), Depth = 0, Owner = "chrome.exe", Maximized = true
        });
        var ledge = SurfaceMap.PathLoop("page:90:1", SurfaceKind.WebLedge,
            new[] { new V2(200, 800), new V2(900, 800) }, new[] { EdgeFacing.Up }, false, 0, 17.2);
        Harness.Check(ledge is not null, "a page edge becomes a real surface loop");
        var pageMap = new SurfaceMap();
        pageMap.Rebuild(desk, 0.78, ledge is null ? null : new[] { ledge }, null, new[] { screen.Frame });
        Harness.Check(pageMap.Loop("page:90:1") is not null, "the page loop is laid in the surface map");
        Harness.Check(pageMap.AllLoops.All(l => l.Kind != SurfaceKind.WindowEdge), "a full-screen page replaces ordinary window loops");
        Harness.Check(pageMap.Loop("screen:0") is null, "a full-screen page replaces the screen border");
        Harness.Check(ledge?.Kind == SurfaceKind.WebLedge && ledge.Kind.OnWindow(), "web ledges count as window surfaces");

        var normalMap = new SurfaceMap();
        normalMap.Rebuild(desk, 0.78);
        Harness.Check(normalMap.LoopCount >= 1, "without pages the desktop map is unchanged");

        // ---------------------------------------------------------------- extension files
        string root = ProjectRoot();
        string extension = Path.Combine(root, "Extension");
        Harness.Check(File.Exists(Path.Combine(extension, "manifest.json")), "the browser extension is bundled");
        Harness.Check(File.Exists(Path.Combine(extension, "worker.js")), "the extension service worker exists");
        Harness.Check(File.Exists(Path.Combine(extension, "page.js")), "the extension page script exists");
        Harness.Check(File.Exists(Path.Combine(extension, "icon48.png")) && File.Exists(Path.Combine(extension, "icon128.png")),
            "both extension icons exist");
        try
        {
            using var manifest = JsonDocument.Parse(File.ReadAllText(Path.Combine(extension, "manifest.json")));
            var m = manifest.RootElement;
            Harness.Check(m.GetProperty("manifest_version").GetInt32() == 3, "the extension is Manifest V3");
            Harness.Check(m.GetProperty("name").GetString() == "Spider Buddy", "the extension is named Spider Buddy");
            var scripts = m.GetProperty("content_scripts")[0];
            Harness.Check(scripts.GetProperty("all_frames").GetBoolean() == false, "the page script only reads the top frame");
            Harness.Check(scripts.GetProperty("matches").GetArrayLength() == 3, "http, https and file pages are covered");
        }
        catch (Exception ex)
        {
            Harness.Fail("the extension manifest is valid JSON", ex.Message);
        }
        string worker = File.ReadAllText(Path.Combine(extension, "worker.js"));
        Harness.Check(worker.Contains("47219") && worker.Contains("47220") && worker.Contains("47221"),
            "the extension tries all three loopback ports");
        Harness.Check(worker.Contains("ws://127.0.0.1"), "the extension only talks to loopback");

        // ---------------------------------------------------------------- settings
        var store = new MemoryStore();
        var settings = new Settings(store);
        settings.SetBool("climbPages", true);
        settings.SetBool("askedToSeePages", true);
        settings.Save(force: true);
        var reread = new Settings(store);
        Harness.Check(reread.GetBool("climbPages", false), "climbPages survives a save and reload");
        Harness.Check(reread.GetBool("askedToSeePages", false), "the once-only page question is remembered");

        return Harness.Summarise("stage 18 talking spider and web pages");
    }

    static SurfaceMap BasicMap()
    {
        var desk = new DesktopState { VirtualBounds = new Rect(0, 0, 1600, 900) };
        desk.Screens.Add(new ScreenFrame
        {
            Id = "screen:0", Frame = new Rect(0, 0, 1600, 900), VisibleFrame = new Rect(0, 0, 1600, 860), Main = true, Dpi = 96
        });
        var map = new SurfaceMap();
        map.Rebuild(desk, 0.78);
        return map;
    }

    static PagePicture SyntheticPage()
    {
        const int w = 720, h = 480;
        var px = new uint[w * h];
        Array.Fill(px, 0x00F0F0F0u);
        void Fill(int x0, int y0, int x1, int y1, uint colour)
        {
            for (int y = Math.Max(0, y0); y < Math.Min(h, y1); y++)
                for (int x = Math.Max(0, x0); x < Math.Min(w, x1); x++) px[y * w + x] = colour;
        }
        Fill(0, 0, w, 44, 0x00303030);          // the browser's own top bar
        Fill(80, 120, 640, 400, 0x00FFFFFF);    // a card on a light page
        Fill(120, 320, 330, 360, 0x002E6FA8);   // a button inside it
        return new PagePicture(w, h, px);
    }

    static string ProjectRoot()
    {
        string? dir = AppContext.BaseDirectory;
        while (!string.IsNullOrEmpty(dir))
        {
            if (File.Exists(Path.Combine(dir, "WINDOWS_PORT_SPEC.md"))) return dir;
            dir = Directory.GetParent(dir)?.FullName;
        }
        return Directory.GetCurrentDirectory();
    }

    sealed class MemoryStore : ITextFileStore
    {
        readonly Dictionary<string, string> _files = new();
        public string? Read(string name) => _files.TryGetValue(name, out var text) ? text : null;
        public void Write(string name, string contents) => _files[name] = contents;
        public string? ReadIn(string folder, string name) => Read(Path.Combine(folder, name));
        public void WriteIn(string folder, string name, string contents) => Write(Path.Combine(folder, name), contents);
        public void DeleteIn(string folder, string name) => _files.Remove(Path.Combine(folder, name));
        public IEnumerable<string> List(string folder) => _files.Keys.Where(k => k.StartsWith(folder)).ToList();
        public string Describe() => "memory";
    }
}
