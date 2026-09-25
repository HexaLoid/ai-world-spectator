# AI-Played World Spectator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the v1 vertical slice from the design spec — one AI-controlled character that autonomously explores, fights, loots, and levels up in a single zone ("Thornfield Meadow"), with a spectator-only camera/UI and zero direct player control.

**Architecture:** Godot 4.6 project, GDScript, 2D top-down. Pure decision/math logic (AI state resolution, leveling, combat rolls, loot rules) lives in standalone `class_name` utility scripts with no Node dependency, so it can be exercised directly. Everything else (movement, rendering, UI) is standard Godot nodes wired through one autoload (`GameState`) that broadcasts signals so UI never reaches into gameplay code directly.

**Tech Stack:** Godot 4.6.2 (confirmed installed version), GDScript, Godot MCP tools (`mcp__godot__*`) for all project/scene/script creation and for live verification via `run_project` / `game_eval` / `game_get_errors` / `game_screenshot`.

**Spec:** [docs/superpowers/specs/2026-09-21-ai-played-world-spectator-design.md](../specs/2026-09-21-ai-played-world-spectator-design.md)

---

## Conventions used throughout this plan

- `PROJECT_PATH` = `C:\Users\n1njaz\Desktop\New folder` — pass this exact string as `projectPath` on every `mcp__godot__*` call.
- All scene/script paths given below are relative to `PROJECT_PATH` (i.e. what you pass as `scenePath`/`scriptPath`/`filePath`), and inside GDScript they're referenced with the `res://` prefix (e.g. `res://scripts/ai/ai_decision.gd`).
- **No formal test framework is installed.** "Tests" for the four pure-logic modules (Tasks 3–6) are done with the Godot MCP `game_eval` tool against a live running instance of the project: call the function with known inputs, read back the returned value, and compare it to the expected value written in the step. This is the closest practical equivalent to unit tests given the tooling available, and follows red/green: each pure-logic task first writes a deliberately-wrong stub, confirms it produces the wrong answer, then writes the real implementation and confirms it produces the right answer.
- **Entity/scene/UI tasks (7–16)** are verified by running the project and checking `game_get_errors` returns nothing new, plus targeted `game_eval`/`game_get_property` checks described in each task. Full end-to-end behavioral verification (the AI actually playing itself well) is Task 17, matching the "How We'll Know V1 Is Done" section of the spec.
- **Godot tool property formats are not fully documented for `add_node`/`modify_scene_node`.** Try passing `Vector2`/`Color` properties as nested objects, e.g. `{"x": -12, "y": -12}` for a `Vector2` and `{"r": 0.2, "g": 0.4, "b": 0.9, "a": 1.0}` for a `Color`. After any such call, use `mcp__godot__read_file` on the `.tscn` file to confirm the property serialized as a real `Vector2(...)`/`Color(...)` line. If it didn't, fix it directly with `mcp__godot__write_file`, writing the corrected `.tscn` text (Godot scene files are plain text in the standard `[gd_scene]` resource format — safe to hand-edit).
- Commit after every task. Every commit message ends with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` per this repo's attribution convention.
- Art: all visuals in this plan are flat-colored `ColorRect` placeholders (grey-boxing). No sprite files are downloaded or imported — automated sourcing of CC0 art packs isn't reliable without a browser/download tool. Swapping in real sprites later is a manual follow-up (replace each entity's `ColorRect` child with a `Sprite2D` pointing at a real texture) and is out of scope for this plan.

---

### Task 1: Project scaffold

**Files:**
- Create: `project.godot` (via `create_project`)
- Create: `scenes/Main.tscn`
- Create: `.gitignore`

- [ ] **Step 1: Create the Godot project**

Run: `mcp__godot__create_project` with `projectPath="C:\Users\n1njaz\Desktop\New folder"`, `projectName="AIWorldSpectator"`.
Expected: confirmation the project was created at that exact path (no nested subfolder — verified during planning: `create_project` creates `project.godot` directly inside the given `projectPath`).

- [ ] **Step 2: Verify with get_project_info**

Run: `mcp__godot__get_project_info` with `projectPath="C:\Users\n1njaz\Desktop\New folder"`.
Expected: `"name": "AIWorldSpectator"`, `"godotVersion"` starting with `"4.6"`.

- [ ] **Step 3: Create folder structure**

Run `mcp__godot__create_directory` once per path (parent before child), all with `projectPath="C:\Users\n1njaz\Desktop\New folder"`:
`scripts`, `scripts/autoload`, `scripts/ai`, `scripts/systems`, `scripts/entities`, `scripts/ui`, `scenes`, `scenes/entities`, `scenes/world`, `scenes/ui`.
Expected: each call succeeds (or reports the directory already exists for `scenes`, which `create_project` may have already created).

- [ ] **Step 4: Create the Main scene**

Run: `mcp__godot__create_scene` with `projectPath="C:\Users\n1njaz\Desktop\New folder"`, `scenePath="scenes/Main.tscn"`, `rootNodeType="Node2D"`.
Expected: `scenes/Main.tscn` created with a `Node2D` root named `Main`.

- [ ] **Step 5: Set it as the main scene**

Run: `mcp__godot__set_main_scene` with `projectPath="C:\Users\n1njaz\Desktop\New folder"`, `scenePath="scenes/Main.tscn"`.
Expected: confirmation; `project.godot`'s `run/main_scene` now points at `res://scenes/Main.tscn`.

- [ ] **Step 6: Add a .gitignore for Godot's import cache**

Write `.gitignore` at the project root (via the `Write` tool, not a Godot tool) with this content:

```
.godot/
export.cfg
export_presets.cfg
```

- [ ] **Step 7: Sanity-run the empty project**

Run: `mcp__godot__run_project` with `projectPath="C:\Users\n1njaz\Desktop\New folder"`.
Then: `mcp__godot__game_get_errors`.
Expected: no errors returned.
Then: `mcp__godot__stop_project`.

- [ ] **Step 8: Commit**

```bash
git add project.godot .gitignore scenes/Main.tscn
git commit -m "$(cat <<'EOF'
Scaffold Godot project for AI-played world spectator

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: GameState autoload

**Files:**
- Create: `scripts/autoload/game_state.gd`

- [ ] **Step 1: Write the autoload script**

Run: `mcp__godot__create_script` with `projectPath="C:\Users\n1njaz\Desktop\New folder"`, `scriptPath="scripts/autoload/game_state.gd"`, `source`:

```gdscript
extends Node

signal character_state_changed(new_state: String)
signal character_hp_changed(hp: int, max_hp: int)
signal character_xp_changed(xp: int)
signal character_leveled_up(level: int)
signal character_equipment_changed(weapon_id: String, armor_id: String)
signal activity_logged(message: String)

var character: Node2D = null
var camera: Camera2D = null

func log_event(message: String) -> void:
	emit_signal("activity_logged", message)
	print(message)
```

- [ ] **Step 2: Register it as an autoload**

Run: `mcp__godot__manage_autoloads` with `projectPath="C:\Users\n1njaz\Desktop\New folder"`, `action="add"`, `name="GameState"`, `path="res://scripts/autoload/game_state.gd"`.
Expected: confirmation; `project.godot` now has `[autoload]` section with `GameState="*res://scripts/autoload/game_state.gd"`.

- [ ] **Step 3: Verify it loads**

Run: `mcp__godot__run_project` with `projectPath="C:\Users\n1njaz\Desktop\New folder"`.
Run: `mcp__godot__game_eval` with `code="return GameState.get_class()"`.
Expected: returns `"Node"` (confirms the autoload singleton exists and is reachable by name).
Run: `mcp__godot__game_get_errors`. Expected: empty.
Run: `mcp__godot__stop_project`.

- [ ] **Step 4: Commit**

```bash
git add project.godot scripts/autoload/game_state.gd
git commit -m "$(cat <<'EOF'
Add GameState autoload for cross-system signals

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: AIDecision (pure state-resolution logic)

**Files:**
- Create: `scripts/ai/ai_decision.gd`

- [ ] **Step 1: Write a deliberately-wrong stub**

Run: `mcp__godot__create_script` with `scriptPath="scripts/ai/ai_decision.gd"`, `source`:

```gdscript
class_name AIDecision
extends RefCounted

static func resolve_state(context: Dictionary) -> Dictionary:
	return {"state": "wander", "reason": "stub"}
```

- [ ] **Step 2: Confirm the stub gives the wrong answer (red)**

Run: `mcp__godot__run_project`.
Run: `mcp__godot__game_eval` with:

```gdscript
var result = AIDecision.resolve_state({"hp_percent": 0.2, "hostile_in_attack_range": false, "hostile_in_aggro_range": true, "hostile_name": "Wolf", "item_nearby": false})
return result.state
```

Expected: `"wander"` — this is **wrong** (should be `"flee"` once implemented), confirming the stub doesn't yet do real work.

- [ ] **Step 3: Write the real implementation**

Run: `mcp__godot__create_script` again (overwrite) with `scriptPath="scripts/ai/ai_decision.gd"`, `source`:

```gdscript
class_name AIDecision
extends RefCounted

const FLEE_HP_THRESHOLD := 0.3

static func resolve_state(context: Dictionary) -> Dictionary:
	var hp_percent: float = context.get("hp_percent", 1.0)
	var hostile_in_attack_range: bool = context.get("hostile_in_attack_range", false)
	var hostile_in_aggro_range: bool = context.get("hostile_in_aggro_range", false)
	var hostile_name: String = context.get("hostile_name", "")
	var item_nearby: bool = context.get("item_nearby", false)

	if hp_percent < FLEE_HP_THRESHOLD and hostile_in_aggro_range:
		return {"state": "flee", "reason": "HP low (%d%%) - fleeing from %s" % [round(hp_percent * 100), hostile_name]}
	if hp_percent < FLEE_HP_THRESHOLD:
		return {"state": "rest", "reason": "HP low (%d%%) - resting to recover" % round(hp_percent * 100)}
	if hostile_in_attack_range:
		return {"state": "combat", "reason": "%s in range - engaging" % hostile_name}
	if hostile_in_aggro_range:
		return {"state": "chase", "reason": "%s spotted - closing in" % hostile_name}
	if item_nearby:
		return {"state": "loot", "reason": "Item nearby - moving to pick it up"}
	return {"state": "wander", "reason": "Nothing pressing - wandering"}
```

- [ ] **Step 4: Confirm all six transition cases (green)**

Run: `mcp__godot__run_project`.
Run six `mcp__godot__game_eval` calls, one per case:

```gdscript
return AIDecision.resolve_state({"hp_percent": 1.0, "hostile_in_attack_range": false, "hostile_in_aggro_range": false, "hostile_name": "", "item_nearby": false}).state
```
Expected: `"wander"`

```gdscript
return AIDecision.resolve_state({"hp_percent": 0.2, "hostile_in_attack_range": false, "hostile_in_aggro_range": true, "hostile_name": "Wolf", "item_nearby": false}).state
```
Expected: `"flee"`

```gdscript
return AIDecision.resolve_state({"hp_percent": 0.2, "hostile_in_attack_range": false, "hostile_in_aggro_range": false, "hostile_name": "", "item_nearby": false}).state
```
Expected: `"rest"`

```gdscript
return AIDecision.resolve_state({"hp_percent": 1.0, "hostile_in_attack_range": true, "hostile_in_aggro_range": true, "hostile_name": "Bandit", "item_nearby": false}).state
```
Expected: `"combat"`

```gdscript
return AIDecision.resolve_state({"hp_percent": 1.0, "hostile_in_attack_range": false, "hostile_in_aggro_range": true, "hostile_name": "Wolf", "item_nearby": false}).state
```
Expected: `"chase"`

```gdscript
return AIDecision.resolve_state({"hp_percent": 1.0, "hostile_in_attack_range": false, "hostile_in_aggro_range": false, "hostile_name": "", "item_nearby": true}).state
```
Expected: `"loot"`

Run: `mcp__godot__game_get_errors`. Expected: empty.
Run: `mcp__godot__stop_project`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ai/ai_decision.gd
git commit -m "$(cat <<'EOF'
Add AIDecision pure state-resolution logic

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: LevelingSystem (pure XP/leveling logic)

**Files:**
- Create: `scripts/systems/leveling_system.gd`

- [ ] **Step 1: Write a deliberately-wrong stub**

Run: `mcp__godot__create_script` with `scriptPath="scripts/systems/leveling_system.gd"`, `source`:

```gdscript
class_name LevelingSystem
extends RefCounted

const XP_THRESHOLDS := [100, 250, 450, 700]
const MAX_LEVEL := 5
const HP_PER_LEVEL := 10
const DAMAGE_PER_LEVEL := 2

static func apply_xp(current_level: int, current_xp: int, xp_gained: int) -> Dictionary:
	return {"level": current_level, "xp": current_xp, "leveled_up": false, "hp_bonus": 0, "damage_bonus": 0}
```

- [ ] **Step 2: Confirm the stub gives the wrong answer (red)**

Run: `mcp__godot__run_project`.
Run: `mcp__godot__game_eval` with `code="return LevelingSystem.apply_xp(1, 0, 150).level"`.
Expected: `1` — **wrong** (should be `2` once implemented: 150 xp crosses the 100-xp threshold for level 2).

- [ ] **Step 3: Write the real implementation**

Run: `mcp__godot__create_script` again with `scriptPath="scripts/systems/leveling_system.gd"`, `source`:

```gdscript
class_name LevelingSystem
extends RefCounted

const XP_THRESHOLDS := [100, 250, 450, 700]
const MAX_LEVEL := 5
const HP_PER_LEVEL := 10
const DAMAGE_PER_LEVEL := 2

static func apply_xp(current_level: int, current_xp: int, xp_gained: int) -> Dictionary:
	var xp: int = current_xp + xp_gained
	var level: int = current_level
	while level < MAX_LEVEL and xp >= XP_THRESHOLDS[level - 1]:
		level += 1
	var levels_gained: int = level - current_level
	return {
		"level": level,
		"xp": xp,
		"leveled_up": levels_gained > 0,
		"hp_bonus": levels_gained * HP_PER_LEVEL,
		"damage_bonus": levels_gained * DAMAGE_PER_LEVEL,
	}
```

- [ ] **Step 4: Confirm four cases (green)**

Run: `mcp__godot__run_project`.

```gdscript
return LevelingSystem.apply_xp(1, 0, 50)
```
Expected: `{"level": 1, "xp": 50, "leveled_up": false, "hp_bonus": 0, "damage_bonus": 0}`

```gdscript
return LevelingSystem.apply_xp(1, 0, 150)
```
Expected: `{"level": 2, "xp": 150, "leveled_up": true, "hp_bonus": 10, "damage_bonus": 2}`

```gdscript
return LevelingSystem.apply_xp(1, 0, 1000)
```
Expected: `{"level": 5, "xp": 1000, "leveled_up": true, "hp_bonus": 40, "damage_bonus": 8}`

```gdscript
return LevelingSystem.apply_xp(5, 700, 500)
```
Expected: `{"level": 5, "xp": 1200, "leveled_up": false, "hp_bonus": 0, "damage_bonus": 0}`

Run: `mcp__godot__game_get_errors`. Expected: empty.
Run: `mcp__godot__stop_project`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/leveling_system.gd
git commit -m "$(cat <<'EOF'
Add LevelingSystem pure XP/leveling logic

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: CombatSystem (pure damage/cooldown logic)

**Files:**
- Create: `scripts/systems/combat_system.gd`

- [ ] **Step 1: Write a deliberately-wrong stub**

Run: `mcp__godot__create_script` with `scriptPath="scripts/systems/combat_system.gd"`, `source`:

```gdscript
class_name CombatSystem
extends RefCounted

static func roll_damage(min_damage: int, max_damage: int, rng: RandomNumberGenerator) -> int:
	return -1

static func is_off_cooldown(last_attack_time_ms: int, cooldown_ms: int, now_ms: int) -> bool:
	return false
```

- [ ] **Step 2: Confirm the stub gives the wrong answer (red)**

Run: `mcp__godot__run_project`.

```gdscript
return CombatSystem.is_off_cooldown(1000, 500, 1600)
```
Expected: `false` — **wrong** (600ms elapsed >= 500ms cooldown, should be `true`).

- [ ] **Step 3: Write the real implementation**

Run: `mcp__godot__create_script` again with `scriptPath="scripts/systems/combat_system.gd"`, `source`:

```gdscript
class_name CombatSystem
extends RefCounted

static func roll_damage(min_damage: int, max_damage: int, rng: RandomNumberGenerator) -> int:
	return rng.randi_range(min_damage, max_damage)

static func is_off_cooldown(last_attack_time_ms: int, cooldown_ms: int, now_ms: int) -> bool:
	return now_ms - last_attack_time_ms >= cooldown_ms
```

- [ ] **Step 4: Confirm cooldown cases and damage bounds (green)**

Run: `mcp__godot__run_project`.

```gdscript
return CombatSystem.is_off_cooldown(1000, 500, 1600)
```
Expected: `true`

```gdscript
return CombatSystem.is_off_cooldown(1000, 500, 1400)
```
Expected: `false`

```gdscript
var rng := RandomNumberGenerator.new()
rng.seed = 42
var all_in_range := true
for i in range(50):
	var dmg = CombatSystem.roll_damage(5, 10, rng)
	if dmg < 5 or dmg > 10:
		all_in_range = false
return all_in_range
```
Expected: `true`

Run: `mcp__godot__game_get_errors`. Expected: empty.
Run: `mcp__godot__stop_project`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/combat_system.gd
git commit -m "$(cat <<'EOF'
Add CombatSystem pure damage/cooldown logic

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: LootTable (pure drop/equip logic)

**Files:**
- Create: `scripts/systems/loot_table.gd`

- [ ] **Step 1: Write a deliberately-wrong stub**

Run: `mcp__godot__create_script` with `scriptPath="scripts/systems/loot_table.gd"`, `source`:

```gdscript
class_name LootTable
extends RefCounted

const ITEMS := {
	"rusty_sword": {"type": "weapon", "damage": 4},
	"iron_sword": {"type": "weapon", "damage": 7},
	"leather_armor": {"type": "armor", "max_hp": 15},
	"health_potion": {"type": "consumable", "heal": 20},
}

static func roll_drop(rng: RandomNumberGenerator) -> String:
	return "rusty_sword"

static func should_equip(equipped_item_id: String, candidate_item_id: String) -> bool:
	return false
```

- [ ] **Step 2: Confirm the stub gives the wrong answer (red)**

Run: `mcp__godot__run_project`.

```gdscript
return LootTable.should_equip("", "rusty_sword")
```
Expected: `false` — **wrong** (empty slot should always accept the candidate, should be `true`).

- [ ] **Step 3: Write the real implementation**

Run: `mcp__godot__create_script` again with `scriptPath="scripts/systems/loot_table.gd"`, `source`:

```gdscript
class_name LootTable
extends RefCounted

const ITEMS := {
	"rusty_sword": {"type": "weapon", "damage": 4},
	"iron_sword": {"type": "weapon", "damage": 7},
	"leather_armor": {"type": "armor", "max_hp": 15},
	"health_potion": {"type": "consumable", "heal": 20},
}

static func roll_drop(rng: RandomNumberGenerator) -> String:
	var keys := ITEMS.keys()
	var index := rng.randi_range(0, keys.size() - 1)
	return keys[index]

static func should_equip(equipped_item_id: String, candidate_item_id: String) -> bool:
	var candidate: Dictionary = ITEMS.get(candidate_item_id, {})
	if candidate.is_empty():
		return false
	var candidate_type: String = candidate.get("type", "")
	if candidate_type == "consumable":
		return false
	if equipped_item_id == "":
		return true
	var equipped: Dictionary = ITEMS.get(equipped_item_id, {})
	if equipped.get("type", "") != candidate_type:
		return false
	var stat_key := "damage" if candidate_type == "weapon" else "max_hp"
	return candidate.get(stat_key, 0) > equipped.get(stat_key, 0)
```

**Note:** `should_equip` assumes the caller always compares against the item currently equipped in the *same slot* (weapon vs weapon, armor vs armor) — Task 7's `Character._pickup_item` relies on this and never mixes slots.

- [ ] **Step 4: Confirm five cases plus roll_drop validity (green)**

Run: `mcp__godot__run_project`.

```gdscript
return LootTable.should_equip("", "rusty_sword")
```
Expected: `true`

```gdscript
return LootTable.should_equip("rusty_sword", "iron_sword")
```
Expected: `true`

```gdscript
return LootTable.should_equip("iron_sword", "rusty_sword")
```
Expected: `false`

```gdscript
return LootTable.should_equip("", "health_potion")
```
Expected: `false`

```gdscript
return LootTable.should_equip("", "leather_armor")
```
Expected: `true`

```gdscript
var rng := RandomNumberGenerator.new()
rng.seed = 7
var key = LootTable.roll_drop(rng)
return LootTable.ITEMS.has(key)
```
Expected: `true`

Run: `mcp__godot__game_get_errors`. Expected: empty.
Run: `mcp__godot__stop_project`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/loot_table.gd
git commit -m "$(cat <<'EOF'
Add LootTable pure drop/equip logic

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Character entity

**Files:**
- Create: `scripts/entities/character.gd`
- Create: `scenes/entities/Character.tscn`
- Modify: `scenes/Main.tscn` (add Character instance)

- [ ] **Step 1: Write the character script**

Run: `mcp__godot__create_script` with `scriptPath="scripts/entities/character.gd"`, `source`:

```gdscript
extends CharacterBody2D

const MOVE_SPEED := 80.0
const ATTACK_RANGE := 28.0
const AGGRO_RANGE := 160.0
const PICKUP_RANGE := 20.0
const ATTACK_COOLDOWN_MS := 900
const RESPAWN_DELAY_S := 2.0
const RESPAWN_POSITION := Vector2(0, 0)

@export var max_hp: int = 60
@export var hp: int = 60
@export var level: int = 1
@export var xp: int = 0
@export var attack_damage_min: int = 4
@export var attack_damage_max: int = 8

var equipped_weapon_id: String = ""
var equipped_armor_id: String = ""
var current_state: String = "wander"
var last_attack_time_ms: int = 0
var wander_target: Vector2 = Vector2.ZERO
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	wander_target = global_position
	GameState.character = self

func _physics_process(delta: float) -> void:
	if hp <= 0:
		return
	var context := _build_context()
	var decision := AIDecision.resolve_state(context)
	var new_state: String = decision["state"]
	if new_state != current_state:
		current_state = new_state
		GameState.log_event(decision["reason"])
		GameState.emit_signal("character_state_changed", current_state)
	_act(delta, context)

func _build_context() -> Dictionary:
	var nearest_hostile := _find_nearest_in_group("enemies")
	var nearest_item := _find_nearest_in_group("items")
	var context := {
		"hp_percent": float(hp) / float(max_hp),
		"hostile_in_attack_range": false,
		"hostile_in_aggro_range": false,
		"hostile_name": "",
		"item_nearby": false,
	}
	if nearest_hostile:
		var dist := global_position.distance_to(nearest_hostile.global_position)
		context["hostile_in_attack_range"] = dist <= ATTACK_RANGE
		context["hostile_in_aggro_range"] = dist <= AGGRO_RANGE
		context["hostile_name"] = nearest_hostile.enemy_name
	if nearest_item:
		var item_dist := global_position.distance_to(nearest_item.global_position)
		context["item_nearby"] = item_dist <= AGGRO_RANGE
	return context

func _find_nearest_in_group(group_name: String) -> Node2D:
	var nodes := get_tree().get_nodes_in_group(group_name)
	var nearest: Node2D = null
	var nearest_dist := INF
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var d := global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = node
	return nearest

func _act(delta: float, context: Dictionary) -> void:
	match current_state:
		"flee":
			var hostile := _find_nearest_in_group("enemies")
			if hostile:
				velocity = (global_position - hostile.global_position).normalized() * MOVE_SPEED
				move_and_slide()
		"rest":
			velocity = Vector2.ZERO
			hp = min(max_hp, hp + 1)
		"combat":
			velocity = Vector2.ZERO
			_attack_nearest_hostile()
		"chase":
			var hostile := _find_nearest_in_group("enemies")
			if hostile:
				velocity = (hostile.global_position - global_position).normalized() * MOVE_SPEED
				move_and_slide()
		"loot":
			var item := _find_nearest_in_group("items")
			if item:
				var to_item := item.global_position - global_position
				if to_item.length() <= PICKUP_RANGE:
					_pickup_item(item)
				else:
					velocity = to_item.normalized() * MOVE_SPEED
					move_and_slide()
		"wander":
			if global_position.distance_to(wander_target) < 8.0:
				wander_target = global_position + Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
			velocity = (wander_target - global_position).normalized() * MOVE_SPEED * 0.5
			move_and_slide()

func _attack_nearest_hostile() -> void:
	var now := Time.get_ticks_msec()
	if not CombatSystem.is_off_cooldown(last_attack_time_ms, ATTACK_COOLDOWN_MS, now):
		return
	var hostile := _find_nearest_in_group("enemies")
	if hostile == null:
		return
	last_attack_time_ms = now
	var damage := CombatSystem.roll_damage(attack_damage_min, attack_damage_max, rng)
	hostile.take_damage(damage)

func take_damage(amount: int) -> void:
	hp = max(0, hp - amount)
	GameState.emit_signal("character_hp_changed", hp, max_hp)
	if hp <= 0:
		_die()

func _die() -> void:
	GameState.log_event("Character died - respawning")
	visible = false
	set_physics_process(false)
	await get_tree().create_timer(RESPAWN_DELAY_S).timeout
	hp = max_hp
	global_position = RESPAWN_POSITION
	visible = true
	set_physics_process(true)
	GameState.emit_signal("character_hp_changed", hp, max_hp)

func gain_xp(amount: int) -> void:
	var result := LevelingSystem.apply_xp(level, xp, amount)
	level = result["level"]
	xp = result["xp"]
	if result["leveled_up"]:
		max_hp += result["hp_bonus"]
		hp += result["hp_bonus"]
		attack_damage_min += result["damage_bonus"]
		attack_damage_max += result["damage_bonus"]
		GameState.log_event("Leveled up to %d!" % level)
		GameState.emit_signal("character_leveled_up", level)
	GameState.emit_signal("character_xp_changed", xp)

func take_kill_credit(enemy_name: String, xp_reward: int) -> void:
	GameState.log_event("Defeated %s" % enemy_name)
	gain_xp(xp_reward)

func _pickup_item(item: Node2D) -> void:
	var item_id: String = item.item_id
	var item_def: Dictionary = LootTable.ITEMS.get(item_id, {})
	var item_type: String = item_def.get("type", "")
	if item_type == "consumable":
		hp = min(max_hp, hp + int(item_def.get("heal", 0)))
		GameState.log_event("Used %s" % item_id)
		GameState.emit_signal("character_hp_changed", hp, max_hp)
	elif item_type == "weapon":
		if LootTable.should_equip(equipped_weapon_id, item_id):
			equipped_weapon_id = item_id
			attack_damage_min = int(item_def.get("damage", attack_damage_min))
			attack_damage_max = attack_damage_min + 4
			GameState.log_event("Equipped %s" % item_id)
			GameState.emit_signal("character_equipment_changed", equipped_weapon_id, equipped_armor_id)
	elif item_type == "armor":
		if LootTable.should_equip(equipped_armor_id, item_id):
			equipped_armor_id = item_id
			max_hp += int(item_def.get("max_hp", 0))
			GameState.log_event("Equipped %s" % item_id)
			GameState.emit_signal("character_equipment_changed", equipped_weapon_id, equipped_armor_id)
	item.queue_free()
```

- [ ] **Step 2: Create the Character scene**

Run: `mcp__godot__create_scene` with `scenePath="scenes/entities/Character.tscn"`, `rootNodeType="CharacterBody2D"`.

- [ ] **Step 3: Attach the script**

Run: `mcp__godot__attach_script` with `scenePath="scenes/entities/Character.tscn"`, `nodePath="root"`, `scriptPath="scripts/entities/character.gd"`.

- [ ] **Step 4: Add the placeholder visual**

Run: `mcp__godot__add_node` with `scenePath="scenes/entities/Character.tscn"`, `parentNodePath="root"`, `nodeType="ColorRect"`, `nodeName="ColorRect"`, `properties={"position": {"x": -12, "y": -12}, "size": {"x": 24, "y": 24}, "color": {"r": 0.2, "g": 0.4, "b": 0.9, "a": 1.0}}`.
Then: `mcp__godot__read_file` on `scenes/entities/Character.tscn` — confirm the `ColorRect` node's `position`, `size`, and `color` appear as real `Vector2(...)`/`Color(...)` values (see Conventions note if not).

- [ ] **Step 5: Save the scene**

Run: `mcp__godot__save_scene` with `scenePath="scenes/entities/Character.tscn"`.

- [ ] **Step 6: Instance Character under Main**

Run: `mcp__godot__add_node` with `scenePath="scenes/Main.tscn"`, `parentNodePath="root"`, `nodeType="CharacterBody2D"`... — **actually, to instance a saved scene (not just add a bare node), use `add_node` if it supports an `instance` path, otherwise fall back to**: open `scenes/Main.tscn` with `read_file`, and use `write_file` to add an `[ext_resource]` line pointing at `res://scenes/entities/Character.tscn` plus a child node line `[node name="Character" parent="." instance=ExtResource("...")]`, matching the existing `.tscn` text format exactly. Whichever method is used, the end state must be: `scenes/Main.tscn` has a child node named `Character` that is an instance of `scenes/entities/Character.tscn`, positioned at `(0, 0)`.
Verify with `mcp__godot__read_file` on `scenes/Main.tscn`.

- [ ] **Step 7: Verify it runs**

Run: `mcp__godot__run_project`.
Run: `mcp__godot__game_eval` with `code="return GameState.character != null"`. Expected: `true`.
Run: `mcp__godot__game_eval` with `code="return GameState.character.current_state"`. Expected: `"wander"` (no enemies/items exist yet, so it should default to wandering).
Run: `mcp__godot__game_get_errors`. Expected: empty.
Run: `mcp__godot__stop_project`.

- [ ] **Step 8: Commit**

```bash
git add scripts/entities/character.gd scenes/entities/Character.tscn scenes/Main.tscn
git commit -m "$(cat <<'EOF'
Add AI-controlled Character entity

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: ItemPickup entity

**Files:**
- Create: `scripts/entities/item_pickup.gd`
- Create: `scenes/entities/ItemPickup.tscn`

- [ ] **Step 1: Write the script**

Run: `mcp__godot__create_script` with `scriptPath="scripts/entities/item_pickup.gd"`, `source`:

```gdscript
extends Node2D

@export var item_id: String = "rusty_sword"

func _ready() -> void:
	add_to_group("items")
```

- [ ] **Step 2: Create the scene**

Run: `mcp__godot__create_scene` with `scenePath="scenes/entities/ItemPickup.tscn"`, `rootNodeType="Node2D"`.
Run: `mcp__godot__attach_script` with `scenePath="scenes/entities/ItemPickup.tscn"`, `nodePath="root"`, `scriptPath="scripts/entities/item_pickup.gd"`.

- [ ] **Step 3: Add the placeholder visual**

Run: `mcp__godot__add_node` with `scenePath="scenes/entities/ItemPickup.tscn"`, `parentNodePath="root"`, `nodeType="ColorRect"`, `nodeName="ColorRect"`, `properties={"position": {"x": -6, "y": -6}, "size": {"x": 12, "y": 12}, "color": {"r": 1.0, "g": 0.85, "b": 0.2, "a": 1.0}}`.
Run: `mcp__godot__save_scene` with `scenePath="scenes/entities/ItemPickup.tscn"`.

- [ ] **Step 4: Verify it instantiates cleanly**

Run: `mcp__godot__run_project`.
Run: `mcp__godot__game_eval` with:

```gdscript
var item = load("res://scenes/entities/ItemPickup.tscn").instantiate()
item.item_id = "iron_sword"
get_tree().current_scene.add_child(item)
return item.is_in_group("items")
```

Expected: `true`.
Run: `mcp__godot__game_get_errors`. Expected: empty.
Run: `mcp__godot__stop_project`.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/item_pickup.gd scenes/entities/ItemPickup.tscn
git commit -m "$(cat <<'EOF'
Add ItemPickup entity

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Enemy entity (shared by Wolf and Bandit)

**Files:**
- Create: `scripts/entities/enemy.gd`
- Create: `scenes/entities/Enemy.tscn`

- [ ] **Step 1: Write the script**

Run: `mcp__godot__create_script` with `scriptPath="scripts/entities/enemy.gd"`, `source`:

```gdscript
extends CharacterBody2D

@export var enemy_name: String = "Enemy"
@export var max_hp: int = 20
@export var move_speed: float = 60.0
@export var attack_damage_min: int = 2
@export var attack_damage_max: int = 5
@export var attack_range: float = 24.0
@export var aggro_range: float = 120.0
@export var attack_cooldown_ms: int = 1200
@export var xp_reward: int = 25

var hp: int
var last_attack_time_ms: int = 0
var rng := RandomNumberGenerator.new()
var spawn_point: Node2D = null

func _ready() -> void:
	hp = max_hp
	rng.randomize()
	add_to_group("enemies")

func _physics_process(delta: float) -> void:
	if hp <= 0:
		return
	var character := GameState.character
	if character == null or not is_instance_valid(character):
		velocity = Vector2.ZERO
		return
	var dist := global_position.distance_to(character.global_position)
	if dist <= attack_range:
		velocity = Vector2.ZERO
		_attack(character)
	elif dist <= aggro_range:
		velocity = (character.global_position - global_position).normalized() * move_speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO

func _attack(character: Node) -> void:
	var now := Time.get_ticks_msec()
	if not CombatSystem.is_off_cooldown(last_attack_time_ms, attack_cooldown_ms, now):
		return
	last_attack_time_ms = now
	var damage := CombatSystem.roll_damage(attack_damage_min, attack_damage_max, rng)
	character.take_damage(damage)

func take_damage(amount: int) -> void:
	hp = max(0, hp - amount)
	if hp <= 0:
		_die()

func _die() -> void:
	var character := GameState.character
	if character and is_instance_valid(character):
		character.take_kill_credit(enemy_name, xp_reward)
	_drop_loot()
	if spawn_point and is_instance_valid(spawn_point):
		spawn_point.on_enemy_died()
	queue_free()

func _drop_loot() -> void:
	var item_id := LootTable.roll_drop(rng)
	var item_scene: PackedScene = load("res://scenes/entities/ItemPickup.tscn")
	var item := item_scene.instantiate()
	item.item_id = item_id
	item.global_position = global_position
	get_tree().current_scene.add_child(item)
```

- [ ] **Step 2: Create the scene**

Run: `mcp__godot__create_scene` with `scenePath="scenes/entities/Enemy.tscn"`, `rootNodeType="CharacterBody2D"`.
Run: `mcp__godot__attach_script` with `scenePath="scenes/entities/Enemy.tscn"`, `nodePath="root"`, `scriptPath="scripts/entities/enemy.gd"`.

- [ ] **Step 3: Add the placeholder visual**

Run: `mcp__godot__add_node` with `scenePath="scenes/entities/Enemy.tscn"`, `parentNodePath="root"`, `nodeType="ColorRect"`, `nodeName="ColorRect"`, `properties={"position": {"x": -12, "y": -12}, "size": {"x": 24, "y": 24}, "color": {"r": 0.6, "g": 0.6, "b": 0.6, "a": 1.0}}`.
Run: `mcp__godot__save_scene` with `scenePath="scenes/entities/Enemy.tscn"`.

- [ ] **Step 4: Verify combat + death + loot drop in isolation**

Run: `mcp__godot__run_project`.
Run: `mcp__godot__game_eval` with:

```gdscript
var e = load("res://scenes/entities/Enemy.tscn").instantiate()
e.enemy_name = "TestWolf"
e.max_hp = 10
get_tree().current_scene.add_child(e)
e.global_position = Vector2(500, 500)
e.take_damage(9999)
return e.hp
```

Expected: `0` (confirms `take_damage` clamps and triggers death; the node itself is freed at end-of-frame via `queue_free()`, but `hp` reads `0` immediately).
Run: `mcp__godot__game_eval` with `code="return get_tree().get_nodes_in_group(\"items\").size()"`. Expected: at least `1` (the dead test enemy dropped loot at `(500, 500)`).
Run: `mcp__godot__game_get_errors`. Expected: empty.
Run: `mcp__godot__stop_project`.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/enemy.gd scenes/entities/Enemy.tscn
git commit -m "$(cat <<'EOF'
Add Enemy entity shared by Wolf and Bandit variants

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: SpawnPoint entity

**Files:**
- Create: `scripts/entities/spawn_point.gd`
- Create: `scenes/entities/SpawnPoint.tscn`

- [ ] **Step 1: Write the script**

Run: `mcp__godot__create_script` with `scriptPath="scripts/entities/spawn_point.gd"`, `source`:

```gdscript
extends Node2D

@export var enemy_scene: PackedScene
@export var respawn_delay_s: float = 8.0
@export var enemy_name_override: String = ""
@export var max_hp_override: int = 0
@export var move_speed_override: float = 0.0
@export var attack_damage_min_override: int = 0
@export var attack_damage_max_override: int = 0
@export var xp_reward_override: int = 0
@export var color_override: Color = Color.WHITE

var current_enemy: Node2D = null

func _ready() -> void:
	_spawn()

func _spawn() -> void:
	if enemy_scene == null:
		return
	current_enemy = enemy_scene.instantiate()
	current_enemy.global_position = global_position
	current_enemy.spawn_point = self
	if enemy_name_override != "":
		current_enemy.enemy_name = enemy_name_override
	if max_hp_override > 0:
		current_enemy.max_hp = max_hp_override
	if move_speed_override > 0.0:
		current_enemy.move_speed = move_speed_override
	if attack_damage_min_override > 0:
		current_enemy.attack_damage_min = attack_damage_min_override
	if attack_damage_max_override > 0:
		current_enemy.attack_damage_max = attack_damage_max_override
	if xp_reward_override > 0:
		current_enemy.xp_reward = xp_reward_override
	if color_override != Color.WHITE:
		current_enemy.get_node("ColorRect").color = color_override
	get_tree().current_scene.add_child(current_enemy)

func on_enemy_died() -> void:
	current_enemy = null
	await get_tree().create_timer(respawn_delay_s).timeout
	_spawn()
```

- [ ] **Step 2: Create the scene**

Run: `mcp__godot__create_scene` with `scenePath="scenes/entities/SpawnPoint.tscn"`, `rootNodeType="Node2D"`.
Run: `mcp__godot__attach_script` with `scenePath="scenes/entities/SpawnPoint.tscn"`, `nodePath="root"`, `scriptPath="scripts/entities/spawn_point.gd"`.
Run: `mcp__godot__save_scene` with `scenePath="scenes/entities/SpawnPoint.tscn"`.

- [ ] **Step 3: Commit**

```bash
git add scripts/entities/spawn_point.gd scenes/entities/SpawnPoint.tscn
git commit -m "$(cat <<'EOF'
Add SpawnPoint entity for respawning enemies

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

(No isolated `game_eval` check here — `SpawnPoint.enemy_scene` is unset until Task 11 places instances in the world with a real scene assigned, so behavior is verified there.)

---

### Task 11: Thornfield Meadow world scene

**Files:**
- Create: `scenes/world/ThornfieldMeadow.tscn`
- Modify: `scenes/Main.tscn` (add World instance)

- [ ] **Step 1: Create the zone scene**

Run: `mcp__godot__create_scene` with `scenePath="scenes/world/ThornfieldMeadow.tscn"`, `rootNodeType="Node2D"`.

- [ ] **Step 2: Add a background**

Run: `mcp__godot__add_node` with `scenePath="scenes/world/ThornfieldMeadow.tscn"`, `parentNodePath="root"`, `nodeType="ColorRect"`, `nodeName="Background"`, `properties={"position": {"x": -400, "y": -300}, "size": {"x": 800, "y": 600}, "color": {"r": 0.35, "g": 0.55, "b": 0.25, "a": 1.0}}`.

- [ ] **Step 3: Add three spawn points**

Run `mcp__godot__add_node` three times, each `scenePath="scenes/world/ThornfieldMeadow.tscn"`, `parentNodePath="root"`, `nodeType="Node2D"` — but since `SpawnPoint.tscn` must be *instanced* (not a bare `Node2D`) to inherit its script and exported properties, use the same instancing approach as Task 7 Step 6 (edit the `.tscn` text directly via `read_file`/`write_file` to add `[ext_resource]` + `[node ... instance=ExtResource(...)]` entries, or use `add_node` if it turns out to support an `instance` property pointing at `res://scenes/entities/SpawnPoint.tscn`). Create these three:

  - `SpawnPointWolf1` at position `(150, -80)`, with `enemy_scene = res://scenes/entities/Enemy.tscn`, `enemy_name_override = "Wolf"`, `max_hp_override = 18`, `move_speed_override = 70.0`, `attack_damage_min_override = 2`, `attack_damage_max_override = 4`, `xp_reward_override = 20`, `color_override = Color(0.5, 0.5, 0.5, 1.0)`.
  - `SpawnPointWolf2` at position `(-180, 100)`, same overrides as `SpawnPointWolf1`.
  - `SpawnPointBandit1` at position `(60, 150)`, with `enemy_scene = res://scenes/entities/Enemy.tscn`, `enemy_name_override = "Bandit"`, `max_hp_override = 35`, `move_speed_override = 45.0`, `attack_damage_min_override = 4`, `attack_damage_max_override = 8`, `xp_reward_override = 35`, `color_override = Color(0.55, 0.3, 0.15, 1.0)`.

Use `mcp__godot__read_file` after each addition to confirm the exported properties serialized correctly (they appear as extra lines under the node's `[node]` block in the `.tscn` text).

- [ ] **Step 4: Save the scene**

Run: `mcp__godot__save_scene` with `scenePath="scenes/world/ThornfieldMeadow.tscn"`.

- [ ] **Step 5: Instance World under Main**

Same instancing technique as Task 7 Step 6: add a child node to `scenes/Main.tscn` named `World`, instancing `res://scenes/world/ThornfieldMeadow.tscn`, positioned at `(0, 0)`.
Verify with `mcp__godot__read_file` on `scenes/Main.tscn`.

- [ ] **Step 6: Verify enemies spawn**

Run: `mcp__godot__run_project`.
Run: `mcp__godot__game_eval` with `code="return get_tree().get_nodes_in_group(\"enemies\").size()"`. Expected: `3`.
Run: `mcp__godot__game_eval` with:

```gdscript
var enemies = get_tree().get_nodes_in_group("enemies")
var names = []
for e in enemies:
	names.append(e.enemy_name)
names.sort()
return names
```

Expected: `["Bandit", "Wolf", "Wolf"]`.
Run: `mcp__godot__game_get_errors`. Expected: empty.
Run: `mcp__godot__stop_project`.

- [ ] **Step 7: Commit**

```bash
git add scenes/world/ThornfieldMeadow.tscn scenes/Main.tscn
git commit -m "$(cat <<'EOF'
Add Thornfield Meadow zone with wolf and bandit spawn points

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Camera controller

**Files:**
- Modify: `scripts/autoload/game_state.gd` (already has `camera` var from Task 2 — no change needed, just confirming it's used here)
- Create: `scripts/ui/camera_controller.gd`
- Modify: `scenes/Main.tscn` (add Camera2D)

- [ ] **Step 1: Write the script**

Run: `mcp__godot__create_script` with `scriptPath="scripts/ui/camera_controller.gd"`, `source`:

```gdscript
extends Camera2D

const ZOOM_STEP := 0.1
const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.5

var following := true
var dragging := false
var drag_start_mouse := Vector2.ZERO
var drag_start_camera := Vector2.ZERO

func _ready() -> void:
	GameState.camera = self

func _process(delta: float) -> void:
	if following and GameState.character and is_instance_valid(GameState.character):
		global_position = GameState.character.global_position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				following = false
				drag_start_mouse = event.position
				drag_start_camera = global_position
			else:
				dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom = (zoom + Vector2.ONE * ZOOM_STEP).clamp(Vector2.ONE * MIN_ZOOM, Vector2.ONE * MAX_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom = (zoom - Vector2.ONE * ZOOM_STEP).clamp(Vector2.ONE * MIN_ZOOM, Vector2.ONE * MAX_ZOOM)
	elif event is InputEventMouseMotion and dragging:
		var delta_mouse := event.position - drag_start_mouse
		global_position = drag_start_camera - delta_mouse / zoom

func recenter() -> void:
	following = true
```

- [ ] **Step 2: Add Camera2D to Main**

Run: `mcp__godot__add_node` with `scenePath="scenes/Main.tscn"`, `parentNodePath="root"`, `nodeType="Camera2D"`, `nodeName="Camera2D"`, `properties={"enabled": true}`.
Run: `mcp__godot__attach_script` with `scenePath="scenes/Main.tscn"`, `nodePath="root/Camera2D"`, `scriptPath="scripts/ui/camera_controller.gd"`.
Run: `mcp__godot__save_scene` with `scenePath="scenes/Main.tscn"`.

- [ ] **Step 3: Verify it follows the character**

Run: `mcp__godot__run_project`.
Run: `mcp__godot__game_eval` with `code="return GameState.camera != null"`. Expected: `true`.
Wait roughly 1 second (the character should have moved while wandering), then run: `mcp__godot__game_eval` with:

```gdscript
var cam_pos = GameState.camera.global_position
var char_pos = GameState.character.global_position
return cam_pos.distance_to(char_pos) < 5.0
```

Expected: `true` (camera is following, so it should be very close to the character's position).
Run: `mcp__godot__game_get_errors`. Expected: empty.
Run: `mcp__godot__stop_project`.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/camera_controller.gd scenes/Main.tscn
git commit -m "$(cat <<'EOF'
Add spectator camera with follow, pan, and zoom

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Unit frame UI

**Files:**
- Create: `scripts/ui/unit_frame.gd`
- Create: `scenes/ui/SpectatorUI.tscn` (created here, extended in Tasks 14–15)

- [ ] **Step 1: Write the script**

Run: `mcp__godot__create_script` with `scriptPath="scripts/ui/unit_frame.gd"`, `source`:

```gdscript
extends Control

@onready var hp_bar: ProgressBar = $HPBar
@onready var level_label: Label = $LevelLabel
@onready var xp_bar: ProgressBar = $XPBar
@onready var weapon_label: Label = $WeaponLabel
@onready var armor_label: Label = $ArmorLabel

func _ready() -> void:
	GameState.character_hp_changed.connect(_on_hp_changed)
	GameState.character_xp_changed.connect(_on_xp_changed)
	GameState.character_leveled_up.connect(_on_leveled_up)
	GameState.character_equipment_changed.connect(_on_equipment_changed)
	if GameState.character:
		_on_hp_changed(GameState.character.hp, GameState.character.max_hp)
		_on_leveled_up(GameState.character.level)

func _on_hp_changed(hp: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp

func _on_xp_changed(xp: int) -> void:
	var next_threshold: int = LevelingSystem.XP_THRESHOLDS[-1]
	if GameState.character:
		var lvl: int = GameState.character.level
		if lvl - 1 < LevelingSystem.XP_THRESHOLDS.size():
			next_threshold = LevelingSystem.XP_THRESHOLDS[lvl - 1]
	xp_bar.max_value = next_threshold
	xp_bar.value = xp

func _on_leveled_up(level: int) -> void:
	level_label.text = "Level %d" % level

func _on_equipment_changed(weapon_id: String, armor_id: String) -> void:
	weapon_label.text = "Weapon: %s" % (weapon_id if weapon_id != "" else "None")
	armor_label.text = "Armor: %s" % (armor_id if armor_id != "" else "None")
```

- [ ] **Step 2: Create SpectatorUI as a CanvasLayer**

Run: `mcp__godot__create_scene` with `scenePath="scenes/ui/SpectatorUI.tscn"`, `rootNodeType="CanvasLayer"`.

- [ ] **Step 3: Add the UnitFrame control and its children**

Run `mcp__godot__add_node` calls, all `scenePath="scenes/ui/SpectatorUI.tscn"`:
- `parentNodePath="root"`, `nodeType="Control"`, `nodeName="UnitFrame"`, `properties={"position": {"x": 16, "y": 16}, "size": {"x": 220, "y": 110}}`
- `parentNodePath="root/UnitFrame"`, `nodeType="ProgressBar"`, `nodeName="HPBar"`, `properties={"position": {"x": 0, "y": 0}, "size": {"x": 200, "y": 20}}`
- `parentNodePath="root/UnitFrame"`, `nodeType="Label"`, `nodeName="LevelLabel"`, `properties={"position": {"x": 0, "y": 24}, "text": "Level 1"}`
- `parentNodePath="root/UnitFrame"`, `nodeType="ProgressBar"`, `nodeName="XPBar"`, `properties={"position": {"x": 0, "y": 48}, "size": {"x": 200, "y": 12}}`
- `parentNodePath="root/UnitFrame"`, `nodeType="Label"`, `nodeName="WeaponLabel"`, `properties={"position": {"x": 0, "y": 66}, "text": "Weapon: None"}`
- `parentNodePath="root/UnitFrame"`, `nodeType="Label"`, `nodeName="ArmorLabel"`, `properties={"position": {"x": 0, "y": 88}, "text": "Armor: None"}`

- [ ] **Step 4: Attach the script and save**

Run: `mcp__godot__attach_script` with `scenePath="scenes/ui/SpectatorUI.tscn"`, `nodePath="root/UnitFrame"`, `scriptPath="scripts/ui/unit_frame.gd"`.
Run: `mcp__godot__save_scene` with `scenePath="scenes/ui/SpectatorUI.tscn"`.

- [ ] **Step 5: Verify it initializes without error in isolation**

Run: `mcp__godot__run_project` with `scene="scenes/ui/SpectatorUI.tscn"`.
Run: `mcp__godot__game_get_errors`. Expected: empty (confirms all `@onready` node paths resolve — `GameState.character` will be null in this isolated run, which the script already guards against).
Run: `mcp__godot__stop_project`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/unit_frame.gd scenes/ui/SpectatorUI.tscn
git commit -m "$(cat <<'EOF'
Add spectator unit frame UI

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: Activity log UI

**Files:**
- Create: `scripts/ui/activity_log.gd`
- Modify: `scenes/ui/SpectatorUI.tscn`

- [ ] **Step 1: Write the script**

Run: `mcp__godot__create_script` with `scriptPath="scripts/ui/activity_log.gd"`, `source`:

```gdscript
extends Control

const MAX_ENTRIES := 100

@onready var log_list: ItemList = $LogList

func _ready() -> void:
	GameState.activity_logged.connect(_on_logged)

func _on_logged(message: String) -> void:
	log_list.add_item(message)
	if log_list.item_count > MAX_ENTRIES:
		log_list.remove_item(0)
	log_list.ensure_current_is_visible()
```

- [ ] **Step 2: Add the ActivityLog control and its child**

Run `mcp__godot__add_node` calls, `scenePath="scenes/ui/SpectatorUI.tscn"`:
- `parentNodePath="root"`, `nodeType="Control"`, `nodeName="ActivityLog"`, `properties={"position": {"x": 16, "y": 400}, "size": {"x": 320, "y": 160}}`
- `parentNodePath="root/ActivityLog"`, `nodeType="ItemList"`, `nodeName="LogList"`, `properties={"position": {"x": 0, "y": 0}, "size": {"x": 320, "y": 160}}`

- [ ] **Step 3: Attach the script and save**

Run: `mcp__godot__attach_script` with `scenePath="scenes/ui/SpectatorUI.tscn"`, `nodePath="root/ActivityLog"`, `scriptPath="scripts/ui/activity_log.gd"`.
Run: `mcp__godot__save_scene` with `scenePath="scenes/ui/SpectatorUI.tscn"`.

- [ ] **Step 4: Verify it initializes without error in isolation**

Run: `mcp__godot__run_project` with `scene="scenes/ui/SpectatorUI.tscn"`.
Run: `mcp__godot__game_get_errors`. Expected: empty.
Run: `mcp__godot__stop_project`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/activity_log.gd scenes/ui/SpectatorUI.tscn
git commit -m "$(cat <<'EOF'
Add spectator activity log UI

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: Speed control UI (+ recenter)

**Files:**
- Create: `scripts/ui/speed_control.gd`
- Modify: `scenes/ui/SpectatorUI.tscn`

- [ ] **Step 1: Write the script**

Run: `mcp__godot__create_script` with `scriptPath="scripts/ui/speed_control.gd"`, `source`:

```gdscript
extends HBoxContainer

@onready var pause_button: Button = $PauseButton
@onready var speed1_button: Button = $Speed1Button
@onready var speed2_button: Button = $Speed2Button
@onready var speed4_button: Button = $Speed4Button
@onready var recenter_button: Button = $RecenterButton

func _ready() -> void:
	pause_button.pressed.connect(func(): Engine.time_scale = 0.0)
	speed1_button.pressed.connect(func(): Engine.time_scale = 1.0)
	speed2_button.pressed.connect(func(): Engine.time_scale = 2.0)
	speed4_button.pressed.connect(func(): Engine.time_scale = 4.0)
	recenter_button.pressed.connect(func():
		if GameState.camera:
			GameState.camera.recenter()
	)
```

- [ ] **Step 2: Add the SpeedControl container and its buttons**

Run `mcp__godot__add_node` calls, `scenePath="scenes/ui/SpectatorUI.tscn"`:
- `parentNodePath="root"`, `nodeType="HBoxContainer"`, `nodeName="SpeedControl"`, `properties={"position": {"x": 500, "y": 16}}`
- `parentNodePath="root/SpeedControl"`, `nodeType="Button"`, `nodeName="PauseButton"`, `properties={"text": "Pause"}`
- `parentNodePath="root/SpeedControl"`, `nodeType="Button"`, `nodeName="Speed1Button"`, `properties={"text": "1x"}`
- `parentNodePath="root/SpeedControl"`, `nodeType="Button"`, `nodeName="Speed2Button"`, `properties={"text": "2x"}`
- `parentNodePath="root/SpeedControl"`, `nodeType="Button"`, `nodeName="Speed4Button"`, `properties={"text": "4x"}`
- `parentNodePath="root/SpeedControl"`, `nodeType="Button"`, `nodeName="RecenterButton"`, `properties={"text": "Recenter"}`

- [ ] **Step 3: Attach the script and save**

Run: `mcp__godot__attach_script` with `scenePath="scenes/ui/SpectatorUI.tscn"`, `nodePath="root/SpeedControl"`, `scriptPath="scripts/ui/speed_control.gd"`.
Run: `mcp__godot__save_scene` with `scenePath="scenes/ui/SpectatorUI.tscn"`.

- [ ] **Step 4: Verify it initializes without error in isolation**

Run: `mcp__godot__run_project` with `scene="scenes/ui/SpectatorUI.tscn"`.
Run: `mcp__godot__game_get_errors`. Expected: empty.
Run: `mcp__godot__stop_project`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/speed_control.gd scenes/ui/SpectatorUI.tscn
git commit -m "$(cat <<'EOF'
Add spectator speed control UI with recenter

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: Final integration

**Files:**
- Modify: `scenes/Main.tscn` (add SpectatorUI instance)

- [ ] **Step 1: Instance SpectatorUI under Main**

Using the same instancing technique as Task 7 Step 6, add a child node to `scenes/Main.tscn` named `UI`, instancing `res://scenes/ui/SpectatorUI.tscn`.
Run: `mcp__godot__save_scene` with `scenePath="scenes/Main.tscn"`.

- [ ] **Step 2: Full run verification**

Run: `mcp__godot__run_project` with `projectPath="C:\Users\n1njaz\Desktop\New folder"` (main scene, no `scene` override).
Run: `mcp__godot__game_get_errors`. Expected: empty.
Run: `mcp__godot__game_screenshot`. Expected: a visible green meadow, a blue square (character), and grey/brown squares (wolves/bandit) somewhere on screen.
Run: `mcp__godot__game_eval` with:

```gdscript
var ui = get_node("/root/Main/UI")
var unit_frame = ui.get_node("UnitFrame")
return unit_frame.hp_bar.value == GameState.character.hp
```

Expected: `true` (confirms the UI is actually reading live character state, not just displaying static text).
Run: `mcp__godot__stop_project`.

- [ ] **Step 3: Commit**

```bash
git add scenes/Main.tscn
git commit -m "$(cat <<'EOF'
Wire spectator UI into the main scene

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: Extended playtest verification

**Files:** none (verification only; fix forward in the relevant file if something's broken)

- [ ] **Step 1: Run unattended and observe**

Run: `mcp__godot__run_project`.
Run: `mcp__godot__game_eval` with `code="Engine.time_scale = 8.0"` to speed through the observation window faster than real time.
Wait, then run: `mcp__godot__game_get_logs` to see the accumulated activity-log print output (each `GameState.log_event` call also does `print()`, so this doubles as an offline transcript).
Repeat waiting + `game_get_logs` a few times across a couple of minutes of wall-clock time (equivalent to ~15+ simulated minutes at 8x).

- [ ] **Step 2: Check against the spec's "done" criteria**

Using the accumulated logs plus targeted `game_eval` calls, confirm:
- The log shows multiple distinct states occurring (`wander`, `chase`, `combat`, and ideally `flee`/`rest`/`loot`) — not stuck repeating one line.
- `mcp__godot__game_eval` with `code="return GameState.character.level"` returns `> 1` at least once during the run (leveling occurred).
- The log contains at least one `"Equipped ..."` line (auto-equip occurred).
- If HP ever hit 0, the log contains `"Character died - respawning"` followed by the character continuing to act afterward (respawn worked, simulation didn't stall).

- [ ] **Step 3: Fix forward if anything is broken**

If the FSM gets stuck (same state repeating with no change for a long stretch of simulated time), or `game_get_errors` shows runtime errors, identify the offending script from the error/log output, fix it in place (in whichever file from Tasks 3–16 is responsible), re-run this task's verification, and commit the fix separately from this task (no combined step — treat it as its own small commit, same message format as other tasks, describing the actual bug fixed).

- [ ] **Step 4: Stop the project**

Run: `mcp__godot__stop_project`.

- [ ] **Step 5: Final commit (if Step 3 required no changes, skip this)**

Only needed if Step 3 produced fixes that weren't already committed there.

---

## Self-review notes

- **Spec coverage:** every section of the design spec maps to a task — AI FSM → Task 3 + Task 7; leveling → Task 4 + Task 7; combat → Task 5 + Tasks 7/9; loot → Task 6 + Tasks 7/8/9; world/zone → Task 11; unit frame/log/camera/speed UI → Tasks 12–15; error handling (state deadlock, death/respawn, spawn failure) → built into Task 7/9/10's `wander` default and `_die()`/`on_enemy_died()` logic; the "how we'll know it's done" criteria → Task 17.
- **Type/signature consistency checked:** `AIDecision.resolve_state(context) -> Dictionary` (Task 3) matches its call site in `character.gd` (Task 7). `LevelingSystem.apply_xp(level, xp, gained) -> Dictionary` with keys `level/xp/leveled_up/hp_bonus/damage_bonus` (Task 4) matches `Character.gain_xp` (Task 7) and `UnitFrame._on_xp_changed` (Task 13). `CombatSystem.roll_damage`/`is_off_cooldown` signatures (Task 5) match both `character.gd` and `enemy.gd` (Tasks 7, 9). `LootTable.ITEMS`/`should_equip`/`roll_drop` (Task 6) match `character.gd`'s `_pickup_item` and `enemy.gd`'s `_drop_loot` (Tasks 7, 9). `enemy_name`, `spawn_point`, `max_hp`, `move_speed`, `attack_damage_min/max`, `xp_reward` exported vars on `Enemy` (Task 9) match every override field read/written in `SpawnPoint` (Task 10) and read in `Character._build_context` (Task 7).
- **Known tooling risk flagged, not hidden:** exact serialization format for Vector2/Color properties passed to `add_node`/`modify_scene_node`, and whether `add_node` supports scene instancing directly, aren't confirmed from the tool schemas alone — every task that depends on this has an explicit verify-and-fix-if-wrong step rather than assuming success silently.
