namespace SpiderBuddy.Core;

/// <summary>A colour in sRGB, components 0…1 (the spec's colour convention — spec 3.2).</summary>
public readonly struct Rgba
{
    public readonly double R, G, B, A;
    public Rgba(double r, double g, double b, double a = 1) { R = r; G = g; B = b; A = a; }

    public static Rgba Rgb(double r, double g, double b) => new(r, g, b, 1);
    public static Rgba White => new(1, 1, 1, 1);
    public static Rgba Black => new(0, 0, 0, 1);
    public static Rgba Clear => new(0, 0, 0, 0);

    public Rgba WithAlpha(double a) => new(R, G, B, a);
    public Rgba Scale(double k) => new(R * k, G * k, B * k, A);
    public Rgba Mix(Rgba o, double t) => new(M.Lerp(R, o.R, t), M.Lerp(G, o.G, t), M.Lerp(B, o.B, t), M.Lerp(A, o.A, t));

    /// <summary>Darken toward black by a fixed step (camo shade rule, spec 3.6).</summary>
    public Rgba Darker(double k) => new(R * (1 - k), G * (1 - k), B * (1 - k), A);
    public Rgba Lighter(double k) => new(M.Lerp(R, 1, k), M.Lerp(G, 1, k), M.Lerp(B, 1, k), A);

    /// <summary>Perceptual luminance, used for camouflage tonal steps.</summary>
    public double Luma => 0.2126 * R + 0.7152 * G + 0.0722 * B;

    public static Rgba FromBytes(byte r, byte g, byte b, byte a = 255) => new(r / 255.0, g / 255.0, b / 255.0, a / 255.0);

    public override string ToString() => $"rgba({R:0.###},{G:0.###},{B:0.###},{A:0.###})";
}

public enum LineCap { Butt, Round, Square }
public enum LineJoin { Miter, Round, Bevel }

/// <summary>
/// The vector drawing shim (spec 3.2). The core draws only through this interface, so `core/`
/// stays free of drawing-API calls (§1.1) and the implementation (Skia) lives in the renderer.
/// The vocabulary is the ~40 CoreGraphics verbs the art actually uses.
/// </summary>
public interface IDraw
{
    // state
    void Save();
    void Restore();
    void Translate(double x, double y);
    void Rotate(double radians);
    void Scale(double x, double y);
    void SetFill(Rgba c);
    void SetStroke(Rgba c);
    void SetLineWidth(double w);
    void SetAlpha(double a);
    void SetLineCap(LineCap cap);
    void SetLineJoin(LineJoin join);

    // paths
    void NewPath();
    void MoveTo(V2 p);
    void LineTo(V2 p);
    void QuadTo(V2 control, V2 p);
    void CurveTo(V2 c1, V2 c2, V2 p);
    void ArcTo(V2 centre, double radius, double startAngle, double endAngle, bool clockwise);
    void ClosePath();
    void AddEllipse(V2 centre, double rx, double ry);
    void AddRect(Rect r);
    void AddRoundedRect(Rect r, double radius);

    // paint
    void Fill();
    void Stroke();
    void FillAndStroke();
    void FillEllipse(V2 centre, double rx, double ry);
    void StrokeEllipse(V2 centre, double rx, double ry);

    // clipping
    void ClipRect(Rect r);
    void ClipPath(bool evenOdd = false);

    // gradients (coats, glass, sun — 5 linear + 3 radial in the art)
    void FillLinearGradient(V2 from, V2 to, Rgba a, Rgba b);
    void FillRadialGradient(V2 centre, double radius, Rgba inner, Rgba outer);

    // convenience used constantly by the art
    void DrawLine(V2 a, V2 b);
}

/// <summary>
/// A segment of a leg in body-local units: hip just inside the body, knee, foot on the ledge.
/// </summary>
public struct LegPose
{
    public V2 Hip;
    public V2 Knee;
    public V2 Foot;
    public double Lift;      // 0 planted, 1 fully raised

    /// <summary>Optional depth for the "legs in the round" system (unused by classic).</summary>
    public double HipZ, KneeZ, FootZ;

    public LegPose(V2 hip, V2 knee, V2 foot, double lift = 0)
    {
        Hip = hip; Knee = knee; Foot = foot; Lift = lift;
        HipZ = KneeZ = FootZ = 0;
    }

    /// <summary>The foot lifted off the ground by `lift` units for drawing and stepping.</summary>
    public V2 RaisedFoot(double ground) => new(Foot.X, Foot.Y + Lift * 4);

    public LegPose LerpTo(LegPose o, double t) => new(
        V2.Lerp(Hip, o.Hip, t), V2.Lerp(Knee, o.Knee, t), V2.Lerp(Foot, o.Foot, t), M.Lerp(Lift, o.Lift, t));
}

/// <summary>A particle of weather on the spider (spec 3.8).</summary>
public struct Speck
{
    public V2 Pos;
    public V2 Vel;
    public double Life;
    public double MaxLife;
    public double Gravity;
    public double FloorY;
    public SpeckKind Kind;
    public double Size;
    public double Spread;
}

public enum SpeckKind { Water, Snow, Sand, Hail, Ring }

/// <summary>
/// Everything the renderer needs to draw one frame of the spider (spec 3.5).
/// Kept as a class so it can be handed to the background rasteriser without copying 8 leg poses
/// per frame; the rasteriser only reads it.
/// </summary>
public sealed class SpiderPose
{
    public V2 Pos;
    public double Heading;          // radians, body frame +x
    public double Facing = 1;       // +1 / −1, animated through 0 during a turn
    public double Spin;             // roll (ball phase)
    public double Ball;             // 0…1 balled up
    public double Grounded = 1;     // 1 on a surface, 0 in the air
    public double Scale = 0.78;

    public double Stretch = 1;      // along the body
    public double Fatten = 1;       // vertical, pivoting on the feet
    public double Lift;             // height of the body above the ledge, along the surface normal

    public readonly LegPose[] Legs = new LegPose[8];

    public V2 Look;                 // screen-space gaze direction
    public double Blink;            // 0 open … 1 closed
    public double Lid;              // heavy eyelids
    public double Happy;            // 0…1
    public double Startled;         // 0…1
    public double Sleep;            // 0…1
    public double AbdomenSway;

    public double EmoteT;           // 0…1 through its time
    public double EmoteClock;       // never held back (looping Z's, drifting hearts)
    public EmoteKind Emote;
    public ThoughtKind Thought;
    public string? ThoughtText;

    public double Time;
    public double Grabbed;          // 0…1
    public double NameTag;          // opacity
    public string? Name;
    public double Odometer;         // distance walked in body units (drives the propeller hat)

    public double BodyPitch;
    public V2 BodyShift;
    public double Chew;
    public double HeadTilt;
    public double HeadCock;
    public double Wink;
    public double PalpNear;
    public double PalpFar;
    public double HeadTurn;
    public double AbdomenTilt;

    public List<Rect> HiddenBy = new();
    public List<V2> PeekGrip = new();

    public double Wet, Snow, Dust, Chill;
    public List<Speck> Specks = new();

    public Rgba Surroundings = new(0.2, 0.2, 0.22, 1);
    public double Grounded01 => Grounded;

    public SpiderPose Clone()
    {
        var p = (SpiderPose)MemberwiseClone();
        Array.Copy(Legs, p.Legs, 8);
        p.HiddenBy = new List<Rect>(HiddenBy);
        p.PeekGrip = new List<V2>(PeekGrip);
        p.Specks = new List<Speck>(Specks);
        return p;
    }

    public override string ToString() => $"Pose({Pos}, head {Heading:0.00}, facing {Facing:0.00}, s{Scale})";
}

public enum EmoteKind
{
    None, Heart, Zzz, Surprise, Sparkle, Question, Note, Exclaim, Charge, Thought
}

public enum ThoughtKind
{
    None, Heart, Hungry, Rain, Sun, Moon, Music, Star, Bug, Home, Snow, Wind, Storm, Rainbow, Text, Dots
}
