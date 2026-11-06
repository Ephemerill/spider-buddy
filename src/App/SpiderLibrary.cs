using System.Text.Json;
using SpiderBuddy.Core;

namespace SpiderBuddy.App;

public sealed class SavedSpider
{
    public string Id = "";
    public DateTime Made = DateTime.UtcNow;
    public SpiderDesign Design = new();

    public string Name => string.IsNullOrWhiteSpace(Design.Name) ? "Spider" : Design.Name;

    public bool Matches(SpiderDesign d)
    {
        var a = Design.Clone();
        var b = d.Clone();
        a.Gait.Motion = LegMotion.Classic;
        b.Gait.Motion = LegMotion.Classic;
        return a.ToJson() == b.ToJson();
    }
}

/// <summary>One JSON per saved spider, under %APPDATA%\SpiderBuddy\Spiders.</summary>
public sealed class SpiderLibrary
{
    readonly string _folder;
    readonly Settings _settings;
    readonly DiskStore _store;
    static readonly JsonSerializerOptions JsonOptions = new() { IncludeFields = true, WriteIndented = true };

    public SpiderLibrary(DiskStore store, Settings settings)
    {
        _store = store;
        _settings = settings;
        _folder = Environment.GetEnvironmentVariable("SPIDER_LIBRARY") is { Length: > 0 } overridePath
            ? overridePath
            : Path.Combine(store.Root, "Spiders");
    }

    public string Folder => _folder;

    public string? CurrentID
    {
        get => _settings.GetString("spiderCurrentSave");
        set
        {
            if (string.IsNullOrWhiteSpace(value)) _settings.Remove("spiderCurrentSave");
            else _settings.SetString("spiderCurrentSave", value);
        }
    }

    public SavedSpider? Current => CurrentID is { } id ? Saved(id) : null;

    public IReadOnlyList<SavedSpider> All()
    {
        if (!Directory.Exists(_folder)) return Array.Empty<SavedSpider>();
        var list = new List<SavedSpider>();
        foreach (string path in Directory.GetFiles(_folder, "*.json"))
        {
            try
            {
                var s = JsonSerializer.Deserialize<SavedSpider>(File.ReadAllText(path), JsonOptions);
                if (s is null || string.IsNullOrWhiteSpace(s.Id)) continue;
                if (s.Made == default) s.Made = File.GetCreationTimeUtc(path);
                list.Add(s);
            }
            catch { }
        }
        return list.OrderBy(s => s.Made).ToArray();
    }

    public SavedSpider? Saved(string id) => All().FirstOrDefault(s => s.Id == id);

    public void Seed(SpiderDesign design)
    {
        if (Directory.Exists(_folder)) return;
        Directory.CreateDirectory(_folder);
        var s = new SavedSpider { Id = Guid.NewGuid().ToString("N"), Made = DateTime.UtcNow, Design = design.Clone() };
        if (Store(s)) CurrentID = s.Id;
    }

    public bool Store(SavedSpider s)
    {
        try
        {
            Directory.CreateDirectory(_folder);
            File.WriteAllText(Path.Combine(_folder, s.Id + ".json"), JsonSerializer.Serialize(s, JsonOptions));
            return true;
        }
        catch { return false; }
    }

    public SavedSpider? Create(SpiderDesign design)
    {
        string baseName = string.IsNullOrWhiteSpace(design.Name) ? "Spider" : design.Name.Trim();
        var copy = design.Clone();
        copy.Name = FreshName(baseName);
        var s = new SavedSpider { Id = Guid.NewGuid().ToString("N"), Made = DateTime.UtcNow, Design = copy };
        if (!Store(s)) return null;
        CurrentID = s.Id;
        return s;
    }

    public void Delete(string id)
    {
        try { File.Delete(Path.Combine(_folder, id + ".json")); } catch { }
        if (CurrentID == id) CurrentID = null;
    }

    public string FreshName(string baseName)
    {
        var names = new HashSet<string>(All().Select(s => s.Name), StringComparer.OrdinalIgnoreCase);
        if (!names.Contains(baseName)) return baseName;
        int n = 2;
        while (names.Contains(baseName + " " + n)) n++;
        return baseName + " " + n;
    }
}
