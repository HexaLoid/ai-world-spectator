# In-Game Codex — Design (Phase 4b of 4)

Date: 2026-09-25

## Context

Last phase of the Erenshor-style roadmap. Phase 4a made the world's content
data-driven (`EnemyTable`, `LootTable`, `ZoneTable`, `QuestTable`: 12 enemies,
42 items, 5 zones, 13 quests). The codex is the in-game "wiki": a panel that
lists what the character has discovered, filling in as it explores.

## Goals

- A toggleable **codex panel** with three tabs: **Bestiary**, **Items**, **Zones**.
- Entries **fill in as discovered**; undiscovered ones show as `???`.
- New discoveries are announced in the activity log.
- The data logic (discovery state, item sources, entry text) is pure and unit-tested.

## Non-goals

- A quests tab (the tracker and character sheet cover quests).
- Saving discoveries between launches (session only, like the sheet's statistics).
- New art; portraits reuse existing sprites and icons.

## Discovery model

`CodexState` (`scripts/systems/codex_state.gd`, pure, no nodes) keeps three
dictionaries: `enemies_met` (enemy id -> true), `items_found` (item id -> true),
`zones_visited` (zone id -> true). API:

- `discover_enemy(id) -> bool`, `discover_item(id) -> bool`, `visit_zone(id) -> bool`
  (true when the entry was new; unknown ids are ignored and return false).
- `enemy_met(id)`, `item_found(id)`, `zone_visited(id)`, and counts
  `enemies_met_count()`, `items_found_count()`, `zones_visited_count()`.

`GameState` gains `var codex := CodexState.new()` and
`signal codex_changed(kind: String, id: String)` (`kind` is `"enemy"`, `"item"`
or `"zone"`).

What counts as discovered (all by the spectated character only, not allies):

| Kind | Trigger | Where |
|---|---|---|
| enemy | it becomes the character's combat target for the first time | `Character._update_combat_target` (name -> id via `EnemyTable.ids_named`) |
| enemy | the character kills it (also implies met) | `Character.take_kill_credit` |
| item | the character acquires it (equipped or "found") | `Character._acquire_item` |
| zone | the character arrives in it (including the starting zone) | `Character._sync_current_zone` and once in `_ready` |

Each new discovery emits `codex_changed` and logs `Codex: new entry - <name>`.
Kill counts are not duplicated: the codex reads `Character.kills_by_name`
(session statistics from phase 2). An enemy with at least one kill is treated as
met even if the fight was never recorded.

**Reveal tiers for enemies:** *met* shows name, portrait, zone, HP and damage;
*killed at least once* also shows XP, gold and drops. Items and zones are single
tier (discovered or not).

## Data additions

- `EnemyTable` entries gain `"zone": "<zone id>"` (Wolf/Bandit -> thornfield_meadow;
  Dire Wolf/Bandit Captain -> blackthorn_forest; Crypt Lord -> sundered_crypt;
  Mire Wolf/Bog Bandit/Mire Tyrant -> mirewater_swamp; Frost Wolf/Frost Raider/
  Raider Captain/Frostpeak Warlord -> frostpeak_pass).
- `CodexData` (`scripts/systems/codex_data.gd`, pure, static) derives:
  - `item_sources(item_id) -> Dictionary` with `"guaranteed"` (enemy names whose
    `guaranteed_drop` is the item), `"quests"` (names of quests whose
    `item_reward` is the item), `"random_from_loot_level"` (the minimum enemy
    `loot_level` at which it can drop randomly, or `-1` if it never drops
    randomly: epic items, consumables aside, and items above every loot level).
    Consumables can drop randomly like gear (they count as level 1).
  - `zone_enemy_ids(zone_id)`, `zone_boss_id(zone_id)` (the enemy in the zone with
    a `guaranteed_drop` and the highest `max_hp`, or `""`), `zone_level_range(zone_id)`
    (its `min_level` to the next zone's `min_level - 1` capped at `MAX_LEVEL`, or
    `MAX_LEVEL` for the last zone).
  - Ordered id lists: `enemy_order()` (by zone travel order, then max HP),
    `item_order()` (by slot order in `LootTable.SLOTS`, consumables last, then
    level requirement, then id), `zone_order()` (`ZoneTable.TRAVEL_ORDER`).

## Entry text: `CodexText` (`scripts/ui/codex_text.gd`, pure, static)

Every function returns BBCode; all inputs are plain values so it is testable
without nodes.

- `list_label(discovered: bool, name: String) -> String`: `name` or `???`.
- `enemy_entry(id, met, kills, zone_visited) -> String`: name (bold), `Elite`/`Boss`
  tag when the enemy has a guaranteed drop, zone name, HP, damage range; with
  `kills >= 1` adds XP, gold range and drops (guaranteed drop with its rarity
  color, or "possible gear up to level N"). Not met: `Not yet discovered.` plus
  `Lurks somewhere in <Zone>.` only when `zone_visited`.
- `item_entry(id, found) -> String`: rarity-colored name, slot label, level
  requirement, stat line (`ItemScoring.describe_stats`, or `Heals N HP` for
  consumables), and the source lines from `CodexData.item_sources`
  ("Guaranteed drop: ...", "Quest reward: ...", "Random drops from level N enemies"
  or nothing for items with no source). Not found: `Not yet discovered.`, plus the
  slot label as a hint.
- `zone_entry(id, visited, enemies_met_in_zone) -> String`: name, level range,
  enemies listed (met ones by name, others `???`), the boss (name when met, else
  `???`) and a discovered count; not visited: `Not yet discovered.`.
- `tab_title(tab, discovered, total) -> String`: e.g. `Bestiary 5/12`.

## Codex panel

`scripts/ui/codex_panel.gd` on a `Panel` in `SpectatorUI.tscn`.

- **Open/close:** the `B` key (`_unhandled_input`, like the sheet's `C`) or a new
  **Codex (B)** button appended to the existing `SpeedControl` row after the Sheet
  button. Does not pause the game. Hidden by default.
- **Layout:** a large overlay (about 640x420) centered horizontally at y=110 so
  it clears the speed row and the sheet's top edge; dark style like the sheet
  and chat panel. Top: three tab buttons (`Bestiary 5/12`, `Items 9/42`,
  `Zones 3/5`). Left column: `ItemList` of entries (`???` for undiscovered).
  Right column: a portrait `TextureRect` above a `RichTextLabel` (BBCode) with the
  detail text from `CodexText`.
- **Portraits:** enemies show the first frame of `idle_right` from their sprite
  frames (`EnemyTable.SPRITE_FRAMES`), tinted with the enemy's `tint`; items show
  their icon; zones and undiscovered entries show no image.
- **Behavior:** the list's first entry is selected when a tab opens; selection is
  remembered per tab. The panel refreshes on open, on tab change, on selection
  change, and on `codex_changed` while visible (keeping the selection).
- **Freed/absent data:** the panel tolerates a null `GameState.character` and
  shows empty lists in that case.

## Files

- New: `scripts/systems/codex_state.gd`, `scripts/systems/codex_data.gd`,
  `scripts/ui/codex_text.gd`, `scripts/ui/codex_panel.gd`, tests
  (`suite_codex_state.gd`, `suite_codex_data.gd`, `suite_codex_text.gd`).
- Modified: `scripts/autoload/game_state.gd` (codex, signal),
  `scripts/systems/enemy_table.gd` (`zone`), `scripts/entities/character.gd`
  (discovery hooks), `scenes/ui/SpectatorUI.tscn` (panel, button),
  `tests/suite_enemy_table.gd` and `tests/suite_spawn_points.gd` (zone
  consistency), `README.md`.

## Error handling

- Unknown ids never raise: state functions return false, `CodexData`/`CodexText`
  return empty results or `???`.
- Discovery hooks only run when the character exists; a name that maps to no
  enemy id is ignored.

## Testing

New headless suites (every suite ends with `t.done()`):

- `suite_codex_state.gd`: new/duplicate discovery return values, unknown ids,
  counts, independence of the three kinds.
- `suite_codex_data.gd`: `item_sources` for a guaranteed drop (`tyrants_maul` ->
  Mire Tyrant), a quest reward (`reinforced_mail` -> The Mire Tyrant), a random
  item (`rusty_sword`, level 1 source) and an epic with no random source; every
  enemy has a valid zone; each zone has at least one enemy; the boss of every zone
  with a guaranteed drop; the level ranges; ordering functions return every id
  exactly once.
- `suite_codex_text.gd`: `list_label`, enemy entry at each reveal tier, the hint
  only when the zone is visited, item entry (gear, consumable, epic, not found),
  zone entry (met/unmet enemies, boss hidden), tab titles.
- `suite_enemy_table.gd` (extended): every enemy's `zone` exists in `ZoneTable`.
- `suite_spawn_points.gd` (extended): each enemy id used in a zone scene has that
  scene's zone as its `zone`.

Live check: entries start as `???`, fill in as the character fights, kills, finds
items and travels (log lines `Codex: new entry - ...`); tabs and counters update;
`B` and the button toggle the panel; portraits show tinted sprites/icons; the
panel overlaps nothing important at 1152x648 (it may cover the world view while
open); no errors.
