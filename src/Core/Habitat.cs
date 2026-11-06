using System.Text.Json;
using System.Text.Json.Nodes;

namespace SpiderBuddy.Core;

public enum HabitatBiome { Forest, Jungle, Desert, Meadow, Cave, Beach, Tundra, Moonlit, Empty }

public static class HabitatBiomes
{
    public static readonly HabitatBiome[] All =
        { HabitatBiome.Forest, HabitatBiome.Jungle, HabitatBiome.Desert, HabitatBiome.Meadow,
          HabitatBiome.Cave, HabitatBiome.Beach, HabitatBiome.Tundra, HabitatBiome.Moonlit };

    public static string Label(this HabitatBiome b) => b switch
    {
        HabitatBiome.Forest => "Forest", HabitatBiome.Jungle => "Jungle", HabitatBiome.Desert => "Desert",
        HabitatBiome.Meadow => "Meadow", HabitatBiome.Cave => "Cave", HabitatBiome.Beach => "Beach",
        HabitatBiome.Tundra => "Snowfall", HabitatBiome.Moonlit => "Moonlit", _ => "Empty"
    };

    public static string Blurb(this HabitatBiome b) => b switch
    {
        HabitatBiome.Forest => "Pines, sunbeams and falling leaves",
        HabitatBiome.Jungle => "Mist, vines and butterflies",
        HabitatBiome.Desert => "Dunes, heat and drifting sand",
        HabitatBiome.Meadow => "Clouds, long grass and pollen",
        HabitatBiome.Cave => "Glowing crystals and drips",
        HabitatBiome.Beach => "Waves, gulls and sea sparkle",
        HabitatBiome.Tundra => "Snow under the northern lights",
        HabitatBiome.Moonlit => "Stars, moonlight and fireflies",
        _ => "A bare tank"
    };

    public static string SaveName(this HabitatBiome b) => b == HabitatBiome.Moonlit ? "night" : b.ToString().ToLowerInvariant();

    public static HabitatBiome Parse(string? s, HabitatBiome fallback = HabitatBiome.Forest)
    {
        if (string.IsNullOrWhiteSpace(s)) return fallback;
        var q = new string(s.Where(char.IsLetter).ToArray()).ToLowerInvariant();
        return q switch
        {
            "forest" => HabitatBiome.Forest, "jungle" => HabitatBiome.Jungle, "desert" => HabitatBiome.Desert,
            "meadow" => HabitatBiome.Meadow, "cave" => HabitatBiome.Cave, "beach" => HabitatBiome.Beach,
            "tundra" or "snowfall" => HabitatBiome.Tundra, "night" or "moonlit" => HabitatBiome.Moonlit,
            "empty" or "bare" => HabitatBiome.Empty, _ => fallback
        };
    }
}

public enum HabitatCategory { Perch, Scenery }
public enum HabitatPlacement { Ground, Rests, Wedged, Hangs }
public enum HabitatLayer { Normal, Rear }
public enum HabitatMount { None, Wall }
public enum HabitatStretch { None, Vertical, Horizontal, Both }
public enum HabitatSnow { Tops, Sprinkle, Bare }

public enum HabitatShelf
{
    Structures, Supports, Shelter, Plants, Ground, Details, Functional, Loose,
    Built, Building, Walls, Home, Decor
}

public static class HabitatShelves
{
    public static readonly HabitatShelf[] All = Enum.GetValues<HabitatShelf>();
    public static string Label(this HabitatShelf s) => s switch
    {
        HabitatShelf.Structures => "Structures", HabitatShelf.Supports => "Supports",
        HabitatShelf.Shelter => "Shelter", HabitatShelf.Plants => "Plants", HabitatShelf.Ground => "Ground",
        HabitatShelf.Details => "Details", HabitatShelf.Functional => "Functional", HabitatShelf.Loose => "Loose",
        HabitatShelf.Built => "Built", HabitatShelf.Building => "Building", HabitatShelf.Walls => "Backing",
        HabitatShelf.Home => "Home", _ => "Decor"
    };
    public static string Heading(this HabitatShelf s) => s switch
    {
        HabitatShelf.Structures => "Structures — branches, roots, bark, rock",
        HabitatShelf.Supports => "Supports — fixed to the back wall",
        HabitatShelf.Shelter => "Shelter — covered places to get into",
        HabitatShelf.Plants => "Plants", HabitatShelf.Ground => "Ground", HabitatShelf.Details => "Natural details",
        HabitatShelf.Functional => "Functional — water, food, warmth, a view",
        HabitatShelf.Loose => "Loose objects — light enough to blow about",
        HabitatShelf.Built => "Built — timber, board and brick",
        HabitatShelf.Building => "Building — floors, walls, doors, a roof",
        HabitatShelf.Walls => "Backing — the back walls of rooms",
        HabitatShelf.Home => "Home — furniture", _ => "Decor — little things, and for the walls"
    };
    public static bool Natural(this HabitatShelf s) =>
        s is not (HabitatShelf.Supports or HabitatShelf.Built or HabitatShelf.Building or HabitatShelf.Walls
            or HabitatShelf.Home or HabitatShelf.Decor);
}

public enum HabitatMaterial { Wood, Bark, Root, Driftwood, Bamboo, Stem, Leaf, Moss, Fungus, Stone, Crystal, Sand, Soil, Water, Shell, Seed, Feather, Made }
public enum HabitatFunction { Water, Feeding, Basking, Lookout, Silk, Climbing, Humid, Cover, Retreat }

public enum HabitatQuality
{
    Climbable, Perchable, Sheltering, Hideable, Drinkable, Wet, Movable, Lightweight, Flexible, Hanging,
    Enclosed, Elevated, Warm, Cool, Exposed, Covered, Organic, Artificial, PreyAttracting, SilkAnchor,
    SleepingSuitable, LookoutSuitable, HuntingSuitable, MoistureSource, Interesting, Glowing, Moving
}

public sealed class HabitatQualities
{
    public const int Count = 27;
    readonly double[] _v = new double[Count];
    public double this[HabitatQuality q] { get => _v[(int)q]; set => _v[(int)q] = M.Clamp01(value); }
    public bool Has(HabitatQuality q, double atLeast = 0.5) => this[q] >= atLeast;
    public void Raise(HabitatQuality q, double x) { if (x > this[q]) this[q] = x; }
    public IEnumerable<(HabitatQuality quality, double amount)> Present =>
        Enum.GetValues<HabitatQuality>().Where(q => this[q] > 0.05).Select(q => (q, this[q])).OrderByDescending(x => x.Item2);
    public override string ToString() => string.Join(", ", Present.Select(x => $"{x.quality} {x.amount:0.##}"));
}

public enum LooseMotion { Flutter, Spin, Roll, Tumble, Slide }

public sealed class LooseBody
{
    public LooseMotion Motion;
    public double Mass, Drag, WindCatch, Bounce, Friction;
    public bool Pushable => Mass < 3;
}

public sealed class HabitatTraits
{
    public HabitatMaterial Material = HabitatMaterial.Made;
    public HashSet<HabitatBiome> Suits = new();
    public HashSet<HabitatMaterial> NicheOn = new();
    public bool NicheSide, Damp;
    public HashSet<HabitatFunction> Functions = new();
    public LooseBody? Loose;
    public string Aka = "";
    public Dictionary<HabitatQuality, double> Extra = new();
}

/// <summary>Everything about a kind of thing but its picture (Swift HabitatObjectDefinition).</summary>
public sealed class HabitatObjectDefinition
{
    public HabitatItemKind Kind;
    public string Label;
    public HabitatCategory Category;
    public double Width, Height;
    public HabitatPlacement Placement;
    public HabitatShelf Shelf;
    public HabitatLayer Layer;
    public HabitatMount Mount;
    public HabitatStretch Stretch;
    public double Sway, WindLean, Shadow;
    public HabitatSnow Snow;
    public double SnowDepth;
    public string Note;

    public HabitatObjectDefinition(HabitatItemKind kind, string label, HabitatCategory category, double w, double h,
        HabitatPlacement placement, HabitatShelf shelf, HabitatLayer layer, HabitatMount mount,
        HabitatStretch stretch, double sway, double windLean, double shadow, HabitatSnow snow, double snowDepth, string note)
    {
        Kind = kind; Label = label; Category = category; Width = w; Height = h; Placement = placement;
        Shelf = shelf; Layer = layer; Mount = mount; Stretch = stretch; Sway = sway; WindLean = windLean;
        Shadow = shadow; Snow = snow; SnowDepth = snowDepth; Note = note;
    }

    public bool Climbable => Category == HabitatCategory.Perch;
    public bool Hangs => Placement == HabitatPlacement.Hangs;
    public bool CanGoInFront => !Climbable && Layer != HabitatLayer.Rear;
    public bool AtBack => Layer == HabitatLayer.Rear;
    public SizeD Size => new(Width, Height);
    public HabitatTraits Traits => HabitatCatalogTraits.For(Kind);
}

public readonly struct SizeD
{
    public readonly double Width, Height;
    public SizeD(double w, double h) { Width = w; Height = h; }
}

public static class HabitatCatalogTraits
{
    static readonly Dictionary<HabitatItemKind, HabitatTraits> Cache = new();
    static readonly object Gate = new();

    public static HabitatTraits For(HabitatItemKind kind)
    {
        lock (Gate)
        {
            if (Cache.TryGetValue(kind, out var t)) return t;
            t = Build(kind);
            Cache[kind] = t;
            return t;
        }
    }

    static HabitatTraits Build(HabitatItemKind kind)
    {
        var t = new HabitatTraits();
        var green = new[] { HabitatBiome.Forest, HabitatBiome.Jungle, HabitatBiome.Meadow, HabitatBiome.Moonlit };
        var woods = new[] { HabitatBiome.Forest, HabitatBiome.Jungle, HabitatBiome.Moonlit, HabitatBiome.Tundra };
        var dry = new[] { HabitatBiome.Desert, HabitatBiome.Beach };
        var stony = new[] { HabitatBiome.Desert, HabitatBiome.Cave, HabitatBiome.Beach, HabitatBiome.Tundra };
        void Set(HabitatMaterial m, IEnumerable<HabitatBiome>? suits = null, IEnumerable<HabitatMaterial>? on = null,
            bool side = false, bool damp = false, IEnumerable<HabitatFunction>? fn = null, LooseBody? loose = null,
            string aka = "", params (HabitatQuality q, double x)[] extra)
        {
            t.Material = m;
            if (suits is not null) foreach (var b in suits) t.Suits.Add(b);
            if (on is not null) foreach (var m2 in on) t.NicheOn.Add(m2);
            t.NicheSide = side; t.Damp = damp;
            if (fn is not null) foreach (var f in fn) t.Functions.Add(f);
            t.Loose = loose; t.Aka = aka;
            foreach (var e in extra) t.Extra[e.q] = e.x;
        }
        LooseBody L(LooseMotion m, double mass, double drag, double wind, double bounce, double friction) =>
            new() { Motion = m, Mass = mass, Drag = drag, WindCatch = wind, Bounce = bounce, Friction = friction };

        switch (kind)
        {
            case HabitatItemKind.Log: Set(HabitatMaterial.Wood, woods.Append(HabitatBiome.Meadow)); break;
            case HabitatItemKind.Hide: Set(HabitatMaterial.Wood, woods.Append(HabitatBiome.Meadow), aka: "hollow"); break;
            case HabitatItemKind.Branch: case HabitatItemKind.ThinBranch: case HabitatItemKind.MediumBranch:
            case HabitatItemKind.ThickBranch: case HabitatItemKind.ShortBranch: case HabitatItemKind.LongBranch:
            case HabitatItemKind.ForkedBranch: case HabitatItemKind.YBranch: case HabitatItemKind.CrookedBranch:
            case HabitatItemKind.Twig: case HabitatItemKind.TwistedBranch: case HabitatItemKind.ThreeFork:
                Set(HabitatMaterial.Wood, new[] { HabitatBiome.Forest, HabitatBiome.Jungle, HabitatBiome.Meadow, HabitatBiome.Moonlit, HabitatBiome.Tundra }); break;
            case HabitatItemKind.Driftwood: case HabitatItemKind.DriftwoodArch: case HabitatItemKind.DriftwoodSnag:
            case HabitatItemKind.DriftwoodRoot: case HabitatItemKind.DriftwoodBranch:
                Set(HabitatMaterial.Driftwood, dry); break;
            case HabitatItemKind.CorkBark: case HabitatItemKind.CorkTube: case HabitatItemKind.CorkSlab:
            case HabitatItemKind.BarkLedge: case HabitatItemKind.LeaningBark:
                Set(HabitatMaterial.Bark, woods.Append(HabitatBiome.Meadow)); break;
            case HabitatItemKind.Rock: case HabitatItemKind.Boulder: case HabitatItemKind.SlateLedge:
            case HabitatItemKind.RockSpire: case HabitatItemKind.StoneArch: case HabitatItemKind.BaskingStone:
            case HabitatItemKind.Pebbles: case HabitatItemKind.PebblePile:
            case HabitatItemKind.SmoothStones:
                Set(HabitatMaterial.Stone, kind is HabitatItemKind.Rock or HabitatItemKind.Boulder or HabitatItemKind.RockSpire ? null : stony); break;
            case HabitatItemKind.Bamboo: case HabitatItemKind.BambooPole: case HabitatItemKind.BambooSegment:
            case HabitatItemKind.BambooTipi: Set(HabitatMaterial.Bamboo, new[] { HabitatBiome.Jungle }); break;
            case HabitatItemKind.Cactus: Set(HabitatMaterial.Stem, new[] { HabitatBiome.Desert }); break;
            case HabitatItemKind.Plant: case HabitatItemKind.Fern: case HabitatItemKind.Grass:
            case HabitatItemKind.Flower: case HabitatItemKind.SmallFern: case HabitatItemKind.LargeFern:
            case HabitatItemKind.BroadLeaf: case HabitatItemKind.TrailingPlant: case HabitatItemKind.ClimbingVine:
            case HabitatItemKind.GrassClump: case HabitatItemKind.FloweringPlant: case HabitatItemKind.TinyFlowers:
            case HabitatItemKind.AirPlant: case HabitatItemKind.MiniPalm: case HabitatItemKind.DeadPlant:
            case HabitatItemKind.Fiddleheads: case HabitatItemKind.CreepingCover: case HabitatItemKind.HangingFoliage:
                Set(HabitatMaterial.Leaf, green); break;
            case HabitatItemKind.Vine: case HabitatItemKind.ThickVine: case HabitatItemKind.ThinVine:
            case HabitatItemKind.LianaLoop: Set(HabitatMaterial.Stem, new[] { HabitatBiome.Jungle, HabitatBiome.Forest, HabitatBiome.Moonlit, HabitatBiome.Cave }); break;
            case HabitatItemKind.WaterDish: Set(HabitatMaterial.Stone, fn: new[] { HabitatFunction.Water }, aka: "drink", extra: (HabitatQuality.Artificial, 1)); break;
            case HabitatItemKind.RockPool: Set(HabitatMaterial.Stone, damp: true, fn: new[] { HabitatFunction.Water }, aka: "drink"); break;
            case HabitatItemKind.Puddle: Set(HabitatMaterial.Water, new[] { HabitatBiome.Forest, HabitatBiome.Jungle, HabitatBiome.Meadow, HabitatBiome.Moonlit, HabitatBiome.Tundra, HabitatBiome.Cave }, damp: true, fn: new[] { HabitatFunction.Water }, aka: "drink"); break;
            case HabitatItemKind.Succulent: case HabitatItemKind.Aloe: case HabitatItemKind.JadePlant:
                Set(HabitatMaterial.Leaf, dry, aka: "succulent"); break;
            case HabitatItemKind.Lithops: Set(HabitatMaterial.Leaf, new[] { HabitatBiome.Desert }, aka: "succulent"); break;
            case HabitatItemKind.Mushrooms: case HabitatItemKind.Mushroom: case HabitatItemKind.MushroomCluster:
            case HabitatItemKind.TinyMushrooms: case HabitatItemKind.ShelfFungus:
                Set(HabitatMaterial.Fungus, new[] { HabitatBiome.Forest, HabitatBiome.Jungle, HabitatBiome.Moonlit, HabitatBiome.Cave },
                    on: new[] { HabitatMaterial.Wood, HabitatMaterial.Bark, HabitatMaterial.Soil, HabitatMaterial.Moss },
                    side: kind == HabitatItemKind.ShelfFungus, damp: true, aka: "toadstool"); break;
            case HabitatItemKind.GlowMushrooms: Set(HabitatMaterial.Fungus, new[] { HabitatBiome.Cave, HabitatBiome.Moonlit, HabitatBiome.Jungle }, damp: true, aka: "light", extra: (HabitatQuality.Glowing, 1)); break;
            case HabitatItemKind.Lichen: Set(HabitatMaterial.Fungus, new[] { HabitatBiome.Forest, HabitatBiome.Tundra, HabitatBiome.Moonlit, HabitatBiome.Meadow, HabitatBiome.Cave }, side: true); break;
            case HabitatItemKind.Moss: case HabitatItemKind.MossCushion: case HabitatItemKind.MoistMoss:
                Set(HabitatMaterial.Moss, new[] { HabitatBiome.Forest, HabitatBiome.Jungle, HabitatBiome.Moonlit, HabitatBiome.Tundra, HabitatBiome.Cave }, damp: true,
                    fn: kind == HabitatItemKind.MoistMoss ? new[] { HabitatFunction.Humid } : null); break;
            case HabitatItemKind.LeafPile: case HabitatItemKind.LeafHeap:
                Set(HabitatMaterial.Leaf, new[] { HabitatBiome.Forest, HabitatBiome.Moonlit, HabitatBiome.Meadow, HabitatBiome.Tundra }, aka: "litter"); break;
            case HabitatItemKind.Crystal: case HabitatItemKind.CrystalCluster:
                Set(HabitatMaterial.Crystal, new[] { HabitatBiome.Cave, HabitatBiome.Moonlit }, aka: "gem", extra: (HabitatQuality.Interesting, .7)); break;
            case HabitatItemKind.Root: case HabitatItemKind.ClimbingRoot: case HabitatItemKind.ExposedRoot:
            case HabitatItemKind.RootTangle: case HabitatItemKind.RootHollow: case HabitatItemKind.HangingRoots:
                Set(HabitatMaterial.Root, woods, fn: kind is HabitatItemKind.RootTangle or HabitatItemKind.RootHollow ? new[] { HabitatFunction.Cover, HabitatFunction.Retreat } : null); break;
            case HabitatItemKind.CorkTunnel: Set(HabitatMaterial.Bark, woods.Append(HabitatBiome.Meadow), fn: new[] { HabitatFunction.Cover, HabitatFunction.Retreat }, aka: "tube hide"); break;
            case HabitatItemKind.BarkCave: case HabitatItemKind.RockCrevice: case HabitatItemKind.LogDen:
            case HabitatItemKind.CurledLeafHide: case HabitatItemKind.MossyHide:
                Set(kind is HabitatItemKind.RockCrevice or HabitatItemKind.MossyHide ? HabitatMaterial.Stone : HabitatMaterial.Bark,
                    new[] { HabitatBiome.Forest, HabitatBiome.Jungle, HabitatBiome.Meadow, HabitatBiome.Moonlit, HabitatBiome.Cave },
                    fn: new[] { HabitatFunction.Cover, HabitatFunction.Retreat }, aka: "hide den"); break;
            case HabitatItemKind.LeafCanopy: case HabitatItemKind.HangingLeafShelter: case HabitatItemKind.Overhang:
            case HabitatItemKind.ShelterCanopy:
                Set(kind == HabitatItemKind.Overhang ? HabitatMaterial.Stone : HabitatMaterial.Leaf,
                    new[] { HabitatBiome.Forest, HabitatBiome.Jungle, HabitatBiome.Meadow, HabitatBiome.Moonlit },
                    fn: new[] { HabitatFunction.Cover }); break;
            case HabitatItemKind.Stump: Set(HabitatMaterial.Wood, woods.Append(HabitatBiome.Meadow), aka: "tree"); break;
            case HabitatItemKind.SandDrift: Set(HabitatMaterial.Sand, dry, aka: "dune"); break;
            case HabitatItemKind.Gravel: Set(HabitatMaterial.Stone, stony, aka: "grit"); break;
            case HabitatItemKind.PineNeedles: Set(HabitatMaterial.Leaf, new[] { HabitatBiome.Forest, HabitatBiome.Tundra, HabitatBiome.Moonlit }); break;
            case HabitatItemKind.Acorn: Set(HabitatMaterial.Seed, new[] { HabitatBiome.Forest, HabitatBiome.Meadow, HabitatBiome.Moonlit }, loose: L(LooseMotion.Roll, 3.5, .08, .05, .3, .35), aka: "nut"); break;
            case HabitatItemKind.PineCone: Set(HabitatMaterial.Seed, new[] { HabitatBiome.Forest, HabitatBiome.Tundra, HabitatBiome.Moonlit }, loose: L(LooseMotion.Roll, 8, .12, .04, .25, .5)); break;
            case HabitatItemKind.SeaShell: Set(HabitatMaterial.Shell, new[] { HabitatBiome.Beach }, aka: "conch"); break;
            case HabitatItemKind.FallenLeaf: case HabitatItemKind.DeadLeaf: case HabitatItemKind.LooseLeaf:
            case HabitatItemKind.Petal: case HabitatItemKind.Feather: case HabitatItemKind.Seed:
                Set(kind == HabitatItemKind.Feather ? HabitatMaterial.Feather : kind == HabitatItemKind.Seed ? HabitatMaterial.Seed : HabitatMaterial.Leaf,
                    green, loose: L(kind == HabitatItemKind.Seed ? LooseMotion.Spin : LooseMotion.Flutter,
                        kind == HabitatItemKind.Feather ? .1 : .3, .8, .8, .05, .55)); break;
            case HabitatItemKind.TinyTwig: Set(HabitatMaterial.Wood, loose: L(LooseMotion.Tumble, .4, .3, .3, .2, .7), aka: "stick"); break;
            case HabitatItemKind.SmallShell: Set(HabitatMaterial.Shell, new[] { HabitatBiome.Beach }, loose: L(LooseMotion.Slide, 1.2, .1, .1, .35, .5)); break;
            case HabitatItemKind.TinyPebble: Set(HabitatMaterial.Stone, loose: L(LooseMotion.Roll, 2, .05, .02, .3, .3), aka: "stone"); break;
            case HabitatItemKind.FeedingPlatform: Set(HabitatMaterial.Bark, fn: new[] { HabitatFunction.Feeding }, aka: "food"); break;
            case HabitatItemKind.Lookout: Set(HabitatMaterial.Driftwood, fn: new[] { HabitatFunction.Lookout }, aka: "high"); break;
            case HabitatItemKind.SilkFrame: Set(HabitatMaterial.Wood, fn: new[] { HabitatFunction.Silk }, aka: "web"); break;
            case HabitatItemKind.ClimbingBark: Set(HabitatMaterial.Bark, fn: new[] { HabitatFunction.Climbing }, aka: "wall"); break;
            case HabitatItemKind.Candle: case HabitatItemKind.Lantern: case HabitatItemKind.HangingLamp:
            case HabitatItemKind.FloorLamp: case HabitatItemKind.Sconce: case HabitatItemKind.Chandelier:
            case HabitatItemKind.StringLights:
                Set(HabitatMaterial.Made, extra: new[] { (HabitatQuality.Glowing, .9), (HabitatQuality.Warm, .35), (HabitatQuality.PreyAttracting, .6) }); break;
            case HabitatItemKind.Fireplace: Set(HabitatMaterial.Made, extra: new[] { (HabitatQuality.Glowing, .8), (HabitatQuality.Warm, 1.0) }); break;
            case HabitatItemKind.Stove: Set(HabitatMaterial.Made, extra: (HabitatQuality.Warm, .6)); break;
            case HabitatItemKind.Tv: Set(HabitatMaterial.Made, extra: new[] { (HabitatQuality.Glowing, .6), (HabitatQuality.Moving, .4), (HabitatQuality.Interesting, .7) }); break;
            case HabitatItemKind.Bed: case HabitatItemKind.BunkBed: case HabitatItemKind.Sofa:
            case HabitatItemKind.Armchair: case HabitatItemKind.Beanbag:
                Set(HabitatMaterial.Made, extra: (HabitatQuality.SleepingSuitable, .8)); break;
            case HabitatItemKind.FlyJar: Set(HabitatMaterial.Made, extra: new[] { (HabitatQuality.PreyAttracting, 1.0), (HabitatQuality.Interesting, .8) }); break;
            default:
                if (kind is HabitatItemKind.Beam or HabitatItemKind.Post or HabitatItemKind.Plank or HabitatItemKind.Plywood
                    or HabitatItemKind.Dowel or HabitatItemKind.Ladder or HabitatItemKind.Pipe or HabitatItemKind.Brick
                    or HabitatItemKind.WoodBlock or HabitatItemKind.Crate or HabitatItemKind.Rope or HabitatItemKind.BackPanel
                    or HabitatItemKind.Pegboard or HabitatItemKind.Floorboards or HabitatItemKind.Wall or HabitatItemKind.Door
                    or HabitatItemKind.DoorClosed or HabitatItemKind.Window or HabitatItemKind.WindowOpen
                    or HabitatItemKind.GableRoof or HabitatItemKind.Stairs or HabitatItemKind.KneeBrace or HabitatItemKind.Fence)
                    Set(HabitatMaterial.Made);
                else if (kind is HabitatItemKind.WoodBacking or HabitatItemKind.BrickBacking or HabitatItemKind.StoneBacking
                    or HabitatItemKind.LogBacking or HabitatItemKind.Wallpaper or HabitatItemKind.BackWindow)
                    Set(HabitatMaterial.Made, fn: new[] { HabitatFunction.Cover });
                else if (kind is HabitatItemKind.Brace or HabitatItemKind.BranchBracket or HabitatItemKind.WallAnchor
                    or HabitatItemKind.GlassMount or HabitatItemKind.SuctionCup or HabitatItemKind.VerticalSupport
                    or HabitatItemKind.HorizontalSupport or HabitatItemKind.CrossBrace or HabitatItemKind.HangingHook
                    or HabitatItemKind.VineClip or HabitatItemKind.ShelfBracket or HabitatItemKind.WallRail
                    or HabitatItemKind.MetalStrut or HabitatItemKind.AngleBracket or HabitatItemKind.Stake)
                    Set(HabitatMaterial.Wood);
                else Set(HabitatMaterial.Made);
                break;
        }
        return t;
    }
}

public static class HabitatKinds
{
    public static HabitatObjectDefinition Definition(this HabitatItemKind k) => HabitatCatalog.Definition(k);
    public static string Label(this HabitatItemKind k) => k.Definition().Label;
    public static SizeD DefaultSize(this HabitatItemKind k) => k.Definition().Size;
    public static bool Climbable(this HabitatItemKind k) => k.Definition().Climbable;
    public static bool Hangs(this HabitatItemKind k) => k.Definition().Hangs;
    public static bool CanGoInFront(this HabitatItemKind k) => k.Definition().CanGoInFront;
    public static bool AtBack(this HabitatItemKind k) => k.Definition().AtBack;
    public static bool IsBacking(this HabitatItemKind k) => k.Definition().Shelf == HabitatShelf.Walls;
    public static HabitatTraits Traits(this HabitatItemKind k) => HabitatCatalogTraits.For(k);
    public static HashSet<HabitatFunction> Functions(this HabitatItemKind k) => k.Traits().Functions;
    public static LooseBody? Loose(this HabitatItemKind k) => k.Traits().Loose;
    public static bool Suits(this HabitatItemKind k, HabitatBiome b) => k.Traits().Suits.Count == 0 || k.Traits().Suits.Contains(b);

    public static bool Matches(this HabitatItemKind k, string query)
    {
        var q = (query ?? "").Trim().ToLowerInvariant();
        if (q.Length == 0) return true;
        var d = k.Definition();
        var traits = k.Traits();
        var words = string.Join(" ", d.Label, d.Note, d.Shelf.Label(), traits.Aka,
            traits.Material.ToString().ToLowerInvariant(),
            string.Join(" ", traits.Functions.Select(f => f.ToString().ToLowerInvariant())),
            traits.Loose is null ? "" : "loose").ToLowerInvariant();
        return q.Split(' ', StringSplitOptions.RemoveEmptyEntries).All(words.Contains);
    }

    public static string SaveName(this HabitatItemKind k)
    {
        string n = k.ToString();
        return char.ToLowerInvariant(n[0]) + n[1..];
    }

    public static HabitatItemKind Parse(string? s, HabitatItemKind fallback = HabitatItemKind.Log)
    {
        if (string.IsNullOrWhiteSpace(s)) return fallback;
        var q = new string(s.Where(char.IsLetterOrDigit).ToArray()).ToLowerInvariant();
        foreach (var k in HabitatCatalog.All)
            if (new string(k.SaveName().Where(char.IsLetterOrDigit).ToArray()).ToLowerInvariant() == q) return k;
        if (int.TryParse(s, out int n) && n >= 0 && n < HabitatCatalog.All.Length) return (HabitatItemKind)n;
        return fallback;
    }
}

/// <summary>One thing in the tank (Swift HabitatItem).</summary>
public sealed class HabitatItem
{
    public int Id;
    public string Uid = Guid.NewGuid().ToString("D").ToUpperInvariant();
    public HabitatItemKind Kind = HabitatItemKind.Log;
    public double X, Y, W, H;
    public bool Flip;
    public int Seed;
    public bool Front;

    public HabitatObjectDefinition Definition => Kind.Definition();
    public SizeD DefaultSize => Kind.DefaultSize();
    public bool Hangs => Kind.Hangs();
    public bool OnGround => !Hangs && Y < 2;
    public bool InFront => Front && Kind.CanGoInFront();
    public double Unit => Math.Max(.5, Math.Min(W / Math.Max(1, Definition.Width), H / Math.Max(1, Definition.Height)));

    public Rect Rect => Hangs
        ? new Rect(X - W / 2, Y - H, W, H)
        : new Rect(X - W / 2, HabitatWorld.Ground + Y, W, H);

    /// <summary>Legacy drawing name: the world-space rectangle.</summary>
    public Rect Frame => Rect;

    public HabitatItem Clone() => (HabitatItem)MemberwiseClone();
    public override string ToString() => $"{Kind} {Id} {Uid} {Rect}";
}

public sealed class HabitatLink
{
    public string Child = "", ChildPort = "", Parent = "", ParentPort = "";
    public double At, ChildAt;
    public HabitatLink Clone() => (HabitatLink)MemberwiseClone();
}

public enum HabitatRegionKind { Thicket, Clearing, Canopy, Shelter, Pool, Rocks, Open }

public sealed class HabitatRegion
{
    public string Id = "";
    public HabitatRegionKind Kind;
    public Rect Rect;
    public List<int> Items = new();
    public string Label => Kind switch
    {
        HabitatRegionKind.Thicket => "Thicket", HabitatRegionKind.Clearing => "Clearing",
        HabitatRegionKind.Canopy => "Branches", HabitatRegionKind.Shelter => "Shelter",
        HabitatRegionKind.Pool => "Pool", HabitatRegionKind.Rocks => "Rocks", _ => "Open Ground"
    };
}

/// <summary>
/// The persistent habitat world (spec 17): a biome, furniture, a world larger than its window,
/// links, and the same saved key names as the macOS app.
/// </summary>
public sealed class HabitatWorld
{
    public const double Ground = 74;
    public const double LayoutWidth = 900;
    public const double LayoutHeight = 540;

    public string Name = "Forest Floor";
    public HabitatBiome Biome = HabitatBiome.Forest;
    public Rect Bounds = new(0, 0, 4042, 1242);
    public List<HabitatItem> Items = new();
    public List<HabitatLink> Links = new();
    public int NextId = 1;

    public double Width => Bounds.W;
    public double Height => Bounds.H;
    public double GroundY => Bounds.MinY + Ground;
    public Rect Air => new(Bounds.MinX, GroundY, Bounds.W, Bounds.H - Ground);

    public int NextOrder { get => NextId; set => NextId = value; }

    static double Clamp(double v, double lo, double hi) => v < lo ? lo : v > hi ? hi : v;

    public static SizeD WorldFor(double screenW, double screenH) =>
        new(Clamp(Math.Round(screenW * 2.75), 3000, 5600), Clamp(Math.Round(screenH * 1.35), 1050, 1600));

    public static Rect DefaultBounds()
    {
        var s = WorldFor(1470, 920);
        return new Rect(0, 0, s.Width, s.Height);
    }

    public void Clamp(HabitatItem it, Rect? bounds = null)
    {
        var b = bounds ?? Bounds;
        it.W = Math.Min(Math.Max(it.W, 12), b.W * .8);
        it.H = Math.Min(Math.Max(it.H, 10), Math.Max(10, (b.H - Ground) * .96));
        it.X = Math.Min(Math.Max(it.X, it.W * .2), b.W - it.W * .2);
        if (it.Hangs)
        {
            it.Y = Math.Min(Math.Max(it.Y, Ground + 40), b.H);
            it.H = Math.Max(10, Math.Min(it.H, it.Y - Ground - 10));
        }
        else
        {
            it.Y = Math.Min(Math.Max(it.Y, 0), b.H - Ground - it.H);
        }
    }

    public void ClampAll()
    {
        foreach (var it in Items) Clamp(it);
    }

    public HabitatItem? Item(int id) => Items.FirstOrDefault(i => i.Id == id);
    public HabitatItem? Item(string uid) => Items.FirstOrDefault(i => i.Uid == uid);

    public HabitatItem AddItem(HabitatItemKind kind, V2 at, double scale = 1, int? id = null, bool? flip = null, int? seed = null, bool front = false)
    {
        var d = kind.Definition();
        var item = new HabitatItem
        {
            Id = id ?? NextId++, Kind = kind, X = at.X, Y = d.Hangs ? at.Y : at.Y,
            W = d.Width * scale, H = d.Height * scale, Flip = flip ?? false, Seed = seed ?? 0, Front = front
        };
        if (d.Hangs && at.Y <= Ground + 1) item.Y = Bounds.H;
        Clamp(item);
        Items.Add(item);
        return item;
    }

    public static void Add(HabitatWorld w, HabitatItemKind kind, double x, double y, double width, double height)
    {
        var item = new HabitatItem
        {
            Id = w.NextId++, Kind = kind, X = x, Y = y, W = width, H = height,
            Seed = (int)((Math.Abs(x * 7919 + y * 104729) % 9998) + 1)
        };
        w.Clamp(item);
        w.Items.Add(item);
    }

    /// <summary>Legacy helper: drop a kind at a world point (at is the centre of its base/top).</summary>
    public HabitatItem AddAt(HabitatItemKind kind, V2 at)
    {
        var d = kind.Definition();
        var it = AddItem(kind, new V2(at.X, d.Hangs ? Bounds.H : Math.Max(0, at.Y - Ground)));
        return it;
    }

    public void Remove(HabitatItem it)
    {
        Items.Remove(it);
        Links.RemoveAll(l => l.Child == it.Uid || l.Parent == it.Uid);
    }

    public HabitatWorld Clone() => FromJson(ToJson()) ?? Empty(Bounds);

    public static HabitatWorld Empty(Rect? bounds = null) =>
        new() { Name = "Bare Tank", Biome = HabitatBiome.Empty, Bounds = bounds ?? DefaultBounds() };

    public static readonly string[] PresetNames =
    {
        "Forest Floor", "Jungle Canopy", "Desert Scrub", "Wildflower Meadow", "Crystal Cave",
        "Beachcomber", "Winter Hollow", "Moonlit Glade", "Bare Tank"
    };

    public static HabitatWorld Preset(int index, Rect? bounds = null)
    {
        var b = bounds ?? DefaultBounds();
        if (index == 8) return Empty(b);
        var biome = index switch
        {
            1 => HabitatBiome.Jungle, 2 => HabitatBiome.Desert, 3 => HabitatBiome.Meadow, 4 => HabitatBiome.Cave,
            5 => HabitatBiome.Beach, 6 => HabitatBiome.Tundra, 7 => HabitatBiome.Moonlit, _ => HabitatBiome.Forest
        };
        return BuildPreset(index, biome, b);
    }

    public static HabitatWorld Preset(HabitatBiome biome, Rect? bounds = null)
    {
        int index = biome switch
        {
            HabitatBiome.Jungle => 1, HabitatBiome.Desert => 2, HabitatBiome.Meadow => 3, HabitatBiome.Cave => 4,
            HabitatBiome.Beach => 5, HabitatBiome.Tundra => 6, HabitatBiome.Moonlit => 7, HabitatBiome.Empty => 8, _ => 0
        };
        return Preset(index, bounds);
    }

    static HabitatWorld BuildPreset(int p, HabitatBiome biome, Rect bounds)
    {
        var w = new HabitatWorld
        {
            Name = PresetNames[Math.Clamp(p, 0, 8)], Biome = biome, Bounds = bounds
        };
        var b = new LayoutBuilder(w, biome, (ulong)(p + 1) * 7919UL + 17);
        double mid = LayoutWidth;
        double x0 = Math.Round((w.Width - mid) / 2);
        foreach (var old in LegacyItems(p, bounds))
        {
            b.PutOld(old, x0);
        }
        b.Overhead(x0 + mid * .5);
        var sides = PresetSides(p);
        b.Fill(x0, 0, sides.left);
        b.Fill(x0 + mid, w.Width, sides.right);
        b.Dress();
        w.Name = PresetNames[Math.Clamp(p, 0, 8)];
        return w;
    }

    static (HabitatRegionKind[] left, HabitatRegionKind[] right) PresetSides(int p) => p switch
    {
        0 => (new[] { HabitatRegionKind.Thicket, HabitatRegionKind.Shelter, HabitatRegionKind.Canopy },
              new[] { HabitatRegionKind.Clearing, HabitatRegionKind.Canopy, HabitatRegionKind.Pool }),
        1 => (new[] { HabitatRegionKind.Pool, HabitatRegionKind.Thicket, HabitatRegionKind.Canopy },
              new[] { HabitatRegionKind.Thicket, HabitatRegionKind.Shelter, HabitatRegionKind.Canopy }),
        2 => (new[] { HabitatRegionKind.Clearing, HabitatRegionKind.Pool, HabitatRegionKind.Canopy },
              new[] { HabitatRegionKind.Thicket, HabitatRegionKind.Shelter, HabitatRegionKind.Rocks }),
        3 => (new[] { HabitatRegionKind.Clearing, HabitatRegionKind.Pool, HabitatRegionKind.Canopy },
              new[] { HabitatRegionKind.Thicket, HabitatRegionKind.Shelter, HabitatRegionKind.Canopy }),
        4 => (new[] { HabitatRegionKind.Pool, HabitatRegionKind.Rocks, HabitatRegionKind.Canopy },
              new[] { HabitatRegionKind.Shelter, HabitatRegionKind.Thicket, HabitatRegionKind.Rocks }),
        5 => (new[] { HabitatRegionKind.Pool, HabitatRegionKind.Clearing, HabitatRegionKind.Rocks },
              new[] { HabitatRegionKind.Rocks, HabitatRegionKind.Shelter, HabitatRegionKind.Canopy }),
        6 => (new[] { HabitatRegionKind.Clearing, HabitatRegionKind.Rocks, HabitatRegionKind.Canopy },
              new[] { HabitatRegionKind.Shelter, HabitatRegionKind.Thicket, HabitatRegionKind.Canopy }),
        7 => (new[] { HabitatRegionKind.Clearing, HabitatRegionKind.Thicket, HabitatRegionKind.Canopy },
              new[] { HabitatRegionKind.Pool, HabitatRegionKind.Shelter, HabitatRegionKind.Canopy }),
        _ => (Array.Empty<HabitatRegionKind>(), Array.Empty<HabitatRegionKind>())
    };

    static IEnumerable<HabitatItem> LegacyItems(int p, Rect b)
    {
        var list = new List<HabitatItem>();
        var w = new HabitatWorld { Bounds = new Rect(0, 0, LayoutWidth, LayoutHeight) };
        int seed = 11;
        void Put(HabitatItemKind k, double x, double y = 0, bool front = false, double scale = 1, bool flip = false)
        {
            var d = k.Definition();
            var it = new HabitatItem
            {
                Id = 0, Kind = k, X = x, Y = k.Hangs() && y == 0 ? LayoutHeight : y,
                W = d.Width * scale, H = d.Height * scale, Flip = flip, Front = front
            };
            seed = (seed * 7919 + 13) % 9973;
            it.Seed = seed + 1;
            w.Clamp(it, w.Bounds);
            list.Add(it);
        }
        switch (p)
        {
            case 0:
                Put(HabitatItemKind.CorkBark, 92, scale: 1.1); Put(HabitatItemKind.Branch, 560, 26, scale: 1.1);
                Put(HabitatItemKind.Log, 330, scale: 1.15); Put(HabitatItemKind.Rock, 470);
                Put(HabitatItemKind.Plant, 770); Put(HabitatItemKind.Mushrooms, 395, 44, scale: .8);
                Put(HabitatItemKind.Moss, 210); Put(HabitatItemKind.LeafPile, 650);
                Put(HabitatItemKind.Vine, 690); Put(HabitatItemKind.Fern, 190, front: true);
                Put(HabitatItemKind.Grass, 860, front: true, scale: .9); break;
            case 1:
                Put(HabitatItemKind.Bamboo, 70, scale: 1.1); Put(HabitatItemKind.Branch, 280, 110, scale: 1.25);
                Put(HabitatItemKind.Branch, 640, 190, scale: 1.1, flip: true); Put(HabitatItemKind.Vine, 170, scale: 1.2);
                Put(HabitatItemKind.Vine, 800); Put(HabitatItemKind.Plant, 790, scale: 1.2);
                Put(HabitatItemKind.Hide, 460, scale: .95); Put(HabitatItemKind.WaterDish, 610);
                Put(HabitatItemKind.Moss, 330); Put(HabitatItemKind.Flower, 700);
                Put(HabitatItemKind.Fern, 250, front: true, scale: 1.1); Put(HabitatItemKind.Fern, 560, front: true, scale: .85, flip: true); break;
            case 2:
                Put(HabitatItemKind.Boulder, 200, scale: 1.1); Put(HabitatItemKind.Rock, 335);
                Put(HabitatItemKind.Cactus, 590, scale: 1.1); Put(HabitatItemKind.Cactus, 660, scale: .7, flip: true);
                Put(HabitatItemKind.Driftwood, 440, scale: .9); Put(HabitatItemKind.Succulent, 520);
                Put(HabitatItemKind.Pebbles, 760); Put(HabitatItemKind.WaterDish, 820, scale: .9);
                Put(HabitatItemKind.Succulent, 120, front: true, scale: .9); break;
            case 3:
                Put(HabitatItemKind.Log, 220); Put(HabitatItemKind.Rock, 350, scale: .8);
                Put(HabitatItemKind.Branch, 780, 20, scale: .9, flip: true); Put(HabitatItemKind.Plant, 560, scale: .9);
                Put(HabitatItemKind.Flower, 430, scale: 1.1); Put(HabitatItemKind.Flower, 660, scale: .8);
                Put(HabitatItemKind.Moss, 610); Put(HabitatItemKind.Grass, 110, front: true);
                Put(HabitatItemKind.Flower, 300, front: true, scale: .8); Put(HabitatItemKind.Grass, 740, front: true, scale: 1.1); break;
            case 4:
                Put(HabitatItemKind.Boulder, 170, scale: 1.2); Put(HabitatItemKind.Boulder, 730);
                Put(HabitatItemKind.Rock, 430); Put(HabitatItemKind.CorkBark, 560, scale: .9);
                Put(HabitatItemKind.Crystal, 300, scale: 1.1); Put(HabitatItemKind.Crystal, 830, scale: .8);
                Put(HabitatItemKind.Mushrooms, 490, scale: 1.1); Put(HabitatItemKind.Pebbles, 640);
                Put(HabitatItemKind.Vine, 380, scale: .8); Put(HabitatItemKind.Crystal, 90, front: true, scale: .7); break;
            case 5:
                Put(HabitatItemKind.Driftwood, 280, scale: 1.3); Put(HabitatItemKind.Rock, 520);
                Put(HabitatItemKind.Rock, 575, scale: .6); Put(HabitatItemKind.Boulder, 820, scale: .8);
                Put(HabitatItemKind.Pebbles, 660); Put(HabitatItemKind.Twigs, 420);
                Put(HabitatItemKind.WaterDish, 720, scale: 1.1); Put(HabitatItemKind.Grass, 110, scale: 1.1);
                Put(HabitatItemKind.Succulent, 610, front: true, scale: .8); break;
            case 6:
                Put(HabitatItemKind.Boulder, 300); Put(HabitatItemKind.Rock, 160);
                Put(HabitatItemKind.Log, 620, scale: 1.1); Put(HabitatItemKind.Branch, 820, 50, scale: .8, flip: true);
                Put(HabitatItemKind.Twigs, 460); Put(HabitatItemKind.Moss, 760);
                Put(HabitatItemKind.Pebbles, 380); Put(HabitatItemKind.Grass, 70, front: true, scale: .8); break;
            case 7:
                Put(HabitatItemKind.Log, 340, scale: 1.1); Put(HabitatItemKind.Branch, 640, 70);
                Put(HabitatItemKind.Plant, 810); Put(HabitatItemKind.Rock, 490);
                Put(HabitatItemKind.Vine, 150); Put(HabitatItemKind.Mushrooms, 210);
                Put(HabitatItemKind.Crystal, 570, scale: .6); Put(HabitatItemKind.Fern, 260, front: true);
                Put(HabitatItemKind.Grass, 700, front: true, scale: .8); break;
        }
        return list;
    }

    /// <summary>Surprise Me: parts across the whole world, never the same twice (Swift surprise).</summary>
    public static HabitatWorld Surprise(Rect? bounds = null, HabitatBiome? biome = null, int? seed = null)
    {
        var b = bounds ?? DefaultBounds();
        var chosen = biome ?? HabitatBiomes.All[(seed ?? Environment.TickCount) & 7];
        var w = new HabitatWorld { Biome = chosen, Bounds = b, Name = "Surprise" };
        var lb = new LayoutBuilder(w, chosen, (ulong)(seed ?? Environment.TickCount));
        int n = Math.Max(3, (int)Math.Round(w.Width / 760));
        var all = new[] { HabitatRegionKind.Thicket, HabitatRegionKind.Clearing, HabitatRegionKind.Canopy,
            HabitatRegionKind.Shelter, HabitatRegionKind.Pool, HabitatRegionKind.Rocks };
        var must = new[] { HabitatRegionKind.Clearing, HabitatRegionKind.Canopy };
        var kinds = new List<HabitatRegionKind>();
        while (kinds.Count < n)
        {
            var k = all[(int)(lb.Dice.Next() * all.Length)];
            if (kinds.Count > 0 && kinds[^1] == k) continue;
            if (kinds.Count == n - must.Length)
                foreach (var miss in must) if (!kinds.Contains(miss)) { k = miss; break; }
            kinds.Add(k);
        }
        lb.Fill(0, w.Width, kinds.ToArray(), open: true);
        lb.Dress();
        return w;
    }

    /// <summary>Walk the tank and the furniture as real loops.</summary>
    public SurfaceMap BuildMap(double scale)
    {
        var map = new SurfaceMap();
        var surfaces = HabitatSurfaceBuilder.Build(this, scale);
        map.InstallHabitat(this, surfaces, scale);
        return map;
    }

    public Spot? GroundSpot(SurfaceMap map, double scale, double x)
    {
        var spots = map.SampleSpots(38, true, scale)
            .Where(s => map.Loop(s.LoopId)?.Segs[s.SegIdx].Facing == EdgeFacing.Up &&
                        s.Point.Y <= GroundY + 20)
            .OrderBy(s => Math.Abs(s.Point.X - x)).ThenBy(s => s.Point.Y)
            .ToList();
        if (spots.Count == 0) spots = map.SampleSpots(38, true, scale).OrderBy(s => Math.Abs(s.Point.X - x)).ToList();
        return spots.Count == 0 ? null : spots[0];
    }

    public List<HabitatRegion> Regions => HabitatRegionFinder.Find(this);

    public IEnumerable<HabitatItem> ItemsOn(HabitatItemKind kind) => Items.Where(i => i.Kind == kind);

    // ------------------------------------------------------------------ saved form
    public string ToJson()
    {
        var root = new JsonObject
        {
            ["biome"] = Biome.SaveName(),
            ["nextID"] = NextId,
            ["world"] = new JsonObject { ["width"] = Bounds.W, ["height"] = Bounds.H },
            ["items"] = new JsonArray(Items.Select(i => (JsonNode)new JsonObject
            {
                ["id"] = i.Id, ["uid"] = i.Uid, ["kind"] = i.Kind.SaveName(),
                ["x"] = i.X, ["y"] = i.Y, ["w"] = i.W, ["h"] = i.H,
                ["flipped"] = i.Flip, ["seed"] = i.Seed, ["front"] = i.Front
            }).ToArray()),
            ["links"] = new JsonArray(Links.Select(l => (JsonNode)new JsonObject
            {
                ["child"] = l.Child, ["childPort"] = l.ChildPort,
                ["parent"] = l.Parent, ["parentPort"] = l.ParentPort, ["at"] = l.At, ["childAt"] = l.ChildAt
            }).ToArray()),
            ["name"] = Name
        };
        return root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

    public static HabitatWorld FromJson(string? json)
    {
        var fallback = Preset(HabitatBiome.Forest, DefaultBounds());
        if (string.IsNullOrWhiteSpace(json)) return fallback;
        try
        {
            var root = JsonNode.Parse(json) as JsonObject;
            if (root is null) return fallback;
            HabitatBiome biome = HabitatBiome.Forest;
            if (root["biome"] is JsonNode bn)
            {
                if (bn is JsonValue bv && bv.TryGetValue(out string? bs)) biome = HabitatBiomes.Parse(bs);
                else if (bn is JsonValue bi && bi.TryGetValue(out int bint)) biome = bint switch
                {
                    1 => HabitatBiome.Jungle, 2 => HabitatBiome.Desert, 3 => HabitatBiome.Meadow,
                    4 => HabitatBiome.Cave, 5 => HabitatBiome.Beach, 6 => HabitatBiome.Tundra,
                    7 => HabitatBiome.Moonlit, 8 => HabitatBiome.Empty, _ => HabitatBiome.Forest
                };
            }
            double width = 0, height = 0;
            if (root["world"] is JsonObject world)
            {
                width = Num(world["width"]); height = Num(world["height"]);
            }
            if (width < 200 || height < 100)
            {
                width = Num(root["w"]); height = Num(root["h"]);
                if (width <= 0) width = LayoutWidth;
                if (height <= 0) height = LayoutHeight;
            }
            bool hadWorld = root["world"] is JsonObject;
            var bounds = new Rect(0, 0, width, height);
            var result = new HabitatWorld
            {
                Name = root["name"] is JsonValue nv && nv.TryGetValue(out string? nm) && !string.IsNullOrWhiteSpace(nm)
                    ? nm : PresetNames[biome switch
                    {
                        HabitatBiome.Jungle => 1, HabitatBiome.Desert => 2, HabitatBiome.Meadow => 3,
                        HabitatBiome.Cave => 4, HabitatBiome.Beach => 5, HabitatBiome.Tundra => 6,
                        HabitatBiome.Moonlit => 7, HabitatBiome.Empty => 8, _ => 0
                    }],
                Biome = biome, Bounds = bounds
            };
            int nextId = (int)Num(root["nextID"]);
            if (root["items"] is JsonArray items)
            {
                foreach (var node in items.OfType<JsonObject>())
                {
                    string? kindText = node["kind"] is JsonValue kv
                        ? (kv.TryGetValue<string>(out var ks) ? ks : kv.TryGetValue<int>(out var ki) ? ki.ToString() : null) : null;
                    var kind = HabitatItemKind.Log;
                    if (node["kind"] is JsonValue kval)
                    {
                        if (kval.TryGetValue<string>(out var s)) kind = HabitatKinds.Parse(s);
                        else if (kval.TryGetValue<int>(out var ii)) kind = HabitatKinds.Parse(ii.ToString());
                    }
                    double x = Num(node["x"]), y = Num(node["y"]), iw = Num(node["w"]), ih = Num(node["h"]);
                    bool legacy = node["id"] is null || node["uid"] is null;
                    if (legacy && !hadWorld)
                    {
                        // The old Windows model stored the bottom-left of a frame in world coordinates.
                        x += iw / 2;
                        y = Math.Max(0, y - Ground);
                    }
                    var it = new HabitatItem
                    {
                        Id = (int)Num(node["id"]), Uid = node["uid"] is JsonValue uv && uv.TryGetValue(out string? us) ? us : Guid.NewGuid().ToString("D").ToUpperInvariant(),
                        Kind = kind, X = x, Y = y, W = Math.Max(12, iw), H = Math.Max(10, ih),
                        Flip = Bool(node["flipped"], Bool(node["flip"], false)), Seed = (int)Num(node["seed"]),
                        Front = Bool(node["front"], false)
                    };
                    if (it.Id <= 0) it.Id = nextId++;
                    result.Items.Add(it);
                }
            }
            if (root["links"] is JsonArray links)
            {
                foreach (var l in links.OfType<JsonObject>())
                {
                    result.Links.Add(new HabitatLink
                    {
                        Child = Str(l["child"]), ChildPort = Str(l["childPort"]),
                        Parent = Str(l["parent"]), ParentPort = Str(l["parentPort"]),
                        At = Num(l["at"]), ChildAt = Num(l["childAt"])
                    });
                }
            }
            result.NextId = Math.Max(nextId, result.Items.Count == 0 ? 1 : result.Items.Max(i => i.Id) + 1);
            result.GiveIdentities();
            if (!hadWorld) result = result.MovedIntoWorld(new SizeD(result.Width, result.Height));
            result.ClampAll();
            result.PruneLinks();
            return result;
        }
        catch { return fallback; }
    }

    static string Str(JsonNode? n) => n is JsonValue v && v.TryGetValue(out string? s) ? s : "";
    static double Num(JsonNode? n) => n is JsonValue v && v.TryGetValue(out double d) && double.IsFinite(d) ? d : 0;
    static bool Bool(JsonNode? n, bool def) => n is JsonValue v && v.TryGetValue(out bool b) ? b : def;

    public bool GiveIdentities()
    {
        bool changed = false;
        var seen = new HashSet<string>();
        foreach (var it in Items)
        {
            if (string.IsNullOrWhiteSpace(it.Uid) || !seen.Add(it.Uid))
            {
                it.Uid = Guid.NewGuid().ToString("D").ToUpperInvariant();
                seen.Add(it.Uid);
                changed = true;
            }
        }
        return changed;
    }

    public HabitatWorld MovedIntoWorld(SizeD world)
    {
        if (Math.Abs(world.Width - Width) < .5 && Math.Abs(world.Height - Height) < .5) return this;
        // An untouched old preset becomes the new layout of that name.
        for (int p = 0; p < 8; p++)
        {
            var legacy = LegacyItems(p, Bounds).ToList();
            if (Items.Count > 0 && SameLayout(legacy, Items))
            {
                var h = Preset(p, new Rect(0, 0, world.Width, world.Height));
                h.Biome = Biome;
                h.Name = Name;
                return h;
            }
        }
        var result = new HabitatWorld { Name = Name, Biome = Biome, Bounds = new Rect(0, 0, world.Width, world.Height), NextId = NextId };
        result.Items.AddRange(Items);
        double dx = Math.Round((world.Width - Width) / 2), lift = world.Height - Height;
        foreach (var it in result.Items)
        {
            it.X += dx;
            if (it.Kind.Hangs()) { it.Y += lift; it.H += lift; }
        }
        result.ClampAll();
        return result;
    }

    public static bool SameLayout(IReadOnlyList<HabitatItem> a, IReadOnlyList<HabitatItem> b)
    {
        if (a.Count != b.Count) return false;
        for (int i = 0; i < a.Count; i++)
        {
            var p = a[i]; var q = b[i];
            if (p.Kind != q.Kind || p.Flip != q.Flip || p.Front != q.Front) return false;
            if (Math.Abs(p.X - q.X) >= 6 || Math.Abs(p.Y - q.Y) >= 6 || Math.Abs(p.W - q.W) >= 6 || Math.Abs(p.H - q.H) >= 6) return false;
        }
        return true;
    }

    public void PruneLinks() => Links.RemoveAll(l => Item(l.Child) is null || Item(l.Parent) is null);

    /// <summary>Top of a thing's solid shape between two x positions (for resting on it).</summary>
    public static double? RestingTop(HabitatItem it, double lo, double hi)
    {
        if (!it.Kind.Climbable()) return null;
        return HabitatGeometry.For(it).Top(lo, hi);
    }

    public static double? SideAt(HabitatItem it, double y, bool right)
    {
        double? best = null;
        foreach (var part in HabitatGeometry.For(it).Parts)
        {
            var o = part.Outline;
            for (int i = 0; i < o.Count; i++)
            {
                var a = o[i]; var b = o[(i + 1) % o.Count];
                if ((a.Y - y) * (b.Y - y) <= 0 && Math.Abs(b.Y - a.Y) > 1e-6)
                {
                    double x = a.X + (b.X - a.X) * (y - a.Y) / (b.Y - a.Y);
                    if (best is null || (right ? x > best : x < best)) best = x;
                }
            }
        }
        return best;
    }
}

/// <summary>The seeded layout builder: parts end to end across the whole world.</summary>
sealed class LayoutBuilder
{
    public readonly HabitatWorld H;
    public readonly SeededDice Dice;
    readonly HabitatBiome _biome;
    readonly double _w, _h, _lift;
    double _partX, _partW;

    public LayoutBuilder(HabitatWorld world, HabitatBiome biome, ulong seed)
    {
        H = world; _biome = biome; _w = world.Width; _h = world.Height;
        Dice = new SeededDice(seed);
        _lift = (world.Height - HabitatWorld.Ground) / (1250 - HabitatWorld.Ground);
    }

    public HabitatItem Put(HabitatItemKind kind, double x, double y = 0, bool front = false, double scale = 1,
        double? tall = null, bool? flipped = null)
    {
        var d = kind.Definition();
        var it = H.AddItem(kind, new V2(x, kind.Hangs() ? _h : y), scale, flip: flipped ?? Dice.Chance(.5), seed: 1 + Dice.Int(9998), front: front);
        if (tall is { } t) it.H = d.Height * t;
        H.Clamp(it);
        if (front && !kind.CanGoInFront()) it.Front = false;
        return it;
    }

    public void Vine(double x, double bottom)
    {
        double len = Math.Max(_h - HabitatWorld.Ground - bottom, 160);
        Put(HabitatItemKind.Vine, x, tall: len / HabitatItemKind.Vine.DefaultSize().Height);
    }

    public void PutOld(HabitatItem old, double dx)
    {
        var it = old.Clone();
        it.Id = H.NextId++;
        it.Uid = Guid.NewGuid().ToString("D").ToUpperInvariant();
        it.X += dx;
        if (it.Kind.Hangs())
        {
            double bottom = old.Y - old.H;
            it.Y = _h;
            it.H = _h - bottom;
        }
        H.Clamp(it);
        H.Items.Add(it);
    }

    public void Overhead(double x)
    {
        double high = 420 * _lift;
        Put(HabitatItemKind.Branch, x - 160, high, scale: 1.45, flipped: false);
        Put(HabitatItemKind.Branch, x + 230, high + 190 * _lift, scale: 1.3, flipped: true);
        Put(HabitatItemKind.Branch, x - 60, high + 400 * _lift, scale: 1.2, flipped: false);
        if (_biome != HabitatBiome.Desert) { Vine(x + 60, high + 60); Vine(x - 250, high + 360 * _lift); }
    }

    public void Fill(double a, double b, IReadOnlyList<HabitatRegionKind> kinds, bool open = false)
    {
        double span = Math.Abs(b - a);
        if (span <= 200 || kinds.Count == 0) return;
        int n = open ? kinds.Count : Math.Max(1, (int)Math.Round(span / 540));
        var laid = new List<HabitatRegionKind>();
        for (int i = 0; i < n; i++) laid.Add(kinds[i % kinds.Count]);
        if (n < kinds.Count)
        {
            laid = kinds.Take(Math.Max(1, n - 1)).ToList();
            laid.Add(kinds[^1]);
        }
        double dir = b > a ? 1 : -1;
        for (int k = 0; k < laid.Count; k++)
        {
            double lo = a + dir * span * k / laid.Count, hi = a + dir * span * (k + 1) / laid.Count;
            Region(laid[k], Math.Min(lo, hi), Math.Max(lo, hi));
        }
    }

    bool Dry => _biome is HabitatBiome.Desert or HabitatBiome.Beach;
    double At(double f) => _partX + _partW * f + Dice.Range(-1, 1) * _partW * .03;

    HabitatItemKind Any(params HabitatItemKind[] kinds)
    {
        var fit = kinds.Where(k => k.Suits(_biome)).ToArray();
        var a = fit.Length > 0 ? fit : kinds;
        return a[Dice.Int(a.Length - 1)];
    }

    public void Region(HabitatRegionKind kind, double x0, double x1)
    {
        _partX = x0; _partW = x1 - x0;
        switch (kind)
        {
            case HabitatRegionKind.Thicket: Thicket(); break;
            case HabitatRegionKind.Clearing: Clearing(); break;
            case HabitatRegionKind.Canopy: Canopy(); break;
            case HabitatRegionKind.Shelter: Shelter(); break;
            case HabitatRegionKind.Pool: Pool(); break;
            case HabitatRegionKind.Rocks: Rocks(); break;
            default: if (Dice.Chance(.5)) Put(HabitatItemKind.Pebbles, At(.5)); break;
        }
    }

    void Thicket()
    {
        switch (_biome)
        {
            case HabitatBiome.Desert:
                Put(HabitatItemKind.Cactus, At(.2), scale: Dice.Range(1.2, 1.6)); Put(HabitatItemKind.Aloe, At(.34), scale: Dice.Range(1, 1.3));
                Put(HabitatItemKind.JadePlant, At(.5), scale: 1.2); Put(HabitatItemKind.Cactus, At(.72), scale: Dice.Range(1.5, 2));
                Put(HabitatItemKind.DeadPlant, At(.86), scale: 1.2); Put(HabitatItemKind.Lithops, At(.42));
                Put(HabitatItemKind.SandDrift, At(.62), scale: .8); Put(HabitatItemKind.Succulent, At(.1), front: true, scale: .9); Put(HabitatItemKind.Gravel, At(.9), front: true); break;
            case HabitatBiome.Beach:
                Put(HabitatItemKind.MiniPalm, At(.16), scale: 1.3); Put(HabitatItemKind.GrassClump, At(.3), scale: 1.2);
                Put(HabitatItemKind.DriftwoodBranch, At(.5), scale: .9); Put(HabitatItemKind.GrassClump, At(.68), scale: 1.4);
                Put(HabitatItemKind.Aloe, At(.84)); Put(HabitatItemKind.SeaShell, At(.42), scale: .8);
                Put(HabitatItemKind.SandDrift, At(.76)); Put(HabitatItemKind.Grass, At(.6), front: true, scale: 1.1); break;
            case HabitatBiome.Cave:
                Put(HabitatItemKind.CrystalCluster, At(.2), scale: 1.2); Put(HabitatItemKind.MushroomCluster, At(.36), scale: 1.1);
                Put(HabitatItemKind.LargeFern, At(.54), scale: .9); Put(HabitatItemKind.CrystalCluster, At(.78), scale: .8);
                Put(HabitatItemKind.HangingRoots, At(.45), tall: 1.5 * _lift); Put(HabitatItemKind.GlowMushrooms, At(.64));
                Put(HabitatItemKind.GlowMushrooms, At(.92), scale: .8); Put(HabitatItemKind.SmallFern, At(.1), front: true); break;
            case HabitatBiome.Tundra:
                Put(HabitatItemKind.Stump, At(.24), scale: 1.1); Put(HabitatItemKind.GrassClump, At(.12), scale: .9);
                Put(HabitatItemKind.DeadPlant, At(.44), scale: 1.2); Put(HabitatItemKind.GrassClump, At(.6));
                Put(HabitatItemKind.MossCushion, At(.74)); Put(HabitatItemKind.PineCone, At(.84));
                Put(HabitatItemKind.PineNeedles, At(.5)); Put(HabitatItemKind.Grass, At(.66), front: true, scale: .8); break;
            default:
                Put(_biome == HabitatBiome.Meadow ? HabitatItemKind.FloweringPlant : HabitatItemKind.LargeFern, At(.18), scale: Dice.Range(1.1, 1.3));
                Put(_biome == HabitatBiome.Jungle ? HabitatItemKind.LeafCanopy : HabitatItemKind.BroadLeaf, At(.38), scale: Dice.Range(1.1, 1.3));
                Put(HabitatItemKind.ClimbingVine, At(.5), tall: Dice.Range(1.3, 1.7));
                Put(Any(HabitatItemKind.GrassClump, HabitatItemKind.Fiddleheads, HabitatItemKind.FloweringPlant), At(.62), scale: 1.2);
                Put(_biome == HabitatBiome.Meadow ? HabitatItemKind.FloweringPlant : HabitatItemKind.LargeFern, At(.8), scale: Dice.Range(1, 1.2));
                Put(HabitatItemKind.MossCushion, At(.28)); Put(Any(HabitatItemKind.MushroomCluster, HabitatItemKind.TinyMushrooms, HabitatItemKind.GlowMushrooms), At(.7));
                Put(_biome == HabitatBiome.Meadow ? HabitatItemKind.TinyFlowers : HabitatItemKind.CreepingCover, At(.92));
                Put(HabitatItemKind.HangingFoliage, At(.3), tall: Dice.Range(1.2, 1.6) * _lift);
                Put(HabitatItemKind.SmallFern, At(.08), front: true, scale: 1.3);
                Put(_biome == HabitatBiome.Meadow ? HabitatItemKind.TinyFlowers : HabitatItemKind.Fern, At(.72), front: true, scale: 1.1); break;
        }
    }

    void Clearing()
    {
        switch (_biome)
        {
            case HabitatBiome.Desert:
                Put(HabitatItemKind.Gravel, At(.2)); Put(HabitatItemKind.SandDrift, At(.42), scale: 1.2);
                Put(HabitatItemKind.SeedPod, At(.6)); Put(HabitatItemKind.BaskingStone, At(.8));
                Put(HabitatItemKind.TinyPebble, At(.3)); Put(HabitatItemKind.DeadLeaf, At(.66)); break;
            case HabitatBiome.Beach:
                Put(HabitatItemKind.SandDrift, At(.2), scale: 1.3); Put(HabitatItemKind.SeaShell, At(.44));
                Put(HabitatItemKind.SmallShell, At(.56)); Put(HabitatItemKind.Feather, At(.68));
                Put(HabitatItemKind.PebblePile, At(.84), scale: .8); Put(HabitatItemKind.SmallShell, At(.3), front: true); break;
            case HabitatBiome.Cave:
                Put(HabitatItemKind.Gravel, At(.2)); Put(HabitatItemKind.Puddle, At(.45), scale: 1.2);
                Put(HabitatItemKind.PebblePile, At(.7)); Put(HabitatItemKind.TinyMushrooms, At(.86));
                Put(HabitatItemKind.Crystal, At(.6), scale: .6); break;
            case HabitatBiome.Tundra:
                Put(HabitatItemKind.PineNeedles, At(.2)); Put(HabitatItemKind.SmoothStones, At(.4), scale: .9);
                Put(HabitatItemKind.TwigPile, At(.62), scale: .8); Put(HabitatItemKind.PineCone, At(.8));
                Put(HabitatItemKind.TinyTwig, At(.5)); break;
            default:
                Put(_biome == HabitatBiome.Meadow ? HabitatItemKind.TinyFlowers : HabitatItemKind.LeafPile, At(.16));
                Put(HabitatItemKind.FallenLeaf, At(.3)); Put(Any(HabitatItemKind.Acorn, HabitatItemKind.SnailShell, HabitatItemKind.SeedPod), At(.4));
                Put(_biome == HabitatBiome.Meadow ? HabitatItemKind.CreepingCover : HabitatItemKind.PineNeedles, At(.55));
                Put(Dice.Chance(.5) ? HabitatItemKind.Mushroom : HabitatItemKind.Puddle, At(.66));
                Put(HabitatItemKind.Rock, At(.82), scale: .7);
                Put(_biome == HabitatBiome.Meadow ? HabitatItemKind.Petals : HabitatItemKind.LooseLeaf, At(.74));
                Put(Any(HabitatItemKind.DeadLeaf, HabitatItemKind.Feather, HabitatItemKind.Seed), At(.92));
                Put(_biome == HabitatBiome.Meadow ? HabitatItemKind.Grass : HabitatItemKind.SmallFern, At(.5), front: true, scale: .8); break;
        }
    }

    void Canopy()
    {
        var choices = _biome switch
        {
            HabitatBiome.Jungle => new[] { HabitatItemKind.BambooTipi, HabitatItemKind.ThreeFork, HabitatItemKind.Lookout, HabitatItemKind.BambooTipi, HabitatItemKind.ClimbingRoot },
            HabitatBiome.Desert => new[] { HabitatItemKind.RockSpire, HabitatItemKind.DriftwoodSnag, HabitatItemKind.Lookout },
            HabitatBiome.Beach => new[] { HabitatItemKind.DriftwoodSnag, HabitatItemKind.Lookout, HabitatItemKind.RockSpire },
            HabitatBiome.Cave => new[] { HabitatItemKind.RockSpire, HabitatItemKind.Lookout, HabitatItemKind.RockSpire },
            _ => new[] { HabitatItemKind.ThreeFork, HabitatItemKind.CorkBark, HabitatItemKind.Lookout, HabitatItemKind.ClimbingRoot }
        };
        var uprights = new List<HabitatItemKind>();
        while (uprights.Count < 3)
        {
            var k = choices[Dice.Int(choices.Length - 1)];
            if (uprights.Count == 0 || uprights[^1] != k || choices.Length < 2) uprights.Add(k);
        }
        if (!uprights.Contains(HabitatItemKind.Lookout) && choices.Contains(HabitatItemKind.Lookout) && Dice.Chance(.6)) uprights[2] = HabitatItemKind.Lookout;
        var heights = new[] { 260 * _lift, 470 * _lift, 680 * _lift };
        var xs = new[] { At(.14), At(.48), At(.84) };
        var tops = new List<V2>();
        for (int i = 0; i < 3; i++)
        {
            var kind = uprights[i];
            var it = Put(kind, xs[i], scale: kind == HabitatItemKind.CorkBark ? 1.3 : 1.1, tall: heights[i] / kind.DefaultSize().Height, flipped: false);
            var top = kind == HabitatItemKind.ThreeFork ? new V2(it.X, it.Rect.MinY + it.H * .62)
                : kind == HabitatItemKind.ClimbingRoot ? new V2(it.X, it.Rect.MaxY - it.H * .25)
                : new V2(it.X, it.Rect.MaxY - (kind == HabitatItemKind.Lookout ? 4 : 10));
            tops.Add(top);
        }
        for (int i = 0; i < 2; i++) Bridge(tops[i], tops[i + 1]);
        var hi = tops[2];
        Bridge(new V2(hi.X - _partW * .02, hi.Y - 8), new V2(Math.Min(hi.X + _partW * .22, _w - 80), hi.Y + 130 * _lift));
        if (Dry) Put(HabitatItemKind.DriftwoodRoot, At(.3), scale: 1.1);
        else
        {
            Put(Any(HabitatItemKind.HangingFoliage, HabitatItemKind.HangingRoots, HabitatItemKind.Vine), At(.66), tall: Math.Max(.2, (_h - HabitatWorld.Ground - tops[1].Y + HabitatWorld.Ground - 60) / 240));
            Put(Any(HabitatItemKind.HangingLeafShelter, HabitatItemKind.HangingBranch), At(.32), tall: 1.4 * _lift);
            Vine(At(.96), tops[2].Y - HabitatWorld.Ground + 40);
            Put(_biome == HabitatBiome.Tundra ? HabitatItemKind.PineNeedles : HabitatItemKind.LeafPile, At(.56));
            Put(Any(HabitatItemKind.ExposedRoot, HabitatItemKind.RootTangle), At(.28), scale: .9);
        }
        Put(Dry ? HabitatItemKind.Succulent : HabitatItemKind.Fern, At(.04), front: true, scale: 1.1);
    }

    void Bridge(V2 p, V2 q)
    {
        double dx = Math.Abs(q.X - p.X), dy = q.Y - p.Y;
        var left = p.X < q.X ? p : q; var right = p.X < q.X ? q : p;
        if (Math.Abs(dy) < 60)
        {
            var kind = _biome == HabitatBiome.Jungle ? HabitatItemKind.BambooSegment : (Dice.Chance(.5) ? HabitatItemKind.TwistedBranch : HabitatItemKind.ShortBranch);
            double w = dx + 70, hgt = kind.DefaultSize().Height * (kind == HabitatItemKind.BambooSegment ? 1 : 1.1);
            double mid = kind == HabitatItemKind.TwistedBranch ? .46 : .5;
            double y = (left.Y + right.Y) / 2 - hgt * mid - HabitatWorld.Ground;
            var it = Put(kind, (left.X + right.X) / 2, Math.Max(0, y), flipped: false);
            it.W = w; it.H = hgt; H.Clamp(it);
        }
        else
        {
            var kind = Dry ? HabitatItemKind.DriftwoodBranch : HabitatItemKind.MediumBranch;
            var (lx, ly, rx, ry) = kind == HabitatItemKind.MediumBranch ? (.02, .25, .98, .8) : (.02, .03, .98, .9);
            var low = left.Y < right.Y ? left : right; var high = left.Y < right.Y ? right : left;
            double w = (dx + 50) / (rx - lx), hgt = Math.Abs(dy) / (ry - ly);
            bool flip = low.X > high.X; double cx = (low.X + high.X) / 2, y = low.Y - ly * hgt - HabitatWorld.Ground;
            var it = Put(kind, cx, Math.Max(0, y), flipped: flip);
            it.W = w; it.H = Math.Max(hgt, 40); it.X = cx; it.Y = Math.Max(0, y); H.Clamp(it);
        }
    }

    void Shelter()
    {
        void Pair(HabitatItemKind a, bool fa, HabitatItemKind b, bool fb) { Put(a, At(.24), flipped: fa); Put(b, At(.77), flipped: fb); }
        switch (_biome)
        {
            case HabitatBiome.Desert:
                Pair(HabitatItemKind.Overhang, false, HabitatItemKind.RockCrevice, false);
                Put(HabitatItemKind.Aloe, At(.02)); Put(HabitatItemKind.Gravel, At(.5)); Put(HabitatItemKind.DeadPlant, At(.97), scale: .8); break;
            case HabitatBiome.Beach:
                Pair(HabitatItemKind.DriftwoodRoot, false, HabitatItemKind.Overhang, true);
                Put(HabitatItemKind.SeaShell, At(.5), scale: .8); Put(HabitatItemKind.SmallShell, At(.56)); break;
            case HabitatBiome.Cave:
                Pair(HabitatItemKind.RockCrevice, true, HabitatItemKind.MossyHide, true);
                Put(HabitatItemKind.GlowMushrooms, At(.5)); Put(HabitatItemKind.Puddle, At(.97), scale: .7); break;
            case HabitatBiome.Tundra:
                Pair(HabitatItemKind.LogDen, true, HabitatItemKind.RootHollow, false);
                Put(HabitatItemKind.PineCone, At(.5)); Put(HabitatItemKind.PineNeedles, At(.55)); break;
            default:
                var first = _biome is HabitatBiome.Jungle or HabitatBiome.Meadow ? HabitatItemKind.CurledLeafHide : HabitatItemKind.BarkCave;
                var second = Dice.Chance(.5) ? HabitatItemKind.LogDen : HabitatItemKind.RootHollow;
                Pair(first, false, second, second != HabitatItemKind.LogDen);
                Put(HabitatItemKind.LeafPile, At(.5)); Put(HabitatItemKind.ShedBark, At(.03), scale: .8); Put(HabitatItemKind.Fern, At(.98), front: true); break;
        }
    }

    void Pool()
    {
        Put(_biome is HabitatBiome.Cave or HabitatBiome.Tundra ? HabitatItemKind.RockPool : HabitatItemKind.WaterDish, At(.36), scale: 1.3);
        Put(Dice.Chance(.5) ? HabitatItemKind.RockPool : HabitatItemKind.Puddle, At(.64), scale: .9);
        Put(HabitatItemKind.SmoothStones, At(.18), scale: .8);
        switch (_biome)
        {
            case HabitatBiome.Desert:
            case HabitatBiome.Beach:
                Put(HabitatItemKind.Aloe, At(.84)); Put(_biome == HabitatBiome.Beach ? HabitatItemKind.SeaShell : HabitatItemKind.BaskingStone, At(.5), scale: .8);
                Put(HabitatItemKind.Succulent, At(.5), front: true, scale: .8); break;
            case HabitatBiome.Cave:
                Put(HabitatItemKind.GlowMushrooms, At(.5)); Put(HabitatItemKind.CrystalCluster, At(.84), scale: .7); break;
            case HabitatBiome.Tundra:
                Put(HabitatItemKind.MossCushion, At(.52)); Put(HabitatItemKind.PebblePile, At(.84)); break;
            default:
                Put(HabitatItemKind.MoistMoss, At(.52)); Put(HabitatItemKind.BroadLeaf, At(.84), scale: 1.1);
                Put(HabitatItemKind.SnailShell, At(.1)); Put(HabitatItemKind.Grass, At(.06), scale: 1.1);
                Put(_biome is HabitatBiome.Meadow or HabitatBiome.Jungle ? HabitatItemKind.Flower : HabitatItemKind.SmallFern, At(.92), front: true); break;
        }
    }

    void Rocks()
    {
        var big = Put(HabitatItemKind.Boulder, At(.24), scale: Dice.Range(1.3, 1.6));
        Put(Dry || _biome == HabitatBiome.Cave ? HabitatItemKind.StoneArch : HabitatItemKind.Rock, At(.5));
        Put(HabitatItemKind.Boulder, At(.76), scale: Dice.Range(.9, 1.1));
        Put(HabitatItemKind.BaskingStone, At(.92), scale: .8); Put(HabitatItemKind.PebblePile, At(.1));
        var prop = Dry ? HabitatItemKind.Driftwood : HabitatItemKind.Log;
        double px = big.X + big.W * .1, half = prop.DefaultSize().Width * .8 * .25;
        var top = HabitatWorld.RestingTop(big, px - half, px + half);
        if (top is { } ty) Put(prop, px, ty - HabitatWorld.Ground, scale: .8);
        switch (_biome)
        {
            case HabitatBiome.Desert: Put(HabitatItemKind.Cactus, At(.62), scale: .7); break;
            case HabitatBiome.Cave: Put(HabitatItemKind.CrystalCluster, At(.62)); Put(HabitatItemKind.Crystal, At(.96), front: true, scale: .7); break;
            case HabitatBiome.Tundra: Put(HabitatItemKind.SmoothStones, At(.62)); break;
            case HabitatBiome.Beach: Put(HabitatItemKind.SeaShell, At(.62)); break;
            default: Put(HabitatItemKind.MossCushion, At(.62)); Put(HabitatItemKind.Mushrooms, At(.96), scale: .8); break;
        }
    }

    public void Dress()
    {
        var hosts = H.Items.Where(i => !i.Kind.Hangs() && i.Kind.Climbable() && i.OnGround && i.W > 60).ToList();
        foreach (var host in hosts)
        {
            var m = host.Kind.Traits().Material;
            var onTop = HabitatCatalog.All.Where(k =>
            {
                var tr = k.Traits();
                return !tr.NicheSide && tr.NicheOn.Contains(m) && k.Suits(_biome) && k.Definition().Shelf == HabitatShelf.Details &&
                       k.DefaultSize().Width < host.W * .6;
            }).ToArray();
            var onSide = HabitatCatalog.All.Where(k =>
            {
                var tr = k.Traits();
                return tr.NicheSide && tr.NicheOn.Contains(m) && k.Suits(_biome);
            }).ToArray();
            if (onSide.Length > 0 && host.H > 70 && Dice.Chance(.45))
            {
                var k = onSide[Dice.Int(onSide.Length - 1)];
                bool right = Dice.Chance(.5);
                double y = host.H * Dice.Range(.3, .6);
                double edge = HabitatWorld.SideAt(host, host.Rect.MinY + y, right) ?? (right ? host.Rect.MaxX : host.Rect.MinX);
                double sw = k.DefaultSize().Width;
                Put(k, edge + (right ? sw * .5 - 4 : -sw * .5 + 4), y, flipped: !right);
            }
            if (onTop.Length > 0 && Dice.Chance(.35))
            {
                var k = onTop[Dice.Int(onTop.Length - 1)];
                double x = host.X + host.W * Dice.Range(-.25, .25);
                double half = k.DefaultSize().Width * .8 * .25;
                var top = HabitatWorld.RestingTop(host, x - half, x + half);
                if (top is { } ty) Put(k, x, ty - HabitatWorld.Ground, scale: .8);
            }
        }
    }
}

sealed class SeededDice
{
    ulong _state;
    public SeededDice(ulong seed) { _state = seed | 1; }
    public double Next()
    {
        _state ^= _state << 13; _state ^= _state >> 7; _state ^= _state << 17;
        return (_state % 1_000_000) / 1_000_000.0;
    }
    public double Range(double a, double b) => a + (b - a) * Next();
    public bool Chance(double p) => Next() < p;
    public int Int(int max) => Math.Min(max, (int)(Next() * (max + 1)));
}

static class HabitatRegionFinder
{
    public static List<HabitatRegion> Find(HabitatWorld h)
    {
        double W = h.Width;
        var sorted = h.Items.OrderBy(i => i.X).ToList();
        var cuts = new List<double> { 0 };
        double reach = 0;
        for (int i = 0; i < sorted.Count; i++)
        {
            var it = sorted[i];
            if (it.Kind.Hangs() || it.W <= 60) continue;
            double lo = it.X - it.W / 2;
            if (i > 0 && lo - reach > 150) cuts.Add(Math.Round((lo + reach) / 2));
            reach = Math.Max(reach, it.X + it.W / 2);
        }
        cuts.Add(W);
        var bands = new List<(double, double)>();
        for (int i = 0; i + 1 < cuts.Count; i++)
        {
            double a = cuts[i], b = cuts[i + 1];
            if (b - a <= 1) continue;
            int n = Math.Max(1, (int)Math.Ceiling((b - a) / 1300));
            for (int k = 0; k < n; k++) bands.Add((a + (b - a) * k / n, a + (b - a) * (k + 1) / n));
        }
        return bands.Select((band, i) =>
        {
            var inside = h.Items.Where(it => it.X >= band.Item1 && it.X < band.Item2).ToList();
            return new HabitatRegion
            {
                Id = $"region:{i}", Kind = Character(inside), Rect = new Rect(band.Item1, 0, band.Item2 - band.Item1, h.Height),
                Items = inside.Select(x => x.Id).ToList()
            };
        }).ToList();
    }

    static HabitatRegionKind Character(List<HabitatItem> items)
    {
        if (items.Any(i => i.Kind.Functions().Contains(HabitatFunction.Water))) return HabitatRegionKind.Pool;
        if (items.Any(i => (i.Kind.Climbable() && i.Y > 150) || (!i.Kind.Hangs() && i.H > 350))) return HabitatRegionKind.Canopy;
        if (items.Any(i => i.Kind.Definition().Shelf == HabitatShelf.Shelter || i.Kind is HabitatItemKind.Hide or HabitatItemKind.CorkTunnel)) return HabitatRegionKind.Shelter;
        if (items.Count(i => i.Kind.Climbable() && i.Kind.Traits().Material == HabitatMaterial.Stone && i.Kind.Definition().Shelf == HabitatShelf.Structures) >= 2) return HabitatRegionKind.Rocks;
        if (items.Count(i => i.Kind is HabitatItemKind.Hide or HabitatItemKind.CorkBark or HabitatItemKind.Log or HabitatItemKind.Driftwood or HabitatItemKind.Stump) >= 2) return HabitatRegionKind.Shelter;
        if (items.Count(i => i.Kind.Definition().Shelf == HabitatShelf.Plants) >= 3) return HabitatRegionKind.Thicket;
        return items.Count == 0 ? HabitatRegionKind.Open : HabitatRegionKind.Clearing;
    }
}
