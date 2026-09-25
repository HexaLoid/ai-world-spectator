# Spectator Experience Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make watching the AI play better: combat juice (flash, knockback, death pop, scaled numbers, shake), boss events (banner, boss bar, slow-mo kill, result banner) and an auto-director camera.

**Architecture:** Pure static helpers (`SpectatorFx`, `CameraDirector`, `EnemyTable.is_boss`) hold every decision and are unit-tested headless. New `GameState` signals (`hit_landed`, `enemy_died`, `boss_event`) carry the events; three small scene-side scripts (`HitFeedback`, `BossEvents`, the upgraded `camera_controller.gd`) consume them. They are attached from `main.gd` in code, so no `.tscn` edits are needed. `GameState.fx_enabled` (false in the sim harness) turns all visual side effects off so balance runs are unchanged.

**Tech Stack:** Godot 4.7 (mono) GDScript, headless test runner `tests/run_tests.gd`.

Spec: `docs/superpowers/specs/2026-09-26-spectator-experience-design.md`.

**Conventions for every task**

- Run in a worktree: `git worktree add .claude/worktrees/spectator-experience -b spectator-experience` from `main`. In a fresh worktree run the headless editor import twice first: `"$GODOT" --headless --path . --editor --quit` (twice).
- `GODOT="C:/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"`.
- Test command (used everywhere below as "run the tests"):
  `"$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|checks"`
  Baseline before this plan: `12047 checks, 0 failures`.
- Every suite's `run(t)` ends with `t.done()`. Register new suites in `SUITES` in `tests/run_tests.gd`.
- The working tree uses CRLF, commits use LF. Edit files with the Edit tool (it preserves endings); when using Python use `open(f, newline='')`.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- GDScript typing quirk: calling a method that is not on the declared type (`Node2D`) is a parse error. Use untyped `var x = ...` or `x.call("name")` / `x.get("prop")` for `Enemy`-only members.

---

### Task 1: `SpectatorFx` pure helper

**Files:**
- Create: `scripts/systems/spectator_fx.gd`
- Create: `tests/suite_spectator_fx.gd`
- Modify: `tests/run_tests.gd` (register suite)

- [ ] **Step 1: Write the failing test**

Create `tests/suite_spectator_fx.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	# number_scale
	t.check_near(SpectatorFx.number_scale(5, false, false), 1.0, "normal hit scale")
	t.check_near(SpectatorFx.number_scale(5, true, false), 1.5, "crit scale")
	t.check_near(SpectatorFx.number_scale(5, false, true), 1.3, "boss hit scale")
	t.check_near(SpectatorFx.number_scale(5, true, true), 1.8, "crit boss scale")
	t.check_near(SpectatorFx.number_scale(40, false, false), 1.3, "large hit bonus")
	t.check_near(SpectatorFx.number_scale(60, true, true), 2.1, "everything stacks")

	# number_color
	t.check_eq(SpectatorFx.number_color(true, false, false), SpectatorFx.HEAL_COLOR, "heal is green")
	t.check_eq(SpectatorFx.number_color(false, true, false), SpectatorFx.CRIT_COLOR, "crit is gold")
	t.check_eq(SpectatorFx.number_color(false, false, true), SpectatorFx.CHARACTER_HIT_COLOR, "damage on the character")
	t.check_eq(SpectatorFx.number_color(false, false, false), SpectatorFx.ENEMY_HIT_COLOR, "damage on others")
	t.check_eq(SpectatorFx.number_color(true, true, true), SpectatorFx.HEAL_COLOR, "heal wins")

	# shake_strength
	t.check_near(SpectatorFx.shake_strength(3, false, false, false, 60), 0.0, "small hit: no shake")
	t.check(SpectatorFx.shake_strength(3, true, false, false, 60) > 0.0, "crit shakes")
	t.check(SpectatorFx.shake_strength(3, false, false, true, 60) > 0.0, "boss hit shakes")
	t.check(SpectatorFx.shake_strength(10, false, false, false, 60) > 0.0, "17% of max HP shakes")
	t.check_near(SpectatorFx.shake_strength(8, false, false, false, 60), 0.0, "13% of max HP does not")
	var previous := 0.0
	for amount in range(1, 101):
		var s := SpectatorFx.shake_strength(amount, false, false, false, 60)
		t.check(s >= previous, "shake never decreases with damage (amount %d)" % amount)
		previous = s
	var in_range := true
	for amount in [0, 1, 20, 100, 1000]:
		for max_hp in [0, 1, 60, 1300]:
			for flags in range(8):
				var s := SpectatorFx.shake_strength(amount, flags & 1 != 0, flags & 2 != 0, flags & 4 != 0, max_hp)
				if s < 0.0 or s > 1.0:
					in_range = false
	t.check(in_range, "shake always within 0..1 (including max_hp 0)")

	# should_slow_kill
	t.check(SpectatorFx.should_slow_kill(true, 1.0), "boss kill while running")
	t.check(SpectatorFx.should_slow_kill(true, 4.0), "boss kill at 4x")
	t.check(not SpectatorFx.should_slow_kill(true, 0.0), "no slow-mo while paused")
	t.check(not SpectatorFx.should_slow_kill(false, 1.0), "no slow-mo for non-boss")
	t.done()
```

Register it: in `tests/run_tests.gd` add `"res://tests/suite_spectator_fx.gd",` after the `suite_ai_decision.gd` line.

- [ ] **Step 2: Run the tests to verify they fail**

Run the tests. Expected: `FAIL: suite failed to load` or a SCRIPT ERROR for `SpectatorFx` (class not defined).

- [ ] **Step 3: Write the implementation**

Create `scripts/systems/spectator_fx.gd`:

```gdscript
class_name SpectatorFx
extends RefCounted

## Pure decisions for the spectator visual effects (no nodes): how big a damage
## number is, what color it is, how hard the camera shakes, and when a kill
## gets slow motion. Consumed by FloatingText/Main, the camera and BossEvents.

const LARGE_HIT := 40
## A hit worth at least this fraction of the target's max HP shakes the camera.
const HEAVY_FRACTION := 0.15
const SLOW_SCALE := 0.25
const SLOW_DURATION_S := 0.6

const HEAL_COLOR := Color(0.3, 0.9, 0.3, 1.0)
const CRIT_COLOR := Color(1.0, 0.82, 0.2, 1.0)
const CHARACTER_HIT_COLOR := Color(1.0, 0.45, 0.15, 1.0)
const ENEMY_HIT_COLOR := Color(1.0, 0.75, 0.72, 1.0)

static func number_scale(amount: int, is_crit: bool, is_boss_hit: bool) -> float:
	var s := 1.0
	if is_crit and is_boss_hit:
		s = 1.8
	elif is_crit:
		s = 1.5
	elif is_boss_hit:
		s = 1.3
	if amount >= LARGE_HIT:
		s += 0.3
	return s

static func number_color(is_heal: bool, is_crit: bool, on_character: bool) -> Color:
	if is_heal:
		return HEAL_COLOR
	if is_crit:
		return CRIT_COLOR
	if on_character:
		return CHARACTER_HIT_COLOR
	return ENEMY_HIT_COLOR

## 0..1. Zero for ordinary hits; crits, boss hits and hits worth 15%+ of the
## target's max HP shake the camera, more for bigger fractions.
static func shake_strength(amount: int, is_crit: bool, on_character: bool, is_boss_hit: bool, max_hp: int) -> float:
	var fraction := float(maxi(amount, 0)) / float(maxi(max_hp, 1))
	var s := 0.0
	if is_boss_hit:
		s = 0.25
	if is_crit:
		s = maxf(s, 0.35)
	if fraction >= HEAVY_FRACTION:
		s = maxf(s, 0.3 + minf(fraction, 0.6))
	if s > 0.0 and on_character:
		s += 0.1
	return clampf(s, 0.0, 1.0)

static func should_slow_kill(is_boss: bool, time_scale: float) -> bool:
	return is_boss and time_scale > 0.0
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the tests. Expected: `0 failures`, no SCRIPT ERROR.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/spectator_fx.gd tests/suite_spectator_fx.gd tests/run_tests.gd
git commit -m "Add SpectatorFx pure helper for number scale, color, shake and slow-mo

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `CameraDirector` pure helper

**Files:**
- Create: `scripts/systems/camera_director.gd`
- Create: `tests/suite_camera_director.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/suite_camera_director.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	var idle := CameraDirector.decide({"enabled": true, "manual": false, "in_boss_fight": false, "travelling": false, "boss_distance": 0.0})
	t.check(idle["active"], "idle: director active")
	t.check_near(idle["zoom"], 1.0, "idle zoom")
	t.check_near(idle["focus_weight"], 0.0, "idle: focus on the character")

	var boss := CameraDirector.decide({"enabled": true, "manual": false, "in_boss_fight": true, "travelling": false, "boss_distance": 100.0})
	t.check_near(boss["zoom"], 1.5, "boss zoom")
	t.check_near(boss["focus_weight"], 0.5, "close boss: midpoint")
	var far := CameraDirector.decide({"enabled": true, "manual": false, "in_boss_fight": true, "travelling": false, "boss_distance": 400.0})
	t.check_near(far["focus_weight"], 0.3, "far boss: character stays within 120 px of the focus")
	var overlap := CameraDirector.decide({"enabled": true, "manual": false, "in_boss_fight": true, "travelling": false, "boss_distance": 0.0})
	t.check_near(overlap["focus_weight"], 0.5, "boss at distance 0 does not divide by zero")

	var travel := CameraDirector.decide({"enabled": true, "manual": false, "in_boss_fight": false, "travelling": true, "boss_distance": 0.0})
	t.check_near(travel["zoom"], 0.8, "travel pull-out")
	t.check_near(travel["focus_weight"], 0.0, "travel: focus on the character")

	var both := CameraDirector.decide({"enabled": true, "manual": false, "in_boss_fight": true, "travelling": true, "boss_distance": 100.0})
	t.check_near(both["zoom"], 1.5, "boss framing wins over travel")

	var manual := CameraDirector.decide({"enabled": true, "manual": true, "in_boss_fight": true, "travelling": false, "boss_distance": 100.0})
	t.check(not manual["active"], "manual override pauses the director")
	var off := CameraDirector.decide({"enabled": false, "manual": false, "in_boss_fight": true, "travelling": false, "boss_distance": 100.0})
	t.check(not off["active"], "director toggled off")
	var defaults := CameraDirector.decide({})
	t.check(defaults["active"], "empty state: defaults to active")

	var in_range := true
	for dist in [0.0, 1.0, 50.0, 240.0, 500.0, 5000.0]:
		var w: float = CameraDirector.decide({"in_boss_fight": true, "boss_distance": dist})["focus_weight"]
		if w < 0.0 or w > 0.5:
			in_range = false
	t.check(in_range, "focus weight always within 0..0.5")
	t.done()
```

Register `"res://tests/suite_camera_director.gd",` in `tests/run_tests.gd` after the spectator suite.

- [ ] **Step 2: Run the tests to verify they fail**

Run the tests. Expected: SCRIPT ERROR / suite failed for `CameraDirector`.

- [ ] **Step 3: Write the implementation**

Create `scripts/systems/camera_director.gd`:

```gdscript
class_name CameraDirector
extends RefCounted

## Pure camera framing decision. `state` keys (all optional): enabled (bool,
## default true), manual (bool: the human took over), in_boss_fight (bool),
## travelling (bool), boss_distance (float px between character and boss).
## Returns {"active": bool, "zoom": float, "focus_weight": float}; the camera
## focuses on lerp(character, boss, focus_weight) and only applies `zoom`
## while `active`.

const DEFAULT_ZOOM := 1.0
const BOSS_ZOOM := 1.5
const TRAVEL_ZOOM := 0.8
## The character never sits further than this (world px) from the focus.
const MAX_OFFSET_PX := 120.0

static func decide(state: Dictionary) -> Dictionary:
	var active: bool = bool(state.get("enabled", true)) and not bool(state.get("manual", false))
	var zoom := DEFAULT_ZOOM
	var weight := 0.0
	if bool(state.get("in_boss_fight", false)):
		zoom = BOSS_ZOOM
		var dist := float(state.get("boss_distance", 0.0))
		weight = 0.5 if dist <= 0.0 else minf(0.5, MAX_OFFSET_PX / dist)
	elif bool(state.get("travelling", false)):
		zoom = TRAVEL_ZOOM
	return {"active": active, "zoom": zoom, "focus_weight": weight}
```

- [ ] **Step 4: Run the tests to verify they pass**

Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/camera_director.gd tests/suite_camera_director.gd tests/run_tests.gd
git commit -m "Add CameraDirector pure framing helper

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: `EnemyTable.is_boss` and `Enemy.is_boss()`

**Files:**
- Modify: `scripts/systems/enemy_table.gd` (after `get_def`, line ~87)
- Modify: `scripts/entities/enemy.gd` (after `_ready`)
- Modify: `tests/suite_enemy_table.gd` (before the final `t.done()`)

- [ ] **Step 1: Write the failing test**

In `tests/suite_enemy_table.gd`, before the final `t.done()` add:

```gdscript
	# is_boss: exactly the enemies with a guaranteed drop
	var bosses: Array = []
	for id in EnemyTable.ENEMIES.keys():
		var has_drop: bool = String(EnemyTable.ENEMIES[id].get("guaranteed_drop", "")) != ""
		t.check_eq(EnemyTable.is_boss(id), has_drop, "is_boss matches guaranteed_drop for %s" % id)
		if has_drop:
			bosses.append(id)
	bosses.sort()
	t.check_eq(bosses, ["bandit_captain", "crypt_lord", "frostpeak_warlord", "mire_tyrant", "raider_captain"], "the five bosses")
	t.check(not EnemyTable.is_boss("nope"), "unknown id is not a boss")
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: SCRIPT ERROR (`is_boss` not found) / suite ended early.

- [ ] **Step 3: Implement**

In `scripts/systems/enemy_table.gd`, after `get_def`:

```gdscript
## Bosses and elites are the enemies with a guaranteed drop.
static func is_boss(id: String) -> bool:
	return String(get_def(id).get("guaranteed_drop", "")) != ""
```

In `scripts/entities/enemy.gd`, after `_ready()`:

```gdscript
func is_boss() -> bool:
	return guaranteed_drop_id != ""
```

- [ ] **Step 4: Run the tests to verify they pass**

Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/enemy_table.gd scripts/entities/enemy.gd tests/suite_enemy_table.gd
git commit -m "Add EnemyTable.is_boss and Enemy.is_boss

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Signals, `fx_enabled`, and event emission

**Files:**
- Modify: `scripts/autoload/game_state.gd` (after the `codex_changed` signal, line ~62)
- Modify: `scripts/entities/enemy.gd` (`take_damage`, `_die`)
- Modify: `scripts/entities/character.gd` (`take_damage`, `_die`, `_update_combat_target`, two `hostile.take_damage(...)` calls)
- Modify: `scripts/entities/simulated_player.gd` (`take_damage`)
- Modify: `tests/sim/sim_run.gd` (`_ready`)

This task has no unit test (it is node wiring); it is verified by the test suite staying green, the sim regression in Task 8 and the live check.

- [ ] **Step 1: Add the signals and flag to `GameState`**

After the `codex_changed` signal (and its doc comment), add:

```gdscript
## A hit landed on `target` (an Enemy, the spectated Character or an ally).
## `on_character` is true when the target is the spectated character.
signal hit_landed(target: Node2D, amount: int, is_crit: bool, on_character: bool)

## An enemy is dying; emitted before it is freed so effects can copy its sprite.
signal enemy_died(enemy: Node2D)

## A boss moment near the character. `kind` is "victory", "defeated" or "fled".
signal boss_event(kind: String, boss_name: String)

## The speed the human last chose (0 = paused); slow-motion restores to this.
var user_time_scale: float = 1.0

## Visual effects (flash, shake, slow-mo, camera zoom). The balance sim turns
## this off so its results never depend on presentation.
var fx_enabled: bool = true
```

- [ ] **Step 2: Emit from `Enemy`**

In `scripts/entities/enemy.gd`:

Add a constant near the other consts: `const BOSS_EVENT_RANGE := 500.0`.

Change the signature and emit after `damage_dealt`:

```gdscript
func take_damage(amount: int, attacker: Node2D = null, is_crit: bool = false) -> void:
	if is_dead:
		return
	if attacker != null:
		last_attacker = attacker
	# (existing damage bookkeeping unchanged)
	if attacker != null and attacker == GameState.character:
		attacker.damage_dealt_total += mini(amount, hp)
	hp = max(0, hp - amount)
	health_bar.value = hp
	GameState.emit_signal("damage_dealt", global_position, amount, false)
	GameState.emit_signal("hit_landed", self, amount, is_crit, false)
	if hp <= 0:
		_die()
```

At the start of `_die()`, right after `is_dead = true`:

```gdscript
	GameState.emit_signal("enemy_died", self)
	if is_boss():
		var c = GameState.character
		if c != null and is_instance_valid(c) and c.global_position.distance_to(global_position) < BOSS_EVENT_RANGE:
			GameState.emit_signal("boss_event", "victory", enemy_name)
```

- [ ] **Step 3: Emit from `Character`**

In `scripts/entities/character.gd`:

1. `take_damage(amount: int)` becomes `take_damage(amount: int, is_crit: bool = false)`; after the `damage_dealt` emit add `GameState.emit_signal("hit_landed", self, amount, is_crit, true)`.
2. In `_attack_nearest_hostile`: `hostile.take_damage(roll["damage"], self)` becomes `hostile.take_damage(roll["damage"], self, roll["is_crit"])`.
3. In `_use_melee_hit`: same change (`hostile.take_damage(roll["damage"], self, roll["is_crit"])`).
4. In `_die()`, before `_update_combat_target(null)`:

```gdscript
	var foe = last_combat_target
	if is_instance_valid(foe) and foe.is_boss():
		GameState.emit_signal("boss_event", "defeated", foe.enemy_name)
```

5. In `_update_combat_target`, capture the previous target and emit "fled":

```gdscript
func _update_combat_target(combat_hostile: Node2D) -> void:
	if combat_hostile != last_combat_target:
		var previous = last_combat_target
		last_combat_target = combat_hostile
		GameState.emit_signal("combat_target_changed", combat_hostile)
		if not is_instance_valid(combat_hostile) and current_state == "flee" \
				and is_instance_valid(previous) and previous.is_boss():
			GameState.emit_signal("boss_event", "fled", previous.enemy_name)
		if combat_hostile != null and is_instance_valid(combat_hostile):
			for enemy_id in EnemyTable.ids_named(combat_hostile.enemy_name):
				GameState.discover("enemy", enemy_id)
```

(The `_die()` sequence in step 4 runs before `_update_combat_target(null)`; the character is not in state "flee" at that point unless it was fleeing, so a death is reported as "defeated" only.)

- [ ] **Step 4: Emit from `SimulatedPlayer`**

In `scripts/entities/simulated_player.gd`, in `take_damage`, after the `damage_dealt` emit add:

```gdscript
	GameState.emit_signal("hit_landed", self, amount, false, false)
```

- [ ] **Step 5: Turn effects off in the sim**

In `tests/sim/sim_run.gd` `_ready()`, first line of the function body:

```gdscript
	GameState.fx_enabled = false
```

- [ ] **Step 6: Run the tests**

Run the tests. Expected: `0 failures`, no SCRIPT ERROR (this also confirms the scripts parse).

- [ ] **Step 7: Commit**

```bash
git add scripts tests/sim/sim_run.gd
git commit -m "Emit hit_landed, enemy_died and boss_event; add fx_enabled

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: `HitFeedback` and scaled floating numbers

**Files:**
- Create: `scripts/ui/hit_feedback.gd`
- Modify: `scripts/ui/floating_text.gd`
- Modify: `scripts/main.gd`

- [ ] **Step 1: Create `scripts/ui/hit_feedback.gd`**

```gdscript
class_name HitFeedback
extends Node2D

## Visual reaction to hits: the target's sprite flashes white and is nudged
## away from the fight, and a dying enemy leaves a short "pop" ghost. Only the
## sprite child is touched (never the body's position), so AI and physics are
## unaffected. Does nothing while GameState.fx_enabled is false.

const FLASH_S := 0.12
const KNOCK_PX := 4.0
const POP_S := 0.25
const POP_SCALE := 1.4
const FLASH_COLOR := Color(2.2, 2.2, 2.2, 1.0)

func _ready() -> void:
	GameState.hit_landed.connect(_on_hit_landed)
	GameState.enemy_died.connect(_on_enemy_died)

## True when a hit belongs to a boss fight: the target is a boss, or the
## spectated character is hit while fighting a boss.
static func is_boss_hit(target: Node, on_character: bool) -> bool:
	if not is_instance_valid(target):
		return false
	if on_character:
		var foe = target.get("last_combat_target")
		return is_instance_valid(foe) and foe.has_method("is_boss") and bool(foe.call("is_boss"))
	return target.has_method("is_boss") and bool(target.call("is_boss"))

func _on_hit_landed(target: Node2D, _amount: int, _is_crit: bool, on_character: bool) -> void:
	if not GameState.fx_enabled or not is_instance_valid(target):
		return
	var spr := target.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		return
	if not spr.has_meta("fx_base_modulate"):
		spr.set_meta("fx_base_modulate", spr.modulate)
		spr.set_meta("fx_base_position", spr.position)
	var base_modulate: Color = spr.get_meta("fx_base_modulate")
	var base_position: Vector2 = spr.get_meta("fx_base_position")
	var running = spr.get_meta("fx_tween", null)
	if running is Tween and running.is_valid():
		running.kill()
	spr.modulate = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, base_modulate.a)
	spr.position = base_position + _knock_direction(target, on_character) * KNOCK_PX
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(spr, "modulate", base_modulate, FLASH_S)
	tween.tween_property(spr, "position", base_position, FLASH_S * 1.5)
	spr.set_meta("fx_tween", tween)

func _knock_direction(target: Node2D, on_character: bool) -> Vector2:
	var from := Vector2.ZERO
	var c = GameState.character
	if not on_character and is_instance_valid(c) and c != target:
		from = c.global_position
	elif on_character:
		var foe = target.get("last_combat_target")
		if is_instance_valid(foe):
			from = foe.global_position
	var away := target.global_position - from
	if away.length() < 1.0:
		return Vector2.RIGHT
	return away.normalized()

func _on_enemy_died(enemy: Node2D) -> void:
	if not GameState.fx_enabled or not is_instance_valid(enemy):
		return
	var src := enemy.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if src == null or src.sprite_frames == null:
		return
	var texture := src.sprite_frames.get_frame_texture(src.animation, src.frame)
	if texture == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = texture
	ghost.flip_h = src.flip_h
	add_child(ghost)
	ghost.global_position = src.global_position
	ghost.global_scale = src.global_scale
	ghost.modulate = src.get_meta("fx_base_modulate", src.modulate)
	var tween := ghost.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ghost, "scale", ghost.scale * POP_SCALE, POP_S)
	tween.tween_property(ghost, "modulate:a", 0.0, POP_S)
	tween.finished.connect(ghost.queue_free)
```

- [ ] **Step 2: Scale and color the floating numbers**

Replace `scripts/ui/floating_text.gd` with:

```gdscript
extends Node2D

var amount: int = 0
var is_heal: bool = false
var is_crit: bool = false
var text_scale: float = 1.0
var text_color: Color = Color(0.95, 0.25, 0.2, 1.0)

@onready var label: Label = $Label

func _ready() -> void:
	var text := ("+%d" % amount) if is_heal else ("-%d" % amount)
	if is_crit:
		text += "!"
	label.text = text
	label.modulate = text_color
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2.ONE * text_scale
	var rise := 36.0 if is_crit else 24.0
	var duration := 0.85 if is_crit else 0.6
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - rise, duration)
	tween.tween_property(label, "modulate:a", 0.0, duration)
	tween.finished.connect(queue_free)
```

- [ ] **Step 3: Build numbers from `hit_landed` in `main.gd`**

Replace `scripts/main.gd` with:

```gdscript
extends Node2D

const FLOATING_TEXT_SCENE: PackedScene = preload("res://scenes/ui/FloatingText.tscn")

func _ready() -> void:
	GameState.damage_dealt.connect(_on_damage_dealt)
	GameState.hit_landed.connect(_on_hit_landed)
	add_child(HitFeedback.new())

# Heals still arrive through damage_dealt; damage numbers come from
# hit_landed, which knows about crits and boss fights.
func _on_damage_dealt(damage_position: Vector2, amount: int, is_heal: bool) -> void:
	if is_heal:
		_spawn_number(damage_position, amount, true, false, false, false)

func _on_hit_landed(target: Node2D, amount: int, is_crit: bool, on_character: bool) -> void:
	if not is_instance_valid(target):
		return
	_spawn_number(target.global_position, amount, false, is_crit, on_character, HitFeedback.is_boss_hit(target, on_character))

func _spawn_number(at: Vector2, amount: int, is_heal: bool, is_crit: bool, on_character: bool, is_boss_hit: bool) -> void:
	var floating_text := FLOATING_TEXT_SCENE.instantiate()
	floating_text.global_position = at
	floating_text.amount = amount
	floating_text.is_heal = is_heal
	floating_text.is_crit = is_crit
	floating_text.text_scale = SpectatorFx.number_scale(amount, is_crit, is_boss_hit)
	floating_text.text_color = SpectatorFx.number_color(is_heal, is_crit, on_character)
	add_child.call_deferred(floating_text)
```

Note: `main.gd` is the script of the `Main` node; the earlier `add_child` of floating text went to the same node, so numbers keep their world position.

- [ ] **Step 4: Verify parse and tests**

Run the tests (expected `0 failures`). Then a quick game boot check with the Godot MCP `run_project`, wait a few seconds, `get_debug_output`: no ERROR/SCRIPT ERROR lines from the new scripts. `stop_project`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/hit_feedback.gd scripts/ui/floating_text.gd scripts/main.gd
git commit -m "Add hit flash, knockback, death pop and scaled damage numbers

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Auto-director camera with shake

**Files:**
- Modify: `scripts/ui/camera_controller.gd`

- [ ] **Step 1: Replace `camera_controller.gd`**

```gdscript
extends Camera2D

const ZOOM_STEP := 0.1
const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.5
## Exponential smoothing rates (per second) for the directed camera.
const POS_SMOOTH := 6.0
const ZOOM_SMOOTH := 3.0
## Trauma lost per second; the shake offset is trauma^2 * SHAKE_MAX_PX.
const SHAKE_DECAY := 2.5
const SHAKE_MAX_PX := 14.0

var following := true
var dragging := false
var drag_start_mouse := Vector2.ZERO
var drag_start_camera := Vector2.ZERO
## The Director button toggles this; off = the camera behaves as it always did.
var director_enabled := true
## True once the human dragged or scrolled; pauses the director until Recenter.
var manual := false
var trauma := 0.0

func _ready() -> void:
	GameState.camera = self
	GameState.hit_landed.connect(_on_hit_landed)

func _process(delta: float) -> void:
	var character = GameState.character
	var have_character: bool = character != null and is_instance_valid(character)
	var boss = null
	if have_character:
		var foe = character.last_combat_target
		if is_instance_valid(foe) and foe.has_method("is_boss") and foe.is_boss() and not foe.is_dead:
			boss = foe
	var plan := CameraDirector.decide({
		"enabled": director_enabled,
		"manual": manual,
		"in_boss_fight": boss != null,
		"travelling": have_character and character.current_state == "travel",
		"boss_distance": character.global_position.distance_to(boss.global_position) if boss != null else 0.0,
	})
	var directed: bool = plan["active"] and GameState.fx_enabled
	if following and have_character:
		var target_position: Vector2 = character.global_position
		if directed:
			if boss != null:
				target_position = target_position.lerp(boss.global_position, plan["focus_weight"])
			global_position = global_position.lerp(target_position, 1.0 - exp(-POS_SMOOTH * delta))
		else:
			global_position = target_position
	if directed:
		var wanted: Vector2 = (Vector2.ONE * float(plan["zoom"])).clamp(Vector2.ONE * MIN_ZOOM, Vector2.ONE * MAX_ZOOM)
		zoom = zoom.lerp(wanted, 1.0 - exp(-ZOOM_SMOOTH * delta))
	trauma = maxf(0.0, trauma - SHAKE_DECAY * delta)
	if GameState.fx_enabled and trauma > 0.0:
		offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * trauma * trauma * SHAKE_MAX_PX
	else:
		offset = Vector2.ZERO

func add_shake(strength: float) -> void:
	trauma = minf(1.0, trauma + strength)

func _on_hit_landed(target: Node2D, amount: int, is_crit: bool, on_character: bool) -> void:
	if not GameState.fx_enabled or not is_instance_valid(target):
		return
	var strength := SpectatorFx.shake_strength(amount, is_crit, on_character, HitFeedback.is_boss_hit(target, on_character), int(target.get("max_hp")))
	if strength > 0.0:
		add_shake(strength)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				following = false
				manual = true
				drag_start_mouse = event.position
				drag_start_camera = global_position
			else:
				dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			manual = true
			zoom = (zoom + Vector2.ONE * ZOOM_STEP).clamp(Vector2.ONE * MIN_ZOOM, Vector2.ONE * MAX_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			manual = true
			zoom = (zoom - Vector2.ONE * ZOOM_STEP).clamp(Vector2.ONE * MIN_ZOOM, Vector2.ONE * MAX_ZOOM)
	elif event is InputEventMouseMotion and dragging:
		var mouse_motion := event as InputEventMouseMotion
		var delta_mouse := mouse_motion.position - drag_start_mouse
		global_position = drag_start_camera - delta_mouse / zoom

func recenter() -> void:
	following = true
	manual = false

## Returns the new state (true = director on).
func toggle_director() -> bool:
	director_enabled = not director_enabled
	if director_enabled:
		manual = false
	return director_enabled
```

- [ ] **Step 2: Verify**

Run the tests (`0 failures`). Boot the game via MCP `run_project`; `game_eval` return `[GameState.camera.zoom, GameState.camera.director_enabled]` (expect `[(1,1), true]` when idle) and `get_debug_output` shows no errors. Stop.

- [ ] **Step 3: Commit**

```bash
git add scripts/ui/camera_controller.gd
git commit -m "Camera: auto-director framing, smoothing, manual override and shake

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: `BossEvents` UI, slow-mo and Director button

**Files:**
- Create: `scripts/ui/boss_events.gd`
- Modify: `scripts/ui/speed_control.gd`
- Modify: `scripts/main.gd` (attach BossEvents to the UI)

- [ ] **Step 1: Create `scripts/ui/boss_events.gd`**

```gdscript
class_name BossEvents
extends Control

## Boss presentation: a name banner and a top-center health bar when the
## character targets a boss, a result banner (Victory / Defeated / Fled), and
## a brief slow-motion on a boss kill. Built in code, added to the UI by Main.

const HOLD_S := 1.6
const FADE_S := 0.6
const ENGAGED_COLOR := Color(1.0, 0.85, 0.3, 1.0)
const VICTORY_COLOR := Color(1.0, 0.9, 0.35, 1.0)
const DEFEATED_COLOR := Color(1.0, 0.35, 0.3, 1.0)
const FLED_COLOR := Color(0.75, 0.85, 1.0, 1.0)

var boss: Node2D = null
var tracking := false
## Boss instances already announced (a respawned boss is a new instance).
var announced := {}

var banner: Label
var bar_panel: Panel
var bar_name: Label
var bar: ProgressBar
var bar_text: Label
var banner_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	banner = Label.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.anchor_right = 1.0
	banner.offset_top = 140.0
	banner.offset_bottom = 190.0
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 34)
	banner.add_theme_constant_override("outline_size", 8)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	banner.modulate.a = 0.0
	add_child(banner)

	bar_panel = Panel.new()
	bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_panel.anchor_left = 0.5
	bar_panel.anchor_right = 0.5
	bar_panel.offset_left = -200.0
	bar_panel.offset_right = 200.0
	bar_panel.offset_top = 104.0
	bar_panel.offset_bottom = 134.0
	bar_panel.visible = false
	add_child(bar_panel)

	# Anchored (not sized) so ProgressBar does not reset its size on setup.
	bar = ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.offset_left = 4.0
	bar.offset_top = 4.0
	bar.offset_right = -4.0
	bar.offset_bottom = -4.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.15, 0.12, 1.0)
	bar.add_theme_stylebox_override("fill", fill)
	bar_panel.add_child(bar)

	bar_name = Label.new()
	bar_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_name.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_name.offset_left = 10.0
	bar_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_name.add_theme_font_size_override("font_size", 13)
	bar_panel.add_child(bar_name)

	bar_text = Label.new()
	bar_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_text.offset_right = -10.0
	bar_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_text.add_theme_font_size_override("font_size", 13)
	bar_panel.add_child(bar_text)

	GameState.combat_target_changed.connect(_on_target_changed)
	GameState.boss_event.connect(_on_boss_event)

func _process(_delta: float) -> void:
	if not tracking:
		return
	if not is_instance_valid(boss):
		_stop_tracking()
		return
	bar.value = float(boss.get("hp"))
	bar_text.text = "%d / %d" % [int(boss.get("hp")), int(boss.get("max_hp"))]

func _on_target_changed(target: Node2D) -> void:
	# is_instance_valid first: a freed Object compares equal to null.
	if is_instance_valid(target) and target.has_method("is_boss") and bool(target.call("is_boss")):
		boss = target
		tracking = true
		var boss_name := String(target.get("enemy_name"))
		bar.max_value = float(target.get("max_hp"))
		bar_name.text = boss_name
		bar_panel.visible = true
		var id := target.get_instance_id()
		if not announced.has(id):
			announced[id] = true
			_show_banner("BOSS - %s" % boss_name, ENGAGED_COLOR)
	else:
		_stop_tracking()

func _stop_tracking() -> void:
	tracking = false
	boss = null
	bar_panel.visible = false

func _on_boss_event(kind: String, boss_name: String) -> void:
	match kind:
		"victory":
			_show_banner("VICTORY - %s" % boss_name, VICTORY_COLOR)
			_slow_motion()
		"defeated":
			_show_banner("DEFEATED by %s" % boss_name, DEFEATED_COLOR)
		"fled":
			_show_banner("Fled from %s" % boss_name, FLED_COLOR)

func _show_banner(text: String, color: Color) -> void:
	if banner_tween != null and banner_tween.is_valid():
		banner_tween.kill()
	banner.text = text
	banner.modulate = color
	banner_tween = create_tween()
	banner_tween.tween_interval(HOLD_S)
	banner_tween.tween_property(banner, "modulate:a", 0.0, FADE_S)

func _slow_motion() -> void:
	if not GameState.fx_enabled or not SpectatorFx.should_slow_kill(true, Engine.time_scale):
		return
	Engine.time_scale = SpectatorFx.SLOW_SCALE
	# process_always = true, process_in_physics = false, ignore_time_scale = true
	await get_tree().create_timer(SpectatorFx.SLOW_DURATION_S, true, false, true).timeout
	Engine.time_scale = GameState.user_time_scale
```

- [ ] **Step 2: Track the chosen speed and add the Director button**

Replace `scripts/ui/speed_control.gd` with:

```gdscript
extends HBoxContainer

@onready var pause_button: Button = $PauseButton
@onready var speed1_button: Button = $Speed1Button
@onready var speed2_button: Button = $Speed2Button
@onready var speed4_button: Button = $Speed4Button
@onready var recenter_button: Button = $RecenterButton

func _ready() -> void:
	pause_button.pressed.connect(func(): _set_speed(0.0))
	speed1_button.pressed.connect(func(): _set_speed(1.0))
	speed2_button.pressed.connect(func(): _set_speed(2.0))
	speed4_button.pressed.connect(func(): _set_speed(4.0))
	recenter_button.pressed.connect(func():
		if GameState.camera:
			GameState.camera.recenter()
	)
	# Appended after the Sheet and Codex buttons.
	var director_button := Button.new()
	director_button.text = "Director: On"
	director_button.pressed.connect(func():
		if GameState.camera:
			var on: bool = GameState.camera.toggle_director()
			director_button.text = "Director: On" if on else "Director: Off"
	)
	add_child(director_button)

## Remembers the human's speed so boss slow-motion can restore it exactly.
func _set_speed(scale: float) -> void:
	GameState.user_time_scale = scale
	Engine.time_scale = scale
```

- [ ] **Step 3: Attach `BossEvents` to the UI**

In `scripts/main.gd` `_ready()`, after `add_child(HitFeedback.new())`, add:

```gdscript
	var ui := get_node_or_null("UI")
	if ui != null:
		ui.add_child(BossEvents.new())
```

- [ ] **Step 4: Verify parse and tests**

Run the tests (`0 failures`). Boot with MCP `run_project`; `get_debug_output` shows no new errors; `game_screenshot` shows the speed row with a `Director: On` button after the Codex button (the row's position may need a look: the row is centered at the top; confirm it still fits in 1152 px, otherwise shorten the label to `Director`).

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/boss_events.gd scripts/ui/speed_control.gd scripts/main.gd
git commit -m "Add boss banner, boss bar, kill slow-mo and Director toggle

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Verification, docs, and sim regression

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/balance/2026-09-25-balance-report.md` (one-line note, optional)

- [ ] **Step 1: Full tests**

Run the tests. Expected `0 failures`, no SCRIPT ERROR, more checks than the 12047 baseline.

- [ ] **Step 2: Sim regression (effects must not change balance)**

```bash
export GODOT="C:/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
tests/sim/run_batch.sh "$TEMP/simE" 45 "warrior mage" "1 2 3 4" 8
```

Compare against the previous run of the same seeds (`$TEMP/simC/warrior_s1..4.log` and `mage_s1..4.log`, from the 2026-09-26 balance follow-up; if those logs are gone, run the same command on `main` first). For each of the eight runs the level-time columns L2..L10 and `deaths` must be identical. Different values mean an effect leaked into gameplay; find and fix the leak (usually a missing `GameState.fx_enabled` guard).

- [ ] **Step 3: Live check (Godot MCP)**

`run_project`, then use `game_eval` / `game_screenshot`:

1. Set `Engine.time_scale = 1.0`. Watch a fight: hit flashes and nudges visible; numbers differ in size; a crit shows a gold number with `!` (force one if needed by calling `GameState.emit_signal("hit_landed", <an enemy>, 30, true, false)`).
2. Teleport the character next to the Crypt Lord (`Sundered Crypt`, x about 2200 + zone offset; use the enemy's `global_position`) and confirm: the `BOSS - Crypt Lord` banner, the top boss bar with HP text, the camera zooming in to about 1.5x, and shake on big hits.
3. Kill it (`enemy.take_damage(9999, GameState.character)`): `VICTORY - Crypt Lord` banner and `Engine.time_scale` at 0.25 then back to the chosen speed within ~1 s. Repeat with `Engine.time_scale = 0.0`: no slow-mo.
4. `GameState.character.current_state = "travel"` for a moment (or wait for a real trip): camera zooms out toward 0.8.
5. Drag the mouse: director pauses (camera stays); click `Recenter`: director resumes. Click `Director: On` -> `Off`: camera hard-follows at zoom 1.0 as before; toggle back.
6. `get_debug_output` shows no errors. Take screenshots of the boss fight for the README if they look good (`get_tree().root.get_texture().get_image().save_png(...)` into `docs/screenshots/`).

- [ ] **Step 4: README**

In `README.md`, under the features list add a bullet: `Spectator experience: hit flash and knockback, scaled damage numbers, camera shake, boss banners with a health bar and slow-motion kills, and an auto-director camera (toggle with the Director button; drag to take over, Recenter to hand back).` In the Controls section mention the Director button. If a boss-fight screenshot was captured, add it to the Screenshots section.

- [ ] **Step 5: Commit**

```bash
git add README.md docs
git commit -m "Docs: spectator experience pass

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Finish**

Use the finishing-a-development-branch flow: fast-forward merge `spectator-experience` into `main` locally, re-run the tests on `main`, delete the branch. Push only when the user asks.
