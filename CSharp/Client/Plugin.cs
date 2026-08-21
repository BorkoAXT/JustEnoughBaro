#nullable enable

using System;
using System.Collections.Generic;
using Barotrauma;
using Barotrauma.LuaCs;
using Barotrauma.LuaCs.Data;
using Barotrauma.LuaCs.Events;
using Microsoft.Xna.Framework.Input;

namespace JustEnoughBaro;

/// <summary>LuaCs client assembly entry point.</summary>
public sealed class Plugin : IAssemblyPlugin, IEventKeyUpdate, IEventRoundEnded
{
    public IEventService EventService { get; set; } = null!;
    public IConfigService ConfigService { get; set; } = null!;
    public IPluginManagementService PluginManagementService { get; set; } = null!;

    private ConfigFile<JebConfig>? configFile;
    private ConfigFile<UserState>? stateFile;
    private ISettingBase<string>? openKeySetting;
    private JebConfig config = JebConfig.Defaults();
    private UserState state = new();
    private PrefabCatalog? catalog;
    private MetadataExtractor? metadata;
    private CreatureMediaRepository? creatureMedia;
    private RecipeTrackerHud? tracker;
    private EncyclopediaWindow? browser;
    private Keys openKey = Keys.J;
    private bool initialized;
    private bool disposed;

    public void PreInitPatching()
    {
        // JEB reads publicized/internal prefab data and does not patch game methods.
    }

    public void Initialize()
    {
        if (disposed || initialized) { return; }
        initialized = true;
        EventService.Subscribe<IEventKeyUpdate>(this);
        EventService.Subscribe<IEventRoundEnded>(this);
    }

    public void OnLoadCompleted()
    {
        if (disposed) { return; }
        try
        {
            var store = new ConfigStore("JustEnoughBaro");
            configFile = store.Register(
                "settings-v1",
                JebConfig.Defaults,
                ValidateConfig,
                MigrateConfig);
            stateFile = store.Register(
                "user-state-v1",
                () => new UserState(),
                ValidateState,
                MigrateState);
            config = configFile.Load();
            state = stateFile.Load();
            BindVisibleSettings();
            ParseOpenKey(config.OpenKey);

            catalog = new PrefabCatalog();
            CatalogSnapshot snapshot = catalog.Build();
            metadata = new MetadataExtractor(config.MetadataDepth);
            creatureMedia = new CreatureMediaRepository();
            tracker = new RecipeTrackerHud(config, state, SaveAll);
            browser = new EncyclopediaWindow(
                catalog, metadata, creatureMedia, tracker, state, config, SaveAll);

            LuaCsLogger.LogMessage(L.F("status.ready", snapshot.All.Count, catalog.LastBuildMilliseconds));
        }
        catch (Exception exception)
        {
            LuaCsLogger.LogError($"[JEB] Initialization failed: {exception}");
            DisposeRuntime();
        }
    }

    public void OnKeyUpdate(double deltaTime)
    {
        if (disposed) { return; }

        tracker?.Update(deltaTime);
        browser?.Update(deltaTime);

        if (browser is null || GUI.KeyboardDispatcher.Subscriber is GUITextBox) { return; }
        if (PlayerInput.KeyHit(openKey))
        {
            bool inspect = PlayerInput.KeyDown(Keys.LeftShift) || PlayerInput.KeyDown(Keys.RightShift);
            Item? selectedItem = Character.Controlled?.SelectedItem;
            if (inspect && selectedItem?.Prefab is not null)
            {
                browser.OpenItem(TextTools.NormalizeIdentifier(selectedItem.Prefab.Identifier));
            }
            else
            {
                browser.Toggle();
            }
            return;
        }
        if (browser.IsVisible && GUI.KeyboardDispatcher.Subscriber is null && PlayerInput.KeyHit(Keys.Escape))
        {
            browser.Close();
        }
    }

    public void OnRoundEnd()
    {
        browser?.Close();
    }

    private void BindVisibleSettings()
    {
        if (!PluginManagementService.TryGetPackageForPlugin<Plugin>(out ContentPackage package))
        {
            LuaCsLogger.LogError("[JEB] Could not resolve the owning content package; using the default open key.");
            return;
        }
        if (!ConfigService.TryGetConfig<ISettingBase<string>>(package, "OpenKey", out ISettingBase<string>? setting))
        {
            return;
        }

        openKeySetting = setting;
        config.OpenKey = setting.Value;
        openKeySetting.OnValueChanged += OnVisibleSettingChanged;
    }

    private void OnVisibleSettingChanged(ISettingBase setting)
    {
        if (setting is not ISettingBase<string> text) { return; }
        config.OpenKey = text.Value;
        ParseOpenKey(config.OpenKey);
        configFile?.Save(config);
    }

    private void ParseOpenKey(string? value)
    {
        if (Enum.TryParse(value?.Trim(), ignoreCase: true, out Keys parsed) && parsed != Keys.None)
        {
            openKey = parsed;
            return;
        }
        openKey = Keys.J;
        config.OpenKey = "J";
        LuaCsLogger.LogError($"[JEB] Unknown open key '{value}'. Falling back to J.");
    }

    private void SaveAll()
    {
        stateFile?.Save(state);
        configFile?.Save(config);
    }

    private static bool ValidateConfig(JebConfig value)
        => value.PageSize is >= 25 and <= 500 &&
           value.MetadataDepth is >= 1 and <= 4 &&
           value.TrackerX is >= 0 and <= 1 &&
           value.TrackerY is >= 0 and <= 1 &&
           !string.IsNullOrWhiteSpace(value.OpenKey);

    private static JebConfig MigrateConfig(JebConfig value)
    {
        value.Version = 1;
        value.PageSize = Math.Clamp(value.PageSize, 25, 500);
        value.MetadataDepth = Math.Clamp(value.MetadataDepth, 1, 4);
        value.TrackerX = Math.Clamp(value.TrackerX, 0.0f, 1.0f);
        value.TrackerY = Math.Clamp(value.TrackerY, 0.0f, 1.0f);
        if (string.IsNullOrWhiteSpace(value.OpenKey)) { value.OpenKey = "J"; }
        return value;
    }

    private static bool ValidateState(UserState value)
        => value.Favorites is not null && value.History is not null && value.CustomProfile is not null;

    private static UserState MigrateState(UserState value)
    {
        value.Version = 1;
        value.Favorites ??= new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        value.History ??= new List<NavigationEntry>();
        value.CustomProfile ??= WindowProfile.CreateCustom();
        if (string.IsNullOrWhiteSpace(value.ActiveProfile)) { value.ActiveProfile = "Balanced"; }
        value.HistoryIndex = Math.Clamp(value.HistoryIndex, -1, value.History.Count - 1);
        return value;
    }

    private void DisposeRuntime()
    {
        if (openKeySetting is not null)
        {
            openKeySetting.OnValueChanged -= OnVisibleSettingChanged;
            openKeySetting = null;
        }
        browser?.Dispose();
        browser = null;
        tracker?.Dispose();
        tracker = null;
        creatureMedia?.Dispose();
        creatureMedia = null;
        metadata?.Clear();
        metadata = null;
        catalog = null;
        stateFile?.Save(state);
        stateFile = null;
        configFile?.Save(config);
        configFile = null;
    }

    public void Dispose()
    {
        if (disposed) { return; }
        disposed = true;
        if (initialized)
        {
            EventService.Unsubscribe<IEventKeyUpdate>(this);
            EventService.Unsubscribe<IEventRoundEnded>(this);
        }
        DisposeRuntime();
        initialized = false;
        GC.SuppressFinalize(this);
    }
}
