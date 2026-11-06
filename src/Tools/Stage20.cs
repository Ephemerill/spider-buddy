using System.Diagnostics;
using System.Text;
using System.Text.Json;
using SkiaSharp;
using SpiderBuddy.Core;
using Activity = SpiderBuddy.Core.Activity;
using SpiderBuddy.Renderer;

namespace SpiderBuddy.Tools;

/// <summary>
/// Stage 20 — the test and verification harness. These are the Windows equivalents of the
/// macOS sim, preview, film, jerk, legs, bench, gallery, beat, perch and pages tools. The
/// checks deliberately run the same core used by the app, on the Stage 2 synthetic desktop.
/// </summary>
public static class Stage20
{
    const double Dt = 1.0 / 60;
    const double WalkSpeed = 62;
    static readonly double[] Scales = { 0.62, 0.78, 0.95, 1.2, 1.55 };
    static readonly Temperament[] Temperaments =
    {
        Temperament.Friendly, Temperament.Shy, Temperament.Hyper, Temperament.Lazy,
        Temperament.Curious, Temperament.ShowOff, Temperament.Chill, Temperament.Grumpy
    };

    public static int Run(string[] args)
    {
        string mode = args.Length == 0 ? "all" : args[0].ToLowerInvariant();
        if (mode is "help" or "--help" or "-h") { Help(); return 0; }
        if (mode is not ("all" or "gate" or "sim" or "preview" or "film" or "jerk" or "legs"
            or "bench" or "gallery" or "beat" or "ears" or "perch" or "pages" or "hooks"))
        {
            Console.Error.WriteLine($"unknown stage20 mode '{mode}' — try: sim, film, jerk, legs, bench, perch, pages, gate");
            return 2;
        }

        bool all = mode is "all" or "gate";
        if (all || mode == "sim") SimChecks();
        if (all || mode == "preview") PreviewChecks();
        if (all || mode == "gallery") GalleryChecks();
        if (all || mode == "film") FilmChecks();
        if (all || mode == "jerk") JerkChecks();
        if (all || mode == "legs") LegChecks();
        if (all || mode == "bench") BenchChecks();
        if (all || mode is "beat" or "ears") MusicChecks();
        if (all || mode == "perch") PerchChecks(args);
        if (all || mode == "pages") PageChecks();
        if (all || mode == "hooks") HookChecks();
        if (mode == "gate") ReleaseGate(args);
        return Harness.Summarise("stage 20 test and verification harness");
    }

    static void Help()
    {
        Console.WriteLine("""
        Spider Buddy — Stage 20 verification harness

          sim      4-minute synthetic roaming sim, scripted interactions, every temperament
          preview  contact sheet and every Studio option sheet; draw-radius cliptest
          film     walk, desk, corner, turn, peekaboo, hunt, jump, hang, swing, hammock,
                   dance and hand-off film strips
          jerk     planted-foot / body / heading jerk detector over a minute of walking
          legs     flat-top invariance at all five sizes, all leg styles and both corner radii
          bench    per-frame update and sprite-raster timings
          gallery  the Studio thumbnails / contact-sheet inventory
          beat     music recognition and dance behaviour (ears)
          perch    all habitat biomes, A* navigation and a living-tank soak
          pages    the synthetic page picture through the pixel page reader
          hooks    the app's SPIDER_* performance test-hook source checks
          gate     run all of the above and print the release-gate summary
          all      every harness section

        Every command prints [ok]/[FAIL] and exits non-zero on failure.
        """);
    }

    // ------------------------------------------------------------------ simulator

    static void SimChecks()
    {
        Harness.Section("stage 20 sim — four simulated minutes and scripted passes");

        var (_, s) = Scene(2001);
        var bouts = Simulate(s, 240);
        Harness.Check(Finite(s), "four simulated minutes leave a finite spider", s.Pos.ToString());
        Harness.Check(bouts.Count >= 20, "the four-minute run has a real activity rhythm", $"{bouts.Count} bouts");
        Harness.Check(bouts.Select(b => b.a).Distinct().Count() >= 5, "the four-minute run is varied",
            string.Join(",", bouts.Select(b => b.a).Distinct()));
        Harness.Check(s.Decisions > 10, "the brain makes decisions", $"{s.Decisions}");

        var (_, grab) = Scene(2002);
        grab.BeginGrab(grab.Pos + new V2(4, 0));
        Harness.Check(grab.IsHeld, "grab starts from the body");
        for (int i = 0; i < 30; i++) grab.MoveGrab(grab.Pos + new V2(40 + i, 20));
        grab.EndGrab(new V2(700, 240));
        for (int i = 0; i < 180; i++) grab.Update(Dt);
        Harness.Check(Finite(grab), "grab, drag and throw end in a finite state", grab.Mode.ToString());

        var (_, rappel) = Scene(2003);
        bool dropped = rappel.DropOnWeb();
        for (int i = 0; i < 180; i++) rappel.Update(Dt);
        Harness.Check(dropped && rappel.WebActive, "rappel drops and stays on its line");
        Harness.Check(Finite(rappel), "rappel ends in a finite state");

        var back = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 1, "back", corner: 8));
        var underneath = new Spider(Sheets.DefaultDesign(), Synth.Build(back, 0.78), new Rng(2004));
        underneath.SetAnchor("win:1", 0, 220, 1);
        var covered = back.With(Synth.Window(2, 100, 200, 1400, 750, 0, "front", corner: 8));
        underneath.SetMap(Synth.Build(covered, 0.78));
        for (int i = 0; i < 30; i++) underneath.Update(Dt);
        Harness.Check(underneath.Mode != Mode.Attached || underneath.Anchor.LoopId != "win:1",
            "a window closing underneath moves it off the old surface", underneath.Mode.ToString());

        var (_, pet) = Scene(2005);
        pet.Poke();
        for (int i = 0; i < 30; i++) pet.Update(Dt);
        Harness.Check(pet.Happy.Value > 0.01 || pet.Happy.Velocity != 0, "petting reaches the body-language springs");

        var (_, swing) = Scene(2006);
        swing.DropOnWeb();
        for (int i = 0; i < 60; i++) swing.Update(Dt);
        swing.StartSwing();
        for (int i = 0; i < 720; i++) swing.Update(Dt);
        Harness.Check(Finite(swing), "a full swing runs without a non-finite state", swing.Mode.ToString());

        var (_, hammock) = Scene(2007);
        Harness.Check(hammock.BuildHammock(), "the sim starts a hammock");
        for (int i = 0; i < 60 * 14; i++) hammock.Update(Dt);
        Harness.Check(hammock.Hammock.Finished, "the hammock build completes in the sim",
            $"{hammock.Hammock.Progress:0.00}");
        Harness.Check(hammock.NapInHammock(), "the sim can nap in it");
        for (int i = 0; i < 60; i++) hammock.Update(Dt);
        Harness.Check(Finite(hammock) && hammock.InHammock, "the hammock nap is stable");
        hammock.WipeHammock(hammock.Hammock.Bed, 80);
        hammock.WipeHammock(hammock.Hammock.Bed, 80);
        Harness.Check(!hammock.Hammock.Exists, "two wipes remove the finished hammock");

        foreach (var temperament in Temperaments)
        {
            var design = Sheets.DefaultDesign();
            design.Personality = Personality.Preset(temperament);
            var sp = new Spider(design, BasicMap(), new Rng(2100 + (ulong)temperament));
            sp.SetAnchor("win:1", 0, 200, 1);
            var run = Simulate(sp, 150);
            Harness.Check(Finite(sp) && run.Count > 0, $"{temperament}: 150 s temperament run is finite");
        }

        var (_, cinema) = Scene(2101);
        cinema.EnterCinema(new Rect(0, 0, 1920, 1080));
        Harness.Check(cinema.Cinema, "cinema manners enter on a full display");
        for (int i = 0; i < 120; i++) cinema.Update(Dt);
        Harness.Check(cinema.Activity is Activity.Walk or Activity.Watch, "cinema settles to watch",
            cinema.Activity.ToString());
        cinema.ExitCinema();
        Harness.Check(!cinema.Cinema, "leaving cinema restores normal manners");

        var maximized = new DesktopState { VirtualBounds = new Rect(0, 0, 1920, 1080) };
        maximized.Screens.Add(new ScreenFrame
        {
            Id = "screen:0", Frame = new Rect(0, 0, 1920, 1080),
            VisibleFrame = new Rect(0, 40, 1920, 1040), Main = true, Dpi = 96
        });
        var maxMap = Synth.Build(maximized.Cinema(), 0.78);
        Harness.Check(maxMap.LoopCount >= 2, "maximized/cinema gives the floor-and-ceiling stage",
            $"{maxMap.LoopCount} loops");

        var (_, weather) = Scene(2102);
        weather.SetWeather(61, 12, false, 9);
        Harness.Check(weather.Raining && weather.WeatherWind == 12, "weather reaches the spider");

        var (_, music) = Scene(2103);
        music.BrainEnabled = false;
        music.SetMusic(true, 120, 0.9);
        for (int i = 0; i < 240; i++) music.Update(Dt);
        Harness.Check(music.DanceCount == 1 && music.Activity == Activity.Groove,
            "three steady seconds of music starts one dance", $"{music.DanceCount} {music.Activity}");

        Harness.Check(Finite(s), "the simulator leaves the original spider intact");
    }

    static List<(Activity a, double dur)> Simulate(Spider s, double seconds, Action<Spider>? each = null)
    {
        var bouts = new List<(Activity, double)>();
        Activity last = s.Activity;
        double since = 0;
        int frames = (int)Math.Round(seconds / Dt);
        for (int i = 0; i < frames; i++)
        {
            each?.Invoke(s);
            s.Update(Dt);
            if (s.Activity != last)
            {
                bouts.Add((last, since));
                last = s.Activity;
                since = 0;
            }
            since += Dt;
        }
        bouts.Add((last, since));
        return bouts;
    }

    static bool Finite(Spider s) =>
        double.IsFinite(s.Pos.X) && double.IsFinite(s.Pos.Y) &&
        double.IsFinite(s.Heading) && double.IsFinite(s.Facing);

    // ------------------------------------------------------------------ preview / gallery

    static void PreviewChecks()
    {
        Harness.Section("stage 20 preview — contact sheet and draw-radius cliptest");
        string contact = Sheets.ContactSheet();
        Harness.Check(File.Exists(contact) && new FileInfo(contact).Length > 5000,
            "contact.png is a real contact sheet", $"{new FileInfo(contact).Length} bytes");

        var designs = new List<(string label, SpiderPose pose, SpiderLook look)>();
        var design = Sheets.DefaultDesign();
        foreach (double yaw in new[] { 1.0, 0.5, 0.0, -0.5, -1.0 })
            designs.Add(($"yaw {yaw:0.0}", PoseBuilder.Standing(design, yaw, 1.0), design.Look));
        designs.Add(("balled", PoseBuilder.Balled(design), design.Look));
        designs.Add(("curled", PoseBuilder.Curled(design), design.Look));
        designs.Add(("hanging", PoseBuilder.Hanging(design), design.Look));
        double worst = 0;
        string worstName = "";
        foreach (var item in designs)
        {
            var (radius, bmp) = SpriteRaster.Measure(item.pose, item.look);
            bmp.Dispose();
            if (radius > worst) { worst = radius; worstName = item.label; }
        }
        Harness.Check(worst <= SpiderRenderer.DrawRadius,
            "drawRadius 72 covers profile, blind spots and the turn sweep", $"{worst:0.0} at {worstName}");
        Harness.Check(worst > 20, "the cliptest actually measured the spider", $"{worst:0.0}");
        Harness.Near(SpriteRaster.SpriteSide(0.62), 100, 1e-9, "sprite side is floored at 100");
        Harness.Near(SpriteRaster.SpriteSide(1.55), 223, 1e-9, "sprite side at Chonky");
    }

    static void GalleryChecks()
    {
        Harness.Section("stage 20 gallery — Studio thumbnails");
        var sheets = Sheets.OptionSheets();
        Harness.Check(sheets.Count == 8, "all eight Studio option sheets are produced", $"{sheets.Count}");
        Harness.Check(sheets.All(p => File.Exists(p) && new FileInfo(p).Length > 2000),
            "every Studio thumbnail sheet has content");
        string index = Path.Combine(Sheets.OutputDir, "gallery.txt");
        File.WriteAllLines(index, sheets.Select(Path.GetFileName)!);
        Harness.Check(File.Exists(index) && new FileInfo(index).Length > 0, "gallery.txt indexes the thumbnails");
    }

    // ------------------------------------------------------------------ films

    static void FilmChecks()
    {
        Harness.Section("stage 20 film — the owner judges what is drawn");

        var (_, walk) = Scene(2201);
        walk.BrainEnabled = false;
        walk.Walk(1, 8);
        WriteFilm("film-walk.png", walk, 24, 3, "walk cycle");

        var corner = CornerScene(2202);
        corner.BrainEnabled = false;
        corner.Walk(1, 8);
        WriteFilm("film-corner.png", corner, 24, 3, "rounded corner");

        var (_, turn) = Scene(2203);
        turn.BrainEnabled = false;
        turn.TurnTo(-turn.WalkDir);
        WriteFilm("film-turn.png", turn, 18, 2, "turn on the spot");

        var (_, peek) = Scene(2204);
        peek.BrainEnabled = false;
        if (!peek.StartPeekaboo()) peek.Play(Activity.Peek, 1.4);
        WriteFilm("film-peekaboo.png", peek, 20, 3, "peek-a-boo");

        var (_, hunt) = Scene(2205);
        hunt.BrainEnabled = false;
        var prey = hunt.ReleasePrey(PreyKind.Cricket, hunt.Pos + new V2(120, 0));
        if (prey is not null) hunt.StartHunt(prey);
        WriteFilm("film-hunt-cricket.png", hunt, 24, 4, "cricket hunt");

        var jump = JumpScene(2206);
        jump.BrainEnabled = false;
        if (!jump.StartJump(TargetOnSecondWindow(jump))) jump.Play(Activity.Crouch, 0.5);
        WriteFilm("film-jump.png", jump, 20, 3, "leap");

        var (_, hang) = Scene(2207);
        hang.BrainEnabled = false;
        if (!hang.DropOnWeb()) hang.Play(Activity.Rappel, 1);
        WriteFilm("film-hang.png", hang, 20, 3, "hang");

        var (_, swing) = Scene(2208);
        swing.BrainEnabled = false;
        if (swing.DropOnWeb())
        {
            for (int i = 0; i < 60; i++) swing.Update(Dt);
            swing.StartSwing();
        }
        WriteFilm("film-swing.png", swing, 24, 3, "swing");

        var (_, hammock) = Scene(2209);
        hammock.BrainEnabled = false;
        hammock.BuildHammock();
        WriteFilm("film-hammock.png", hammock, 24, 12, "hammock build");

        var (_, dance) = Scene(2210);
        dance.BrainEnabled = false;
        dance.Play(Activity.Dance, 3);
        WriteFilm("film-dance.png", dance, 20, 3, "dance");

        var (_, seq) = Scene(2211);
        seq.BrainEnabled = false;
        seq.Walk(1, 2);
        var cells = new List<(string, SpiderPose, SpiderLook)>();
        for (int i = 0; i < 10; i++)
        {
            for (int k = 0; k < 2; k++) seq.Update(Dt);
            cells.Add(($"walk {i}", seq.BuildPose(), seq.Design.Look));
        }
        seq.TurnTo(-seq.WalkDir);
        for (int i = 0; i < 10; i++)
        {
            for (int k = 0; k < 2; k++) seq.Update(Dt);
            cells.Add(($"turn {i}", seq.BuildPose(), seq.Design.Look));
        }
        string seqPath = Sheets.Grid(Path.Combine(Sheets.OutputDir, "film-seq.png"), cells, 6, 1.0);
        Harness.Check(File.Exists(seqPath) && new FileInfo(seqPath).Length > 4000,
            "film-seq.png carries the walk → turn hand-off");

        string desk = DeskFilm();
        Harness.Check(File.Exists(desk) && new FileInfo(desk).Length > 5000,
            "film-desk.png shows actual-size poses on a mock desktop", $"{new FileInfo(desk).Length} bytes");
        Console.WriteLine($"    films in {Path.GetFullPath(Sheets.OutputDir)}");
    }

    static string WriteFilm(string name, Spider sp, int frames, int every, string label)
    {
        var cells = new List<(string, SpiderPose, SpiderLook)>();
        for (int i = 0; i < frames; i++)
        {
            for (int k = 0; k < every; k++) sp.Update(Dt);
            cells.Add(($"{label} {(i + 1) * every / 60.0:0.00}s", sp.BuildPose(), sp.Design.Look));
        }
        string path = Sheets.Grid(Path.Combine(Sheets.OutputDir, name), cells, 6, 1.0, checkerboard: true);
        Harness.Check(File.Exists(path) && new FileInfo(path).Length > 4000,
            $"{name} is a real film strip", $"{new FileInfo(path).Length} bytes");
        return path;
    }

    static string DeskFilm()
    {
        const int W = 1200, H = 720;
        using var bmp = new SKBitmap(new SKImageInfo(W, H, SKColorType.Bgra8888, SKAlphaType.Premul));
        using var canvas = new SKCanvas(bmp);
        canvas.Clear(new SKColor(0x1d, 0x21, 0x27));
        canvas.Save();
        canvas.Translate(0, H);
        canvas.Scale(1, -1);
        using var fill = new SKPaint { Color = new SKColor(0x2a, 0x32, 0x3d), IsAntialias = true };
        using var window = new SKPaint { Color = new SKColor(0x72, 0x78, 0x82), IsAntialias = true, Style = SKPaintStyle.Stroke, StrokeWidth = 1.5f };
        using var accent = new SKPaint { Color = new SKColor(0xd9, 0x82, 0x2b), IsAntialias = true, Style = SKPaintStyle.Stroke, StrokeWidth = 2 };
        canvas.DrawRect(35, 35, W - 70, H - 75, fill);
        canvas.DrawRect(180, 270, 690, 330, fill);
        canvas.DrawRect(180, 270, 690, 330, window);
        canvas.DrawRect(35, 35, W - 70, 40, new SKPaint { Color = new SKColor(0x39, 0x42, 0x4e) });
        canvas.DrawLine(35, 75, W - 35, 75, accent);
        canvas.DrawLine(35, 35, 35, H - 40, accent);
        canvas.DrawLine(W - 35, 35, W - 35, H - 40, accent);
        canvas.DrawLine(35, H - 40, W - 35, H - 40, accent);

        var design = Sheets.DefaultDesign();
        void SpiderAt(double x, double y, double heading, string label)
        {
            var pose = PoseBuilder.Standing(design, 1, 0.78);
            pose.Pos = new V2(x, y);
            pose.Heading = heading;
            pose.Grounded = 1;
            SpiderRenderer.Draw(new SkiaDraw(canvas), pose, design.Look, drawNameTag: false);
        }
        SpiderAt(520, 600, 0, "window top");
        SpiderAt(870, 435, -Math.PI / 2, "window side");
        SpiderAt(520, 270, Math.PI, "window bottom");
        SpiderAt(180, 435, Math.PI / 2, "window side");
        SpiderAt(520, 75, 0, "taskbar");
        canvas.Restore();

        using var text = new SKPaint { Color = new SKColor(0xc8, 0xcc, 0xd4), IsAntialias = true };
        using var font = new SKFont(SKTypeface.Default, 13);
        canvas.DrawText("Desk — screen rim, window top/sides/bottom, taskbar (actual size)", 42, 30, SKTextAlign.Left, font, text);
        using var img = SKImage.FromBitmap(bmp);
        using var data = img.Encode(SKEncodedImageFormat.Png, 100);
        string path = Path.Combine(Sheets.OutputDir, "film-desk.png");
        File.WriteAllBytes(path, data.ToArray());
        return path;
    }

    // ------------------------------------------------------------------ jerk / legs

    static void JerkChecks()
    {
        Harness.Section("stage 20 jerk — body, heading and foot teleports");
        var (_, s) = Scene(2301);
        s.BrainEnabled = false;
        s.Walk(1, 5);
        V2 prevPos = s.Pos;
        double prevHeading = s.HeadingSpring.Value;
        var prevFoot = new V2[8];
        var prevStance = new bool[8];
        for (int i = 0; i < 8; i++) { prevFoot[i] = s.WorldFoot(i); prevStance[i] = !s.Gait.Legs[i].InSwing; }
        int flags = 0, bodyFlags = 0, headingFlags = 0, footFlags = 0;
        var groups = new Dictionary<string, int>();
        Activity last = s.Activity;
        const int seconds = 60;
        for (int f = 0; f < seconds * 60; f++)
        {
            if (s.Activity != Activity.Walk && s.Mode == Mode.Attached) s.Walk(1, 3);
            s.Update(Dt);
            if (s.Mode != Mode.Attached)
            {
                prevPos = s.Pos; prevHeading = s.HeadingSpring.Value;
                for (int i = 0; i < 8; i++) { prevFoot[i] = s.WorldFoot(i); prevStance[i] = false; }
                last = s.Activity;
                continue;
            }
            V2 body = s.Pos + new V2(0, s.BodyLift).Rotated(s.HeadingSpring.Value);
            double bodyStep = s.Pos.DistanceTo(prevPos);
            double headingStep = Math.Abs(M.WrapPi(s.HeadingSpring.Value - prevHeading));
            double footStep = 0;
            for (int i = 0; i < 8; i++)
            {
                bool stance = !s.Gait.Legs[i].InSwing;
                if (stance && prevStance[i]) footStep = Math.Max(footStep, s.WorldFoot(i).DistanceTo(prevFoot[i]));
                prevFoot[i] = s.WorldFoot(i);
                prevStance[i] = stance;
            }
            bool flag = bodyStep > 14 || headingStep > 0.6 || footStep > 8;
            if (flag)
            {
                flags++;
                if (bodyStep > 14)
                {
                    bodyFlags++;
                    Console.WriteLine($"    body jump f{f} d={bodyStep:0.0} {last}->{s.Activity} " +
                        $"{s.Anchor.LoopId}:{s.Anchor.SegIdx} t={s.Anchor.T:0.0} " +
                        $"{prevPos} -> {s.Pos}");
                }
                if (headingStep > 0.6) headingFlags++;
                if (footStep > 8) footFlags++;
                string key = $"{last}→{s.Activity}";
                groups[key] = groups.TryGetValue(key, out int n) ? n + 1 : 1;
            }
            prevPos = s.Pos; prevHeading = s.HeadingSpring.Value;
            last = s.Activity;
        }
        Harness.Check(flags <= 2, "jerk stays under 2 flags per minute", $"{flags} flags ({bodyFlags} body, {headingFlags} heading, {footFlags} foot)");
        Harness.Check(bodyFlags == 0, "the body never teleports while walking", $"{bodyFlags}");
        Harness.Check(headingFlags == 0, "the drawn heading never jumps", $"{headingFlags}");
        Harness.Check(footFlags == 0, "a planted foot never teleports relative to the body", $"{footFlags}");
        if (groups.Count > 0)
            Console.WriteLine("    jerk groups: " + string.Join(", ", groups.Select(g => $"{g.Key}={g.Value}")));
    }

    static void LegChecks()
    {
        Harness.Section("stage 20 legs — flat-top invariance at every size");
        var baseline = new V2[8];
        double worstNorm = 0;
        double worstFootY = 0;
        for (int k = 0; k < Scales.Length; k++)
        {
            double scale = Scales[k];
            var (map, s) = WindowScene(scale, 2401 + (ulong)k);
            s.SetAnchor("win:1", 0, 400, 1);
            var local = new V2[8];
            for (int i = 0; i < 8; i++)
            {
                local[i] = (s.WorldFoot(i) - s.Pos) / scale;
                worstFootY = Math.Max(worstFootY, Math.Abs(s.WorldFoot(i).Y - 800));
            }
            if (k == 0) baseline = local;
            else for (int i = 0; i < 8; i++) worstNorm = Math.Max(worstNorm, local[i].DistanceTo(baseline[i]));

            var spot = map.NearestSpot(new V2(500, 800), 300, null, scale);
            Harness.Check(spot is not null, $"scale {scale:0.00}: a flat window top has a spot");
            var anchor = new Anchor("win:1", 0, 400, 1);
            var resolved = map.Resolve(anchor, Spider.CornerRadius * scale);
            Harness.Check(resolved.Pos.DistanceTo(map.Loop("win:1")!.Segs[0].Point(400)) < 1e-9,
                $"scale {scale:0.00}: the flat segment is not rounded");
        }
        Harness.Check(worstNorm < 0.5, "flat-top feet normalize identically at all five sizes", $"{worstNorm:0.000}");
        Harness.Check(worstFootY < 1.5, "all feet stay on the real top edge", $"{worstFootY:0.000}");

        int styleFailures = 0;
        var design = Sheets.DefaultDesign();
        foreach (var name in Enum.GetNames<LegStyle>())
        {
            if (!Enum.TryParse<LegStyle>(name, out var style)) continue;
            var (_, s) = WindowScene(0.78, 2402);
            s.Design.Look.Legs = style;
            s.SetAnchor("win:1", 0, 400, 1);
            for (int i = 0; i < 8; i++)
                if (!double.IsFinite(s.WorldFoot(i).X) || Math.Abs(s.WorldFoot(i).Y - 800) > 2.5) styleFailures++;
        }
        Harness.Check(styleFailures == 0, "all 13 leg styles keep feet on the flat ledge", $"{styleFailures} bad feet");

        var rounded = new DesktopState { VirtualBounds = new Rect(0, 0, 1920, 1080) };
        rounded.Screens.Add(new ScreenFrame
        {
            Id = "screen:0", Frame = new Rect(0, 0, 1920, 1080),
            VisibleFrame = new Rect(0, 40, 1920, 1040), Main = true, Dpi = 96
        });
        rounded.Windows.Add(Synth.Window(1, 200, 300, 900, 500, 0, "rounded", corner: 30));
        var roundedMap = Synth.Build(rounded, 0.78);
        var rr = new Spider(design, roundedMap, new Rng(2403)) { UserScale = 0.78, BrainEnabled = false };
        rr.SetAnchor("win:1", 0, roundedMap.Loop("win:1")!.Segs[0].Len - 30, 1);
        rr.Walk(1, 2);
        bool cornerFinite = true;
        for (int i = 0; i < 180; i++) { rr.Update(Dt); cornerFinite &= Finite(rr); }
        Harness.Check(cornerFinite, "rounded corners keep finite feet and heading");
    }

    // ------------------------------------------------------------------ bench / music

    static void BenchChecks()
    {
        Harness.Section("stage 20 bench — per-frame cost");
        var (_, s) = WindowScene(0.78, 2501);
        s.BrainEnabled = true;
        var update = new List<double>();
        var render = new List<double>();
        var poses = new List<SpiderPose>();
        var sw = new Stopwatch();
        for (int i = 0; i < 180; i++)
        {
            sw.Restart();
            s.Update(Dt);
            update.Add(sw.Elapsed.TotalMilliseconds);
            poses.Add(s.BuildPose());
        }
        for (int i = 0; i < 90; i++)
        {
            sw.Restart();
            using var bmp = SpriteRaster.Render(poses[i % poses.Count], s.Design.Look, s.UserScale);
            render.Add(sw.Elapsed.TotalMilliseconds);
        }
        double updateMean = update.Average(), updateWorst = update.Max();
        double renderMean = render.Average(), renderWorst = render.Max();
        Harness.Check(updateMean < 8, "core update mean is under half a frame", $"{updateMean:0.00} ms");
        Harness.Check(updateWorst < 25, "core update worst is under 25 ms", $"{updateWorst:0.00} ms");
        Harness.Check(renderMean < 12, "sprite raster mean is under a frame", $"{renderMean:0.00} ms");
        Harness.Check(renderWorst < 40, "sprite raster worst is bounded", $"{renderWorst:0.00} ms");
        string path = Path.Combine(Sheets.OutputDir, "bench.txt");
        File.WriteAllText(path,
            $"update mean {updateMean:0.000} ms worst {updateWorst:0.000} ms{Environment.NewLine}" +
            $"render mean {renderMean:0.000} ms worst {renderWorst:0.000} ms{Environment.NewLine}" +
            $"frames {update.Count} update / {render.Count} render{Environment.NewLine}");
        Harness.Check(File.Exists(path), "bench.txt records the timing run");
        Console.WriteLine($"    update {updateMean:0.00}/{updateWorst:0.00} ms · raster {renderMean:0.00}/{renderWorst:0.00} ms");
    }

    static void MusicChecks()
    {
        Harness.Section("stage 20 beat / ears — music and dance");
        var (_, s) = Scene(2601);
        s.BrainEnabled = false;
        s.SetMusic(true, 120, 0.9);
        for (int i = 0; i < 210; i++) s.Update(Dt);
        Harness.Check(s.DanceCount == 1 && s.Activity == Activity.Groove, "three steady seconds starts one groove");

        var (_, quiet) = Scene(2602);
        quiet.BrainEnabled = false;
        quiet.SetMusic(true, 120, 0.2);
        for (int i = 0; i < 300; i++) quiet.Update(Dt);
        Harness.Check(quiet.DanceCount == 0, "low-confidence music is not danced to");

        var (_, off) = Scene(2603);
        off.BrainEnabled = false;
        off.DanceToMusic = false;
        off.SetMusic(true, 120, 0.9);
        for (int i = 0; i < 240; i++) off.Update(Dt);
        Harness.Check(off.DanceCount == 0, "Dance to Music off means no groove");

        var (_, habit) = Scene(2604);
        habit.BrainEnabled = false;
        habit.Design.Habits.DanceMusic = 0;
        habit.SetMusic(true, 120, 0.9);
        for (int i = 0; i < 240; i++) habit.Update(Dt);
        Harness.Check(habit.DanceCount == 0, "a zero music habit means no groove");

        var (_, cooldown) = Scene(2605);
        cooldown.BrainEnabled = false;
        cooldown.SetMusic(true, 120, 0.9);
        for (int i = 0; i < 210; i++) cooldown.Update(Dt);
        cooldown.SetMusic(false);
        for (int i = 0; i < 31 * 60; i++) cooldown.Update(Dt);
        cooldown.SetMusic(true, 120, 0.9);
        for (int i = 0; i < 30; i++) cooldown.Update(Dt);
        Harness.Check(cooldown.DanceCount == 1, "a short silence does not allow an immediate repeat");
    }

    // ------------------------------------------------------------------ habitat / pages

    static void PerchChecks(string[] args)
    {
        Harness.Section("stage 20 perch — habitat worlds, navigation and soak");
        int seconds = ArgInt(args, "--habitat-seconds", 120);
        var world = HabitatWorld.Preset(HabitatBiome.Forest, new Rect(0, 0, 4042, 1242));
        var map = world.BuildMap(0.78);
        var knowledge = new HabitatKnowledge();
        knowledge.Meet(world);
        var mind = new TankMind();
        mind.Refresh(world, map, knowledge, 0.78);
        var spider = new Spider(Sheets.DefaultDesign(), map, new Rng(2701)) { BrainEnabled = true };
        var spot = world.GroundSpot(map, 0.78, 900);
        if (spot is { } sp) spider.SetAnchor(sp.Anchor.LoopId, sp.Anchor.SegIdx, sp.Anchor.T, sp.Anchor.Dir);
        else spider.SetAnchor(map.AllLoops.First().Id, 0, 20, 1);
        var weather = new WeatherClock(new WeatherSettings { Mode = WeatherMode.Always, Always = WeatherKind.Rain }, HabitatBiome.Forest, 12);
        weather.Force(WeatherKind.Rain);
        bool finite = true;
        for (int i = 0; i < seconds * 60; i++)
        {
            spider.Update(Dt);
            mind.Update(Dt, spider, weather.Conditions(WeatherClock.Now, i / 60.0), knowledge, 0.78);
            if (i % 20 == 0) mind.Ecology.Update(0.333, weather.Conditions(WeatherClock.Now, i / 60.0), 0.78);
            if (!Finite(spider)) { finite = false; break; }
        }
        Harness.Check(finite, $"the living tank survives a {seconds} s rain soak", spider.Pos.ToString());
        Harness.Check(mind.Status.Length > 0, "the tank has a current mind status");
        Harness.Check(mind.Thirst is >= 0 and <= 1 && mind.Hunger is >= 0 and <= 1, "tank urges stay bounded");

        for (int i = 0; i < HabitatBiomes.All.Length; i++)
        {
            var biome = HabitatBiomes.All[i];
            var w = HabitatWorld.Preset(biome, new Rect(0, 0, 4042, 1242));
            var m = w.BuildMap(0.78);
            var nav = new TankNav(m, 0.78);
            Harness.Check(m.LoopCount >= 2 && nav.Nodes.Count > 0,
                $"{biome}: a preset builds surfaces and A* nodes", $"{m.LoopCount} loops, {nav.Nodes.Count} nodes");
        }

        var back = HabitatWorld.FromJson(world.ToJson());
        Harness.Check(back.Items.Count == world.Items.Count && back.Bounds.W == world.Bounds.W,
            "habitat JSON round-trips through the perch harness");
        Harness.Check(HabitatWorld.PresetNames.Length == 9, "all nine habitat presets remain available");
    }

    static void PageChecks()
    {
        Harness.Section("stage 20 pages — a picture of a web page");
        var picture = SyntheticPage();
        var settings = PageReader.Settings.ForScale(0.9);
        int top = PageReader.PageTop(picture, 180, settings);
        Harness.Check(top is >= 35 and <= 55, "the page reader finds the browser's top bar", $"{top}");
        var area = new Rect(0, top + 2, picture.Width, picture.Height - top - 2);
        var edges = PageReader.Edges(picture, settings, area);
        Harness.Check(edges.Count >= 4, "page ledges are found", $"{edges.Count}");
        Harness.Check(edges.Any(e => e.Horizontal) && edges.Any(e => !e.Horizontal),
            "both horizontal and upright page ledges are found");
        var chains = PageReader.Chains(edges, settings.Trim, settings.Trim);
        Harness.Check(chains.Count > 0 && chains.Any(c => c.Points.Count >= 2),
            "page ledges chain into walkable runs");
        var again = PageReader.Edges(picture, settings, area);
        Harness.Check(again.Count == edges.Count && again.Zip(edges).All(p =>
                p.First.Horizontal == p.Second.Horizontal && p.First.Pos == p.Second.Pos &&
                p.First.Lo == p.Second.Lo && p.First.Hi == p.Second.Hi && p.First.Side == p.Second.Side),
            "reading the same page twice is stable", $"{edges.Count} then {again.Count}");
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
        Fill(0, 0, w, 44, 0x00303030);
        Fill(80, 120, 640, 400, 0x00FFFFFF);
        Fill(120, 320, 330, 360, 0x002E6FA8);
        return new PagePicture(w, h, px);
    }

    // ------------------------------------------------------------------ hooks / gate

    static void HookChecks()
    {
        Harness.Section("stage 20 app hooks — source contract");
        string root = ProjectRoot();
        string appDir = Path.Combine(root, "src", "App");
        string program = File.ReadAllText(Path.Combine(appDir, "Program.cs"));
        string appSource = string.Join("\n", Directory.GetFiles(appDir, "*.cs").Select(File.ReadAllText));
        Harness.Check(appSource.Contains("SPIDER_TIMING", StringComparison.Ordinal) &&
                      appSource.Contains("SPIDER_FRAMES", StringComparison.Ordinal) &&
                      appSource.Contains("SPIDER_STATS", StringComparison.Ordinal) &&
                      appSource.Contains("SPIDER_OPEN_TIMING", StringComparison.Ordinal),
            "the app exposes timing, frames, stats and open-timing hooks");
        Harness.Check(program.Contains("--stage20-smoke", StringComparison.Ordinal),
            "the app exposes a Stage 20 host smoke hook");
        string gate = Path.Combine(root, "tools", "windows", "release-gate.ps1");
        Harness.Check(File.Exists(gate), "the Windows release-gate script exists");
    }

    static void ReleaseGate(string[] args)
    {
        Harness.Section("stage 20 release gate");
        string outDir = Sheets.OutputDir;
        string[] expected =
        {
            "film-walk.png", "film-desk.png", "film-corner.png", "film-turn.png",
            "film-peekaboo.png", "film-hunt-cricket.png", "film-jump.png", "film-hang.png",
            "film-swing.png", "film-hammock.png", "film-dance.png", "film-seq.png",
            "contact.png", "bench.txt", "gallery.txt"
        };
        int missing = expected.Count(n => !File.Exists(Path.Combine(outDir, n)));
        Harness.Check(missing == 0, "all release-gate artifacts are present", $"{missing} missing");
        Harness.Check(Environment.GetEnvironmentVariable("SPIDER_RELEASE_GATE") == "1",
            "the gate is running under the release-gate wrapper");
        Console.WriteLine("    RELEASE GATE: sim/film/jerk/legs/bench/preview pages/perch checked.");
        Console.WriteLine("    Full 30-minute desktop and habitat soaks are separate measured gates.");
    }

    // ------------------------------------------------------------------ scenes

    static (SurfaceMap map, Spider s) Scene(ulong seed)
    {
        var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26));
        var map = Synth.Build(desk, 0.78);
        var s = new Spider(Sheets.DefaultDesign(), map, new Rng(seed));
        s.SetAnchor("win:1", 0, 220, 1);
        return (map, s);
    }

    static (SurfaceMap map, Spider s) WindowScene(double scale, ulong seed)
    {
        var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26));
        var map = Synth.Build(desk, scale);
        var s = new Spider(Sheets.DefaultDesign(), map, new Rng(seed)) { UserScale = scale };
        return (map, s);
    }

    static Spider CornerScene(ulong seed)
    {
        var desk = Synth.Desktop().With(Synth.Window(1, 200, 300, 900, 500, 0, "notepad", corner: 26));
        var map = Synth.Build(desk, 0.78);
        var s = new Spider(Sheets.DefaultDesign(), map, new Rng(seed)) { UserScale = 0.78 };
        var loop = map.Loop("win:1")!;
        s.SetAnchor("win:1", 0, Math.Max(0, loop.Segs[0].Len - 45), 1);
        return s;
    }

    static Spider JumpScene(ulong seed)
    {
        var desk = Synth.Desktop()
            .With(Synth.Window(1, 160, 300, 620, 300, 0, "launch", corner: 12))
            .With(Synth.Window(2, 1000, 500, 620, 300, 1, "target", corner: 12));
        var map = Synth.Build(desk, 0.78);
        var s = new Spider(Sheets.DefaultDesign(), map, new Rng(seed)) { UserScale = 0.78 };
        s.SetAnchor("win:1", 0, 300, 1);
        return s;
    }

    static V2 TargetOnSecondWindow(Spider s)
    {
        var loop = s.Map.Loop("win:2");
        return loop is null ? s.Pos + new V2(300, 100) : loop.Segs[0].Point(300);
    }

    static SurfaceMap BasicMap()
    {
        var desk = Synth.Desktop().With(Synth.Window(1, 100, 200, 1200, 500, 0, "notepad", corner: 8));
        return Synth.Build(desk, 0.78);
    }

    static int ArgInt(string[] args, string name, int fallback)
    {
        string? value = args.FirstOrDefault(a => a.StartsWith(name + "=", StringComparison.Ordinal))?[(name.Length + 1)..];
        int at = Array.IndexOf(args, name);
        if (value is null && at >= 0 && at + 1 < args.Length && !args[at + 1].StartsWith("--")) value = args[at + 1];
        return int.TryParse(value, out int n) ? Math.Clamp(n, 1, 7200) : fallback;
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
}
