#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Xml.Linq;
using Barotrauma;
using Microsoft.Xna.Framework;

namespace JustEnoughBaro;

internal sealed class MetadataExtractor
{
    private const int MaximumValuesPerSection = 64;
    private const int MaximumCollectionEntries = 16;
    private const int MaximumTotalValues = 360;
    private const int CacheCapacity = 64;

    private static readonly string[] SectionOrder =
    {
        "identity", "gameplay", "weapon", "medical", "electrical", "creature",
        "world", "talent", "mission", "contained", "visual", "other"
    };

    private static readonly HashSet<string> ExcludedMembers = new(StringComparer.OrdinalIgnoreCase)
    {
        "ConfigElement", "OriginalElement", "SourceElement", "SerializableProperties",
        "Prefabs", "TalentPrefabs", "ContentFile", "File", "Parent", "Children",
        "Sprite", "InventoryIcon", "Icon", "IconSmall", "MinimapIcon", "SchematicSprite",
        "FabricationRecipes", "DeconstructItems", "TreatmentSuitabilities", "Effects",
        "PeriodicEffects", "GetType", "UintIdentifier", "EqualityCheckVal", "Element"
    };

    private sealed class CacheEntry
    {
        public required IReadOnlyList<MetadataSection> Value { get; init; }
        public required LinkedListNode<string> Node { get; init; }
    }

    private readonly object cacheGate = new();
    private readonly Dictionary<string, CacheEntry> cache = new(StringComparer.OrdinalIgnoreCase);
    private readonly LinkedList<string> recency = new();
    private readonly int maximumDepth;

    public MetadataExtractor(int maximumDepth)
    {
        this.maximumDepth = Math.Clamp(maximumDepth, 1, 4);
    }

    public IReadOnlyList<MetadataSection> Extract(CatalogRecord record, string catalogSignature)
    {
        string key = catalogSignature + ":" + record.Key;
        lock (cacheGate)
        {
            if (cache.TryGetValue(key, out CacheEntry? cached))
            {
                recency.Remove(cached.Node);
                recency.AddFirst(cached.Node);
                return cached.Value;
            }
        }

        IReadOnlyList<MetadataSection> extracted = ExtractUncached(record);
        lock (cacheGate)
        {
            if (cache.TryGetValue(key, out CacheEntry? raced))
            {
                recency.Remove(raced.Node);
                recency.AddFirst(raced.Node);
                return raced.Value;
            }
            LinkedListNode<string> node = recency.AddFirst(key);
            cache[key] = new CacheEntry { Value = extracted, Node = node };
            while (cache.Count > CacheCapacity && recency.Last is not null)
            {
                string evicted = recency.Last.Value;
                recency.RemoveLast();
                cache.Remove(evicted);
            }
        }
        return extracted;
    }

    public void Clear()
    {
        lock (cacheGate)
        {
            cache.Clear();
            recency.Clear();
        }
    }

    private IReadOnlyList<MetadataSection> ExtractUncached(CatalogRecord record)
    {
        var grouped = SectionOrder.ToDictionary(
            section => section,
            _ => new List<MetadataValue>(),
            StringComparer.OrdinalIgnoreCase);

        Add(grouped, "identity", L.Get("detail.name"), record.Name);
        Add(grouped, "identity", L.Get("detail.identifier"), record.Identifier);
        Add(grouped, "identity", L.Get("detail.prefab_type"), record.Prefab.GetType().FullName ?? record.Prefab.GetType().Name);
        if (!string.IsNullOrWhiteSpace(record.Tags)) { Add(grouped, "identity", L.Get("detail.tags"), record.Tags); }
        if (!string.IsNullOrWhiteSpace(record.Source)) { Add(grouped, "identity", L.Get("detail.source"), record.Source); }
        if (!string.IsNullOrWhiteSpace(record.Description))
        {
            Add(grouped, "identity", L.Get("detail.description"), record.Description);
        }

        var visited = new HashSet<object>(ReferenceComparer.Instance) { record.Prefab };
        foreach (MemberInfo member in ReflectionTools.ReadableMembers(record.Prefab.GetType()))
        {
            if (ExcludedMembers.Contains(member.Name)) { continue; }
            object? value = ReflectionTools.Read(record.Prefab, member);
            AppendValue(grouped, member.Name, value, 0, visited, SectionFor(member.Name));
            if (Total(grouped) >= MaximumTotalValues) { break; }
        }

        AppendSemanticXml(record, grouped);

        return SectionOrder
            .Where(section => grouped[section].Count > 0)
            .Select(section => new MetadataSection(section, grouped[section]))
            .ToArray();
    }

    private void AppendValue(
        IDictionary<string, List<MetadataValue>> grouped,
        string name,
        object? value,
        int depth,
        ISet<object> visited,
        string section)
    {
        if (value is null || ExcludedMembers.Contains(name)) { return; }
        if (grouped[section].Count >= MaximumValuesPerSection) { return; }

        Type type = value.GetType();
        if (IsSimple(type, value))
        {
            string text = FormatSimple(value);
            if (!ShouldDisplay(text)) { return; }
            Add(grouped, section, TextTools.Humanize(name), text, depth);
            return;
        }

        if (value is Sprite)
        {
            Add(grouped, "visual", TextTools.Humanize(name), L.Get("detail.available"), depth);
            return;
        }
        if (value is ContentXElement or XElement) { return; }
        if (value is Delegate) { return; }

        if (value is IEnumerable enumerable && value is not string)
        {
            AppendEnumerable(grouped, name, enumerable, depth, visited, section);
            return;
        }

        if (depth >= maximumDepth || !CanExpand(type))
        {
            string rendered = TextTools.Stringify(value);
            if (ShouldDisplay(rendered) && !LooksLikeTypeName(rendered, type))
            {
                Add(grouped, section, TextTools.Humanize(name), rendered, depth);
            }
            return;
        }

        if (!visited.Add(value)) { return; }
        string nestedSection = IsContainedName(name) ? "contained" : section;
        AddHeader(grouped, nestedSection, TextTools.Humanize(name), depth);
        int before = grouped[nestedSection].Count;
        foreach (MemberInfo member in ReflectionTools.ReadableMembers(type).Take(32))
        {
            if (ExcludedMembers.Contains(member.Name)) { continue; }
            AppendValue(
                grouped,
                member.Name,
                ReflectionTools.Read(value, member),
                depth + 1,
                visited,
                SectionFor(name + " " + member.Name, nestedSection));
            if (grouped[nestedSection].Count - before >= MaximumCollectionEntries) { break; }
        }
        visited.Remove(value);
    }

    private void AppendEnumerable(
        IDictionary<string, List<MetadataValue>> grouped,
        string name,
        IEnumerable enumerable,
        int depth,
        ISet<object> visited,
        string section)
    {
        var entries = new List<object?>();
        try
        {
            foreach (object? entry in enumerable)
            {
                entries.Add(entry);
                if (entries.Count > MaximumCollectionEntries) { break; }
            }
        }
        catch { return; }
        if (entries.Count == 0) { return; }

        string targetSection = IsContainedName(name) ? "contained" : section;
        bool simple = entries.Where(entry => entry is not null)
            .All(entry => IsSimple(entry!.GetType(), entry));
        if (simple)
        {
            string joined = string.Join(", ", entries
                .Take(MaximumCollectionEntries)
                .Select(entry => FormatSimple(entry!))
                .Where(ShouldDisplay));
            if (entries.Count > MaximumCollectionEntries) { joined += ", …"; }
            if (ShouldDisplay(joined))
            {
                Add(grouped, targetSection, TextTools.Humanize(name), joined, depth);
            }
            return;
        }

        AddHeader(grouped, targetSection, $"{TextTools.Humanize(name)} ({entries.Count}{(entries.Count > MaximumCollectionEntries ? "+" : string.Empty)})", depth);
        int index = 0;
        foreach (object? entry in entries.Take(MaximumCollectionEntries))
        {
            if (entry is null) { continue; }
            index++;
            if (entry is DictionaryEntry dictionaryEntry)
            {
                AppendValue(grouped, TextTools.Stringify(dictionaryEntry.Key), dictionaryEntry.Value,
                    depth + 1, visited, targetSection);
                continue;
            }

            Type entryType = entry.GetType();
            PropertyInfo? keyProperty = entryType.GetProperty("Key");
            PropertyInfo? valueProperty = entryType.GetProperty("Value");
            if (keyProperty is not null && valueProperty is not null)
            {
                string key = TextTools.Stringify(SafeProperty(entry, keyProperty));
                AppendValue(grouped, key, SafeProperty(entry, valueProperty), depth + 1, visited, targetSection);
            }
            else
            {
                string label = TextTools.Stringify(ReflectionTools.GetMember(entry, "Name", "Identifier"));
                if (string.IsNullOrWhiteSpace(label)) { label = $"{entryType.Name} {index}"; }
                AppendValue(grouped, label, entry, depth + 1, visited, targetSection);
            }
        }
    }

    private static object? SafeProperty(object target, PropertyInfo property)
    {
        try { return property.GetValue(target); }
        catch { return null; }
    }

    private static void AppendSemanticXml(
        CatalogRecord record,
        IDictionary<string, List<MetadataValue>> grouped)
    {
        ContentXElement? config = ReflectionTools.FindConfigElement(record.Prefab);
        if (config is null) { return; }

        var componentCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        try
        {
            foreach (XElement element in config.Element.Descendants())
            {
                string elementName = element.Name.LocalName;
                string lower = elementName.ToLowerInvariant();
                if (lower is "sprite" or "inventoryicon" or "decorativesprite" or "sound" or
                    "fabricate" or "deconstruct" or "connection" or "input" or "output")
                {
                    continue;
                }

                string section = SectionFor(elementName);
                XAttribute[] attributes = element.Attributes()
                    .Where(attribute => IsSemanticAttribute(attribute.Name.LocalName))
                    .Take(24)
                    .ToArray();
                if (attributes.Length == 0) { continue; }
                if (grouped[section].Count >= MaximumValuesPerSection) { continue; }

                componentCounts.TryGetValue(elementName, out int ordinal);
                componentCounts[elementName] = ++ordinal;
                string header = ordinal == 1 ? TextTools.Humanize(elementName) : $"{TextTools.Humanize(elementName)} {ordinal}";
                AddHeader(grouped, section, header, 0);
                foreach (XAttribute attribute in attributes)
                {
                    string value = attribute.Value.Trim();
                    if (!ShouldDisplay(value)) { continue; }
                    Add(grouped, section, TextTools.Humanize(attribute.Name.LocalName), value, 1);
                }
            }
        }
        catch
        {
            // A malformed third-party prefab should not prevent the page from opening.
        }
    }

    private static bool IsSemanticAttribute(string name)
    {
        string lower = name.ToLowerInvariant();
        return lower is not (
            "texture" or "sourcerect" or "sheetindex" or "sheetelementsize" or "origin" or
            "depth" or "rotation" or "flipx" or "flipy" or "inherit" or "inheritfrom" or
            "file" or "path" or "sprite") &&
            !lower.StartsWith("color", StringComparison.Ordinal) &&
            !lower.EndsWith("color", StringComparison.Ordinal);
    }

    private static bool IsSimple(Type type, object value)
        => type.IsPrimitive || type.IsEnum || value is
            string or decimal or Identifier or LocalizedString or Guid or DateTime or TimeSpan or
            Vector2 or Vector3 or Vector4 or Point or Rectangle or Color;

    private static string FormatSimple(object value)
    {
        return value switch
        {
            bool boolean => boolean ? L.Get("detail.yes") : L.Get("detail.no"),
            float single => TextTools.Number(single),
            double number => TextTools.Number(number),
            decimal decimalNumber => TextTools.Number((double)decimalNumber),
            _ => TextTools.CleanDisplayText(value)
        };
    }

    private static bool CanExpand(Type type)
    {
        string? space = type.Namespace;
        return space is not null &&
               (space.StartsWith("Barotrauma", StringComparison.Ordinal) ||
                type.Name.Contains("Info", StringComparison.OrdinalIgnoreCase) ||
                type.Name.Contains("Requirement", StringComparison.OrdinalIgnoreCase) ||
                type.Name.Contains("Effect", StringComparison.OrdinalIgnoreCase));
    }

    private static bool ShouldDisplay(string? value)
        => !string.IsNullOrWhiteSpace(value) &&
           !value.Equals("None", StringComparison.OrdinalIgnoreCase) &&
           !value.Equals("System.Collections.Immutable.ImmutableArray`1", StringComparison.Ordinal);

    private static bool LooksLikeTypeName(string value, Type type)
        => value.Equals(type.FullName, StringComparison.Ordinal) ||
           value.Equals(type.Name, StringComparison.Ordinal);

    private static bool IsContainedName(string value)
    {
        string lower = value.ToLowerInvariant();
        return lower.Contains("contained") || lower.Contains("container") ||
               lower.Contains("requireditem") || lower.Contains("linkeditem") ||
               lower.Contains("inventory");
    }

    private static string SectionFor(string name, string fallback = "other")
    {
        string value = name.ToLowerInvariant();
        if (ContainsAny(value, "identifier", "name", "description", "tag", "alias", "category", "translation", "variant")) return "identity";
        if (ContainsAny(value, "weapon", "attack", "damage", "projectile", "ammo", "reload", "spread", "recoil", "penetr", "range", "stun", "impact", "fire")) return "weapon";
        if (ContainsAny(value, "medical", "affliction", "treatment", "heal", "vitality", "poison", "buff", "bleed", "burn", "resistance", "health")) return "medical";
        if (ContainsAny(value, "connection", "signal", "power", "voltage", "electrical", "wire", "reactor", "pump", "engine", "mechanical", "charge")) return "electrical";
        if (ContainsAny(value, "creature", "species", "ragdoll", "limb", "joint", "ai", "sight", "hearing", "swim", "walk", "blood", "gib")) return "creature";
        if (ContainsAny(value, "biome", "level", "location", "commonness", "spawn", "difficulty", "abyss", "cave", "map", "generation", "depth")) return "world";
        if (ContainsAny(value, "talent", "skill", "job", "profession", "recipeunlock", "experience")) return "talent";
        if (ContainsAny(value, "mission", "reward", "campaign", "objective", "faction")) return "mission";
        if (ContainsAny(value, "contained", "container", "inventory", "linked", "requireditem")) return "contained";
        if (ContainsAny(value, "sprite", "icon", "color", "size", "scale", "offset", "rotation", "visual")) return "visual";
        if (ContainsAny(value, "price", "cost", "stack", "condition", "interact", "quality", "fabricat", "deconstruct", "duration", "time")) return "gameplay";
        return fallback;
    }

    private static bool ContainsAny(string value, params string[] fragments)
        => fragments.Any(value.Contains);

    private static void Add(
        IDictionary<string, List<MetadataValue>> grouped,
        string section,
        string name,
        string value,
        int depth = 0)
    {
        if (!grouped.TryGetValue(section, out List<MetadataValue>? values)) { return; }
        if (values.Count >= MaximumValuesPerSection) { return; }
        if (values.Any(existing => !existing.IsHeader &&
                                   existing.Name.Equals(name, StringComparison.OrdinalIgnoreCase) &&
                                   existing.Value.Equals(value, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }
        values.Add(new MetadataValue { Name = name, Value = value, Depth = depth });
    }

    private static void AddHeader(
        IDictionary<string, List<MetadataValue>> grouped,
        string section,
        string name,
        int depth)
    {
        if (!grouped.TryGetValue(section, out List<MetadataValue>? values)) { return; }
        if (values.Count >= MaximumValuesPerSection) { return; }
        values.Add(new MetadataValue { Name = name, Depth = depth, IsHeader = true });
    }

    private static int Total(IDictionary<string, List<MetadataValue>> grouped)
        => grouped.Values.Sum(values => values.Count);

    private sealed class ReferenceComparer : IEqualityComparer<object>
    {
        public static readonly ReferenceComparer Instance = new();
        public new bool Equals(object? x, object? y) => ReferenceEquals(x, y);
        public int GetHashCode(object obj) => System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(obj);
    }
}
