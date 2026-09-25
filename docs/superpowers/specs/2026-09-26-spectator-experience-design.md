# Spectator Experience Pass - Design

Date: 2026-09-26

## Context

The game is feature-complete (five zones, loot, codex, party, balance pass),
but watching it is flat: fights are sprites trading small red numbers, boss
fights look like any other fight, and the camera only follows the character
at one fixed zoom. This pass makes the spectating itself better, in three
parts: **combat juice**, **boss events**, and an **auto-director camera**.

## Goals

- Hits are visible and satisfying: flash, knockback, death pop, numbers that
  scale with importance, shake on big hits.
- Boss encounters read as events: name banner, big health bar, slow-motion on
  the killing blow, a result banner.
- The camera frames the action by itself: smooth follow, boss framing, travel
  pull-out; the human can still take over.
- The logic that decides scales, shake, camera mode and slow-mo is pure and
  unit-tested; balance simulations are unaffected.

## Non-goals

- Sound effects, letterbox cinematics, settings menu, new art.
- Any change to combat balance, AI or enemy stats.

## Part 1: Combat juice

### Signal

`GameState` gains `signal hit_landed(target: Node2D, amount: int, is_crit: bool, on_character: bool)`
(`on_character` is true when the target is the spectated character). The
existing `damage_dealt` signal stays unchanged (audio and heals use it).

- `Enemy.take_damage(amount, attacker = null, is_crit = false)` emits it (after
  the damage is applied, before death handling).
- `Character.take_damage(amount, is_crit = false)` emits it with
  `on_character = true`.
- Callers that already know a crit (`Character._roll_damage` result, ability
  hits) pass `is_crit`; every other caller keeps working with the default.

### Pure helper: `SpectatorFx` (`scripts/systems/spectator_fx.gd`, static)

- `number_scale(amount, is_crit, is_boss_hit) -> float`: 1.0 normal; crit 1.5;
  boss hit 1.3; both 1.8; plus up to +0.3 for large amounts (amount >= 40).
- `number_color(is_heal, is_crit, on_character) -> Color`: heal green, crit
  gold, damage on the character orange-red, other damage white-red.
- `shake_strength(amount, is_crit, on_character, is_boss_hit, max_hp) -> float`
  in 0..1: 0 for small hits; crits, boss hits and hits worth >= 15% of the
  target's max HP produce 0.3..1.0, larger for bigger fractions.
- `should_slow_kill(is_boss, time_scale) -> bool`: true only for boss kills
  while the game is running (`time_scale > 0`).

### Visuals

- **Hit flash + knockback:** `HitFeedback` (`scripts/ui/hit_feedback.gd`)
  listens to `hit_landed`; for the target's `Sprite2D`/`AnimatedSprite2D`
  child it tweens `modulate` to white and back (0.12 s) and offsets the
  sprite's local `position` away from the attacker direction by up to 4 px and
  back. Only the sprite is touched, never the body position.
- **Death pop:** on enemy death a short-lived ghost (copy of the sprite
  texture/frame) scales to 1.4x and fades over 0.25 s.
- **Floating numbers:** `FloatingText` takes `scale`, `color`, `is_crit`;
  crits get a `!` suffix and a slightly longer, higher rise. `Main` builds
  damage numbers from `hit_landed` and keeps `damage_dealt` only for heals.
- **Shake:** `Camera2D` gets `add_shake(strength)` (trauma model: trauma decays
  over about 0.4 s, offset = trauma^2 x 10 px, plain random per frame).

## Part 2: Boss events

- `EnemyTable.is_boss(id) -> bool`: true when `guaranteed_drop` is non-empty.
  `Enemy` exposes `is_boss`.
- `BossEvents` (`scripts/ui/boss_events.gd`, on a `Control` in
  `SpectatorUI.tscn`) tracks the character's current combat target:
  - **Engaged:** the first time the character targets a given boss instance,
    show a banner "BOSS - <Name>" (fades after 2 s) and show a top-center
    boss health bar (name + HP text + bar), updated on `hit_landed` and hidden
    when the target changes to a non-boss or dies.
  - **Result banner:** boss dies to the character or the party -> "Victory - <Name>";
    the character dies while engaged -> "Defeated by <Name>"; the character
    starts fleeing from it -> "Fled from <Name>". Each fades in 2.5 s.
- **Slow-mo:** on a boss kill, if `SpectatorFx.should_slow_kill`, set
  `Engine.time_scale = 0.25` for 0.6 real seconds (timer with
  `ignore_time_scale`), then restore the value the speed buttons last set.
  `SpeedControl` gains `user_time_scale` so the restore is exact and the Pause
  button is never overridden (a pause during slow-mo wins).
- **Signals:** `GameState` gains `boss_engaged(enemy)`, `boss_event(kind: String, name: String)`
  (`kind` in `victory`, `defeated`, `fled`). `Character` emits engaged from
  target selection, `fled` when the flee state starts against a boss target,
  `defeated` on death with a boss target; `Enemy._die` emits `victory`.

## Part 3: Auto-director camera

`camera_controller.gd` becomes a director.

- **Pure decision:** `CameraDirector.decide(state) -> Dictionary` (static,
  `scripts/systems/camera_director.gd`). Input: `{mode_enabled, manual, in_boss_fight,
  travelling, boss_distance}`. Output: `{zoom, focus: "character"|"fight"}`:
  - manual or director off -> keep the current zoom, follow only as before;
  - boss fight -> zoom 1.5, focus on the midpoint between character and boss
    (clamped so the character stays within about 40% of screen);
  - travelling between zones -> zoom 0.8, focus on the character;
  - otherwise zoom 1.0, focus on the character.
- **Smoothing:** position follows with exponential smoothing
  (`1 - exp(-6 * delta)`), zoom lerps at about 3/s. Speed changes do not alter
  the feel because smoothing uses `delta`.
- **Manual override:** dragging or scrolling sets `manual = true` (director
  paused; the camera stays where the user puts it and the existing behavior
  applies). `Recenter` clears `manual` and re-enables following. A new
  **Director** toggle button in `SpeedControl` enables/disables the director
  (on by default); when off, the camera behaves exactly like today.
- **Travelling** is the character's existing zone-trip state (a flag already
  exists on the character; the plan will pin the exact field).

## Safety for simulations

`GameState.fx_enabled` (default true). The sim harness sets it false. When
false: no slow-mo, no shake, no camera zoom changes, no hit flash or death
pop. Banners and the boss bar are UI-only and stay harmless. Combat, AI and
balance numbers never read any of this, and the headless test runner has no
scene tree UI, so it is unaffected.

## Files

- New: `scripts/systems/spectator_fx.gd`, `scripts/systems/camera_director.gd`,
  `scripts/ui/hit_feedback.gd`, `scripts/ui/boss_events.gd`,
  `tests/suite_spectator_fx.gd`, `tests/suite_camera_director.gd`.
- Modified: `scripts/autoload/game_state.gd` (signals, `fx_enabled`),
  `scripts/entities/enemy.gd`, `scripts/entities/character.gd`,
  `scripts/systems/enemy_table.gd` (`is_boss`), `scripts/ui/camera_controller.gd`,
  `scripts/ui/floating_text.gd`, `scripts/main.gd`, `scripts/ui/speed_control.gd`,
  `scenes/ui/SpectatorUI.tscn`, `scenes/ui/FloatingText.tscn` (if needed),
  `tests/run_tests.gd`, `tests/suite_enemy_table.gd`, `tests/sim/sim_run.gd`,
  `README.md`.

## Testing

Headless suites (each ends with `t.done()`):

- `suite_spectator_fx`: scale table (normal, crit, boss, both, large amount),
  colors, shake (small hit 0, crit > 0, boss hit > 0, 15% rule, monotonic in
  amount, always within 0..1), `should_slow_kill` (boss + running, boss +
  paused, non-boss).
- `suite_camera_director`: each mode's output (manual, off, boss, travel,
  default), boss framing focus lies between the two positions.
- `suite_enemy_table` (extended): `is_boss` true exactly for the five
  enemies with a guaranteed drop, false for the rest.

Live check in the running game (MCP): numbers scale on crits, flash and
knockback visible, boss banner and bar appear on a boss target, slow-mo on the
kill and speed restores, camera zooms on boss and out during travel, drag
pauses the director and Recenter resumes it, Director toggle works, no errors;
one short sim run confirms unchanged results with `fx_enabled = false`.
