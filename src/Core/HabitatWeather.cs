using System.Text.Json;
using System.Text.Json.Nodes;

namespace SpiderBuddy.Core;

public enum WeatherKind
{
    Clear, Sunny, Cloudy, Fog, Drizzle, Rain, Storm, Hail, Snow, Blizzard, Windy, Sandstorm, Sunshower, Starfall, Aurora
}

public sealed class WeatherRecipe
{
    public double Rain, Snow, Hail, Sand, Cloud, Storm, Dark, Fog, Sun, Wind, Gust, Lightning, Cold, Heat, Rainbow, Night, Stars, Aurora;

    public WeatherRecipe Plus(WeatherRecipe b) => new()
    {
        Rain = Rain + b.Rain, Snow = Snow + b.Snow, Hail = Hail + b.Hail, Sand = Sand + b.Sand,
        Cloud = Cloud + b.Cloud, Storm = Storm + b.Storm, Dark = Dark + b.Dark, Fog = Fog + b.Fog,
        Sun = Sun + b.Sun, Wind = Wind + b.Wind, Gust = Gust + b.Gust, Lightning = Lightning + b.Lightning,
        Cold = Cold + b.Cold, Heat = Heat + b.Heat, Rainbow = Rainbow + b.Rainbow,
        Night = Night + b.Night, Stars = Stars + b.Stars, Aurora = Aurora + b.Aurora
    };
    public WeatherRecipe Times(double k) => new()
    {
        Rain = Rain * k, Snow = Snow * k, Hail = Hail * k, Sand = Sand * k, Cloud = Cloud * k,
        Storm = Storm * k, Dark = Dark * k, Fog = Fog * k, Sun = Sun * k, Wind = Wind * k,
        Gust = Gust * k, Lightning = Lightning * k, Cold = Cold * k, Heat = Heat * k,
        Rainbow = Rainbow * k, Night = Night * k, Stars = Stars * k, Aurora = Aurora * k
    };
    WeatherRecipe C() => new()
    {
        Rain = M.Clamp01(Rain), Snow = M.Clamp01(Snow), Hail = M.Clamp01(Hail), Sand = M.Clamp01(Sand),
        Cloud = M.Clamp01(Cloud), Storm = M.Clamp01(Storm), Dark = M.Clamp01(Dark), Fog = M.Clamp01(Fog),
        Sun = M.Clamp01(Sun), Wind = M.Clamp01(Wind), Gust = M.Clamp01(Gust), Lightning = M.Clamp01(Lightning),
        Cold = M.Clamp01(Cold), Heat = M.Clamp01(Heat), Rainbow = M.Clamp01(Rainbow),
        Night = M.Clamp01(Night), Stars = M.Clamp01(Stars), Aurora = M.Clamp01(Aurora)
    };
    public WeatherRecipe Clamped => C();
}

public sealed class WeatherConditions
{
    public WeatherRecipe Mix = new();
    public double WindNow;
    public WeatherKind Shown = WeatherKind.Clear;
    public double Strength;
    public static WeatherConditions Calm => new();
}

public static class WeatherKinds
{
    public static readonly WeatherKind[] All = Enum.GetValues<WeatherKind>();
    public static string Label(this WeatherKind k) => k switch
    {
        WeatherKind.Clear => "Clear", WeatherKind.Sunny => "Blazing Sun", WeatherKind.Cloudy => "Overcast",
        WeatherKind.Fog => "Fog", WeatherKind.Drizzle => "Drizzle", WeatherKind.Rain => "Rain",
        WeatherKind.Storm => "Thunderstorm", WeatherKind.Hail => "Hail", WeatherKind.Snow => "Snow",
        WeatherKind.Blizzard => "Blizzard", WeatherKind.Windy => "Gale", WeatherKind.Sandstorm => "Sandstorm",
        WeatherKind.Sunshower => "Sun Shower", WeatherKind.Starfall => "Shooting Stars", _ => "Northern Lights"
    };
    public static string Blurb(this WeatherKind k) => k switch
    {
        WeatherKind.Clear => "Just the scenery", WeatherKind.Sunny => "Glare and heat haze",
        WeatherKind.Cloudy => "Grey skies", WeatherKind.Fog => "Thick, drifting mist",
        WeatherKind.Drizzle => "A fine, light rain", WeatherKind.Rain => "Puddles and splashes",
        WeatherKind.Storm => "Lightning and thunder", WeatherKind.Hail => "Ice, bouncing",
        WeatherKind.Snow => "It settles on things", WeatherKind.Blizzard => "Snow on a gale",
        WeatherKind.Windy => "Everything blows about", WeatherKind.Sandstorm => "A wall of dust",
        WeatherKind.Sunshower => "Rain, sun and a rainbow", WeatherKind.Starfall => "A meteor shower",
        _ => "Curtains of light"
    };
    public static string Summon(this WeatherKind k) => k switch
    {
        WeatherKind.Clear => "Clear the Sky", WeatherKind.Sunny => "Bring Out the Sun",
        WeatherKind.Cloudy => "Cloud Over", WeatherKind.Fog => "Roll In the Fog",
        WeatherKind.Drizzle => "Make It Drizzle", WeatherKind.Rain => "Make It Rain",
        WeatherKind.Storm => "Brew a Thunderstorm", WeatherKind.Hail => "Make It Hail",
        WeatherKind.Snow => "Make It Snow", WeatherKind.Blizzard => "Whip Up a Blizzard",
        WeatherKind.Windy => "Blow a Gale", WeatherKind.Sandstorm => "Kick Up a Sandstorm",
        WeatherKind.Sunshower => "A Sun Shower", WeatherKind.Starfall => "Shooting Stars",
        _ => "The Northern Lights"
    };
    public static bool Falls(this WeatherKind k) => k is WeatherKind.Drizzle or WeatherKind.Rain or WeatherKind.Storm
        or WeatherKind.Hail or WeatherKind.Snow or WeatherKind.Blizzard or WeatherKind.Sandstorm or WeatherKind.Sunshower;
    public static bool Wets(this WeatherKind k) => k is WeatherKind.Drizzle or WeatherKind.Rain or WeatherKind.Storm or WeatherKind.Sunshower;
    public static double Stay(this WeatherKind k) => k switch
    {
        WeatherKind.Hail => .35, WeatherKind.Sunshower => .5,
        WeatherKind.Storm or WeatherKind.Blizzard or WeatherKind.Sandstorm => .75,
        WeatherKind.Fog or WeatherKind.Cloudy => 1.2, _ => 1
    };
    public static WeatherKind[] TurnsInto(this WeatherKind k) => k switch
    {
        WeatherKind.Cloudy => new[] { WeatherKind.Drizzle, WeatherKind.Rain },
        WeatherKind.Drizzle => new[] { WeatherKind.Rain },
        WeatherKind.Rain => new[] { WeatherKind.Storm, WeatherKind.Drizzle, WeatherKind.Sunshower },
        WeatherKind.Storm => new[] { WeatherKind.Rain, WeatherKind.Hail },
        WeatherKind.Hail => new[] { WeatherKind.Rain },
        WeatherKind.Snow => new[] { WeatherKind.Blizzard },
        WeatherKind.Blizzard => new[] { WeatherKind.Snow },
        WeatherKind.Windy => new[] { WeatherKind.Sandstorm, WeatherKind.Rain },
        WeatherKind.Sandstorm => new[] { WeatherKind.Windy },
        WeatherKind.Fog => new[] { WeatherKind.Drizzle },
        WeatherKind.Starfall => new[] { WeatherKind.Aurora },
        _ => Array.Empty<WeatherKind>()
    };
    public static (double min, double max) Fade(this WeatherKind k) => k switch
    {
        WeatherKind.Storm => (30, 50), WeatherKind.Rain or WeatherKind.Fog or WeatherKind.Snow => (22, 40),
        WeatherKind.Drizzle or WeatherKind.Cloudy or WeatherKind.Blizzard => (16, 28),
        WeatherKind.Sunny or WeatherKind.Aurora or WeatherKind.Starfall => (16, 24),
        WeatherKind.Windy or WeatherKind.Sandstorm => (8, 16),
        WeatherKind.Sunshower or WeatherKind.Hail or WeatherKind.Clear => (8, 12), _ => (12, 20)
    };

    public static WeatherRecipe Recipe(this WeatherKind k)
    {
        var r = new WeatherRecipe();
        switch (k)
        {
            case WeatherKind.Sunny: r.Sun = 1; r.Heat = .8; r.Wind = .08; r.Gust = .2; break;
            case WeatherKind.Cloudy: r.Cloud = .9; r.Dark = .22; r.Wind = .25; r.Gust = .3; r.Cold = .1; break;
            case WeatherKind.Fog: r.Fog = 1; r.Cloud = .35; r.Dark = .15; r.Cold = .25; r.Wind = .03; break;
            case WeatherKind.Drizzle: r.Rain = .3; r.Cloud = .75; r.Dark = .25; r.Wind = .12; r.Gust = .2; r.Cold = .1; break;
            case WeatherKind.Rain: r.Rain = .75; r.Cloud = .95; r.Storm = .35; r.Dark = .4; r.Wind = .3; r.Gust = .4; r.Cold = .15; break;
            case WeatherKind.Storm: r.Rain = 1; r.Cloud = 1; r.Storm = 1; r.Dark = .62; r.Wind = .7; r.Gust = .9; r.Lightning = 1; r.Cold = .2; break;
            case WeatherKind.Hail: r.Hail = 1; r.Rain = .25; r.Cloud = 1; r.Storm = .8; r.Dark = .5; r.Wind = .45; r.Gust = .6; r.Lightning = .25; r.Cold = .45; break;
            case WeatherKind.Snow: r.Snow = .65; r.Cloud = .85; r.Dark = .18; r.Wind = .12; r.Gust = .2; r.Cold = .8; break;
            case WeatherKind.Blizzard: r.Snow = 1; r.Cloud = 1; r.Storm = .4; r.Dark = .3; r.Fog = .45; r.Wind = 1; r.Gust = .7; r.Cold = 1; break;
            case WeatherKind.Windy: r.Wind = .85; r.Gust = 1; r.Cloud = .3; break;
            case WeatherKind.Sandstorm: r.Sand = 1; r.Wind = .95; r.Gust = .6; r.Dark = .3; r.Fog = .35; r.Heat = .4; break;
            case WeatherKind.Sunshower: r.Rain = .45; r.Sun = .8; r.Rainbow = 1; r.Cloud = .2; r.Wind = .1; r.Gust = .2; break;
            case WeatherKind.Starfall: r.Night = 1; r.Stars = 1; r.Dark = .35; r.Cold = .1; break;
            case WeatherKind.Aurora: r.Night = 1; r.Aurora = 1; r.Dark = .35; r.Cold = .35; break;
        }
        return r;
    }

    public static (WeatherKind kind, double weight)[] Natural(this HabitatBiome b) => b switch
    {
        HabitatBiome.Forest => new[] { (WeatherKind.Cloudy, 3.0), (WeatherKind.Drizzle, 2.0), (WeatherKind.Rain, 3.0), (WeatherKind.Storm, 1.2), (WeatherKind.Fog, 2.0), (WeatherKind.Windy, 1.5), (WeatherKind.Sunshower, 1.0), (WeatherKind.Sunny, 1.0) },
        HabitatBiome.Jungle => new[] { (WeatherKind.Rain, 4.0), (WeatherKind.Storm, 2.0), (WeatherKind.Drizzle, 2.0), (WeatherKind.Fog, 2.5), (WeatherKind.Sunshower, 1.5), (WeatherKind.Sunny, 1.0), (WeatherKind.Cloudy, 1.0) },
        HabitatBiome.Desert => new[] { (WeatherKind.Sunny, 4.0), (WeatherKind.Windy, 2.0), (WeatherKind.Sandstorm, 2.0), (WeatherKind.Cloudy, .6), (WeatherKind.Storm, .5), (WeatherKind.Starfall, .6) },
        HabitatBiome.Meadow => new[] { (WeatherKind.Sunny, 3.0), (WeatherKind.Cloudy, 2.0), (WeatherKind.Drizzle, 1.5), (WeatherKind.Rain, 2.0), (WeatherKind.Storm, .8), (WeatherKind.Windy, 1.5), (WeatherKind.Sunshower, 1.5), (WeatherKind.Hail, .5) },
        HabitatBiome.Cave => new[] { (WeatherKind.Fog, 3.0), (WeatherKind.Drizzle, 2.0), (WeatherKind.Rain, .6) },
        HabitatBiome.Beach => new[] { (WeatherKind.Sunny, 3.0), (WeatherKind.Windy, 2.5), (WeatherKind.Cloudy, 1.5), (WeatherKind.Rain, 1.5), (WeatherKind.Storm, 1.0), (WeatherKind.Sunshower, 1.0), (WeatherKind.Fog, 1.0) },
        HabitatBiome.Tundra => new[] { (WeatherKind.Snow, 4.0), (WeatherKind.Blizzard, 1.5), (WeatherKind.Windy, 1.5), (WeatherKind.Fog, 1.5), (WeatherKind.Cloudy, 1.0), (WeatherKind.Aurora, 2.0) },
        _ => new[] { (WeatherKind.Fog, 2.0), (WeatherKind.Drizzle, 1.0), (WeatherKind.Rain, 1.5), (WeatherKind.Storm, 1.0), (WeatherKind.Windy, 1.0), (WeatherKind.Starfall, 2.0), (WeatherKind.Aurora, 1.0), (WeatherKind.Snow, .5) }
    };
}

public enum WeatherMode { Changing, Always, Outside }

public sealed class WeatherSettings
{
    public const string Key = "habitatWeather";
    public WeatherMode Mode = WeatherMode.Changing;
    public WeatherKind Always = WeatherKind.Rain;
    public Dictionary<HabitatBiome, List<WeatherKind>> Custom = new();
    public double Pace = .5, Amount = .5;

    public List<WeatherKind> Rotation(HabitatBiome b)
    {
        var list = Custom.TryGetValue(b, out var c) ? c : b.Natural().Select(x => x.kind).ToList();
        return WeatherKinds.All.Where(k => k != WeatherKind.Clear && list.Contains(k)).ToList();
    }
    public List<(WeatherKind kind, double weight)> Weights(HabitatBiome b)
    {
        var natural = b.Natural().ToDictionary(x => x.kind, x => x.weight);
        return Rotation(b).Select(k => (k, natural.TryGetValue(k, out var w) ? w : 1.6)).ToList();
    }
    public bool IsCustom(HabitatBiome b) => Custom.TryGetValue(b, out var c) && c.ToHashSet().SetEquals(b.Natural().Select(x => x.kind)) == false;
    public void Toggle(WeatherKind k, HabitatBiome b)
    {
        if (k == WeatherKind.Clear) return;
        var list = Rotation(b);
        if (!list.Remove(k)) list.Add(k);
        Custom[b] = list;
        if (!IsCustom(b)) Custom.Remove(b);
    }
    public void Reset(HabitatBiome b) => Custom.Remove(b);

    public string ToJson()
    {
        var custom = new JsonObject();
        foreach (var (b, ks) in Custom) custom[b.SaveName()] = new JsonArray(ks.Select(k => (JsonNode)JsonValue.Create(k.ToString())).ToArray());
        return new JsonObject
        {
            ["mode"] = Mode.ToString().ToLowerInvariant(), ["always"] = Always.ToString().ToLowerInvariant(),
            ["pace"] = Pace, ["amount"] = Amount, ["custom"] = custom
        }.ToJsonString();
    }

    public static WeatherSettings FromJson(string? json)
    {
        var s = new WeatherSettings();
        if (string.IsNullOrWhiteSpace(json)) return s;
        try
        {
            var o = JsonNode.Parse(json) as JsonObject;
            if (o is null) return s;
            if (o["mode"]?.GetValue<string>() is { } m)
                s.Mode = m.Equals("always", StringComparison.OrdinalIgnoreCase) ? WeatherMode.Always
                    : m.Equals("outside", StringComparison.OrdinalIgnoreCase) ? WeatherMode.Outside : WeatherMode.Changing;
            if (o["always"]?.GetValue<string>() is { } a && Enum.TryParse<WeatherKind>(a, true, out var ak)) s.Always = ak;
            s.Pace = M.Clamp(Num(o["pace"], .5), 0, 1);
            s.Amount = M.Clamp(Num(o["amount"], .5), 0, 1);
            if (o["custom"] is JsonObject co)
                foreach (var (key, val) in co)
                {
                    var biome = HabitatBiomes.Parse(key);
                    if (val is JsonArray arr) s.Custom[biome] = arr.Select(n => Enum.TryParse<WeatherKind>(n?.GetValue<string>(), true, out var k) ? k : WeatherKind.Clear).Where(k => k != WeatherKind.Clear).ToList();
                }
        }
        catch { }
        return s;
    }
    static double Num(JsonNode? n, double d) => n is JsonValue v && v.TryGetValue(out double x) ? x : d;
}

public sealed class WeatherSpell
{
    public WeatherKind Kind;
    public double Start, Full, Leave, End, Dir;
    public bool Planned;
    public double Strength(double now)
    {
        if (now <= Start || now >= End) return 0;
        if (now < Full) return M.Smoothstep((now - Start) / Math.Max(.01, Full - Start));
        if (now < Leave) return 1;
        return 1 - M.Smoothstep((now - Leave) / Math.Max(.01, End - Leave));
    }
}

/// <summary>Wall-clock weather: keeps its spells while the tank is shut, exactly as the Swift clock.</summary>
public sealed class WeatherClock
{
    public const double Forever = 1e12;
    public WeatherSettings Settings;
    public HabitatBiome Biome;
    public WeatherKind? Outside;
    public List<WeatherSpell> Spells = new();
    public double? NextAt;
    double _rainbowFrom, _rainbowTo;
    public bool Persists = true;
    readonly Rng _rng;
    public Action? Changed;

    public WeatherClock(WeatherSettings settings, HabitatBiome biome, int seed = 1)
    {
        Settings = settings; Biome = biome; _rng = new Rng((ulong)seed * 7919 + 3);
    }

    public static double Now => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;
    public WeatherKind CurrentAt(double now)
    {
        Advance(now);
        return Spells.Where(s => s.Strength(now) > 0 && now < s.Leave).OrderBy(s => s.Start).LastOrDefault()?.Kind ?? WeatherKind.Clear;
    }
    public WeatherKind Current => CurrentAt(Now);

    public WeatherConditions Conditions(double now, double clock)
    {
        Advance(now);
        var c = new WeatherConditions();
        var mix = new WeatherRecipe();
        double wind = 0, best = 0, bestStart = double.MinValue;
        foreach (var s in Spells)
        {
            double k = s.Strength(now);
            if (k <= 0) continue;
            mix = mix.Plus(s.Kind.Recipe().Times(k));
            wind += s.Kind.Recipe().Wind * k * s.Dir;
            if (k > best + .001 || (Math.Abs(k - best) <= .001 && s.Start > bestStart))
            {
                best = k; bestStart = s.Start; c.Shown = s.Kind;
            }
        }
        c.Strength = best;
        if (now > _rainbowFrom && now < _rainbowTo)
        {
            double a = Math.Min(Math.Min((now - _rainbowFrom) / 12, (_rainbowTo - now) / 15), 1);
            mix.Rainbow = Math.Max(mix.Rainbow, M.Smoothstep(a));
        }
        c.Mix = mix.Clamped;
        double n = Gustiness(clock);
        c.WindNow = wind * (1 + c.Mix.Gust * (1.6 * n - .5));
        return c;
    }

    public static double Gustiness(double t)
    {
        double a = Math.Sin(t * .53) * .45 + Math.Sin(t * 1.37 + 1.3) * .3 + Math.Sin(t * 2.91 + .4) * .15 + Math.Sin(t * 5.3 + 2.2) * .1;
        double v = M.Clamp01(.5 + .5 * a);
        return v * v * (1.4 - .4 * v);
    }

    public string Summary(double now)
    {
        Advance(now);
        switch (Settings.Mode)
        {
            case WeatherMode.Always:
                return Settings.Always == WeatherKind.Clear ? "Always clear skies" : "Always " + Settings.Always.Label().ToLowerInvariant();
            case WeatherMode.Outside:
                return Outside is null ? "Waiting to hear what it’s doing outside"
                    : Outside == WeatherKind.Clear ? "Clear, like it is outside" : $"{Outside.Value.Label()}, like it is outside";
            default:
                var live = Spells.Where(s => s.Strength(now) > .02 || s.Start > now).OrderBy(s => s.Start).LastOrDefault();
                if (live is null)
                    return NextAt is { } n && n - now < 75 ? "Clear, but something’s brewing" : "Clear skies, for now";
                if (now < live.Full) return live.Kind.Label() + ", rolling in";
                if (now >= live.Leave) return live.Kind.Label() + ", clearing";
                double left = live.Leave - now;
                if (left > 3600) return live.Kind.Label();
                if (left < 90) return live.Kind.Label() + ", clearing soon";
                int mins = (int)Math.Round(left / 60);
                return $"{live.Kind.Label()}, for about {mins} more minute{(mins == 1 ? "" : "s")}";
        }
    }

    public void Bring(WeatherKind kind)
    {
        double now = Now;
        if (Settings.Mode == WeatherMode.Always) { Settings.Always = kind; Changed?.Invoke(); return; }
        if (Settings.Mode == WeatherMode.Outside) Settings.Mode = WeatherMode.Changing;
        ClearAll(now, 6); _rainbowTo = Math.Min(_rainbowTo, now);
        if (kind == WeatherKind.Clear) NextAt = now + Gap();
        else { Add(kind, now, 6, Hold(kind)); NextAt = null; }
        Changed?.Invoke();
    }

    public void ChangeNow()
    {
        if (Settings.Mode != WeatherMode.Changing) return;
        double now = Now; var was = Current;
        ClearAll(now, 10);
        var k = Draw(was);
        if (k is { } kk) { Add(kk, now, 10, Hold(kk)); NextAt = null; }
        else NextAt = now + Gap();
        Changed?.Invoke();
    }

    public void Settle(double now, bool fresh = false)
    {
        Spells.RemoveAll(s => s.End <= now);
        if (Settings.Mode is WeatherMode.Always or WeatherMode.Outside)
        {
            var want = Settings.Mode == WeatherMode.Always ? Settings.Always : (Outside ?? WeatherKind.Clear);
            bool kept = Spells.Any(s => s.Kind == want && s.Leave >= Forever);
            if (!kept)
            {
                ClearAll(now, fresh ? .01 : 8);
                if (want != WeatherKind.Clear) Add(want, now, fresh ? 3 : 8, Forever, fresh);
            }
            NextAt = null;
        }
        else
        {
            var list = Settings.Rotation(Biome);
            foreach (var s in Spells.Where(s => s.Leave >= Forever))
            {
                s.Leave = Math.Max(now, s.Full) + Hold(s.Kind);
                s.End = s.Leave + _rng.Range(s.Kind.Fade().min, s.Kind.Fade().max);
                s.Planned = false;
            }
            var gone = Spells.Any(s => !list.Contains(s.Kind) && now < s.Leave);
            if (gone)
            {
                foreach (var s in Spells.Where(s => !list.Contains(s.Kind) && now < s.Leave)) FadeOut(s, now, 10);
                Spells.RemoveAll(s => s.End <= now);
                NextAt = now + Gap();
            }
            if (fresh && Spells.Count == 0 && NextAt is null)
            {
                if (_rng.Chance(.5) && Draw(null) is { } k) Add(k, now, _rng.Range(k.Fade().min, k.Fade().max), Hold(k) * .6, true);
                else NextAt = now + _rng.Range(25, 90);
            }
        }
        Changed?.Invoke();
    }

    public void Force(WeatherKind kind)
    {
        double now = Now;
        Spells = kind == WeatherKind.Clear ? new() : new()
        {
            new WeatherSpell { Kind = kind, Start = now - 2, Full = now - 1, Leave = Forever, End = Forever + 1, Dir = 1, Planned = true }
        };
        NextAt = null; _rainbowTo = 0;
    }

    void Advance(double now)
    {
        int before = Spells.Count;
        Spells.RemoveAll(s => s.End <= now);
        if (Settings.Mode != WeatherMode.Changing) return;
        foreach (var s in Spells.Where(s => !s.Planned && now >= s.Leave))
        {
            s.Planned = true;
            var follow = s.Kind.TurnsInto().Where(k => Settings.Rotation(Biome).Contains(k)).ToArray();
            if (follow.Length > 0 && _rng.Chance(.4))
            {
                var k = follow[_rng.RangeInt(0, follow.Length - 1)];
                Add(k, now, _rng.Range(k.Fade().min, k.Fade().max), Hold(k));
                NextAt = null;
            }
            else
            {
                NextAt = s.End + Gap();
                if (s.Kind.Wets() && Biome != HabitatBiome.Cave && _rng.Chance(.45))
                {
                    _rainbowFrom = s.Leave + (s.End - s.Leave) * .4;
                    _rainbowTo = _rainbowFrom + _rng.Range(50, 90);
                }
            }
        }
        bool live = Spells.Any(s => now < s.Leave || !s.Planned);
        if (!live && NextAt is null) NextAt = now + Gap();
        if (!live && NextAt is { } n && now >= n)
        {
            NextAt = null;
            if (Draw(Spells.LastOrDefault()?.Kind) is { } k) { Add(k, now, _rng.Range(k.Fade().min, k.Fade().max), Hold(k)); Changed?.Invoke(); }
            else NextAt = now + Gap();
        }
    }

    void ClearAll(double now, double fade)
    {
        foreach (var s in Spells) FadeOut(s, now, fade);
        Spells.RemoveAll(s => s.End <= now);
    }

    static void FadeOut(WeatherSpell s, double now, double fade)
    {
        s.Planned = true;
        double k = s.Strength(now);
        if (s.Start >= now || k <= .001) { s.End = now; return; }
        if (now >= s.Leave && s.End - now <= fade) return;
        double lo = 0, hi = 1;
        for (int i = 0; i < 16; i++)
        {
            double m = (lo + hi) / 2;
            if (1 - M.Smoothstep(m) > k) lo = m; else hi = m;
        }
        s.Leave = now - fade * lo; s.End = s.Leave + fade;
        s.Full = Math.Min(s.Full, s.Leave); s.Start = Math.Min(s.Start, s.Full - .01);
    }

    void Add(WeatherKind kind, double now, double fadeIn, double hold, bool already = false)
    {
        double fadeOut = _rng.Range(kind.Fade().min, kind.Fade().max);
        double start = already ? now - fadeIn : now;
        var s = new WeatherSpell
        {
            Kind = kind, Start = start, Full = start + fadeIn, Leave = start + fadeIn + hold,
            End = start + fadeIn + hold + fadeOut, Dir = _rng.Chance(.5) ? 1 : -1
        };
        if (hold >= Forever / 2) { s.Leave = Forever; s.End = Forever + 1; s.Planned = true; }
        if (Spells.Count > 0 && _rng.Chance(.7)) s.Dir = Spells[^1].Dir;
        Spells.Add(s);
    }

    double Hold(WeatherKind k) => M.Lerp(9, 1.5, Settings.Pace) * k.Stay() * _rng.Range(.6, 1.4) * 60;
    double Gap() => Math.Max(12, M.Lerp(9, 1.5, Settings.Pace) * M.Lerp(2.4, .12, Settings.Amount) * 60 * _rng.Range(.5, 1.5));

    WeatherKind? Draw(WeatherKind? avoid)
    {
        var w = Settings.Weights(Biome);
        if (w.Count == 0) return null;
        var weighted = w.Select(x => (x.kind, x.kind == avoid && w.Count > 1 ? x.weight * .25 : x.weight)).ToList();
        double total = weighted.Sum(x => x.Item2), pick = _rng.Range(0, Math.Max(total, .0001));
        foreach (var (k, wt) in weighted) { pick -= wt; if (pick < 0) return k; }
        return weighted.Count > 0 ? weighted[^1].kind : null;
    }

    public string ToJson()
    {
        var spells = new JsonArray(Spells.Select(s => (JsonNode)new JsonObject
        {
            ["kind"] = s.Kind.ToString().ToLowerInvariant(), ["start"] = s.Start, ["full"] = s.Full,
            ["leave"] = s.Leave, ["end"] = s.End, ["dir"] = s.Dir, ["planned"] = s.Planned
        }).ToArray());
        return new JsonObject
        {
            ["spells"] = spells, ["nextAt"] = NextAt, ["rainbowFrom"] = _rainbowFrom,
            ["rainbowTo"] = _rainbowTo
        }.ToJsonString();
    }

    public void Restore(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return;
        try
        {
            var o = JsonNode.Parse(json) as JsonObject;
            if (o is null) return;
            double now = Now;
            Spells = new();
            if (o["spells"] is JsonArray arr)
                foreach (var n in arr.OfType<JsonObject>())
                {
                    if (!Enum.TryParse<WeatherKind>(n["kind"]?.GetValue<string>(), true, out var k)) continue;
                    double end = Num(n["end"]);
                    if (end <= now) continue;
                    Spells.Add(new WeatherSpell
                    {
                        Kind = k, Start = Num(n["start"]), Full = Num(n["full"]), Leave = Num(n["leave"]),
                        End = end, Dir = Num(n["dir"]), Planned = n["planned"]?.GetValue<bool>() ?? false
                    });
                }
            NextAt = o["nextAt"] is null ? null : Num(o["nextAt"]);
            _rainbowFrom = Num(o["rainbowFrom"]); _rainbowTo = Num(o["rainbowTo"]);
        }
        catch { }
    }
    static double Num(JsonNode? n) => n is JsonValue v && v.TryGetValue(out double d) ? d : 0;
}
