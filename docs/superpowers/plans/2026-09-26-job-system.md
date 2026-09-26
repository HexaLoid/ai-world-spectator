# Job System (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Seven Final Fantasy style jobs (Warrior, Black Mage, White Mage, Thief, Black Belt, Dragoon, Red Mage) for the hero and the allies, a character select screen, and a New Character button.

**Architecture:** Jobs are `AbilityTable.CLASSES` entries (ids `warrior` and `mage` unchanged) with new display/role keys, three small ability extensions (`hit_count`, a jump hit on `gap_closer`, and an `ally_heal` kind), and pure helpers in `AbilityMath` for unit tests. `Character` and `SimulatedPlayer` consume them. Allies get an optional `job_id`. The select screen is a separate scene reached from `Main._enter_tree` (no `project.godot` edit), controlled by `GameState` flags the sim harness turns off.

**Tech Stack:** Godot 4.7 (mono) GDScript, headless tests `tests/run_tests.gd`, `tests/sim` balance harness.

Spec: `docs/superpowers/specs/2026-09-26-job-system-design.md`.

**Deviations from the spec (decided while planning)**

- Allies keep their existing scene tints (they are already visually distinct); the job only changes their stats and, for healers, behavior.
- `AbilityTable` gains `JOB_ORDER` (select-screen order) and `job_ids()`/`job_name()` helpers.
- The sheet snapshot keeps `class_name` (the id, existing tests) and adds `job_name`.

**Conventions for every task**

- Work in a worktree: from `main`, `git worktree add .claude/worktrees/job-system -b job-system`; in it run the headless editor import twice (`"$GODOT" --headless --path . --editor --quit`), and once more after creating new `class_name` scripts or scenes (commit the generated `.gd.uid` files, the repo tracks them).
- `GODOT="C:/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"`.
- "Run the tests": `"$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|checks"`. Baseline `13233 checks, 0 failures`.
- Every suite's `run(t)` ends with `t.done()`; register new suites in `SUITES` in `tests/run_tests.gd`.
- Working tree is CRLF, commits LF: edit with the Edit tool (or Python `newline=''`).
- Never stage `assets/**/*.import`, `docs/screenshots/*.import`, `project.godot`.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- GDScript quirks: members not on the declared type (`Node2D`) are parse errors (use untyped `var`, `.call`, `.get`); guard `get_meta` with `has_meta`; no integer `/` division; a freed Object compares equal to null, so `is_instance_valid` first; do NOT give new nodes a property named `rng` (the sim seeds every node that has one and would shift all later seeds).
- **Sim regression rule:** Warrior and Black Mage runs must stay identical to the pre-change logs until Task 8 deliberately changes the allies. Reference logs are in `$TEMP/simC` (seeds 1-24, both classes; produced on `main` before this work). If missing, produce them on `main` first: `tests/sim/run_batch.sh "$TEMP/simC" 45 "warrior mage" "$(seq -s ' ' 1 4)" 8 trait=steady`.

---

### Task 1: `AbilityMath` pure helper

**Files:**
- Create: `scripts/systems/ability_math.gd`
- Create: `tests/suite_ability_math.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/suite_ability_math.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	# hit_count
	t.check_eq(AbilityMath.hit_count({}), 1, "no hit_count: one hit")
	t.check_eq(AbilityMath.hit_count({"hit_count": 3}), 3, "hit_count 3")
	t.check_eq(AbilityMath.hit_count({"hit_count": 0}), 1, "hit_count never below 1")
	t.check_eq(AbilityMath.hit_count({"hit_count": -2}), 1, "negative hit_count clamps to 1")

	# jump_multiplier
	t.check_near(AbilityMath.jump_multiplier({}), 0.0, "plain gap closer has no jump hit")
	t.check_near(AbilityMath.jump_multiplier({"damage_multiplier": 1.6}), 1.6, "jump hit multiplier")

	# pick_heal_target: lowest HP fraction below the threshold, or -1
	t.check_eq(AbilityMath.pick_heal_target([10, 50, 30], [100, 100, 100], 0.65), 0, "lowest fraction wins")
	t.check_eq(AbilityMath.pick_heal_target([90, 80], [100, 100], 0.65), -1, "everyone healthy: no target")
	t.check_eq(AbilityMath.pick_heal_target([], [], 0.65), -1, "empty party: no target")
	t.check_eq(AbilityMath.pick_heal_target([30, 20], [100, 40], 0.65), 1, "fractions, not raw HP: 20/40 < 30/100")
	t.check_eq(AbilityMath.pick_heal_target([65], [100], 0.65), -1, "exactly at the threshold is not below it")
	t.check_eq(AbilityMath.pick_heal_target([0, 30], [100, 100], 0.65), 1, "a dead member (0 HP) is skipped")
	t.check_eq(AbilityMath.pick_heal_target([10], [0], 0.65), -1, "max_hp 0 is skipped")

	# heal_amount
	t.check_eq(AbilityMath.heal_amount(100, 0.3), 30, "30% of 100")
	t.check_eq(AbilityMath.heal_amount(45, 0.25), 11, "rounds to nearest")
	t.check_eq(AbilityMath.heal_amount(1, 0.01), 1, "always at least 1")
	t.done()
```

Register `"res://tests/suite_ability_math.gd",` at the end of `SUITES` in `tests/run_tests.gd`.

- [ ] **Step 2: Run the tests to verify they fail**

Expected: SCRIPT ERROR / suite failed to load for `AbilityMath`.

- [ ] **Step 3: Implement**

Create `scripts/systems/ability_math.gd`:

```gdscript
class_name AbilityMath
extends RefCounted

## Pure numbers behind the job abilities (no nodes), so they are unit-tested.

## How many times a `melee_hit` ability strikes (default 1, never below 1).
static func hit_count(def: Dictionary) -> int:
	return maxi(1, int(def.get("hit_count", 1)))

## Damage multiplier of the hit that lands after a `gap_closer` jump; 0 = no hit.
static func jump_multiplier(def: Dictionary) -> float:
	return float(def.get("damage_multiplier", 0.0))

## Index of the member with the lowest HP fraction that is below `below`, or -1.
## Members with 0 HP (dead) or a max HP of 0 are skipped.
static func pick_heal_target(hps: Array, max_hps: Array, below: float) -> int:
	var best := -1
	var best_fraction := below
	for i in range(mini(hps.size(), max_hps.size())):
		var hp := int(hps[i])
		var max_hp := int(max_hps[i])
		if hp <= 0 or max_hp <= 0:
			continue
		var fraction := float(hp) / float(max_hp)
		if fraction < best_fraction:
			best_fraction = fraction
			best = i
	return best

## HP restored by a heal worth `percent` of `max_hp` (at least 1).
static func heal_amount(max_hp: int, percent: float) -> int:
	return maxi(1, roundi(float(max_hp) * percent))
```

- [ ] **Step 4: Import and run the tests**

Import once, then run the tests. Expected `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/ability_math.gd scripts/systems/ability_math.gd.uid tests/suite_ability_math.gd tests/suite_ability_math.gd.uid tests/run_tests.gd
git commit -m "Add AbilityMath pure helper for job abilities

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Job data in `AbilityTable`, and `bonus_crit_chance`

**Files:**
- Modify: `scripts/systems/ability_table.gd`
- Modify: `scripts/systems/stat_calculator.gd`
- Create: `tests/suite_job_table.gd`
- Modify: `tests/suite_stat_calculator.gd`, `tests/suite_ability_table.gd` (only if it hard-codes the class list), `tests/run_tests.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/suite_job_table.gd`:

```gdscript
extends RefCounted

const ROLES := ["tank", "healer", "melee", "magic"]
const KINDS := ["gap_closer", "melee_hit", "bleed", "self_heal", "ally_heal"]
const KEYS := ["name", "role", "blurb", "resource_name", "resource_color", "max_resource", "primary_stat", "stat_weights", "sprite_tint", "abilities", "ally_hp_mult", "ally_damage_mult"]

func run(t) -> void:
	t.check_eq(AbilityTable.JOB_ORDER.size(), 7, "seven jobs")
	t.check_eq(AbilityTable.job_ids(), AbilityTable.JOB_ORDER, "job_ids returns the order")
	t.check_eq(AbilityTable.CLASSES.size(), 7, "CLASSES has exactly the seven jobs")
	for id in AbilityTable.CLASSES.keys():
		t.check(AbilityTable.JOB_ORDER.has(id), "%s is in JOB_ORDER" % id)
	for id in AbilityTable.JOB_ORDER:
		var def: Dictionary = AbilityTable.CLASSES[id]
		for key in KEYS:
			t.check(def.has(key), "%s has %s" % [id, key])
		t.check(ROLES.has(def["role"]), "%s: valid role" % id)
		t.check(["strength", "intellect"].has(def["primary_stat"]), "%s: known primary stat" % id)
		t.check(float(def["ally_hp_mult"]) > 0.0 and float(def["ally_damage_mult"]) > 0.0, "%s: positive ally multipliers" % id)
		for stat in def["stat_weights"].keys():
			t.check(float(def["stat_weights"][stat]) > 0.0, "%s: weight %s positive" % [id, stat])
		var damaging := false
		for ability_id in def["abilities"]:
			t.check(AbilityTable.ABILITIES.has(ability_id), "%s: ability %s exists" % [id, ability_id])
			var ability: Dictionary = AbilityTable.ABILITIES.get(ability_id, {})
			t.check(KINDS.has(ability.get("kind", "")), "%s/%s: known kind" % [id, ability_id])
			t.check(int(ability.get("cooldown_ms", 0)) > 0, "%s/%s: positive cooldown" % [id, ability_id])
			t.check(ResourceLoader.exists(String(ability.get("icon", ""))), "%s/%s: icon exists" % [id, ability_id])
			if ability.get("kind", "") in ["melee_hit", "bleed"]:
				damaging = true
		t.check(damaging, "%s has a damaging ability" % id)

	# names and helpers
	t.check_eq(AbilityTable.job_name("mage"), "Black Mage", "mage is displayed as Black Mage")
	t.check_eq(AbilityTable.job_name("white_mage"), "White Mage", "job_name")
	t.check_eq(AbilityTable.job_name("nope"), "Nope", "unknown id falls back to a capitalized id")
	t.check_eq(AbilityTable.job_name(""), "Adventurer", "empty id falls back to Adventurer")

	# roles and the special abilities
	t.check_eq(AbilityTable.CLASSES["warrior"]["role"], "tank", "warrior is the tank")
	t.check_eq(AbilityTable.CLASSES["white_mage"]["role"], "healer", "white mage is the healer")
	var healer_kinds: Array = []
	for ability_id in AbilityTable.CLASSES["white_mage"]["abilities"]:
		healer_kinds.append(AbilityTable.ABILITIES[ability_id]["kind"])
	t.check(healer_kinds.has("ally_heal"), "white mage can heal allies")
	t.check(float(AbilityTable.CLASSES["thief"].get("gold_bonus_mult", 1.0)) > 1.0, "thief steals extra gold")
	t.check(float(AbilityTable.CLASSES["thief"].get("bonus_crit_chance", 0.0)) > 0.0, "thief has innate crit")
	t.check(int(AbilityTable.ABILITIES["combo"].get("hit_count", 1)) > 1, "black belt combo hits several times")
	t.check(AbilityMath.jump_multiplier(AbilityTable.ABILITIES["jump"]) > 0.0, "dragoon jump lands a hit")

	# the two original jobs keep their numbers
	t.check_eq(AbilityTable.CLASSES["warrior"]["abilities"], ["charge", "rend", "heroic_strike", "second_wind"], "warrior abilities unchanged")
	t.check_eq(AbilityTable.CLASSES["mage"]["abilities"], ["frost_nova", "arcane_bolt", "mana_ward"], "mage abilities unchanged")
	t.check_eq(int(AbilityTable.CLASSES["mage"]["bonus_max_hp"]), 25, "mage bonus HP unchanged")
	t.check_eq(int(AbilityTable.CLASSES["mage"]["bonus_armor"]), 5, "mage bonus armor unchanged")
	t.done()
```

Register `"res://tests/suite_job_table.gd",` in `tests/run_tests.gd`. In `tests/suite_stat_calculator.gd`, before the final `t.done()` add:

```gdscript
	# bonus_crit_chance is a flat class bonus on top of gear
	var crit_class := {"bonus_crit_chance": 0.10}
	t.check_near(float(StatCalculator.derive(base, {}, crit_class)["crit_chance"]), 0.10, "class crit bonus")
	t.check_near(float(StatCalculator.derive(base, {"neck": "lucky_charm"}, crit_class)["crit_chance"]), 0.10 + float(StatCalculator.derive(base, {"neck": "lucky_charm"}, {})["crit_chance"]), "class crit stacks with gear")
	t.check_near(float(StatCalculator.derive(base, {}, warrior)["crit_chance"]), 0.0, "no class crit bonus by default")
```

(`base` and `warrior` are already defined earlier in that suite; if `lucky_charm` is not a crit item, use whichever neck/ring id the existing crit test in that file uses.)

- [ ] **Step 2: Run the tests to verify they fail**

Expected: FAIL / SCRIPT ERROR (`JOB_ORDER`, `job_name`, new jobs missing).

- [ ] **Step 3: `StatCalculator`**

In `scripts/systems/stat_calculator.gd` `derive`, change the crit line to include the class bonus:

```gdscript
		"crit_chance": float(base["crit_chance"]) + float(class_def.get("bonus_crit_chance", 0.0)) + float(gear.get("crit_chance", 0.0)),
```

- [ ] **Step 4: `AbilityTable`**

In `scripts/systems/ability_table.gd`:

1. Add near the top of the class (before `CLASSES`):

```gdscript
## Select-screen order (by role): tank, melee, healer, magic.
const JOB_ORDER := ["warrior", "black_belt", "thief", "dragoon", "white_mage", "mage", "red_mage"]

static func job_ids() -> Array:
	return JOB_ORDER

## Display name of a job; unknown ids fall back to the capitalized id.
static func job_name(id: String) -> String:
	if id == "":
		return "Adventurer"
	return String(CLASSES.get(id, {}).get("name", id.capitalize()))
```

2. In `CLASSES["warrior"]` add (keep every existing key and value): `"name": "Warrior", "role": "tank", "blurb": "Heavy armor and Rage. Charges in and holds the line.", "ally_hp_mult": 1.3, "ally_damage_mult": 0.85,`.
   In `CLASSES["mage"]` add: `"name": "Black Mage", "role": "magic", "blurb": "Burns foes from a distance with Mana spells.", "ally_hp_mult": 1.0, "ally_damage_mult": 1.0,`.

3. Add these five entries to `CLASSES` after `"mage"`:

```gdscript
	"white_mage": {
		"name": "White Mage", "role": "healer", "blurb": "Heals the party and herself. Light damage.",
		"resource_name": "Mana", "resource_color": Color(0.85, 0.85, 1.0, 1.0),
		"max_resource": 100.0, "resource_regen_per_second": 6.0,
		"primary_stat": "intellect", "bonus_max_hp": 20, "bonus_armor": 4,
		"stat_weights": {"damage": 2.5, "intellect": 2.0, "armor": 1.0, "max_hp": 0.5, "crit_chance": 100.0},
		"sprite_tint": Color(1.0, 0.92, 0.92, 1.0),
		"abilities": ["holy", "cure", "benediction"],
		"ally_hp_mult": 0.9, "ally_damage_mult": 0.6,
	},
	"thief": {
		"name": "Thief", "role": "melee", "blurb": "Fast and lucky: high crit, and steals extra gold.",
		"resource_name": "Focus", "resource_color": Color(0.9, 0.8, 0.2, 1.0),
		"max_resource": 100.0, "resource_decay_per_second": 2.0,
		"rage_per_swing": 5.0, "rage_per_hit_taken": 3.0,
		"primary_stat": "strength", "bonus_max_hp": 10, "bonus_armor": 2,
		"bonus_crit_chance": 0.10, "gold_bonus_mult": 1.5,
		"stat_weights": {"damage": 3.0, "strength": 1.5, "armor": 1.0, "max_hp": 0.4, "crit_chance": 150.0},
		"sprite_tint": Color(0.5, 0.5, 0.58, 1.0),
		"abilities": ["dash", "backstab", "poison"],
		"ally_hp_mult": 0.9, "ally_damage_mult": 1.15,
	},
	"black_belt": {
		"name": "Black Belt", "role": "melee", "blurb": "An unarmed fighter with rapid multi-hit combos.",
		"resource_name": "Chakra", "resource_color": Color(1.0, 0.6, 0.2, 1.0),
		"max_resource": 100.0, "resource_decay_per_second": 2.0,
		"rage_per_swing": 8.0, "rage_per_hit_taken": 3.0,
		"primary_stat": "strength", "bonus_max_hp": 20, "bonus_armor": 2,
		"stat_weights": {"damage": 3.0, "strength": 2.0, "armor": 1.0, "max_hp": 0.6, "crit_chance": 100.0},
		"sprite_tint": Color(1.0, 0.82, 0.55, 1.0),
		"abilities": ["rush", "combo", "meditate"],
		"ally_hp_mult": 1.1, "ally_damage_mult": 1.0,
	},
	"dragoon": {
		"name": "Dragoon", "role": "melee", "blurb": "Leaps onto foes with a crushing spear strike.",
		"resource_name": "Focus", "resource_color": Color(0.4, 0.7, 0.95, 1.0),
		"max_resource": 100.0, "resource_decay_per_second": 2.0,
		"rage_per_swing": 5.0, "rage_per_hit_taken": 3.0,
		"primary_stat": "strength", "bonus_max_hp": 15, "bonus_armor": 3,
		"stat_weights": {"damage": 3.0, "strength": 2.0, "armor": 1.5, "max_hp": 0.5, "crit_chance": 100.0},
		"sprite_tint": Color(0.7, 0.85, 1.0, 1.0),
		"abilities": ["jump", "impulse", "elusive"],
		"ally_hp_mult": 1.0, "ally_damage_mult": 1.1,
	},
	"red_mage": {
		"name": "Red Mage", "role": "magic", "blurb": "A hybrid: spells, a little healing, and steel.",
		"resource_name": "Mana", "resource_color": Color(0.9, 0.3, 0.4, 1.0),
		"max_resource": 100.0, "resource_regen_per_second": 5.0,
		"primary_stat": "intellect", "bonus_max_hp": 20, "bonus_armor": 3,
		"stat_weights": {"damage": 3.0, "intellect": 1.5, "strength": 1.0, "armor": 1.0, "max_hp": 0.4, "crit_chance": 100.0},
		"sprite_tint": Color(1.0, 0.6, 0.62, 1.0),
		"abilities": ["verthunder", "enfeeble", "vercure"],
		"ally_hp_mult": 1.0, "ally_damage_mult": 1.0,
	},
```

4. Update the doc comment above `ABILITIES` to list the new kind `"ally_heal"` and the optional `hit_count` (melee_hit) and `damage_multiplier` (gap_closer) parameters, and add these entries to `ABILITIES` (icons exist in `assets/icons/`):

```gdscript
	"holy": {"name": "Holy", "icon": "res://assets/icons/arcane_bolt_icon.png", "resource_cost": 15.0, "cooldown_ms": 3500, "kind": "melee_hit", "damage_multiplier": 1.6},
	"cure": {"name": "Cure", "icon": "res://assets/icons/potion_icon.png", "resource_cost": 20.0, "cooldown_ms": 5000, "kind": "ally_heal", "heal_percent": 0.30, "heal_below": 0.65},
	"benediction": {"name": "Benediction", "icon": "res://assets/icons/mana_ward_icon.png", "resource_cost": 25.0, "cooldown_ms": 25000, "kind": "self_heal", "heal_percent": 0.35},
	"dash": {"name": "Dash", "icon": "res://assets/icons/charge_icon.png", "resource_cost": 0.0, "resource_gain": 10.0, "cooldown_ms": 8000, "kind": "gap_closer"},
	"backstab": {"name": "Backstab", "icon": "res://assets/icons/heroic_strike_icon.png", "resource_cost": 15.0, "cooldown_ms": 3500, "kind": "melee_hit", "damage_multiplier": 2.0},
	"poison": {"name": "Poison", "icon": "res://assets/icons/rend_icon.png", "resource_cost": 10.0, "cooldown_ms": 8000, "kind": "bleed", "tick_damage_min": 2, "tick_damage_max": 4, "tick_count": 5, "tick_interval_ms": 1500},
	"rush": {"name": "Rush", "icon": "res://assets/icons/charge_icon.png", "resource_cost": 0.0, "resource_gain": 15.0, "cooldown_ms": 7000, "kind": "gap_closer"},
	"combo": {"name": "Combo", "icon": "res://assets/icons/heroic_strike_icon.png", "resource_cost": 20.0, "cooldown_ms": 5000, "kind": "melee_hit", "damage_multiplier": 0.8, "hit_count": 3},
	"meditate": {"name": "Meditate", "icon": "res://assets/icons/second_wind_icon.png", "resource_cost": 0.0, "cooldown_ms": 25000, "kind": "self_heal", "heal_percent": 0.30},
	"jump": {"name": "Jump", "icon": "res://assets/icons/charge_icon.png", "resource_cost": 0.0, "resource_gain": 15.0, "cooldown_ms": 8000, "kind": "gap_closer", "damage_multiplier": 1.6},
	"impulse": {"name": "Impulse", "icon": "res://assets/icons/heroic_strike_icon.png", "resource_cost": 15.0, "cooldown_ms": 3000, "kind": "melee_hit", "damage_multiplier": 1.8},
	"elusive": {"name": "Elusive", "icon": "res://assets/icons/second_wind_icon.png", "resource_cost": 0.0, "cooldown_ms": 30000, "kind": "self_heal", "heal_percent": 0.20},
	"verthunder": {"name": "Verthunder", "icon": "res://assets/icons/arcane_bolt_icon.png", "resource_cost": 20.0, "cooldown_ms": 3500, "kind": "melee_hit", "damage_multiplier": 2.0},
	"enfeeble": {"name": "Enfeeble", "icon": "res://assets/icons/frost_nova_icon.png", "resource_cost": 15.0, "cooldown_ms": 9000, "kind": "bleed", "tick_damage_min": 2, "tick_damage_max": 4, "tick_count": 4, "tick_interval_ms": 1500},
	"vercure": {"name": "Vercure", "icon": "res://assets/icons/mana_ward_icon.png", "resource_cost": 25.0, "cooldown_ms": 20000, "kind": "self_heal", "heal_percent": 0.25},
```

If `tests/suite_ability_table.gd` asserts the old two-class list or the class key set, update those checks to the seven jobs (keeping every existing warrior/mage assertion).

- [ ] **Step 5: Import and run the tests**

Import once, then run the tests. Expected `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/ability_table.gd scripts/systems/stat_calculator.gd tests/suite_job_table.gd tests/suite_job_table.gd.uid tests/suite_stat_calculator.gd tests/suite_ability_table.gd tests/run_tests.gd
git commit -m "Add the seven jobs, job helpers and class crit bonus

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Job behavior in `Character`, plus job names in the UI

**Files:**
- Modify: `scripts/entities/character.gd`
- Modify: `scripts/ui/unit_frame.gd`, `scripts/ui/sheet_text.gd`
- Modify: `tests/suite_sheet_text.gd`

Node wiring; verified by the tests, the Warrior/Mage regression in Task 4 and the live check. The `sheet_text` change is unit-tested.

- [ ] **Step 1: Sheet text test first**

In `tests/suite_sheet_text.gd`, before the final `t.done()` add:

```gdscript
	# job name replaces the capitalized class id when present
	var job_snap := _full_snapshot()
	job_snap["class_name"] = "mage"
	job_snap["job_name"] = "Black Mage"
	t.check(SheetText.build(job_snap).contains("Level 3 Black Mage"), "sheet shows the job name")
	var id_snap := _full_snapshot()
	t.check(SheetText.build(id_snap).contains("Level 3 Warrior"), "no job_name: capitalized class id as before")
```

Run the tests: the first check fails. Then in `scripts/ui/sheet_text.gd`, change the class text lines to:

```gdscript
	var class_text := String(snap.get("job_name", ""))
	if class_text == "":
		class_text = String(snap.get("class_name", "")).capitalize()
	if class_text == "":
		class_text = "Adventurer"
```

- [ ] **Step 2: `Character` changes** (read each area first; keep all other behavior)

1. **Job choice in `_ready`:** replace the block that picks a random class when `character_class == ""` with:

```gdscript
	if character_class == "":
		if GameState.selected_job != "" and AbilityTable.CLASSES.has(GameState.selected_job):
			character_class = GameState.selected_job
		else:
			var job_ids := AbilityTable.job_ids()
			character_class = job_ids[rng.randi_range(0, job_ids.size() - 1)]
```

2. **Multi-hit:** rewrite `_use_melee_hit` so a `hit_count` of 1 behaves exactly as before (same rng draws, same log line and order):

```gdscript
func _use_melee_hit(hostile: Node2D, ability_id: String, def: Dictionary) -> void:
	_spend_resource(float(def.get("resource_cost", 0.0)))
	_start_cooldown(ability_id, int(def.get("cooldown_ms", 0)))
	var count := AbilityMath.hit_count(def)
	var rolls: Array = []
	var total := 0
	var any_crit := false
	for i in range(count):
		var roll := _roll_damage(attack_damage_min, attack_damage_max, float(def.get("damage_multiplier", 1.0)))
		rolls.append(roll)
		total += int(roll["damage"])
		any_crit = any_crit or bool(roll["is_crit"])
	var crit_suffix := " (Critical!)" if any_crit else ""
	if count == 1:
		GameState.log_event("%s hits %s for %d!%s" % [def.get("name", "An ability"), hostile.enemy_name, total, crit_suffix])
	else:
		GameState.log_event("%s hits %s %d times for %d!%s" % [def.get("name", "An ability"), hostile.enemy_name, count, total, crit_suffix])
	for roll in rolls:
		if not is_instance_valid(hostile) or hostile.is_dead:
			break
		hostile.take_damage(int(roll["damage"]), self, bool(roll["is_crit"]))
	attack_anim_until_ms = game_time_ms + ATTACK_ANIM_DURATION_MS
```

3. **Jump hit in `_try_gap_closer`:** after the existing `GameState.log_event("Uses %s on %s!" ...)` line and before `return true`, add:

```gdscript
	var jump_mult := AbilityMath.jump_multiplier(def)
	if jump_mult > 0.0:
		var jump_roll := _roll_damage(attack_damage_min, attack_damage_max, jump_mult)
		hostile.take_damage(int(jump_roll["damage"]), self, bool(jump_roll["is_crit"]))
```

(Charge has no `damage_multiplier`, so the Warrior is unchanged.)

4. **Ally heal:** add and call from `_physics_process` (after `_act(delta, context)`):

```gdscript
## White Mage's Cure: heals the lowest-HP member among the character and its
## party when one is below the ability's threshold. No-op for jobs without an
## ally_heal ability (no rng use, no state change).
func _try_ally_heal() -> void:
	var ability_id := _find_class_ability_id("ally_heal")
	if ability_id == "":
		return
	var def: Dictionary = AbilityTable.ABILITIES.get(ability_id, {})
	if not _ability_ready(ability_id, float(def.get("resource_cost", 0.0))):
		return
	var members: Array = [self]
	for ally in party:
		if is_instance_valid(ally) and not ally.is_dead:
			members.append(ally)
	var hps: Array = []
	var max_hps: Array = []
	for member in members:
		hps.append(member.hp)
		max_hps.append(member.max_hp)
	var index := AbilityMath.pick_heal_target(hps, max_hps, float(def.get("heal_below", 0.65)))
	if index < 0:
		return
	_spend_resource(float(def.get("resource_cost", 0.0)))
	_start_cooldown(ability_id, int(def.get("cooldown_ms", 0)))
	var target = members[index]
	target.receive_heal(AbilityMath.heal_amount(int(max_hps[index]), float(def.get("heal_percent", 0.0))))
	var who: String = "herself" if target == self else String(target.player_name)
	GameState.log_event("%s heals %s" % [def.get("name", "Cure"), who])

## Restores HP from an ally's heal (see SimulatedPlayer's healer role).
func receive_heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	var old_hp := hp
	hp = mini(max_hp, hp + amount)
	GameState.emit_signal("character_hp_changed", hp, max_hp)
	if hp > old_hp:
		GameState.emit_signal("damage_dealt", global_position, hp - old_hp, true)
```

5. **Thief gold:** in `_gain_gold`, first line: `amount = roundi(float(amount) * float(class_def.get("gold_bonus_mult", 1.0)))`.

6. **Sheet snapshot:** in `get_sheet_snapshot()` add `"job_name": AbilityTable.job_name(character_class), "role": String(class_def.get("role", "")),`.

7. In `scripts/ui/unit_frame.gd` `_on_leveled_up`, replace `" %s" % GameState.character.character_class.capitalize()` with `" %s" % AbilityTable.job_name(GameState.character.character_class)`; check the initial level label code path in the same file (where the label is first set) and use `AbilityTable.job_name` there too.

- [ ] **Step 3: Run the tests and check parse**

Run the tests (expected `0 failures`, no SCRIPT ERROR) and `"$GODOT" --headless --path . --quit 2>&1 | grep -iE "error|parse"` (nothing about the changed files).

- [ ] **Step 4: Commit**

```bash
git add scripts/entities/character.gd scripts/ui/unit_frame.gd scripts/ui/sheet_text.gd tests/suite_sheet_text.gd
git commit -m "Character: multi-hit, jump hit, ally heal, thief gold and job names

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Warrior and Black Mage regression

- [ ] **Step 1: Compare seeded runs against the reference logs**

```bash
export GODOT="C:/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
rm -rf "$TEMP/simJ0" && tests/sim/run_batch.sh "$TEMP/simJ0" 45 "warrior mage" "1 2 3 4" 8 trait=steady > /dev/null 2>&1
for f in "$TEMP"/simJ0/*.log; do b=$(basename $f); a=$(python tests/sim/summarize.py "$TEMP/simC/$b" | head -2 | tail -1 | tr -s ' '); c=$(python tests/sim/summarize.py "$f" | head -2 | tail -1 | tr -s ' '); [ "$a" == "$c" ] && echo "SAME $b" || echo "DIFF $b"; done
```

Expected: eight `SAME`. A `DIFF` means Task 3 changed Warrior or Black Mage behavior (most likely `_use_melee_hit`'s rng order, the gap closer, or `_gain_gold` rounding for multiplier 1.0): fix before continuing. No commit needed unless a fix was required.

---

### Task 5: Healer role and job stats for allies

**Files:**
- Modify: `scripts/entities/simulated_player.gd`

- [ ] **Step 1: Implement** (read the file first; add, do not restructure)

1. Constants and vars:

```gdscript
## Set in the zone scene; "" = the original ally (unchanged stats and behavior).
@export var job_id: String = ""
const HEAL_INTERVAL_MS := 6000.0
const HEAL_BELOW := 0.7
const HEAL_PERCENT := 0.25
var job_role: String = ""
var next_heal_ms: float = 0.0
```

2. In `_ready`, after the existing setup and before `hp = max_hp` is used (place before the `hp = max_hp` line), apply the job:

```gdscript
	if job_id != "" and AbilityTable.CLASSES.has(job_id):
		var job: Dictionary = AbilityTable.CLASSES[job_id]
		job_role = String(job.get("role", ""))
		max_hp = maxi(1, roundi(float(max_hp) * float(job.get("ally_hp_mult", 1.0))))
		var damage_mult := float(job.get("ally_damage_mult", 1.0))
		attack_damage_min = maxi(1, roundi(float(attack_damage_min) * damage_mult))
		attack_damage_max = maxi(attack_damage_min, roundi(float(attack_damage_max) * damage_mult))
```

3. `receive_heal` and the healer tick, called at the end of `_physics_process` (after `_act`):

```gdscript
func receive_heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	var old_hp := hp
	hp = mini(max_hp, hp + amount)
	if hp > old_hp:
		GameState.emit_signal("damage_dealt", global_position, hp - old_hp, true)

## Healer allies restore the lowest-HP member among the leader and the party.
func _tick_healer() -> void:
	if job_role != "healer" or game_time_ms < next_heal_ms:
		return
	if group_leader == null or not is_instance_valid(group_leader):
		return
	var members: Array = [group_leader]
	for ally in group_leader.party:
		if is_instance_valid(ally):
			members.append(ally)
	var hps: Array = []
	var max_hps: Array = []
	var candidates: Array = []
	for member in members:
		if member.is_dead:
			continue
		candidates.append(member)
		hps.append(member.hp)
		max_hps.append(member.max_hp)
	var index := AbilityMath.pick_heal_target(hps, max_hps, HEAL_BELOW)
	if index < 0:
		return
	next_heal_ms = game_time_ms + HEAL_INTERVAL_MS
	var target = candidates[index]
	target.receive_heal(AbilityMath.heal_amount(int(max_hps[index]), HEAL_PERCENT))
	var who: String = String(target.get("player_name")) if target != group_leader else "the leader"
	GameState.log_event("[Ally] %s heals %s" % [player_name, who])
```

(`member.is_dead`, `.hp`, `.max_hp` exist on both `Character` and `SimulatedPlayer`; `group_leader` is untyped-safe via `.party`; if `group_leader.party` is not accessible under the declared type of `group_leader`, use `group_leader.get("party")`.)

Call `_tick_healer()` at the end of `_physics_process`.

- [ ] **Step 2: Run the tests**

Run the tests (`0 failures`) and the parse check.

- [ ] **Step 3: Commit**

```bash
git add scripts/entities/simulated_player.gd
git commit -m "Allies: optional job with stat scaling and a healer role

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

(No scene sets `job_id` yet, so behavior is unchanged until Task 8.)

---

### Task 6: Character select, `GameState` flags, New Character button

**Files:**
- Create: `scenes/CharacterSelect.tscn`, `scripts/ui/character_select.gd`
- Modify: `scripts/autoload/game_state.gd`, `scripts/main.gd`, `scripts/ui/speed_control.gd`, `tests/sim/sim_run.gd`

- [ ] **Step 1: `GameState`**

Add near the other run-level vars:

```gdscript
## Job picked on the character select screen ("" until chosen).
var selected_job: String = ""
var job_chosen: bool = false
## When true, Main redirects to the character select screen until a job is
## chosen. The balance sim turns this off.
var select_screen_enabled: bool = true

## Clears everything that belongs to one run (called before a new character).
func reset_run() -> void:
	codex = CodexState.new()
	journal = Journal.new()
	character = null
	camera = null
	Engine.time_scale = 1.0
	user_time_scale = 1.0
```

- [ ] **Step 2: `main.gd`**

Add at the top of the script (after the existing `const`):

```gdscript
const SELECT_SCENE := "res://scenes/CharacterSelect.tscn"

func _enter_tree() -> void:
	if GameState.select_screen_enabled and not GameState.job_chosen:
		get_tree().change_scene_to_file.call_deferred(SELECT_SCENE)
```

- [ ] **Step 3: Select scene**

Create `scenes/CharacterSelect.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/character_select.gd" id="1_select"]

[node name="CharacterSelect" type="Control"]
script = ExtResource("1_select")
```

Create `scripts/ui/character_select.gd`:

```gdscript
extends Control

## Pick a job to start a new run. Cards are built in code from AbilityTable.

const MAIN_SCENE := "res://scenes/Main.tscn"
const ROLE_LABELS := {"tank": "Tank", "healer": "Healer", "melee": "Melee DPS", "magic": "Magic DPS"}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme_res := load("res://assets/theme/spectator_theme.tres")
	if theme_res is Theme:
		theme = theme_res
	var background := ColorRect.new()
	background.color = Color(0.07, 0.06, 0.09, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40.0
	root.offset_right = -40.0
	root.offset_top = 30.0
	root.offset_bottom = -30.0
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	var title := Label.new()
	title.text = "Choose a job"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Your character plays itself. You just watch."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(subtitle)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(grid)
	for job_id in AbilityTable.job_ids():
		grid.add_child(_make_card(job_id))
	grid.add_child(_make_random_card())

func _make_card(job_id: String) -> Button:
	var def: Dictionary = AbilityTable.CLASSES[job_id]
	var button := Button.new()
	button.custom_minimum_size = Vector2(250.0, 130.0)
	button.text = "%s\n[%s]\n%s" % [def["name"], ROLE_LABELS.get(def["role"], def["role"]), def["blurb"]]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tint: Color = def["sprite_tint"]
	button.add_theme_color_override("font_color", tint.lightened(0.35))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	button.pressed.connect(_start.bind(job_id))
	return button

func _make_random_card() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(250.0, 130.0)
	button.text = "Random\n[Any job]\nLet fate decide."
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(func(): _start(AbilityTable.job_ids()[randi() % AbilityTable.job_ids().size()]))
	return button

func _start(job_id: String) -> void:
	GameState.selected_job = job_id
	GameState.job_chosen = true
	get_tree().change_scene_to_file(MAIN_SCENE)
```

- [ ] **Step 4: New Character button**

In `scripts/ui/speed_control.gd` `_ready`, after the Journal button, append:

```gdscript
	var new_button := Button.new()
	new_button.text = "New Character"
	new_button.pressed.connect(func():
		GameState.reset_run()
		GameState.job_chosen = false
		get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")
	)
	add_child(new_button)
```

- [ ] **Step 5: Sim flag**

In `tests/sim/sim_run.gd` `_ready`, next to `GameState.fx_enabled = false` add `GameState.select_screen_enabled = false`.

- [ ] **Step 6: Import, test, live check**

Import once (new scene). Run the tests (`0 failures`). Boot with Godot MCP (`run_project` with the worktree path; ~15 s until `game_eval` connects, retry; never probe port 9090 from bash): the game should show the select screen first (screenshot: 7 job cards and a Random card, all text readable, none cut off at 1152x648). Use `game_eval` to click a card programmatically: `for b in get_tree().root.find_children("*", "Button", true, false): if b.text.begins_with("White Mage"): b.pressed.emit()`, wait a few seconds, then check `GameState.character.character_class == "white_mage"`, the unit frame reads `Level 1 White Mage`, and the speed row (with Director, Journal and New Character buttons) still fits in 1152 px (if not, shorten labels: `Director`, `Journal`, `New Char`). Press New Character: the select screen returns and a different job can be chosen; no ERROR lines. Stop the project.

- [ ] **Step 7: Commit**

```bash
git add scenes/CharacterSelect.tscn scenes/CharacterSelect.tscn.uid scripts/ui/character_select.gd scripts/ui/character_select.gd.uid scripts/autoload/game_state.gd scripts/main.gd scripts/ui/speed_control.gd tests/sim/sim_run.gd
git commit -m "Add the character select screen and New Character button

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

(Include any generated `.uid` files that exist for the new scene/script.)

---

### Task 7: Balance pass A (every job, original allies)

- [ ] **Step 1: Regression again**

Repeat the Task 4 comparison (Warrior/Black Mage seeds 1-4 must be `SAME`); the select-screen and healer code must not have changed them.

- [ ] **Step 2: Measure all seven jobs**

```bash
export GODOT="C:/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
for j in warrior mage white_mage thief black_belt dragoon red_mage; do
  rm -rf "$TEMP/simJA_$j"; echo "== $j"
  tests/sim/run_batch.sh "$TEMP/simJA_$j" 45 "$j" "$(seq -s ' ' 1 12)" 12 trait=steady 2>&1 | grep -E "^\s*$j\s+[0-9]+\s+(min to L5|min to L10|deaths |worst)" | sed 's/  */ /g'
done > "$TEMP/simJA.txt" 2>&1 &
```

This takes a while (run it in the background and wait for `== red_mage` to have its `deaths` lines). Each batch is 12 runs of a single job.

- [ ] **Step 3: Check acceptance** per job: mean deaths 0.3 to 3.0; level 5 mean at most 13 min; level 10 reached in at least 10 of 12 runs; mean level 10 time within 25% of Warrior. For a failing job, adjust only that job's numbers in `AbilityTable` (small steps: `bonus_max_hp`/`bonus_armor`, ability `damage_multiplier`, `cooldown_ms`, resource cost, `heal_percent`) and re-run that job until it passes. A job that is far too strong or weak in one number (e.g. White Mage damage) needs the damage lever; one that never dies needs less armor/HP; one that dies constantly needs more.

  Note: a White Mage has no ally healing help from the starting party in this pass, but it heals itself with Cure (self is a candidate) and Benediction; its Cure should not make it immortal (deaths >= 0.3).

- [ ] **Step 3: Update pinned numbers** (if you changed any) in `tests/suite_job_table.gd` (only the Warrior and Black Mage numbers are pinned; they must NOT change) and re-run the tests.

- [ ] **Step 4: Record** the table (job, deaths, L5, L10, L10 reached, tuning applied) in a new section 9 of `docs/superpowers/balance/2026-09-25-balance-report.md`, and commit:

```bash
git add scripts/systems/ability_table.gd tests/suite_job_table.gd docs/superpowers/balance/2026-09-25-balance-report.md
git commit -m "Balance: tune the new jobs (original allies)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Ally jobs in the zone scenes, and balance pass B

**Files:**
- Modify: `scenes/world/ThornfieldMeadow.tscn`, `BlackthornForest.tscn`, `MirewaterSwamp.tscn`, `FrostpeakPass.tscn`

- [ ] **Step 1: Assign jobs** (add one `job_id = "<job>"` line under each ally node header; use Python with `newline=''` to preserve CRLF; keep every other property)

| Ally node | job_id |
|---|---|
| `SimulatedPlayerKaelen` (Thornfield) | `warrior` |
| `SimulatedPlayerElowen` (Thornfield) | `white_mage` |
| `SimulatedPlayerBrynhild` (Blackthorn) | `dragoon` |
| `SimulatedPlayerGorrim` (Blackthorn) | `black_belt` |
| `SimulatedPlayerVesper` (Mirewater) | `red_mage` |
| `SimulatedPlayerHrolf` (Frostpeak) | `thief` |

Run the tests and the parse check.

- [ ] **Step 2: Re-baseline all seven jobs with the new allies**

Same loop as Task 7 Step 2 into `$TEMP/simJB_$j`. The healer ally (Elowen) is recruited at the start, so every hero now has a healer.

- [ ] **Step 3: Check acceptance** exactly as in Task 7. Expect fewer deaths for everyone (Elowen heals the hero); if a job now drops below 0.3 deaths per run, reduce the healer's effect first (for example `HEAL_INTERVAL_MS` 6000 to 9000 or `HEAL_PERCENT` 0.25 to 0.18 in `simulated_player.gd`), and only then touch job numbers. Keep Warrior and Black Mage inside the acceptance band too (their numbers may be tuned here, since the party changed). Update `tests/suite_job_table.gd` pins if you change the Warrior/Black Mage numbers, and say so in the report.

- [ ] **Step 4: Report and commit**

Add the "with job allies" table and the levers used to section 9, then:

```bash
git add scenes/world scripts/entities/simulated_player.gd scripts/systems/ability_table.gd tests/suite_job_table.gd docs/superpowers/balance/2026-09-25-balance-report.md
git commit -m "Allies get jobs; re-baseline every job

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: Live check, README, final review and merge

- [ ] **Step 1: Live check** (Godot MCP; worktree path)

1. Select screen shows all jobs; pick each of White Mage, Thief, Black Belt, Dragoon and Red Mage in turn (use the New Character button between runs): the unit frame shows `Level 1 <Job>`, the ability bar shows that job's abilities, the sprite is tinted, and the sheet (`C`) shows the job name.
2. White Mage: `GameState.character.hp = 5` with a party present: Cure fires (a log line `Cure heals ...` and a green number). Elowen (ally healer) heals the hero when the hero is below 70%.
3. Black Belt: fights with `Combo hits X n times` log lines. Dragoon: `Jump` deals damage on landing (a hit number right after the jump). Thief: a coin pickup gives about 1.5x gold (compare `GameState.character.gold` before/after with a known `gold_amount`).
4. No ERROR lines in the debug output. Screenshot the select screen and one job's HUD for the README (`docs/screenshots/jobs.png`, `docs/screenshots/select.png`).

- [ ] **Step 2: README**

Add a feature bullet (`Jobs: seven Final Fantasy style jobs (Warrior, Black Mage, White Mage, Thief, Black Belt, Dragoon, Red Mage) with roles, resources and abilities; pick one on the character select screen or press New Character; allies have jobs too, and the White Mage ally heals the party`), a Controls row for `New Character`, and the screenshots.

- [ ] **Step 3: Final tests and review**

Run the tests (`0 failures`) and dispatch a review subagent over `git diff main...job-system`, focused on: Warrior/Black Mage exactness (`_use_melee_hit` rng order, gap closer, gold rounding), `receive_heal`/`_try_ally_heal` with dead or freed members and `group_leader.party`, the select-screen redirect (Main `_enter_tree` with deferred scene change; state left in `GameState` after a redirect; `reset_run()` completeness: recorders, narrator and other nodes that connect to `GameState` signals belong to the freed scene), the sim harness path with `select_screen_enabled = false`, UI fit at 1152x648 (select cards, the speed row with four extra buttons), and test pins. Fix real findings.

- [ ] **Step 4: Commit and merge**

```bash
git add README.md docs
git commit -m "Docs: job system

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

Fast-forward merge `job-system` into `main` from the main checkout (`git merge --ff-only job-system`), re-import and re-run the tests on `main`, remove the worktree (`git worktree remove --force .claude/worktrees/job-system`, a Windows "Permission denied" on the folder is harmless) and delete the branch. Push only when the user asks.
