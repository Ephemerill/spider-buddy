using System.Text.Json.Nodes;

namespace SpiderBuddy.Core;

/// <summary>What each kind is to the spider: nature by rule, then the situation where it stands.</summary>
public static class HabitatSemantics
{
    static readonly Dictionary<HabitatItemKind, HabitatQualities> Cache = new();

    public static HabitatQualities Nature(HabitatItemKind kind)
    {
        if (Cache.TryGetValue(kind, out var cached)) return cached;
        var d = kind.Definition();
        var tr = kind.Traits();
        var g = HabitatGeometry.ForKind(kind, new Rect(0, 0, d.Width, d.Height), 0, 1);
        bool solid = d.Category == HabitatCategory.Perch && g.Parts.Count > 0;
        bool water = tr.Functions.Contains(HabitatFunction.Water) || tr.Material == HabitatMaterial.Water;
        bool hollow = g.Hollows.Count > 0 || g.Anchors.Any(a => a.Kind is AnchorKind.Refuge or AnchorKind.Entrance);
        double sway = M.Clamp01(d.Sway / .03);
        double over = solid ? Overhang(g, d.Size, d.Placement is HabitatPlacement.Wedged or HabitatPlacement.Hangs) : 0;
        double foliage = g.Visual.Sum(v => Math.Abs(Poly.Area(v))) / Math.Max(1, d.Width * d.Height);
        var q = new HabitatQualities();
        q[HabitatQuality.Climbable] = solid ? M.Clamp(.55 + d.Height / 250, .55, 1) : 0;
        q[HabitatQuality.Perchable] = solid
            ? Math.Max(M.Clamp(WidestFlat(g) / 40, 0, 1), g.Anchors.Any(a => a.Kind == AnchorKind.Perch) ? .8 : 0) : 0;
        q[HabitatQuality.Sheltering] = Math.Max(tr.Functions.Contains(HabitatFunction.Cover) || tr.Functions.Contains(HabitatFunction.Retreat) ? 1 : 0,
            Math.Max(hollow ? .85 : 0, over));
        q[HabitatQuality.Hideable] = Math.Max(tr.Functions.Contains(HabitatFunction.Retreat) ? 1 : 0,
            Math.Max(hollow ? .9 : 0, Math.Max(M.Clamp(foliage * 1.2, 0, .6), kind.CanGoInFront() && d.Height > 30 ? .4 : 0)));
        q[HabitatQuality.Enclosed] = Math.Max(hollow ? 1 : 0,
            Math.Max(tr.Functions.Contains(HabitatFunction.Retreat) ? .9 : 0, tr.Functions.Contains(HabitatFunction.Cover) ? .35 : 0));
        q[HabitatQuality.Elevated] = Math.Max(tr.Functions.Contains(HabitatFunction.Lookout) ? 1 : 0,
            Math.Max(d.Placement == HabitatPlacement.Hangs ? .8 : 0, solid ? M.Clamp((d.Height - 120) / 200, 0, .6) : 0));
        q[HabitatQuality.Hanging] = d.Placement == HabitatPlacement.Hangs ? 1 : 0;
        q[HabitatQuality.Drinkable] = water ? 1 : 0;
        q[HabitatQuality.Wet] = Math.Max(water ? .9 : 0, Math.Max(tr.Functions.Contains(HabitatFunction.Humid) ? .7 : 0, tr.Damp ? .3 : 0));
        q[HabitatQuality.MoistureSource] = Math.Max(water ? 1 : 0, Math.Max(tr.Functions.Contains(HabitatFunction.Humid) ? .9 : 0,
            Math.Max(tr.Damp ? .45 : 0, tr.Material == HabitatMaterial.Moss ? .4 : 0)));
        q[HabitatQuality.Warm] = Math.Max(tr.Functions.Contains(HabitatFunction.Basking) ? 1 : 0, tr.Material == HabitatMaterial.Stone ? .25 : 0);
        q[HabitatQuality.Cool] = Math.Max(water ? .8 : 0, Math.Max(tr.Functions.Contains(HabitatFunction.Humid) ? .7 : 0,
            Math.Max(tr.Material == HabitatMaterial.Moss ? .5 : 0, Math.Max(tr.Damp ? .4 : 0, Math.Max(hollow ? .45 : 0, over * .4)))));
        q[HabitatQuality.Organic] = tr.Material is not (HabitatMaterial.Stone or HabitatMaterial.Crystal or HabitatMaterial.Sand or HabitatMaterial.Water or HabitatMaterial.Made) ? 1 : 0;
        q[HabitatQuality.Artificial] = tr.Material == HabitatMaterial.Made || !d.Shelf.Natural() ? 1 : 0;
        q[HabitatQuality.Movable] = tr.Loose is not null ? 1 : 0;
        q[HabitatQuality.Lightweight] = tr.Loose is { } lb ? M.Clamp(1.2 - lb.Mass / 8, .2, 1) : 0;
        q[HabitatQuality.Flexible] = Math.Max(sway, d.Placement == HabitatPlacement.Hangs && d.Stretch == HabitatStretch.Vertical ? .6 : 0);
        q[HabitatQuality.Moving] = Math.Max(sway, tr.Loose is null ? 0 : .25);
        q[HabitatQuality.PreyAttracting] = Math.Max(tr.Functions.Contains(HabitatFunction.Feeding) ? 1 : 0,
            Math.Max(water ? .4 : 0, Math.Max(tr.Material == HabitatMaterial.Fungus ? .35 : 0, tr.Damp ? .3 : 0)));
        q[HabitatQuality.SilkAnchor] = Math.Max(tr.Functions.Contains(HabitatFunction.Silk) ? 1 : 0,
            Math.Max(g.Anchors.Any(a => a.Kind == AnchorKind.Tie) ? .8 : 0,
                Math.Max(solid && g.Parts.Any(p => p.Role == ShapeRole.Limb) ? .6 : 0, Math.Max(over * .7, solid ? .25 : 0))));
        q[HabitatQuality.SleepingSuitable] = Math.Max(tr.Functions.Contains(HabitatFunction.Retreat) ? 1 : 0,
            Math.Max(hollow ? .8 : 0, Math.Max(tr.Functions.Contains(HabitatFunction.Cover) ? .55 : 0, over * .4)));
        q[HabitatQuality.LookoutSuitable] = Math.Max(tr.Functions.Contains(HabitatFunction.Lookout) ? 1 : 0,
            q[HabitatQuality.Perchable] * M.Clamp((d.Height - 60) / 180, 0, .8));
        foreach (var (quality, amount) in tr.Extra) q.Raise(quality, amount);
        q.Raise(HabitatQuality.HuntingSuitable, Math.Max(q[HabitatQuality.PreyAttracting] *
            Math.Max(q[HabitatQuality.Perchable], q[HabitatQuality.Climbable] * .6), q[HabitatQuality.LookoutSuitable] * .6));
        q.Raise(HabitatQuality.Interesting, .35 + .25 * q[HabitatQuality.Glowing] + .2 * q[HabitatQuality.Moving] +
            (hollow ? .15 : 0) + .1 * q[HabitatQuality.Drinkable] + .1 * q[HabitatQuality.PreyAttracting] + (g.Parts.Count > 3 ? .1 : 0));
        Cache[kind] = q;
        return q;
    }

    static double WidestFlat(ObjectGeometry g)
    {
        double best = 0;
        foreach (var line in g.TopLines(4))
        {
            double run = 0;
            for (int i = 1; i < line.Count; i++)
            {
                double dx = Math.Abs(line[i].X - line[i - 1].X);
                if (dx > .01 && Math.Abs(line[i].Y - line[i - 1].Y) / dx < .35) run += dx;
                else run = 0;
                best = Math.Max(best, run);
            }
        }
        return best;
    }

    static double Overhang(ObjectGeometry g, SizeD size, bool aloft)
    {
        var b = g.Bounds;
        if (b.W <= 1) return 0;
        int n = 24, clear = 0, some = 0;
        for (int k = 0; k < n; k++)
        {
            double x = b.MinX + b.W * (k + .5) / n, low = double.MaxValue;
            foreach (var part in g.Parts)
            {
                var o = part.Outline;
                for (int i = 0; i < o.Count; i++)
                {
                    var a = o[i]; var c = o[(i + 1) % o.Count];
                    if ((a.X - x) * (c.X - x) <= 0 && Math.Abs(c.X - a.X) > 1e-6)
                        low = Math.Min(low, a.Y + (c.Y - a.Y) * (x - a.X) / (c.X - a.X));
                }
            }
            if (low >= double.MaxValue) continue;
            some++;
            if (aloft || low >= b.MinY + 30) clear++;
        }
        if (some == 0) return 0;
        double share = (double)clear / n;
        return M.Clamp(share * M.Clamp(share * b.W / 50, 0, 1) * (aloft ? .8 : 1), 0, 1);
    }

    public static HabitatQualities Qualities(HabitatWorld world, HabitatItem item)
    {
        var q = Nature(item.Kind);
        double up = item.Kind.Hangs() ? 1 : M.Clamp((item.Y - 24) / 140, 0, 1);
        q.Raise(HabitatQuality.Elevated, up);
        double roof = Cover(world, item);
        q[HabitatQuality.Covered] = Math.Max(roof, q[HabitatQuality.Enclosed] * .8);
        q[HabitatQuality.Exposed] = 1 - roof;
        if (up > .3) q.Raise(HabitatQuality.LookoutSuitable, q[HabitatQuality.Perchable] * up * .7);
        return q;
    }

    public static double Cover(HabitatWorld world, HabitatItem item)
    {
        var r = item.Rect;
        if (r.W <= 1) return 0;
        var spans = new List<(double, double)>();
        foreach (var o in world.Items)
        {
            if (o.Id == item.Id || o.Kind.IsBacking() || o.Kind.Definition().Shelf == HabitatShelf.Walls) continue;
            var q = o.Rect;
            if (q.MaxX <= r.MinX || q.MinX >= r.MaxX || q.MinY < r.MaxY - 6 || q.MinY - r.MaxY >= 320) continue;
            spans.Add((Math.Max(q.MinX, r.MinX), Math.Min(q.MaxX, r.MaxX)));
        }
        spans.Sort((a, b) => a.Item1.CompareTo(b.Item1));
        double len = 0, reach = r.MinX;
        foreach (var (a, b) in spans)
            if (b > reach) { len += b - Math.Max(a, reach); reach = b; }
        return M.Clamp(len / r.W, 0, 1);
    }

    public static Rect? WaterArea(this HabitatItemKind kind) => kind switch
    {
        HabitatItemKind.WaterDish => new Rect(.1, .45, .8, .36),
        HabitatItemKind.RockPool => new Rect(.16, .75, .68, .16),
        HabitatItemKind.Puddle => new Rect(.08, .05, .84, .8),
        _ => null
    };
    public static Rect? Water(this HabitatItem item)
    {
        var f = item.Kind.WaterArea();
        if (f is null) return null;
        var r = item.Rect;
        return new Rect(r.MinX + r.W * f.Value.X, r.MinY + r.H * f.Value.Y, r.W * f.Value.W, r.H * f.Value.H);
    }
    public static bool BuiltForIt(this HabitatItemKind k) =>
        k.Definition().Shelf is HabitatShelf.Built or HabitatShelf.Building or HabitatShelf.Home or HabitatShelf.Decor;
}

public enum InteractionKind
{
    Inspect, Touch, Top, Perch, Underside, Beneath, Side, Edge, Entrance, Interior,
    Launch, SilkAnchor, DrinkEdge, WaterSurface, Bask, Lookout, Feed
}

public sealed class InteractionPoint
{
    public InteractionKind Kind;
    public string Part = "body";
    public V2 Point, Normal;
    public InteractionStand? Stand;
    public V2? StandPoint;
    public double Facing = 1;
    public override string ToString() => $"{Kind} ({Part})";
}

public sealed class InteractionStand
{
    public Anchor Anchor;
    public V2 Point;
}

public static class HabitatInteractions
{
    public static List<InteractionPoint> Points(HabitatItem item, SurfaceMap map)
    {
        var result = new List<InteractionPoint>();
        var geo = HabitatGeometry.For(item);
        var r = item.Rect;
        double off = map.Standoff;
        V2 Ground = new(r.Mid.X, r.MinY - off);

        InteractionStand? StandNear(V2 p, double within)
        {
            var s = map.NearestSpot(p, within, null, map.Scale);
            return s is { } spot ? new InteractionStand { Anchor = spot.Anchor, Point = spot.Point } : null;
        }

        var top = geo.Top(r.MinX, r.MaxX);
        if (top is { } ty)
        {
            var p = new V2(r.Mid.X, ty);
            result.Add(new InteractionPoint { Kind = InteractionKind.Top, Part = geo.Parts.FirstOrDefault()?.Name ?? "body", Point = p, Normal = new V2(0, 1), Stand = StandNear(p + new V2(0, off), off * 2.2), StandPoint = p + new V2(0, off) });
            result.Add(new InteractionPoint { Kind = InteractionKind.Perch, Part = "top", Point = p, Normal = new V2(0, 1), Stand = StandNear(p + new V2(0, off), off * 2.2), StandPoint = p + new V2(0, off) });
        }
        var underside = new V2(r.Mid.X, r.MinY);
        result.Add(new InteractionPoint { Kind = InteractionKind.Underside, Part = "body", Point = underside, Normal = new V2(0, -1), Stand = StandNear(underside - new V2(0, off), off * 2.4), StandPoint = underside - new V2(0, off) });
        result.Add(new InteractionPoint { Kind = InteractionKind.Beneath, Part = "body", Point = underside, Normal = new V2(0, -1), Stand = StandNear(Ground, off * 3), StandPoint = Ground });
        result.Add(new InteractionPoint { Kind = InteractionKind.Side, Part = "body", Point = new V2(r.MinX, r.Mid.Y), Normal = new V2(-1, 0), Stand = StandNear(new V2(r.MinX - off, r.Mid.Y), off * 2.5) });
        result.Add(new InteractionPoint { Kind = InteractionKind.Side, Part = "body", Point = new V2(r.MaxX, r.Mid.Y), Normal = new V2(1, 0), Stand = StandNear(new V2(r.MaxX + off, r.Mid.Y), off * 2.5) });
        result.Add(new InteractionPoint { Kind = InteractionKind.Edge, Part = "edge", Point = new V2(r.MaxX, r.Mid.Y), Normal = new V2(1, 0), Stand = StandNear(new V2(r.MaxX + off, r.Mid.Y), off * 2.5) });
        result.Add(new InteractionPoint { Kind = InteractionKind.Inspect, Part = "body", Point = r.Mid, Normal = new V2(0, 1), Stand = StandNear(Ground, off * 4) });
        result.Add(new InteractionPoint { Kind = InteractionKind.Touch, Part = geo.Parts.FirstOrDefault()?.Name ?? "body", Point = new V2(r.MinX, r.Mid.Y), Normal = new V2(-1, 0), Stand = StandNear(Ground, off * 3) });

        foreach (var a in geo.Anchors)
        {
            var kind = a.Kind switch
            {
                AnchorKind.Perch => InteractionKind.Perch, AnchorKind.Tie => InteractionKind.SilkAnchor,
                AnchorKind.Entrance => InteractionKind.Entrance, AnchorKind.Refuge => InteractionKind.Interior,
                AnchorKind.Drink => InteractionKind.DrinkEdge, AnchorKind.Bask => InteractionKind.Bask,
                AnchorKind.Lookout => InteractionKind.Lookout, _ => InteractionKind.Feed
            };
            var st = StandNear(a.Point + a.Normal * off, off * 3);
            result.Add(new InteractionPoint { Kind = kind, Part = "anchor", Point = a.Point, Normal = a.Normal, Stand = st, StandPoint = st?.Point });
        }
        if (item.Water() is { } water)
        {
            result.Add(new InteractionPoint { Kind = InteractionKind.WaterSurface, Part = "water", Point = water.Mid, Normal = new V2(0, 1), Stand = StandNear(new V2(water.MinX - off, water.MinY), off * 3) });
            result.Add(new InteractionPoint { Kind = InteractionKind.DrinkEdge, Part = "rim", Point = new V2(water.MinX, water.MinY), Normal = new V2(-1, 0), Stand = StandNear(new V2(water.MinX - off, water.MinY), off * 3) });
        }
        // De-duplicate points by location and kind, keeping the first with a stand.
        var seen = new HashSet<string>();
        return result.Where(p => seen.Add($"{p.Kind}:{Math.Round(p.Point.X / 4)}:{Math.Round(p.Point.Y / 4)}"))
            .Where(p => p.Stand is not null).ToList();
    }
}

public static class HabitatInteractionKinds
{
    public static int Count => Enum.GetValues<InteractionKind>().Length;
}

/// <summary>Per-spider familiarity, places and routes (Swift HabitatKnowledge). Key habitatKnowledge.</summary>
public sealed class HabitatKnowledge
{
    public enum Stage { Unknown, Noticed, Investigating, Familiar }

    public sealed class Acquaintance
    {
        public Stage Stage;
        public double Exposure, Unease, Fond = 0, LastVisit = -1;
        public string Kind = "";
    }

    public sealed class PlaceRecord
    {
        public double X, Y;
        public string? Uid;
        public Dictionary<string, double> Fond = new();
        public double Visits, Last = -1, Frights, Catches, Sightings;
    }

    public Dictionary<string, Acquaintance> Things = new();
    public Dictionary<string, double> Kinds = new();
    public Dictionary<string, PlaceRecord> Places = new();
    public Dictionary<string, double> Routes = new();
    public bool Seeded;
    public double Clock;
    public bool Dirty;

    public static string Key => "habitatKnowledge";

    public void Meet(HabitatWorld tank)
    {
        bool first = !Seeded;
        foreach (var it in tank.Items)
        {
            if (Things.ContainsKey(it.Uid)) continue;
            Things[it.Uid] = new Acquaintance
            {
                Stage = first ? Stage.Familiar : Stage.Unknown,
                Exposure = first ? 1 : 0, Kind = it.Kind.SaveName()
            };
            Dirty = true;
        }
        if (first) { Seeded = true; Dirty = true; }
    }

    public Acquaintance For(string uid) => Things.TryGetValue(uid, out var a) ? a : new Acquaintance();
    public Stage StageOf(string uid) => For(uid).Stage;
    public double KindFamiliarity(HabitatItemKind k) => Kinds.TryGetValue(k.SaveName(), out var v) ? v : 0;

    public bool Notice(HabitatItem it, double unease)
    {
        if (!Things.TryGetValue(it.Uid, out var a)) { a = new Acquaintance { Kind = it.Kind.SaveName() }; Things[it.Uid] = a; }
        if (a.Stage != Stage.Unknown) return false;
        a.Stage = Stage.Noticed; a.Unease = Math.Max(a.Unease, unease); Dirty = true; return true;
    }

    public void Investigating(HabitatItem it, bool on)
    {
        if (!Things.TryGetValue(it.Uid, out var a) || a.Stage == Stage.Familiar) return;
        a.Stage = on ? Stage.Investigating : Stage.Noticed; Dirty = true;
    }

    public bool Expose(HabitatItem it, double amount)
    {
        if (amount <= 0 || !Things.TryGetValue(it.Uid, out var a) || a.Stage == Stage.Familiar) return false;
        double kind = KindFamiliarity(it.Kind);
        if (a.Stage == Stage.Unknown) a.Stage = Stage.Noticed;
        a.Exposure = M.Clamp01(a.Exposure + amount * (1 + 1.2 * kind));
        a.Unease = Math.Max(0, a.Unease - amount * .6);
        bool became = a.Exposure >= 1;
        if (became) { a.Stage = Stage.Familiar; a.Unease = 0; Kinds[it.Kind.SaveName()] = Math.Min(1, kind + .35); }
        Dirty = true; return became;
    }

    public void Unsettle(HabitatItem it, double amount)
    {
        if (!Things.TryGetValue(it.Uid, out var a)) { a = new Acquaintance { Kind = it.Kind.SaveName() }; Things[it.Uid] = a; }
        a.Unease = M.Clamp01(a.Unease + amount);
        if (a.Stage != Stage.Familiar) a.Exposure = Math.Max(0, a.Exposure - amount * .25);
        Dirty = true;
    }
    public void Calm(double dt)
    {
        foreach (var a in Things.Values) if (a.Unease > 0) a.Unease = Math.Max(0, a.Unease - dt / 40);
    }
    public void Warm(HabitatItem it, double amount)
    {
        if (!Things.TryGetValue(it.Uid, out var a)) return;
        double toward = amount > 0 ? 1 : -1;
        a.Fond = M.Clamp(a.Fond + amount * (toward - a.Fond) * toward, -1, 1); Dirty = true;
    }
    public void Visited(HabitatItem it) { if (Things.TryGetValue(it.Uid, out var a)) { a.LastVisit = Clock; Dirty = true; } }
    public double? SinceVisit(string uid) => Things.TryGetValue(uid, out var a) && a.LastVisit >= 0 ? Clock - a.LastVisit : null;

    public PlaceRecord Place(string key)
    {
        if (!Places.TryGetValue(key, out var r)) { r = new PlaceRecord(); Places[key] = r; }
        return r;
    }

    public void VisitPlace(string key, V2 at, string? uid, double fond, string use)
    {
        var r = Place(key); r.X = at.X; r.Y = at.Y; r.Uid = uid;
        r.Visits++; r.Last = Clock;
        r.Fond[use] = M.Clamp((r.Fond.TryGetValue(use, out var v) ? v : 0) + .08, -1, 1);
        Dirty = true;
    }

    public string ToJson()
    {
        var things = new JsonObject();
        foreach (var (uid, a) in Things) things[uid] = new JsonObject
        {
            ["stage"] = a.Stage.ToString().ToLowerInvariant(), ["exposure"] = a.Exposure, ["unease"] = a.Unease,
            ["kind"] = a.Kind, ["fond"] = a.Fond, ["lastVisit"] = a.LastVisit
        };
        var places = new JsonObject();
        foreach (var (key, p) in Places)
        {
            var fond = new JsonObject(); foreach (var (u, v) in p.Fond) fond[u] = v;
            places[key] = new JsonObject
            {
                ["x"] = p.X, ["y"] = p.Y, ["uid"] = p.Uid, ["fond"] = fond, ["visits"] = p.Visits,
                ["last"] = p.Last, ["frights"] = p.Frights, ["catches"] = p.Catches, ["sightings"] = p.Sightings
            };
        }
        var kinds = new JsonObject(); foreach (var (k, v) in Kinds) kinds[k] = v;
        var routes = new JsonObject(); foreach (var (k, v) in Routes) routes[k] = v;
        return new JsonObject
        {
            ["version"] = 1, ["things"] = things, ["kinds"] = kinds, ["seeded"] = Seeded,
            ["clock"] = Clock, ["places"] = places, ["routes"] = routes
        }.ToJsonString();
    }

    public static HabitatKnowledge FromJson(string? json)
    {
        var k = new HabitatKnowledge();
        if (string.IsNullOrWhiteSpace(json)) return k;
        try
        {
            var o = JsonNode.Parse(json) as JsonObject;
            if (o is null) return k;
            k.Seeded = o["seeded"]?.GetValue<bool>() ?? false;
            k.Clock = Num(o["clock"]);
            if (o["things"] is JsonObject things)
                foreach (var (uid, n) in things)
                {
                    if (n is not JsonObject a) continue;
                    k.Things[uid] = new Acquaintance
                    {
                        Stage = Enum.TryParse<Stage>(a["stage"]?.GetValue<string>(), true, out var st) ? st : Stage.Unknown,
                        Exposure = Num(a["exposure"]), Unease = Num(a["unease"]), Kind = a["kind"]?.GetValue<string>() ?? "",
                        Fond = Num(a["fond"]), LastVisit = Num(a["lastVisit"], -1)
                    };
                }
            if (o["kinds"] is JsonObject kinds) foreach (var (key, v) in kinds) k.Kinds[key] = Num(v);
            if (o["routes"] is JsonObject routes) foreach (var (key, v) in routes) k.Routes[key] = Num(v);
            if (o["places"] is JsonObject places)
                foreach (var (key, n) in places)
                {
                    if (n is not JsonObject p) continue;
                    var rec = new PlaceRecord { X = Num(p["x"]), Y = Num(p["y"]), Uid = p["uid"]?.GetValue<string>(), Visits = Num(p["visits"]), Last = Num(p["last"], -1), Frights = Num(p["frights"]), Catches = Num(p["catches"]), Sightings = Num(p["sightings"]) };
                    if (p["fond"] is JsonObject fond) foreach (var (u, v) in fond) rec.Fond[u] = Num(v);
                    k.Places[key] = rec;
                }
        }
        catch { }
        return k;
    }
    static double Num(JsonNode? n, double d = 0) => n is JsonValue v && v.TryGetValue(out double x) ? x : d;
}
