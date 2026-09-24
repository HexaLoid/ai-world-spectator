# World Content Expansion — Design (Phase 4a of 4)

Date: 2026-09-25

## Context

Phase 4 of the Erenshor-style roadmap is split in two: **4a (this document)**
expands the world's content; **4b** adds an in-game codex (bestiary + item
list) that reads this content. Phases 1-3 (loot & gear depth, character sheet
& target frame, party frames & ally chat) are done.

Today the world is three zones in a line (Thornfield Meadow, Blackthorn Forest,
Sundered Crypt), five enemy types built from two sprite sheets (wolf, bandit),
six quests, 27 items and a level cap of 5. Enemy stats live inside each
`SpawnPoint` node as long lists of per-field overrides in the zone scenes; there
is no central enemy table. A character that reaches level 5 has nothing left to
progress toward.

## Goals

- A central, data-driven **enemy table** that spawn points, quests and (later)
  the codex all read.
- **Two new zones** (Mirewater Swamp, Frostpeak Pass) appended to the travel
  loop, with their own enemy mixes, bosses and one extra ally each.
- **Level cap 10** with a longer XP curve.
- **About a dozen new gear items** for levels 5-10 and **level-aware loot** so
  early enemies stop dropping gear the character cannot use.
- **Seven new quests** covering the new zones, converging on a final capstone.
- Table-driven validation tests so content stays consistent as it grows.

## Non-goals

- New creature art or tilesets (new enemies are tinted/rescaled wolf and bandit
  sprites; new zones re-tint existing terrain and tree art). No downloads.
- The codex UI (phase 4b).
- Gear for allies, new classes, new abilities, per-zone weather.

## Enemy table

`EnemyTable` (`scripts/systems/enemy_table.gd`, static, keyed by enemy id):

```
"mire_wolf": {
    "name": "Mire Wolf",            # matches quest target_name and the log text
    "sprite": "wolf",               # "wolf" or "bandit": which SpriteFrames to use
    "tint": Color(0.55, 0.85, 0.6, 1), "sprite_size": 40.0,
    "max_hp": 45, "move_speed": 72.0,
    "attack_min": 5, "attack_max": 9, "aggro_range": 120.0,
    "xp_reward": 55, "gold_min": 3, "gold_max": 6,
    "loot_level": 6,                # random drops only pick items with level_req <= this
    "guaranteed_drop": "",          # boss/elite drop, "" for none
}
```

- `EnemyTable.ENEMIES` holds every enemy: the five existing ones with stats
  identical to today's scene overrides (Wolf, Dire Wolf, Bandit, Bandit Captain,
  Crypt Lord), plus the new ones below.
- `EnemyTable.SPRITE_FRAMES` maps `"wolf"`/`"bandit"` to the existing
  `SpriteFrames` resource paths (`wolf_frames.tres`, `bandit_frames.tres`).
- Helpers: `EnemyTable.get_def(id)`, `EnemyTable.name_of(id)`,
  `EnemyTable.ids_named(name)` (used by validation and later by the codex).
- Enemy names are unique across the table (quests match kills by name).

`SpawnPoint` gains `@export var enemy_id: String`. When set, `_spawn()` applies
the table entry (name, stats, tint, size, sprite frames, gold range, loot level,
guaranteed drop) instead of the per-field overrides. The override exports are
removed and the three existing zone scenes are converted to `enemy_id`
(`respawn_delay_s` stays a per-spawn-point export). `Enemy` gains
`@export var loot_level: int = 1`.

## Levels and loot

- `LevelingSystem.MAX_LEVEL = 10`; `XP_THRESHOLDS = [100, 250, 450, 700, 1000,
  1400, 1900, 2500, 3200]` (levels 2-10); HP and damage per level unchanged.
- **New items** (about 13, ids and stats fixed in the plan), level 5-9
  requirements, rare and epic, covering every slot and both classes (warrior and
  mage weapons), with icons from the Kyrise pack already extracted for phase 1
  (credited in `assets/CREDITS.txt`). Existing item ids are unchanged.
- **Level-aware drops:** `LootTable.roll_drop(rng, loot_level)` only considers
  items with `level_req <= loot_level` (consumables count as level 1). Epic items
  still never roll randomly. `Enemy._drop_loot` passes its `loot_level`. With the
  default `loot_level` of the five existing enemies raised only as far as their
  zone warrants (Thornfield 2, Blackthorn 3, Crypt 4), drops in early zones are
  always usable.
- Boss and elite `guaranteed_drop` items must have `level_req` at most 2 above
  the zone's `min_level` (a character normally reaches a boss a level or two
  after entering the zone; validated by tests).

## Zones

`ZoneTable` gains:

| Zone | id | center | bounds | min_level | stay |
|---|---|---|---|---|---|
| Mirewater Swamp | `mirewater_swamp` | (6600, 0) | (6220, -280) to (6980, 280) | 4 | default |
| Frostpeak Pass | `frostpeak_pass` | (8800, 0) | (8420, -280) to (9180, 280) | 7 | default |

`TRAVEL_ORDER` becomes meadow, forest, crypt, swamp, pass (then loops).
`WORLD_BOUNDS_MAX` becomes `(9180, 280)`.

`World.tscn` gains the two zone scenes at `(6600, 0)` and `(8800, 0)` and the
corridor sprites/rects between the previous zone edge and the next
(Sundered Crypt to Mirewater, Mirewater to Frostpeak), matching the existing
corridor style. Each new zone scene follows `BlackthornForest.tscn`'s structure:
800x600 background color rect, a tinted ground sprite (grass re-tinted dark
teal for the swamp, near-white blue for the pass), scattered decorations, tinted
pine trees around the border (snow-dusted look for the pass via a light tint),
a pond in the swamp, and the spawn points below. Each gets one
`SimulatedPlayer` (`Vesper` in Mirewater, `Hrolf` in Frostpeak) and the swamp
also gets one `QuestGiver` board (the board group logic already picks the
nearest board), so quests can be turned in without a full trek back.

Nothing else is zone-id-specific (the audio director only special-cases the
crypt; the camera is unbounded), so no other code changes for zones.

## New enemies

| Id / name | Sprite | Zone | HP | Damage | XP | Notes |
|---|---|---|---|---|---|---|
| `mire_wolf` Mire Wolf | wolf, green tint | swamp | 45 | 5-9 | 55 | loot_level 6 |
| `bog_bandit` Bog Bandit | bandit, green tint | swamp | 55 | 6-11 | 65 | loot_level 6 |
| `mire_tyrant` Mire Tyrant | bandit, large, dark green | swamp boss | 260 | 14-24 | 600 | guaranteed epic drop, respawn 120 s |
| `frost_wolf` Frost Wolf | wolf, pale blue | pass | 70 | 8-13 | 90 | loot_level 9 |
| `frost_raider` Frost Raider | bandit, ice blue | pass | 85 | 9-15 | 105 | loot_level 9 |
| `raider_captain` Raider Captain | bandit, large, blue | pass elite | 180 | 12-20 | 260 | guaranteed rare drop, respawn 90 s |
| `frostpeak_warlord` Frostpeak Warlord | bandit, very large, white | pass boss | 420 | 18-30 | 1200 | guaranteed epic drop, respawn 150 s |

Each new zone spawns a mix (swamp: 2 Mire Wolves, 2 Bog Bandits, the Tyrant;
pass: 2 Frost Wolves, 2 Frost Raiders, the Captain, the Warlord). Stats are
starting values and are tuned during the live check.

## Quests

Seven new entries in `QuestTable.QUESTS` (ids, target, count, min_level,
requires; exact XP and item rewards in the plan):

- swamp: `drain_the_mire` (Mire Wolf x4, L4, requires `the_crypt_lord`),
  `bog_bandits` (Bog Bandit x3, L4, requires `the_crypt_lord`), `the_mire_tyrant`
  (Mire Tyrant x1, L5, requires both).
- pass: `frozen_fangs` (Frost Wolf x4, L7, requires `the_mire_tyrant`),
  `raiders_of_the_pass` (Frost Raider x3, L7, requires `the_mire_tyrant`),
  `raider_captain_bounty` (Raider Captain x1, L8, requires both),
  `the_frostpeak_warlord` (Frostpeak Warlord x1, L9, requires the captain bounty
  and `hero_of_thornfield`).

Rewards are items with `level_req` at or below the quest's `min_level`.

## Allies

Two new `SimulatedPlayer` instances (`Vesper`, `Hrolf`) with `home_zone_id` set
to their zone; `tests/suite_name_table.gd`'s ally-name list gains both so the
character's name pool cannot collide with them.

## Testing

New/extended headless suites:

- `suite_enemy_table.gd`: every entry has a known sprite, positive HP, `attack_min
  <= attack_max`, gold range valid, `loot_level` in 1..MAX_LEVEL, unique names;
  every `guaranteed_drop` exists in `LootTable.ITEMS`; the five original enemies
  keep their original stats (regression).
- `suite_zone_table.gd`: every id in `TRAVEL_ORDER` exists and vice versa; bounds
  contain the zone center; zones do not overlap; `min_level` never decreases along
  `TRAVEL_ORDER` and never exceeds `MAX_LEVEL`; `WORLD_BOUNDS` contain every zone.
- `suite_quest_table.gd`: every `target_name` is an `EnemyTable` name, every
  `requires` id exists and the chain is acyclic, every reward item exists and its
  `level_req <= min_level`, `min_level <= MAX_LEVEL`.
- `suite_leveling_system.gd`: `MAX_LEVEL == 10`, thresholds strictly increasing
  with length `MAX_LEVEL - 1`, `apply_xp` reaches level 10 and stops there.
- `suite_loot_table.gd` (extended): `roll_drop(rng, loot_level)` never returns an
  item above `loot_level`, never an epic, and always returns something at level 1;
  boss/elite guaranteed drops satisfy `level_req <= zone min_level + 2`.
- `suite_spawn_points.gd`: reads every `scenes/world/*.tscn` as text and checks each
  `enemy_id = "..."` value exists in `EnemyTable` (catches typos in scenes).

Live checks: the character travels through all five zones (teleport with
`game_eval` to save time), enemies show their tints/sizes and correct names, new
loot drops are usable, bosses drop their guaranteed items, quests progress and
turn in (swamp board), levels reach 10 with correct XP bar, no errors.
