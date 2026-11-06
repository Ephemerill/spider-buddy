using System.Text.Json.Nodes;

namespace SpiderBuddy.Core;

/// <summary>A habitat put by: one JSON file in My Habitats (Swift SavedHabitat).</summary>
public sealed class SavedHabitat
{
    public string Id = "";
    public string Name = "";
    public DateTime Saved = DateTime.UtcNow;
    public HabitatWorld Habitat = HabitatWorld.Empty();

    public string When
    {
        get
        {
            var local = Saved.ToLocalTime();
            if (local.Date == DateTime.Today) return "Today, " + local.ToString("HH:mm");
            if (local.Date == DateTime.Today.AddDays(-1)) return "Yesterday, " + local.ToString("HH:mm");
            return local.Year == DateTime.Today.Year ? local.ToString("d MMM") : local.ToString("d MMM y");
        }
    }

    /// <summary>Its habitat ready for a tank of this size, centred, hanging things from the new lid.</summary>
    public HabitatWorld Fitted(SizeD world)
    {
        var h = Habitat.Clone();
        h.GiveIdentities();
        if (Math.Abs(h.Width - world.Width) > .5 || Math.Abs(h.Height - world.Height) > .5)
            h = h.MovedIntoWorld(world);
        h.ClampAll();
        h.PruneLinks();
        return h;
    }

    public string ToJson()
    {
        var habitat = JsonNode.Parse(Habitat.ToJson()) ?? new JsonObject();
        return new JsonObject
        {
            ["id"] = Id, ["name"] = Name,
            ["saved"] = Saved.ToUniversalTime().ToString("O"),
            ["habitat"] = habitat
        }.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
    }

    public static SavedHabitat? FromJson(string? json)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(json)) return null;
            if (JsonNode.Parse(json) is not JsonObject o) return null;
            string id = o["id"]?.GetValue<string>() ?? "";
            string name = o["name"]?.GetValue<string>() ?? "";
            string saved = o["saved"]?.GetValue<string>() ?? "";
            if (o["habitat"] is not JsonObject habitat) return null;
            var h = HabitatWorld.FromJson(habitat.ToJsonString());
            if (h is null) return null;
            DateTime when = DateTime.TryParse(saved, null,
                System.Globalization.DateTimeStyles.RoundtripKind, out var parsed) ? parsed.ToUniversalTime() : DateTime.UtcNow;
            return new SavedHabitat
            {
                Id = string.IsNullOrWhiteSpace(id) ? Guid.NewGuid().ToString("D") : id,
                Name = string.IsNullOrWhiteSpace(name) ? h.Name : name,
                Saved = when, Habitat = h
            };
        }
        catch { return null; }
    }
}

/// <summary>My Habitats: one JSON per saved tank, newest first (Swift HabitatLibrary).</summary>
public static class HabitatLibrary
{
    public const string Extension = "spiderhabitat";

    public static string Folder
    {
        get
        {
            string? over = Environment.GetEnvironmentVariable("SPIDER_HABITAT_LIBRARY");
            if (!string.IsNullOrWhiteSpace(over)) return over;
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "SpiderBuddy", "Habitats");
        }
    }

    static string PathOf(string id) => Path.Combine(Folder, id + ".json");

    public static IReadOnlyList<SavedHabitat> All()
    {
        try
        {
            if (!Directory.Exists(Folder)) return Array.Empty<SavedHabitat>();
            var list = new List<SavedHabitat>();
            foreach (string path in Directory.GetFiles(Folder, "*.json"))
            {
                try
                {
                    var saved = SavedHabitat.FromJson(File.ReadAllText(path));
                    if (saved is null) continue;
                    if (string.IsNullOrWhiteSpace(saved.Id)) saved.Id = Path.GetFileNameWithoutExtension(path);
                    list.Add(saved);
                }
                catch { }
            }
            return list.OrderByDescending(s => s.Saved).ToArray();
        }
        catch { return Array.Empty<SavedHabitat>(); }
    }

    public static SavedHabitat? Saved(string? id) =>
        string.IsNullOrWhiteSpace(id) ? null : All().FirstOrDefault(s => s.Id == id);

    public static bool Store(SavedHabitat saved)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(saved.Id)) saved.Id = Guid.NewGuid().ToString("D");
            Directory.CreateDirectory(Folder);
            string path = PathOf(saved.Id);
            string tmp = path + ".tmp";
            File.WriteAllText(tmp, saved.ToJson());
            File.Move(tmp, path, overwrite: true);
            return true;
        }
        catch { return false; }
    }

    public static void Delete(string id)
    {
        try { File.Delete(PathOf(id)); } catch { }
    }

    public static bool Rename(string id, string name)
    {
        var saved = Saved(id);
        if (saved is null || string.IsNullOrWhiteSpace(name)) return false;
        saved.Name = name.Trim();
        return Store(saved);
    }

    public static string FreshName(string basename)
    {
        var names = All().Select(s => s.Name.ToLowerInvariant()).ToHashSet();
        if (!names.Contains(basename.ToLowerInvariant())) return basename;
        int n = 2;
        while (names.Contains($"{basename} {n}".ToLowerInvariant())) n++;
        return $"{basename} {n}";
    }

    public static void Export(SavedHabitat saved, string path)
    {
        string dir = Path.GetDirectoryName(Path.GetFullPath(path)) ?? Folder;
        Directory.CreateDirectory(dir);
        File.WriteAllText(path, saved.ToJson());
    }

    public static SavedHabitat ImportFile(string path)
    {
        string json = File.ReadAllText(path);
        var whole = SavedHabitat.FromJson(json);
        if (whole is null)
        {
            var h = HabitatWorld.FromJson(json) ?? throw new InvalidDataException("Not a habitat");
            whole = new SavedHabitat
            {
                Id = Guid.NewGuid().ToString("D"),
                Name = Path.GetFileNameWithoutExtension(path),
                Saved = DateTime.UtcNow, Habitat = h
            };
        }
        whole.Id = Guid.NewGuid().ToString("D");
        whole.Name = FreshName(string.IsNullOrWhiteSpace(whole.Name) ? Path.GetFileNameWithoutExtension(path) : whole.Name);
        whole.Saved = DateTime.UtcNow;
        if (!Store(whole)) throw new IOException("Could not save the habitat");
        return whole;
    }
}
