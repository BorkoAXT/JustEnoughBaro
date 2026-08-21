#nullable enable

using System;
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using Barotrauma;

namespace JustEnoughBaro;

/// <summary>
/// Small, type-agnostic configuration helper. It is deliberately independent from the
/// LuaCs settings types: any serializable object can opt into defaults, validation and a
/// migration callback. Writes are atomic so an interrupted save cannot destroy the last
/// working configuration.
/// </summary>
internal sealed class ConfigStore
{
    private readonly string root;
    private readonly ConcurrentDictionary<string, object> gates = new(StringComparer.OrdinalIgnoreCase);
    private readonly JsonSerializerOptions jsonOptions = new()
    {
        AllowTrailingCommas = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter() }
    };

    public ConfigStore(string applicationName)
    {
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(local))
        {
            local = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        }
        if (string.IsNullOrWhiteSpace(local))
        {
            local = ".";
        }

        root = Path.Combine(local, "Barotrauma", Sanitize(applicationName));
        Directory.CreateDirectory(root);
    }

    public string Root => root;

    public ConfigFile<T> Register<T>(
        string name,
        Func<T> defaults,
        Func<T, bool>? validator = null,
        Func<T, T>? migrate = null)
        where T : class
    {
        string safeName = Sanitize(name);
        string path = Path.Combine(root, safeName + ".json");
        object gate = gates.GetOrAdd(path, _ => new object());
        return new ConfigFile<T>(path, defaults, validator, migrate, jsonOptions, gate);
    }

    private static string Sanitize(string value)
    {
        char[] invalid = Path.GetInvalidFileNameChars();
        string safe = new(value.Select(c => invalid.Contains(c) ? '_' : c).ToArray());
        return string.IsNullOrWhiteSpace(safe) ? "config" : safe.Trim();
    }
}

internal sealed class ConfigFile<T> where T : class
{
    private readonly string path;
    private readonly Func<T> defaults;
    private readonly Func<T, bool>? validator;
    private readonly Func<T, T>? migrate;
    private readonly JsonSerializerOptions options;
    private readonly object gate;

    internal ConfigFile(
        string path,
        Func<T> defaults,
        Func<T, bool>? validator,
        Func<T, T>? migrate,
        JsonSerializerOptions options,
        object gate)
    {
        this.path = path;
        this.defaults = defaults;
        this.validator = validator;
        this.migrate = migrate;
        this.options = options;
        this.gate = gate;
    }

    public string Path => path;

    public T Load()
    {
        lock (gate)
        {
            try
            {
                if (!File.Exists(path))
                {
                    T initial = defaults();
                    SaveUnsafe(initial);
                    return initial;
                }

                string json = File.ReadAllText(path);
                T? value = JsonSerializer.Deserialize<T>(json, options);
                if (value is null)
                {
                    throw new InvalidDataException("The configuration contained no object.");
                }

                if (migrate is not null)
                {
                    value = migrate(value);
                }

                if (validator is not null && !validator(value))
                {
                    throw new InvalidDataException("The configuration did not pass validation.");
                }

                return value;
            }
            catch (Exception exception)
            {
                LuaCsLogger.LogError($"[JEB] Could not load {System.IO.Path.GetFileName(path)}: {exception.Message}");
                T fallback = defaults();
                TryArchiveBrokenFile();
                SaveUnsafe(fallback);
                return fallback;
            }
        }
    }

    public bool Save(T value)
    {
        lock (gate)
        {
            try
            {
                if (validator is not null && !validator(value))
                {
                    LuaCsLogger.LogError($"[JEB] Refused to save invalid {System.IO.Path.GetFileName(path)}.");
                    return false;
                }
                SaveUnsafe(value);
                return true;
            }
            catch (Exception exception)
            {
                LuaCsLogger.LogError($"[JEB] Could not save {System.IO.Path.GetFileName(path)}: {exception.Message}");
                return false;
            }
        }
    }

    private void SaveUnsafe(T value)
    {
        string? directory = System.IO.Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        string temporary = path + ".tmp";
        string json = JsonSerializer.Serialize(value, options);
        File.WriteAllText(temporary, json);
        File.Move(temporary, path, overwrite: true);
    }

    private void TryArchiveBrokenFile()
    {
        if (!File.Exists(path)) { return; }
        try
        {
            string archive = path + ".broken-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss");
            File.Move(path, archive);
        }
        catch
        {
            // Recovery must never prevent the mod from starting with defaults.
        }
    }
}
