# Job Switching (Phase 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The hero keeps a level, XP and gear set per job and changes job by itself at a Job Crystal in Thornfield Meadow, training all seven jobs.

**Architecture:** Pure helpers `JobState` and `JobSwitch` (catch-up level, inherited gear, when a switch is due, which job next) are unit-tested. `Character` keeps a `job_states` dictionary and swaps the active job's level/XP/gear in and out in one `_change_job` function; a new AI state `job_change` walks to the crystal like the quest state. A `GameState.job_switching_enabled` flag (off by default in the sim) keeps phase-1 behavior available for regression.

**Tech Stack:** Godot 4.7 (mono) GDScript, headless tests `tests/run_tests.gd`, `tests/sim` balance harness.

Spec: `docs/superpowers/specs/2026-09-27-job-switching-design.md`.

**Conventions for every task**

- Work in a worktree: from `main`, `git worktree add .claude/worktrees/job-switching -b job-switching`; run the headless editor import twice in it (`"$GODOT" --headless --path . --editor --quit`) and once more after creating new `class_name` scripts or scenes (commit the generated `.gd.uid` files, the repo tracks them).
- `GODOT="C:/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"`.
- "Run the tests": `"$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|checks"`. Baseline `13532 checks, 0 failures`.
- Every suite's `run(t)` ends with `t.done()`; register new suites at the end of `SUITES` in `tests/run_tests.gd`.
- Working tree is CRLF, commits LF: edit with the Edit tool (or Python `newline=''`).
- Never stage `assets/**/*.import`, `docs/screenshots/*.import`, `project.godot`.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- GDScript quirks: members not on the declared type (`Node2D`) are a parse error (use untyped `var`, `.call`, `.get`); guard `get_meta` with `has_meta`; no integer `/` division; freed Objects compare equal to null, so `is_instance_valid` first; do NOT give new nodes a property named `rng` (the sim seeds every node that has one, shifting later seeds).
- **Regression rule:** with `GameState.job_switching_enabled = false` (the sim default `switching=0`) every seeded run must be identical to the phase-1 logs in `$TEMP/simJC_<job>` (12 seeds each, 45 min, `trait=steady`; produced on `main` before this phase). If they are missing, regenerate them on `main` first: `tests/sim/run_batch.sh "$TEMP/simJC_<job>" 45 "<job>" "$(seq -s ' ' 1 12)" 12 trait=steady` for each of warrior, mage, white_mage, thief, black_belt, dragoon, red_mage.

---

### Task 1: `JobState` and `JobSwitch` (pure)

**Files:**
- Create: `scripts/systems/job_state.gd`, `scripts/systems/job_switch.gd`
- Create: `tests/suite_job_state.gd`, `tests/suite_job_switch.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/suite_job_state.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	var fresh := JobState.new()
	t.check_eq(fresh.level, 1, "default level")
	t.check_eq(fresh.xp, 0, "default xp")
	t.check_eq(fresh.equipment, {}, "default equipment is empty")

	var made := JobState.create(5, 900, {"weapon": "rusty_sword"})
	t.check_eq(made.level, 5, "create sets level")
	t.check_eq(made.xp, 900, "create sets xp")
	t.check_eq(made.equipment, {"weapon": "rusty_sword"}, "create sets equipment")

	var copy := made.duplicate()
	copy.equipment["head"] = "iron_helm"
	copy.level = 6
	t.check_eq(made.equipment, {"weapon": "rusty_sword"}, "duplicate does not share the equipment dictionary")
	t.check_eq(made.level, 5, "duplicate does not share level")
	var input := {"weapon": "rusty_sword"}
	var stored := JobState.create(1, 0, input)
	input["chest"] = "leather_armor"
	t.check_eq(stored.equipment, {"weapon": "rusty_sword"}, "create copies the equipment it is given")
	t.done()
```

Create `tests/suite_job_switch.gd`:

```gdscript
extends RefCounted

func _item_at_level(min_level: int, max_level: int) -> String:
	for id in LootTable.ITEMS.keys():
		var def: Dictionary = LootTable.ITEMS[id]
		if LootTable.SLOTS.has(String(def.get("slot", ""))):
			var req := int(def.get("level_req", 1))
			if req >= min_level and req <= max_level:
				return id
	return ""

func run(t) -> void:
	# catch_up_level
	t.check_eq(JobSwitch.catch_up_level({}), 1, "no jobs taken: level 1")
	t.check_eq(JobSwitch.catch_up_level({"warrior": 10}), 8, "best minus 2")
	t.check_eq(JobSwitch.catch_up_level({"warrior": 2}), 1, "never below 1")
	t.check_eq(JobSwitch.catch_up_level({"warrior": 3, "thief": 6}), 4, "uses the best job")

	# starting_xp
	t.check_eq(JobSwitch.starting_xp(1), 0, "level 1 starts at 0 XP")
	t.check_eq(JobSwitch.starting_xp(2), LevelingSystem.XP_THRESHOLDS[0], "level 2 threshold")
	t.check_eq(JobSwitch.starting_xp(8), LevelingSystem.XP_THRESHOLDS[6], "level 8 threshold")

	# inherit_equipment
	var low := _item_at_level(1, 1)
	var high := _item_at_level(5, 10)
	t.check(low != "" and high != "", "test data: a level-1 item and a level-5+ item exist")
	var slot_low: String = LootTable.ITEMS[low]["slot"]
	var slot_high: String = LootTable.ITEMS[high]["slot"]
	if slot_low != slot_high:
		var gear := {slot_low: low, slot_high: high}
		var inherited := JobSwitch.inherit_equipment(gear, 3)
		t.check_eq(inherited.get(slot_low, ""), low, "a usable item is kept")
		t.check(not inherited.has(slot_high), "an item above the level is dropped")
		t.check_eq(JobSwitch.inherit_equipment(gear, 10).size(), 2, "everything usable at level 10 is kept")
		t.check_eq(gear.size(), 2, "the input dictionary is not modified")
	t.check_eq(JobSwitch.inherit_equipment({}, 5), {}, "empty gear stays empty")

	# switch_due
	t.check(JobSwitch.switch_due(10, [10, 4, 1], "cap"), "cap: due when another job is below the cap")
	t.check(not JobSwitch.switch_due(10, [10, 10], "cap"), "cap: not due when every other job is capped")
	t.check(not JobSwitch.switch_due(9, [1], "cap"), "cap: not due below the cap")
	t.check(JobSwitch.switch_due(8, [6], "loop"), "loop: gap of exactly 2 is due")
	t.check(not JobSwitch.switch_due(8, [7], "loop"), "loop: gap of 1 is not due")
	t.check(not JobSwitch.switch_due(5, [], "loop"), "loop: no other jobs")
	t.check(JobSwitch.switch_due(10, [8, 10], "loop"), "loop at the cap with a job 2 below")
	t.check(not JobSwitch.switch_due(5, [1], "nope"), "unknown reason is never due")

	# pick_next_job
	var order := AbilityTable.job_ids()
	var others: Array = []
	for id in order:
		if id != "warrior":
			others.append(id)
	t.check_eq(JobSwitch.pick_next_job("warrior", {"warrior": 10}, "steady", 0.0), others[0], "untaken jobs count as level 1: first in order at roll 0")
	t.check_eq(JobSwitch.pick_next_job("warrior", {"warrior": 10}, "steady", 0.999), others[others.size() - 1], "last in order at roll 0.999")
	t.check_eq(JobSwitch.pick_next_job("warrior", {"warrior": 10, "dragoon": 3}, "steady", 0.0), others[0], "a taken job above level 1 is not the lowest")

	var capped := {}
	for id in order:
		capped[id] = 10
	t.check_eq(JobSwitch.pick_next_job("warrior", capped, "steady", 0.5), "", "everything capped: no pick")
	capped["thief"] = 4
	t.check_eq(JobSwitch.pick_next_job("warrior", capped, "steady", 0.5), "thief", "capped jobs are excluded")
	t.check_eq(JobSwitch.pick_next_job("thief", capped, "steady", 0.5), "", "the active job is excluded")

	# trait nudges (within 2 levels of the lowest)
	var levels := {"warrior": 10, "black_belt": 1, "thief": 1, "dragoon": 1, "white_mage": 2, "mage": 1, "red_mage": 1}
	t.check_eq(JobSwitch.pick_next_job("warrior", levels, "steady", 0.0), "black_belt", "steady: lowest level pool")
	t.check_eq(JobSwitch.pick_next_job("warrior", levels, "cautious", 0.0), "white_mage", "cautious prefers the healer within 2 levels")
	levels["white_mage"] = 5
	t.check_eq(JobSwitch.pick_next_job("warrior", levels, "cautious", 0.0), "black_belt", "cautious: healer too far above the lowest, base pick")

	var rlevels := {"warrior": 10, "white_mage": 1, "black_belt": 2, "thief": 10, "dragoon": 10, "mage": 10, "red_mage": 10}
	t.check_eq(JobSwitch.pick_next_job("warrior", rlevels, "steady", 0.0), "white_mage", "steady picks the lowest")
	t.check_eq(JobSwitch.pick_next_job("warrior", rlevels, "reckless", 0.0), "black_belt", "reckless prefers melee or magic")

	var glevels := {"warrior": 10, "thief": 3, "black_belt": 1, "dragoon": 10, "white_mage": 10, "mage": 10, "red_mage": 10}
	t.check_eq(JobSwitch.pick_next_job("warrior", glevels, "greedy", 0.0), "thief", "greedy prefers the thief within 2 levels")
	glevels["thief"] = 4
	t.check_eq(JobSwitch.pick_next_job("warrior", glevels, "greedy", 0.0), "black_belt", "greedy: thief too far above the lowest")

	t.check_eq(JobSwitch.pick_next_job("warrior", {"warrior": 10, "thief": 9}, "explorer", 0.0), others[0], "explorer: any candidate, first at roll 0")
	t.check_eq(JobSwitch.pick_next_job("warrior", {"warrior": 10}, "explorer", 0.999), others[others.size() - 1], "explorer: last at roll 0.999")
	t.check_eq(JobSwitch.pick_next_job("warrior", levels, "steady", 0.3), JobSwitch.pick_next_job("warrior", levels, "steady", 0.3), "deterministic for a given roll")
	t.done()
```

Register both suites at the end of `SUITES` in `tests/run_tests.gd`.

- [ ] **Step 2: Run the tests to verify they fail**

Expected: SCRIPT ERROR / suite failed to load for `JobState` and `JobSwitch`.

- [ ] **Step 3: Implement `JobState`**

Create `scripts/systems/job_state.gd`:

```gdscript
class_name JobState
extends RefCounted

## One job's progress for the hero: level, cumulative XP and its own gear set.

var level: int = 1
var xp: int = 0
var equipment: Dictionary = {}

static func create(new_level: int, new_xp: int, new_equipment: Dictionary) -> JobState:
	var state := JobState.new()
	state.level = new_level
	state.xp = new_xp
	state.equipment = new_equipment.duplicate()
	return state

func duplicate() -> JobState:
	return JobState.create(level, xp, equipment)
```

- [ ] **Step 4: Implement `JobSwitch`**

Create `scripts/systems/job_switch.gd`:

```gdscript
class_name JobSwitch
extends RefCounted

## Pure rules for the hero's job changes: the level a job starts at, the gear
## it inherits, when a change is due and which job comes next.

## A job's level is at most this many levels below the best job when first taken.
const CATCH_UP_GAP := 2
## "loop" trigger: some other job is at least this many levels below the active one.
const LOOP_GAP := 2
## A trait's preferred job is only used within this many levels of the lowest.
const NUDGE_WINDOW := 2

static func catch_up_level(levels: Dictionary) -> int:
	var best := 1
	for id in levels.keys():
		best = maxi(best, int(levels[id]))
	return maxi(1, best - CATCH_UP_GAP)

## Cumulative XP a job has on reaching `level` (0 at level 1).
static func starting_xp(level: int) -> int:
	if level <= 1:
		return 0
	return int(LevelingSystem.XP_THRESHOLDS[mini(level, LevelingSystem.MAX_LEVEL) - 2])

## The outgoing gear set filtered to items usable at `level` (a copy).
static func inherit_equipment(equipment: Dictionary, level: int) -> Dictionary:
	var result := {}
	for slot in equipment.keys():
		var item_id := String(equipment[slot])
		if item_id != "" and ItemScoring.meets_level(item_id, level):
			result[slot] = item_id
	return result

## `reason` is "cap" (the active job is at the level cap) or "loop" (arrived in
## the meadow on the zone loop). `other_levels` are the levels of every other
## job, untaken jobs counted as 1.
static func switch_due(active_level: int, other_levels: Array, reason: String) -> bool:
	if reason == "cap":
		if active_level < LevelingSystem.MAX_LEVEL:
			return false
		for level in other_levels:
			if int(level) < LevelingSystem.MAX_LEVEL:
				return true
		return false
	if reason == "loop":
		for level in other_levels:
			if int(level) <= active_level - LOOP_GAP:
				return true
		return false
	return false

## The next job, or "" when every other job is at the cap. `levels` maps the
## jobs taken so far to their level (missing jobs count as level 1); `roll`
## (0..1) picks deterministically inside the candidate pool.
static func pick_next_job(active_id: String, levels: Dictionary, trait_id: String, roll: float, job_ids: Array = AbilityTable.JOB_ORDER) -> String:
	var candidates: Array = []
	var lowest := LevelingSystem.MAX_LEVEL + 1
	for id in job_ids:
		if id == active_id:
			continue
		var level := int(levels.get(id, 1))
		if level >= LevelingSystem.MAX_LEVEL:
			continue
		candidates.append(id)
		lowest = mini(lowest, level)
	if candidates.is_empty():
		return ""
	var pool: Array = []
	if trait_id == "explorer":
		pool = candidates
	else:
		var preferred: Array = []
		for id in candidates:
			if _prefers(trait_id, id) and int(levels.get(id, 1)) <= lowest + NUDGE_WINDOW:
				preferred.append(id)
		if not preferred.is_empty():
			var preferred_lowest := LevelingSystem.MAX_LEVEL + 1
			for id in preferred:
				preferred_lowest = mini(preferred_lowest, int(levels.get(id, 1)))
			for id in preferred:
				if int(levels.get(id, 1)) == preferred_lowest:
					pool.append(id)
		else:
			for id in candidates:
				if int(levels.get(id, 1)) == lowest:
					pool.append(id)
	var index := mini(int(clampf(roll, 0.0, 0.999999) * float(pool.size())), pool.size() - 1)
	return String(pool[index])

static func _prefers(trait_id: String, job_id: String) -> bool:
	var role := String(AbilityTable.CLASSES.get(job_id, {}).get("role", ""))
	match trait_id:
		"cautious":
			return role == "tank" or role == "healer"
		"reckless":
			return role == "melee" or role == "magic"
		"greedy":
			return job_id == "thief"
	return false
```

- [ ] **Step 5: Import and run the tests**

Import once, then run the tests. Expected `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/job_state.gd scripts/systems/job_state.gd.uid scripts/systems/job_switch.gd scripts/systems/job_switch.gd.uid tests/suite_job_state.gd tests/suite_job_state.gd.uid tests/suite_job_switch.gd tests/suite_job_switch.gd.uid tests/run_tests.gd
git commit -m "Add JobState and JobSwitch pure helpers

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `AIDecision` job_change state

**Files:**
- Modify: `scripts/ai/ai_decision.gd`
- Modify: `tests/suite_ai_decision.gd`

- [ ] **Step 1: Write the failing test**

In `tests/suite_ai_decision.gd`, before the final `t.done()` add:

```gdscript
	# job_change: below flee/rest/combat and the quest board, above chase
	var crystal := _ctx(1.0, false)
	crystal["job_change_ready"] = true
	t.check_eq(AIDecision.resolve_state(crystal)["state"], "job_change", "wants a job change, nothing else to do: job_change")
	var crystal_chase := _ctx(1.0, true)
	crystal_chase["job_change_ready"] = true
	t.check_eq(AIDecision.resolve_state(crystal_chase)["state"], "job_change", "job_change beats chase")
	var crystal_fight := _ctx(1.0, true, true)
	crystal_fight["job_change_ready"] = true
	t.check_eq(AIDecision.resolve_state(crystal_fight)["state"], "combat", "combat beats job_change")
	var crystal_hurt := _ctx(0.05, true, true)
	crystal_hurt["job_change_ready"] = true
	t.check_eq(AIDecision.resolve_state(crystal_hurt)["state"], "flee", "flee beats job_change")
	var crystal_rest := _ctx(0.2, false)
	crystal_rest["job_change_ready"] = true
	t.check_eq(AIDecision.resolve_state(crystal_rest)["state"], "rest", "rest beats job_change")
	var crystal_quest := _ctx(1.0, false)
	crystal_quest["job_change_ready"] = true
	crystal_quest["quest_giver_in_zone"] = true
	crystal_quest["quest_ready"] = true
	t.check_eq(AIDecision.resolve_state(crystal_quest)["state"], "quest", "a quest to turn in comes first")
	t.check(String(AIDecision.resolve_state(crystal)["reason"]).contains("crystal"), "the reason mentions the crystal")
	t.check_eq(AIDecision.resolve_state(_ctx(1.0, false))["state"], "wander", "no key: unchanged")
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: FAIL on the first new check.

- [ ] **Step 3: Implement**

In `scripts/ai/ai_decision.gd`: extend the doc comment's key list and returned states with `job_change_ready` (bool, optional) and `"job_change"`. After `var quest_ready ...` add `var job_change_ready: bool = bool(context.get("job_change_ready", false))`. Immediately after the `if quest_giver_in_zone and quest_ready:` block (and before `if hostile_in_aggro_range:` chase) add:

```gdscript
	if job_change_ready:
		return {"state": "job_change", "reason": "Heading to the job crystal"}
```

- [ ] **Step 4: Run the tests to verify they pass**

Expected `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scripts/ai/ai_decision.gd tests/suite_ai_decision.gd
git commit -m "AIDecision: job_change state for the job crystal

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Switching in `Character`, `GameState`, sim flag

**Files:**
- Modify: `scripts/autoload/game_state.gd`
- Modify: `scripts/entities/character.gd`
- Modify: `tests/sim/sim_run.gd`

Node wiring: verified by the tests staying green, the regression (Task 6) and the live check (Task 7).

- [ ] **Step 1: `GameState`**

Add next to the other run-level flags:

```gdscript
## The hero changes job by itself at the crystal (phase 2). The balance sim
## turns this off unless it is measuring the feature (`switching=1`).
var job_switching_enabled: bool = true

## The hero changed job (ids are AbilityTable class ids; `level` is the new job's level).
signal job_changed(old_id: String, new_id: String, level: int)
## A job reached the level cap for the first time.
signal job_mastered(job_id: String)
```

- [ ] **Step 2: `Character` fields and constants**

Near the other vars add:

```gdscript
const CRYSTAL_ZONE_ID := "thornfield_meadow"
const CRYSTAL_RANGE := 30.0

## Per-job progress for jobs the hero has taken (job id -> JobState). The
## active job's level, xp and equipment live in `level`, `xp` and `equipment`.
var job_states: Dictionary = {}
var jobs_mastered: Array = []
var wants_job_change: bool = false
var job_change_reason: String = ""
var _left_crystal_zone: bool = false
## Level-1 base stats, captured in _ready; base stats at a level are derived
## from these (identical to what gain_xp accumulates).
var _lvl1_hp: int = 0
var _lvl1_damage_min: int = 0
var _lvl1_damage_max: int = 0
```

Add `"job_change": "Changing job",` to `STATE_DISPLAY_NAMES`. In `_ready`, right after `base_damage_max = attack_damage_max` (the lines that set the base stats) add:

```gdscript
	_lvl1_hp = base_max_hp - (level - 1) * LevelingSystem.HP_PER_LEVEL
	_lvl1_damage_min = base_damage_min - (level - 1) * LevelingSystem.DAMAGE_PER_LEVEL
	_lvl1_damage_max = base_damage_max - (level - 1) * LevelingSystem.DAMAGE_PER_LEVEL
```

- [ ] **Step 3: Helpers and `_change_job`**

Add to `character.gd`:

```gdscript
## Levels of every taken job including the active one (id -> level).
func _taken_levels() -> Dictionary:
	var levels := {}
	for id in job_states.keys():
		levels[id] = (job_states[id] as JobState).level
	levels[character_class] = level
	return levels

## Levels of every job except the active one, untaken jobs counted as 1.
func _other_levels() -> Array:
	var taken := _taken_levels()
	var result: Array = []
	for id in AbilityTable.job_ids():
		if id != character_class:
			result.append(int(taken.get(id, 1)))
	return result

func _set_base_stats_for_level(new_level: int) -> void:
	base_max_hp = _lvl1_hp + (new_level - 1) * LevelingSystem.HP_PER_LEVEL
	base_damage_min = _lvl1_damage_min + (new_level - 1) * LevelingSystem.DAMAGE_PER_LEVEL
	base_damage_max = _lvl1_damage_max + (new_level - 1) * LevelingSystem.DAMAGE_PER_LEVEL

## Swaps to another job: the outgoing job's level, XP and gear are stored, the
## new job's are loaded (created on first use with the catch-up level and
## inherited gear). Everything else (quests, gold, party, codex) is shared.
func _change_job(new_id: String) -> void:
	if new_id == "" or new_id == character_class or not AbilityTable.CLASSES.has(new_id):
		return
	var old_id := character_class
	job_states[old_id] = JobState.create(level, xp, equipment)
	var state: JobState
	if job_states.has(new_id):
		state = job_states[new_id]
	else:
		var start_level := JobSwitch.catch_up_level(_taken_levels())
		state = JobState.create(start_level, JobSwitch.starting_xp(start_level), JobSwitch.inherit_equipment(equipment, start_level))
	character_class = new_id
	class_def = AbilityTable.CLASSES[new_id]
	max_resource = float(class_def.get("max_resource", 0.0))
	sprite.modulate = class_def.get("sprite_tint", Color(1.0, 1.0, 1.0, 1.0))
	level = state.level
	xp = state.xp
	equipment = state.equipment.duplicate()
	_set_base_stats_for_level(level)
	_recompute_stats()
	hp = max_hp
	resource_amount = 0.0
	ability_cooldowns.clear()
	wants_job_change = false
	job_change_reason = ""
	_left_crystal_zone = false
	GameState.log_event("Changed job: %s -> %s (level %d)" % [AbilityTable.job_name(old_id), AbilityTable.job_name(new_id), level])
	GameState.emit_signal("job_changed", old_id, new_id, level)
	GameState.emit_signal("character_equipment_changed", equipment.duplicate())
	GameState.emit_signal("character_hp_changed", hp, max_hp)
	GameState.emit_signal("character_resource_changed", resource_amount, max_resource)
	GameState.emit_signal("character_xp_changed", xp)

## Sets the "go to the crystal" flag when a switch is due for `reason`.
func _check_job_change(reason: String) -> void:
	if not GameState.job_switching_enabled or wants_job_change:
		return
	if JobSwitch.switch_due(level, _other_levels(), reason):
		wants_job_change = true
		job_change_reason = reason
```

- [ ] **Step 4: Triggers**

1. `gain_xp`: after `xp = result["xp"]` and the existing level-up block (before the final `character_xp_changed` emit) add:

```gdscript
	if level >= LevelingSystem.MAX_LEVEL and not jobs_mastered.has(character_class):
		jobs_mastered.append(character_class)
		GameState.emit_signal("job_mastered", character_class)
		_check_job_change("cap")
```

2. `_sync_current_zone`: after `current_zone_id = zone_id` add tracking, and after the `_recruit_companions_in_zone(zone_id)` call at the end:

```gdscript
	if zone_id != CRYSTAL_ZONE_ID:
		_left_crystal_zone = true
	elif _left_crystal_zone:
		_left_crystal_zone = false
		_check_job_change("loop")
```

(Put the `if zone_id != CRYSTAL_ZONE_ID` block at the very end of the function so it runs after companions are recruited.)

- [ ] **Step 5: The crystal state and travel override**

1. `_build_context`: add to the dictionary literal

```gdscript
		"job_change_ready": _job_crystal_here() != null,
```

and change `ready_to_travel` so a pending change leaves other zones at once: prefix the expression with `(wants_job_change and current_zone_id != CRYSTAL_ZONE_ID) or `. Also make the next-zone name in the context follow the override: where `next_zone_id` is computed (`if next_zone_id == "": next_zone_id = ZoneTable.next_zone_id(...)`), add `if wants_job_change: next_zone_id = CRYSTAL_ZONE_ID` after it.

2. Add the finder:

```gdscript
## The crystal in the current zone if a job change is pending, else null.
func _job_crystal_here() -> Node2D:
	if not wants_job_change:
		return null
	var crystal := _find_nearest_in_group("job_crystals")
	if crystal != null and _zone_id_for_position(crystal.global_position) == current_zone_id:
		return crystal
	return null
```

3. `_act`: add a `match` arm next to `"quest"`:

```gdscript
		"job_change":
			var crystal := _job_crystal_here()
			if crystal:
				var to_crystal := crystal.global_position - global_position
				if to_crystal.length() <= CRYSTAL_RANGE:
					_change_job(JobSwitch.pick_next_job(character_class, _taken_levels(), character_trait, rng.randf()))
					wants_job_change = false
				else:
					_move_toward(to_crystal, MOVE_SPEED)
			base_anim = "walk"
```

(`_change_job` already clears the flag; the explicit `wants_job_change = false` also covers `pick_next_job` returning `""`.) Note `rng.randf()` is only called when the character is at the crystal, so seeded runs with switching off never reach it.

4. `_do_travel`: after the existing `if travel_destination_id == "": ...` block add

```gdscript
	if wants_job_change and travel_destination_id != CRYSTAL_ZONE_ID:
		travel_destination_id = CRYSTAL_ZONE_ID
```

- [ ] **Step 6: Sheet snapshot**

In `get_sheet_snapshot()` add:

```gdscript
		"jobs": _job_rows(),
```

with

```gdscript
func _job_rows() -> Array:
	var rows: Array = []
	for id in AbilityTable.job_ids():
		var row_level := 0
		if id == character_class:
			row_level = level
		elif job_states.has(id):
			row_level = (job_states[id] as JobState).level
		rows.append({"id": id, "name": AbilityTable.job_name(id), "level": row_level, "active": id == character_class})
	return rows
```

- [ ] **Step 7: Sim flag**

In `tests/sim/sim_run.gd` `_ready`, next to the other `GameState` flags add `GameState.job_switching_enabled = args.get("switching", "0") == "1"` (parse `args` before it if needed) and document `switching=0|1` (default 0) in the header comment.

- [ ] **Step 8: Tests and parse**

Run the tests (`0 failures`) and `"$GODOT" --headless --path . --quit 2>&1 | grep -iE "error|parse"` (nothing about the changed files).

- [ ] **Step 9: Commit**

```bash
git add scripts/autoload/game_state.gd scripts/entities/character.gd tests/sim/sim_run.gd
git commit -m "Character: per-job progress, job change at the crystal, switching flag

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: The Job Crystal

**Files:**
- Create: `scenes/world/JobCrystal.tscn`, `scripts/world/job_crystal.gd`
- Modify: `scenes/world/ThornfieldMeadow.tscn`

- [ ] **Step 1: Script and scene**

Create `scripts/world/job_crystal.gd`:

```gdscript
extends Node2D

## A pulsing crystal where the hero changes job (see Character._change_job).
## Drawn in code; no art needed.

func _ready() -> void:
	add_to_group("job_crystals")
	var outer := Polygon2D.new()
	outer.polygon = PackedVector2Array([Vector2(0, -26), Vector2(15, 0), Vector2(0, 26), Vector2(-15, 0)])
	outer.color = Color(0.35, 0.85, 1.0, 0.9)
	add_child(outer)
	var inner := Polygon2D.new()
	inner.polygon = PackedVector2Array([Vector2(0, -14), Vector2(7, 0), Vector2(0, 14), Vector2(-7, 0)])
	inner.color = Color(0.85, 1.0, 1.0, 0.95)
	add_child(inner)
	var label := Label.new()
	label.text = "Job Crystal"
	label.position = Vector2(-34, 30)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0, 1.0))
	add_child(label)
	var tween := create_tween().set_loops()
	tween.tween_property(outer, "scale", Vector2(1.14, 1.14), 1.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(outer, "scale", Vector2(1.0, 1.0), 1.2).set_trans(Tween.TRANS_SINE)
```

Create `scenes/world/JobCrystal.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/world/job_crystal.gd" id="1_crystal"]

[node name="JobCrystal" type="Node2D"]
script = ExtResource("1_crystal")
```

- [ ] **Step 2: Place it in the meadow**

In `scenes/world/ThornfieldMeadow.tscn` (CRLF file: edit with Python `newline=''`): add `[ext_resource type="PackedScene" path="res://scenes/world/JobCrystal.tscn" id="20_jobcrystal"]` after the last `ext_resource`, increment `load_steps` in the header by 1, and add at the end of the file:

```
[node name="JobCrystal" parent="." instance=ExtResource("20_jobcrystal")]
position = Vector2(-200, -110)
```

(The quest board is at (-280, -160); the meadow spans x -400..400, y -300..300.)

- [ ] **Step 3: Import, test, boot**

Import once (new scene), run the tests (`0 failures`). Boot with the Godot MCP (`run_project` with the worktree path; ~15 s until `game_eval` connects; do not probe port 9090 from bash; pick a job on the select screen via `for b in get_tree().root.find_children("*", "Button", true, false): if b.text.begins_with("Warrior"): b.pressed.emit()`), screenshot the meadow near the quest board: the crystal is visible and pulsing. Check `get_debug_output` for errors. Stop the project.

- [ ] **Step 4: Commit**

```bash
git add scenes/world/JobCrystal.tscn scripts/world/job_crystal.gd scripts/world/job_crystal.gd.uid scenes/world/ThornfieldMeadow.tscn
git commit -m "Add the Job Crystal to Thornfield Meadow

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

(Include a `.uid` for the scene if one was generated.)

---

### Task 5: UI, narrator and journal

**Files:**
- Modify: `scripts/ui/ability_bar.gd`, `scripts/ui/unit_frame.gd`, `scripts/ui/sheet_text.gd`
- Modify: `scripts/systems/narrator_lines.gd`, `scripts/ui/narrator_director.gd`, `scripts/ui/journal_recorder.gd`
- Modify: `tests/suite_sheet_text.gd`, `tests/suite_narrator_lines.gd`

- [ ] **Step 1: Failing tests**

In `tests/suite_sheet_text.gd`, before the final `t.done()` add:

```gdscript
	# Jobs section
	var jobs_snap := _full_snapshot()
	jobs_snap["jobs"] = [
		{"id": "warrior", "name": "Warrior", "level": 10, "active": false},
		{"id": "white_mage", "name": "White Mage", "level": 8, "active": true},
		{"id": "thief", "name": "Thief", "level": 0, "active": false},
	]
	var jobs_text := SheetText.build(jobs_snap)
	t.check(jobs_text.contains("Warrior: 10"), "a taken job shows its level")
	t.check(jobs_text.contains("White Mage: 8 (active)"), "the active job is marked")
	t.check(jobs_text.contains("Thief: -"), "an untaken job shows a dash")
	t.check(not SheetText.build(_full_snapshot()).contains("Thief: -"), "no jobs key: no Jobs section")
```

In `tests/suite_narrator_lines.gd`: change the events count assertion from 10 to 11 (`t.check_eq(NarratorLines.EVENTS.size(), 11, "eleven narrated events")`) and extend `CONTEXT` with `"job": "White Mage"` and add before `t.done()`:

```gdscript
	t.check(NarratorLines.line_for("job_change", "steady", CONTEXT, 0.1).contains("White Mage"), "job change line names the job")
	t.check(NarratorLines.line_for("job_change", "explorer", CONTEXT, 0.1) != NarratorLines.line_for("job_change", "steady", CONTEXT, 0.1), "explorer has its own job change line")
```

Run the tests: expect failures.

- [ ] **Step 2: `SheetText` Jobs section**

In `scripts/ui/sheet_text.gd` `build()`, after the Equipment lines block and before the "Progress" header, add (using the file's existing `_header` helper and `lines` array):

```gdscript
	var jobs: Array = snap.get("jobs", [])
	if not jobs.is_empty():
		lines.append("")
		lines.append(_header("Jobs"))
		for job in jobs:
			var job_level := int(job.get("level", 0))
			var level_text := "-" if job_level <= 0 else str(job_level)
			var active_text := " (active)" if bool(job.get("active", false)) else ""
			lines.append("%s: %s%s" % [String(job.get("name", "")), level_text, active_text])
```

(Match the surrounding blank-line convention of the function.)

- [ ] **Step 3: `NarratorLines` job_change**

Add `"job_change"` to `EVENTS`, add `"job": "a new job"` and `"level": "?"` handling (`level` already has a fallback; add `"job": "a new calling"` to `FALLBACKS`), and add to `TEMPLATES`:

```gdscript
	"job_change": {
		"neutral": ["{name} takes up the {job}'s path, level {level}.", "A new calling: {name} becomes a {job}, level {level}."],
		"cautious": ["{name} studies the crystal, then chooses the {job}."],
		"reckless": ["{name} grabs the crystal and becomes a {job} without a second thought."],
		"greedy": ["The crystal hums. {name} sees profit in being a {job}."],
		"explorer": ["Another road, another calling: {name} is a {job} now."],
	},
```

- [ ] **Step 4: Narrator and journal listeners**

`narrator_director.gd` `_ready`: add

```gdscript
	GameState.job_changed.connect(func(_old_id: String, new_id: String, new_level: int): _say("job_change", {"job": AbilityTable.job_name(new_id), "level": new_level}))
```

`journal_recorder.gd` `_ready`: add

```gdscript
	GameState.job_changed.connect(func(_old_id: String, new_id: String, new_level: int): _add("job", "Took up %s (level %d)" % [AbilityTable.job_name(new_id), new_level]))
	GameState.job_mastered.connect(_on_job_mastered)
```

and

```gdscript
func _on_job_mastered(job_id: String) -> void:
	_add("job", "Mastered %s" % AbilityTable.job_name(job_id))
	var c = GameState.character
	if c != null and is_instance_valid(c) and c.jobs_mastered.size() >= AbilityTable.job_ids().size():
		_add("job", "Mastered every job")
```

- [ ] **Step 5: Ability bar and unit frame refresh**

`scripts/ui/ability_bar.gd`: move the slot-building loop into `_rebuild()` (free existing children first: `for child in get_children(): child.queue_free()`), call `_rebuild()` from `_ready` after the existing null-character guard, and connect `GameState.job_changed.connect(func(_o, _n, _l): _rebuild())`. Keep the same slot scene and `ability_id` assignment. Because `queue_free` is deferred, build the new slots after removing the old ones with `remove_child(child)` then `child.queue_free()` so the new slots are not mixed with the old.

`scripts/ui/unit_frame.gd`: extract the resource-bar recolor block (the code that reads `class_def["resource_color"]` and overrides the fill style) into `_apply_resource_color()` (called from `_ready` where the block was), and connect `GameState.job_changed` to a handler that calls `_apply_resource_color()`, `_on_leveled_up(GameState.character.level)`, `_on_xp_changed(GameState.character.xp)`, `_on_resource_changed(GameState.character.resource_amount, GameState.character.max_resource)`, `_on_equipment_changed(GameState.character.equipment)` and `_on_hp_changed(GameState.character.hp, GameState.character.max_hp)`.

- [ ] **Step 6: Run the tests and a boot check**

Run the tests (`0 failures`, no SCRIPT ERROR) and the parse check. Boot with the Godot MCP and force a change: `GameState.character._change_job("white_mage")` via `game_eval`; screenshot: the ability bar shows Holy/Cure/Benediction, the unit frame reads `Level N White Mage` with the Mana bar recolored, the sheet (`C`) lists all seven jobs with the active one marked, the Story channel shows a job-change line (narrator cooldown permitting), the journal (`J`) has `Took up White Mage (level N)`. No ERROR lines. Stop the project.

- [ ] **Step 7: Commit**

```bash
git add scripts/ui scripts/systems/narrator_lines.gd tests/suite_sheet_text.gd tests/suite_narrator_lines.gd
git commit -m "UI, narrator and journal follow job changes; sheet lists every job

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Sim logging and the regression

**Files:**
- Modify: `tests/sim/sim_monitor.gd`, `tests/sim/summarize.py`

- [ ] **Step 1: Monitor**

In `tests/sim/sim_monitor.gd`, where the other `GameState` signals are connected in `_ready`, add `GameState.job_changed.connect(_on_job_changed)` and:

```gdscript
func _on_job_changed(old_id: String, new_id: String, new_level: int) -> void:
	_emit("job", {"from": old_id, "to": new_id, "level": new_level})
```

Also add `"job": ch.character_class` to the fields of the `level_up` event emitted in `_on_level_up`.

- [ ] **Step 2: Summary script**

In `tests/sim/summarize.py`: in `load_run` add `"jobs": []` and `"level_events": []` to the run dict; in the event loop add

```python
            elif kind == "job":
                run["jobs"].append((t, f.get("from", ""), f.get("to", ""), int(f.get("level", "1"))))
```

and record every `level_up` as `run["level_events"].append((t, lvl))` (inside the existing `level_up` branch, keeping the `level_t` logic). Add a helper:

```python
def switch_outcomes(run):
    """For each job change: did the new job reach level 10 before the next change (or the end), and when."""
    outcomes = []
    jobs = run["jobs"]
    for i, (t0, _from, to, lvl) in enumerate(jobs):
        t1 = jobs[i + 1][0] if i + 1 < len(jobs) else run["end_t"]
        reached = None
        if lvl >= MAX_LEVEL:
            reached = 0.0
        else:
            for (t, level) in run["level_events"]:
                if t0 < t <= t1 and level >= MAX_LEVEL:
                    reached = t - t0
                    break
        outcomes.append(reached)
    return outcomes
```

In `main()`, after the existing per-class aggregate rows, add for each class: `agg_rows.append([cls, n, "job switches", stats([len(it["jobs"]) for it in items])])` (store `len(r["jobs"])` in each `per_class` item as `"jobs"`) and a row `"switches reaching L10 within 25 min"` = `ok/total` over all switches of that class where `ok` counts outcomes that are not None and at most 1500 seconds. Do not change the per-run table columns (the regression compares that row).

- [ ] **Step 3: Regression (switching off must equal the phase-1 logs)**

```bash
export GODOT="C:/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
rm -rf "$TEMP/simK0" && tests/sim/run_batch.sh "$TEMP/simK0" 45 "warrior mage white_mage thief black_belt dragoon red_mage" "1 2" 12 trait=steady > /dev/null 2>&1
for f in "$TEMP"/simK0/*.log; do b=$(basename $f); c=${b%_s*}; a=$(python tests/sim/summarize.py "$TEMP/simJC_$c/$b" | head -2 | tail -1 | tr -s ' '); d=$(python tests/sim/summarize.py "$f" | head -2 | tail -1 | tr -s ' '); [ "$a" == "$d" ] && echo "SAME $b" || echo "DIFF $b"; done
```

Expected: 14 `SAME`. A `DIFF` means switching-off behavior changed (most likely an rng draw or a context change in Task 3); find and fix before continuing. (`run_batch.sh` logs are named `<class>_s<seed>.log`.)

- [ ] **Step 4: Commit**

```bash
git add tests/sim/sim_monitor.gd tests/sim/summarize.py
git commit -m "Sim: log job changes and summarize switching outcomes

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Live check

- [ ] **Step 1: Run the checks** (Godot MCP; worktree path; connection ~15 s; no bash probes of port 9090; `game_eval` needs an explicit `return`)

1. Start as a Warrior. Give the hero the cap: `GameState.character.gain_xp(999999)` (or set level/xp) so it reaches level 10; confirm `wants_job_change == true` and the state turns to travel toward the meadow (`GameState.character.travel_destination_id == "thornfield_meadow"` if it is elsewhere) or `job_change` if already there. Teleport it to the meadow (`global_position = Vector2(-150, -60)`) and let it walk to the crystal; a log line `Changed job: Warrior -> <Job> (level 8)` appears, `level == 8` for a first-time job, and the gear set is inherited (`equipment` not empty if the Warrior had gear the new job can use).
2. Afterwards `GameState.character.job_states["warrior"].level == 10`. Force another change: the second change to a taken job restores its stored level and gear.
3. The ability bar, unit frame, sheet Jobs section, journal (`Took up ... (level N)`, `Mastered Warrior`) and a narrator line update; the crystal is visible; no ERROR lines in the debug output.
4. Trait checks: with `character_trait = "explorer"` and `wants_job_change = true` at the crystal, several forced changes pick different jobs.

- [ ] **Step 2: Fix anything found** in the relevant script, re-run the tests and the Task 6 regression if `Character` changed, commit as `Fix: <what>`.

---

### Task 8: Balance measurement (switching on)

**Files:**
- Modify (only if tuning is needed): `scripts/systems/job_switch.gd` (`CATCH_UP_GAP`, `LOOP_GAP`, `NUDGE_WINDOW`)
- Modify: `docs/superpowers/balance/2026-09-25-balance-report.md` (section 10)

- [ ] **Step 1: Measure**

```bash
export GODOT="C:/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
for j in warrior white_mage thief; do
  rm -rf "$TEMP/simL_$j"; tests/sim/run_batch.sh "$TEMP/simL_$j" 120 "$j" "$(seq -s ' ' 1 8)" 12 trait=steady switching=1 > /dev/null 2>&1
  echo "== $j"; python tests/sim/summarize.py "$TEMP/simL_$j"/*.log | grep -E "final level|deaths / 10|job switches|switches reaching|min to L10" | sed 's/  */ /g'
done > "$TEMP/simL.txt" 2>&1
```

Run this in the background (about 30 to 40 minutes) and wait for `== thief` to have its rows. Also run one trait check for variety: `trait=explorer` with `class=thief`, 8 seeds, into `simL_explorer`.

- [ ] **Step 2: Acceptance** (per starting job): mean job changes per run at least 3; mean deaths per 10 minutes at most 1.0; at least 75% of changes have the new job reach level 10 within 25 minutes; no run stuck (final level below 8 at 120 minutes counts as a failure). If a criterion fails, tune in small steps and re-run only the failing job: raise `CATCH_UP_GAP` to 1 if new jobs die too much; lower it to 3 if leveling is too slow; change `LOOP_GAP` to 3 if switching is too frequent. Update the pinned numbers in `tests/suite_job_switch.gd` (the `catch_up_level` and `switch_due` expectations) in the same commit as any tuning.

- [ ] **Step 3: Report and commit**

Add section 10 (job switching: table per starting job with switches per run, deaths per 10 minutes, share of changes reaching L10 within 25 minutes, any tuning) to the balance report:

```bash
git add scripts/systems/job_switch.gd tests/suite_job_switch.gd docs/superpowers/balance/2026-09-25-balance-report.md
git commit -m "Balance: measure job switching

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: README, final review and merge

- [ ] **Step 1: README**

Add a feature bullet (`Job switching: the hero keeps a level and gear set for every job and changes job by itself at the Job Crystal in Thornfield Meadow, so all seven jobs get leveled over a long run`) and, if the live check produced a good screenshot of the crystal or the sheet's Jobs section, save it in `docs/screenshots/` and add it to the Screenshots section.

- [ ] **Step 2: Final tests and review**

Run the tests (`0 failures`). Dispatch a review subagent over `git diff main...job-switching` focused on: exactness with switching off (context keys, `gain_xp` bookkeeping, `_sync_current_zone` tracking, rng use in the crystal branch), `_change_job` completeness (everything that depends on `class_def`/`character_class`/`max_resource`/`equipment` refreshed: ability cooldowns, resource bar, sprite tint, party, sheet snapshot, `ItemScoring` inputs, `_recompute_stats`), the forced travel override (`wants_job_change` while traveling, fleeing, dead/respawning, at the crystal zone but no crystal), stuck states (character never reaching the crystal, `pick_next_job` returning "", flag never cleared), jobs_mastered/journal duplicates, signal lifetimes (lambdas connected in UI nodes), and UI refresh after a switch. Fix real findings.

- [ ] **Step 3: Commit and merge**

```bash
git add README.md docs
git commit -m "Docs: job switching

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

Fast-forward merge `job-switching` into `main` from the main checkout, re-import and re-run the tests on `main`, remove the worktree (`git worktree remove --force .claude/worktrees/job-switching`; a Windows "Permission denied" on the folder is harmless) and delete the branch. Push only when the user asks.
