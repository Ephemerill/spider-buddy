using System.Text.Json;
using System.Text.Json.Serialization;

namespace SpiderBuddy.Core;

// ============================================================================================
// The option library (spec 3.6). Labels are user-visible; keep them.
// ============================================================================================

public enum BodyShape
{
    Classic = 0, Round, Plump, Slim, Peanut, Chonk, Tall, Pear, BigHead, Bean, Petite, Custom
}

public enum EyeStyle
{
    Classic = 0, Huge, Beady, Sleepy, Wide, Sparkly, Oval, CrossEyed, Wink, Glowing, Dizzy,
    HeartEyes, Button, Custom
}

public enum BrowStyle { None = 0, Soft, Arched, Stern, Worried, Unibrow, Thick, Quizzical, Bushy, Flat }

public enum FangStyle { Fangs = 0, Tusks, Emerald, Smile, Blep, Grin, BuckTeeth, Chelicerae, Pout, FangsSmall, FangsBig }

public enum LegStyle
{
    Classic = 0, Slender, Chunky, Stubby, Long, Fuzzy, Banded, Socks, Spindly, Boots, Robot,
    Knobbly, Striped, Custom
}

public enum HatStyle
{
    None = 0, TopHat, PartyHat, Crown, Beanie, Flower, Bow, Cap, Halo, Wizard, Propeller, Cowboy,
    Chef, Bucket, Viking, Tiara, Pirate, Mushroom, Sombrero, Fez, Beret, Bowler, Santa, Mortarboard,
    BunnyEars, CatEars, Antlers, HardHat, Sailor, Jester, Horns, Unicorn, Ushanka, Pumpkin,
    Strawberry, Sweatband, FlowerCrown, LittleBird
}

public enum AccessoryStyle
{
    None = 0, Glasses, Monocle, Shades, HeartShades, Goggles, EyePatch, HeroMask, ClownNose, Moustache,
    Beard, BowTie, Necktie, Scarf, Bandana, BellCollar, Pearls, Medal, FlowerLei, Headphones, Sweater,
    Tutu, Backpack, Satchel, Bindle, Jetpack, Balloon, Cape, FairyWings, BatWings
}

public enum CoatStyle
{
    // 30 flat
    None = 0, Espresso, Amber, Rust, Copper, Cream, Sand, Olive, Moss, Forest, Teal, Sky, Navy,
    Violet, Plum, Rose, Blush, Cherry, Coral, Butter, Lemon, Lilac, Slate, Graphite, Ink, Snow,
    Ash, Taupe, Desert, Clay, Pistachio,
    // 16 gradient
    Sunset, Dawn, Meadow, Reef, Ember, Twilight, Mint, Peach, Storm, Candy, Forest2, Ice, Wine,
    Lagoon, Gold, Nebula,
    // 15 living
    Rainbow, Lava, Camouflage, Galaxy, Ocean, Aurora, Disco, Fire, Frost, Toxic, Pearl, CandyCane,
    Thunderstorm, Chrome, WebSlinger,
    // special
    Custom, DebugLegs
}

public enum PatternStyle
{
    None = 0, Stripe, Spots, Chevron, Heart, Star, Skull, Moon, Flower, Eyespots, Hourglass, Tiger,
    Leopard, Checker, Lightning, Speckle, Marble, Zigzag, Diamonds, Rings
}

public enum FuzzLevel { Sleek = 0, Normal, VeryFuzzy }

public enum GaitStyle { Normal = 0, Bouncy, Tiptoe, Lumber }
public enum GaitPreference { Mixed = 0, Steady, Bouncy, Tiptoe, Lumbering, Scurrying }
public enum LegMotion { Classic = 0, Natural, Refined }

public enum Temperament { Custom = 0, Friendly, Shy, Hyper, Lazy, Curious, ShowOff, Chill, Grumpy }

// ============================================================================================
// Personality, gait, habits (spec 6.1, 6.4, 4.5)
// ============================================================================================

/// <summary>Six 0…1 sliders. Order matters: energy, curiosity, bravery, playfulness, affection, laziness.</summary>
public sealed class Personality
{
    public double Energy = 0.55;
    public double Curiosity = 0.7;
    public double Bravery = 0.6;
    public double Playfulness = 0.55;
    public double Affection = 0.85;
    public double Laziness = 0.25;

    public Personality Clone() => (Personality)MemberwiseClone();

    public static Personality Preset(Temperament t) => t switch
    {
        Temperament.Friendly => new() { Energy = .55, Curiosity = .7, Bravery = .6, Playfulness = .55, Affection = .85, Laziness = .25 },
        Temperament.Shy => new() { Energy = .4, Curiosity = .35, Bravery = .15, Playfulness = .3, Affection = .4, Laziness = .35 },
        Temperament.Hyper => new() { Energy = .95, Curiosity = .7, Bravery = .7, Playfulness = .9, Affection = .6, Laziness = .05 },
        Temperament.Lazy => new() { Energy = .2, Curiosity = .3, Bravery = .6, Playfulness = .2, Affection = .5, Laziness = .9 },
        Temperament.Curious => new() { Energy = .6, Curiosity = .95, Bravery = .55, Playfulness = .45, Affection = .5, Laziness = .2 },
        Temperament.ShowOff => new() { Energy = .7, Curiosity = .5, Bravery = .85, Playfulness = .95, Affection = .7, Laziness = .1 },
        Temperament.Chill => new() { Energy = .35, Curiosity = .45, Bravery = .75, Playfulness = .35, Affection = .55, Laziness = .5 },
        Temperament.Grumpy => new() { Energy = .45, Curiosity = .3, Bravery = .9, Playfulness = .1, Affection = .15, Laziness = .45 },
        _ => new Personality()
    };

    public static Personality Random(Rng rng) => new()
    {
        Energy = rng.Range(0.15, 0.95),
        Curiosity = rng.Range(0.1, 1.0),
        Bravery = rng.Range(0.1, 1.0),
        Playfulness = rng.Range(0.1, 1.0),
        Affection = rng.Range(0.1, 1.0),
        Laziness = rng.Range(0.0, 0.85)
    };

    /// <summary>The derived multipliers every draw uses (spec 6.1).</summary>
    public double Play(double chill, double drowsy) => M.Lerp(0.25, 2.2, Playfulness) * chill * M.Lerp(1, 0.5, drowsy);
    public double Love => M.Lerp(0.2, 2.2, Affection);
    public double Lazy(double chill, double drowsy) => M.Lerp(0.3, 2.4, Laziness) / chill * M.Lerp(1, 2, drowsy);
    public double Busy(double chill, double drowsy) => M.Lerp(0.5, 1.6, Energy) * chill * M.Lerp(1, 0.55, drowsy);
    public double Liveliness => M.Lerp(0.45, 2.4, Energy);
}

/// <summary>Gait dials (spec 4.5). All 0…1.</summary>
public sealed class GaitConfig
{
    public GaitPreference Preference = GaitPreference.Mixed;
    public double Pace = 0.5;
    public double Stride = 0.5;
    public double Bounce = 0.5;
    public double Stance = 0.5;
    public double Bounciness = 0.4;
    public LegMotion Motion = LegMotion.Classic;
    public bool NewLegs;

    public GaitConfig Clone() => (GaitConfig)MemberwiseClone();

    /// <summary>strideLength 28 units per cycle, scaled by the stride dial and the style (spec 4.5).</summary>
    [JsonIgnore]
    public double StrideLength => 28 * M.Lerp(0.82, 1.22, Stride);
}

/// <summary>
/// The ~30 habit dials (spec 6.4), all 0…1 with 0.5 = as usual.
/// Tolerant decoding is a HARD requirement (spec 1.5): a new dial must default when absent,
/// otherwise every older saved design silently resets.
/// </summary>
public sealed class Habits
{
    // getting about
    public double Wander = 0.5, Leap = 0.5, Rappel = 0.5, Swing = 0.5, Hammock = 0.5, Nap = 0.5, Sleep = 0.5;
    // antics
    public double Drum = 0.5, Dance = 0.5, DanceMusic = 0.5, Roll = 0.5, Spin = 0.5, Pushup = 0.5,
        Stretch = 0.5, Wiggle = 0.5, ArmsUp = 0.5;
    // quiet moments
    public double Look = 0.5, Rest = 0.5, Groom = 0.5, Fidget = 0.5, Scratch = 0.5, Peer = 0.5, Muse = 0.5;
    // with you
    public double Approach = 0.5, Curious = 0.5, Stare = 0.5, Glance = 0.5, WalkTurned = 0.3,
        Greet = 0.5, Wave = 0.5, Peekaboo = 0.5;

    /// <summary>
    /// Habit → weight multiplier (spec 6.1): v ≥ 0.995 means "every chance it gets" (100 000),
    /// v ≤ 0.5 is max(0, 2v) (0 = never, 0.5 = as usual), otherwise 400^((v−0.5)·2).
    /// </summary>
    public static double Weight(double v)
    {
        if (v >= 0.995) return 100_000;
        if (v <= 0.5) return Math.Max(0, 2 * v);
        return Math.Pow(400, (v - 0.5) * 2);
    }

    public Habits Clone() => (Habits)MemberwiseClone();

    /// <summary>Every dial as (name, value) in the Studio's order — used by the Habits tab and tests.</summary>
    [JsonIgnore]
    public IReadOnlyList<(string name, Func<double> get, Action<double> set)> Dials => new List<(string, Func<double>, Action<double>)>
    {
        ("Wandering", () => Wander, v => Wander = v), ("Leaping between windows", () => Leap, v => Leap = v),
        ("Dropping on a thread", () => Rappel, v => Rappel = v), ("Swinging on a line", () => Swing, v => Swing = v),
        ("Building a hammock", () => Hammock, v => Hammock = v), ("Napping in the hammock", () => Nap, v => Nap = v),
        ("Nodding off", () => Sleep, v => Sleep = v),
        ("Drumming", () => Drum, v => Drum = v), ("Dancing", () => Dance, v => Dance = v),
        ("Dancing to music", () => DanceMusic, v => DanceMusic = v), ("Rolling over", () => Roll, v => Roll = v),
        ("Spinning", () => Spin, v => Spin = v), ("Push-ups", () => Pushup, v => Pushup = v),
        ("Stretching", () => Stretch, v => Stretch = v), ("Wiggling", () => Wiggle, v => Wiggle = v),
        ("Arms up", () => ArmsUp, v => ArmsUp = v),
        ("Looking about", () => Look, v => Look = v), ("Resting", () => Rest, v => Rest = v),
        ("Grooming", () => Groom, v => Groom = v), ("Fidgeting", () => Fidget, v => Fidget = v),
        ("Scratching", () => Scratch, v => Scratch = v), ("Peering", () => Peer, v => Peer = v),
        ("Thinking", () => Muse, v => Muse = v),
        ("Coming to see the pointer", () => Approach, v => Approach = v), ("Craning at it", () => Curious, v => Curious = v),
        ("Staring", () => Stare, v => Stare = v), ("Glancing", () => Glance, v => Glance = v),
        ("Walking turned toward you", () => WalkTurned, v => WalkTurned = v), ("Greeting", () => Greet, v => Greet = v),
        ("Waving", () => Wave, v => Wave = v), ("Peek-a-boo", () => Peekaboo, v => Peekaboo = v),
    };
}

// ============================================================================================
// Look and Design
// ============================================================================================

/// <summary>What the Studio edits (spec 3.6). Every field decodes with a default.</summary>
public sealed class SpiderLook
{
    public BodyShape Body = BodyShape.Classic;
    public EyeStyle Eyes = EyeStyle.Classic;
    public BrowStyle Brows = BrowStyle.None;
    public FangStyle Fangs = FangStyle.Fangs;
    public LegStyle Legs = LegStyle.Classic;
    public PatternStyle Pattern = PatternStyle.None;
    public CoatStyle Coat = CoatStyle.None;
    public CoatStyle Gradient = CoatStyle.None;
    public bool Living;
    public Rgba CustomBody = new(0.878, 0.604, 0.333);
    public Rgba CustomLeg = new(0.788, 0.518, 0.278);
    public bool Shimmer;
    public double[] BodyTune = { 1, 1, 1 };
    public double[] EyeTune = { 1, 1, 1 };
    public double[] LegTune = { 1, 1, 1 };
    public Rgba Accent = new(0.298, 0.180, 0.086);
    public Rgba? CustomAccent;
    public bool CamoMarkings;
    public HatStyle Hat = HatStyle.None;
    public AccessoryStyle Accessory = AccessoryStyle.None;
    public FuzzLevel Fuzz = FuzzLevel.Normal;
    public bool FaceOverLegs;

    public SpiderLook Clone()
    {
        var l = (SpiderLook)MemberwiseClone();
        l.BodyTune = (double[])BodyTune.Clone();
        l.EyeTune = (double[])EyeTune.Clone();
        l.LegTune = (double[])LegTune.Clone();
        return l;
    }

    /// <summary>Body-shape multipliers (abdomen rx, abdomen ry, head) — spec 3.6.</summary>
    [JsonIgnore]
    public V3 ShapeMultipliers => Body switch
    {
        BodyShape.Classic => new V3(1.0, 1.0, 1.0),
        BodyShape.Round => new V3(1.08, 1.1, 1.04),
        BodyShape.Plump => new V3(1.22, 1.16, 0.96),
        BodyShape.Slim => new V3(0.95, 0.82, 0.92),
        BodyShape.Peanut => new V3(0.82, 0.86, 1.1),
        BodyShape.Chonk => new V3(1.3, 1.26, 1.12),
        BodyShape.Tall => new V3(0.9, 1.18, 1.0),
        BodyShape.Pear => new V3(1.12, 1.3, 0.8),
        BodyShape.BigHead => new V3(0.82, 0.84, 1.3),
        BodyShape.Bean => new V3(1.28, 0.78, 0.88),
        BodyShape.Petite => new V3(0.84, 0.84, 0.86),
        _ => new V3(M.Clamp(BodyTune[0], 0.6, 1.6), M.Clamp(BodyTune[1], 0.6, 1.6), M.Clamp(BodyTune[2], 0.6, 1.6))
    };

    /// <summary>Eye-size multiplier per style (spec 3.6).</summary>
    [JsonIgnore]
    public double EyeScale => Eyes switch
    {
        EyeStyle.Huge => 1.22,
        EyeStyle.Beady => 0.7,
        EyeStyle.Wide => 1.08,
        EyeStyle.Button => 1.1,
        EyeStyle.Custom => M.Clamp(EyeTune[0], 0.4, 2),
        _ => 1.0
    };

    /// <summary>Leg rig per style: reach multiplies foot-x and knee offset; knee adds rise; width is the stroke.</summary>
    [JsonIgnore]
    public (double reach, double knee, double width) LegRig => Legs switch
    {
        LegStyle.Slender => (1.0, 0.6, 0.75),
        LegStyle.Chunky => (0.94, 0.8, 1.55),
        LegStyle.Stubby => (0.72, 0.5, 1.25),
        LegStyle.Long => (1.22, 1.15, 0.9),
        LegStyle.Fuzzy => (1.0, 0.9, 1.2),
        LegStyle.Banded => (1.0, 0.9, 1.0),
        LegStyle.Socks => (1.0, 0.9, 1.05),
        LegStyle.Spindly => (1.12, 1.1, 0.6),
        LegStyle.Boots => (0.98, 0.85, 1.35),
        LegStyle.Robot => (1.02, 0.95, 1.3),
        LegStyle.Knobbly => (0.96, 0.95, 1.15),
        LegStyle.Striped => (1.0, 0.9, 1.0),
        LegStyle.Custom => (M.Clamp(LegTune[0], 0.5, 1.5), M.Clamp(LegTune[1], 0.5, 1.6), M.Clamp(LegTune[2], 0.5, 1.8)),
        _ => (1.0, 0.9, 1.0)
    };

    /// <summary>Whether this look is lopsided — lopsided outfits keep the head on the legs' side (3.6).</summary>
    [JsonIgnore]
    public bool FaceOnSymmetric =>
        Hat is HatStyle.None or HatStyle.Crown or HatStyle.Halo or HatStyle.PartyHat or HatStyle.Tiara
            or HatStyle.FlowerCrown or HatStyle.Antlers or HatStyle.BunnyEars or HatStyle.CatEars
            or HatStyle.Horns or HatStyle.Mortarboard
        && Accessory is AccessoryStyle.None or AccessoryStyle.Glasses or AccessoryStyle.Shades
            or AccessoryStyle.Goggles or AccessoryStyle.BowTie or AccessoryStyle.Necktie
            or AccessoryStyle.Pearls or AccessoryStyle.BellCollar or AccessoryStyle.Cape
            or AccessoryStyle.FairyWings or AccessoryStyle.BatWings
        && Eyes != EyeStyle.Wink && Brows != BrowStyle.Quizzical;
}

/// <summary>
/// The saved spider: look + personality + gait + habits + name + thoughts (spec 3.6).
/// Decoded tolerantly from JSON so older saves keep loading.
/// </summary>
public sealed class SpiderDesign
{
    public string Name = "";
    public SpiderLook Look = new();
    public Personality Personality = new();
    public GaitConfig Gait = new();
    public Habits Habits = new();
    public List<string> Packs = new() { "chitchat" };
    public List<string> CustomPhrases = new();
    public bool VoicePictures = true;
    public bool Intelligence;
    public string Manner = "";

    public SpiderDesign Clone() => new()
    {
        Name = Name,
        Look = Look.Clone(),
        Personality = Personality.Clone(),
        Gait = Gait.Clone(),
        Habits = Habits.Clone(),
        Packs = new List<string>(Packs),
        CustomPhrases = new List<string>(CustomPhrases),
        VoicePictures = VoicePictures,
        Intelligence = Intelligence,
        Manner = Manner
    };

    // The design is a field-based record in the Swift, so fields must be included both ways.
    static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = false,
        IncludeFields = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
        NumberHandling = JsonNumberHandling.AllowNamedFloatingPointLiterals
    };

    public string ToJson() => JsonSerializer.Serialize(this, JsonOpts);

    /// <summary>Tolerant decode: any failure or missing field yields a default, never an exception.</summary>
    public static SpiderDesign FromJson(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new SpiderDesign();
        try
        {
            var d = JsonSerializer.Deserialize<SpiderDesign>(json, new JsonSerializerOptions
            {
                IncludeFields = true,
                NumberHandling = JsonNumberHandling.AllowNamedFloatingPointLiterals,
                PropertyNameCaseInsensitive = true
            });
            return d ?? new SpiderDesign();
        }
        catch
        {
            return new SpiderDesign();
        }
    }

    /// <summary>A random look with no name/packs/phrases and no living coats (visitors — spec 15.2).</summary>
    public static SpiderDesign Random(Rng rng, bool allowLiving = true)
    {
        var d = new SpiderDesign
        {
            Look = new SpiderLook
            {
                Body = (BodyShape)rng.RangeInt(0, 12),
                Eyes = (EyeStyle)rng.RangeInt(0, 14),
                Brows = (BrowStyle)rng.RangeInt(0, 10),
                Fangs = (FangStyle)rng.RangeInt(0, 11),
                Legs = (LegStyle)rng.RangeInt(0, 14),
                Pattern = (PatternStyle)rng.RangeInt(0, 20),
                Coat = (CoatStyle)rng.RangeInt(0, 31),
                Hat = (HatStyle)rng.RangeInt(0, 38),
                Accessory = (AccessoryStyle)rng.RangeInt(0, 30),
                Fuzz = (FuzzLevel)rng.RangeInt(0, 3),
                Accent = new Rgba(rng.Range(0.1, 0.5), rng.Range(0.1, 0.5), rng.Range(0.1, 0.5))
            },
            Personality = Personality.Random(rng)
        };
        if (allowLiving && rng.Chance(0.25)) d.Look.Living = true;
        d.Gait.Preference = (GaitPreference)rng.RangeInt(0, 6);
        return d;
    }
}
