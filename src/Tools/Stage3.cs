using SpiderBuddy.Core;
using SpiderBuddy.Renderer;

namespace SpiderBuddy.Tools;

/// <summary>
/// Stage 3 acceptance (spec 3 "Done when"):
///  - the spider is drawn from a pose, correctly anti-aliased, and every Studio option changes it;
///  - the profile → front → profile sweep shows no leg flip;
///  - the draw radius (72) covers every pose and option;
///  - a contact sheet of every pose and option exists to compare against the Mac.
/// Plus the anatomy constants of 3.4 and the palette of 3.4.
/// </summary>
public static class Stage3
{
    public static int Run(string[] args)
    {
        bool buildSheets = !args.Contains("--no-sheets");
        AnatomyChecks();
        PaletteChecks();
        LegRigChecks();
        KneeChecks();
        YawChecks();
        DrawRadiusChecks();
        OptionChecks();
        DesignChecks();
        if (buildSheets) SheetChecks();
        return Harness.Summarise("stage 3 drawing");
    }

    // ------------------------------------------------------------------ anatomy

    static void AnatomyChecks()
    {
        Harness.Section("anatomy constants (spec 3.4)");

        Harness.Near(SpiderRenderer.Ground, -22, 0, "ground is −22 (hence standoff 22)");
        Harness.Near(SpiderRenderer.DrawRadius, 72, 0, "draw radius is 72");
        Harness.Near(SpiderRenderer.BodyLength, 46, 0, "body length is ~46 units");
        Harness.Check(SpiderRenderer.LeanPivot.DistanceTo(new V2(1, -8)) < 1e-12, "lean pivot (1,−8) sits between the hips");
        Harness.Near(SpiderRenderer.AbdomenC.X, -14, 0, "abdomen centre x");
        Harness.Near(SpiderRenderer.AbdomenC.Y, 3, 0, "abdomen centre y");
        Harness.Near(SpiderRenderer.HeadC.X, 9.5, 0, "head centre x");
        Harness.Near(SpiderRenderer.HeadR, 13, 0, "head radius");
        Harness.Near(SpiderRenderer.BallCentre.X, -6, 0, "ball centre x");
        Harness.Check(SpiderRenderer.Neck.DistanceTo(new V2(-2, 0)) < 1e-12, "neck at (−2,0)");

        // eyes: 4 each, the two anterior-median big
        Harness.Check(SpiderRenderer.ProfileEyes.Length == 4, "four profile eyes");
        Harness.Check(SpiderRenderer.FrontEyes.Length == 4, "four front eyes");
        Harness.Check(SpiderRenderer.ProfileEyes[0].c.DistanceTo(new V2(16.2, 1.2)) < 1e-12, "near anterior-median at (16.2,1.2)");
        Harness.Near(SpiderRenderer.ProfileEyes[0].r, 4.7, 1e-12, "near anterior-median radius 4.7");
        Harness.Check(SpiderRenderer.ProfileEyes[0].big && SpiderRenderer.ProfileEyes[1].big, "the two anterior-medians are big");
        Harness.Check(!SpiderRenderer.ProfileEyes[2].big && !SpiderRenderer.ProfileEyes[3].big, "the laterals are small");
        Harness.Check(SpiderRenderer.FrontEyes[0].c.DistanceTo(new V2(4.8, 0.2)) < 1e-12, "front eye at (4.8,0.2)");
        Harness.Check(SpiderRenderer.FrontEyes.Select(e => e.c.X).OrderBy(x => x).SequenceEqual(new[] { -11.6, -4.8, 4.8, 11.6 }),
            "the front face is symmetric about x = 0");

        // the front view must be symmetric under i ↔ 7−i for the legs (spec 3.4)
        bool symmetric = true;
        for (int i = 0; i < 4; i++)
        {
            var a = SpiderRig.Rig(i, 0);
            var b = SpiderRig.Rig(SpiderRig.Mirror(i), 0);
            if (Math.Abs(a.Foot.X + b.Foot.X) > 1e-9) symmetric = false;
        }
        Harness.Check(symmetric, "front-view legs pair under mirror i ↔ 7−i");
    }

    static void PaletteChecks()
    {
        Harness.Section("palette (spec 3.4)");

        var p = Palette.Reference;
        void Close(Rgba a, double r, double g, double b, string what)
        {
            bool ok = Math.Abs(a.R - r) < 1e-9 && Math.Abs(a.G - g) < 1e-9 && Math.Abs(a.B - b) < 1e-9;
            Harness.Check(ok, what, ok ? null : $"got {a}");
        }
        Close(p.Outline, 0.298, 0.180, 0.086, "outline (0.298,0.180,0.086)");
        Close(p.Body, 0.878, 0.604, 0.333, "body fill (0.878,0.604,0.333)");
        Close(p.BodyLight, 0.945, 0.729, 0.486, "body light (0.945,0.729,0.486)");
        Close(p.Head, 0.898, 0.655, 0.392, "head (0.898,0.655,0.392)");
        Close(p.LegFill, 0.788, 0.518, 0.278, "leg fill (0.788,0.518,0.278)");
        Close(p.LegLight, 0.855, 0.596, 0.345, "leg light (0.855,0.596,0.345)");
        Close(p.FarLeg, 0.690, 0.435, 0.220, "far-side leg (0.690,0.435,0.220)");
        Close(p.FarOutline, 0.255, 0.150, 0.070, "far outline (0.255,0.150,0.070)");
        Close(p.EyeDark, 0.239, 0.129, 0.055, "eye dark (0.239,0.129,0.055)");

        // far-side legs are a shade darker than near-side ones
        Harness.Check(p.FarLeg.Luma < p.LegFill.Luma, "far legs are darker than near legs");
        Harness.Check(p.FarOutline.Luma < p.Outline.Luma, "far outline is darker too");

        // a coat actually changes the palette, and living coats animate with time
        var look = new SpiderLook { Coat = CoatStyle.Rainbow };
        var poseA = PoseBuilder.Standing(new SpiderDesign(), 1) ; poseA.Time = 0;
        var poseB = PoseBuilder.Standing(new SpiderDesign(), 1); poseB.Time = 1.5;
        var a = SpiderRenderer.PaletteFor(look, poseA);
        var b = SpiderRenderer.PaletteFor(look, poseB);
        Harness.Check(a.Body.Luma != b.Body.Luma || a.Body.R != b.Body.R, "a living coat changes over time");
        var plain = SpiderRenderer.PaletteFor(new SpiderLook(), poseA);
        Harness.Check(plain.Body.Distance(new Rgba(0.878, 0.604, 0.333)) < 1e-9, "no coat is the reference body colour");

        // camouflage drifts toward the surroundings rather than flashing
        var camo = new SpiderLook { Coat = CoatStyle.Camouflage };
        poseA.Surroundings = new Rgba(0.2, 0.7, 0.3);
        var c1 = SpiderRenderer.PaletteFor(camo, poseA);
        Harness.Check(c1.Body.G > c1.Body.R, "camouflage takes the colour behind it");
    }

    static void LegRigChecks()
    {
        Harness.Section("leg rig (spec 3.4)");

        var profile = new[]
        {
            new[] { new V2(9, -9), new V2(24, 2), new V2(30, -22) },
            new[] { new V2(6, -10), new V2(15, -8), new V2(18, -22) },
            new[] { new V2(1, -10), new V2(-6, -5), new V2(-6, -22) },
            new[] { new V2(-3, -9), new V2(-17, -1), new V2(-24, -22) },
            new[] { new V2(7, -7), new V2(21, 5), new V2(26, -22) },
            new[] { new V2(4, -8), new V2(11, 1), new V2(13, -22) },
            new[] { new V2(-1, -8), new V2(-11, 2), new V2(-13, -22) },
            new[] { new V2(-5, -7), new V2(-21, 3), new V2(-30, -22) },
        };
        bool allOk = true;
        for (int i = 0; i < 8; i++)
        {
            var rig = SpiderRig.Rig(i, 1);
            if (rig.Hip.DistanceTo(profile[i][0]) > 1e-9) allOk = false;
            if (rig.Knee.DistanceTo(profile[i][1]) > 1e-9) allOk = false;
            if (rig.Foot.DistanceTo(profile[i][2]) > 1e-9) allOk = false;
        }
        Harness.Check(allOk, "all eight profile legs match the reference table exactly");

        Harness.Check(SpiderRig.Rig(0, 1).Foot.X > 0, "near 0 reaches ahead of the face");
        Harness.Check(SpiderRig.Rig(3, 1).Foot.X < 0, "near 3 reaches behind");
        Harness.Check(SpiderRig.Rig(4, 1).Hip.Y > SpiderRig.Rig(0, 1).Hip.Y - 1, "far legs sit a little higher");
        Harness.Check(SpiderRig.IsFar(4) && !SpiderRig.IsFar(3), "legs 4–7 are the far side");
        for (int i = 0; i < 8; i++)
            Harness.Near(SpiderRig.Rig(i, 0.5).Foot.Y, SpiderRig.Ground, 1e-12, $"leg {i} foot is on the ground at mid-yaw");

        // leg styles change the rig but keep feet on the ledge
        var classic = SpiderRig.Rig(0, 1);
        var longLeg = SpiderRig.Style(classic, LegStyle.Long, default);
        Harness.Check(Math.Abs(longLeg.Foot.X) > Math.Abs(classic.Foot.X), "long legs stand wider");
        Harness.Near(longLeg.Foot.Y, SpiderRig.Ground, 1e-12, "long legs stay on the ledge");
        var stubby = SpiderRig.Style(classic, LegStyle.Stubby, default);
        Harness.Check(Math.Abs(stubby.Foot.X) < Math.Abs(classic.Foot.X), "stubby legs stand narrower");

        Harness.Near(SpiderRig.LegLength(0, 1), Math.Sqrt(21 * 21 + 13 * 13), 1e-9, "leg 0 length is |hip→foot|");
        Harness.Check(SpiderRig.LegLength(3, 1) > 20, "leg length is measurable for the reach limiter");
        Harness.Check(SpiderRig.LongestLegLength(1) > SpiderRig.LongestLegLength(0) * 0.8, "longest leg length is sane");
    }

    static void KneeChecks()
    {
        Harness.Section("the classic knee model (spec 3.4, 4.6)");

        var rest = SpiderRig.Rig(0, 1);

        // At rest the knee must be exactly the rest knee (the model is a no-op there).
        var knee = SpiderRig.Knee(rest.Hip, rest.Foot, rest);
        Harness.Check(knee.DistanceTo(rest.Knee) < 1e-9, "at rest the knee is the rest knee", $"{knee} vs {rest.Knee}");

        // Move the foot out: the knee swings about the hip and keeps its rest shape.
        var outFoot = rest.Foot + new V2(6, 0);
        var outKnee = SpiderRig.Knee(rest.Hip, outFoot, rest);
        var restOffset = rest.Knee - rest.Hip;
        var outOffset = outKnee - rest.Hip;
        Harness.Check(Math.Abs(outOffset.Length / restOffset.Length - M.Clamp(rest.Hip.DistanceTo(outFoot) / rest.Hip.DistanceTo(rest.Foot), 0.5, 1.3)) < 0.02,
            "the knee scales with how far the foot is from the hip");
        Harness.Check(outKnee.DistanceTo(rest.Knee) > 0.5, "moving the foot moves the knee");

        // Foot closer than rest: the leg folds, and the thigh keeps its length.
        var inFoot = rest.Hip + (rest.Foot - rest.Hip) * 0.6;
        var inKnee = SpiderRig.Knee(rest.Hip, inFoot, rest);
        double a = restOffset.Length;
        Harness.Near(inKnee.DistanceTo(rest.Hip), a, 0.6, "a folded leg keeps its thigh length");
        Harness.Check(inKnee.DistanceTo(rest.Hip) < a + 0.6, "the folded knee does not fly out");

        // The knee never crosses to the other side of the hip→foot line (no leg swapping).
        bool sameSide = Math.Sign((inKnee - rest.Hip).Cross(inFoot - rest.Hip)) == Math.Sign(restOffset.Cross(rest.Foot - rest.Hip))
                      || Math.Abs((inKnee - rest.Hip).Cross(inFoot - rest.Hip)) < 1e-6;
        Harness.Check(sameSide, "a folding knee bends the same way as its rest shape");

        // Real IK exists for a thread grip and bends outward from the thread.
        var ik = SpiderRig.KneeIk(new V2(0, 0), new V2(0, -30), 20, 20, new V2(-10, -15));
        Harness.Check(ik.X > 0, "the line-grip IK bends away from the thread", $"knee at {ik}");
    }

    static void YawChecks()
    {
        Harness.Section("turning is a yaw, not a mirror (spec 3.4, 4.7)");

        Harness.Near(SpiderRig.ProfileAmount(1), 1, 1e-12, "yaw 1 is full profile");
        Harness.Near(SpiderRig.ProfileAmount(-1), 1, 1e-12, "yaw −1 is full profile too");
        Harness.Near(SpiderRig.ProfileAmount(0), 0, 1e-12, "yaw 0 is the front view");
        Harness.Near(SpiderRig.ProfileAmount(0.5), 0.5, 1e-12, "yaw 0.5 is halfway (smoothstep)");
        Harness.Check(SpiderRig.ProfileAmount(0.3) < SpiderRig.ProfileAmount(0.7), "profile amount rises with yaw");

        // The sweep must be continuous: no leg jumps more than a few units between steps.
        var design = Sheets.DefaultDesign();
        var sweep = PoseBuilder.TurnSweep(design, 40).ToList();
        double worstJump = 0;
        for (int s = 1; s < sweep.Count; s++)
        {
            for (int i = 0; i < 8; i++)
            {
                worstJump = Math.Max(worstJump, sweep[s].Legs[i].Foot.DistanceTo(sweep[s - 1].Legs[i].Foot));
                worstJump = Math.Max(worstJump, sweep[s].Legs[i].Knee.DistanceTo(sweep[s - 1].Legs[i].Knee));
            }
        }
        Harness.Check(worstJump < 3.0, "the profile → front → profile sweep is continuous", $"worst jump {worstJump:0.00}");

        // At the exact front view the leg pairs coincide across the mirror (nothing pops).
        var front = PoseBuilder.Standing(design, 0);
        bool paired = true;
        for (int i = 0; i < 4; i++)
            if (Math.Abs(front.Legs[i].Foot.X + front.Legs[7 - i].Foot.X) > 1e-6) paired = false;
        Harness.Check(paired, "at the front view the feet are re-paired symmetrically");

        // Sanity: the pose sweep ends facing the other way
        Harness.Check(sweep[0].Facing > 0.99 && sweep[^1].Facing < -0.99, "the sweep runs +1 → −1");
    }

    static void DrawRadiusChecks()
    {
        Harness.Section("draw radius (spec 3.3) — the cliptest");

        var design = Sheets.DefaultDesign();
        var worst = (label: "", radius: 0.0);
        void Test(string label, SpiderPose pose, SpiderLook look)
        {
            var (r, bmp) = SpriteRaster.Measure(pose, look);
            bmp.Dispose();
            if (r > worst.radius) worst = (label, r);
            if (r > SpiderRenderer.DrawRadius)
                Harness.Fail($"draw radius covers: {label}", $"{r:0.0} > 72");
        }

        Test("profile", PoseBuilder.Standing(design, 1), design.Look);
        Test("three-quarter", PoseBuilder.Standing(design, 0.5), design.Look);
        Test("front", PoseBuilder.Standing(design, 0), design.Look);
        Test("balled", PoseBuilder.Balled(design), design.Look);
        Test("curled", PoseBuilder.Curled(design), design.Look);
        Test("hanging", PoseBuilder.Hanging(design), design.Look);
        Harness.Ok("core poses measured");

        // every leg style, every hat, every accessory, every coat
        foreach (var name in Enum.GetNames<LegStyle>())
        {
            if (!Enum.TryParse<LegStyle>(name, out var v)) continue;
            var look = design.Look.Clone(); look.Legs = v;
            Test($"legs {name}", PoseBuilder.Standing(design, 0.85), look);
        }
        Harness.Ok("all leg styles measured");
        foreach (var name in Enum.GetNames<HatStyle>())
        {
            if (!Enum.TryParse<HatStyle>(name, out var v)) continue;
            var look = design.Look.Clone(); look.Hat = v;
            Test($"hat {name}", PoseBuilder.Standing(design, 0.8), look);
        }
        Harness.Ok("all hats measured");
        foreach (var name in Enum.GetNames<AccessoryStyle>())
        {
            if (!Enum.TryParse<AccessoryStyle>(name, out var v)) continue;
            var look = design.Look.Clone(); look.Accessory = v;
            Test($"extra {name}", PoseBuilder.Standing(design, 0.8), look);
        }
        Harness.Ok("all extras measured");
        foreach (var name in Enum.GetNames<CoatStyle>())
        {
            if (!Enum.TryParse<CoatStyle>(name, out var v)) continue;
            var look = design.Look.Clone(); look.Coat = v;
            Test($"coat {name}", PoseBuilder.Standing(design, 0.8), look);
        }
        Harness.Ok("all coats measured");
        foreach (var name in Enum.GetNames<BodyShape>())
        {
            if (!Enum.TryParse<BodyShape>(name, out var v)) continue;
            var look = design.Look.Clone(); look.Body = v;
            Test($"body {name}", PoseBuilder.Standing(design, 0.65), look);
        }
        Harness.Ok("all body shapes measured");

        Harness.Check(worst.radius <= SpiderRenderer.DrawRadius,
            $"drawRadius 72 covers every pose and option (worst {worst.radius:0.0} at '{worst.label}')");
        Harness.Check(worst.radius > 20, "something was actually drawn", $"worst radius {worst.radius:0.0}");

        // sprite side: max(100, round(72·2·scale))
        Harness.Near(SpriteRaster.SpriteSide(1.0), 144, 1e-9, "sprite side at scale 1");
        Harness.Near(SpriteRaster.SpriteSide(0.62), 100, 1e-9, "sprite side is floored at 100");
        Harness.Near(SpriteRaster.SpriteSide(1.55), 223, 1e-9, "sprite side at Chonky");
        Harness.Near(SpriteRaster.WindowSlack, 68, 0, "window slack is 68");
    }

    static void OptionChecks()
    {
        Harness.Section("the option inventory (spec 3.6)");

        Harness.Check(Enum.GetNames<BodyShape>().Length == 12, "11 body shapes + custom", $"{Enum.GetNames<BodyShape>().Length}");
        Harness.Check(Enum.GetNames<EyeStyle>().Length == 14, "13 eye styles + custom");
        Harness.Check(Enum.GetNames<BrowStyle>().Length == 10, "10 brows");
        Harness.Check(Enum.GetNames<FangStyle>().Length == 11, "11 mouths/fangs");
        // Spec 3.6 says "38 hats" / "30 extras" but its own lists enumerate 37 and 29; every named
        // option in the document is present here. The discrepancy is recorded in progress.md.
        Harness.Check(Enum.GetNames<HatStyle>().Length - 1 == 37, "every hat named in the spec is present", $"{Enum.GetNames<HatStyle>().Length - 1}");
        Harness.Check(Enum.GetNames<AccessoryStyle>().Length - 1 == 29, "every extra named in the spec is present", $"{Enum.GetNames<AccessoryStyle>().Length - 1}");
        Harness.Check(Enum.GetNames<LegStyle>().Length == 14, "13 leg styles + custom");
        Harness.Check(Enum.GetNames<PatternStyle>().Length == 20, "20 markings", $"{Enum.GetNames<PatternStyle>().Length}");
        Harness.Check(Enum.GetNames<FuzzLevel>().Length == 3, "3 fuzz levels");

        int flat = 0, grad = 0, living = 0;
        foreach (var n in Enum.GetNames<CoatStyle>())
        {
            if (!Enum.TryParse<CoatStyle>(n, out var c)) continue;
            int v = (int)c;
            if (v >= (int)CoatStyle.Espresso && v <= (int)CoatStyle.Pistachio) flat++;
            else if (v >= (int)CoatStyle.Sunset && v <= (int)CoatStyle.Nebula) grad++;
            else if (v >= (int)CoatStyle.Rainbow && v <= (int)CoatStyle.WebSlinger) living++;
        }
        Harness.Check(flat == 30, "30 flat coats", $"{flat}");
        Harness.Check(grad == 16, "16 gradient coats", $"{grad}");
        Harness.Check(living == 15, "15 living coats", $"{living}");

        // body-shape multipliers
        var look = new SpiderLook { Body = BodyShape.Chonk };
        var m = look.ShapeMultipliers;
        Harness.Check(m.X > 1.2 && m.Y > 1.2 && m.Z > 1.0, "Chonk is big in every direction");
        look.Body = BodyShape.BigHead;
        Harness.Check(look.ShapeMultipliers.Z > 1.2, "Big Head has a big head");

        // eye scale
        look.Eyes = EyeStyle.Huge;
        Harness.Near(look.EyeScale, 1.22, 1e-12, "Huge eyes are ×1.22");
        look.Eyes = EyeStyle.Beady;
        Harness.Near(look.EyeScale, 0.7, 1e-12, "Beady eyes are ×0.7");

        // symmetry detection
        Harness.Check(new SpiderLook().FaceOnSymmetric, "a plain look is face-on symmetric");
        Harness.Check(!new SpiderLook { Hat = HatStyle.Cowboy }.FaceOnSymmetric, "a cowboy hat is lopsided");
        Harness.Check(!new SpiderLook { Eyes = EyeStyle.Wink }.FaceOnSymmetric, "a wink is lopsided");
    }

    static void DesignChecks()
    {
        Harness.Section("designs save and load tolerantly (spec 1.5, 3.6)");

        var d = Sheets.DefaultDesign();
        d.Look.Hat = HatStyle.Propeller;
        d.Personality.Affection = 0.9;
        d.Habits.Wander = 0.75;
        string json = d.ToJson();
        var back = SpiderDesign.FromJson(json);
        Harness.Check(back.Look.Hat == HatStyle.Propeller, "the look round-trips");
        Harness.Near(back.Personality.Affection, 0.9, 1e-12, "personality round-trips");
        Harness.Near(back.Habits.Wander, 0.75, 1e-12, "a habit dial round-trips");
        Harness.Check(back.Name == "Biscuit", "the name round-trips");

        // an older save with keys missing must default, not throw
        var old = SpiderDesign.FromJson("""{"name":"Old","look":{"hat":3}}""");
        Harness.Check(old.Name == "Old", "an old minimal save loads its name");
        Harness.Check(old.Look.Hat == HatStyle.Crown, "an old save loads its hat (enum by number)");
        Harness.Near(old.Habits.Swing, 0.5, 1e-12, "a habit absent from an old save defaults to 0.5");
        Harness.Near(old.Personality.Laziness, 0.25, 1e-12, "personality absent from an old save defaults");

        Harness.Check(SpiderDesign.FromJson("").Name == "", "an empty save is a default design");
        Harness.Check(SpiderDesign.FromJson("{not json").Name == "", "a corrupt save is a default design, no throw");
        Harness.Check(SpiderDesign.FromJson("null").Name == "", "a null save is a default design");

        // habit weights: 0 = never, 0.5 = as usual, 1 = every chance it gets
        Harness.Near(Habits.Weight(0.0), 0, 1e-12, "habit 0 → never");
        Harness.Near(Habits.Weight(0.5), 1, 1e-12, "habit 0.5 → as usual");
        Harness.Near(Habits.Weight(0.25), 0.5, 1e-12, "habit 0.25 → half as often");
        Harness.Check(Habits.Weight(1.0) >= 100_000, "habit 1 → every chance it gets");
        Harness.Check(Habits.Weight(0.8) > 3 && Habits.Weight(0.8) < 400, "habit 0.8 is a strong, finite push");

        Harness.Check(new Habits().Dials.Count == 31, "the Studio exposes every habit dial", $"{new Habits().Dials.Count}");
        Harness.Check(Personality.Preset(Temperament.Hyper).Energy > 0.9, "Hyper is energetic");
        Harness.Check(Personality.Preset(Temperament.Lazy).Laziness > 0.85, "Lazy is lazy");
    }

    static void SheetChecks()
    {
        Harness.Section("contact sheets (spec 3.10)");

        string contact = Sheets.ContactSheet();
        Harness.Check(File.Exists(contact), "contact.png written");
        Harness.Check(new FileInfo(contact).Length > 5000, "contact.png has content", $"{new FileInfo(contact).Length} bytes");

        var sheets = Sheets.OptionSheets();
        Harness.Check(sheets.Count == 8, "eight option sheets", $"{sheets.Count}");
        bool allExist = sheets.All(s => File.Exists(s) && new FileInfo(s).Length > 2000);
        Harness.Check(allExist, "every option sheet has content");
        Console.WriteLine($"    sheets in {Path.GetFullPath(Sheets.OutputDir)}");
    }
}

static class RgbaExt
{
    public static double Distance(this Rgba a, Rgba b)
        => Math.Abs(a.R - b.R) + Math.Abs(a.G - b.G) + Math.Abs(a.B - b.B);
}
