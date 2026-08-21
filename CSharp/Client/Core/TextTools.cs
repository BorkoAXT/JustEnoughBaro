#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using Barotrauma;

namespace JustEnoughBaro;

internal static class TextTools
{
    private static readonly Regex RichColorTag = new(
        @"\[/?color(?::[^\]]+)?\]|</?color[^>]*>",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex WordBoundary = new(
        @"(?<=[a-z0-9])(?=[A-Z])|[_\-.]+",
        RegexOptions.Compiled);
    private static readonly Regex SearchNoise = new(
        @"[^\p{L}\p{N}]+",
        RegexOptions.Compiled);

    public static string NormalizeIdentifier(object? value)
    {
        string raw = Stringify(value).ToLowerInvariant();
        var builder = new StringBuilder(raw.Length);
        foreach (char character in raw)
        {
            if (char.IsLetterOrDigit(character) || character is '_' or '-')
            {
                builder.Append(character);
            }
        }
        return builder.ToString();
    }

    public static string WikiKey(object? value)
    {
        string raw = Stringify(value).ToLowerInvariant();
        var builder = new StringBuilder(raw.Length);
        foreach (char character in raw)
        {
            if (character is >= 'a' and <= 'z' or >= '0' and <= '9')
            {
                builder.Append(character);
            }
        }
        return builder.ToString();
    }

    public static string NormalizeSearch(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) { return string.Empty; }
        string decomposed = value.Normalize(NormalizationForm.FormD).ToLowerInvariant();
        var withoutMarks = new StringBuilder(decomposed.Length);
        foreach (char character in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark)
            {
                withoutMarks.Append(character);
            }
        }
        return SearchNoise.Replace(withoutMarks.ToString(), " ").Trim();
    }

    public static bool SearchMatches(string indexedText, string query)
    {
        string normalized = NormalizeSearch(query);
        if (normalized.Length == 0) { return true; }
        foreach (string token in normalized.Split(' ', StringSplitOptions.RemoveEmptyEntries))
        {
            if (!indexedText.Contains(token, StringComparison.Ordinal)) { return false; }
        }
        return true;
    }

    public static string CleanDisplayText(object? value)
    {
        string rendered = Stringify(value);
        if (rendered.StartsWith("userdata:", StringComparison.OrdinalIgnoreCase)) { return string.Empty; }
        return RichColorTag.Replace(rendered, string.Empty).Trim();
    }

    public static string Humanize(object? value)
    {
        string input = Stringify(value).Trim();
        if (input.Length == 0) { return string.Empty; }
        string spaced = WordBoundary.Replace(input, " ");
        spaced = string.Join(" ", spaced.Split(' ', StringSplitOptions.RemoveEmptyEntries));
        if (spaced.Length == 0) { return input; }
        return char.ToUpper(spaced[0], CultureInfo.CurrentCulture) + spaced[1..];
    }

    public static string Stringify(object? value)
    {
        if (value is null) { return string.Empty; }
        if (value is string text) { return text; }
        if (value is char character) { return character.ToString(); }
        if (value is bool boolean) { return boolean ? "Yes" : "No"; }
        if (value is float single) { return Number(single); }
        if (value is double number) { return Number(number); }
        if (value is decimal decimalNumber) { return Number((double)decimalNumber); }
        if (value is Identifier identifier) { return identifier.Value ?? string.Empty; }
        if (value is LocalizedString localized) { return localized.Value ?? string.Empty; }

        Type type = value.GetType();
        if (type.IsPrimitive || type.IsEnum)
        {
            return Convert.ToString(value, CultureInfo.InvariantCulture) ?? string.Empty;
        }

        try
        {
            object? nested = ReflectionTools.GetMember(value, "Value");
            if (nested is string nestedString) { return nestedString; }
        }
        catch { }

        try { return value.ToString() ?? string.Empty; }
        catch { return type.Name; }
    }

    public static string Number(double value)
    {
        if (Math.Abs(value) < 0.0005) { value = 0.0; }
        return value.ToString("0.###", CultureInfo.InvariantCulture);
    }

    public static string JoinValues(object? collection, int maximum = 20)
    {
        if (collection is null) { return string.Empty; }
        if (collection is string text) { return text; }
        if (collection is not IEnumerable enumerable) { return Stringify(collection); }

        var values = new List<string>();
        int total = 0;
        foreach (object? entry in enumerable)
        {
            total++;
            if (values.Count < maximum)
            {
                string value = Stringify(entry);
                if (!string.IsNullOrWhiteSpace(value)) { values.Add(value); }
            }
        }
        if (total > maximum) { values.Add($"+{total - maximum}"); }
        return string.Join(", ", values);
    }
}

internal static class ReflectionTools
{
    private const BindingFlags InstanceFlags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;
    private const BindingFlags StaticFlags = BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;

    public static object? GetMember(object? target, params string[] names)
    {
        if (target is null) { return null; }
        Type type = target.GetType();
        foreach (string name in names)
        {
            try
            {
                PropertyInfo? property = type.GetProperty(name, InstanceFlags | BindingFlags.IgnoreCase);
                if (property is not null && property.GetIndexParameters().Length == 0)
                {
                    return property.GetValue(target);
                }
                FieldInfo? field = type.GetField(name, InstanceFlags | BindingFlags.IgnoreCase);
                if (field is not null) { return field.GetValue(target); }
            }
            catch
            {
                // Prefabs supplied by other mods are allowed to throw from optional getters.
            }
        }
        return null;
    }

    public static T? GetMember<T>(object? target, params string[] names)
    {
        object? value = GetMember(target, names);
        if (value is T typed) { return typed; }
        return default;
    }

    public static object? GetStaticMember(Type type, params string[] names)
    {
        foreach (string name in names)
        {
            try
            {
                PropertyInfo? property = type.GetProperty(name, StaticFlags | BindingFlags.IgnoreCase);
                if (property is not null && property.GetIndexParameters().Length == 0)
                {
                    return property.GetValue(null);
                }
                FieldInfo? field = type.GetField(name, StaticFlags | BindingFlags.IgnoreCase);
                if (field is not null) { return field.GetValue(null); }
            }
            catch { }
        }
        return null;
    }

    public static IEnumerable<object> Enumerate(object? value)
    {
        if (value is null || value is string) { yield break; }
        if (value is IDictionary dictionary)
        {
            foreach (DictionaryEntry pair in dictionary)
            {
                if (pair.Value is not null) { yield return pair.Value; }
            }
            yield break;
        }
        if (value is not IEnumerable enumerable) { yield break; }
        IEnumerator? iterator = null;
        try
        {
            iterator = enumerable.GetEnumerator();
            while (iterator.MoveNext())
            {
                if (iterator.Current is not null) { yield return iterator.Current; }
            }
        }
        finally
        {
            (iterator as IDisposable)?.Dispose();
        }
    }

    public static Type? FindType(string fullName)
    {
        foreach (System.Reflection.Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            try
            {
                Type? type = assembly.GetType(fullName, throwOnError: false, ignoreCase: false);
                if (type is not null) { return type; }
            }
            catch { }
        }
        return null;
    }

    public static Sprite? FindSprite(object prefab)
    {
        foreach (string member in new[]
                 {
                     "InventoryIcon", "Icon", "IconSmall", "Sprite", "SchematicSprite",
                     "MinimapIcon", "SonarIcon"
                 })
        {
            if (GetMember(prefab, member) is Sprite sprite) { return sprite; }
        }
        return null;
    }

    public static ContentXElement? FindConfigElement(object prefab)
        => GetMember(prefab, "ConfigElement", "Element") as ContentXElement;

    public static IReadOnlyList<MemberInfo> ReadableMembers(Type type)
    {
        var members = new List<MemberInfo>();
        members.AddRange(type.GetProperties(InstanceFlags)
            .Where(property => property.GetIndexParameters().Length == 0 && property.GetMethod is not null));
        members.AddRange(type.GetFields(InstanceFlags));
        return members
            .GroupBy(member => member.Name, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.OrderBy(member => member is PropertyInfo ? 0 : 1).First())
            .OrderBy(member => member.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    public static object? Read(object target, MemberInfo member)
    {
        try
        {
            return member switch
            {
                PropertyInfo property => property.GetValue(target),
                FieldInfo field => field.GetValue(target),
                _ => null
            };
        }
        catch { return null; }
    }
}
