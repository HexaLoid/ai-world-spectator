# HUD/UI Upgrade — Design

## Summary

Replace the completely unstyled spectator HUD (default-theme grey progress
bars, plain text labels, a bare `ItemList` log) with a themed, fantasy-styled
UI, and add four new pieces of at-a-glance information: equipment icons,
floating damage numbers, a health bar over the character's current combat
target, and a floating label above the character showing its current AI
action. This is a **visual/UI-layer-only** change — no changes to
`AIDecision`, `CombatSystem`, `LevelingSystem`, or `LootTable` logic, and no
new gameplay mechanics. It builds on top of the already-shipped visual-art
upgrade (real sprites/animation) the same way that shipped on top of v1.

## Goals

- Give the existing HUD (unit frame, activity log, speed controls) a
  cohesive fantasy/parchment visual theme instead of default Godot styling.
- Show weapon/armor as small icons instead of only plain text.
- Show floating damage numbers when a hit lands, for both the character and
  enemies.
- Show a health bar above whichever enemy the character is currently
  fighting (and only that one).
- Show a small floating label above the character's head reflecting its
  current AI state ("Fighting", "Fleeing", "Resting", etc.), independent of
  the activity log.

## Non-Goals

- No minimap, no inventory management UI, no new item types or gameplay
  stats, no sound effects.
- No health bars over enemies that aren't the current combat target.
- No changes to FSM/AI decision-making, combat resolution, leveling, or loot
  logic — this is UI presentation and light signal-wiring only.
- No sourced texture pack for panels/buttons (see Architecture) — the
  fantasy look comes from a procedural Godot `Theme`, not new panel art.

## Current State

- `scenes/ui/SpectatorUI.tscn` / `scripts/ui/unit_frame.gd`: a `Control`
  with a default-theme `ProgressBar` (HP), a `Label` ("Level N"), a second
  default `ProgressBar` (XP), and two plain `Label`s ("Weapon: X",
  "Armor: Y"). No panel background, no color coding, no icons.
- `scripts/ui/activity_log.gd`: a bare default-theme `ItemList`.
- `scripts/ui/speed_control.gd`: default-theme `Button`s in an
  `HBoxContainer` (Pause/1x/2x/4x/Recenter).
- `scripts/systems/loot_table.gd`'s `ITEMS` dict has 4 entries:
  `rusty_sword`/`iron_sword` (weapons), `leather_armor` (armor),
  `health_potion` (consumable) — no icon field today.
- `scripts/entities/character.gd` already computes a `combat_hostile`
  reference locally inside `_act()` when in the `"combat"` state (added by
  the recent combat-facing fix) — this is the natural hook for "current
  combat target."

## Architecture

### New files

```
/assets/theme
  spectator_theme.tres        Godot Theme resource: StyleBoxFlat panels/
                               buttons/progress-bar fills, fonts, colors
/assets/icons
  sword_icon.png (+.import)   sourced from a free LPC-compatible/CC icon
  armor_icon.png (+.import)   pack (same OpenGameArt/LPC ecosystem already
  potion_icon.png (+.import)  used for sprites/tiles), licensed and
                               credited the same way as existing assets
/scenes/ui
  FloatingText.tscn           Label + AnimationPlayer, rises and fades over
                               ~0.6s, frees itself when done
  EnemyHealthBar.tscn         a ProgressBar sized/positioned to sit just
                               above an enemy sprite, hidden by default
/scripts/ui
  floating_text.gd            sets the label text/color and starts the
                               rise-and-fade animation
  enemy_health_bar.gd         listens for its owner enemy's HP changing and
                               for GameState's combat-target signal to
                               decide visibility
```

### Modified files

- `scenes/ui/SpectatorUI.tscn` — apply `spectator_theme.tres` as the
  CanvasLayer's theme; add a `TextureRect` next to each of the
  Weapon/Armor labels in `UnitFrame`.
- `scripts/ui/unit_frame.gd` — `_on_equipment_changed` sets the new
  `TextureRect.texture` from `LootTable.ITEMS[item_id]["icon"]` (loaded via
  `load()`, same pattern used elsewhere in this codebase) alongside the
  existing text.
- `scripts/systems/loot_table.gd` — add an `"icon": "res://assets/icons/..."`
  key to each `ITEMS` entry.
- `scripts/autoload/game_state.gd` — add two new signals:
  `damage_dealt(position: Vector2, amount: int, is_heal: bool)` and
  `combat_target_changed(target: Node2D)`. This keeps the same decoupling
  rule the v1 design already established: gameplay code only emits
  `GameState` signals, UI only listens to them, never the other way around.
- `scripts/entities/character.gd` — in `take_damage()`, after applying
  `amount`, emit `GameState.damage_dealt(global_position, amount, false)`;
  in `_pickup_item()`'s consumable-heal branch, emit
  `GameState.damage_dealt(global_position, healed_amount, true)`. In `_act()`,
  emit `GameState.combat_target_changed(combat_hostile)` whenever
  `combat_hostile` changes from the previous frame's value (only on change,
  not every frame). Add a child `Label` (`ActionLabel`) positioned above the
  sprite (e.g. `position = Vector2(0, -40)`, as a sibling of
  `AnimatedSprite2D` so it isn't affected by the sprite's dynamic scale);
  update its text from a small `current_state -> display string` lookup
  each time `current_state` changes (same place that already logs the
  transition reason).
- `scripts/entities/enemy.gd` — in `take_damage()`, after applying
  `amount`, emit `GameState.damage_dealt(global_position, amount, false)`.
  Add an `EnemyHealthBar` instance as a child (or instantiate/attach one
  lazily) that listens to `GameState.combat_target_changed` and shows
  itself only when the signal's `target` is this enemy, hides otherwise;
  its `value`/`max_value` track this enemy's own `hp`/`max_hp`.
- A small always-on listener (e.g. a script on `SpectatorUI` or a new
  minimal autoload-adjacent helper) subscribes to `GameState.damage_dealt`
  and instantiates `FloatingText.tscn` at the given world position, adding
  it to `get_tree().current_scene` — this keeps `FloatingText` spawning
  itself out of gameplay code entirely, consistent with the Non-Goals.

### Data flow summary

```
character.gd/enemy.gd take_damage()
  -> GameState.damage_dealt(pos, amount, is_heal)
     -> UI listener spawns FloatingText.tscn at pos

character.gd _act() combat_hostile changes
  -> GameState.combat_target_changed(target)
     -> every EnemyHealthBar listens, shows/hides itself based on
        whether it belongs to `target`

character.gd current_state changes (existing log_event call site)
  -> ActionLabel.text updated directly (no signal needed, same node)

LootTable.ITEMS[id]["icon"]
  -> unit_frame.gd _on_equipment_changed loads it into a TextureRect
     (existing character_equipment_changed signal, no new signal needed)
```

## Error Handling / Edge Cases

- `FloatingText` instances free themselves (`queue_free()`) when their
  animation completes — same instantiate-then-self-free pattern already
  used by `ItemPickup`, no manual cleanup needed, no leak risk.
- `EnemyHealthBar` is a child of its enemy, so if the enemy is defeated and
  `queue_free()`'d, the bar is destroyed with it automatically — no
  dangling reference to the dead enemy anywhere else.
- If `combat_hostile` becomes `null` (character leaves combat, or the
  target dies), `combat_target_changed(null)` fires and every
  `EnemyHealthBar` hides itself — no bar left visible on a target that's no
  longer being fought.
- `ActionLabel`'s state-to-text lookup has a default fallback (capitalize
  the raw state string) for any state it doesn't have a friendly name for,
  so it's never blank even if a new FSM state is added later.
- Icon `TextureRect`s with a `null` texture (e.g. an icon fails to load)
  just render as empty space — Godot handles this natively, no crash.

## Testing / Validation

Same manual/in-engine approach used throughout this project (no automated
test suite — this is a simulation/spectator game, verified primarily by
observation, per the original v1 design's own testing section):

- Run the game and confirm the HUD renders with the new parchment theme
  (panel backgrounds, gold borders, styled bars/buttons) instead of default
  grey Godot controls.
- Confirm equipment icons appear and update correctly on pickup/equip,
  matching the item actually equipped.
- Confirm floating damage numbers appear at the right position and fade out
  correctly on both character and enemy hits, and that healing (potion use)
  is visually distinguishable from damage (e.g. color).
- Confirm the enemy health bar appears only above the character's current
  combat target, tracks that enemy's HP as it takes damage, and disappears
  when the fight ends (target defeated or character disengages) — and that
  it never appears over an enemy that isn't the current target.
- Confirm the action-indicator label updates correctly as the character
  cycles through wander/chase/combat/flee/loot/rest, staying legible and
  correctly positioned as the character moves/faces different directions.
- `game_get_errors` stays clean (known pre-existing background noise only)
  throughout.

## How We'll Know This Is Done

The HUD looks like a cohesive, fantasy-themed spectator UI instead of
default Godot placeholder controls; a spectator can see equipment as icons,
watch damage numbers pop during fights, see how a fight against the current
enemy is going via its health bar, and tell what the character is doing at
a glance from the floating action label — all without any change to how the
AI actually plays the game.
