#nullable enable

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Barotrauma;

namespace JustEnoughBaro;

internal sealed class CreatureMediaRepository : IDisposable
{
    internal sealed class Entry
    {
        public string Title { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;
        public string Image { get; set; } = string.Empty;
        public string Url { get; set; } = string.Empty;
    }

    private readonly Dictionary<string, Entry> entries = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, Sprite> sprites = new(StringComparer.OrdinalIgnoreCase);
    private readonly string modDirectory;

    public CreatureMediaRepository()
    {
        modDirectory = ResolveModDirectory();
        Load();
    }

    public Entry? Find(string identifier)
    {
        string key = NormalizeCreatureIdentifier(identifier);
        return entries.TryGetValue(key, out Entry? entry) ? entry : null;
    }

    public Sprite? GetSprite(string identifier)
    {
        string key = NormalizeCreatureIdentifier(identifier);
        if (sprites.TryGetValue(key, out Sprite? cached)) { return cached; }

        Entry? entry = Find(key);
        string relative = entry?.Image ?? string.Empty;
        if (string.IsNullOrWhiteSpace(relative))
        {
            relative = $"Assets/Creatures/{key}.png";
        }
        string path = Path.IsPathRooted(relative)
            ? relative
            : Path.Combine(modDirectory, relative.Replace('/', Path.DirectorySeparatorChar));
        if (!File.Exists(path)) { return null; }

        try
        {
            var sprite = new Sprite(path, sourceRectangle: null);
            sprites[key] = sprite;
            return sprite;
        }
        catch (Exception exception)
        {
            LuaCsLogger.LogError($"[JEB] Could not load creature preview {path}: {exception.Message}");
            return null;
        }
    }

    private void Load()
    {
        string path = Path.Combine(modDirectory, "Data", "creature_wiki.json");
        if (!File.Exists(path)) { return; }
        try
        {
            Dictionary<string, Entry>? loaded = JsonSerializer.Deserialize<Dictionary<string, Entry>>(
                File.ReadAllText(path),
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (loaded is null) { return; }
            foreach ((string key, Entry value) in loaded)
            {
                entries[NormalizeCreatureIdentifier(key)] = value;
            }
        }
        catch (Exception exception)
        {
            LuaCsLogger.LogError($"[JEB] Could not read creature media data: {exception.Message}");
        }
    }

    private static string NormalizeCreatureIdentifier(string identifier)
    {
        string value = TextTools.NormalizeIdentifier(identifier);
        if (value.EndsWith("_m", StringComparison.OrdinalIgnoreCase)) { value = value[..^2]; }
        return value switch
        {
            "mudraptorpet" => "mudraptor_pet",
            _ => value
        };
    }

    private static string ResolveModDirectory()
    {
        try
        {
            ContentPackage? package = ContentPackageManager.EnabledPackages.All.FirstOrDefault(
                candidate => candidate.NameMatches("Just Enough Baro (JEB)") ||
                             candidate.NameMatches("Just Enough Baro") ||
                             candidate.NameMatches("Europa Dictionary"));
            if (package is not null && !string.IsNullOrWhiteSpace(package.Dir)) { return package.Dir; }
        }
        catch { }
        return Directory.GetCurrentDirectory();
    }

    public void Dispose()
    {
        foreach (Sprite sprite in sprites.Values)
        {
            try { sprite.Remove(); }
            catch { }
        }
        sprites.Clear();
    }
}
