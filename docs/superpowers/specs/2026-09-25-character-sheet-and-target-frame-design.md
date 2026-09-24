# Character Sheet & Target Frame — Design (Phase 2 of 4)

Date: 2026-09-25

## Context

Phase 2 of the Erenshor-style roadmap (1: loot & gear depth — done; 2: richer
HUD & stats; 3: simulated players / social; 4: world & content). The HUD today
has a unit frame (HP/XP/resource bars, six equipment slots, gold), an activity
log, a quest tracker, speed controls and an ability bar. The spectator can see
equipment icons and tooltips but has no place to read the character's full
stats, and no readout of the enemy being fought beyond a tiny bar over its head.

## Goals

- A toggleable **character sheet** showing level/class/zone, derived stats,
  full equipment with stats, gold, quest progress and session statistics.
- A **target frame** for the enemy the character is fighting.
- New session counters: kills (total and per enemy type), deaths, damage
  dealt, damage taken, gold earned, time played.

## Non-goals

- Minimap, log tabs and party frames (party frames belong to phase 3).
- Changing the small health bar over enemies' heads.
- Persisting statistics across launches (session only).

## Character sheet

**Opening:** press `C`, or click a new **Sheet** button added to the existing
speed-control row. It toggles a panel anchored to the right edge of the screen;
it does not pause the game.

**Contents** (one scrollable `RichTextLabel` with BBCode, inside a themed panel):

1. **Header:** "Level 3 Warrior", current zone name, XP as `XP 40 / 100`
   (or `MAX` at max level).
2. **Stats:** HP (`60 / 95`), damage range (`12 - 16`), armor, crit chance
   (`17%`), and the class's primary stat with its damage bonus
   (`Strength 5 (+5% damage)`).
3. **Equipment:** all six slots in HUD order. Each line shows the slot label,
   the item name colored by rarity, and its stats (`+7 damage`). Empty slots
   read `empty`.
4. **Gold and quest:** gold, the active quest with progress
   (`Cull the Wolves 2/3`, or `none active`), and the number of completed quests.
5. **Session statistics:** total kills plus the top three enemy types by
   kills, deaths, damage dealt, damage taken, gold earned, time played
   (`mm:ss`, in-game time, so it follows the speed control).

**Data flow.** `Character.get_sheet_snapshot()` returns a plain dictionary of
everything above. A new pure class `SheetText` (`scripts/ui/sheet_text.gd`,
static functions, no node access) turns a snapshot into the BBCode string. The
sheet script (`scripts/ui/character_sheet.gd`) fetches a snapshot and calls
`SheetText.build()` when opened and every 0.5 s while visible (a `Timer`), so no
new signals are needed. If `GameState.character` is null the sheet shows
"No character".

**Snapshot keys:** `level`, `class_name`, `zone_name`, `xp`, `xp_next` (0 at max
level), `hp`, `max_hp`, `damage_min`, `damage_max`, `armor`, `crit_chance`,
`primary_stat` (`""` if none), `primary_value`, `primary_bonus_percent`,
`equipment` (slot -> item id), `gold`, `quest_text`, `quests_completed`,
`kills_total`, `kills_by_name` (Dictionary), `deaths`, `damage_dealt`,
`damage_taken`, `gold_earned`, `time_played_ms`.

## Session counters

Fields on `Character`: `kills_by_name: Dictionary`, `deaths: int`,
`damage_dealt_total: int`, `damage_taken_total: int`, `gold_earned: int`.
Increment sites:

| Counter | Where |
|---|---|
| kills | `Character.take_kill_credit(enemy_name, ...)` |
| deaths | `Character._die()` |
| gold earned | `Character._gain_gold(amount)` |
| damage taken | `Character.take_damage()`, after armor mitigation (actual HP lost) |
| damage dealt | `Enemy.take_damage(amount, attacker)`: when `attacker == GameState.character`, add `min(amount, hp before the hit)` (overkill is not counted). This one site covers auto-attacks, Heroic Strike and Rend ticks |

Time played is `Character.game_time_ms` (already accumulates scaled delta).

## Target frame

- A themed panel at top-center, under the quest tracker, hidden by default.
- Shows when `GameState.combat_target_changed(target)` reports a valid enemy and
  hides when it reports null or the enemy is freed.
- Contents: enemy name, an `Elite` tag when `guaranteed_drop_id != ""`, an HP
  bar with numbers (`12 / 18`), and its damage range (`2 - 4 damage`).
- The enemy's HP is read every frame from the enemy node (`hp`, `max_hp`), so no
  enemy or signal changes are needed. If the enemy node becomes invalid
  (`is_instance_valid` false) the frame hides.
- Script: `scripts/ui/target_frame.gd`. Its ProgressBar follows the same
  sizing workaround as the unit frame (`custom_minimum_size` plus reassigning
  `size` in `_ready()`) because Godot resets scene-declared ProgressBar sizes.

## Architecture / files

- `scripts/ui/sheet_text.gd` (new, pure): snapshot -> BBCode; also `format_time(ms)`.
- `scripts/ui/character_sheet.gd` (new): panel, toggle (`C` key via
  `_unhandled_input`, and the Sheet button), refresh timer.
- `scripts/ui/target_frame.gd` (new): target frame behavior.
- `scripts/entities/character.gd`: counters and `get_sheet_snapshot()`.
- `scripts/entities/enemy.gd`: damage-dealt counter in `take_damage`.
- `scenes/ui/SpectatorUI.tscn`: adds `CharacterSheet`, `TargetFrame` and a
  `SheetButton` in `SpeedControl`. All use the existing parchment theme.
- `README.md`: controls table gains `C` / Sheet button.

## Error handling

- Missing or unknown values in a snapshot fall back to sensible defaults
  (`0`, `"?"`, `"empty"`) so a partial snapshot never errors.
- The sheet and target frame tolerate `GameState.character` being null and
  freed enemy nodes.
- Toggling the sheet while typing is not a concern (no text inputs exist).

## Testing

New headless suite `tests/suite_sheet_text.gd`:

- `format_time` (`0` -> `00:00`, `65000` -> `01:05`, large values).
- `build()` with a full snapshot contains each expected line (level/class,
  stats, an equipment line with rarity color, quest text, session stats).
- Empty equipment renders `empty` for all slots.
- Max-level XP renders `MAX`.
- Top-three kills ordering (ties broken by name for determinism).
- A minimal/empty snapshot does not error and uses defaults.

Live check in the running game: `C` and the Sheet button toggle the sheet;
values update while playing (kills, gold, damage counters rise); the target
frame appears during fights with correct name/HP and hides afterwards; no
errors in the log; nothing overlaps the existing HUD at 1152x648.
