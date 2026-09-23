# HUD/UI Upgrade — Design

## Summary

Replace the completely unstyled spectator HUD (default-theme grey progress
bars, plain text labels, a bare `ItemList` log) with a themed, fantasy-styled
UI, and add four new pieces of at-a-glance information: equipment icons,
floating damage numbers, a health bar over the character's current combat
target, and a floating label above the character showing its current AI
action. Folded into the same pass: two small AI-behavior fixes surfaced by a
recent bug audit — the character's `wander`/`flee` movement has no boundary
and can drift outside the visible meadow, and rejected loot (a worse weapon/
armor than what's equipped) despawns with no log line explaining why. This
is primarily a **visual/UI-layer change** — no changes to `AIDecision`,
`CombatSystem`, or `LevelingSystem` logic — plus these two narrowly-scoped
behavior fixes. It builds on top of the already-shipped visual-art upgrade
(real sprites/animation) the same way that shipped on top of v1.

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
- Keep the character's `wander`/`flee` movement within the meadow's visible
  area instead of drifting past the tree-line border indefinitely.
- Log a line when a dropped weapon/armor is found but not equipped (because
  it's worse than what's already equipped), instead of silently discarding
  it.

## Non-Goals

- No minimap, no inventory management UI, no new item types or gameplay
  stats, no sound effects.
- No health bars over enemies that aren't the current combat target.
- No changes to `AIDecision`'s state-selection logic, `CombatSystem`, or
  `LevelingSystem` — the two behavior fixes below only touch *where the
  character is allowed to move* and *what gets logged on pickup*, not which
  FSM state it picks or how combat/leveling resolve.
- No inventory storage for rejected loot — it still despawns, it just logs
  why first.
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
- Neither `Character`, `Enemy`, nor `ThornfieldMeadow.tscn` has any
  boundary — no `CollisionShape2D` walls, no position clamp anywhere. The
  meadow's visible area is the `Background` rect, `(-400,-300)` to
  `(400,300)` (same bounds Task 7's tree-line border rings). `wander`
  picks a random offset with no bound; `flee` moves directly away from a
  hostile with no bound either. A sustained playtest observed the
  character drift to roughly `(-211, 530)`, well outside the tree line.
  Enemies never wander independently (they only chase toward the character
  or hold still), so they aren't a source of drift on their own.
- `_pickup_item()`'s weapon/armor branches call `LootTable.should_equip()`
  and only act (re-stat, log "Equipped ...", emit the equipment-changed
  signal) when it returns `true`; when `false`, nothing happens in that
  branch, and the unconditional `item.queue_free()` at the end of the
  function silently removes the item with no log entry at all.

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

### Wander/flee boundary

- `scripts/entities/character.gd` gets two new consts,
  `MEADOW_MIN := Vector2(-380, -280)` and `MEADOW_MAX := Vector2(380, 280)`
  — a small inset from the Background rect's `(-400,-300)`/`(400,300)` so
  the character doesn't visually clip into the tree-line border.
- The `"wander"` branch clamps its randomly-generated `wander_target` into
  that rect (`wander_target.clamp(MEADOW_MIN, MEADOW_MAX)` or equivalent),
  so new wander targets are never picked outside the meadow in the first
  place.
- As a general backstop that also covers `"flee"` (which has no target to
  clamp, just a direction), `_act()` clamps `global_position` into the same
  rect as its last step, after movement is resolved for the frame. This is
  a position clamp only — it doesn't change velocity or facing, so it
  doesn't interact with the animation/facing logic already at the end of
  `_act()`.
- Enemies are untouched — since they only ever move toward the character
  (never wander independently), keeping the character bounded keeps them
  bounded too.

### Rejected loot logging

- In `_pickup_item()`'s weapon and armor branches, add an `else` arm
  alongside the existing `if LootTable.should_equip(...)` check that logs
  `GameState.log_event("Found %s - current gear is better" % item_id)` (or
  similar wording) before falling through to the existing unconditional
  `item.queue_free()`. No new signal needed — this reuses the same
  `GameState.log_event()` the activity log already listens to for every
  other transition/pickup/equip line.

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
- Run the game at higher speed (2x/4x) for several minutes and confirm
  `global_position` never leaves `MEADOW_MIN`/`MEADOW_MAX`, including during
  sustained `flee` — the exact scenario the bug audit used to find the
  original drift.
- Force a worse-item pickup (e.g. via `game_eval`, matching the technique
  used elsewhere in this project) and confirm a log line appears explaining
  why it wasn't equipped, and that a better item still equips and logs as
  before.
- `game_get_errors` stays clean (known pre-existing background noise only)
  throughout.

## How We'll Know This Is Done

The HUD looks like a cohesive, fantasy-themed spectator UI instead of
default Godot placeholder controls; a spectator can see equipment as icons,
watch damage numbers pop during fights, see how a fight against the current
enemy is going via its health bar, and tell what the character is doing at
a glance from the floating action label. The character stays visible within
the meadow's tree line even during long flee/wander stretches at high game
speed, and the activity log explains every loot pickup — kept or discarded
— not just the ones that get equipped. None of this changes how the AI
actually decides what to do.
