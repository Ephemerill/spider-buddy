using System.Text.Json;

namespace SpiderBuddy.Core;

public enum ExperienceKind
{
    Petted, Greeted, Company, Carried, Thrown, Startled, Chased, Played, Fed, HuntWon, HuntMissed, Alone
}

public readonly struct ExperienceInfo
{
    public readonly double Mood, Lasting, Rate, Comfort;
    public ExperienceInfo(double mood, double lasting, double rate, double comfort)
    {
        Mood = mood; Lasting = lasting; Rate = rate; Comfort = comfort;
    }
}

public sealed class MemoryEntry
{
    public double Feeling;
    public double Lesson;
    public int Measures;
}

public sealed class PlaceMemory
{
    public V2 Pos;
    public double Comfort;
}

/// <summary>The six sliders plus sureness and roaming (spec 13.2).</summary>
public sealed class TraitShift
{
    public double Energy, Curiosity, Bravery, Playfulness, Affection, Laziness, Prowess, Roaming;

    public void Add(TraitShift o)
    {
        Energy += o.Energy; Curiosity += o.Curiosity; Bravery += o.Bravery;
        Playfulness += o.Playfulness; Affection += o.Affection; Laziness += o.Laziness;
        Prowess += o.Prowess; Roaming += o.Roaming;
    }

    public TraitShift Scaled(double k) => new()
    {
        Energy = Energy * k, Curiosity = Curiosity * k, Bravery = Bravery * k,
        Playfulness = Playfulness * k, Affection = Affection * k, Laziness = Laziness * k,
        Prowess = Prowess * k, Roaming = Roaming * k
    };
}

/// <summary>Stage 13 — a slow, bounded personality drift (spec 13).</summary>
public sealed class SpiderMemory
{
    public bool LearnFromExperience = true;
    public Dictionary<ExperienceKind, MemoryEntry> Entries = new();
    public List<PlaceMemory> Places = new();
    public bool Dirty;

    static readonly JsonSerializerOptions JsonOpts = new() { IncludeFields = true };

    public static ExperienceInfo Info(ExperienceKind k) => k switch
    {
        ExperienceKind.Petted => new(15 * 60, 10 * 86400, 0.05, 0.6),
        ExperienceKind.Greeted => new(10 * 60, 7 * 86400, 0.03, 0.3),
        ExperienceKind.Company => new(20 * 60, 7 * 86400, 0.04, 0.3),
        ExperienceKind.Carried => new(10 * 60, 5 * 86400, 0.03, 0),
        ExperienceKind.Thrown => new(15 * 60, 4 * 86400, 0.04, -0.3),
        ExperienceKind.Startled => new(12 * 60, 3 * 86400, 0.03, -1),
        ExperienceKind.Chased => new(10 * 60, 3 * 86400, 0.03, -0.4),
        ExperienceKind.Played => new(20 * 60, 7 * 86400, 0.04, 0.4),
        ExperienceKind.Fed => new(30 * 60, 5 * 86400, 0.03, 0.8),
        ExperienceKind.HuntWon => new(20 * 60, 10 * 86400, 0.05, 0.4),
        ExperienceKind.HuntMissed => new(10 * 60, 4 * 86400, 0.03, 0),
        _ => new(30 * 60, 5 * 86400, 0.03, 0)
    };

    public void Record(ExperienceKind kind, Personality p)
    {
        if (!Entries.TryGetValue(kind, out var e)) { e = new MemoryEntry(); Entries[kind] = e; }
        var info = Info(kind);
        e.Feeling = Math.Min(2, e.Feeling + 1);
        e.Lesson += (1 - e.Lesson) * info.Rate;
        e.Measures++;
        Dirty = true;
    }

    public void RememberPlace(V2 at, double comfort)
    {
        Places.Add(new PlaceMemory { Pos = at, Comfort = comfort });
        if (Places.Count > 12) Places.RemoveAt(0);
        Dirty = true;
    }

    public V2? FavouritePlace => Places.Count == 0 ? null : Places.MaxBy(p => p.Comfort)!.Pos;

    /// <summary>Feeling passes within the hour; the lesson fades over days (spec 13.3).</summary>
    public void Update(double dt)
    {
        foreach (var (kind, e) in Entries)
        {
            var info = Info(kind);
            e.Feeling *= Math.Exp(-Math.Log(2) * dt / info.Mood);
            e.Lesson *= Math.Exp(-Math.Log(2) * dt / info.Lasting);
        }
    }

    /// <summary>Closed time counts, but only up to three days.</summary>
    public void AdvanceOffline(double seconds)
    {
        if (seconds > 0) Update(Math.Min(seconds, 3 * 86400));
    }

    public TraitShift Shift(Personality p)
    {
        var shift = new TraitShift();
        foreach (var (kind, e) in Entries)
            shift.Add(Feels(kind, p).Scaled(Math.Min(1, e.Lesson)));
        return shift;
    }

    public Personality Effective(Personality baseP)
    {
        if (!LearnFromExperience) return baseP.Clone();
        var s = Shift(baseP);
        var p = baseP.Clone();
        p.Energy = M.Clamp01(p.Energy + M.Clamp(s.Energy, -0.2, 0.2));
        p.Curiosity = M.Clamp01(p.Curiosity + M.Clamp(s.Curiosity, -0.2, 0.2));
        p.Bravery = M.Clamp01(p.Bravery + M.Clamp(s.Bravery, -0.2, 0.2));
        p.Playfulness = M.Clamp01(p.Playfulness + M.Clamp(s.Playfulness, -0.2, 0.2));
        p.Affection = M.Clamp01(p.Affection + M.Clamp(s.Affection, -0.2, 0.2));
        p.Laziness = M.Clamp01(p.Laziness + M.Clamp(s.Laziness, -0.2, 0.2));
        return p;
    }

    public double ProwessOffset(Personality p) => M.Clamp(Shift(p).Prowess, -0.2, 0.2);

    public double HabitLean(string dial, Personality p)
    {
        var s = Shift(p);
        return dial switch
        {
            "Wander" or "Wandering" => M.Clamp(1 + 0.4 * s.Roaming, 0.4, 1.6),
            "Dance" or "Dancing" => M.Clamp(1 + 0.3 * s.Playfulness, 0.4, 1.6),
            "Approach" or "Coming to see the pointer" => M.Clamp(1 + 0.3 * s.Affection, 0.4, 1.6),
            "Greet" or "Greeting" => M.Clamp(1 + 0.3 * s.Affection, 0.4, 1.6),
            "Curious" or "Craning at it" => M.Clamp(1 + 0.3 * s.Curiosity, 0.4, 1.6),
            _ => 1
        };
    }

    public double MoodGlow => Entries.Sum(e => Math.Max(0, e.Value.Feeling) * Info(e.Key).Comfort);
    public double MoodShaken => Entries.Sum(e => Math.Max(0, e.Value.Feeling) * Math.Max(0, -Info(e.Key).Comfort));

    public string Summary
    {
        get
        {
            if (Entries.Count == 0) return "still exactly as designed";
            var top = Entries.OrderByDescending(e => e.Value.Measures).First();
            return $"shaped by {top.Key.ToString().ToLowerInvariant()} ×{top.Value.Measures}";
        }
    }

    public void ForgetAll()
    {
        Entries.Clear();
        Places.Clear();
        Dirty = true;
    }

    public string ToJson() => JsonSerializer.Serialize(this, JsonOpts);

    public static SpiderMemory FromJson(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new SpiderMemory();
        try { return JsonSerializer.Deserialize<SpiderMemory>(json, JsonOpts) ?? new SpiderMemory(); }
        catch { return new SpiderMemory(); }
    }

    public void Save(Settings settings)
    {
        settings.SetString("memory", ToJson());
        Dirty = false;
    }

    public static SpiderMemory Load(Settings settings) => FromJson(settings.GetString("memory"));

    /// <summary>The exact per-measure lessons (spec 13.2).</summary>
    public static TraitShift Feels(ExperienceKind kind, Personality p)
    {
        var t = new TraitShift();
        switch (kind)
        {
            case ExperienceKind.Petted:
                t.Affection = 1; t.Bravery = 0.6; t.Curiosity = 0.3; t.Laziness = 0.15; t.Roaming = -0.3;
                break;
            case ExperienceKind.Greeted:
                t.Affection = 0.8; t.Curiosity = 0.5; t.Bravery = 0.4; t.Roaming = -0.2;
                break;
            case ExperienceKind.Company:
                t.Affection = 0.5; t.Bravery = 0.5; t.Curiosity = 0.3; t.Roaming = -0.4;
                break;
            case ExperienceKind.Carried:
                t.Bravery = 0.4; t.Affection = 0.3; t.Curiosity = 0.1;
                break;
            case ExperienceKind.Thrown:
            {
                double joy = (p.Bravery + p.Playfulness) - 1;
                t.Playfulness = 0.1 + 0.6 * Math.Max(joy, 0);
                t.Energy = 0.3 * Math.Max(joy, 0);
                t.Bravery = -0.1 - 0.7 * Math.Max(-joy, 0);
                t.Affection = -0.4 * Math.Max(-joy, 0);
                t.Roaming = 0.2 * Math.Max(-joy, 0);
                break;
            }
            case ExperienceKind.Startled:
                t.Bravery = -1; t.Curiosity = -0.3; t.Laziness = -0.2; t.Energy = 0.1;
                break;
            case ExperienceKind.Chased:
            {
                double joy = 2 * p.Playfulness - 1;
                t.Playfulness = 0.4 * Math.Max(joy, 0);
                t.Energy = 0.3 * Math.Max(joy, 0);
                t.Bravery = -0.2 - 0.8 * Math.Max(-joy, 0);
                t.Curiosity = -0.3 * Math.Max(-joy, 0);
                t.Roaming = 0.3 * Math.Max(-joy, 0);
                break;
            }
            case ExperienceKind.Played:
                t.Playfulness = 1; t.Energy = 0.5; t.Affection = 0.3; t.Laziness = -0.4; t.Bravery = 0.2;
                break;
            case ExperienceKind.Fed:
                t.Laziness = 0.3; t.Prowess = 0.2; t.Affection = 0.2; t.Energy = -0.1;
                break;
            case ExperienceKind.HuntWon:
                t.Prowess = 1; t.Bravery = 0.3; t.Energy = 0.2;
                break;
            case ExperienceKind.HuntMissed:
                t.Prowess = -0.6; t.Bravery = -0.1;
                break;
            case ExperienceKind.Alone:
                t.Roaming = 1; t.Curiosity = 0.4; t.Energy = 0.2;
                break;
        }
        return t;
    }
}

/// <summary>Stage 13 wiring: memories react to what happens and feed the choices.</summary>
public sealed partial class Spider
{
    public readonly SpiderMemory Memory = new();
    double _memoryMinute;
    double _placeClock;

    public Personality ActivePersonality => Memory.Effective(Design.Personality);
    public TraitShift LearnedShift => Memory.Shift(Design.Personality);

    void Remember(ExperienceKind kind) => Memory.Record(kind, Design.Personality);

    void UpdateMemory(double dt)
    {
        Memory.Update(dt);
        _memoryMinute += dt;
        if (_memoryMinute >= 60 && Time > 300)
        {
            _memoryMinute = 0;
            if (UserIdleFor > 300) Remember(ExperienceKind.Alone);
            else if (UserIdleFor < 120) Remember(ExperienceKind.Company);
        }
        _placeClock += dt;
        if (_placeClock > 45 && Mode == Mode.Attached)
        {
            _placeClock = 0;
            Memory.RememberPlace(Pos, Memory.MoodGlow - Memory.MoodShaken);
        }
        Prowess = M.Clamp01(0.5 + Memory.ProwessOffset(Design.Personality));
    }

    void OnPointerMemory(PointerMemoryEvent e)
    {
        Remember(e switch
        {
            PointerMemoryEvent.Greeted => ExperienceKind.Greeted,
            PointerMemoryEvent.Carried => ExperienceKind.Carried,
            PointerMemoryEvent.Thrown => ExperienceKind.Thrown,
            PointerMemoryEvent.Stroked => ExperienceKind.Petted,
            PointerMemoryEvent.Scared => ExperienceKind.Startled,
            _ => ExperienceKind.Played
        });
    }
}
