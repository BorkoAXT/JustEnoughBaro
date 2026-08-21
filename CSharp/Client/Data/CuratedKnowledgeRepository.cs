#nullable enable

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using Barotrauma;

namespace JustEnoughBaro;

/// <summary>
/// Loads small editorial datasets that complement live prefab data. The game prefabs remain
/// authoritative; this repository only supplies prose and official-wiki reference fields.
/// </summary>
internal sealed class CuratedKnowledgeRepository
{
    internal sealed class ProfessionKnowledge
    {
        [JsonIgnore]
        public string Identifier { get; internal set; } = string.Empty;

        public List<string> Responsibilities { get; set; } = new();
        public List<string> Tips { get; set; } = new();
        public string Source { get; set; } = string.Empty;
    }

    internal sealed class SubmarineKnowledge
    {
        [JsonIgnore]
        public string Identifier { get; internal set; } = string.Empty;

        public float HorizontalSpeed { get; set; }
        public float DescentSpeed { get; set; }
        public List<string> Weapons { get; set; } = new();
        public int Hardpoints { get; set; }
        public int LargeHardpoints { get; set; }
        public List<string> Other { get; set; } = new();
        public string Source { get; set; } = string.Empty;
    }

    private sealed class KnowledgeDocument
    {
        public int SchemaVersion { get; set; }
        public Dictionary<string, ProfessionKnowledge> Professions { get; set; } =
            new(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, SubmarineKnowledge> Submarines { get; set; } =
            new(StringComparer.OrdinalIgnoreCase);
    }

    private readonly Dictionary<string, ProfessionKnowledge> professionIndex =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, SubmarineKnowledge> submarineIndex =
        new(StringComparer.OrdinalIgnoreCase);

    public CuratedKnowledgeRepository()
    {
        DataPath = ResolveDataPath();
        Load();
    }

    public string DataPath { get; }
    public int SchemaVersion { get; private set; }
    public IReadOnlyCollection<ProfessionKnowledge> Professions { get; private set; } =
        Array.Empty<ProfessionKnowledge>();
    public IReadOnlyCollection<SubmarineKnowledge> Submarines { get; private set; } =
        Array.Empty<SubmarineKnowledge>();

    public bool TryGetProfession(
        CatalogRecord record,
        out ProfessionKnowledge knowledge)
    {
        if (record.Kind == PrefabKind.Profession)
        {
            return TryGetProfession(record.Identifier, record.Name, out knowledge);
        }
        knowledge = null!;
        return false;
    }

    public bool TryGetProfession(
        string? identifier,
        string? name,
        out ProfessionKnowledge knowledge)
        => TryLookup(professionIndex, identifier, name, out knowledge);

    public ProfessionKnowledge? FindProfession(string? identifier, string? name = null)
        => TryGetProfession(identifier, name, out ProfessionKnowledge knowledge) ? knowledge : null;

    public bool TryGetSubmarine(
        CatalogRecord record,
        out SubmarineKnowledge knowledge)
    {
        if (record.Kind == PrefabKind.Submarine)
        {
            return TryGetSubmarine(record.Identifier, record.Name, out knowledge);
        }
        knowledge = null!;
        return false;
    }

    public bool TryGetSubmarine(
        string? identifier,
        string? name,
        out SubmarineKnowledge knowledge)
        => TryLookup(submarineIndex, identifier, name, out knowledge);

    public SubmarineKnowledge? FindSubmarine(string? identifier, string? name = null)
        => TryGetSubmarine(identifier, name, out SubmarineKnowledge knowledge) ? knowledge : null;

    private void Load()
    {
        if (string.IsNullOrWhiteSpace(DataPath)) { return; }

        try
        {
            KnowledgeDocument? document = JsonSerializer.Deserialize<KnowledgeDocument>(
                File.ReadAllText(DataPath),
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (document is null) { return; }

            SchemaVersion = document.SchemaVersion;
            foreach ((string identifier, ProfessionKnowledge value) in document.Professions)
            {
                value.Identifier = TextTools.NormalizeIdentifier(identifier);
                AddAliases(professionIndex, value, value.Identifier, value.Source);
            }
            foreach ((string identifier, SubmarineKnowledge value) in document.Submarines)
            {
                value.Identifier = TextTools.NormalizeIdentifier(identifier);
                AddAliases(submarineIndex, value, value.Identifier, value.Source);
            }

            Professions = document.Professions.Values.Distinct().ToArray();
            Submarines = document.Submarines.Values.Distinct().ToArray();
        }
        catch (Exception exception)
        {
            LuaCsLogger.LogError($"[JEB] Could not read curated knowledge data: {exception.Message}");
        }
    }

    private static bool TryLookup<T>(
        IReadOnlyDictionary<string, T> index,
        string? identifier,
        string? name,
        out T value)
        where T : class
    {
        foreach (string candidate in LookupKeys(identifier).Concat(LookupKeys(name)))
        {
            if (index.TryGetValue(candidate, out T? found))
            {
                value = found;
                return true;
            }
        }
        value = null!;
        return false;
    }

    private static void AddAliases<T>(
        IDictionary<string, T> index,
        T value,
        string identifier,
        string source)
    {
        foreach (string key in LookupKeys(identifier)) { index[key] = value; }

        if (Uri.TryCreate(source, UriKind.Absolute, out Uri? uri))
        {
            string sourceName = Uri.UnescapeDataString(uri.Segments.LastOrDefault() ?? string.Empty)
                .Trim('/');
            foreach (string key in LookupKeys(sourceName)) { index[key] = value; }
        }
    }

    private static IEnumerable<string> LookupKeys(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) { yield break; }

        string identifier = TextTools.NormalizeIdentifier(value);
        if (identifier.Length > 0) { yield return identifier; }

        string wikiKey = TextTools.WikiKey(value);
        if (wikiKey.Length > 0 && !wikiKey.Equals(identifier, StringComparison.OrdinalIgnoreCase))
        {
            yield return wikiKey;
        }
    }

    private static string ResolveDataPath()
    {
        const string relativePath = "Data/curated_knowledge.json";
        var candidates = new List<string>();

        try
        {
            ContentPackage? namedPackage = ContentPackageManager.EnabledPackages.All.FirstOrDefault(
                package => package.NameMatches("Just Enough Baro (JEB)") ||
                           package.NameMatches("Just Enough Baro") ||
                           package.NameMatches("Europa Dictionary"));
            if (namedPackage is not null) { candidates.Add(namedPackage.Dir); }

            candidates.AddRange(ContentPackageManager.EnabledPackages.All
                .Select(package => package.Dir)
                .Where(directory => !string.IsNullOrWhiteSpace(directory)));
        }
        catch { }

        try
        {
            string assemblyLocation = Assembly.GetExecutingAssembly().Location;
            if (!string.IsNullOrWhiteSpace(assemblyLocation))
            {
                candidates.Add(Path.GetDirectoryName(assemblyLocation) ?? string.Empty);
            }
        }
        catch { }

        candidates.Add(Directory.GetCurrentDirectory());
        foreach (string candidate in candidates.Where(path => !string.IsNullOrWhiteSpace(path)))
        {
            DirectoryInfo? directory;
            try { directory = new DirectoryInfo(Path.GetFullPath(candidate)); }
            catch { continue; }

            for (int depth = 0; directory is not null && depth < 7; depth++, directory = directory.Parent)
            {
                string path = Path.Combine(
                    directory.FullName,
                    relativePath.Replace('/', Path.DirectorySeparatorChar));
                if (File.Exists(path)) { return path; }
            }
        }
        return string.Empty;
    }
}
