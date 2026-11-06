namespace SpiderBuddy.Core;

/// <summary>What a bit of the tank is like for the small things that live in it.</summary>
public enum EcoFeature { Shelter, Litter, Damp, Dark, Food, Bloom, Bark, Foliage, Glow, Fungus }

/// <summary>A run of tank surface with one character (Swift EcoSite).</summary>
public sealed class EcoSite
{
    public EcoFeature Feature;
    public readonly List<int> On = new();
    public readonly List<int> By = new();
    public readonly List<string> Owners = new();
    public Rect Rect;
    public double Pull;
    public double Reach = 1;
    public int Spots;
    public override string ToString() => $"{Feature} {Rect} pull={Pull:0.##} spots={Spots}";
}

/// <summary>One place a small thing can be.</summary>
public sealed class EcoSpot
{
    public V2 Point, Surface;
    public EdgeFacing Facing;
    public int Owner;
    public bool Glass, Open, Water;
    public double Height;
    public List<int> Sites = new();
}

/// <summary>Water waiting to be shaken off a surface.</summary>
public sealed class Droplet
{
    public V2 Point;
    public double Size;
    public bool Fall;
    public EcoSpot? Spot;
}

/// <summary>What is left of something eaten.</summary>
public sealed class Remains
{
    public V2 Point;
    public PreyKind Kind;
    public double Age;
    public double Life = 1;
}

/// <summary>A small visitor arriving: where it will appear, and which way it heads.</summary>
public sealed class EcoArrival
{
    public PreyKind Kind;
    public EcoSpot Spot = null!;
    public V2 Patch;
    public bool Landed;
}

/// <summary>
/// The roof over a point: what keeps the rain off, and how high it is (Swift SkyCover).
/// Spans are the actual undersides of things, including their real shape.
/// </summary>
public sealed class SkyCover
{
    readonly record struct Span(double Bottom, double Top, int Owner);
    readonly Dictionary<int, List<Span>> _cols = new();
    public readonly double Reach = 320;
    const double Column = 6;

    public SkyCover(HabitatWorld world)
    {
        foreach (var it in world.Items)
        {
            if (!PlaceSurvey.Counts(it) || it.InFront) continue;
            var d = it.Kind.Definition();
            if (d.Shelf == HabitatShelf.Ground) continue;
            bool shelter = it.Kind.Traits().Functions.Any(f => f is HabitatFunction.Cover or HabitatFunction.Retreat);
            var geo = HabitatGeometry.For(it);
            foreach (var part in geo.Parts)
            {
                if (!shelter && part.Role != ShapeRole.Bulk) continue;
                var b = Poly.Bounds(part.Outline);
                if (b.W < .5 || b.H < .5) continue;
                int c0 = (int)Math.Floor(b.MinX / Column), c1 = (int)Math.Ceiling(b.MaxX / Column);
                for (int c = c0; c <= c1; c++)
                {
                    double x = c * Column;
                    var hits = new List<double>();
                    for (int i = 0; i < part.Outline.Count; i++)
                    {
                        var a = part.Outline[i];
                        var z = part.Outline[(i + 1) % part.Outline.Count];
                        if ((a.X <= x && z.X > x) || (z.X <= x && a.X > x))
                            hits.Add(a.Y + (x - a.X) / (z.X - a.X) * (z.Y - a.Y));
                    }
                    if (hits.Count < 2) continue;
                    hits.Sort();
                    for (int i = 0; i + 1 < hits.Count; i += 2)
                    {
                        if (hits[i + 1] - hits[i] < .3) continue;
                        if (!_cols.TryGetValue(c, out var list)) _cols[c] = list = new();
                        list.Add(new Span(hits[i], hits[i + 1], it.Id));
                    }
                }
            }
        }
        foreach (var list in _cols.Values) list.Sort((a, b) => a.Bottom.CompareTo(b.Bottom));
    }

    static int ColumnOf(double x) => (int)Math.Floor(x / Column);

    public (double H, int Owner)? Roof(double x, double y)
    {
        if (!_cols.TryGetValue(ColumnOf(x), out var spans)) return null;
        foreach (var s in spans)
        {
            double h = s.Bottom - y;
            if (h > 4 && h < Reach && y >= s.Bottom - Reach && y < s.Top) return (h, s.Owner);
        }
        return null;
    }

    /// <summary>How much sky a body-sized thing can see at a point, 0…1.</summary>
    public double OpenAt(V2 p)
    {
        int open = 0;
        foreach (double dx in new[] { -9.0, 0, 9 })
            if (Roof(p.X + dx, p.Y) is null) open++;
        return open / 3.0;
    }

    /// <summary>The undersides in a box, as segments at their lowest visible part.</summary>
    public List<(V2 A, V2 B, int Owner)> Covered(Rect r)
    {
        var result = new List<(V2, V2, int)>();
        int c0 = ColumnOf(r.MinX), c1 = ColumnOf(r.MaxX);
        for (int c = c0; c <= c1; c++)
        {
            if (!_cols.TryGetValue(c, out var spans)) continue;
            foreach (var s in spans)
            {
                if (s.Bottom < r.MinY || s.Bottom > r.MaxY) continue;
                var a = new V2(c * Column, s.Bottom);
                var b = new V2((c + 1) * Column, s.Bottom);
                result.Add((a, b, s.Owner));
            }
        }
        return result;
    }
}

/// <summary>The ecology of the tank: small things, weather, water and what is left over.</summary>
public sealed class HabitatEcology
{
    readonly Rng _rng = new(0x5EED);
    public HabitatWorld World { get; }
    public SurfaceMap Map { get; }
    public PlaceSurvey? Survey { get; private set; }
    public SkyCover Sky { get; private set; }
    public readonly List<EcoSite> Sites = new();
    public readonly List<EcoSpot> Spots = new();
    public readonly List<Droplet> Drops = new();
    public readonly List<Remains> Remains = new();
    public readonly List<EcoArrival> Arrivals = new();
    public double Wetness, Warmth, WindNow;
    double _sinceRain = 99, _dropBudget, _remaining = 10;
    readonly Dictionary<string, double> _sightChance = new();
    public EcoArrival? Carried { get; private set; }

    sealed class LayoutData
    {
        public List<EcoSite> Sites = new();
        public List<EcoSpot> Spots = new();
        public List<(Rect r, bool water, double wet)> Wets = new();
        public List<(int owner, EcoFeature feature)> Fills = new();
        public List<(Rect r, int owner)> Rooms = new();
        public List<Remains> Remains = new();
    }

    public HabitatEcology(HabitatWorld world, SurfaceMap map) { World = world; Map = map; Sky = new SkyCover(world); }

    public void Refresh(PlaceSurvey survey, double scale = .78)
    {
        Survey = survey;
        var layout = MakeLayout(World, Map, survey, Sky, scale);
        Sites.Clear(); Sites.AddRange(layout.Sites);
        Spots.Clear(); Spots.AddRange(layout.Spots);
        Remains.Clear(); Remains.AddRange(layout.Remains);
        _wets = layout.Wets;
        _fills = layout.Fills;
        _rooms = layout.Rooms;
    }

    List<(Rect r, bool water, double wet)> _wets = new();
    List<(int owner, EcoFeature feature)> _fills = new();
    List<(Rect r, int owner)> _rooms = new();

    static LayoutData MakeLayout(HabitatWorld world, SurfaceMap map, PlaceSurvey survey, SkyCover sky, double scale)
    {
        var L = new LayoutData();
        var features = new Dictionary<EcoFeature, List<int>>();
        foreach (var f in Enum.GetValues<EcoFeature>()) features[f] = new();
        bool Has(string s, params string[] words) => words.Any(w => s.Contains(w, StringComparison.OrdinalIgnoreCase));
        foreach (var it in world.Items)
        {
            if (!PlaceSurvey.Counts(it)) continue;
            var d = it.Kind.Definition();
            var tr = it.Kind.Traits();
            var quals = HabitatSemantics.Qualities(world, it);
            string all = $"{d.Label} {d.Note} {it.Kind}".ToLowerInvariant();
            var b = it.Rect;
            void Site(EcoFeature f, double pull)
            {
                var existing = L.Sites.LastOrDefault(s => s.Feature == f && s.On.Contains(it.Id));
                if (existing is null)
                {
                    L.Sites.Add(new EcoSite
                    {
                        Feature = f, Rect = b, Pull = pull,
                        Reach = f is EcoFeature.Damp or EcoFeature.Glow ? 150 : 230
                    });
                }
                else existing.Pull = Math.Max(existing.Pull, pull);
            }

            if (quals[HabitatQuality.SleepingSuitable] >= .35 || tr.Functions.Contains(HabitatFunction.Retreat))
                Site(EcoFeature.Shelter, .4 + quals[HabitatQuality.SleepingSuitable] * .5);
            if (d.Shelf is HabitatShelf.Ground or HabitatShelf.Plants && Has(all, "leaf", "leaves", "litter", "mulch", "bark"))
                Site(EcoFeature.Litter, .55);
            if (quals[HabitatQuality.MoistureSource] >= .3) Site(EcoFeature.Damp, quals[HabitatQuality.MoistureSource]);
            if (tr.Functions.Contains(HabitatFunction.Retreat) && quals[HabitatQuality.Covered] >= .5)
                Site(EcoFeature.Dark, .6);
            if (quals[HabitatQuality.PreyAttracting] >= .25 || Has(all, "fruit", "berry", "nectar", "seed")) Site(EcoFeature.Food, Math.Max(.45, quals[HabitatQuality.PreyAttracting]));
            if (b.W >= 8 && Has(all, "flower", "bloom", "blossom", "lily", "orchid", "daisy", "clover", "sunflower", "rose", "tulip"))
                Site(EcoFeature.Bloom, .7);
            if (tr.Material is HabitatMaterial.Bark or HabitatMaterial.Wood)
                Site(EcoFeature.Bark, .5);
            if (tr.Material is HabitatMaterial.Leaf or HabitatMaterial.Moss || d.Shelf == HabitatShelf.Plants)
                Site(EcoFeature.Foliage, .45);
            if (quals[HabitatQuality.Glowing] >= .2) Site(EcoFeature.Glow, quals[HabitatQuality.Glowing]);
            if (Has(all, "mushroom", "fungus", "fungi", "toadstool")) Site(EcoFeature.Fungus, .5);

            if (it.Kind.CanGoInFront())
                foreach (var (spanA, spanB, owner) in sky.Covered(b))
                {
                    var rr = new Rect(Math.Min(spanA.X, spanB.X), spanA.Y - 6, Math.Abs(spanB.X - spanA.X), 26);
                    if (rr.W > 12) L.Rooms.Add((rr, owner));
                }
            if (it.Water() is { } water)
                L.Wets.Add((water, true, 1));
            else if (quals[HabitatQuality.Wet] > .2 || tr.Aka.Contains("pool", StringComparison.OrdinalIgnoreCase))
                L.Wets.Add((b, false, Math.Max(.6, quals[HabitatQuality.Wet])));
        }

        // Merge sites that share an item and feature, then give each nearby spots.
        var itemOwners = world.Items.GroupBy(i => i.Id).ToDictionary(g => g.Key, g => g.First().Uid);
        foreach (var site in L.Sites)
        {
            var ids = world.Items.Where(i => i.Rect.Intersects(site.Rect) || i.Rect.Contains(site.Rect) ||
                site.Rect.Inset(24).Contains(i.Rect)).Select(i => i.Id);
            foreach (var id in ids)
            {
                if (!site.On.Contains(id)) site.On.Add(id);
                if (itemOwners.TryGetValue(id, out var uid) && !site.Owners.Contains(uid)) site.Owners.Add(uid);
            }
        }

        double floor = HabitatWorld.Ground + map.Standoff;
        foreach (var s in map.SampleSpots(12 * scale, true, scale))
        {
            int owner = map.OwnerOf(s.LoopId, s.SegIdx);
            if (owner != 0 && L.Sites.Any(si => si.On.Contains(owner)) == false) continue;
            if (owner != 0 && world.Items.FirstOrDefault(i => i.Id == owner) is { } own && !PlaceSurvey.Counts(own)) continue;
            var seg = map.SegOf(s.Anchor);
            if (seg is null) continue;
            var surface = s.Point - seg.Normal * map.Standoff;
            bool water = world.Items.Any(i => i.Water() is { } w && w.Inset(2).Contains(surface));
            var spot = new EcoSpot
            {
                Point = s.Point, Surface = surface, Facing = seg.Facing, Owner = owner,
                Glass = (s.Point.X < survey.World.MinX + map.Standoff + 34 * scale || s.Point.X > survey.World.MaxX - map.Standoff - 34 * scale)
                    && s.Point.Y < floor + 150 * scale,
                Open = sky.OpenAt(s.Point) > .5, Water = water,
                Height = s.Point.Y - floor
            };
            L.Spots.Add(spot);
        }
        for (int i = 0; i < L.Sites.Count; i++)
        {
            var site = L.Sites[i];
            int found = 0;
            foreach (var sp in L.Spots)
            {
                bool on = site.On.Contains(sp.Owner) || site.Rect.Inset(16).Contains(sp.Surface) || site.Rect.Inset(16).Contains(sp.Point);
                if (!on) continue;
                sp.Sites.Add(i);
                found++;
            }
            site.Spots = found;
        }
        for (int i = 0; i < L.Spots.Count; i++)
        {
            var sp = L.Spots[i];
            if (L.Wets.Any(w => w.r.Inset(4).Contains(sp.Surface))) sp.Water = true;
        }
        foreach (var w in L.Wets) { }
        L.Remains = new List<Remains>();
        return L;
    }

    static List<V2> TopLines(HabitatItem it, double step)
    {
        var pts = new List<V2>();
        foreach (var outline in HabitatGeometry.For(it).Visual)
        {
            if (outline.Count < 2) continue;
            for (int i = 0; i < outline.Count; i++)
            {
                var a = outline[i];
                var b = outline[(i + 1) % outline.Count];
                double len = a.DistanceTo(b);
                int n = Math.Max(1, (int)Math.Ceiling(len / step));
                for (int k = 0; k <= n; k++) pts.Add(V2.Lerp(a, b, (double)k / n));
            }
        }
        return pts;
    }

    /// <summary>Advance weather, droplets, water and remains (Swift TankEcology.update).</summary>
    public void Update(double dt, WeatherConditions w, double scale = .78)
    {
        dt = M.Clamp(dt, 0, .2);
        Wetness = M.Approach(Wetness, 0, .018, dt);
        bool raining = w.Mix.Rain > .05 || w.Mix.Hail > .04 || w.Mix.Snow > .04;
        if (raining) { _sinceRain = 0; Wetness = Math.Min(1, Wetness + dt * (.05 + w.Mix.Rain * .2)); }
        else _sinceRain += dt;
        double wetting = w.Mix.Rain * .7 + w.Mix.Hail * .5 + w.Mix.Snow * .25 + w.Mix.Fog * .07;
        _dropBudget += wetting * Math.Max(1, WetCount()) * dt * .012;
        while (_dropBudget >= 1)
        {
            _dropBudget -= 1;
            if (Drops.Count >= 200) break;
            var cand = Spots.Where(s => s.Open && s.Facing != EdgeFacing.Down && (s.Owner != 0 || !s.Glass)).ToList();
            if (cand.Count == 0 && _wets.Count > 0)
            {
                var wet = _wets[_rng.RangeInt(0, _wets.Count)];
                cand = Spots.Where(s => s.Facing != EdgeFacing.Down && (s.Owner != 0 || !s.Glass) &&
                    (wet.water || wet.r.Inset(16).Contains(s.Surface))).ToList();
            }
            if (cand.Count == 0) break;
            var at = cand[_rng.RangeInt(0, cand.Count)];
            var p = at.Point + new V2(_rng.Range(-3, 3), _rng.Range(-1, 3));
            if (Drops.Any(d => d.Point.DistanceTo(p) < 5)) continue;
            Drops.Add(new Droplet { Point = p, Size = _rng.Range(.8, 1.8) * scale, Spot = at });
        }
        double drying = (1 - Math.Max(wetting, w.Mix.Sun * .7)) * dt * .015 + w.Mix.Sun * dt * .01;
        for (int i = Drops.Count - 1; i >= 0; i--)
        {
            var d = Drops[i];
            d.Size -= drying;
            if (d.Fall)
            {
                d.Point += new V2(0, -60 * dt);
                var ground = Map.NearestSpot(d.Point, 40 * scale, null, scale);
                if (ground is { } g && d.Point.Y <= g.Point.Y)
                {
                    Drops.RemoveAt(i);
                    Drops.Add(new Droplet { Point = g.Point, Size = Math.Max(.3, d.Size * .7) });
                }
                else if (d.Point.Y < surveyWorldFloor() - 10) Drops.RemoveAt(i);
            }
            else if (d.Size <= .05) Drops.RemoveAt(i);
            else if (_rng.Chance((drying + .006) * dt * 30) && d.Point.Y > HabitatWorld.Ground + 20)
            {
                d.Fall = true;
            }
        }
        Warmth = M.Approach(Warmth, w.Mix.Sun * .8 - w.Mix.Cold * .45 + w.Mix.Heat * .35, .02, dt);
        WindNow = w.WindNow;
        for (int i = Remains.Count - 1; i >= 0; i--)
        {
            var r = Remains[i];
            r.Age += dt;
            r.Life -= dt * (.0009 + Wetness * .004);
            if (r.Life <= 0) Remains.RemoveAt(i);
        }
        _remaining -= dt;
        if (_remaining <= 0)
        {
            _remaining = 12 + _rng.Range(0, 20);
            if (Remains.Count > 0 && Wetness > .25)
            {
                var r = Remains[_rng.RangeInt(0, Remains.Count)];
                if (r is not null) r.Life = Math.Min(r.Life, .3);
            }
        }
        if (Arrivals.Count > 20) Arrivals.RemoveRange(0, Arrivals.Count - 20);
        return;

        int WetCount() => Drops.Count + _wets.Count;
        double surveyWorldFloor() => World.Bounds.MinY;
    }

    public bool SpawnDrop(V2 p)
    {
        if (Drops.Count >= 200) return false;
        Drops.Add(new Droplet { Point = p, Size = 1.2, Fall = false });
        return true;
    }

    public void ShakeDrops(V2 at, double radius, double power)
    {
        foreach (var d in Drops)
            if (!d.Fall && d.Point.DistanceTo(at) < radius) d.Fall = true;
        if (power > 1 && _rng.Chance(.6))
        {
            var near = Spots.Where(s => s.Point.DistanceTo(at) < radius).ToList();
            if (near.Count > 0) AddArrival(EcoFeature.Damp);
        }
    }

    public void AddDroplets(double n, V2 at, double radius)
    {
        for (int i = 0; i < n && Drops.Count < 200; i++)
        {
            var cand = Spots.Where(s => s.Facing != EdgeFacing.Down && s.Point.DistanceTo(at) < radius).ToList();
            if (cand.Count == 0) return;
            var p = cand[_rng.RangeInt(0, cand.Count)].Point;
            if (Drops.Any(d => d.Point.DistanceTo(p) < 4)) continue;
            Drops.Add(new Droplet { Point = p, Size = _rng.Range(.7, 1.5), Spot = cand[_rng.RangeInt(0, cand.Count)] });
        }
    }

    public double HidingPlaces(double x, double y, double radius, double scale = .78)
    {
        double hiding = 0;
        foreach (var site in Sites)
            if (site.Feature.Hides())
                hiding += site.Pull * M.Clamp(1 - Math.Sqrt(Math.Pow(Math.Max(Math.Max(site.Rect.MinX - x, 0), x - site.Rect.MaxX), 2) +
                    Math.Pow(Math.Max(Math.Max(site.Rect.MinY - y, 0), y - site.Rect.MaxY), 2)) / (radius + 40), 0, 1);
        double wet = _wets.Sum(w => M.Clamp(1 - Math.Sqrt(Math.Pow(Math.Max(Math.Max(w.r.MinX - x, 0), x - w.r.MaxX), 2) +
            Math.Pow(Math.Max(Math.Max(w.r.MinY - y, 0), y - w.r.MaxY), 2)) / (radius + 40), 0, 1));
        return (hiding + wet * .5) * .55;
    }

    public double Concealment(V2 p, double scale = .78)
    {
        if (Spots.Count == 0) return 0;
        return M.Clamp(HidingPlaces(p.X, p.Y, 100 * scale, scale) + (1 - Sky.OpenAt(p)) * .6, 0, 1);
    }

    public double PreyPull(V2 p, double scale = .78)
    {
        double pull = 0;
        foreach (var site in Sites)
        {
            if (site.Feature is not (EcoFeature.Food or EcoFeature.Bloom or EcoFeature.Damp or EcoFeature.Fungus)) continue;
            double dx = Math.Max(Math.Max(site.Rect.MinX - p.X, 0), p.X - site.Rect.MaxX);
            double dy = Math.Max(Math.Max(site.Rect.MinY - p.Y, 0), p.Y - site.Rect.MaxY);
            pull += site.Pull * M.Clamp(1 - Math.Sqrt(dx * dx + dy * dy) / (site.Reach * scale), 0, 1);
        }
        return M.Clamp(pull * .8, 0, 1.4);
    }

    public double Light(V2 p, WeatherConditions w, double scale = .78)
    {
        double open = Sky.OpenAt(p);
        double glow = 0;
        foreach (var site in Sites.Where(s => s.Feature is EcoFeature.Glow or EcoFeature.Bloom))
        {
            double dx = Math.Max(Math.Max(site.Rect.MinX - p.X, 0), p.X - site.Rect.MaxX);
            double dy = Math.Max(Math.Max(site.Rect.MinY - p.Y, 0), p.Y - site.Rect.MaxY);
            glow += site.Pull * M.Clamp(1 - Math.Sqrt(dx * dx + dy * dy) / (130 * scale), 0, 1);
        }
        double daylight = (1 - w.Mix.Night * .8 + w.Mix.Dark * .4) * (.45 + w.Mix.Sun * .6 - w.Mix.Storm * .3 - w.Mix.Fog * .25);
        return M.Clamp(open * daylight + glow * .7, 0, 1);
    }

    public double WaterAt(V2 p, double scale = .78) =>
        _wets.Any(w => w.r.Inset(6).Contains(p)) || Spots.Any(s => s.Water && s.Point.DistanceTo(p) < 16 * scale) ? 1 : 0;

    public EcoSpot? NearestSpot(V2 p, double within, Func<EcoSpot, bool>? filter = null)
    {
        EcoSpot? best = null; double bd = within;
        foreach (var s in Spots)
        {
            if (filter is not null && !filter(s)) continue;
            double d = s.Point.DistanceTo(p);
            if (d < bd) { bd = d; best = s; }
        }
        return best;
    }

    public EcoSpot? SpotAt(EcoFeature feature, V2? near = null)
    {
        var choices = Spots.Where(s => s.Sites.Any(i => i >= 0 && i < Sites.Count && Sites[i].Feature == feature)).ToList();
        if (choices.Count == 0) choices = Spots.Where(s => s.Owner != 0).ToList();
        if (choices.Count == 0) choices = Spots.ToList();
        if (choices.Count == 0) return null;
        if (near is not { } p) return choices[_rng.RangeInt(0, choices.Count)];
        var sorted = choices.OrderBy(s => s.Point.DistanceTo(p)).Take(Math.Max(1, Math.Min(12, choices.Count))).ToList();
        return sorted[_rng.WeightedIndex(sorted.Select((s, i) => 1.0 / (1 + i)).ToList())];
    }

    public EcoSpot? Haunt(V2 p, double scale = .78)
    {
        var near = Spots.Where(s => s.Point.DistanceTo(p) < 260 * scale && s.Owner != 0).ToList();
        if (near.Count == 0) return SpotAt(EcoFeature.Shelter, p);
        return near.OrderByDescending(s => Concealment(s.Point, scale) + PreyPull(s.Point, scale) * .5).First();
    }

    public double ArrivalOdds(EcoSpot spot, WeatherConditions w, double scale = .78)
    {
        double pull = PreyPull(spot.Point, scale);
        double hidden = Concealment(spot.Point, scale);
        double open = Sky.OpenAt(spot.Point);
        int nearby = Spots.Count(s => s.Point.DistanceTo(spot.Point) < 90 * scale && s.Water);
        double damp = Math.Max(hidden * .5, _wets.Count > 0 ? .5 : 0);
        return M.Clamp01(pull * .35 + (1 - open) * .15 + damp * .2 + nearby * .1 + .04);
    }

    public double ArrivalGap(WeatherConditions w) =>
        (8 + _rng.Range(0, 14)) * (1 + w.Mix.Rain * .4 - w.Mix.Sun * .3);

    public EcoArrival? AddArrival(EcoFeature? feature = null)
    {
        var spot = feature is { } f ? SpotAt(f) : Haunt(Spots.Count > 0 ? Spots[_rng.RangeInt(0, Spots.Count)].Point : new V2(World.Bounds.Mid.X, World.Bounds.MinY));
        if (spot is null) return null;
        int n = Sites.Count(s => s.Feature == EcoFeature.Food) + Sites.Count(s => s.Feature == EcoFeature.Bloom);
        var kinds = Enum.GetValues<PreyKind>().ToList();
        var weights = kinds.Select(k =>
        {
            var info = Prey.Info(k);
            double weight = 1;
            if (info.Flies) weight += 2;
            if (!info.Climbs && spot.Height > 60) weight *= .2;
            if (spot.Facing == EdgeFacing.Down) weight *= .3;
            return weight;
        }).ToList();
        var kind = kinds[_rng.WeightedIndex(weights)];
        var arrival = new EcoArrival
        {
            Kind = kind,
            Spot = spot,
            Patch = spot.Point + new V2(
                _rng.Range(-70, 70) * (n > 0 ? 1.2 : .5),
                _rng.Range(-40, 90) * (n > 0 ? 1.2 : .5))
        };
        if (Arrivals.Count >= 24) Arrivals.RemoveAt(0);
        Arrivals.Add(arrival);
        return arrival;
    }

    public bool Sighted(EcoArrival arrival, double scale = .78)
    {
        string key = $"{arrival.Kind}:{arrival.Spot.Point}";
        if (_sightChance.TryGetValue(key, out var seen) && seen > .85) return false;
        _sightChance[key] = Math.Min(1, seen + .15);
        return true;
    }

    public void LeaveRemains(V2 p, PreyKind kind)
    {
        if (Remains.Count >= 36) Remains.RemoveAt(0);
        Remains.Add(new Remains { Point = p, Kind = kind, Life = 1 });
    }

    public void Carry(EcoArrival arrival) => Carried = arrival;

    public void DropCarried(V2? near = null)
    {
        if (Carried is null) return;
        if (near is { } p) { LeaveRemains(p, Carried.Kind); Carried = null; return; }
        Carried = null;
    }

    public void RemoveRemains(V2 p, double radius)
    {
        Remains.RemoveAll(r => r.Point.DistanceTo(p) <= radius);
    }
}
