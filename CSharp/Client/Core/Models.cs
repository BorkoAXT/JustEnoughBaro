#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using Barotrauma;

namespace JustEnoughBaro;

/// <summary>
/// The browser intentionally models prefab families instead of hard-coding one screen per
/// Barotrauma type. New sources can be registered in <see cref="PrefabCatalog"/> without
/// changing navigation, search, favorites, or metadata rendering.
/// </summary>
internal enum PrefabKind
{
    All,
    Favorite,
    Item,
    Affliction,
    Creature,
    Biome,
    Talent,
    Profession,
    Mission,
    Submarine,
    Structure,
    Upgrade,
    ItemAssembly,
    LevelObject,
    Event
}

internal static class PrefabKindExtensions
{
    public static string LocalizationKey(this PrefabKind kind) => $"kind.{kind.ToString().ToLowerInvariant()}";

    public static string StableName(this PrefabKind kind) => kind.ToString().ToLowerInvariant();

    public static bool IsPrimary(this PrefabKind kind) => kind is
        PrefabKind.All or PrefabKind.Item or PrefabKind.Affliction or PrefabKind.Creature or
        PrefabKind.Biome or PrefabKind.Talent;
}

internal sealed class CatalogRecord
{
    public CatalogRecord(
        PrefabKind kind,
        string identifier,
        string name,
        string description,
        string tags,
        string source,
        object prefab,
        Sprite? icon)
    {
        Kind = kind;
        Identifier = identifier;
        Name = name;
        Description = description;
        Tags = tags;
        Source = source;
        Prefab = prefab;
        Icon = icon;
        Key = $"{kind.StableName()}:{identifier}";
        SearchText = TextTools.NormalizeSearch($"{name} {identifier} {tags} {source} {kind}");
    }

    public PrefabKind Kind { get; }
    public string Identifier { get; }
    public string Name { get; }
    public string Description { get; }
    public string Tags { get; }
    public string Source { get; }
    public object Prefab { get; }
    public Sprite? Icon { get; }
    public string Key { get; }
    public string SearchText { get; }

    public override string ToString() => $"{Kind}: {Name} ({Identifier})";
}

internal sealed class CatalogSnapshot
{
    public static readonly CatalogSnapshot Empty = new(
        Array.Empty<CatalogRecord>(),
        new Dictionary<string, CatalogRecord>(StringComparer.OrdinalIgnoreCase),
        new Dictionary<PrefabKind, IReadOnlyList<CatalogRecord>>(),
        new Dictionary<string, IReadOnlyList<RecipeUse>>(StringComparer.OrdinalIgnoreCase),
        new Dictionary<string, IReadOnlyList<DeconstructionSource>>(StringComparer.OrdinalIgnoreCase),
        string.Empty);

    public CatalogSnapshot(
        IReadOnlyList<CatalogRecord> all,
        IReadOnlyDictionary<string, CatalogRecord> byKey,
        IReadOnlyDictionary<PrefabKind, IReadOnlyList<CatalogRecord>> byKind,
        IReadOnlyDictionary<string, IReadOnlyList<RecipeUse>> usedIn,
        IReadOnlyDictionary<string, IReadOnlyList<DeconstructionSource>> obtainedFrom,
        string signature)
    {
        All = all;
        ByKey = byKey;
        ByKind = byKind;
        UsedIn = usedIn;
        ObtainedFrom = obtainedFrom;
        Signature = signature;
    }

    public IReadOnlyList<CatalogRecord> All { get; }
    public IReadOnlyDictionary<string, CatalogRecord> ByKey { get; }
    public IReadOnlyDictionary<PrefabKind, IReadOnlyList<CatalogRecord>> ByKind { get; }
    public IReadOnlyDictionary<string, IReadOnlyList<RecipeUse>> UsedIn { get; }
    public IReadOnlyDictionary<string, IReadOnlyList<DeconstructionSource>> ObtainedFrom { get; }
    public string Signature { get; }

    public IReadOnlyList<CatalogRecord> ForKind(PrefabKind kind)
        => kind == PrefabKind.All
            ? All
            : ByKind.TryGetValue(kind, out IReadOnlyList<CatalogRecord>? records)
                ? records
                : Array.Empty<CatalogRecord>();
}

internal sealed class IngredientOption
{
    public IngredientOption(string identifier, string name)
    {
        Identifier = identifier;
        Name = name;
    }

    public string Identifier { get; }
    public string Name { get; }
}

internal sealed class RecipeIngredient
{
    public RecipeIngredient(
        IReadOnlyList<IngredientOption> options,
        int amount,
        float minimumCondition,
        float maximumCondition,
        bool consumesCondition,
        string tag)
    {
        Options = options;
        Amount = amount;
        MinimumCondition = minimumCondition;
        MaximumCondition = maximumCondition;
        ConsumesCondition = consumesCondition;
        Tag = tag;
    }

    public IReadOnlyList<IngredientOption> Options { get; }
    public int Amount { get; }
    public float MinimumCondition { get; }
    public float MaximumCondition { get; }
    public bool ConsumesCondition { get; }
    public string Tag { get; }

    public string TrackerKey => Options.Count == 1
        ? Options[0].Identifier
        : string.IsNullOrWhiteSpace(Tag)
            ? string.Join("|", Options.Select(option => option.Identifier))
            : $"tag:{Tag}";
}

internal sealed class RecipeInfo
{
    public RecipeInfo(
        string id,
        string outputIdentifier,
        string outputName,
        int outputAmount,
        float time,
        IReadOnlyList<string> fabricators,
        IReadOnlyList<RecipeIngredient> ingredients,
        IReadOnlyList<string> skills,
        bool requiresUnlock,
        int requiredMoney)
    {
        Id = id;
        OutputIdentifier = outputIdentifier;
        OutputName = outputName;
        OutputAmount = outputAmount;
        Time = time;
        Fabricators = fabricators;
        Ingredients = ingredients;
        Skills = skills;
        RequiresUnlock = requiresUnlock;
        RequiredMoney = requiredMoney;
    }

    public string Id { get; }
    public string OutputIdentifier { get; }
    public string OutputName { get; }
    public int OutputAmount { get; }
    public float Time { get; }
    public IReadOnlyList<string> Fabricators { get; }
    public IReadOnlyList<RecipeIngredient> Ingredients { get; }
    public IReadOnlyList<string> Skills { get; }
    public bool RequiresUnlock { get; }
    public int RequiredMoney { get; }
}

internal sealed class RecipeUse
{
    public RecipeUse(CatalogRecord output, RecipeInfo recipe)
    {
        Output = output;
        Recipe = recipe;
    }

    public CatalogRecord Output { get; }
    public RecipeInfo Recipe { get; }
}

internal sealed class DeconstructionOutput
{
    public string Identifier { get; init; } = string.Empty;
    public string Name { get; init; } = string.Empty;
    public int Amount { get; init; }
    public float Probability { get; init; } = 1.0f;
    public float MinimumCondition { get; init; }
    public float MaximumCondition { get; init; } = 1.0f;
    public float OutputConditionMinimum { get; init; } = 1.0f;
    public float OutputConditionMaximum { get; init; } = 1.0f;
    public IReadOnlyList<string> RequiredDeconstructors { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> RequiredOtherItems { get; init; } = Array.Empty<string>();
}

internal sealed class DeconstructionSource
{
    public DeconstructionSource(CatalogRecord source, DeconstructionOutput output)
    {
        Source = source;
        Output = output;
    }

    public CatalogRecord Source { get; }
    public DeconstructionOutput Output { get; }
}

internal sealed class TreatmentLink
{
    public CatalogRecord Item { get; init; } = null!;
    public float Suitability { get; init; }
    public float Strength { get; init; }
    public bool Contraindicated { get; init; }
    public string Note { get; init; } = string.Empty;
}

internal sealed class AfflictionCauseLink
{
    public CatalogRecord Source { get; init; } = null!;
    public float Strength { get; init; }
}

internal sealed class WiringPin
{
    public string Name { get; init; } = string.Empty;
    public string Direction { get; init; } = string.Empty;
    public string Description { get; init; } = string.Empty;
}

internal sealed class WiringPanelInfo
{
    public string Key { get; init; } = string.Empty;
    public string Title { get; init; } = string.Empty;
    public string Summary { get; init; } = string.Empty;
    public IReadOnlyList<WiringPin> Pins { get; init; } = Array.Empty<WiringPin>();
}

internal sealed class MetadataValue
{
    public string Name { get; init; } = string.Empty;
    public string Value { get; init; } = string.Empty;
    public int Depth { get; init; }
    public bool IsHeader { get; init; }
}

internal sealed class MetadataSection
{
    public MetadataSection(string key, IEnumerable<MetadataValue> values)
    {
        Key = key;
        Values = new ReadOnlyCollection<MetadataValue>(values.ToList());
    }

    public string Key { get; }
    public IReadOnlyList<MetadataValue> Values { get; }
}

internal sealed class NavigationEntry
{
    public string RecordKey { get; set; } = string.Empty;
    public PrefabKind Kind { get; set; }
    public string DetailTab { get; set; } = "overview";
    public string Search { get; set; } = string.Empty;
}

internal sealed class TrackedRecipe
{
    public string RecipeId { get; set; } = string.Empty;
    public string OutputIdentifier { get; set; } = string.Empty;
    public string OutputName { get; set; } = string.Empty;
    public List<TrackedIngredient> Ingredients { get; set; } = new();
}

internal sealed class TrackedIngredient
{
    public string Key { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public int Required { get; set; }
    public List<string> AcceptedIdentifiers { get; set; } = new();
}

internal sealed class UserState
{
    public int Version { get; set; } = 1;
    public HashSet<string> Favorites { get; set; } = new(StringComparer.OrdinalIgnoreCase);
    public List<NavigationEntry> History { get; set; } = new();
    public int HistoryIndex { get; set; } = -1;
    public TrackedRecipe? TrackedRecipe { get; set; }
    public string ActiveProfile { get; set; } = "Balanced";
    public WindowProfile CustomProfile { get; set; } = WindowProfile.CreateCustom();
}

internal enum MetadataPlacement
{
    Right,
    Bottom,
    Hidden
}

internal sealed class WindowProfile
{
    public string Name { get; set; } = "Balanced";
    public float Width { get; set; } = 0.90f;
    public float Height { get; set; } = 0.88f;
    /// <summary>Normalized top-left position inside the UI canvas.</summary>
    public float PositionX { get; set; } = 0.5f;
    public float PositionY { get; set; } = 0.5f;
    public float IndexRatio { get; set; } = 0.23f;
    public float MetadataRatio { get; set; } = 0.25f;
    public float UiScale { get; set; } = 1.0f;
    public MetadataPlacement MetadataPlacement { get; set; } = MetadataPlacement.Right;
    public bool ShowDescriptionsInIndex { get; set; }

    public WindowProfile Copy(string? name = null) => new()
    {
        Name = name ?? Name,
        Width = Width,
        Height = Height,
        PositionX = PositionX,
        PositionY = PositionY,
        IndexRatio = IndexRatio,
        MetadataRatio = MetadataRatio,
        UiScale = UiScale,
        MetadataPlacement = MetadataPlacement,
        ShowDescriptionsInIndex = ShowDescriptionsInIndex
    };

    public static WindowProfile CreateCustom() => new()
    {
        Name = "Custom",
        Width = 0.90f,
        Height = 0.88f,
        PositionX = 0.5f,
        PositionY = 0.5f,
        IndexRatio = 0.23f,
        MetadataRatio = 0.25f,
        MetadataPlacement = MetadataPlacement.Right
    };
}

internal sealed class JebConfig
{
    public int Version { get; set; } = 1;
    public string OpenKey { get; set; } = "J";
    public int PageSize { get; set; } = 100;
    public bool ShowContextHint { get; set; } = true;
    public bool ShowHudTracker { get; set; } = true;
    public float TrackerX { get; set; } = 0.77f;
    public float TrackerY { get; set; } = 0.16f;
    public int MetadataDepth { get; set; } = 2;

    public static JebConfig Defaults() => new();
}

internal static class BuiltInProfiles
{
    private static readonly IReadOnlyList<WindowProfile> profiles = new[]
    {
        new WindowProfile
        {
            Name = "Balanced",
            Width = 0.90f,
            Height = 0.88f,
            IndexRatio = 0.23f,
            MetadataRatio = 0.25f,
            MetadataPlacement = MetadataPlacement.Right
        },
        new WindowProfile
        {
            Name = "Wide",
            Width = 0.97f,
            Height = 0.92f,
            IndexRatio = 0.20f,
            MetadataRatio = 0.28f,
            MetadataPlacement = MetadataPlacement.Right,
            ShowDescriptionsInIndex = true
        },
        new WindowProfile
        {
            Name = "Compact",
            Width = 0.76f,
            Height = 0.78f,
            IndexRatio = 0.30f,
            MetadataRatio = 0.30f,
            MetadataPlacement = MetadataPlacement.Bottom,
            UiScale = 0.92f
        },
        new WindowProfile
        {
            Name = "Focus",
            Width = 0.86f,
            Height = 0.88f,
            IndexRatio = 0.24f,
            MetadataRatio = 0.0f,
            MetadataPlacement = MetadataPlacement.Hidden
        }
    };

    public static IReadOnlyList<WindowProfile> All => profiles;

    public static WindowProfile Resolve(string? name, WindowProfile custom)
        => string.Equals(name, "Custom", StringComparison.OrdinalIgnoreCase)
            ? custom.Copy("Custom")
            : profiles.FirstOrDefault(profile => string.Equals(profile.Name, name, StringComparison.OrdinalIgnoreCase))?.Copy()
                ?? profiles[0].Copy();
}
