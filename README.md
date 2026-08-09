# Europa Encyclopedia

A dynamic in-game journal for Barotrauma, implemented with LuaCsForBarotrauma.

## Features

- Bestiary generated from every loaded `CharacterPrefab`, including compatible creature mods.
- A fully unlocked bestiary generated from loaded creature content.
- Searchable item database generated from every loaded `ItemPrefab`.
- Item-category filters for weapons, ammunition, gear, ores, alien/ruin items and more.
- Read-only profession pages with native-style, hoverable three-column talent trees.
- Clickable crafting skill requirements that open the associated profession reference.
- Affliction reference pages with effects, stat stages, treatments and item causes.
- Fabrication recipes plus an automatically generated **Used to craft** reverse index.
- Deconstruction outputs, conditions/chances, and an automatically generated source index.
- Clickable ingredient, output, reverse-crafting, and deconstruction-source navigation.
- Lazy detail pages and capped list population for large mod packs.
- Barotrauma-native GUI styles with an in-game configurable open key.

## Install

1. Install the current LuaCsForBarotrauma client patch.
2. Copy this directory to `Barotrauma/LocalMods/Europa Encyclopedia`.
3. Enable **Europa Encyclopedia** in Barotrauma's mod list and restart the game.

## Testing

- Press **J** to open the journal. It is deliberately drawn above inventories,
  containers, stores and workbench interfaces.
- `encyclopedia_corpse mudraptor` spawns a mudraptor at the cursor and, after a
  short delay, runs `killmonsters` so corpse targeting can be tested.
  This kills every currently living monster, so use it only in a disposable test round.
4. In multiplayer, the server and clients must enable the content package. Press **J** in a round.

LuaCs documentation and installer: https://github.com/evilfactory/LuaCsForBarotrauma

## Configuration

Change the encyclopedia key in Barotrauma's mod settings. Enter an XNA key name
such as `J`, `K`, or `F6`; invalid values fall back to `J`. The `pageSize` value
in `config.lua` limits instantiated search rows, and refining the search reveals
the remaining results.

## Code style

Lua files use the repository's `stylua.toml` rules. Keep one operation per line,
give domain values descriptive constant names, and place callback bodies on their
own lines. Run `stylua config.lua Lua` before committing Lua changes.

## Known data limitations

The encyclopedia only renders fields reliably exposed by loaded prefabs. Creature XML varies substantially, so it does not fabricate armor, spawn, loot, or attack summaries where the runtime prefab does not expose a stable value. The data/index layer is structured so these panels can be added independently.
