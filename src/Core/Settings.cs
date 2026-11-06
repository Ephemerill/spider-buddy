using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace SpiderBuddy.Core;

/// <summary>
/// A typed key/value settings store, JSON on disk, written atomically (spec 1.5).
/// Tolerant on read: unknown keys are ignored (and preserved), missing keys default.
/// Underlying storage is an interface so the core never touches the filesystem directly in tests.
/// </summary>
public interface ITextFileStore
{
    string? Read(string name);
    void Write(string name, string contents);
    IEnumerable<string> List(string folder);
    string? ReadIn(string folder, string name);
    void WriteIn(string folder, string name, string contents);
    void DeleteIn(string folder, string name);
    string Describe();
}

/// <summary>Settings with the exact key names from Appendix B, tolerant round-tripping.</summary>
public sealed class Settings
{
    readonly ITextFileStore _store;
    readonly JsonObject _root;
    readonly object _lock = new();

    public string StoreDescription => _store.Describe();
    public bool Dirty { get; private set; }

    public Settings(ITextFileStore store)
    {
        _store = store;
        _root = Load(store);
    }

    static JsonObject Load(ITextFileStore store)
    {
        try
        {
            string? text = store.Read("settings.json");
            if (string.IsNullOrWhiteSpace(text)) return new JsonObject();
            JsonNode? node = JsonNode.Parse(text, documentOptions: new JsonDocumentOptions
            {
                AllowTrailingCommas = true,
                CommentHandling = JsonCommentHandling.Skip
            });
            return node as JsonObject ?? new JsonObject();
        }
        catch
        {
            // A corrupt file must never stop the app starting.
            return new JsonObject();
        }
    }

    // ---------------------------------------------------------------- primitives

    public double GetDouble(string key, double def)
        => _root.TryGetPropertyValue(key, out var n) && n is JsonValue v && v.TryGetValue(out double d) && double.IsFinite(d) ? d : def;

    public void SetDouble(string key, double value)
    {
        lock (_lock) { _root[key] = value; Dirty = true; }
    }

    public int GetInt(string key, int def)
        => _root.TryGetPropertyValue(key, out var n) && n is JsonValue v && v.TryGetValue(out int i) ? i : (int)GetDouble(key, def);

    public void SetInt(string key, int value)
    {
        lock (_lock) { _root[key] = value; Dirty = true; }
    }

    public bool GetBool(string key, bool def)
        => _root.TryGetPropertyValue(key, out var n) && n is JsonValue v && v.TryGetValue(out bool b) ? b : def;

    public void SetBool(string key, bool value)
    {
        lock (_lock) { _root[key] = value; Dirty = true; }
    }

    public string? GetString(string key)
        => _root.TryGetPropertyValue(key, out var n) && n is JsonValue v && v.TryGetValue(out string? s) ? s : null;

    public void SetString(string key, string? value)
    {
        lock (_lock)
        {
            if (value is null) _root.Remove(key); else _root[key] = value;
            Dirty = true;
        }
    }

    public bool Has(string key) => _root.ContainsKey(key);

    public void Remove(string key)
    {
        lock (_lock) { _root.Remove(key); Dirty = true; }
    }

    // ---------------------------------------------------------------- structured values

    /// <summary>Store an arbitrary object as JSON under a key.</summary>
    public void SetObject<T>(string key, T value, JsonSerializerOptions? options = null)
    {
        lock (_lock)
        {
            _root[key] = JsonSerializer.SerializeToNode(value, options);
            Dirty = true;
        }
    }

    /// <summary>Tolerant read: any failure or absence yields <paramref name="def"/>.</summary>
    public T GetObject<T>(string key, T def, JsonSerializerOptions? options = null)
    {
        try
        {
            if (!_root.TryGetPropertyValue(key, out var n) || n is null) return def;
            return n.Deserialize<T>(options) ?? def;
        }
        catch
        {
            return def;
        }
    }

    public JsonNode? GetNode(string key) => _root.TryGetPropertyValue(key, out var n) ? n : null;
    public void SetNode(string key, JsonNode? node) { lock (_lock) { _root[key] = node; Dirty = true; } }

    /// <summary>Resolve a point as a pair (used for confine / habitatGlass / habitatCamera).</summary>
    public V2? GetPoint(string key)
    {
        if (!_root.TryGetPropertyValue(key, out var n) || n is not JsonObject o) return null;
        double x = o.TryGetPropertyValue("x", out var nx) && nx is JsonValue vx && vx.TryGetValue(out double dx) ? dx : double.NaN;
        double y = o.TryGetPropertyValue("y", out var ny) && ny is JsonValue vy && vy.TryGetValue(out double dy) ? dy : double.NaN;
        return double.IsFinite(x) && double.IsFinite(y) ? new V2(x, y) : null;
    }

    public void SetPoint(string key, V2? p)
    {
        lock (_lock)
        {
            if (p is null) _root.Remove(key);
            else _root[key] = new JsonObject { ["x"] = p.Value.X, ["y"] = p.Value.Y };
            Dirty = true;
        }
    }

    /// <summary>A rect as {x,y,w,h} (confine box).</summary>
    public Rect? GetRect(string key)
    {
        if (!_root.TryGetPropertyValue(key, out var n) || n is not JsonObject o) return null;
        double R(string k, double d) => o.TryGetPropertyValue(k, out var v) && v is JsonValue jv && jv.TryGetValue(out double dv) ? dv : d;
        var r = new Rect(R("x", double.NaN), R("y", double.NaN), R("w", double.NaN), R("h", double.NaN));
        return r.IsValid ? r : null;
    }

    public void SetRect(string key, Rect? r)
    {
        lock (_lock)
        {
            if (r is null || !r.Value.IsValid) _root.Remove(key);
            else _root[key] = new JsonObject { ["x"] = r.Value.X, ["y"] = r.Value.Y, ["w"] = r.Value.W, ["h"] = r.Value.H };
            Dirty = true;
        }
    }

    // ---------------------------------------------------------------- persistence

    /// <summary>Write atomically (temp + replace). Saves everything, including keys we do not understand.</summary>
    public void Save(bool force = false)
    {
        if (!Dirty && !force) return;
        lock (_lock)
        {
            var opts = new JsonSerializerOptions { WriteIndented = true };
            _store.Write("settings.json", _root.ToJsonString(opts));
            Dirty = false;
        }
    }

    public string ToJson() => _root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });

    /// <summary>All keys currently present — used by tests to prove unknown keys round-trip.</summary>
    public IReadOnlyList<string> Keys => _root.Select(kv => kv.Key).OrderBy(k => k, StringComparer.Ordinal).ToList();
}

/// <summary>A simple rectangle in y-up world coordinates (matches CGRect semantics where used).</summary>
public readonly struct Rect
{
    public readonly double X, Y, W, H;

    public Rect(double x, double y, double w, double h) { X = x; Y = y; W = w; H = h; }

    public bool IsValid => double.IsFinite(X) && double.IsFinite(Y) && double.IsFinite(W) && double.IsFinite(H) && W >= 0 && H >= 0;
    public static Rect Zero => new(0, 0, 0, 0);

    public double MinX => X;
    public double MaxX => X + W;
    public double MinY => Y;
    public double MaxY => Y + H;
    public V2 Min => new(MinX, MinY);
    public V2 Max => new(MaxX, MaxY);
    public V2 Mid => new(X + W / 2, Y + H / 2);
    public V2 TopLeft => new(MinX, MaxY);
    public V2 TopRight => new(MaxX, MaxY);
    public V2 BottomLeft => new(MinX, MinY);
    public V2 BottomRight => new(MaxX, MinY);

    public static Rect FromLTRB(double l, double b, double r, double t) => new(l, b, r - l, t - b);

    /// <summary>Grow outward on every side (negative inset shrinks).</summary>
    public Rect Inset(double d) => new(X - d, Y - d, W + 2 * d, H + 2 * d);
    public Rect Inset(double dx, double dy) => new(X - dx, Y - dy, W + 2 * dx, H + 2 * dy);

    public bool Contains(V2 p) => p.X >= MinX && p.X <= MaxX && p.Y >= MinY && p.Y <= MaxY;

    public bool Contains(Rect o) => o.MinX >= MinX && o.MaxX <= MaxX && o.MinY >= MinY && o.MaxY <= MaxY;

    public bool Intersects(Rect o) => !(o.MinX >= MaxX || o.MaxX <= MinX || o.MinY >= MaxY || o.MaxY <= MinY);

    public Rect Intersection(Rect o)
    {
        double l = Math.Max(MinX, o.MinX), b = Math.Max(MinY, o.MinY);
        double r = Math.Min(MaxX, o.MaxX), t = Math.Min(MaxY, o.MaxY);
        if (r <= l || t <= b) return Zero;
        return FromLTRB(l, b, r, t);
    }

    public Rect Union(Rect o)
    {
        if (!IsValid) return o;
        if (!o.IsValid) return this;
        return FromLTRB(Math.Min(MinX, o.MinX), Math.Min(MinY, o.MinY), Math.Max(MaxX, o.MaxX), Math.Max(MaxY, o.MaxY));
    }

    public Rect Offset(double dx, double dy) => new(X + dx, Y + dy, W, H);

    public bool IsEmpty => W <= 0 || H <= 0;

    public double Area => W * H;

    public bool ApproximatelyEquals(Rect o, double tol = 0.5)
        => Math.Abs(X - o.X) <= tol && Math.Abs(Y - o.Y) <= tol && Math.Abs(W - o.W) <= tol && Math.Abs(H - o.H) <= tol;

    public override string ToString() => $"[{X:0.#},{Y:0.#} {W:0.#}x{H:0.#}]";
}

/// <summary>
/// Liang–Barsky segment-vs-rect clip. Returns the clipped t-range on the segment (t0 &lt; t1)
/// and false when the segment misses the rect entirely (spec 2.3 span()).
/// </summary>
public static class Clip
{
    public static bool SegmentInRect(V2 a, V2 b, Rect r, out double t0, out double t1)
    {
        t0 = 0; t1 = 1;
        double dx = b.X - a.X, dy = b.Y - a.Y;
        double p, q;

        // left
        p = -dx; q = a.X - r.MinX;
        if (!ClipEdge(p, q, ref t0, ref t1)) return false;
        // right
        p = dx; q = r.MaxX - a.X;
        if (!ClipEdge(p, q, ref t0, ref t1)) return false;
        // bottom
        p = -dy; q = a.Y - r.MinY;
        if (!ClipEdge(p, q, ref t0, ref t1)) return false;
        // top
        p = dy; q = r.MaxY - a.Y;
        if (!ClipEdge(p, q, ref t0, ref t1)) return false;

        return t1 > t0;
    }

    static bool ClipEdge(double p, double q, ref double t0, ref double t1)
    {
        if (Math.Abs(p) < 1e-12) return q >= 0;   // parallel: inside or outside
        double r = q / p;
        if (p < 0) { if (r > t1) return false; if (r > t0) t0 = r; }
        else { if (r < t0) return false; if (r < t1) t1 = r; }
        return true;
    }
}
