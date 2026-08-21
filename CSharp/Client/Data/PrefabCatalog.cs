#nullable enable

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Diagnostics;
using System.Linq;
using System.Xml.Linq;
using Barotrauma;

namespace JustEnoughBaro;

internal sealed class PrefabCatalog
{
    private sealed class SourceDefinition
    {
        public SourceDefinition(PrefabKind kind, string typeName, string[] collectionMembers)
        {
            Kind = kind;
            TypeName = typeName;
            CollectionMembers = collectionMembers;
        }

        public PrefabKind Kind { get; }
        public string TypeName { get; }
        public string[] CollectionMembers { get; }
    }

    private static readonly SourceDefinition[] Sources =
    {
        new(PrefabKind.Item, "Barotrauma.ItemPrefab", new[] { "Prefabs" }),
        new(PrefabKind.Affliction, "Barotrauma.AfflictionPrefab", new[] { "Prefabs" }),
        new(PrefabKind.Creature, "Barotrauma.CharacterPrefab", new[] { "Prefabs" }),
        new(PrefabKind.Biome, "Barotrauma.Biome", new[] { "Prefabs" }),
        new(PrefabKind.Talent, "Barotrauma.TalentPrefab", new[] { "TalentPrefabs", "Prefabs" }),
        new(PrefabKind.Profession, "Barotrauma.JobPrefab", new[] { "Prefabs" }),
        new(PrefabKind.Mission, "Barotrauma.MissionPrefab", new[] { "Prefabs" }),
        new(PrefabKind.Submarine, "Barotrauma.SubmarineInfo", new[] { "SavedSubmarines", "SavedSubmarineInfos" }),
        new(PrefabKind.Structure, "Barotrauma.StructurePrefab", new[] { "Prefabs" }),
        new(PrefabKind.Upgrade, "Barotrauma.UpgradePrefab", new[] { "Prefabs" }),
        new(PrefabKind.ItemAssembly, "Barotrauma.ItemAssemblyPrefab", new[] { "Prefabs" }),
        new(PrefabKind.LevelObject, "Barotrauma.LevelObjectPrefab", new[] { "Prefabs" }),
        new(PrefabKind.Event, "Barotrauma.EventPrefab", new[] { "Prefabs" })
    };

    private static readonly ConcurrentDictionary<string, CatalogSnapshot> MemoryCache =
        new(StringComparer.Ordinal);

    private readonly object buildGate = new();
    private readonly Dictionary<string, IReadOnlyList<RecipeInfo>> recipesByOutput =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, IReadOnlyList<DeconstructionOutput>> deconstructionBySource =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, IReadOnlyList<TreatmentLink>> treatmentsByAffliction =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, IReadOnlyList<AfflictionCauseLink>> causesByAffliction =
        new(StringComparer.OrdinalIgnoreCase);

    private CatalogSnapshot snapshot = CatalogSnapshot.Empty;

    public CatalogSnapshot Snapshot => snapshot;
    public long LastBuildMilliseconds { get; private set; }

    public CatalogSnapshot Build(bool force = false)
    {
        lock (buildGate)
        {
            string signature = BuildContentSignature();
            if (!force && snapshot != CatalogSnapshot.Empty && snapshot.Signature == signature)
            {
                return snapshot;
            }
            if (!force && MemoryCache.TryGetValue(signature, out CatalogSnapshot? cached))
            {
                snapshot = cached;
                BuildSpecializedIndexes(cached);
                return snapshot;
            }

            var timer = Stopwatch.StartNew();
            var records = new List<CatalogRecord>(4096);
            var byKey = new Dictionary<string, CatalogRecord>(StringComparer.OrdinalIgnoreCase);

            foreach (SourceDefinition source in Sources)
            {
                foreach (object prefab in EnumerateSource(source))
                {
                    CatalogRecord? record = CreateRecord(source.Kind, prefab);
                    if (record is null || byKey.ContainsKey(record.Key)) { continue; }
                    byKey.Add(record.Key, record);
                    records.Add(record);
                }
            }

            records.Sort(CompareRecords);
            var byKind = records
                .GroupBy(record => record.Kind)
                .ToDictionary(
                    group => group.Key,
                    group => (IReadOnlyList<CatalogRecord>)group.ToArray());

            BuildRecipeIndexes(records, out Dictionary<string, IReadOnlyList<RecipeUse>> usedIn,
                out Dictionary<string, IReadOnlyList<DeconstructionSource>> obtainedFrom);
            BuildAfflictionIndexes(records);

            snapshot = new CatalogSnapshot(
                records.ToArray(),
                byKey,
                byKind,
                usedIn,
                obtainedFrom,
                signature);
            MemoryCache[signature] = snapshot;
            timer.Stop();
            LastBuildMilliseconds = timer.ElapsedMilliseconds;
            return snapshot;
        }
    }

    public IReadOnlyList<RecipeInfo> GetRecipes(CatalogRecord record)
        => recipesByOutput.TryGetValue(record.Identifier, out IReadOnlyList<RecipeInfo>? recipes)
            ? recipes
            : Array.Empty<RecipeInfo>();

    public IReadOnlyList<DeconstructionOutput> GetDeconstruction(CatalogRecord record)
        => deconstructionBySource.TryGetValue(record.Identifier, out IReadOnlyList<DeconstructionOutput>? outputs)
            ? outputs
            : Array.Empty<DeconstructionOutput>();

    public IReadOnlyList<RecipeUse> GetUsage(CatalogRecord record)
        => snapshot.UsedIn.TryGetValue(record.Identifier, out IReadOnlyList<RecipeUse>? uses)
            ? uses
            : Array.Empty<RecipeUse>();

    public IReadOnlyList<DeconstructionSource> GetSources(CatalogRecord record)
        => snapshot.ObtainedFrom.TryGetValue(record.Identifier, out IReadOnlyList<DeconstructionSource>? sources)
            ? sources
            : Array.Empty<DeconstructionSource>();

    public IReadOnlyList<TreatmentLink> GetTreatments(CatalogRecord record)
        => treatmentsByAffliction.TryGetValue(record.Identifier, out IReadOnlyList<TreatmentLink>? links)
            ? links
            : Array.Empty<TreatmentLink>();

    public IReadOnlyList<AfflictionCauseLink> GetCauses(CatalogRecord record)
        => causesByAffliction.TryGetValue(record.Identifier, out IReadOnlyList<AfflictionCauseLink>? links)
            ? links
            : Array.Empty<AfflictionCauseLink>();

    public CatalogRecord? Find(PrefabKind kind, string identifier)
    {
        string key = $"{kind.StableName()}:{TextTools.NormalizeIdentifier(identifier)}";
        return snapshot.ByKey.TryGetValue(key, out CatalogRecord? record) ? record : null;
    }

    public CatalogRecord? FindItem(string identifier) => Find(PrefabKind.Item, identifier);

    public IEnumerable<CatalogRecord> Query(PrefabKind kind, string search, ISet<string> favorites)
    {
        IEnumerable<CatalogRecord> records = kind switch
        {
            PrefabKind.All => snapshot.All,
            PrefabKind.Favorite => snapshot.All.Where(record => favorites.Contains(record.Key)),
            _ => snapshot.ForKind(kind)
        };

        string normalized = TextTools.NormalizeSearch(search);
        return normalized.Length == 0
            ? records
            : records.Where(record => TextTools.SearchMatches(record.SearchText, normalized));
    }

    private static IEnumerable<object> EnumerateSource(SourceDefinition source)
    {
        Type? type = ReflectionTools.FindType(source.TypeName);
        if (type is null) { yield break; }

        object? collection = ReflectionTools.GetStaticMember(type, source.CollectionMembers);
        foreach (object prefab in ReflectionTools.Enumerate(collection))
        {
            yield return prefab;
        }
    }

    private static CatalogRecord? CreateRecord(PrefabKind kind, object prefab)
    {
        string identifier = IdentifierFor(kind, prefab);
        if (identifier.Length == 0) { return null; }
        ContentXElement? config = ReflectionTools.FindConfigElement(prefab);
        // Items and afflictions are the comprehensive reference families: hidden/debug and
        // mod-only prefabs remain searchable instead of being silently excluded.
        if (kind is not (PrefabKind.Item or PrefabKind.Affliction) && IsHidden(prefab, config))
        {
            return null;
        }
        if (kind == PrefabKind.Submarine && !IsBrowsableSubmarine(prefab)) { return null; }

        string name = FirstText(prefab, "DisplayName", "Name", "OriginalName", "Title");
        if (string.IsNullOrWhiteSpace(name)) { name = TextTools.Humanize(identifier); }
        string description = TextTools.CleanDisplayText(ReflectionTools.GetMember(
            prefab, "Description", "Tooltip", "FlavorText", "InfoText"));
        string tags = TextTools.JoinValues(ReflectionTools.GetMember(
            prefab, "Tags", "TagSet", "Category", "Type", "BiomeIdentifier"));
        string source = SourceFor(prefab);
        Sprite? icon = ReflectionTools.FindSprite(prefab);

        return new CatalogRecord(kind, identifier, name, description, tags, source, prefab, icon);
    }

    private static string IdentifierFor(PrefabKind kind, object prefab)
    {
        object? value = ReflectionTools.GetMember(prefab,
            "Identifier", "SpeciesName", "UintIdentifier", "Name");
        string identifier = TextTools.NormalizeIdentifier(value);
        if (identifier.Length > 0) { return identifier; }

        string name = FirstText(prefab, "Name", "DisplayName", "OriginalName", "Title");
        identifier = TextTools.NormalizeIdentifier(name);
        if (identifier.Length > 0) { return identifier; }
        return kind.StableName() + "-" + prefab.GetHashCode().ToString("x");
    }

    private static string FirstText(object prefab, params string[] members)
    {
        foreach (string member in members)
        {
            string value = TextTools.CleanDisplayText(ReflectionTools.GetMember(prefab, member));
            if (!string.IsNullOrWhiteSpace(value)) { return value; }
        }
        return string.Empty;
    }

    private static bool IsHidden(object prefab, ContentXElement? config)
    {
        if (ReflectionTools.GetMember(prefab, "Hidden", "HideInMenus", "HiddenJob") is bool hidden && hidden)
        {
            return true;
        }
        try
        {
            return config?.GetAttributeBool("hideinmenus", false) ?? false;
        }
        catch { return false; }
    }

    private static bool IsBrowsableSubmarine(object prefab)
    {
        if (ReflectionTools.GetMember(prefab, "IsFileCorrupted") is bool corrupted && corrupted) { return false; }
        if (ReflectionTools.GetMember(prefab, "IsBeacon") is bool beacon && beacon) { return false; }
        object? isPlayerValue = ReflectionTools.GetMember(prefab, "IsPlayer");
        if (isPlayerValue is bool isPlayer && !isPlayer) { return false; }
        string type = TextTools.NormalizeIdentifier(ReflectionTools.GetMember(prefab, "Type"));
        return !type.Contains("beaconstation", StringComparison.OrdinalIgnoreCase);
    }

    private static string SourceFor(object prefab)
    {
        object? contentFile = ReflectionTools.GetMember(prefab, "ContentFile", "File");
        object? package = ReflectionTools.GetMember(contentFile, "ContentPackage", "Package") ??
                          ReflectionTools.GetMember(prefab, "ContentPackage");
        string packageName = TextTools.Stringify(ReflectionTools.GetMember(package, "Name"));
        string path = TextTools.Stringify(ReflectionTools.GetMember(contentFile, "Path", "FilePath"));
        if (!string.IsNullOrWhiteSpace(path))
        {
            return string.IsNullOrWhiteSpace(packageName) ? path : $"{packageName} · {path}";
        }
        string direct = TextTools.Stringify(ReflectionTools.GetMember(prefab, "FilePath", "Path"));
        if (!string.IsNullOrWhiteSpace(direct))
        {
            return string.IsNullOrWhiteSpace(packageName) ? direct : $"{packageName} · {direct}";
        }
        return string.IsNullOrWhiteSpace(packageName) ? prefab.GetType().Name : packageName;
    }

    private static int CompareRecords(CatalogRecord left, CatalogRecord right)
    {
        int kind = left.Kind.CompareTo(right.Kind);
        if (kind != 0) { return kind; }
        int name = StringComparer.CurrentCultureIgnoreCase.Compare(left.Name, right.Name);
        return name != 0
            ? name
            : StringComparer.OrdinalIgnoreCase.Compare(left.Identifier, right.Identifier);
    }

    private void BuildRecipeIndexes(
        IReadOnlyList<CatalogRecord> records,
        out Dictionary<string, IReadOnlyList<RecipeUse>> usedIn,
        out Dictionary<string, IReadOnlyList<DeconstructionSource>> obtainedFrom)
    {
        recipesByOutput.Clear();
        deconstructionBySource.Clear();

        var mutableUsedIn = new Dictionary<string, List<RecipeUse>>(StringComparer.OrdinalIgnoreCase);
        var mutableSources = new Dictionary<string, List<DeconstructionSource>>(StringComparer.OrdinalIgnoreCase);

        foreach (CatalogRecord record in records.Where(record => record.Kind == PrefabKind.Item))
        {
            if (record.Prefab is not ItemPrefab prefab) { continue; }
            IReadOnlyList<RecipeInfo> recipes = ExtractRecipes(record, prefab);
            recipesByOutput[record.Identifier] = recipes;
            foreach (RecipeInfo recipe in recipes)
            {
                var use = new RecipeUse(record, recipe);
                foreach (string ingredientIdentifier in recipe.Ingredients
                             .SelectMany(ingredient => ingredient.Options)
                             .Select(option => option.Identifier)
                             .Distinct(StringComparer.OrdinalIgnoreCase))
                {
                    Add(mutableUsedIn, ingredientIdentifier, use,
                        existing => existing.Output.Key == use.Output.Key && existing.Recipe.Id == use.Recipe.Id);
                }
            }

            IReadOnlyList<DeconstructionOutput> outputs = ExtractDeconstruction(prefab);
            deconstructionBySource[record.Identifier] = outputs;
            foreach (DeconstructionOutput output in outputs)
            {
                var source = new DeconstructionSource(record, output);
                Add(mutableSources, output.Identifier, source,
                    existing => existing.Source.Key == source.Source.Key &&
                                existing.Output.Identifier == source.Output.Identifier);
            }
        }

        usedIn = mutableUsedIn.ToDictionary(
            pair => pair.Key,
            pair => (IReadOnlyList<RecipeUse>)pair.Value
                .OrderBy(value => value.Output.Name, StringComparer.CurrentCultureIgnoreCase)
                .ToArray(),
            StringComparer.OrdinalIgnoreCase);
        obtainedFrom = mutableSources.ToDictionary(
            pair => pair.Key,
            pair => (IReadOnlyList<DeconstructionSource>)pair.Value
                .OrderBy(value => value.Source.Name, StringComparer.CurrentCultureIgnoreCase)
                .ToArray(),
            StringComparer.OrdinalIgnoreCase);
    }

    private IReadOnlyList<RecipeInfo> ExtractRecipes(CatalogRecord output, ItemPrefab prefab)
    {
        var recipes = new List<RecipeInfo>();
        try
        {
            int ordinal = 0;
            foreach (FabricationRecipe recipe in prefab.FabricationRecipes.Values)
            {
                ordinal++;
                var ingredients = new List<RecipeIngredient>();
                foreach (FabricationRecipe.RequiredItem required in recipe.RequiredItems)
                {
                    IngredientOption[] options = required.ItemPrefabs
                        .Where(item => item is not null)
                        .Select(item => new IngredientOption(
                            TextTools.NormalizeIdentifier(item.Identifier),
                            TextTools.CleanDisplayText(item.Name)))
                        .GroupBy(option => option.Identifier, StringComparer.OrdinalIgnoreCase)
                        .Select(group => group.First())
                        .OrderBy(option => option.Name, StringComparer.CurrentCultureIgnoreCase)
                        .ToArray();
                    string tag = required is FabricationRecipe.RequiredItemByTag byTag
                        ? TextTools.NormalizeIdentifier(byTag.Tag)
                        : string.Empty;
                    ingredients.Add(new RecipeIngredient(
                        options,
                        required.Amount,
                        required.MinCondition,
                        required.MaxCondition,
                        required.UseCondition,
                        tag));
                }

                string[] skills = recipe.RequiredSkills
                    .Select(skill => $"{TextTools.Humanize(skill.Identifier)} {skill.Level}")
                    .ToArray();
                string[] fabricators = recipe.SuitableFabricatorIdentifiers
                    .Select(identifier => TextTools.Humanize(identifier))
                    .ToArray();
                recipes.Add(new RecipeInfo(
                    $"{output.Identifier}:{recipe.RecipeHash}:{ordinal}",
                    output.Identifier,
                    output.Name,
                    recipe.Amount,
                    recipe.RequiredTime,
                    fabricators,
                    ingredients,
                    skills,
                    recipe.RequiresRecipe,
                    recipe.RequiredMoney));
            }
        }
        catch (Exception exception)
        {
            LuaCsLogger.LogError($"[JEB] Could not index recipes for {output.Identifier}: {exception.Message}");
        }
        return recipes;
    }

    private IReadOnlyList<DeconstructionOutput> ExtractDeconstruction(ItemPrefab prefab)
    {
        var outputs = new List<DeconstructionOutput>();
        try
        {
            foreach (DeconstructItem output in prefab.DeconstructItems)
            {
                string identifier = TextTools.NormalizeIdentifier(output.ItemIdentifier);
                CatalogRecord? target = FindItemFromCurrentBuild(identifier);
                outputs.Add(new DeconstructionOutput
                {
                    Identifier = identifier,
                    Name = target?.Name ?? TextTools.Humanize(identifier),
                    Amount = output.Amount,
                    Probability = output.Commonness,
                    MinimumCondition = output.MinCondition,
                    MaximumCondition = output.MaxCondition,
                    OutputConditionMinimum = output.OutConditionMin,
                    OutputConditionMaximum = output.OutConditionMax,
                    RequiredDeconstructors = output.RequiredDeconstructor
                        .Select(identifier => TextTools.Stringify(identifier)).ToArray(),
                    RequiredOtherItems = output.RequiredOtherItem
                        .Select(identifier => TextTools.Stringify(identifier)).ToArray()
                });
            }
        }
        catch (Exception exception)
        {
            LuaCsLogger.LogError($"[JEB] Could not index deconstruction for {prefab.Identifier}: {exception.Message}");
        }
        return outputs;
    }

    private CatalogRecord? FindItemFromCurrentBuild(string identifier)
    {
        if (snapshot != CatalogSnapshot.Empty)
        {
            CatalogRecord? existing = Find(PrefabKind.Item, identifier);
            if (existing is not null) { return existing; }
        }
        try
        {
            ItemPrefab? prefab = ItemPrefab.Prefabs.FirstOrDefault(
                item => TextTools.NormalizeIdentifier(item.Identifier) == identifier);
            if (prefab is null) { return null; }
            return CreateRecord(PrefabKind.Item, prefab);
        }
        catch { return null; }
    }

    private void BuildAfflictionIndexes(IReadOnlyList<CatalogRecord> records)
    {
        treatmentsByAffliction.Clear();
        causesByAffliction.Clear();

        Dictionary<string, CatalogRecord> items = records
            .Where(record => record.Kind == PrefabKind.Item)
            .ToDictionary(record => record.Identifier, StringComparer.OrdinalIgnoreCase);
        Dictionary<string, CatalogRecord> afflictions = records
            .Where(record => record.Kind == PrefabKind.Affliction)
            .ToDictionary(record => record.Identifier, StringComparer.OrdinalIgnoreCase);

        var mutableTreatments = afflictions.Keys.ToDictionary(
            key => key,
            _ => new Dictionary<string, TreatmentLink>(StringComparer.OrdinalIgnoreCase),
            StringComparer.OrdinalIgnoreCase);
        var mutableCauses = afflictions.Keys.ToDictionary(
            key => key,
            _ => new Dictionary<string, AfflictionCauseLink>(StringComparer.OrdinalIgnoreCase),
            StringComparer.OrdinalIgnoreCase);

        foreach (CatalogRecord afflictionRecord in afflictions.Values)
        {
            if (afflictionRecord.Prefab is not AfflictionPrefab affliction) { continue; }
            try
            {
                foreach ((Identifier itemIdentifier, float suitability) in affliction.TreatmentSuitabilities)
                {
                    string itemId = TextTools.NormalizeIdentifier(itemIdentifier);
                    if (!items.TryGetValue(itemId, out CatalogRecord? itemRecord)) { continue; }
                    mutableTreatments[afflictionRecord.Identifier][itemId] = new TreatmentLink
                    {
                        Item = itemRecord,
                        Suitability = suitability,
                        Contraindicated = suitability < 0,
                        Note = suitability < 0 ? L.Get("section.contraindications") : string.Empty
                    };
                }
            }
            catch { }
        }

        foreach (CatalogRecord itemRecord in items.Values)
        {
            ContentXElement? config = ReflectionTools.FindConfigElement(itemRecord.Prefab);
            if (config is null) { continue; }
            try
            {
                foreach (XElement element in config.Element.DescendantsAndSelf())
                {
                    string elementName = element.Name.LocalName.ToLowerInvariant();
                    string identifier = TextTools.NormalizeIdentifier(
                        element.Attribute("identifier")?.Value ?? string.Empty);
                    string afflictionType = TextTools.NormalizeIdentifier(
                        element.Attribute("type")?.Value ?? string.Empty);
                    float strength = AttributeFloat(element, "amount", AttributeFloat(element, "strength", 0));
                    float suitability = AttributeFloat(element, "suitability", 0);

                    foreach (CatalogRecord afflictionRecord in MatchingAfflictions(
                                 identifier, afflictionType, afflictions.Values))
                    {
                        Dictionary<string, TreatmentLink> treatmentMap =
                            mutableTreatments[afflictionRecord.Identifier];
                        Dictionary<string, AfflictionCauseLink> causeMap =
                            mutableCauses[afflictionRecord.Identifier];

                        if (elementName is "suitabletreatment" or "reduceaffliction" ||
                            (elementName == "affliction" && strength < 0))
                        {
                            treatmentMap.TryGetValue(itemRecord.Identifier, out TreatmentLink? previous);
                            float reduction = elementName == "affliction" ? Math.Abs(strength) : Math.Abs(strength);
                            treatmentMap[itemRecord.Identifier] = new TreatmentLink
                            {
                                Item = itemRecord,
                                Strength = Math.Max(previous?.Strength ?? 0, reduction),
                                Suitability = Math.Abs(suitability) > Math.Abs(previous?.Suitability ?? 0)
                                    ? suitability
                                    : previous?.Suitability ?? suitability,
                                Contraindicated = suitability < 0 || previous?.Contraindicated == true,
                                Note = suitability < 0 ? L.Get("section.contraindications") : previous?.Note ?? string.Empty
                            };
                        }
                        else if (elementName == "affliction" && strength > 0)
                        {
                            causeMap.TryGetValue(itemRecord.Identifier, out AfflictionCauseLink? previous);
                            causeMap[itemRecord.Identifier] = new AfflictionCauseLink
                            {
                                Source = itemRecord,
                                Strength = Math.Max(previous?.Strength ?? 0, strength)
                            };
                        }
                    }
                }
            }
            catch { }
        }

        foreach (string identifier in afflictions.Keys)
        {
            treatmentsByAffliction[identifier] = mutableTreatments[identifier].Values
                .OrderBy(link => link.Contraindicated)
                .ThenByDescending(link => link.Suitability)
                .ThenByDescending(link => link.Strength)
                .ThenBy(link => link.Item.Name, StringComparer.CurrentCultureIgnoreCase)
                .ToArray();
            causesByAffliction[identifier] = mutableCauses[identifier].Values
                .OrderByDescending(link => link.Strength)
                .ThenBy(link => link.Source.Name, StringComparer.CurrentCultureIgnoreCase)
                .ToArray();
        }
    }

    private static IEnumerable<CatalogRecord> MatchingAfflictions(
        string identifier,
        string type,
        IEnumerable<CatalogRecord> afflictions)
    {
        if (identifier.Length == 0 && type.Length == 0) { yield break; }
        foreach (CatalogRecord record in afflictions)
        {
            if (identifier.Length > 0 && record.Identifier.Equals(identifier, StringComparison.OrdinalIgnoreCase))
            {
                yield return record;
                continue;
            }
            if (type.Length == 0) { continue; }
            string recordType = TextTools.NormalizeIdentifier(
                ReflectionTools.GetMember(record.Prefab, "AfflictionType", "Type"));
            if (recordType.Equals(type, StringComparison.OrdinalIgnoreCase)) { yield return record; }
        }
    }

    private void BuildSpecializedIndexes(CatalogSnapshot cached)
    {
        BuildRecipeIndexes(cached.All,
            out Dictionary<string, IReadOnlyList<RecipeUse>> _,
            out Dictionary<string, IReadOnlyList<DeconstructionSource>> __);
        BuildAfflictionIndexes(cached.All);
    }

    private static void Add<T>(
        IDictionary<string, List<T>> index,
        string key,
        T value,
        Func<T, bool> duplicate)
    {
        if (string.IsNullOrWhiteSpace(key)) { return; }
        if (!index.TryGetValue(key, out List<T>? values))
        {
            values = new List<T>();
            index[key] = values;
        }
        if (!values.Any(duplicate)) { values.Add(value); }
    }

    private static float AttributeFloat(XElement element, string name, float fallback)
        => float.TryParse(
            element.Attribute(name)?.Value,
            System.Globalization.NumberStyles.Float,
            System.Globalization.CultureInfo.InvariantCulture,
            out float value)
            ? value
            : fallback;

    private static string BuildContentSignature()
    {
        try
        {
            object? merged = ReflectionTools.GetStaticMember(
                typeof(ContentPackageManager.EnabledPackages), "MergedHash", "Hash");
            string hash = TextTools.Stringify(merged);
            string packages = string.Join("|", ContentPackageManager.EnabledPackages.All
                .Select(package => TextTools.Stringify(ReflectionTools.GetMember(package, "Name")))
                .OrderBy(name => name, StringComparer.OrdinalIgnoreCase));
            return hash + ":" + packages + ":" + L.CurrentLanguage;
        }
        catch
        {
            return DateTime.UtcNow.Date.Ticks.ToString();
        }
    }
}
