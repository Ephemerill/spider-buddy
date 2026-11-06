using SkiaSharp;
using SpiderBuddy.Core;
using SpiderBuddy.Renderer;

namespace SpiderBuddy.Tools;

/// <summary>
/// Contact sheets (spec 3.10): every Studio option rendered as a thumbnail, plus the spider in
/// profile / 3/4 / front, each leg style, each hat, a rolled ball, curled asleep and hanging.
/// These are the judge for art changes.
/// </summary>
public static class Sheets
{
    public const int Cell = 190;

    public static string OutputDir
    {
        get
        {
            string dir = Environment.GetEnvironmentVariable("SPIDER_OUT") ?? "out";
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    /// <summary>Draw a labelled grid of poses into a PNG.</summary>
    public static string Grid(string path, IReadOnlyList<(string label, SpiderPose pose, SpiderLook look)> cells,
        int columns = 6, double scale = 1.0, bool checkerboard = true)
    {
        int rows = (cells.Count + columns - 1) / columns;
        int w = columns * Cell, h = rows * Cell;
        using var bmp = new SKBitmap(new SKImageInfo(w, h, SKColorType.Bgra8888, SKAlphaType.Premul));
        using (var canvas = new SKCanvas(bmp))
        {
            canvas.Clear(new SKColor(0x24, 0x26, 0x2b));

            for (int i = 0; i < cells.Count; i++)
            {
                int cx = (i % columns) * Cell;
                int cy = (i / columns) * Cell;
                canvas.Save();
                canvas.Translate(cx, cy);
                if (checkerboard)
                {
                    using var soft = new SKPaint { Color = new SKColor(0x2e, 0x31, 0x38) };
                    canvas.DrawRect(2, 2, Cell - 4, Cell - 4, soft);
                }
                canvas.Save();
                canvas.Translate(Cell / 2f, Cell / 2f + 4);
                canvas.Scale(1, -1);   // world is y-up, Skia is y-down
                var draw = new SkiaDraw(canvas);
                var pose = cells[i].pose.Clone();
                pose.Pos = V2.Zero;
                pose.Scale = scale;
                SpiderRenderer.Draw(draw, pose, cells[i].look, drawNameTag: false);
                canvas.Restore();

                using var text = new SKPaint { Color = new SKColor(0xc8, 0xcc, 0xd4), IsAntialias = true };
                using var font = new SKFont(SKTypeface.Default, 11);
                canvas.DrawText(cells[i].label, 8, Cell - 10, SKTextAlign.Left, font, text);
                canvas.Restore();
            }
        }
        using var img = SKImage.FromBitmap(bmp);
        using var data = img.Encode(SKEncodedImageFormat.Png, 100);
        File.WriteAllBytes(path, data.ToArray());
        return path;
    }

    /// <summary>The main contact sheet: poses, turn sweep, styles, moods, weather.</summary>
    public static string ContactSheet(string? designJson = null)
    {
        var design = designJson is null ? DefaultDesign() : SpiderDesign.FromJson(designJson);
        var cells = new List<(string, SpiderPose, SpiderLook)>();

        for (int i = 0; i < 5; i++)
        {
            double f = i / 4.0;   // 1 → 0 : profile to front
            cells.Add(($"yaw {f:0.00} (profile→front)", PoseBuilder.Standing(design, f, 1.0), design.Look));
        }
        for (int i = 0; i < 5; i++)
        {
            double f = -i / 4.0;  // 0 → −1 : front to the other profile
            cells.Add(($"yaw {f:0.00} (front→profile)", PoseBuilder.Standing(design, f, 1.0), design.Look));
        }

        var asleep = PoseBuilder.Standing(design, 1, 1.0);
        asleep.Sleep = 1;
        asleep.Blink = 1;
        asleep.AbdomenSway = 0.2;
        cells.Add(("asleep (Zzz)", asleep, design.Look));

        var balled = PoseBuilder.Balled(design);
        cells.Add(("rolled ball", balled, design.Look));
        cells.Add(("curled (hammock)", PoseBuilder.Curled(design), design.Look));
        cells.Add(("hanging on silk", PoseBuilder.Hanging(design), design.Look));

        var wet = PoseBuilder.Standing(design, 0.6, 1.0);
        wet.Wet = 1; wet.Chill = 0.3;
        cells.Add(("wet", wet, design.Look));

        var snowy = PoseBuilder.Standing(design, 0.6, 1.0);
        snowy.Snow = 1; snowy.Chill = 0.8;
        cells.Add(("snow", snowy, design.Look));

        var dusty = PoseBuilder.Standing(design, 0.6, 1.0);
        dusty.Dust = 1;
        cells.Add(("dusty", dusty, design.Look));

        var happy = PoseBuilder.Standing(design, 0.2, 1.0);
        happy.Happy = 1; happy.Emote = EmoteKind.Heart; happy.EmoteT = 0.5;
        cells.Add(("happy + hearts", happy, design.Look));

        var startle = PoseBuilder.Standing(design, 1, 1.0);
        startle.Startled = 1; startle.Emote = EmoteKind.Exclaim; startle.EmoteT = 0.5;
        cells.Add(("startled (!)", startle, design.Look));

        var thought = PoseBuilder.Standing(design, 0.35, 1.0);
        thought.Thought = ThoughtKind.Dots; thought.Emote = EmoteKind.Thought; thought.EmoteT = 0.6;
        cells.Add(("thinking", thought, design.Look));

        var named = PoseBuilder.Standing(design, 1, 1.0);
        named.NameTag = 1; named.Name = "Biscuit";
        cells.Add(("name tag", named, design.Look));

        var low = PoseBuilder.Standing(design, 1, 1.0);
        low.BodyPitch = -0.38; low.Lift = -3;
        cells.Add(("peek (nose down)", low, design.Look));

        var up = PoseBuilder.Standing(design, 1, 1.0);
        up.BodyPitch = 0.22; up.Lift = 2;
        cells.Add(("arms up / greet", up, design.Look));

        return Grid(Path.Combine(OutputDir, "contact.png"), cells, 6);
    }

    /// <summary>Every option as a thumbnail: body shapes, eyes, brows, mouths, leg styles, coats, markings, hats, extras.</summary>
    public static List<string> OptionSheets(SpiderDesign? design = null)
    {
        design ??= DefaultDesign();
        var written = new List<string>();

        // --- bodies
        var bodies = new List<(string, SpiderPose, SpiderLook)>();
        var bodyNames = Enum.GetNames<BodyShape>();
        for (int i = 0; i < bodyNames.Length; i++)
        {
            var look = design.Look.Clone();
            look.Body = (BodyShape)i;
            bodies.Add((bodyNames[i], PoseBuilder.Standing(design, 0.75, 1.0), look));
        }
        written.Add(Grid(Path.Combine(OutputDir, "options-bodies.png"), bodies, 6));

        // --- eyes
        var eyes = new List<(string, SpiderPose, SpiderLook)>();
        var eyeNames = Enum.GetNames<EyeStyle>();
        for (int i = 0; i < eyeNames.Length; i++)
        {
            var look = design.Look.Clone();
            look.Eyes = (EyeStyle)i;
            eyes.Add((eyeNames[i], PoseBuilder.Standing(design, 0.0, 1.0), look));
        }
        written.Add(Grid(Path.Combine(OutputDir, "options-eyes.png"), eyes, 6));

        // --- brows / mouths
        var brows = new List<(string, SpiderPose, SpiderLook)>();
        var browNames = Enum.GetNames<BrowStyle>();
        for (int i = 0; i < browNames.Length; i++)
        {
            var look = design.Look.Clone();
            look.Brows = (BrowStyle)i;
            brows.Add((browNames[i], PoseBuilder.Standing(design, 0.0, 1.0), look));
        }
        var mouthNames = Enum.GetNames<FangStyle>();
        for (int i = 0; i < mouthNames.Length; i++)
        {
            var look = design.Look.Clone();
            look.Fangs = (FangStyle)i;
            brows.Add(("mouth: " + mouthNames[i], PoseBuilder.Standing(design, 0.0, 1.0), look));
        }
        written.Add(Grid(Path.Combine(OutputDir, "options-face.png"), brows, 6));

        // --- legs
        var legs = new List<(string, SpiderPose, SpiderLook)>();
        var legNames = Enum.GetNames<LegStyle>();
        for (int i = 0; i < legNames.Length; i++)
        {
            var look = design.Look.Clone();
            look.Legs = (LegStyle)i;
            legs.Add((legNames[i], PoseBuilder.Standing(design, 0.85, 1.0), look));
        }
        written.Add(Grid(Path.Combine(OutputDir, "options-legs.png"), legs, 5));

        // --- coats
        var coats = new List<(string, SpiderPose, SpiderLook)>();
        var coatNames = Enum.GetNames<CoatStyle>();
        foreach (var name in coatNames)
        {
            if (!Enum.TryParse<CoatStyle>(name, out var coat)) continue;
            var look = design.Look.Clone();
            look.Coat = coat;
            var pose = PoseBuilder.Standing(design, 0.7, 1.0, time: 0.8);
            pose.Surroundings = new Rgba(0.35, 0.55, 0.30);
            coats.Add((name, pose, look));
        }
        written.Add(Grid(Path.Combine(OutputDir, "options-coats.png"), coats, 7));

        // --- markings
        var marks = new List<(string, SpiderPose, SpiderLook)>();
        var patNames = Enum.GetNames<PatternStyle>();
        foreach (var name in patNames)
        {
            if (!Enum.TryParse<PatternStyle>(name, out var pat)) continue;
            var look = design.Look.Clone();
            look.Pattern = pat;
            look.Accent = new Rgba(0.10, 0.06, 0.03);
            marks.Add((name, PoseBuilder.Standing(design, 0.8, 1.0), look));
        }
        written.Add(Grid(Path.Combine(OutputDir, "options-markings.png"), marks, 7));

        // --- hats
        var hats = new List<(string, SpiderPose, SpiderLook)>();
        foreach (var name in Enum.GetNames<HatStyle>())
        {
            if (!Enum.TryParse<HatStyle>(name, out var hat)) continue;
            var look = design.Look.Clone();
            look.Hat = hat;
            hats.Add((name, PoseBuilder.Standing(design, 0.8, 1.0), look));
        }
        written.Add(Grid(Path.Combine(OutputDir, "options-hats.png"), hats, 8));

        // --- extras
        var extras = new List<(string, SpiderPose, SpiderLook)>();
        foreach (var name in Enum.GetNames<AccessoryStyle>())
        {
            if (!Enum.TryParse<AccessoryStyle>(name, out var acc)) continue;
            var look = design.Look.Clone();
            look.Accessory = acc;
            extras.Add((name, PoseBuilder.Standing(design, 0.8, 1.0), look));
        }
        written.Add(Grid(Path.Combine(OutputDir, "options-extras.png"), extras, 8));

        return written;
    }

    public static SpiderDesign DefaultDesign()
    {
        // The owner's own spider: Small (0.78), a friendly affable character.
        var d = new SpiderDesign
        {
            Name = "Biscuit",
            Personality = Personality.Preset(Temperament.Friendly)
        };
        d.Gait.Motion = LegMotion.Classic;
        return d;
    }
}
