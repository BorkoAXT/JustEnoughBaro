# Europa Encyclopedia

A dynamic in-game journal for Barotrauma, implemented with LuaCsForBarotrauma.

## Features

- Bestiary generated from every loaded `CharacterPrefab`, including compatible creature mods.
- Server-authoritative first-kill discovery shared by the crew and persisted per campaign.
- Searchable item database generated from every loaded `ItemPrefab`.
- Read-only profession pages with starting skills and hoverable talent trees.
- Affliction reference pages with effects, stat stages, treatments and item causes.
- Fabrication recipes plus an automatically generated **Used to craft** reverse index.
- Deconstruction outputs, conditions/chances, and an automatically generated source index.
- Clickable ingredient, output, reverse-crafting, and deconstruction-source navigation.
- Lazy detail pages and capped list population for large mod packs.
- Barotrauma-native GUI styles; press **J** to toggle (editable in `config.lua`).

## Install

1. Install the current LuaCsForBarotrauma client patch. A server/host must also run LuaCs for authoritative discoveries.
2. Copy this directory to `Barotrauma/LocalMods/Europa Encyclopedia`.
3. Enable **Europa Encyclopedia** in Barotrauma's mod list and restart the game.

## Testing

- Press **J** to open the journal. It is deliberately drawn above inventories,
  containers, stores and workbench interfaces.
- `encyclopedia_test all` unlocks all bestiary pages in single-player.
- `encyclopedia_corpse mudraptor` spawns a mudraptor at the cursor and, after a
  short delay, runs `killmonsters` so the normal death/discovery hook can be tested.
  This kills every currently living monster, so use it only in a disposable test round.
4. In multiplayer, the server and clients must enable the content package. Press **J** in a round.

LuaCs documentation and installer: https://github.com/evilfactory/LuaCsForBarotrauma

## Configuration

Edit `config.lua` before launch. `openKey` accepts an XNA `Keys` enum name. `pageSize` limits instantiated search rows; refining the search reveals the rest.

## Persistence

The server writes newline-delimited species identifiers under `Data/`, keyed from the campaign save path. Clients can only request the current set; they cannot report kills or unlock entries.

## Known data limitations

The encyclopedia only renders fields reliably exposed by loaded prefabs. Creature XML varies substantially, so it does not fabricate armor, spawn, loot, or attack summaries where the runtime prefab does not expose a stable value. The data/index layer is structured so these panels can be added independently.
