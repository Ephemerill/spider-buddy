namespace SpiderBuddy.Core;

/// <summary>Something a place in the tank can offer, graded 0…1 (Swift PlaceQuality).</summary>
public enum PlaceQuality
{
    Shelter, Elevation, Exposure, Warmth, Moisture, Visibility, Cover, Enclosure, Made,
    PreyActivity, Familiarity, Safety, Novelty, Disturbance, Silk, Rest, Hunting, Water, Access
}

/// <summary>How much of each place quality a spot has.</summary>
public sealed class PlaceQualities
{
    readonly double[] _v = new double[Enum.GetValues<PlaceQuality>().Length];
    public double this[PlaceQuality q]
    {
        get => _v[(int)q];
        set => _v[(int)q] = M.Clamp01(value);
    }
    public bool Has(PlaceQuality q, double atLeast = 0.05) => this[q] >= atLeast;
    public void Raise(PlaceQuality q, double amount) { if (amount > this[q]) this[q] = amount; }
    public override string ToString() => string.Join(", ",
        Enum.GetValues<PlaceQuality>().Where(q => this[q] > .05).Select(q => $"{q} {this[q]:0.##}"));
}

/// <summary>What the spider might go somewhere for.</summary>
public enum PlaceUse { Sleep, Rest, Shelter, Hide, Lookout, Drink, Hunt, Bask, Perch }

/// <summary>A place in the tank: where it stands, what it is at, and what it offers.</summary>
public sealed class HabitatPlace
{
    public string Key = "";
    public InteractionKind? Kind;
    public bool Glass;
    public Anchor Anchor;
    public V2 Point;
    public EdgeFacing Facing;
    public int Owner;
    public int Thing;
    public int RoofOwner;
    public V2? Focus;
    public double Along = 1;
    public PlaceQualities Q = new();

    public bool Standing => Facing == EdgeFacing.Up;
    public bool Hanging => Facing == EdgeFacing.Down;
    public string LoopId => Anchor.LoopId;
    public override string ToString() => $"{Key} {Point} {Facing} {Q}";
}

/// <summary>What it has in mind when choosing somewhere.</summary>
public sealed class PlaceWant
{
    public PlaceUse Use;
    public V2 From;
    public double Scale = .78;
    public Personality Personality = new();
    public V2? Threat;
    public bool Rough;
    public double Sun;
}

/// <summary>What the spider has made of a place, and what is happening there now.</summary>
public sealed class PlaceSense
{
    public HabitatKnowledge.PlaceRecord? Record;
    public double ThingFond;
    public double Disturbance;
    public double Warm;
    public double Prey;
}

/// <summary>
/// Sizes up every walkable surface and every named interaction point in the tank (Swift PlaceSurvey).
/// The survey is rebuilt whenever the layout changes; it never draws anything.
/// </summary>
public sealed class PlaceSurvey
{
    public readonly List<HabitatPlace> Places = new();
    readonly Dictionary<string, int> _byKey = new(StringComparer.Ordinal);
    public readonly List<WaterSpot> Water = new();
    public readonly List<DoorSpot> Doors = new();
    public readonly HashSet<string> Walkable = new(StringComparer.Ordinal);
    public readonly Rect World;
    public readonly double Floor;
    public readonly double Scale;
    public readonly double Standoff;

    public sealed class WaterSpot
    {
        public string Uid = "";
        public int Id;
        public Rect Surface;
        public List<int> Drinks = new();
    }

    public sealed class DoorSpot
    {
        public int Id;
        public Rect Rect;
        public List<(Anchor anchor, V2 point)> Sides = new();
    }

    sealed class SurfaceSeg
    {
        public V2 A, B;
        public EdgeFacing Facing;
        public int Owner;
        public bool Rim;
        public Rect Box;
    }

    sealed class RoofSeg
    {
        public double X0, X1, Y;
        public int Owner;
    }

    readonly List<SurfaceSeg> _segs = new();
    readonly List<RoofSeg> _roofs = new();
    readonly Dictionary<HabitatItem, bool> _built = new();

    public PlaceSurvey(HabitatWorld world, SurfaceMap map, double scale)
    {
        Scale = scale;
        Standoff = map.Standoff;
        World = world.Bounds;
        Floor = HabitatWorld.Ground + Standoff;
        var items = world.Items.GroupBy(i => i.Id).ToDictionary(g => g.Key, g => g.First());
        bool Built(int id) => id != 0 && items.TryGetValue(id, out var it) && it.Kind.BuiltForIt();
        foreach (var it in world.Items) { _built[it] = it.Kind.BuiltForIt(); _thingUids[it.Id] = it.Uid; }

        if (map.Loop("screen:0") is not null)
        {
            var outgoing = map.Junctions.GroupBy(j => j.FromLoop).ToDictionary(g => g.Key, g => g.ToList());
            var frontier = new Stack<string>();
            Walkable.Add("screen:0"); frontier.Push("screen:0");
            while (frontier.Count > 0)
            {
                var id = frontier.Pop();
                if (!outgoing.TryGetValue(id, out var js)) continue;
                foreach (var j in js)
                    if (Walkable.Add(j.ToLoop)) frontier.Push(j.ToLoop);
            }
        }

        foreach (var loop in map.AllLoops)
        {
            for (int i = 0; i < loop.Segs.Count; i++)
            {
                var s = loop.Segs[i];
                _segs.Add(new SurfaceSeg
                {
                    A = s.A, B = s.B, Facing = s.Facing, Owner = loop.OwnerOf(i),
                    Rim = loop.Kind == SurfaceKind.ScreenBorder,
                    Box = new Rect(Math.Min(s.A.X, s.B.X), Math.Min(s.A.Y, s.B.Y), Math.Abs(s.B.X - s.A.X), Math.Abs(s.B.Y - s.A.Y))
                });
            }
        }
        double lid = _segs.Where(s => s.Rim && s.Owner == 0)
            .Select(s => Math.Max(s.A.Y, s.B.Y)).DefaultIfEmpty(HabitatWorld.Ground).Max() - 2;

        // The undersides that keep weather off: the real top of each thing, counted
        // only when it has a body over the point (Swift SkyCover proves the same fact).
        foreach (var it in world.Items)
        {
            if (!Counts(it) || it.InFront) continue;
            var d = it.Kind.Definition();
            if (d.Shelf == HabitatShelf.Ground) continue;
            var geo = HabitatGeometry.For(it);
            bool shelter = it.Kind.Traits().Functions.Any(f => f is HabitatFunction.Cover or HabitatFunction.Retreat);
            foreach (var part in geo.Parts)
            {
                if (!shelter && part.Role != ShapeRole.Bulk) continue;
                var b = Poly.Bounds(part.Outline);
                _roofs.Add(new RoofSeg { X0 = b.MinX, X1 = b.MaxX, Y = b.MinY, Owner = it.Id });
            }
        }

        // Named places on things.
        var used = new HashSet<string>(StringComparer.Ordinal);
        string Unique(string k)
        {
            string key = k; int n = 1;
            while (!used.Add(key)) { key = $"{k}~{n++}"; }
            return key;
        }
        string Cell(V2 p, Rect r)
        {
            int fx = (int)M.Clamp(Math.Floor((p.X - r.MinX) / Math.Max(r.W, 1) * 8), -3, 11);
            int fy = (int)M.Clamp(Math.Floor((p.Y - r.MinY) / Math.Max(r.H, 1) * 8), -3, 11);
            return $"{fx}.{fy}";
        }
        var waters = new Dictionary<int, WaterSpot>();
        foreach (var it in world.Items)
        {
            if (!Counts(it)) continue;
            foreach (var ip in HabitatInteractions.Points(it, map))
            {
                if (ip.Stand is not { } stand || ip.StandPoint is not { } sp) continue;
                var seg = map.SegOf(stand.Anchor);
                if (seg is null) continue;
                var pl = new HabitatPlace
                {
                    Key = Unique($"{it.Uid}:{ip.Kind}:{Cell(sp, it.Rect)}"),
                    Kind = ip.Kind, Anchor = stand.Anchor, Point = sp, Facing = seg.Facing,
                    Owner = map.OwnerOf(stand.Anchor.LoopId, stand.Anchor.SegIdx), Thing = it.Id,
                    Focus = ip.Point
                };
                pl.Along = ip.Kind is InteractionKind.Touch or InteractionKind.Inspect ? ip.Facing
                    : ((ip.Point - sp).Dot(seg.Dir) >= 0 ? 1 : -1);
                if (ip.Kind == InteractionKind.DrinkEdge && it.Water() is { } water)
                {
                    var aim = new V2(M.Clamp(sp.X, water.MinX + water.W * .2, water.MaxX - water.W * .2), water.MaxY - water.H * .3);
                    pl.Focus = aim;
                    pl.Along = (aim - sp).Dot(seg.Dir) >= 0 ? 1 : -1;
                    if (!waters.TryGetValue(it.Id, out var ws))
                        waters[it.Id] = ws = new WaterSpot { Uid = it.Uid, Id = it.Id, Surface = water };
                    ws.Drinks.Add(Places.Count);
                }
                Places.Add(pl);
            }
        }
        Water.AddRange(waters.Values.OrderBy(w => w.Id));

        // Everywhere else on the surfaces, one place per small patch.
        var named = new Dictionary<long, List<V2>>();
        long Bucket(V2 p) => (long)Math.Floor(p.X / 40) * 100_003 + (long)Math.Floor(p.Y / 40);
        foreach (var pl in Places)
            (named.TryGetValue(Bucket(pl.Point), out var list) ? list : named[Bucket(pl.Point)] = new()).Add(pl.Point);
        bool NearNamed(V2 p)
        {
            long bx = (long)Math.Floor(p.X / 40), by = (long)Math.Floor(p.Y / 40);
            for (int dx = -1; dx <= 1; dx++) for (int dy = -1; dy <= 1; dy++)
                if (named.TryGetValue((bx + dx) * 100_003 + (by + dy), out var list) &&
                    list.Any(q => q.DistanceTo(p) < 14 * scale)) return true;
            return false;
        }
        double glassBand = 34 * scale;
        foreach (var s in map.SampleSpots(24 * scale, true, scale))
        {
            if (NearNamed(s.Point)) continue;
            int owner = map.OwnerOf(s.LoopId, s.SegIdx);
            if (owner != 0 && items.TryGetValue(owner, out var owned) && !Counts(owned)) continue;
            var seg = map.SegOf(s.Anchor);
            if (seg is null) continue;
            bool glass = (s.Point.X < World.MinX + Standoff + glassBand || s.Point.X > World.MaxX - Standoff - glassBand)
                && s.Point.Y < Floor + 150 * scale && seg.Facing != EdgeFacing.Down;
            string key;
            if (owner != 0 && items.TryGetValue(owner, out var own))
                key = $"{own.Uid}:spot:{Cell(s.Point, own.Rect)}";
            else
                key = $"tank:{(int)Math.Floor(s.Point.X / 32)}.{(int)Math.Floor(s.Point.Y / 32)}:{seg.Facing}";
            if (!used.Add(key)) continue;
            var pl = new HabitatPlace
            {
                Key = key, Glass = glass, Anchor = s.Anchor, Point = s.Point,
                Facing = seg.Facing, Owner = owner, Thing = owner
            };
            if (glass) pl.Along = (s.Point.X < World.Mid.X ? -1 : 1) * (seg.Dir.X >= 0 ? 1 : -1);
            Places.Add(pl);
        }

        // Shut doors, and a floor spot either side of them.
        foreach (var it in world.Items.Where(i => i.Kind == HabitatItemKind.DoorClosed))
        {
            var sides = new List<(Anchor, V2)>();
            foreach (var side in new[] { -1.0, 1.0 })
            {
                double x = side < 0 ? it.Rect.MinX - 30 * scale : it.Rect.MaxX + 30 * scale;
                var s = map.NearestSpot(new V2(x, it.Rect.MinY + 30 * scale), 80 * scale, null, scale);
                if (s is { } hit && Math.Abs(hit.Point.Y - (it.Rect.MinY + Standoff)) < 30 * scale)
                    sides.Add((hit.Anchor, hit.Point));
            }
            if (sides.Count > 0) Doors.Add(new DoorSpot { Id = it.Id, Rect = it.Rect, Sides = sides });
        }

        // What each offers.
        var warmers = new List<(Rect r, double w)>();
        var damp = new List<(Rect r, double w)>();
        var lures = new List<(Rect r, double w)>();
        foreach (var it in world.Items.Where(Counts))
        {
            var q = HabitatSemantics.Qualities(world, it);
            double warm = Math.Max(q[HabitatQuality.Warm], q[HabitatQuality.Glowing] * .75);
            if (warm > .3) warmers.Add((it.Rect, warm));
            if (q[HabitatQuality.MoistureSource] > .3) damp.Add((it.Rect, q[HabitatQuality.MoistureSource]));
            if (q[HabitatQuality.PreyAttracting] > .3) lures.Add((it.Rect, q[HabitatQuality.PreyAttracting]));
        }
        for (int i = 0; i < Places.Count; i++)
        {
            var pl = Places[i];
            var p = pl.Point;
            var q = new PlaceQualities();
            double cov = 0, madeCov = 0, roofH = double.MaxValue;
            bool overhead = false;
            foreach (double dx in new[] { -12 * scale, 0, 12 * scale })
            {
                var r = RoofAt(p.X + dx, p.Y, 320 * scale);
                if (r is null) continue;
                double c = M.Clamp(1.2 - (r.Value.H - Standoff) / (280 * scale), .25, 1);
                cov += c / 3;
                if (Built(r.Value.Owner)) madeCov += c / 3;
                if (r.Value.H < roofH) { roofH = r.Value.H; pl.RoofOwner = r.Value.Owner; }
                if (Math.Abs(dx) < .01) overhead = true;
            }
            if (!overhead) { cov *= .3; madeCov *= .3; }
            if (pl.Hanging)
            {
                bool under = new[] { -10 * scale, 10 * scale }.All(dx =>
                {
                    var r = RoofAt(p.X + dx, p.Y, 320 * scale);
                    return r is { } v && v.H < Standoff * 1.8;
                });
                double c = pl.Owner == 0 ? .3 : (under ? .8 : .4);
                cov = Math.Max(cov, c);
                if (Built(pl.Owner)) madeCov = Math.Max(madeCov, c);
                pl.RoofOwner = pl.Owner;
                roofH = 0;
            }
            var wl = WallAt(p, -1, 150 * scale);
            var wr = WallAt(p, 1, 150 * scale);
            double Strength((double d, int owner, bool glass)? w) =>
                w is { } x ? M.Clamp(1 - x.d / (150 * scale), 0, 1) * (x.glass ? .5 : 1) : 0;
            double sl = Strength(wl), sr = Strength(wr);
            double madeWalls = (wl is { } l && Built(l.owner) ? sl : 0) + (wr is { } rr && Built(rr.owner) ? sr : 0);
            double enc = M.Clamp(.5 * cov + .25 * (sl + sr), 0, 1);
            if (pl.Kind == InteractionKind.Interior) { enc = Math.Max(enc, .95); cov = Math.Max(cov, .9); }
            if (pl.Kind == InteractionKind.Entrance) enc = Math.Max(enc, .55);
            double elev = M.Clamp((p.Y - Floor) / (300 * scale), 0, 1);
            var underQ = pl.Owner == 0 ? new HabitatQualities() : HabitatSemantics.Qualities(world, items[pl.Owner]);
            double made = M.Clamp(.85 * madeCov + .15 * Math.Min(madeWalls, 1) * Math.Min(cov * 2, 1), 0, 1);
            if (Built(pl.Owner) && pl.Standing && underQ[HabitatQuality.SleepingSuitable] >= .5) made = Math.Max(made, .7);
            q[PlaceQuality.Cover] = cov;
            q[PlaceQuality.Enclosure] = enc;
            q[PlaceQuality.Made] = made;
            q[PlaceQuality.Shelter] = M.Clamp(.75 * cov + .35 * enc, 0, 1);
            q[PlaceQuality.Elevation] = elev;
            q[PlaceQuality.Exposure] = M.Clamp(1 - .85 * cov - .2 * enc + .15 * elev, 0, 1);
            double warm = underQ[HabitatQuality.Warm] * (pl.Owner != 0 ? 1 : 0);
            foreach (var (r, w) in warmers) warm = Math.Max(warm, w * M.Clamp(1 - Gap(r, p) / (110 * scale), 0, 1));
            q[PlaceQuality.Warmth] = warm;
            double wet = underQ[HabitatQuality.Wet] * (pl.Owner != 0 ? .8 : 0);
            foreach (var (r, m) in damp) wet = Math.Max(wet, m * M.Clamp(1 - Gap(r, p) / (140 * scale), 0, 1));
            q[PlaceQuality.Moisture] = wet;
            q[PlaceQuality.Water] = pl.Kind == InteractionKind.DrinkEdge ? 1 : 0;
            q[PlaceQuality.Silk] = Math.Max(pl.Hanging ? .6 : 0,
                Math.Max(roofH < 90 * scale + Standoff ? .45 : 0, Math.Max(underQ[HabitatQuality.SilkAnchor] * .8, pl.Kind == InteractionKind.SilkAnchor ? 1 : 0)));
            double prey = 0;
            foreach (var (r, v) in lures) prey = Math.Max(prey, v * M.Clamp(1 - Gap(r, p) / (220 * scale), 0, 1) * .7);
            q[PlaceQuality.PreyActivity] = prey;
            q[PlaceQuality.Access] = Walkable.Contains(pl.Anchor.LoopId) ? 1 : .35;
            double lie = pl.Standing ? 1 : (pl.Hanging ? .8 : .35);
            q[PlaceQuality.Rest] = M.Clamp(lie * (.5 + .3 * cov + .2 * enc) + .3 * underQ[HabitatQuality.SleepingSuitable] + (pl.Kind == InteractionKind.Interior ? .15 : 0), 0, 1);
            q[PlaceQuality.Safety] = M.Clamp(.4 * enc + .35 * cov + .25 * (1 - q[PlaceQuality.Exposure]), 0, 1);
            q[PlaceQuality.Novelty] = M.Clamp(underQ[HabitatQuality.Interesting], 0, 1);
            if (pl.Kind is null && !pl.Glass && cov > .3 && map.SegOf(pl.Anchor) is { } s && Math.Abs(s.Dir.X) > .5)
            {
                double dl = wl?.d ?? double.MaxValue, dr = wr?.d ?? double.MaxValue;
                double outward = dl < dr ? 1 : -1;
                pl.Along = outward * (s.Dir.X >= 0 ? 1 : -1);
            }
            pl.Q = q;
        }

        // How far each high place can see: a fan of looks, only where that matters.
        double reach = 600 * scale;
        for (int i = 0; i < Places.Count; i++)
        {
            var pl = Places[i];
            bool high = pl.Q[PlaceQuality.Elevation] > .2 && pl.Standing;
            bool namedHigh = pl.Kind is InteractionKind.Top or InteractionKind.Perch or InteractionKind.Lookout;
            if (!high && !namedHigh)
            {
                pl.Q[PlaceQuality.Visibility] = M.Clamp(.25 * (1 - pl.Q[PlaceQuality.Enclosure]) + .3 * pl.Q[PlaceQuality.Elevation], 0, 1);
                pl.Q[PlaceQuality.Hunting] = M.Clamp(.35 * pl.Q[PlaceQuality.Visibility] + .45 * pl.Q[PlaceQuality.PreyActivity] +
                    .25 * (pl.Owner == 0 ? 0 : HabitatSemantics.Qualities(world, items[pl.Owner])[HabitatQuality.HuntingSuitable]), 0, 1);
                continue;
            }
            var n = pl.Facing.Normal();
            var o = pl.Point + n * 3;
            double free = 0;
            (double len, V2 dir)? best = null;
            for (int k = 0; k < 12; k++)
            {
                double a = (-110 + k * 20) * Math.PI / 180;
                var d = n.Rotated(a);
                double len = Sight(o, d, reach);
                free += len / reach / 12;
                if (d.Y < .5 && len > (best?.len ?? 0)) best = (len, d);
            }
            pl.Q[PlaceQuality.Visibility] = M.Clamp(.6 * free + .4 * pl.Q[PlaceQuality.Elevation], 0, 1);
            pl.Q[PlaceQuality.Hunting] = M.Clamp(.35 * pl.Q[PlaceQuality.Visibility] + .2 * pl.Q[PlaceQuality.Elevation] +
                .45 * pl.Q[PlaceQuality.PreyActivity] + .25 * (pl.Owner == 0 ? 0 : HabitatSemantics.Qualities(world, items[pl.Owner])[HabitatQuality.HuntingSuitable]), 0, 1);
            if (best is { } b && pl.Kind != InteractionKind.DrinkEdge)
            {
                var view = pl.Point + b.dir * b.len * .8;
                pl.Focus = view;
                if (map.SegOf(pl.Anchor) is { } seg) pl.Along = (view - pl.Point).Dot(seg.Dir) >= 0 ? 1 : -1;
            }
        }

        foreach (var pl in Places) _byKey[pl.Key] = Places.IndexOf(pl);
    }

    public static bool Counts(HabitatItem it) =>
        !it.Kind.IsBacking() && it.Definition.Layer != HabitatLayer.Rear && it.Definition.Shelf != HabitatShelf.Walls;

    (double H, int Owner, bool Lid)? RoofAt(double x, double y, double reach)
    {
        (double H, int Owner, bool Lid)? best = null;
        foreach (var r in _roofs)
        {
            if (x < r.X0 || x > r.X1) continue;
            double h = r.Y - y;
            if (h <= 4 || h >= reach) continue;
            if (best is null || h < best.Value.H) best = (h, r.Owner, false);
        }
        return best;
    }

    (double d, int owner, bool glass)? WallAt(V2 p, double dir, double reach)
    {
        (double d, int owner, bool glass)? best = null;
        foreach (var s in _segs)
        {
            if (dir > 0 ? s.Facing != EdgeFacing.Right : s.Facing != EdgeFacing.Left) continue;
            if (p.Y < s.Box.MinY - 2 || p.Y > s.Box.MaxY + 2) continue;
            double x = Math.Abs(s.B.Y - s.A.Y) > .01 ? s.A.X + (s.B.X - s.A.X) * (p.Y - s.A.Y) / (s.B.Y - s.A.Y) : (s.Box.MinX + s.Box.MaxX) / 2;
            double d = (x - p.X) * dir;
            if (d <= -3 || d >= reach) continue;
            if (best is null || d < best.Value.d) best = (Math.Max(d, 0), s.Owner, s.Rim && s.Owner == 0);
        }
        return best;
    }

    double Sight(V2 o, V2 d, double len)
    {
        double best = len;
        foreach (var s in _segs)
        {
            var sd = s.B - s.A;
            double den = d.Cross(sd);
            if (Math.Abs(den) < 1e-9) continue;
            var w = s.A - o;
            double u = w.Cross(sd) / den, v = w.Cross(d) / den;
            if (u > 8 && u < best && v >= 0 && v <= 1) best = u;
        }
        return best;
    }

    static double Gap(Rect r, V2 p)
    {
        double dx = Math.Max(Math.Max(r.MinX - p.X, 0), p.X - r.MaxX);
        double dy = Math.Max(Math.Max(r.MinY - p.Y, 0), p.Y - r.MaxY);
        return Math.Sqrt(dx * dx + dy * dy);
    }

    public HabitatPlace? Place(string key) => _byKey.TryGetValue(key, out int i) ? Places[i] : null;

    public HabitatPlace? Nearest(V2 p, double within)
    {
        HabitatPlace? best = null; double bd = within;
        foreach (var pl in Places)
        {
            double d = pl.Point.DistanceTo(p);
            if (d < bd) { bd = d; best = pl; }
        }
        return best;
    }

    public PlaceQualities Sensed(HabitatPlace pl, PlaceSense sense)
    {
        var q = new PlaceQualities();
        foreach (var quality in Enum.GetValues<PlaceQuality>()) q[quality] = pl.Q[quality];
        var r = sense.Record;
        double fam = r is null ? 0 : 1 - Math.Exp(-r.Visits / 4);
        double disturb = M.Clamp01(sense.Disturbance + Math.Min(r?.Frights ?? 0, 1) * .7);
        q[PlaceQuality.Familiarity] = fam;
        q[PlaceQuality.Novelty] = M.Clamp(pl.Q[PlaceQuality.Novelty] * (1 - fam) + (r is null ? .3 : 0), 0, 1);
        q[PlaceQuality.Disturbance] = disturb;
        q[PlaceQuality.Safety] = M.Clamp(pl.Q[PlaceQuality.Safety] * .75 + fam * .25 - disturb * .6, 0, 1);
        q[PlaceQuality.PreyActivity] = M.Clamp(pl.Q[PlaceQuality.PreyActivity] + (r?.Catches ?? 0) * .35 +
            (r?.Sightings ?? 0) * .15 + sense.Prey * .6, 0, 1);
        if (pl.Standing) q[PlaceQuality.Warmth] = Math.Max(q[PlaceQuality.Warmth], Math.Min(1, sense.Warm * 1.1));
        return q;
    }

    public double Appeal(HabitatPlace pl, PlaceWant want, PlaceSense sense)
    {
        var q = Sensed(pl, sense);
        double sc = want.Scale;
        var P = want.Personality;
        var r = sense.Record;
        double fam = q[PlaceQuality.Familiarity];
        double fond = r is not null && r.Fond.TryGetValue(want.Use.ToString().ToLowerInvariant(), out var f) ? f : 0;
        double disturb = q[PlaceQuality.Disturbance], safety = q[PlaceQuality.Safety];
        double d = pl.Point.DistanceTo(want.From);
        double Far(double k) => 1 / (1 + d / (k * sc));
        double made = q[PlaceQuality.Made];
        double s;
        switch (want.Use)
        {
            case PlaceUse.Shelter:
                if (q[PlaceQuality.Cover] < .35) return 0;
                s = 1.2 * q[PlaceQuality.Cover] + .5 * q[PlaceQuality.Enclosure] + 1.6 * made + .3 * fam +
                    .6 * fond + .2 * q[PlaceQuality.Access] - .3 * q[PlaceQuality.Exposure] - .4 * disturb;
                s *= Far(700); break;
            case PlaceUse.Hide:
                if (q[PlaceQuality.Enclosure] < .3 && q[PlaceQuality.Cover] < .55) return 0;
                s = q[PlaceQuality.Enclosure] + .6 * q[PlaceQuality.Cover] + 1.6 * made + .5 * safety +
                    .5 * fond + .3 * fam - .6 * disturb;
                if (want.Threat is { } th)
                {
                    double away = pl.Point.DistanceTo(th);
                    s += .4 * M.Clamp(away / (400 * sc), 0, 1) - (away < 90 * sc ? .9 : 0);
                }
                s *= Far(550); break;
            case PlaceUse.Sleep:
                if (pl.Facing != EdgeFacing.Up && pl.Facing != EdgeFacing.Down && q[PlaceQuality.Enclosure] <= .6) return 0;
                s = .8 * q[PlaceQuality.Rest] + .45 * q[PlaceQuality.Cover] + .35 * q[PlaceQuality.Enclosure] +
                    1.4 * made + .5 * safety + .5 * fam + 1.4 * fond - .8 * disturb +
                    (P.Bravery - .5) * .5 * q[PlaceQuality.Elevation];
                if (want.Rough) s -= .5 * q[PlaceQuality.Exposure];
                s *= Far(1500); break;
            case PlaceUse.Rest:
                s = .7 * q[PlaceQuality.Rest] + .25 * q[PlaceQuality.Cover] + .2 * q[PlaceQuality.Enclosure] +
                    .8 * made + .25 * q[PlaceQuality.Warmth] + .3 * safety + .35 * fam + 1.3 * fond - .6 * disturb;
                s *= Far(800); break;
            case PlaceUse.Lookout:
                if (q[PlaceQuality.Elevation] < .25 || !pl.Standing) return 0;
                s = q[PlaceQuality.Elevation] + 1.1 * q[PlaceQuality.Visibility] + .3 * fam + 1.2 * fond -
                    .3 * q[PlaceQuality.Cover] - .4 * disturb + (pl.Kind == InteractionKind.Lookout ? .3 : 0);
                s *= Far(1100); break;
            case PlaceUse.Drink:
                if (q[PlaceQuality.Water] < .9) return 0;
                s = 1 + .4 * fam + .8 * fond + .3 * q[PlaceQuality.Access] - .5 * disturb;
                s *= Far(900); break;
            case PlaceUse.Hunt:
                if (q[PlaceQuality.PreyActivity] <= .15 || pl.Facing == EdgeFacing.Down) return 0;
                s = q[PlaceQuality.PreyActivity] + .35 * q[PlaceQuality.Hunting] + .25 * q[PlaceQuality.Visibility] +
                    .2 * q[PlaceQuality.Elevation] + .8 * fond - .3 * disturb;
                s *= Far(900); break;
            case PlaceUse.Bask:
                double warm = Math.Max(q[PlaceQuality.Warmth], pl.Standing ? want.Sun * q[PlaceQuality.Exposure] * .8 : 0);
                if (warm < .3) return 0;
                s = 1.2 * warm + .3 * fam + .7 * fond - .3 * disturb;
                s *= Far(900); break;
            default:
                if (pl.Owner == 0 || !pl.Standing || q[PlaceQuality.Elevation] <= .05) return 0;
                s = .4 * q[PlaceQuality.Elevation] + .3 * q[PlaceQuality.Visibility] + .3 * q[PlaceQuality.Rest] +
                    1.3 * fond + Math.Max(sense.ThingFond, 0) + .3 * fam - .6 * disturb;
                s *= Far(1000); break;
        }
        return Math.Max(s, 0);
    }

    public List<(HabitatPlace place, double score)> Ranked(PlaceWant want, Func<HabitatPlace, PlaceSense?> sense, int top = 8)
    {
        var outList = new List<(HabitatPlace, double)>();
        foreach (var pl in Places)
        {
            var s = sense(pl);
            if (s is null) continue;
            double a = Appeal(pl, want, s);
            if (a > .05) outList.Add((pl, a));
        }
        return outList.OrderByDescending(x => x.Item2).Take(top).ToList();
    }

    public PlaceSense SenseFor(HabitatPlace pl, HabitatKnowledge knowledge, double disturbance = 0, double warm = 0, double prey = 0)
    {
        knowledge.Places.TryGetValue(pl.Key, out var record);
        double thingFond = pl.Owner == 0 ? 0 : knowledge.For(knowledgeItemUid(pl)).Fond;
        return new PlaceSense { Record = record, ThingFond = thingFond, Disturbance = disturbance, Warm = warm, Prey = prey };

        string knowledgeItemUid(HabitatPlace place)
        {
            if (place.Thing == 0) return "";
            return _thingUids.TryGetValue(place.Thing, out var uid) ? uid : "";
        }
    }

    readonly Dictionary<int, string> _thingUids = new();

    public string OwnerUid(int id) => _thingUids.TryGetValue(id, out var uid) ? uid : "";

}

public static class HabitatPlaceUse
{
    /// <summary>The saved lower-case name of a place use (the key in PlaceRecord.Fond).</summary>
    public static string Key(this PlaceUse use) => use.ToString().ToLowerInvariant();
    public static bool Hides(this EcoFeature feature) => feature is EcoFeature.Litter or EcoFeature.Bark or EcoFeature.Dark;
}

/// <summary>Where two surfaces meet, as place memory knows it (a moved thing is a new way).</summary>
public static class HabitatRouteKey
{
    public static string Of(SurfaceJunction j) => $"{(int)Math.Round(j.At.X / 8)}.{(int)Math.Round(j.At.Y / 8)}";
}
