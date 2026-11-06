using SpiderBuddy.Core;

namespace SpiderBuddy.Renderer;

/// <summary>
/// Every colour the spider is drawn with (spec 3.4 palette, derived from the Look).
/// Far-side legs and body parts sit in shadow and are drawn a shade darker.
/// </summary>
public readonly struct Palette
{
    public readonly Rgba Outline, Body, BodyLight, Head, HeadLight, LegFill, LegLight, FarLeg, FarOutline, EyeDark, Accent, White;

    public Palette(Rgba outline, Rgba body, Rgba bodyLight, Rgba head, Rgba headLight,
                   Rgba legFill, Rgba legLight, Rgba farLeg, Rgba farOutline, Rgba eyeDark, Rgba accent)
    {
        Outline = outline; Body = body; BodyLight = bodyLight; Head = head; HeadLight = headLight;
        LegFill = legFill; LegLight = legLight; FarLeg = farLeg; FarOutline = farOutline;
        EyeDark = eyeDark; Accent = accent; White = Rgba.White;
    }

    public static Palette Reference => new(
        new Rgba(0.298, 0.180, 0.086),   // outline
        new Rgba(0.878, 0.604, 0.333),   // body fill
        new Rgba(0.945, 0.729, 0.486),   // body light
        new Rgba(0.898, 0.655, 0.392),   // head
        new Rgba(0.955, 0.745, 0.505),   // head light
        new Rgba(0.788, 0.518, 0.278),   // leg fill
        new Rgba(0.855, 0.596, 0.345),   // leg light
        new Rgba(0.690, 0.435, 0.220),   // far-side leg
        new Rgba(0.255, 0.150, 0.070),   // far outline
        new Rgba(0.239, 0.129, 0.055),   // eye dark
        new Rgba(0.298, 0.180, 0.086));  // accent
}

/// <summary>
/// The vector drawing of the spider (spec Stages 3–4). Everything is drawn in body-local units and
/// transformed once, so hats, markings and weather ride through corners, rolls and hanging upside
/// down for free (spec 3.6).
/// </summary>
public static class SpiderRenderer
{
    public const double Ground = -22;
    public const double DrawRadius = 72;
    public const double BodyLength = 46;

    public static readonly V2 LeanPivot = new(1, -8);
    public static readonly V2 AbdomenC = new(-14, 3);
    public const double AbdomenRx = 14, AbdomenRy = 13;
    public static readonly V2 HeadC = new(9.5, 0.5);
    public const double HeadR = 13;
    public static readonly V2 Neck = new(-2, 0);
    public static readonly V2 BallCentre = new(-6, -5);
    public static readonly V2 FrontAbdomenC = new(0, 7);
    public const double FrontAbdomenRx = 13.5, FrontAbdomenRy = 12.5;
    public static readonly V2 FrontHeadC = new(0, -1);
    public const double FrontHeadR = 13;

    /// <summary>Profile eyes: (centre, radius, big). The face is turned 3/4 so all four front eyes show.</summary>
    public static readonly (V2 c, double r, bool big)[] ProfileEyes =
    {
        (new V2(16.2, 1.2), 4.7, true),    // near anterior-median
        (new V2(10.0, 3.6), 3.8, true),    // far anterior-median
        (new V2(19.6, 6.4), 2.5, false),   // near lateral
        (new V2(5.6, 7.0), 2.1, false),    // far lateral
    };

    public static readonly (V2 c, double r, bool big)[] FrontEyes =
    {
        (new V2(4.8, 0.2), 4.5, true),
        (new V2(-4.8, 0.2), 4.5, true),
        (new V2(11.6, 1.4), 2.9, false),
        (new V2(-11.6, 1.4), 2.9, false),
    };

    // =========================================================================== palette

    /// <summary>Derive the palette for this look at this moment (living coats recompute every frame).</summary>
    public static Palette PaletteFor(SpiderLook look, SpiderPose pose)
    {
        var p = Palette.Reference;
        bool far = false;
        Rgba body = look.CustomBody, leg = look.CustomLeg;

        switch (look.Coat)
        {
            case CoatStyle.None:
                body = p.Body; leg = p.LegFill; break;

            case CoatStyle.Camouflage:
            {
                // Drifts toward the colour behind it (spec 3.6) — a 1–2 s fade, never a flash.
                var target = pose.Surroundings;
                double drift = 1 - Math.Exp(-0.05 * 1.2);
                body = body.Mix(target, drift) ;
                body = target.Lighter(0.06);
                leg = body.Darker(0.10) ;
                break;
            }
            case CoatStyle.Rainbow:
            {
                double hue = (pose.Time * 40 + pose.Pos.X * 0.35) % 360;
                body = Hsv(hue, 0.62, 0.98);
                leg = Hsv((hue + 35) % 360, 0.66, 0.92);
                break;
            }
            case CoatStyle.Lava:
            {
                double pulse = 0.5 + 0.5 * Math.Sin(pose.Time * 1.6);
                body = new Rgba(M.Lerp(0.20, 0.95, pulse), M.Lerp(0.05, 0.35, pulse), 0.04);
                leg = new Rgba(M.Lerp(0.22, 0.7, pulse), 0.09, 0.05);
                break;
            }
            case CoatStyle.Galaxy:
                body = new Rgba(0.16, 0.14, 0.32);
                leg = new Rgba(0.22, 0.19, 0.42);
                break;
            case CoatStyle.Ocean:
            {
                double w = 0.5 + 0.5 * Math.Sin(pose.Time * 0.9);
                body = new Rgba(0.10, M.Lerp(0.42, 0.62, w), M.Lerp(0.62, 0.78, w));
                leg = new Rgba(0.09, 0.38, 0.60);
                break;
            }
            case CoatStyle.Aurora:
            {
                double w = 0.5 + 0.5 * Math.Sin(pose.Time * 0.6);
                body = new Rgba(M.Lerp(0.18, 0.42, w), M.Lerp(0.80, 0.95, w), M.Lerp(0.60, 0.82, w));
                leg = new Rgba(0.28, 0.72, 0.62);
                break;
            }
            case CoatStyle.Disco:
            {
                double h = (pose.Time * 180) % 360;
                body = Hsv(h, 0.55, 1.0);
                leg = Hsv((h + 120) % 360, 0.55, 0.95);
                break;
            }
            case CoatStyle.Fire:
                body = new Rgba(0.95, 0.45, 0.12);
                leg = new Rgba(0.85, 0.30, 0.08);
                break;
            case CoatStyle.Frost:
                body = new Rgba(0.78, 0.90, 1.0);
                leg = new Rgba(0.62, 0.80, 0.96);
                break;
            case CoatStyle.Toxic:
                body = new Rgba(0.55, 0.95, 0.25);
                leg = new Rgba(0.40, 0.80, 0.18);
                break;
            case CoatStyle.Pearl:
            {
                double s = 0.5 + 0.5 * Math.Sin(pose.Time * 0.8);
                body = new Rgba(M.Lerp(0.90, 0.98, s), M.Lerp(0.88, 0.95, s), M.Lerp(0.86, 0.99, s));
                leg = body.Darker(0.08);
                break;
            }
            case CoatStyle.CandyCane:
            {
                double band = Math.Sin(pose.Pos.X * 0.6 + pose.Pos.Y * 0.4) > 0 ? 1 : 0;
                body = band > 0 ? new Rgba(0.92, 0.15, 0.20) : new Rgba(0.98, 0.97, 0.95);
                leg = band > 0 ? new Rgba(0.85, 0.12, 0.18) : new Rgba(0.95, 0.94, 0.92);
                break;
            }
            case CoatStyle.Thunderstorm:
            {
                double flash = Math.Max(0, Math.Sin(pose.Time * 3.1)) > 0.97 ? 1 : 0;
                body = new Rgba(M.Lerp(0.30, 0.85, flash), M.Lerp(0.32, 0.88, flash), M.Lerp(0.42, 0.95, flash));
                leg = new Rgba(0.26, 0.28, 0.38);
                break;
            }
            case CoatStyle.Chrome:
            {
                double s = 0.5 + 0.5 * Math.Sin(pose.Pos.X * 0.5 + pose.Time);
                body = new Rgba(M.Lerp(0.62, 0.94, s), M.Lerp(0.66, 0.96, s), M.Lerp(0.70, 0.99, s));
                leg = body.Darker(0.12);
                break;
            }
            case CoatStyle.WebSlinger:
                body = new Rgba(0.85, 0.13, 0.16);
                leg = new Rgba(0.15, 0.22, 0.65);
                break;
            case CoatStyle.Custom:
                body = look.CustomBody;
                leg = look.CustomLeg;
                break;
            default:
                body = FlatCoat(look.Coat, body);
                leg = body.Darker(0.12);
                break;
        }

        // Gradient coats blend a second colour across the body.
        if (look.Gradient != CoatStyle.None && look.Coat == CoatStyle.None)
        {
            var g = FlatCoat(look.Gradient, body);
            body = body.Mix(g, 0.65);
            leg = body.Darker(0.10);
        }

        _ = far;
        Rgba outline = body.Darker(0.62);
        Rgba bodyLight = body.Lighter(0.22);
        Rgba head = body.Lighter(0.04);
        Rgba headLight = body.Lighter(0.26);
        Rgba legLight = leg.Lighter(0.20);
        Rgba farLeg = leg.Darker(0.18);
        Rgba farOutline = outline.Darker(0.10);
        Rgba eyeDark = outline.Darker(0.35);
        Rgba accent = look.CustomAccent ?? look.Accent;

        // weather tints (spec 3.8): wet darkens and glosses, chill blues
        if (pose.Wet > 0.01) { body = body.Darker(0.16 * pose.Wet); head = head.Darker(0.13 * pose.Wet); leg = leg.Darker(0.14 * pose.Wet); }
        if (pose.Chill > 0.01) { body = body.Mix(new Rgba(0.60, 0.74, 0.95), 0.22 * pose.Chill); }
        if (pose.Dust > 0.01) { body = body.Mix(new Rgba(0.80, 0.72, 0.55), 0.16 * pose.Dust); }

        return new Palette(outline, body, bodyLight, head, headLight, leg, legLight, farLeg, farOutline, eyeDark, accent);
    }

    static Rgba FlatCoat(CoatStyle c, Rgba fallback) => c switch
    {
        CoatStyle.Espresso => new Rgba(0.35, 0.24, 0.16),
        CoatStyle.Amber => new Rgba(0.86, 0.58, 0.18),
        CoatStyle.Rust => new Rgba(0.66, 0.32, 0.16),
        CoatStyle.Copper => new Rgba(0.76, 0.45, 0.25),
        CoatStyle.Cream => new Rgba(0.96, 0.90, 0.78),
        CoatStyle.Sand => new Rgba(0.87, 0.79, 0.62),
        CoatStyle.Olive => new Rgba(0.50, 0.50, 0.26),
        CoatStyle.Moss => new Rgba(0.38, 0.48, 0.28),
        CoatStyle.Forest => new Rgba(0.22, 0.38, 0.26),
        CoatStyle.Teal => new Rgba(0.20, 0.55, 0.55),
        CoatStyle.Sky => new Rgba(0.52, 0.72, 0.90),
        CoatStyle.Navy => new Rgba(0.18, 0.24, 0.45),
        CoatStyle.Violet => new Rgba(0.52, 0.38, 0.72),
        CoatStyle.Plum => new Rgba(0.42, 0.22, 0.40),
        CoatStyle.Rose => new Rgba(0.85, 0.48, 0.55),
        CoatStyle.Blush => new Rgba(0.93, 0.68, 0.68),
        CoatStyle.Cherry => new Rgba(0.80, 0.18, 0.24),
        CoatStyle.Coral => new Rgba(0.94, 0.52, 0.40),
        CoatStyle.Butter => new Rgba(0.97, 0.90, 0.60),
        CoatStyle.Lemon => new Rgba(0.96, 0.94, 0.45),
        CoatStyle.Lilac => new Rgba(0.76, 0.68, 0.88),
        CoatStyle.Slate => new Rgba(0.42, 0.46, 0.52),
        CoatStyle.Graphite => new Rgba(0.28, 0.29, 0.32),
        CoatStyle.Ink => new Rgba(0.14, 0.14, 0.18),
        CoatStyle.Snow => new Rgba(0.97, 0.97, 0.98),
        CoatStyle.Ash => new Rgba(0.62, 0.62, 0.64),
        CoatStyle.Taupe => new Rgba(0.58, 0.52, 0.46),
        CoatStyle.Desert => new Rgba(0.84, 0.70, 0.48),
        CoatStyle.Clay => new Rgba(0.70, 0.48, 0.38),
        CoatStyle.Pistachio => new Rgba(0.70, 0.82, 0.52),
        CoatStyle.Sunset => new Rgba(0.96, 0.45, 0.30),
        CoatStyle.Dawn => new Rgba(0.96, 0.72, 0.62),
        CoatStyle.Meadow => new Rgba(0.52, 0.78, 0.42),
        CoatStyle.Reef => new Rgba(0.20, 0.70, 0.72),
        CoatStyle.Ember => new Rgba(0.72, 0.28, 0.16),
        CoatStyle.Twilight => new Rgba(0.32, 0.30, 0.58),
        CoatStyle.Mint => new Rgba(0.60, 0.90, 0.78),
        CoatStyle.Peach => new Rgba(0.98, 0.72, 0.55),
        CoatStyle.Storm => new Rgba(0.42, 0.46, 0.56),
        CoatStyle.Candy => new Rgba(0.96, 0.48, 0.72),
        CoatStyle.Forest2 => new Rgba(0.28, 0.52, 0.32),
        CoatStyle.Ice => new Rgba(0.76, 0.90, 0.96),
        CoatStyle.Wine => new Rgba(0.52, 0.16, 0.28),
        CoatStyle.Lagoon => new Rgba(0.20, 0.58, 0.66),
        CoatStyle.Gold => new Rgba(0.90, 0.75, 0.32),
        CoatStyle.Nebula => new Rgba(0.46, 0.30, 0.66),
        _ => fallback
    };

    static Rgba Hsv(double h, double s, double v)
    {
        h = ((h % 360) + 360) % 360;
        double c = v * s;
        double x = c * (1 - Math.Abs((h / 60) % 2 - 1));
        double m = v - c;
        (double r, double g, double b) = h switch
        {
            < 60 => (c, x, 0.0),
            < 120 => (x, c, 0.0),
            < 180 => (0.0, c, x),
            < 240 => (0.0, x, c),
            < 300 => (x, 0.0, c),
            _ => (c, 0.0, x)
        };
        return new Rgba(r + m, g + m, b + m);
    }

    // =========================================================================== drawing

    /// <summary>Draw a whole pose: frame, shadow, legs, body, face, hat, accessory, name tag.</summary>
    public static void Draw(IDraw g, SpiderPose pose, SpiderLook look, bool drawNameTag = true)
    {
        var pal = PaletteFor(look, pose);
        double prof = SpiderRig.ProfileAmount(pose.Facing);
        double mirror = pose.Facing < 0 ? -1 : 1;

        // ---- contact shadow, in the surface frame (scaled by grounded — spec 3.4)
        if (pose.Grounded > 0.01)
        {
            g.Save();
            g.Translate(pose.Pos.X, pose.Pos.Y);
            g.Rotate(pose.Heading);
            g.Scale(pose.Scale, pose.Scale);
            double w = 26 * pose.Grounded * pose.Stretch;
            g.SetFill(new Rgba(0, 0, 0, 0.16 * pose.Grounded));
            g.FillEllipse(new V2(-4, Ground + 0.5), w, 4.2 * pose.Grounded);
            g.Restore();
        }

        // ---- body frame
        g.Save();
        g.Translate(pose.Pos.X, pose.Pos.Y);
        g.Rotate(pose.Heading);
        g.Translate(0, pose.Lift);
        g.Scale(mirror, 1);
        g.Scale(pose.Scale, pose.Scale);
        g.SetLineCap(LineCap.Round);
        g.SetLineJoin(LineJoin.Round);

        // squash & stretch, pivoting on the feet (spec 3.5)
        double st = M.Clamp(pose.Stretch, 0.6, 1.5);
        double fa = M.Clamp(pose.Fatten, 0.6, 1.5);
        g.Translate(0, Ground);
        g.Scale(st, fa);
        g.Translate(0, -Ground);

        DrawBodyLocal(g, pose, look, pal, prof);

        g.Restore();

        // ---- bubbles and name tag are screen-space, outside the body frame
        DrawEmote(g, pose, pal);
        if (drawNameTag && !string.IsNullOrEmpty(pose.Name) && pose.NameTag > 0.01)
            DrawNameTag(g, pose, pal);
    }

    /// <summary>Body-local drawing: the caller has already set the world frame.</summary>
    public static void DrawBodyLocal(IDraw g, SpiderPose pose, SpiderLook look, Palette pal, double prof)
    {
        var (reach, kneeRise, width) = look.LegRig;

        // ---- far-side legs (4…7), behind the body and darker
        for (int i = 4; i < 8; i++) DrawLeg(g, pose, look, pal, i, pal.FarLeg, pal.FarOutline, width, prof);

        // ---- the body leans about the rotation point; planted legs are outside this transform
        g.Save();
        g.Translate(LeanPivot.X + pose.BodyShift.X, LeanPivot.Y + pose.BodyShift.Y);
        g.Rotate(pose.BodyPitch);
        g.Translate(-LeanPivot.X, -LeanPivot.Y);

        if (pose.Ball > 0.5)
        {
            DrawBall(g, pose, look, pal);
            g.Restore();
            return;   // every leg is tucked inside the ball (spec 6.6)
        }

        DrawAbdomen(g, pose, look, pal, prof);
        DrawHead(g, pose, look, pal, prof);
        DrawFace(g, pose, look, pal, prof);
        DrawHat(g, pose, look, pal);
        DrawAccessory(g, pose, look, pal);

        g.Restore();

        // ---- near-side legs (0…3), in front
        for (int i = 0; i < 4; i++) DrawLeg(g, pose, look, pal, i, pal.LegFill, pal.Outline, width, prof);
    }

    static (V2 c, double rx, double ry) AbdomenShape(SpiderLook look, double prof, SpiderPose pose)
    {
        var m = look.ShapeMultipliers;
        V2 c = V2.Lerp(FrontAbdomenC, AbdomenC, prof);
        double rx = M.Lerp(FrontAbdomenRx, AbdomenRx, prof) * m.X;
        double ry = M.Lerp(FrontAbdomenRy, AbdomenRy, prof) * m.Y;
        // breathing / idle: never quite still
        double breathe = 1 + 0.012 * Math.Sin(pose.Time * 1.7);
        return (c, rx * breathe, ry * breathe);
    }

    static (V2 c, double r) HeadShape(SpiderLook look, double prof)
    {
        var m = look.ShapeMultipliers;
        V2 c = V2.Lerp(FrontHeadC, HeadC, prof);
        return (c, HeadR * m.Z);
    }

    // ------------------------------------------------------------------ body

    /// <summary>
    /// The rolled ball (spec 6.6): an egg 20 units along � 17 across, rolling without slipping.
    /// ballHeight(spin) = sqrt((20 sin s)^2 + (17 cos s)^2) keeps the silhouette right as it turns.
    /// </summary>
    static void DrawBall(IDraw g, SpiderPose pose, SpiderLook look, Palette pal)
    {
        const double along = 20, across = 17;
        double spin = pose.Spin;
        double height = Math.Sqrt(Math.Pow(along * Math.Sin(spin), 2) + Math.Pow(across * Math.Cos(spin), 2));

        // Rest the egg ON the ledge: the bottom of the ball touches the ground line.
        double cy = Ground + height * 0.5;
        g.Save();
        g.Translate(BallCentre.X, cy);
        g.Rotate(spin * 0.45);
        g.NewPath();
        g.AddEllipse(V2.Zero, along * 0.5, height * 0.5);
        g.SetFill(pal.Body);
        g.Fill();
        g.SetStroke(pal.Outline);
        g.SetLineWidth(2.2);
        g.Stroke();

        // a couple of tucked leg tips peeking out, and a sheen
        g.SetStroke(pal.LegFill);
        g.SetLineWidth(2.2);
        g.SetLineCap(LineCap.Round);
        for (int i = 0; i < 3; i++)
        {
            g.NewPath();
            g.MoveTo(new V2(-4 + i * 4, -height * 0.36));
            g.LineTo(new V2(-6 + i * 4.5, -height * 0.5 - 2));
            g.Stroke();
        }
        g.SetFill(new Rgba(1, 1, 1, 0.18));
        g.FillEllipse(new V2(-2, height * 0.22), along * 0.22, height * 0.16);
        g.Restore();
    }

    static void DrawAbdomen(IDraw g, SpiderPose pose, SpiderLook look, Palette pal, double prof)
    {
        var (c, rx, ry) = AbdomenShape(look, prof, pose);
        double tilt = pose.AbdomenTilt + pose.AbdomenSway * 0.10 + (pose.Ball * -0.25);

        g.Save();
        g.Translate(c.X, c.Y);
        g.Rotate(tilt);
        g.Translate(-c.X, -c.Y);

        // silhouette: a slightly egg-shaped blob (jumping spiders have a peanut abdomen profile)
        g.NewPath();
        g.MoveTo(new V2(c.X - rx, c.Y + ry * 0.15));
        g.CurveTo(new V2(c.X - rx * 1.02, c.Y + ry * 0.95), new V2(c.X - rx * 0.35, c.Y + ry), new V2(c.X + rx * 0.35, c.Y + ry * 0.96));
        g.CurveTo(new V2(c.X + rx * 1.0, c.Y + ry * 0.9), new V2(c.X + rx, c.Y + ry * 0.2), new V2(c.X + rx, c.Y - ry * 0.1));
        g.CurveTo(new V2(c.X + rx, c.Y - ry * 0.75), new V2(c.X + rx * 0.5, c.Y - ry), new V2(c.X - rx * 0.1, c.Y - ry));
        g.CurveTo(new V2(c.X - rx * 0.8, c.Y - ry), new V2(c.X - rx, c.Y - ry * 0.55), new V2(c.X - rx, c.Y + ry * 0.15));
        g.ClosePath();
        g.SetFill(pal.Body);
        g.Fill();
        g.SetStroke(pal.Outline);
        g.SetLineWidth(2.1);
        g.Stroke();

        // soft top light
        g.SetFill(new Rgba(1, 1, 1, 0.16));
        g.FillEllipse(new V2(c.X + rx * 0.05, c.Y + ry * 0.42), rx * 0.62, ry * 0.42);

        DrawMarkings(g, pose, look, pal, (c, rx, ry));

        g.Restore();
    }

    static void DrawMarkings(IDraw g, SpiderPose pose, SpiderLook look, Palette pal, (V2 c, double rx, double ry) abd)
    {
        if (look.Pattern == PatternStyle.None) return;
        Rgba ink = look.CamoMarkings ? pose.Surroundings.Lighter(0.35) : pal.Accent;
        g.Save();
        // clip to the abdomen silhouette so markings never spill
        g.AddEllipse(abd.c, abd.rx * 0.96, abd.ry * 0.96);
        g.ClipPath();

        switch (look.Pattern)
        {
            case PatternStyle.Stripe:
                for (int i = -1; i <= 1; i++)
                {
                    g.SetFill(ink.WithAlpha(0.55));
                    g.FillEllipse(new V2(abd.c.X + i * abd.rx * 0.45, abd.c.Y), abd.rx * 0.13, abd.ry * 0.95);
                }
                break;
            case PatternStyle.Spots:
                g.SetFill(ink.WithAlpha(0.62));
                for (int i = 0; i < 5; i++)
                {
                    double a = i * 2.399;
                    g.FillEllipse(new V2(abd.c.X + Math.Cos(a) * abd.rx * 0.45, abd.c.Y + Math.Sin(a) * abd.ry * 0.45),
                        abd.rx * 0.16, abd.ry * 0.16);
                }
                break;
            case PatternStyle.Chevron:
                g.SetStroke(ink.WithAlpha(0.7));
                g.SetLineWidth(2.4);
                for (int i = -1; i <= 1; i++)
                {
                    g.NewPath();
                    g.MoveTo(new V2(abd.c.X + i * 7 - 6, abd.c.Y + abd.ry * 0.55));
                    g.LineTo(new V2(abd.c.X + i * 7, abd.c.Y));
                    g.LineTo(new V2(abd.c.X + i * 7 + 6, abd.c.Y + abd.ry * 0.55));
                    g.Stroke();
                }
                break;
            case PatternStyle.Heart:
                DrawHeart(g, new V2(abd.c.X, abd.c.Y + abd.ry * 0.05), abd.rx * 0.45, ink.WithAlpha(0.7));
                break;
            case PatternStyle.Star:
                DrawStar(g, new V2(abd.c.X, abd.c.Y), abd.rx * 0.55, ink.WithAlpha(0.7));
                break;
            case PatternStyle.Hourglass:
                g.SetFill(ink.WithAlpha(0.6));
                g.NewPath();
                g.MoveTo(new V2(abd.c.X - 5, abd.c.Y + 8));
                g.LineTo(new V2(abd.c.X + 5, abd.c.Y + 8));
                g.LineTo(new V2(abd.c.X - 4, abd.c.Y));
                g.LineTo(new V2(abd.c.X + 4, abd.c.Y));
                g.LineTo(new V2(abd.c.X + 5, abd.c.Y - 8));
                g.LineTo(new V2(abd.c.X - 5, abd.c.Y - 8));
                g.ClosePath();
                g.Fill();
                break;
            case PatternStyle.Tiger:
                g.SetFill(ink.WithAlpha(0.5));
                for (int i = -2; i <= 2; i++)
                    g.FillEllipse(new V2(abd.c.X + i * abd.rx * 0.28, abd.c.Y + Math.Sin(i) * 4), abd.rx * 0.07, abd.ry * 0.8);
                break;
            case PatternStyle.Checker:
                g.SetFill(ink.WithAlpha(0.45));
                for (int x = -2; x <= 2; x++)
                    for (int y = -1; y <= 1; y++)
                        if (((x + y) & 1) == 0)
                            g.FillEllipse(new V2(abd.c.X + x * abd.rx * 0.32, abd.c.Y + y * abd.ry * 0.4), abd.rx * 0.16, abd.ry * 0.2);
                break;
            case PatternStyle.Lightning:
                g.SetFill(ink.WithAlpha(0.75));
                g.NewPath();
                g.MoveTo(new V2(abd.c.X + 2, abd.c.Y + abd.ry * 0.7));
                g.LineTo(new V2(abd.c.X - 5, abd.c.Y));
                g.LineTo(new V2(abd.c.X + 1, abd.c.Y + 1));
                g.LineTo(new V2(abd.c.X - 3, abd.c.Y - abd.ry * 0.7));
                g.LineTo(new V2(abd.c.X + 6, abd.c.Y + 2));
                g.LineTo(new V2(abd.c.X, abd.c.Y + 1));
                g.ClosePath();
                g.Fill();
                break;
            case PatternStyle.Eyespots:
                for (int i = -1; i <= 1; i += 2)
                {
                    g.SetFill(ink.WithAlpha(0.75));
                    g.FillEllipse(new V2(abd.c.X + i * 5, abd.c.Y + 2), 4.2, 4.2);
                    g.SetFill(Rgba.White.WithAlpha(0.8));
                    g.FillEllipse(new V2(abd.c.X + i * 5 + 1.2, abd.c.Y + 3.2), 1.4, 1.4);
                }
                break;
            default:
                g.SetFill(ink.WithAlpha(0.4));
                g.FillEllipse(new V2(abd.c.X, abd.c.Y), abd.rx * 0.4, abd.ry * 0.4);
                break;
        }
        g.Restore();
    }

    static void DrawHead(IDraw g, SpiderPose pose, SpiderLook look, Palette pal, double prof)
    {
        var (c, r) = HeadShape(look, prof);

        // ball fold: translate to the neck, rotate, scale down, offset (spec 3.4)
        double ball = M.Clamp01(pose.Ball);
        g.Save();
        if (ball > 0.001)
        {
            g.Translate(Neck.X, Neck.Y);
            g.Rotate(-1.2 * ball);
            g.Scale(1 - 0.15 * ball, 1 - 0.15 * ball);
            g.Translate(-Neck.X - 3 * ball, -Neck.Y + 3 * ball);
        }
        else
        {
            g.Translate(c.X, c.Y + pose.HeadCock * 1.5);
            g.Rotate(pose.HeadTilt);
            g.Translate(-c.X, -c.Y);
        }

        g.SetFill(pal.Head);
        g.FillEllipse(c, r * 0.98, r * 0.94);
        g.SetStroke(pal.Outline);
        g.SetLineWidth(2.1);
        g.StrokeEllipse(c, r * 0.98, r * 0.94);

        // crown light
        g.SetFill(new Rgba(1, 1, 1, 0.18));
        g.FillEllipse(new V2(c.X + r * 0.05, c.Y + r * 0.45), r * 0.55, r * 0.32);

        g.Restore();
    }

    static void DrawFace(IDraw g, SpiderPose pose, SpiderLook look, Palette pal, double prof)
    {
        var (hc, hr) = HeadShape(look, prof);
        double eyeScale = look.EyeScale;
        double blink = M.Clamp01(pose.Blink);
        if (pose.Sleep > 0.5) blink = Math.Max(blink, pose.Sleep * 0.85);

        g.Save();
        g.Translate(hc.X, hc.Y + pose.HeadCock * 1.5);
        g.Rotate(pose.HeadTilt);
        g.Translate(-hc.X, -hc.Y);

        // ---- eyes: profile and front layouts blended by the yaw
        for (int i = 0; i < 4; i++)
        {
            var f = FrontEyes[i];
            var p = ProfileEyes[i];
            V2 c = V2.Lerp(f.c, p.c, prof);
            double rr = M.Lerp(f.r, p.r, prof) * eyeScale;
            bool big = prof > 0.5 ? p.big : f.big;

            // the look follows the pointer a little (gaze), scaled by how much of the face shows
            V2 gaze = new(pose.Look.X * 0.10, pose.Look.Y * 0.08);
            c += gaze;

            DrawEye(g, c, rr, big, blink, pose, look, pal, i);
        }

        // ---- brows
        DrawBrows(g, pose, look, pal, prof, eyeScale);

        // ---- fangs / mouth
        DrawMouth(g, pose, look, pal, prof);

        // ---- palps (two little feelers at the front)
        double palpLift = pose.PalpNear * 2.2;
        double palpLift2 = pose.PalpFar * 2.2;
        g.SetFill(pal.LegFill);
        g.SetStroke(pal.Outline);
        g.SetLineWidth(1.6);
        g.FillEllipse(new V2(hc.X + 8 * prof + 4, hc.Y - 8 + palpLift), 3.1, 2.4);
        g.SetFill(pal.FarLeg);
        g.FillEllipse(new V2(hc.X + 4 * prof + 2, hc.Y - 9 + palpLift2), 2.6, 2.0);

        // ---- bristles / fuzz around the head
        if (look.Fuzz != FuzzLevel.Sleek) DrawFuzz(g, pose, look, pal, prof, (hc, hr));

        g.Restore();

        // ---- blush when happy or petted
        if (pose.Happy > 0.2)
        {
            g.SetFill(new Rgba(0.96, 0.45, 0.45, 0.20 * pose.Happy));
            g.FillEllipse(new V2(hc.X + 4 * prof + 5, hc.Y - 3), 4.4, 2.6);
        }
    }

    static void DrawEye(IDraw g, V2 c, double r, bool big, double blink, SpiderPose pose, SpiderLook look, Palette pal, int idx)
    {
        bool wink = look.Eyes == EyeStyle.Wink && idx == 0 && pose.Wink > 0.5;

        switch (look.Eyes)
        {
            case EyeStyle.HeartEyes:
            {
                DrawHeart(g, c, r * 1.15, new Rgba(0.92, 0.25, 0.35));
                return;
            }
            case EyeStyle.Glowing:
            {
                g.SetFill(pal.EyeDark);
                g.FillEllipse(c, r * 1.05, r * 1.05);
                g.SetFill(new Rgba(0.55, 0.95, 0.95, 0.85));
                g.FillEllipse(c, r * 0.72, r * 0.72);
                return;
            }
            case EyeStyle.Button:
            {
                g.SetFill(pal.EyeDark);
                g.FillEllipse(c, r, r);
                g.SetStroke(new Rgba(1, 1, 1, 0.5));
                g.SetLineWidth(0.9);
                g.StrokeEllipse(c, r * 0.6, r * 0.6);
                return;
            }
        }

        double squash = wink ? 0.12 : M.Lerp(1, 0.08, blink);
        double ry = r * squash;
        double rx = r * (look.Eyes == EyeStyle.Oval ? 1.25 : 1);

        if (look.Eyes == EyeStyle.Sleepy && blink < 0.2)
            ry = Math.Min(ry, r * 0.55);

        // eye socket rim
        g.SetFill(pal.EyeDark);
        g.FillEllipse(c, rx, Math.Max(ry, 0.9));

        if (squash > 0.3)
        {
            // pupil shading and a glint (glints mirror correctly across the front view — spec 5.5)
            g.SetFill(new Rgba(0.10, 0.06, 0.03, 0.55));
            g.FillEllipse(new V2(c.X + rx * 0.12, c.Y - ry * 0.2), rx * 0.55, ry * 0.5);
            g.SetFill(Rgba.White.WithAlpha(0.92));
            double glint = big ? 0.34 : 0.28;
            g.FillEllipse(new V2(c.X - rx * 0.30, c.Y + ry * 0.34), rx * glint, ry * glint);
            if (look.Eyes == EyeStyle.Sparkly)
            {
                g.SetFill(Rgba.White.WithAlpha(0.8));
                g.FillEllipse(new V2(c.X + rx * 0.32, c.Y - ry * 0.28), rx * 0.16, ry * 0.16);
            }
            if (look.Eyes == EyeStyle.Dizzy)
            {
                g.SetStroke(Rgba.White.WithAlpha(0.85));
                g.SetLineWidth(0.8);
                g.NewPath();
                double turns = 3;
                for (int s = 0; s <= 18; s++)
                {
                    double a = s / 18.0 * turns * M.Tau;
                    double rad = r * (s / 18.0) * 0.9;
                    V2 pt = new(c.X + Math.Cos(a) * rad, c.Y + Math.Sin(a) * rad);
                    if (s == 0) g.MoveTo(pt); else g.LineTo(pt);
                }
                g.Stroke();
            }
        }

        // cross-eyed aims the big pair inward
        if (look.Eyes == EyeStyle.CrossEyed && idx < 2)
        {
            g.SetFill(pal.EyeDark);
            g.FillEllipse(new V2(c.X + (idx == 0 ? -rx * 0.25 : rx * 0.25), c.Y), rx * 0.5, ry * 0.8);
        }
    }

    static void DrawBrows(IDraw g, SpiderPose pose, SpiderLook look, Palette pal, double prof, double eyeScale)
    {
        if (look.Brows == BrowStyle.None) return;
        var (hc, hr) = HeadShape(look, prof);
        double y = hc.Y + 9.5 * prof + 4;
        g.SetStroke(pal.Outline.Scale(0.85));
        g.SetLineWidth(1.5);
        g.SetLineCap(LineCap.Round);

        void Brow(double x0, double x1, double lift0, double lift1)
        {
            g.NewPath();
            g.MoveTo(new V2(x0, y + lift0));
            g.QuadTo(new V2((x0 + x1) / 2, y + Math.Max(lift0, lift1) + 2.2), new V2(x1, y + lift1));
            g.Stroke();
        }

        switch (look.Brows)
        {
            case BrowStyle.Soft: Brow(2, 9, 0, 0); Brow(11, 17, 0, 0); break;
            case BrowStyle.Arched: Brow(2, 9, 0.6, 0.6); Brow(11, 17, 0.6, 0.6); break;
            case BrowStyle.Stern: Brow(2, 9, 2.0, -1.2); Brow(11, 17, -1.2, 2.0); break;
            case BrowStyle.Worried: Brow(2, 9, -1.4, 1.6); Brow(11, 17, 1.6, -1.4); break;
            case BrowStyle.Unibrow: Brow(2, 17, 0, 0); break;
            case BrowStyle.Thick:
                g.SetLineWidth(3.0); Brow(2, 9, 0, 0); Brow(11, 17, 0, 0); break;
            case BrowStyle.Quizzical: Brow(2, 9, 0, 0); Brow(11, 17, 3.4, 0.4); break;
            case BrowStyle.Bushy:
                g.SetLineWidth(2.6);
                Brow(2, 9, 0.4, 0.4); Brow(11, 17, 0.4, 0.4); break;
            case BrowStyle.Flat:
                g.SetLineWidth(1.8); Brow(2, 9, 0, 0); Brow(11, 17, 0, 0); break;
        }
    }

    static void DrawMouth(IDraw g, SpiderPose pose, SpiderLook look, Palette pal, double prof)
    {
        var (hc, hr) = HeadShape(look, prof);
        V2 mouth = new(hc.X + 3 * prof, hc.Y - 8.5 + pose.Chew * 1.4);
        g.SetFill(pal.LegFill);
        g.SetStroke(pal.Outline);
        g.SetLineWidth(1.4);

        switch (look.Fangs)
        {
            case FangStyle.Smile:
                g.SetStroke(pal.Outline);
                g.SetLineWidth(1.6);
                g.NewPath();
                g.MoveTo(new V2(mouth.X - 3.5, mouth.Y + 1));
                g.QuadTo(new V2(mouth.X, mouth.Y - 3.2 - pose.Chew * 2), new V2(mouth.X + 3.5, mouth.Y + 1));
                g.Stroke();
                break;
            case FangStyle.Blep:
                g.SetStroke(pal.Outline);
                g.SetLineWidth(1.6);
                g.NewPath();
                g.MoveTo(new V2(mouth.X - 3.5, mouth.Y + 1));
                g.QuadTo(new V2(mouth.X, mouth.Y - 2.5), new V2(mouth.X + 3.5, mouth.Y + 1));
                g.Stroke();
                g.SetFill(new Rgba(0.93, 0.45, 0.50));
                g.FillEllipse(new V2(mouth.X + 1, mouth.Y - 4.2), 2.1, 2.6);
                break;
            case FangStyle.Grin:
                g.SetStroke(pal.Outline);
                g.SetLineWidth(1.8);
                g.NewPath();
                g.MoveTo(new V2(mouth.X - 5, mouth.Y + 1.5));
                g.QuadTo(new V2(mouth.X, mouth.Y - 4.5), new V2(mouth.X + 5, mouth.Y + 1.5));
                g.Stroke();
                g.SetFill(Rgba.White.WithAlpha(0.9));
                g.NewPath();
                g.MoveTo(new V2(mouth.X - 4.2, mouth.Y + 1.2));
                g.QuadTo(new V2(mouth.X, mouth.Y - 3.4), new V2(mouth.X + 4.2, mouth.Y + 1.2));
                g.LineTo(new V2(mouth.X - 4.2, mouth.Y + 1.2));
                g.Fill();
                break;
            case FangStyle.BuckTeeth:
                g.SetFill(Rgba.White);
                g.SetStroke(pal.Outline);
                g.SetLineWidth(1.0);
                g.NewPath();
                g.MoveTo(new V2(mouth.X - 2.4, mouth.Y));
                g.LineTo(new V2(mouth.X - 0.2, mouth.Y));
                g.LineTo(new V2(mouth.X - 0.2, mouth.Y - 4.4));
                g.LineTo(new V2(mouth.X - 2.4, mouth.Y - 4.4));
                g.ClosePath();
                g.FillAndStroke();
                g.NewPath();
                g.MoveTo(new V2(mouth.X + 0.2, mouth.Y));
                g.LineTo(new V2(mouth.X + 2.4, mouth.Y));
                g.LineTo(new V2(mouth.X + 2.4, mouth.Y - 4.4));
                g.LineTo(new V2(mouth.X + 0.2, mouth.Y - 4.4));
                g.ClosePath();
                g.FillAndStroke();
                break;
            case FangStyle.Emerald:
                g.SetFill(new Rgba(0.22, 0.72, 0.45));
                g.FillEllipse(new V2(mouth.X - 1.8, mouth.Y - 1.2), 2.4, 3.0);
                g.FillEllipse(new V2(mouth.X + 1.8, mouth.Y - 1.2), 2.4, 3.0);
                break;
            case FangStyle.Tusks:
                g.SetFill(Rgba.White);
                g.NewPath();
                g.MoveTo(new V2(mouth.X - 2.6, mouth.Y));
                g.LineTo(new V2(mouth.X - 1.6, mouth.Y - 5.2));
                g.LineTo(new V2(mouth.X - 0.6, mouth.Y));
                g.Fill();
                g.NewPath();
                g.MoveTo(new V2(mouth.X + 2.6, mouth.Y));
                g.LineTo(new V2(mouth.X + 1.6, mouth.Y - 5.2));
                g.LineTo(new V2(mouth.X + 0.6, mouth.Y));
                g.Fill();
                break;
            case FangStyle.Pout:
                g.SetStroke(pal.Outline);
                g.SetLineWidth(1.6);
                g.NewPath();
                g.MoveTo(new V2(mouth.X - 2.6, mouth.Y - 1.2));
                g.QuadTo(new V2(mouth.X, mouth.Y + 1.6), new V2(mouth.X + 2.6, mouth.Y - 1.2));
                g.Stroke();
                break;
            case FangStyle.FangsSmall:
            case FangStyle.FangsBig:
            case FangStyle.Chelicerae:
            default:
            {
                double len = look.Fangs == FangStyle.FangsBig ? 4.6 : (look.Fangs == FangStyle.FangsSmall ? 2.6 : 3.6);
                double spread = look.Fangs == FangStyle.Chelicerae ? 3.4 : 2.2;
                g.SetFill(Rgba.White);
                g.NewPath();
                g.MoveTo(new V2(mouth.X - spread, mouth.Y + 0.4));
                g.LineTo(new V2(mouth.X - spread + 1.2, mouth.Y - len));
                g.LineTo(new V2(mouth.X - spread + 2.4, mouth.Y + 0.4));
                g.ClosePath();
                g.Fill();
                g.NewPath();
                g.MoveTo(new V2(mouth.X + spread - 2.4, mouth.Y + 0.4));
                g.LineTo(new V2(mouth.X + spread - 1.2, mouth.Y - len));
                g.LineTo(new V2(mouth.X + spread, mouth.Y + 0.4));
                g.ClosePath();
                g.Fill();
                break;
            }
        }
    }

    static void DrawFuzz(IDraw g, SpiderPose pose, SpiderLook look, Palette pal, double prof, (V2 c, double r) head)
    {
        int count = look.Fuzz == FuzzLevel.VeryFuzzy ? 14 : 8;
        g.SetStroke(pal.Outline.WithAlpha(0.45));
        g.SetLineWidth(0.9);
        for (int i = 0; i < count; i++)
        {
            double a = -0.4 + i * (2.0 / count) + prof * 0.6;
            V2 from = head.c + new V2(Math.Cos(a), Math.Sin(a)) * (head.r * 0.92);
            V2 to = from + new V2(Math.Cos(a), Math.Sin(a)) * (look.Fuzz == FuzzLevel.VeryFuzzy ? 4.2 : 2.6);
            g.NewPath();
            g.MoveTo(from);
            g.LineTo(to);
            g.Stroke();
        }
    }

    // ------------------------------------------------------------------ legs

    static void DrawLeg(IDraw g, SpiderPose pose, SpiderLook look, Palette pal, int i, Rgba fill, Rgba outline, double width, double prof)
    {
        var leg = pose.Legs[i];
        var rest = SpiderRig.Rig(i, prof, look.Legs);
        V2 hip = leg.Hip;
        V2 foot = leg.RaisedFoot(Ground);
        V2 knee = leg.Knee;
        if (knee.LengthSquared < 1e-9) knee = SpiderRig.Knee(hip, foot, rest);

        // a lifted foot rises; the knee follows the art model
        double lift = M.Clamp01(leg.Lift);
        foot = new V2(foot.X, foot.Y + lift * 4);
        knee = SpiderRig.Knee(hip, foot, rest);
        knee = new V2(knee.X, knee.Y + lift * 1.5);

        double w = 3.4 * width;

        // shadow-side pass (outline) then the filled leg
        foreach (var (col, extra) in new[] { (outline, 1.9), (fill, 0.0) })
        {
            g.SetStroke(col);
            g.SetLineWidth(w + extra);
            g.SetLineCap(LineCap.Round);
            g.SetLineJoin(LineJoin.Round);
            g.NewPath();
            // thigh: hip → knee, slightly bowed
            V2 mid1 = V2.Lerp(hip, knee, 0.5) + new V2(0, 0.8);
            g.MoveTo(hip);
            g.QuadTo(mid1, knee);
            // shin: knee → foot
            V2 mid2 = V2.Lerp(knee, foot, 0.55);
            g.QuadTo(mid2, foot);
            g.Stroke();
        }

        // leg light down the top of the thigh
        g.SetStroke(fill.Lighter(0.22));
        g.SetLineWidth(w * 0.38);
        g.NewPath();
        g.MoveTo(V2.Lerp(hip, knee, 0.18));
        g.QuadTo(V2.Lerp(hip, knee, 0.55), knee);
        g.Stroke();

        // foot
        g.SetFill(fill);
        g.SetStroke(outline);
        g.SetLineWidth(1.1);
        g.FillEllipse(foot, w * 0.62, w * 0.52);

        // leg-style extras
        if (look.Legs == LegStyle.Socks)
        {
            g.SetFill(Rgba.White.WithAlpha(0.92));
            g.FillEllipse(V2.Lerp(knee, foot, 0.78), w * 0.6, 1.7);
        }
        else if (look.Legs == LegStyle.Banded || look.Legs == LegStyle.Striped)
        {
            g.SetStroke(outline.WithAlpha(0.55));
            g.SetLineWidth(1.4);
            for (int b = 1; b <= 2; b++)
            {
                V2 p = V2.Lerp(hip, knee, b / 3.0);
                g.NewPath();
                g.MoveTo(p + new V2(-1.6, -1.2));
                g.LineTo(p + new V2(1.6, 1.2));
                g.Stroke();
            }
        }
        else if (look.Legs == LegStyle.Boots)
        {
            g.SetFill(outline);
            g.FillEllipse(new V2(foot.X, foot.Y + 0.8), w * 0.75, w * 0.6);
        }
        else if (look.Legs == LegStyle.Robot)
        {
            g.SetFill(fill.Lighter(0.3));
            g.FillEllipse(knee, 2.0, 2.0);
        }
        else if (look.Legs == LegStyle.Knobbly)
        {
            g.SetFill(fill.Lighter(0.2));
            g.FillEllipse(V2.Lerp(hip, knee, 0.5), 2.1, 2.1);
            g.FillEllipse(V2.Lerp(knee, foot, 0.45), 1.7, 1.7);
        }
        else if (look.Legs == LegStyle.Fuzzy)
        {
            g.SetStroke(outline.WithAlpha(0.4));
            g.SetLineWidth(0.9);
            for (int f = 0; f < 3; f++)
            {
                V2 p = V2.Lerp(hip, knee, 0.3 + f * 0.22);
                g.NewPath();
                g.MoveTo(p);
                g.LineTo(p + new V2(-0.6, 3.0));
                g.Stroke();
            }
        }
    }

    // ------------------------------------------------------------------ hats and extras

    static (V2 c, double r) HeadShapeForHat(SpiderLook look, double prof, SpiderPose pose)
    {
        var (hc, hr) = HeadShape(look, prof);
        return (new V2(hc.X, hc.Y + pose.HeadCock * 1.5), hr);
    }

    static void DrawHat(IDraw g, SpiderPose pose, SpiderLook look, Palette pal)
    {
        if (look.Hat == HatStyle.None) return;
        double prof = SpiderRig.ProfileAmount(pose.Facing);
        var (hc, hr) = HeadShapeForHat(look, prof, pose);

        g.Save();
        g.Translate(hc.X, hc.Y + pose.HeadCock * 1.5);
        g.Rotate(pose.HeadTilt);
        g.Translate(-hc.X, -hc.Y);
        V2 top = new(hc.X, hc.Y + hr * 0.82);

        switch (look.Hat)
        {
            case HatStyle.TopHat:
            {
                g.SetFill(new Rgba(0.12, 0.12, 0.16));
                g.FillEllipse(new V2(top.X, top.Y + 0.5), 9.5, 2.6);
                g.FillEllipse(new V2(top.X, top.Y + 7), 5.6, 6.6);
                g.SetFill(new Rgba(0.70, 0.12, 0.18));
                g.FillEllipse(new V2(top.X, top.Y + 3.4), 5.7, 1.5);
                break;
            }
            case HatStyle.PartyHat:
            {
                g.SetFill(new Rgba(0.95, 0.55, 0.25));
                g.NewPath();
                g.MoveTo(new V2(top.X - 6, top.Y));
                g.LineTo(new V2(top.X + 0.6, top.Y + 13));
                g.LineTo(new V2(top.X + 6, top.Y));
                g.ClosePath();
                g.Fill();
                g.SetFill(Rgba.White.WithAlpha(0.8));
                g.FillEllipse(new V2(top.X + 0.6, top.Y + 13.2), 1.8, 1.8);
                break;
            }
            case HatStyle.Crown:
            {
                g.SetFill(new Rgba(0.98, 0.82, 0.22));
                g.NewPath();
                g.MoveTo(new V2(top.X - 6.5, top.Y));
                g.LineTo(new V2(top.X - 6.5, top.Y + 5));
                g.LineTo(new V2(top.X - 3.2, top.Y + 2));
                g.LineTo(new V2(top.X, top.Y + 6));
                g.LineTo(new V2(top.X + 3.2, top.Y + 2));
                g.LineTo(new V2(top.X + 6.5, top.Y + 5));
                g.LineTo(new V2(top.X + 6.5, top.Y));
                g.ClosePath();
                g.Fill();
                g.SetFill(new Rgba(0.85, 0.20, 0.30));
                g.FillEllipse(new V2(top.X, top.Y + 2.6), 1.3, 1.3);
                break;
            }
            case HatStyle.Beanie:
                g.SetFill(new Rgba(0.30, 0.55, 0.85));
                g.FillEllipse(new V2(top.X, top.Y + 3.2), 7.4, 6.2);
                g.SetFill(new Rgba(0.22, 0.42, 0.70));
                g.FillEllipse(new V2(top.X, top.Y + 0.6), 7.6, 2.0);
                break;
            case HatStyle.Flower:
            {
                for (int i = 0; i < 5; i++)
                {
                    double a = i / 5.0 * M.Tau + pose.Time * 0.1;
                    g.SetFill(new Rgba(0.97, 0.62, 0.75));
                    g.FillEllipse(new V2(top.X + Math.Cos(a) * 3.4, top.Y + 1 + Math.Sin(a) * 3.0), 2.5, 2.2);
                }
                g.SetFill(new Rgba(0.99, 0.85, 0.35));
                g.FillEllipse(new V2(top.X, top.Y + 1), 1.8, 1.7);
                break;
            }
            case HatStyle.Bow:
            {
                g.SetFill(new Rgba(0.90, 0.30, 0.45));
                g.FillEllipse(new V2(top.X - 3.6, top.Y + 2.5), 3.6, 2.4);
                g.FillEllipse(new V2(top.X + 3.6, top.Y + 2.5), 3.6, 2.4);
                g.FillEllipse(new V2(top.X, top.Y + 2.5), 1.6, 1.6);
                break;
            }
            case HatStyle.Cap:
                g.SetFill(new Rgba(0.22, 0.42, 0.72));
                g.FillEllipse(new V2(top.X, top.Y + 2.6), 7.2, 5.2);
                g.FillEllipse(new V2(top.X + 5.2, top.Y + 0.2), 5.0, 1.7);
                break;
            case HatStyle.Halo:
                g.SetStroke(new Rgba(1.0, 0.90, 0.45, 0.95));
                g.SetLineWidth(1.9);
                g.StrokeEllipse(new V2(top.X, top.Y + 8.5), 6.0, 1.9);
                break;
            case HatStyle.Wizard:
            {
                g.SetFill(new Rgba(0.28, 0.22, 0.62));
                g.NewPath();
                g.MoveTo(new V2(top.X - 7, top.Y));
                g.LineTo(new V2(top.X - 1.5, top.Y + 16));
                g.LineTo(new V2(top.X + 7, top.Y));
                g.ClosePath();
                g.Fill();
                g.SetFill(new Rgba(0.98, 0.85, 0.35, 0.9));
                for (int i = 0; i < 3; i++)
                    g.FillEllipse(new V2(top.X - 3 + i * 3, top.Y + 4 + i * 2.4), 0.8, 0.8);
                break;
            }
            case HatStyle.Propeller:
            {
                g.SetFill(new Rgba(0.35, 0.62, 0.85));
                g.FillEllipse(new V2(top.X, top.Y + 2.4), 7.0, 5.0);
                double spin = pose.Odometer * 0.6 + pose.Time * 0.4;
                g.SetStroke(new Rgba(0.95, 0.35, 0.35));
                g.SetLineWidth(1.5);
                g.NewPath();
                g.MoveTo(new V2(top.X - Math.Cos(spin) * 6, top.Y + 8 + Math.Sin(spin) * 1.6));
                g.LineTo(new V2(top.X + Math.Cos(spin) * 6, top.Y + 8 - Math.Sin(spin) * 1.6));
                g.Stroke();
                g.SetFill(new Rgba(0.95, 0.35, 0.35));
                g.FillEllipse(new V2(top.X, top.Y + 8), 1.4, 1.4);
                break;
            }
            case HatStyle.Cowboy:
            {
                g.SetFill(new Rgba(0.62, 0.44, 0.26));
                g.FillEllipse(new V2(top.X, top.Y + 0.8), 11.0, 2.9);
                g.FillEllipse(new V2(top.X, top.Y + 5.2), 5.2, 4.4);
                g.SetFill(new Rgba(0.40, 0.28, 0.18));
                g.FillEllipse(new V2(top.X, top.Y + 1.6), 5.4, 1.2);
                break;
            }
            case HatStyle.Chef:
                g.SetFill(Rgba.White);
                g.FillEllipse(new V2(top.X, top.Y + 8), 8.4, 6.4);
                g.FillEllipse(new V2(top.X - 4, top.Y + 10.5), 4.0, 3.6);
                g.FillEllipse(new V2(top.X + 4, top.Y + 10.5), 4.0, 3.6);
                g.FillEllipse(new V2(top.X, top.Y + 1.2), 6.6, 2.0);
                break;
            case HatStyle.Fez:
                g.SetFill(new Rgba(0.72, 0.15, 0.16));
                g.FillEllipse(new V2(top.X, top.Y + 3.0), 5.2, 3.4);
                g.SetFill(new Rgba(0.98, 0.85, 0.35));
                g.FillEllipse(new V2(top.X, top.Y + 0.6), 5.4, 0.9);
                break;
            case HatStyle.Beret:
                g.SetFill(new Rgba(0.55, 0.20, 0.35));
                g.FillEllipse(new V2(top.X, top.Y + 3.4), 8.0, 3.4);
                g.FillEllipse(new V2(top.X + 2, top.Y + 6.2), 1.4, 1.4);
                break;
            case HatStyle.Bowler:
                g.SetFill(new Rgba(0.16, 0.16, 0.20));
                g.FillEllipse(new V2(top.X, top.Y + 0.6), 9.5, 2.4);
                g.FillEllipse(new V2(top.X, top.Y + 5.0), 5.4, 4.6);
                break;
            case HatStyle.Santa:
                g.SetFill(new Rgba(0.82, 0.14, 0.16));
                g.NewPath();
                g.MoveTo(new V2(top.X - 7.4, top.Y));
                g.QuadTo(new V2(top.X, top.Y + 13), new V2(top.X + 7.4, top.Y));
                g.ClosePath();
                g.Fill();
                g.SetFill(Rgba.White);
                g.FillEllipse(new V2(top.X, top.Y + 0.4), 7.6, 1.8);
                g.FillEllipse(new V2(top.X + 6.6, top.Y + 8.4), 2.2, 2.2);
                break;
            case HatStyle.BunnyEars:
                foreach (int s in new[] { -1, 1 })
                {
                    g.SetFill(new Rgba(0.94, 0.90, 0.93));
                    g.NewPath();
                    g.MoveTo(new V2(top.X + s * 3.4, top.Y));
                    g.QuadTo(new V2(top.X + s * 5.4, top.Y + 14), new V2(top.X + s * 6.6, top.Y + 12));
                    g.QuadTo(new V2(top.X + s * 6.2, top.Y + 2), new V2(top.X + s * 3.4, top.Y));
                    g.Fill();
                    g.SetFill(new Rgba(0.95, 0.62, 0.70));
                    g.FillEllipse(new V2(top.X + s * 5.0, top.Y + 7.5), 0.9, 4.0);
                }
                break;
            case HatStyle.CatEars:
                foreach (int s in new[] { -1, 1 })
                {
                    g.SetFill(new Rgba(0.25, 0.22, 0.26));
                    g.NewPath();
                    g.MoveTo(new V2(top.X + s * 2.6, top.Y + 1));
                    g.LineTo(new V2(top.X + s * 6.4, top.Y + 10));
                    g.LineTo(new V2(top.X + s * 7.4, top.Y + 1));
                    g.ClosePath();
                    g.Fill();
                }
                break;
            case HatStyle.Antlers:
                g.SetStroke(new Rgba(0.55, 0.38, 0.22));
                g.SetLineWidth(1.9);
                foreach (int s in new[] { -1, 1 })
                {
                    g.NewPath();
                    g.MoveTo(new V2(top.X + s * 3, top.Y + 1));
                    g.LineTo(new V2(top.X + s * 7, top.Y + 10));
                    g.LineTo(new V2(top.X + s * 10, top.Y + 12));
                    g.MoveTo(new V2(top.X + s * 7, top.Y + 10));
                    g.LineTo(new V2(top.X + s * 5, top.Y + 14));
                    g.Stroke();
                }
                break;
            case HatStyle.HardHat:
                g.SetFill(new Rgba(0.98, 0.78, 0.16));
                g.FillEllipse(new V2(top.X, top.Y + 3.4), 8.0, 5.4);
                g.FillEllipse(new V2(top.X, top.Y + 0.6), 10.0, 1.8);
                break;
            case HatStyle.Horns:
                g.SetFill(new Rgba(0.86, 0.28, 0.20));
                foreach (int s in new[] { -1, 1 })
                {
                    g.NewPath();
                    g.MoveTo(new V2(top.X + s * 4.4, top.Y + 2));
                    g.LineTo(new V2(top.X + s * 7.0, top.Y + 9));
                    g.LineTo(new V2(top.X + s * 7.6, top.Y + 1));
                    g.ClosePath();
                    g.Fill();
                }
                break;
            case HatStyle.Unicorn:
            {
                g.SetFill(new Rgba(0.99, 0.95, 0.75));
                g.NewPath();
                g.MoveTo(new V2(top.X - 1.6, top.Y + 2));
                g.LineTo(new V2(top.X + 0.8, top.Y + 16));
                g.LineTo(new V2(top.X + 2.0, top.Y + 2));
                g.ClosePath();
                g.Fill();
                break;
            }
            case HatStyle.Pumpkin:
            {
                g.SetFill(new Rgba(0.95, 0.52, 0.15));
                g.FillEllipse(new V2(top.X, top.Y + 3.4), 8.2, 5.0);
                g.SetStroke(new Rgba(0.85, 0.40, 0.10));
                g.SetLineWidth(1.1);
                for (int i = -1; i <= 1; i++)
                {
                    g.NewPath();
                    g.MoveTo(new V2(top.X + i * 3.4, top.Y + 8));
                    g.QuadTo(new V2(top.X + i * 4.6, top.Y + 3.4), new V2(top.X + i * 3.4, top.Y - 1));
                    g.Stroke();
                }
                g.SetFill(new Rgba(0.35, 0.55, 0.25));
                g.FillEllipse(new V2(top.X, top.Y + 8.6), 1.4, 2.0);
                break;
            }
            case HatStyle.Strawberry:
            {
                g.SetFill(new Rgba(0.90, 0.20, 0.26));
                g.NewPath();
                g.MoveTo(new V2(top.X - 6.4, top.Y + 2));
                g.QuadTo(new V2(top.X, top.Y - 6), new V2(top.X + 6.4, top.Y + 2));
                g.QuadTo(new V2(top.X, top.Y + 10), new V2(top.X - 6.4, top.Y + 2));
                g.Fill();
                g.SetFill(new Rgba(0.35, 0.62, 0.28));
                g.FillEllipse(new V2(top.X, top.Y + 8.4), 3.4, 1.5);
                break;
            }
            default:
            {
                // a simple, tidy hat for the styles not drawn in detail yet
                g.SetFill(pal.Accent.Lighter(0.15));
                g.FillEllipse(new V2(top.X, top.Y + 2.6), 6.6, 4.4);
                break;
            }
        }
        g.Restore();
    }

    static void DrawAccessory(IDraw g, SpiderPose pose, SpiderLook look, Palette pal)
    {
        if (look.Accessory == AccessoryStyle.None) return;
        double prof = SpiderRig.ProfileAmount(pose.Facing);
        var (hc, hr) = HeadShapeForHat(look, prof, pose);

        g.Save();
        g.Translate(hc.X, hc.Y + pose.HeadCock * 1.5);
        g.Rotate(pose.HeadTilt);
        g.Translate(-hc.X, -hc.Y);

        V2 face = new(hc.X + 5 * prof, hc.Y + 1);
        V2 neck = new(hc.X - 2, hc.Y - hr * 0.95);

        switch (look.Accessory)
        {
            case AccessoryStyle.Glasses:
                g.SetStroke(new Rgba(0.20, 0.22, 0.28));
                g.SetLineWidth(1.3);
                g.StrokeEllipse(new V2(face.X + 3, face.Y + 1.5), 4.6, 4.0);
                g.StrokeEllipse(new V2(face.X + 11, face.Y + 1.5), 4.6, 4.0);
                g.NewPath();
                g.MoveTo(new V2(face.X + 7.6, face.Y + 1.5));
                g.LineTo(new V2(face.X + 6.4, face.Y + 1.5));
                g.Stroke();
                break;
            case AccessoryStyle.Monocle:
                g.SetStroke(new Rgba(0.85, 0.72, 0.30));
                g.SetLineWidth(1.6);
                g.StrokeEllipse(new V2(face.X + 4, face.Y + 1.5), 5.0, 4.6);
                g.NewPath();
                g.MoveTo(new V2(face.X + 4, face.Y - 3));
                g.QuadTo(new V2(face.X + 2, face.Y - 9), new V2(face.X - 2, face.Y - 12));
                g.Stroke();
                break;
            case AccessoryStyle.Shades:
            case AccessoryStyle.HeartShades:
            {
                g.SetFill(new Rgba(0.10, 0.10, 0.14, 0.92));
                g.FillEllipse(new V2(face.X + 3, face.Y + 1.5), 5.0, 3.6);
                g.FillEllipse(new V2(face.X + 11, face.Y + 1.5), 5.0, 3.6);
                if (look.Accessory == AccessoryStyle.HeartShades)
                {
                    DrawHeart(g, new V2(face.X + 3, face.Y + 1.5), 3.2, new Rgba(0.92, 0.25, 0.35));
                    DrawHeart(g, new V2(face.X + 11, face.Y + 1.5), 3.2, new Rgba(0.92, 0.25, 0.35));
                }
                break;
            }
            case AccessoryStyle.Goggles:
                g.SetStroke(new Rgba(0.35, 0.30, 0.26));
                g.SetLineWidth(2.4);
                g.StrokeEllipse(new V2(face.X + 3, face.Y + 2), 5.2, 4.6);
                g.StrokeEllipse(new V2(face.X + 11, face.Y + 2), 5.2, 4.6);
                g.SetFill(new Rgba(0.60, 0.80, 0.95, 0.35));
                g.FillEllipse(new V2(face.X + 3, face.Y + 2), 4.6, 4.0);
                g.FillEllipse(new V2(face.X + 11, face.Y + 2), 4.6, 4.0);
                break;
            case AccessoryStyle.EyePatch:
                g.SetFill(new Rgba(0.12, 0.12, 0.16));
                g.FillEllipse(new V2(face.X + 3, face.Y + 1.5), 4.4, 4.0);
                g.SetStroke(new Rgba(0.12, 0.12, 0.16));
                g.SetLineWidth(1.2);
                g.NewPath();
                g.MoveTo(new V2(face.X - 1, face.Y + 4));
                g.LineTo(new V2(hc.X - 6, hc.Y + 7));
                g.Stroke();
                break;
            case AccessoryStyle.HeroMask:
                g.SetFill(new Rgba(0.20, 0.35, 0.75, 0.9));
                g.NewPath();
                g.MoveTo(new V2(face.X - 4, face.Y + 6));
                g.QuadTo(new V2(face.X + 6, face.Y + 9), new V2(face.X + 14, face.Y + 3));
                g.LineTo(new V2(face.X + 12, face.Y - 2));
                g.QuadTo(new V2(face.X + 5, face.Y + 1), new V2(face.X - 4, face.Y - 1));
                g.ClosePath();
                g.Fill();
                break;
            case AccessoryStyle.ClownNose:
                g.SetFill(new Rgba(0.92, 0.20, 0.20));
                g.FillEllipse(new V2(face.X + 7, face.Y - 4), 2.8, 2.6);
                break;
            case AccessoryStyle.Moustache:
                g.SetFill(new Rgba(0.24, 0.16, 0.12));
                g.NewPath();
                g.MoveTo(new V2(face.X + 3, face.Y - 7));
                g.QuadTo(new V2(face.X + 7, face.Y - 4), new V2(face.X + 11, face.Y - 7));
                g.QuadTo(new V2(face.X + 7, face.Y - 8.5), new V2(face.X + 3, face.Y - 7));
                g.Fill();
                break;
            case AccessoryStyle.BowTie:
                g.SetFill(new Rgba(0.80, 0.18, 0.28));
                g.FillEllipse(new V2(neck.X - 2, neck.Y - 1), 2.6, 2.0);
                g.FillEllipse(new V2(neck.X + 2.4, neck.Y - 1), 2.6, 2.0);
                break;
            case AccessoryStyle.Necktie:
                g.SetFill(new Rgba(0.20, 0.35, 0.65));
                g.NewPath();
                g.MoveTo(new V2(neck.X - 2, neck.Y));
                g.LineTo(new V2(neck.X + 2, neck.Y));
                g.LineTo(new V2(neck.X + 1, neck.Y - 8));
                g.LineTo(new V2(neck.X - 1, neck.Y - 8));
                g.ClosePath();
                g.Fill();
                break;
            case AccessoryStyle.Scarf:
                g.SetFill(new Rgba(0.85, 0.35, 0.34));
                g.FillEllipse(new V2(neck.X, neck.Y + 1), 6.4, 2.6);
                g.FillEllipse(new V2(neck.X - 4, neck.Y - 4), 2.2, 4.0);
                break;
            case AccessoryStyle.Bandana:
                g.SetFill(new Rgba(0.30, 0.55, 0.82));
                g.NewPath();
                g.MoveTo(new V2(neck.X - 6, neck.Y + 2));
                g.LineTo(new V2(neck.X + 6, neck.Y + 2));
                g.LineTo(new V2(neck.X, neck.Y - 7));
                g.ClosePath();
                g.Fill();
                break;
            case AccessoryStyle.BellCollar:
                g.SetStroke(new Rgba(0.75, 0.20, 0.22));
                g.SetLineWidth(2.2);
                g.NewPath();
                g.MoveTo(new V2(neck.X - 6, neck.Y + 1));
                g.QuadTo(new V2(neck.X, neck.Y - 2), new V2(neck.X + 6, neck.Y + 1));
                g.Stroke();
                g.SetFill(new Rgba(0.98, 0.84, 0.30));
                g.FillEllipse(new V2(neck.X, neck.Y - 3.2), 2.2, 2.2);
                break;
            case AccessoryStyle.Pearls:
                g.SetFill(new Rgba(0.97, 0.96, 0.94));
                for (int i = 0; i < 5; i++)
                {
                    double a = (i - 2) * 0.42;
                    g.FillEllipse(new V2(neck.X + Math.Sin(a) * 8, neck.Y + 1 - Math.Cos(a) * 2.4), 1.4, 1.4);
                }
                break;
            case AccessoryStyle.Medal:
                g.SetStroke(new Rgba(0.30, 0.45, 0.80));
                g.SetLineWidth(1.2);
                g.NewPath();
                g.MoveTo(new V2(neck.X - 3, neck.Y + 2));
                g.LineTo(new V2(neck.X, neck.Y - 5));
                g.LineTo(new V2(neck.X + 3, neck.Y + 2));
                g.Stroke();
                g.SetFill(new Rgba(0.98, 0.82, 0.28));
                g.FillEllipse(new V2(neck.X, neck.Y - 6), 2.6, 2.6);
                break;
            case AccessoryStyle.Sweater:
                g.SetFill(new Rgba(0.85, 0.42, 0.30));
                g.FillEllipse(new V2(neck.X - 4, neck.Y - 2), 9.0, 6.0);
                break;
            case AccessoryStyle.Cape:
                g.SetFill(new Rgba(0.55, 0.12, 0.22, 0.92));
                g.NewPath();
                g.MoveTo(new V2(neck.X - 1, neck.Y + 2));
                g.QuadTo(new V2(neck.X - 16, neck.Y - 6), new V2(neck.X - 12, neck.Y - 16));
                g.QuadTo(new V2(neck.X - 2, neck.Y - 10), new V2(neck.X + 2, neck.Y - 2));
                g.ClosePath();
                g.Fill();
                break;
            case AccessoryStyle.BatWings:
            case AccessoryStyle.FairyWings:
            {
                var col = look.Accessory == AccessoryStyle.BatWings
                    ? new Rgba(0.28, 0.20, 0.34, 0.85)
                    : new Rgba(0.80, 0.92, 1.0, 0.68);
                g.SetFill(col);
                for (int s = -1; s <= 1; s += 2)
                {
                    g.NewPath();
                    g.MoveTo(new V2(neck.X - 2, neck.Y + 2));
                    g.QuadTo(new V2(neck.X + s * 12, neck.Y + 12), new V2(neck.X + s * 14, neck.Y + 1));
                    g.QuadTo(new V2(neck.X + s * 10, neck.Y - 4), new V2(neck.X - 2, neck.Y - 2));
                    g.Fill();
                }
                break;
            }
            default:
                g.SetFill(pal.Accent.WithAlpha(0.9));
                g.FillEllipse(new V2(neck.X, neck.Y - 2), 4.0, 3.0);
                break;
        }
        g.Restore();
    }

    // ------------------------------------------------------------------ bubbles and name tag

    static void DrawEmote(IDraw g, SpiderPose pose, Palette pal)
    {
        if (pose.Emote == EmoteKind.None || pose.EmoteT <= 0.001) return;

        double t = M.Clamp01(pose.EmoteT);
        double alpha = Math.Min(1, Math.Min(t * 6, (1 - t) * 6));
        if (alpha <= 0.001) return;

        V2 anchor = pose.Pos + new V2(0, 30 * pose.Scale);

        switch (pose.Emote)
        {
            case EmoteKind.Heart:
                DrawHeart(g, anchor + new V2(0, 6 * pose.Scale * t), 7 * pose.Scale,
                    new Rgba(0.94, 0.32, 0.42, alpha));
                break;
            case EmoteKind.Zzz:
                for (int i = 0; i < 3; i++)
                {
                    double ph = (pose.EmoteClock * 0.5 + i / 3.0) % 1.0;
                    double size = (4 + i * 1.6) * pose.Scale;
                    V2 p = anchor + new V2(6 + ph * 14, 4 + ph * 20) * pose.Scale;
                    DrawZ(g, p, size, alpha * (1 - Math.Abs(ph - 0.5) * 1.4));
                }
                break;
            case EmoteKind.Surprise:
            case EmoteKind.Exclaim:
                DrawBang(g, anchor, 1.0, alpha, pose.Scale, pose.Emote == EmoteKind.Exclaim ? 2 : 1);
                break;
            case EmoteKind.Sparkle:
                for (int i = 0; i < 3; i++)
                {
                    double a = pose.EmoteClock * 1.2 + i * 2.1;
                    V2 p = anchor + new V2(Math.Cos(a) * 12, Math.Sin(a) * 8 + 6) * pose.Scale;
                    DrawStar(g, p, 3.6 * pose.Scale, new Rgba(1.0, 0.88, 0.42, alpha));
                }
                break;
            case EmoteKind.Question:
                DrawText(g, "?", anchor, 13 * pose.Scale, new Rgba(0.35, 0.30, 0.26, alpha));
                break;
            case EmoteKind.Note:
                DrawNote(g, anchor, pose.Scale, alpha);
                break;
            case EmoteKind.Charge:
                g.SetStroke(new Rgba(0.55, 0.85, 1.0, alpha));
                g.SetLineWidth(1.6);
                for (int i = 0; i < 3; i++)
                {
                    double a = pose.EmoteClock * 6 + i * 2.1;
                    V2 p = anchor + new V2(Math.Cos(a) * 12, Math.Sin(a) * 9) * pose.Scale;
                    g.NewPath();
                    g.MoveTo(p);
                    g.LineTo(p + new V2(2, 5) * pose.Scale);
                    g.Stroke();
                }
                break;
            case EmoteKind.Thought:
                DrawThoughtBubble(g, pose, alpha);
                break;
        }
    }

    static void DrawThoughtBubble(IDraw g, SpiderPose pose, double alpha)
    {
        if (pose.Thought == ThoughtKind.Text && !string.IsNullOrWhiteSpace(pose.ThoughtText))
        {
            DrawThoughtTextBubble(g, pose, alpha);
            return;
        }
        double s = pose.Scale;
        V2 c = pose.Pos + new V2(26 * s, 34 * s);
        double r = 13 * s;
        g.SetFill(new Rgba(0.99, 0.99, 0.98, 0.92 * alpha));
        g.SetStroke(new Rgba(0.35, 0.30, 0.26, 0.65 * alpha));
        g.SetLineWidth(1.2);
        g.FillEllipse(c, r, r * 0.86);
        g.StrokeEllipse(c, r, r * 0.86);
        // the little trail of dots back to the spider
        for (int i = 0; i < 3; i++)
        {
            double f = (i + 1) / 4.0;
            V2 p = V2.Lerp(pose.Pos + new V2(8 * s, 22 * s), c - new V2(r * 0.7, r * 0.6), f);
            g.FillEllipse(p, 2.2 * s * (1 - f * 0.4), 2.2 * s * (1 - f * 0.4));
        }
        DrawThoughtIcon(g, pose, c, r, alpha);
    }

    static void DrawThoughtIcon(IDraw g, SpiderPose pose, V2 c, double r, double alpha)
    {
        switch (pose.Thought)
        {
            case ThoughtKind.Heart: DrawHeart(g, c, r * 0.6, new Rgba(0.92, 0.32, 0.42, alpha)); break;
            case ThoughtKind.Rain:
                g.SetFill(new Rgba(0.62, 0.70, 0.82, alpha));
                g.FillEllipse(c + new V2(-3, 3), r * 0.5, r * 0.34);
                g.FillEllipse(c + new V2(3, 4), r * 0.45, r * 0.32);
                g.SetStroke(new Rgba(0.35, 0.55, 0.85, alpha));
                g.SetLineWidth(1.2);
                for (int i = -1; i <= 1; i++)
                {
                    g.NewPath();
                    g.MoveTo(c + new V2(i * 4.0, -1));
                    g.LineTo(c + new V2(i * 4.0 - 1, -6));
                    g.Stroke();
                }
                break;
            case ThoughtKind.Sun:
                g.SetFill(new Rgba(0.99, 0.82, 0.30, alpha));
                g.FillEllipse(c, r * 0.38, r * 0.38);
                break;
            case ThoughtKind.Moon:
                g.SetFill(new Rgba(0.95, 0.93, 0.80, alpha));
                g.FillEllipse(c, r * 0.4, r * 0.4);
                g.SetFill(new Rgba(0.99, 0.99, 0.98, alpha));
                g.FillEllipse(c + new V2(r * 0.22, r * 0.12), r * 0.34, r * 0.34);
                break;
            case ThoughtKind.Music: DrawNote(g, c, 1, alpha); break;
            case ThoughtKind.Star: DrawStar(g, c, r * 0.55, new Rgba(1.0, 0.88, 0.42, alpha)); break;
            case ThoughtKind.Bug:
                g.SetFill(new Rgba(0.35, 0.30, 0.22, alpha));
                g.FillEllipse(c, r * 0.34, r * 0.24);
                g.SetStroke(new Rgba(0.35, 0.30, 0.22, alpha));
                g.SetLineWidth(1.0);
                for (int i = -1; i <= 1; i += 2)
                    for (int k = -1; k <= 1; k++)
                    {
                        g.NewPath();
                        g.MoveTo(c + new V2(i * r * 0.2, k * r * 0.1));
                        g.LineTo(c + new V2(i * r * 0.55, k * r * 0.22));
                        g.Stroke();
                    }
                break;
            case ThoughtKind.Home:
                g.SetFill(new Rgba(0.62, 0.46, 0.30, alpha));
                g.NewPath();
                g.MoveTo(c + new V2(-r * 0.5, 0));
                g.LineTo(c + new V2(0, r * 0.45));
                g.LineTo(c + new V2(r * 0.5, 0));
                g.ClosePath();
                g.Fill();
                break;
            case ThoughtKind.Snow:
                g.SetStroke(new Rgba(0.70, 0.85, 0.95, alpha));
                g.SetLineWidth(1.1);
                for (int i = 0; i < 3; i++)
                {
                    double a = i / 3.0 * M.Pi;
                    g.NewPath();
                    g.MoveTo(c + new V2(Math.Cos(a), Math.Sin(a)) * r * 0.45);
                    g.LineTo(c - new V2(Math.Cos(a), Math.Sin(a)) * r * 0.45);
                    g.Stroke();
                }
                break;
            case ThoughtKind.Dots:
                g.SetFill(new Rgba(0.35, 0.30, 0.26, alpha));
                for (int i = 0; i < 3; i++)
                {
                    double bob = Math.Sin(pose.EmoteClock * 4 + i) * 1.4;
                    g.FillEllipse(c + new V2((i - 1) * r * 0.42, bob), 1.7, 1.7);
                }
                break;
            default:
                g.SetFill(new Rgba(0.40, 0.34, 0.28, alpha));
                g.FillEllipse(c, r * 0.25, r * 0.25);
                break;
        }
    }

    static void DrawNameTag(IDraw g, SpiderPose pose, Palette pal)
    {
        double a = M.Clamp01(pose.NameTag) * 0.92;
        double s = pose.Scale;
        V2 c = pose.Pos + new V2(0, -38 * s);
        double w = Math.Max(30, (pose.Name?.Length ?? 0) * 4.6 + 12) * s;
        double h = 13 * s;
        g.SetFill(new Rgba(0.99, 0.98, 0.96, a));
        g.SetStroke(new Rgba(0.30, 0.26, 0.22, a * 0.5));
        g.SetLineWidth(1.0);
        g.AddRoundedRect(new Rect(c.X - w / 2, c.Y - h / 2, w, h), 4 * s);
        g.FillAndStroke();
        DrawText(g, pose.Name ?? "", c + new V2(0, -3.4 * s), 8.5 * s, new Rgba(0.25, 0.22, 0.18, a));
    }

    // ------------------------------------------------------------------ small shapes

    public static void DrawHeart(IDraw g, V2 c, double r, Rgba col)
    {
        g.SetFill(col);
        g.NewPath();
        g.MoveTo(c + new V2(0, -r * 0.75));
        g.CurveTo(c + new V2(-r * 1.35, r * 0.35), c + new V2(-r * 0.55, r * 1.05), c + new V2(0, r * 0.42));
        g.CurveTo(c + new V2(r * 0.55, r * 1.05), c + new V2(r * 1.35, r * 0.35), c + new V2(0, -r * 0.75));
        g.ClosePath();
        g.Fill();
    }

    public static void DrawStar(IDraw g, V2 c, double r, Rgba col)
    {
        g.SetFill(col);
        g.NewPath();
        for (int i = 0; i < 10; i++)
        {
            double a = -M.Pi / 2 + i * M.Pi / 5;
            double rad = (i % 2 == 0) ? r : r * 0.44;
            V2 p = c + new V2(Math.Cos(a), Math.Sin(a)) * rad;
            if (i == 0) g.MoveTo(p); else g.LineTo(p);
        }
        g.ClosePath();
        g.Fill();
    }

    static void DrawZ(IDraw g, V2 c, double size, double alpha)
    {
        g.SetStroke(new Rgba(0.35, 0.42, 0.62, M.Clamp01(alpha)));
        g.SetLineWidth(1.5);
        g.NewPath();
        g.MoveTo(c + new V2(-size * 0.5, size * 0.5));
        g.LineTo(c + new V2(size * 0.5, size * 0.5));
        g.LineTo(c + new V2(-size * 0.5, -size * 0.5));
        g.LineTo(c + new V2(size * 0.5, -size * 0.5));
        g.Stroke();
    }

    static void DrawBang(IDraw g, V2 c, double size, double alpha, double scale, int count)
    {
        for (int i = 0; i < count; i++)
        {
            double x = c.X + (i - (count - 1) / 2.0) * 7 * scale;
            g.SetFill(new Rgba(0.95, 0.55, 0.20, alpha));
            g.FillEllipse(new V2(x, c.Y + 4 * scale), 1.7 * scale, 2.0 * scale);
            g.FillEllipse(new V2(x, c.Y - 1 * scale), 1.4 * scale, 1.4 * scale);
        }
    }

    static void DrawNote(IDraw g, V2 c, double s, double alpha)
    {
        g.SetFill(new Rgba(0.35, 0.40, 0.68, alpha));
        g.FillEllipse(c + new V2(-2 * s, -3 * s), 2.6 * s, 2.0 * s);
        g.SetStroke(new Rgba(0.35, 0.40, 0.68, alpha));
        g.SetLineWidth(1.3);
        g.NewPath();
        g.MoveTo(c + new V2(0.4 * s, -2.2 * s));
        g.LineTo(c + new V2(0.4 * s, 6 * s));
        g.LineTo(c + new V2(5 * s, 4.4 * s));
        g.Stroke();
    }

    /// <summary>
    /// A tiny text fallback: the shim has no font, so this draws with the platform's own text later.
    /// For now it centres a simple glyph run as small marks so bubbles read at desktop size.
    /// </summary>
    static void DrawText(IDraw g, string text, V2 c, double size, Rgba col)
    {
        if (string.IsNullOrEmpty(text)) return;
        // Platform text is provided by the host through ITextDraw; when it is absent (the contact
        // sheet, headless tools) we draw a placeholder block so layout is still verifiable.
        if (g is ITextDrawable td)
        {
            td.DrawText(text, c, size, col);
            return;
        }
        g.SetFill(col.WithAlpha(col.A * 0.25));
        double w = text.Length * size * 0.5;
        g.FillEllipse(c + new V2(0, size * 0.3), w * 0.5, size * 0.4);
    }

    static void DrawThoughtTextBubble(IDraw g, SpiderPose pose, double alpha)
    {
        var layout = ThoughtTextLayout(pose);
        double s = pose.Scale;
        g.SetFill(new Rgba(0.99, 0.99, 0.98, 0.94 * alpha));
        g.SetStroke(new Rgba(0.35, 0.30, 0.26, 0.65 * alpha));
        g.SetLineWidth(1.2);
        g.AddRoundedRect(layout.rect, 8 * s);
        g.FillAndStroke();
        // The little trail of dots back to the spider.
        for (int i = 0; i < 3; i++)
        {
            double f = (i + 1) / 4.0;
            V2 p = V2.Lerp(pose.Pos + new V2(8 * s, 22 * s),
                new V2(layout.rect.MinX + 8 * s, layout.rect.MinY + 5 * s), f);
            g.FillEllipse(p, 2.2 * s * (1 - f * 0.4), 2.2 * s * (1 - f * 0.4));
        }
        double size = 8.0 * s;
        double lineHeight = 9.8 * s;
        double y = layout.rect.MaxY - 8 * s;
        foreach (var line in layout.lines)
        {
            DrawText(g, line, new V2(layout.rect.Mid.X, y), size,
                new Rgba(0.30, 0.26, 0.22, alpha));
            y -= lineHeight;
        }
    }

    static (Rect rect, List<string> lines) ThoughtTextLayout(SpiderPose pose)
    {
        double s = pose.Scale;
        var lines = WrapText(pose.ThoughtText ?? "", 32, 5);
        int longest = lines.Count == 0 ? 1 : lines.Max(l => l.Length);
        double width = Math.Min(190 * s, Math.Max(56 * s, longest * 4.6 * s + 15 * s));
        double height = lines.Count * 9.8 * s + 12 * s;
        double left = pose.Pos.X + 16 * s;
        double bottom = pose.Pos.Y + 30 * s;
        return (new Rect(left, bottom, width, height), lines);
    }

    static List<string> WrapText(string text, int maxChars, int maxLines)
    {
        var lines = new List<string>();
        var words = text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var line = "";
        foreach (var word in words)
        {
            if (line.Length == 0) line = word;
            else if (line.Length + 1 + word.Length <= maxChars) line += " " + word;
            else { lines.Add(line); line = word; if (lines.Count == maxLines - 1) break; }
        }
        if (line.Length > 0 && lines.Count < maxLines) lines.Add(line);
        if (lines.Count == maxLines)
        {
            int consumed = lines.Sum(l => l.Length) + Math.Max(0, lines.Count - 1);
            if (consumed < text.Length && lines[^1].Length > 1)
                lines[^1] = lines[^1][..Math.Min(lines[^1].Length, maxChars - 1)] + "…";
        }
        return lines;
    }

    /// <summary>The thought-bubble rect, used to hit-test a click on the bubble (spec 3.7).</summary>
    public static Rect ThoughtBubbleRect(SpiderPose pose)
    {
        if (pose.Thought == ThoughtKind.Text && !string.IsNullOrWhiteSpace(pose.ThoughtText))
            return ThoughtTextLayout(pose).rect;
        double s = pose.Scale;
        V2 c = pose.Pos + new V2(26 * s, 34 * s);
        double r = 13 * s;
        return new Rect(c.X - r, c.Y - r * 0.86, r * 2, r * 1.72);
    }
}

/// <summary>Optional text drawing supplied by the host (Skia/DirectWrite).</summary>
public interface ITextDrawable
{
    void DrawText(string text, V2 centre, double size, Rgba colour);
}
