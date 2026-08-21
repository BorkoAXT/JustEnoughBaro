# Just Enough Baro (JEB)

Just Enough Baro is a client-side, in-game reference browser for Barotrauma. The current runtime is written entirely in C# and loaded by LuaCsForBarotrauma from `CSharp/Client`; no Lua file is loaded by `ModConfig.xml`.

## Features

- A unified browser for loaded items, afflictions, creatures, biomes, talents, professions, missions, submarines, structures, upgrades, item assemblies, level objects, and events, including content added by other mods.
- Fabrication, deconstruction, obtain, and usage views with reverse recipe indexes, alternative ingredients, conditions, devices, skill requirements, and unlock information.
- Structured right-panel metadata grouped into readable sections such as identity, economy, contained objects, equipment, weapon, medical, electrical, creature, talent, and world-generation information.
- An affliction reference built from every loaded `AfflictionPrefab`, with strength stages, periodic effects, treatments, item causes, suitability, and contraindications when the prefab exposes them.
- Creature previews and anatomy data derived from loaded character and ragdoll definitions, with bundled wiki media used as a vanilla fallback.
- Connection-panel diagrams and pin tooltips backed by 101 distinct panels imported from the official Barotrauma Wiki (including secondary loader panels), with current-vanilla variant aliases and localized per-pin fallbacks for modded or undocumented components.
- A movable and resizable three-panel interface, visual layout profiles, clickable type separators, combined search, browser-style back/forward navigation, and pinned records.
- A HUD fabrication tracker that updates carried ingredient counts without consuming items.
- English, Russian, and Brazilian Portuguese interface support.

The clinical simulator and raw XML viewer are intentionally not part of JEB.

## Requirements and installation

JEB uses LuaCsForBarotrauma's supported in-memory C# assembly loader. C# mods are unrestricted and are disabled by LuaCs by default.

1. Install the current [LuaCsForBarotrauma](https://github.com/evilfactory/LuaCsForBarotrauma) client patch.
2. In the LuaCs settings menu, enable **CSharp**. LuaCs can also prompt for temporary permission when joining a server that requires a C# package.
3. Copy this directory to `Barotrauma/LocalMods/Just Enough Baro (JEB)` and enable **Just Enough Baro (JEB)** in Barotrauma's mod list.
4. Restart the client after enabling or updating the mod. The C# sources are compiled when LuaCs loads the package, so the first load can take a little longer.
5. Press **J** in game, or change the key in Barotrauma's mod settings. Hold **Shift** while pressing the key to jump directly to the currently selected item's page.

JEB contains no server assembly and does not alter simulation state. Each player who wants the browser must install and enable it on their own client.

## Configuration and user state

The open key is exposed through LuaCs' in-game configuration service. Favorites, history, active layout, window geometry, and tracked recipe state are stored as versioned per-user data rather than inside the mod or Workshop directory.

The window clamps itself to the current resolution. Built-in profiles provide compact, balanced, wide, and distraction-free layouts; the custom profile preserves manual position, size, and the selected panel arrangement.

## Source layout

- `CSharp/Client/Core` contains shared models, localization, text helpers, and typed configuration persistence.
- `CSharp/Client/Data` builds the loaded-prefab catalog, reverse indexes, structured metadata, creature anatomy, and offline media lookups.
- `CSharp/Client/Features` contains independent client features such as the HUD recipe tracker.
- `CSharp/Client/UI` contains Barotrauma-native GUI construction and the responsive browser interface.
- `Data` and `Assets` contain curated offline reference data and fallback media. Runtime browsing still comes from loaded prefabs, so modded content does not require entries in those datasets.
- `scripts` contains offline import and validation utilities. These scripts are development tools and never access the network during gameplay.

`ModConfig.xml` declares one recursive client source assembly:

```xml
<Assembly Folder="%ModDir%/CSharp/Client" Target="Client" IsScript="true" UseInternalAccessName="true" />
```

Do not add compiled DLL assembly entries alongside the source entry: loading both would initialize two copies of JEB. A future compiled release must replace the source declaration with one platform-specific client DLL declaration per supported platform.

For offline structural checks, run `python3 scripts/validate_mod.py`. The optional IDE/build project can be compiled with `dotnet build CSharp/JustEnoughBaro.Client.csproj -p:BarotraumaDir=/absolute/path/to/Barotrauma`; it is a validation project and is not loaded by the mod package.

## Data and attribution

Some bundled creature descriptions, images, and connection-panel documentation are derived from the official Barotrauma Wiki. Source and license details are recorded in [NOTICE](NOTICE). The game and wiki remain authoritative when cached reference material differs from the currently installed game version.

## Known limitations

- Prefabs vary widely between game versions and mods. JEB omits a metadata row when a stable value cannot be read instead of inventing one.
- A generated level or arbitrary submarine is not instantiated merely to create a preview. Map, skeleton, and preview tabs render safe data already supplied by loaded prefabs or the current game state.
- Official wiki pin documentation covers vanilla components. Modded connection panels are displayed from their loaded definitions and clearly identify pins without curated descriptions.
