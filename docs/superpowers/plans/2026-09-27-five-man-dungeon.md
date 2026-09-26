# Five-Man Dungeon (the Hollowed Vault) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An instanced three-room dungeon for a five-person role party (tank, healer, three damage), entered from a portal in the Sundered Crypt, with threat, a telegraphed boss strike, an add phase, dungeon-only epics and a clear/fail result.

**Architecture:** Pure helpers (`PartyBuilder`, `ThreatRules`, `EncounterLogic`) hold the decisions and are unit-tested. `DungeonRun` (a node in `Main`) builds the party, instantiates the vault scene at a far-away world position, watches for clear/fail and restores everything. Enemies gain an optional `mechanics` child (`BossMechanics`) and a threat rule that only applies while `GameState.in_dungeon`. The hero gets two AI states (`dungeon_enter`, `dungeon_advance`). A `dungeon` sim flag (off by default) keeps earlier behavior available for regression.

**Tech Stack:** Godot 4.7 (mono) GDScript, headless tests `tests/run_tests.gd`, `tests/sim` balance harness.

Spec: `docs/superpowers/specs/2026-09-27-five-man-dungeon-design.md`.

**Decisions made while planning (small deviations from the spec)**

- Enemy construction moves into a shared `EnemyFactory` (used by `SpawnPoint` and by the boss's adds); `SpawnPoint` behavior must stay identical.
- The dungeon epics are marked `"dungeon": true` in `LootTable`; `roll_boss_bonus` takes a `dungeon` argument so open-world bosses never roll them and dungeon bosses only roll them.
- After the final boss dies the run waits `CLEAR_DELAY_S` (6 s) before teleporting out, so the hero can pick up the loot.
- The world's `WORLD_BOUNDS_MAX.x` grows to 12750 to contain the vault; the corridor between Frostpeak Pass and the vault is empty world (nothing walks there).

**Conventions for every task**

- Work in a worktree: from `main`, `git worktree add .claude/worktrees/dungeon -b dungeon`; run the headless editor import twice in it (`"$GODOT" --headless --path . --editor --quit`) and once more after creating new `class_name` scripts or scenes (commit the generated `.gd.uid` files, the repo tracks them).
- `GODOT="C:/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"`.
- "Run the tests": `"$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|checks"`. Baseline `13698 checks, 0 failures`.
- Every suite's `run(t)` ends with `t.done()`; register new suites at the end of `SUITES` in `tests/run_tests.gd`.
- Working tree is CRLF, commits LF: edit with the Edit tool (or Python `newline=''`; normalize a file if you end up with mixed endings).
- Never stage `assets/**/*.import`, `docs/screenshots/*.import`, `project.godot`.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- GDScript quirks: members not on the declared type (`Node2D`) are a parse error (use untyped `var`, `.call`, `.get`); guard `get_meta` with `has_meta`; no integer `/` division; freed Objects compare equal to null, so `is_instance_valid` first; do NOT give new nodes a property named `rng` (the sim seeds every node that has one, shifting later seeds); `game_eval` code in the Godot MCP needs an explicit `return`.
- **Regression rule:** with `GameState.dungeon_enabled = false` (the sim default `dungeon=0`) and `switching=0`, `trait=steady`, every seeded run must be identical to the phase-2 logs in `$TEMP/simJC_<job>` (12 seeds each, 45 min). If they are missing, regenerate them on `main` first.

---

### Task 1: `PartyBuilder`, `ThreatRules`, `EncounterLogic` (pure)

**Files:**
- Create: `scripts/systems/party_builder.gd`, `scripts/systems/threat_rules.gd`, `scripts/systems/encounter_logic.gd`
- Create: `tests/suite_party_builder.gd`, `tests/suite_threat_rules.gd`, `tests/suite_encounter_logic.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/suite_party_builder.gd`:

```gdscript
extends RefCounted

func _m(name: String, role: String) -> Dictionary:
	return {"id": name, "name": name, "role": role}

func _names(members: Array) -> Array:
	var out: Array = []
	for m in members:
		out.append(m["name"])
	return out

func run(t) -> void:
	var pool := [_m("Kaelen", "tank"), _m("Elowen", "healer"), _m("Brynhild", "melee"), _m("Gorrim", "melee"), _m("Vesper", "magic"), _m("Hrolf", "melee")]

	# a melee hero with an empty party: tank, healer, then two damage dealers
	var picks := PartyBuilder.missing_members("melee", [], pool, 5)
	t.check_eq(_names(picks), ["Kaelen", "Elowen", "Brynhild", "Gorrim"], "tank, healer, then damage in pool order")

	# a tank hero needs no second tank
	picks = PartyBuilder.missing_members("tank", [], pool, 5)
	t.check_eq(_names(picks), ["Elowen", "Brynhild", "Gorrim", "Vesper"], "a tank hero adds a healer and damage")

	# a healer hero needs no healer
	picks = PartyBuilder.missing_members("healer", [], pool, 5)
	t.check_eq(_names(picks), ["Kaelen", "Brynhild", "Gorrim", "Vesper"], "a healer hero adds a tank and damage")

	# existing members stay and count
	var party := [_m("Kaelen", "tank"), _m("Elowen", "healer")]
	picks = PartyBuilder.missing_members("magic", party, pool, 5)
	t.check_eq(_names(picks), ["Brynhild", "Gorrim"], "party already has tank and healer: two damage dealers join")
	for p in picks:
		t.check(p["name"] != "Kaelen" and p["name"] != "Elowen", "never re-adds a member already in the party")

	# missing roles come first even when the party has damage dealers
	picks = PartyBuilder.missing_members("magic", [_m("Brynhild", "melee"), _m("Gorrim", "melee")], pool, 5)
	t.check_eq(_names(picks), ["Kaelen", "Elowen"], "tank and healer first")

	# a role missing from the pool is skipped
	var no_healer := [_m("Kaelen", "tank"), _m("Brynhild", "melee"), _m("Gorrim", "melee")]
	picks = PartyBuilder.missing_members("melee", [], no_healer, 5)
	t.check_eq(_names(picks), ["Kaelen", "Brynhild", "Gorrim"], "no healer available: fill with what exists")

	# never more than the free slots
	picks = PartyBuilder.missing_members("melee", [_m("A", "melee"), _m("B", "melee"), _m("C", "melee")], pool, 5)
	t.check_eq(picks.size(), 1, "one free slot: one member")
	picks = PartyBuilder.missing_members("melee", [_m("A", "melee"), _m("B", "melee"), _m("C", "melee"), _m("D", "melee")], pool, 5)
	t.check_eq(picks.size(), 0, "full party: nobody joins")
	t.check_eq(PartyBuilder.missing_members("melee", [], [], 5).size(), 0, "empty pool")
	t.check_eq(PartyBuilder.missing_members("melee", [], pool, 3).size(), 2, "size 3 party: two joiners")
	t.check_eq(_names(PartyBuilder.missing_members("melee", [], pool, 5)), _names(PartyBuilder.missing_members("melee", [], pool, 5)), "deterministic")
	t.done()
```

Create `tests/suite_threat_rules.gd`:

```gdscript
extends RefCounted

func _c(dist: float, is_tank: bool) -> Dictionary:
	return {"dist": dist, "is_tank": is_tank}

func run(t) -> void:
	t.check_eq(ThreatRules.pick_target([], 120.0), -1, "no candidates")
	t.check_eq(ThreatRules.pick_target([_c(80.0, false), _c(50.0, false)], 120.0), 1, "no tank: nearest wins")
	t.check_eq(ThreatRules.pick_target([_c(40.0, false), _c(100.0, true)], 120.0), 1, "a tank in range beats a nearer non-tank")
	t.check_eq(ThreatRules.pick_target([_c(40.0, false), _c(150.0, true)], 120.0), 1, "the pull range is 1.3x the aggro range (156)")
	t.check_eq(ThreatRules.pick_target([_c(40.0, false), _c(200.0, true)], 120.0), 0, "a tank beyond the pull range loses")
	t.check_eq(ThreatRules.pick_target([_c(100.0, true), _c(60.0, true)], 120.0), 1, "two tanks: the nearer one")
	t.check_eq(ThreatRules.pick_target([_c(50.0, false), _c(50.0, false)], 120.0), 0, "a tie goes to the first")
	t.check_near(ThreatRules.TANK_PULL_MULT, 1.3, "pull multiplier")
	t.done()
```

Create `tests/suite_encounter_logic.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	t.check(EncounterLogic.heavy_due(9000.0, 9000.0), "due exactly on time")
	t.check(EncounterLogic.heavy_due(9500.0, 9000.0), "due when late")
	t.check(not EncounterLogic.heavy_due(8999.0, 9000.0), "not due early")
	t.check_eq(EncounterLogic.heavy_damage(50), 125, "50 x 2.5")
	t.check_eq(EncounterLogic.heavy_damage(55, 2.0), 110, "custom multiplier")
	t.check_eq(EncounterLogic.heavy_damage(0), 0, "no attack, no heavy damage")
	t.check(not EncounterLogic.add_phase_due(1000, 1800, false), "above 50%: no add phase")
	t.check(EncounterLogic.add_phase_due(900, 1800, false), "exactly 50%: add phase")
	t.check(EncounterLogic.add_phase_due(100, 1800, false), "below 50%: add phase")
	t.check(not EncounterLogic.add_phase_due(100, 1800, true), "the add phase fires only once")
	t.check(not EncounterLogic.add_phase_due(0, 1800, false), "a dead boss does not summon")
	t.check_near(EncounterLogic.HEAVY_INTERVAL_MS, 9000.0, "heavy strike interval")
	t.check_near(EncounterLogic.HEAVY_WINDUP_MS, 1500.0, "wind-up")
	t.check_eq(EncounterLogic.ADD_COUNT, 2, "two adds")
	t.done()
```

Register the three suites at the end of `SUITES`.

- [ ] **Step 2: Run the tests to verify they fail**

Expected: SCRIPT ERROR / suite failed to load.

- [ ] **Step 3: Implement**

`scripts/systems/party_builder.gd`:

```gdscript
class_name PartyBuilder
extends RefCounted

## Which pool members to add so a dungeon party has `size` people (hero
## included): a tank first when there is none, then a healer, then damage
## dealers, then anyone. `party` and `pool` are arrays of dictionaries with a
## "role" (tank/healer/melee/magic) and any other keys (the same dictionaries
## are returned). Deterministic: pool order breaks ties.
static func missing_members(hero_role: String, party: Array, pool: Array, size: int = 5) -> Array:
	var free := size - 1 - party.size()
	var picks: Array = []
	if free <= 0:
		return picks
	var has_tank := hero_role == "tank"
	var has_healer := hero_role == "healer"
	var in_party := {}
	for member in party:
		in_party[member.get("id", member.get("name", ""))] = true
		var role := String(member.get("role", ""))
		has_tank = has_tank or role == "tank"
		has_healer = has_healer or role == "healer"
	var remaining: Array = []
	for candidate in pool:
		if not in_party.has(candidate.get("id", candidate.get("name", ""))):
			remaining.append(candidate)
	if not has_tank:
		_take_first(remaining, picks, ["tank"], free)
	if not has_healer:
		_take_first(remaining, picks, ["healer"], free)
	while picks.size() < free:
		var before := picks.size()
		_take_first(remaining, picks, ["melee", "magic"], free)
		if picks.size() == before:
			break
	while picks.size() < free and not remaining.is_empty():
		picks.append(remaining.pop_front())
	return picks

static func _take_first(remaining: Array, picks: Array, roles: Array, free: int) -> void:
	if picks.size() >= free:
		return
	for i in range(remaining.size()):
		if roles.has(String(remaining[i].get("role", ""))):
			picks.append(remaining[i])
			remaining.remove_at(i)
			return
```

`scripts/systems/threat_rules.gd`:

```gdscript
class_name ThreatRules
extends RefCounted

## Who an enemy attacks inside a dungeon: a tank within TANK_PULL_MULT x the
## enemy's aggro range beats a nearer non-tank; otherwise the nearest wins.
## `candidates` is an array of {"dist": float, "is_tank": bool}; returns an
## index or -1 for none.
const TANK_PULL_MULT := 1.3

static func pick_target(candidates: Array, aggro_range: float) -> int:
	var nearest := -1
	var nearest_dist := INF
	var tank := -1
	var tank_dist := INF
	for i in range(candidates.size()):
		var dist := float(candidates[i]["dist"])
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = i
		if bool(candidates[i]["is_tank"]) and dist <= aggro_range * TANK_PULL_MULT and dist < tank_dist:
			tank_dist = dist
			tank = i
	return tank if tank >= 0 else nearest
```

`scripts/systems/encounter_logic.gd`:

```gdscript
class_name EncounterLogic
extends RefCounted

## Timing and numbers for the dungeon boss mechanics (see BossMechanics).
const HEAVY_INTERVAL_MS := 9000.0
const HEAVY_WINDUP_MS := 1500.0
const HEAVY_MULT := 2.5
const ADD_PHASE_HP := 0.5
const ADD_COUNT := 2

static func heavy_due(now_ms: float, next_ms: float) -> bool:
	return now_ms >= next_ms

static func heavy_damage(attack_max: int, mult: float = HEAVY_MULT) -> int:
	return roundi(float(attack_max) * mult)

static func add_phase_due(hp: int, max_hp: int, done: bool) -> bool:
	return not done and hp > 0 and float(hp) <= float(max_hp) * ADD_PHASE_HP
```

- [ ] **Step 4: Import and run the tests**

Import once, then run the tests. Expected `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/party_builder.gd scripts/systems/party_builder.gd.uid scripts/systems/threat_rules.gd scripts/systems/threat_rules.gd.uid scripts/systems/encounter_logic.gd scripts/systems/encounter_logic.gd.uid tests/suite_party_builder.gd tests/suite_party_builder.gd.uid tests/suite_threat_rules.gd tests/suite_threat_rules.gd.uid tests/suite_encounter_logic.gd tests/suite_encounter_logic.gd.uid tests/run_tests.gd
git commit -m "Add PartyBuilder, ThreatRules and EncounterLogic pure helpers

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Data: the vault zone, enemies, dungeon epics, codex

**Files:**
- Modify: `scripts/systems/zone_table.gd`, `enemy_table.gd`, `loot_table.gd`, `codex_data.gd`
- Modify tests: `tests/suite_zone_table.gd`, `suite_enemy_table.gd`, `suite_spawn_points.gd`, `suite_loot_table.gd`, `suite_codex_data.gd` (and `suite_codex_text.gd` if it counts zones)

Read each file and its test first; this task is data plus test adaptation.

- [ ] **Step 1: `ZoneTable`**

Add the zone (after `frostpeak_pass`):

```gdscript
	"hollowed_vault": {
		"name": "Hollowed Vault",
		"instanced": true,
		"center": Vector2(12000, 0),
		"bounds_min": Vector2(11250, -200),
		"bounds_max": Vector2(12750, 200),
		"min_level": 8,
		"stay_duration_ms": 60000.0,
	},
```

Set `WORLD_BOUNDS_MAX := Vector2(12750, 280)`. `TRAVEL_ORDER` stays the five open-world zones. Add:

```gdscript
## Every zone in display order: the travel loop, then instanced zones (dungeons).
static func all_zone_order() -> Array:
	var order: Array = TRAVEL_ORDER.duplicate()
	for id in ZONES.keys():
		if bool(ZONES[id].get("instanced", false)) and not order.has(id):
			order.append(id)
	return order
```

Update the class doc comment to explain `instanced` (not part of the rotation; the dungeon run teleports there).

- [ ] **Step 2: `EnemyTable`** (add after `frostpeak_warlord`; sprite/tint keys follow the existing entries)

```gdscript
	# --- Hollowed Vault (dungeon, level 8+) ---
	"vault_skeleton": {
		"name": "Vault Skeleton", "zone": "hollowed_vault", "sprite": "bandit", "tint": Color(0.78, 0.78, 0.86, 1.0), "sprite_size": 42.0,
		"max_hp": 90, "move_speed": 52.0, "attack_min": 10, "attack_max": 16, "aggro_range": 140.0,
		"xp_reward": 120, "gold_min": 6, "gold_max": 11, "loot_level": 10, "guaranteed_drop": "",
	},
	"vault_wraith": {
		"name": "Vault Wraith", "zone": "hollowed_vault", "sprite": "wolf", "tint": Color(0.6, 0.5, 0.95, 1.0), "sprite_size": 42.0,
		"max_hp": 60, "move_speed": 84.0, "attack_min": 12, "attack_max": 18, "aggro_range": 200.0,
		"xp_reward": 60, "gold_min": 4, "gold_max": 8, "loot_level": 10, "guaranteed_drop": "",
	},
	"bone_warden": {
		"name": "Bone Warden", "zone": "hollowed_vault", "sprite": "bandit", "tint": Color(0.9, 0.88, 0.7, 1.0), "sprite_size": 64.0,
		"max_hp": 700, "move_speed": 60.0, "attack_min": 30, "attack_max": 45, "aggro_range": 200.0,
		"xp_reward": 700, "gold_min": 20, "gold_max": 30, "loot_level": 10, "guaranteed_drop": "wardens_plate",
	},
	"hollow_king": {
		"name": "Hollow King", "zone": "hollowed_vault", "sprite": "bandit", "tint": Color(0.5, 0.3, 0.65, 1.0), "sprite_size": 80.0,
		"max_hp": 1800, "move_speed": 66.0, "attack_min": 38, "attack_max": 55, "aggro_range": 260.0,
		"xp_reward": 1600, "gold_min": 40, "gold_max": 60, "loot_level": 10, "guaranteed_drop": "hollow_crown",
		"mechanics": "hollow_king",
	},
```

(The Vault Wraith is an add, not placed in the scene by a spawn point.) `is_boss` becomes true for `bone_warden` and `hollow_king` automatically (guaranteed drop).

- [ ] **Step 3: `LootTable`** four dungeon epics (`"dungeon": true`, icons reused) after the frost epics, and a new bonus-roll argument:

```gdscript
	"wardens_plate": {"slot": "chest", "rarity": "epic", "level_req": 8, "dungeon": true, "icon": "res://assets/icons/champions_plate_icon.png", "stats": {"armor": 12, "max_hp": 50, "strength": 4, "intellect": 4}},
	"hollow_crown": {"slot": "head", "rarity": "epic", "level_req": 9, "dungeon": true, "icon": "res://assets/icons/crown_of_thornfield_icon.png", "stats": {"armor": 6, "max_hp": 30, "strength": 3, "intellect": 3}},
	"kings_edge": {"slot": "weapon", "rarity": "epic", "level_req": 9, "dungeon": true, "icon": "res://assets/icons/warlords_greatsword_icon.png", "stats": {"damage": 26, "strength": 7}},
	"void_scepter": {"slot": "weapon", "rarity": "epic", "level_req": 9, "dungeon": true, "icon": "res://assets/icons/glacier_staff_icon.png", "stats": {"damage": 22, "intellect": 8}},
```

`roll_boss_bonus(rng, loot_level, exclude_id = "", dungeon = false)`: the eligible pool is `epic_ids_up_to(loot_level)` filtered to items whose `bool(item.get("dungeon", false)) == dungeon`; everything else unchanged (including the 35% chance and the `""` result). `epic_ids_up_to` itself is unchanged (it includes dungeon epics). `Enemy._drop_loot` will pass `is_in_group("dungeon_enemies")` (Task 3).

- [ ] **Step 4: `CodexData`**

Make `zone_order()` return `ZoneTable.all_zone_order()`, `enemy_order()` iterate `ZoneTable.all_zone_order()`, and check `zone_level_range` for the vault (`TRAVEL_ORDER.find` is -1, so the high end is `MAX_LEVEL`: correct). In `item_sources`, `"boss_bonus"` must respect the dungeon partition: a dungeon epic lists only dungeon bosses (enemies whose zone is instanced) with `loot_level >= level_req`, an open-world epic lists only non-dungeon bosses. Read the existing implementation and adapt; keep existing outputs for open-world items unchanged.

- [ ] **Step 5: Tests**

Adapt the existing suites (keep every existing assertion that is still meaningful):

- `suite_zone_table`: `TRAVEL_ORDER.size() + (number of instanced zones) == ZONES.size()`; "every zone is in the travel order" applies only to non-instanced zones; the center-order, min_level-order and stay checks iterate `TRAVEL_ORDER`; keep "min bounds inside the world" and "no overlap" for all zones; add checks: the vault is `instanced`, is not in `TRAVEL_ORDER`, has `min_level` 8, `all_zone_order()` ends with `hollowed_vault`, `next_zone_id` never returns it.
- `suite_enemy_table`: extend `NEW_IDS`/validation loops with the four enemies; `is_boss` set becomes the seven bosses (`bandit_captain`, `crypt_lord`, `mire_tyrant`, `raider_captain`, `frostpeak_warlord`, `bone_warden`, `hollow_king`); every boss `guaranteed_drop` exists; the boss-drop level rule ("`level_req` at most 2 above the zone `min_level`") must hold: `wardens_plate` 8 and `hollow_crown` 9 vs `min_level` 8.
- `suite_spawn_points`: add `"HollowedVault.tscn": "hollowed_vault"` to its scene-to-zone map (the scene is created in Task 5; until then that entry is unused).
- `suite_loot_table`: `roll_boss_bonus(..., dungeon = false)` never returns a dungeon epic and "every eligible epic can be rolled" compares against the non-dungeon epics; with `dungeon = true` at loot level 10 it returns only dungeon epics and every dungeon epic can be rolled; `epic_ids_up_to(99)` still equals every epic; the dungeon epics have `level_req` 8 or 9 and valid slots.
- `suite_codex_data`: `zone_order()` ends with the vault; `enemy_order()` still returns every enemy id exactly once (now 16); `item_sources("wardens_plate")["guaranteed"]` names Bone Warden; a dungeon epic's `boss_bonus` lists only dungeon bosses; an open-world epic's `boss_bonus` never lists a dungeon boss; `zone_level_range("hollowed_vault")` is `[8, 10]`; `zone_boss_id("hollowed_vault")` is `hollow_king` (highest HP with a guaranteed drop).
- `suite_codex_text`: adapt any zone-count text (`Zones 5/5` style) if the tab title counts `zone_order()` (now 6).

- [ ] **Step 6: Run the tests**

Expected `0 failures`. Fix test expectations that only encode the old zone/enemy/epic counts; do not weaken real checks.

- [ ] **Step 7: Commit**

```bash
git add scripts/systems tests
git commit -m "Data: the Hollowed Vault zone, its enemies and dungeon-only epics

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Enemy factory, dungeon spawns, threat, boss mechanics

**Files:**
- Create: `scripts/systems/enemy_factory.gd`, `scripts/entities/boss_mechanics.gd`
- Modify: `scripts/entities/spawn_point.gd`, `scripts/entities/enemy.gd`, `scripts/entities/character.gd` (`job_role`), `scripts/autoload/game_state.gd`

Node wiring: verified by the tests, the regression (Task 7) and the live check (Task 8).

- [ ] **Step 1: `GameState`**

```gdscript
## The dungeon (Hollowed Vault) can be entered (phase 3). The balance sim turns
## this off unless it is measuring the feature (`dungeon=1`).
var dungeon_enabled: bool = true
## True while a DungeonRun is active: enemies then use ThreatRules.
var in_dungeon: bool = false

## kind: "enter", "warning", "clear" or "fail"; `text` is the dungeon or boss name.
signal dungeon_event(kind: String, text: String)
## A run ended: result is "cleared", "failed" or "timeout".
signal dungeon_finished(result: String, duration_s: float)
```

and add `in_dungeon = false` to `reset_run()`.

- [ ] **Step 2: `EnemyFactory`**

Create `scripts/systems/enemy_factory.gd` by moving the field assignments out of `SpawnPoint._spawn`:

```gdscript
class_name EnemyFactory
extends RefCounted

## Builds an enemy node from EnemyTable[enemy_id] (shared by SpawnPoint and the
## boss's adds). The caller adds it to the tree. Returns null for an unknown id.
static func create(scene: PackedScene, enemy_id: String, at: Vector2, spawn_point: Node2D) -> Node2D:
	var def := EnemyTable.get_def(enemy_id)
	if scene == null or def.is_empty():
		return null
	var enemy: Node2D = scene.instantiate()
	enemy.global_position = at
	enemy.spawn_point = spawn_point
	enemy.enemy_name = def["name"]
	enemy.max_hp = def["max_hp"]
	enemy.move_speed = def["move_speed"]
	enemy.attack_damage_min = def["attack_min"]
	enemy.attack_damage_max = def["attack_max"]
	enemy.aggro_range = def["aggro_range"]
	enemy.xp_reward = def["xp_reward"]
	enemy.gold_min = def["gold_min"]
	enemy.gold_max = def["gold_max"]
	enemy.loot_level = def["loot_level"]
	enemy.sprite_size = def["sprite_size"]
	enemy.sprite_tint = def["tint"]
	enemy.guaranteed_drop_id = def["guaranteed_drop"]
	enemy.mechanics = String(def.get("mechanics", ""))
	enemy.get_node("AnimatedSprite2D").sprite_frames = load(EnemyTable.SPRITE_FRAMES[def["sprite"]])
	return enemy
```

- [ ] **Step 3: `SpawnPoint`**

Rewrite `_spawn` to use the factory with identical behavior (keep the `push_warning` for an unknown id and the deferred `add_child` to `current_scene`), add exports and dungeon handling:

```gdscript
## Dungeon spawn points spawn once (no respawn) and mark their enemy for the run.
@export var dungeon: bool = false
## The final boss of a dungeon: its death clears the run.
@export var final_boss: bool = false
```

In `_spawn`, after creating the enemy: `if dungeon: current_enemy.add_to_group("dungeon_enemies")`, `if final_boss: current_enemy.add_to_group("dungeon_final")`. In `on_enemy_died`, `if dungeon: return` right after `current_enemy = null`.

- [ ] **Step 4: `Enemy`**

1. `@export var mechanics: String = ""`; in `_ready` after the existing setup: `if mechanics != "": add_child(BossMechanics.new())`.
2. Threat: change `_find_nearest_target` so that when `GameState.in_dungeon` it delegates to:

```gdscript
func _find_target_with_threat() -> Node2D:
	var nodes: Array = []
	var candidates: Array = []
	for node in get_tree().get_nodes_in_group("combat_targets"):
		if not is_instance_valid(node) or node.is_dead:
			continue
		nodes.append(node)
		candidates.append({"dist": global_position.distance_to(node.global_position), "is_tank": str(node.get("job_role")) == "tank"})
	var index := ThreatRules.pick_target(candidates, aggro_range)
	return null if index < 0 else nodes[index]
```

   The existing nearest-target loop stays as the non-dungeon path, unchanged.
3. `_drop_loot`: pass the dungeon flag to the bonus roll: `LootTable.roll_boss_bonus(rng, loot_level, guaranteed_drop_id, is_in_group("dungeon_enemies"))`.

- [ ] **Step 5: `Character.job_role`**

Add `var job_role: String: get: return String(class_def.get("role", ""))` (a read-only property).

- [ ] **Step 6: `BossMechanics`**

Create `scripts/entities/boss_mechanics.gd`:

```gdscript
class_name BossMechanics
extends Node

## The Hollow King's mechanics (child of the Enemy): a telegraphed heavy strike
## on the tank every EncounterLogic.HEAVY_INTERVAL_MS and, once at 50% HP, two
## adds. Timing and numbers live in EncounterLogic.

const VICTIM_RANGE := 320.0
const ENEMY_SCENE := "res://scenes/entities/Enemy.tscn"

var boss: Node2D
var next_heavy_ms: float = 0.0
var windup_end_ms: float = -1.0
var adds_done: bool = false

func _ready() -> void:
	boss = get_parent()
	next_heavy_ms = _now() + EncounterLogic.HEAVY_INTERVAL_MS

func _now() -> float:
	return float(boss.get("game_time_ms"))

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(boss) or bool(boss.get("is_dead")):
		return
	var now := _now()
	if windup_end_ms >= 0.0:
		if now >= windup_end_ms:
			_strike()
			windup_end_ms = -1.0
			next_heavy_ms = now + EncounterLogic.HEAVY_INTERVAL_MS
	elif EncounterLogic.heavy_due(now, next_heavy_ms) and _pick_victim() != null:
		windup_end_ms = now + EncounterLogic.HEAVY_WINDUP_MS
		GameState.emit_signal("dungeon_event", "warning", "%s winds up!" % String(boss.get("enemy_name")))
		_flash_red()
	if EncounterLogic.add_phase_due(int(boss.get("hp")), int(boss.get("max_hp")), adds_done):
		adds_done = true
		_spawn_adds()

func _pick_victim() -> Node2D:
	var nodes: Array = []
	var candidates: Array = []
	for node in get_tree().get_nodes_in_group("combat_targets"):
		if not is_instance_valid(node) or node.is_dead:
			continue
		var dist := boss.global_position.distance_to(node.global_position)
		if dist > VICTIM_RANGE:
			continue
		nodes.append(node)
		candidates.append({"dist": dist, "is_tank": str(node.get("job_role")) == "tank"})
	var index := ThreatRules.pick_target(candidates, VICTIM_RANGE)
	return null if index < 0 else nodes[index]

func _strike() -> void:
	var victim := _pick_victim()
	if victim == null:
		return
	var damage := EncounterLogic.heavy_damage(int(boss.get("attack_damage_max")))
	if victim == GameState.character:
		victim.take_damage(damage, false, boss)
	else:
		victim.take_damage(damage)

func _flash_red() -> void:
	if not GameState.fx_enabled:
		return
	var sprite := boss.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null:
		return
	var base: Color = sprite.get_meta("fx_base_modulate", sprite.modulate) if sprite.has_meta("fx_base_modulate") else sprite.modulate
	sprite.modulate = Color(1.6, 0.4, 0.4, 1.0)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", base, EncounterLogic.HEAVY_WINDUP_MS / 1000.0)

func _spawn_adds() -> void:
	var scene: PackedScene = load(ENEMY_SCENE)
	for i in range(EncounterLogic.ADD_COUNT):
		var offset := Vector2(60.0 if i == 0 else -60.0, 50.0)
		var add := EnemyFactory.create(scene, "vault_wraith", boss.global_position + offset, null)
		if add == null:
			continue
		add.add_to_group("dungeon_enemies")
		get_tree().current_scene.add_child.call_deferred(add)
```

- [ ] **Step 7: Tests and parse**

Run the tests (`0 failures`) and `"$GODOT" --headless --path . --quit 2>&1 | grep -iE "error|parse"` (nothing about the changed files).

- [ ] **Step 8: Commit**

```bash
git add scripts/systems/enemy_factory.gd scripts/systems/enemy_factory.gd.uid scripts/entities scripts/autoload/game_state.gd
git commit -m "Enemy factory, dungeon spawns, threat targeting and boss mechanics

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

(Include the `.uid` for `boss_mechanics.gd`.)

---

### Task 4: AI states and Character wiring

**Files:**
- Modify: `scripts/ai/ai_decision.gd`, `scripts/entities/character.gd`
- Modify: `tests/suite_ai_decision.gd`

- [ ] **Step 1: Failing tests**

In `tests/suite_ai_decision.gd`, before the final `t.done()` add:

```gdscript
	# dungeon_enter: below flee/rest/combat, quest and job change, above chase
	var gate := _ctx(1.0, false)
	gate["dungeon_ready"] = true
	t.check_eq(AIDecision.resolve_state(gate)["state"], "dungeon_enter", "dungeon ready, nothing else to do: dungeon_enter")
	var gate_chase := _ctx(1.0, true)
	gate_chase["dungeon_ready"] = true
	t.check_eq(AIDecision.resolve_state(gate_chase)["state"], "dungeon_enter", "dungeon_enter beats chase")
	var gate_fight := _ctx(1.0, true, true)
	gate_fight["dungeon_ready"] = true
	t.check_eq(AIDecision.resolve_state(gate_fight)["state"], "combat", "combat beats dungeon_enter")
	var gate_hurt := _ctx(0.05, true, true)
	gate_hurt["dungeon_ready"] = true
	t.check_eq(AIDecision.resolve_state(gate_hurt)["state"], "flee", "flee beats dungeon_enter")
	var gate_quest := _ctx(1.0, false)
	gate_quest["dungeon_ready"] = true
	gate_quest["quest_giver_in_zone"] = true
	gate_quest["quest_ready"] = true
	t.check_eq(AIDecision.resolve_state(gate_quest)["state"], "quest", "a quest to turn in comes first")
	var gate_job := _ctx(1.0, false)
	gate_job["dungeon_ready"] = true
	gate_job["job_change_ready"] = true
	t.check_eq(AIDecision.resolve_state(gate_job)["state"], "job_change", "a job change comes first")
	t.check(String(AIDecision.resolve_state(gate)["reason"]).contains("Vault Gate"), "the reason mentions the gate")

	# dungeon_advance: inside a dungeon with nothing to fight or pick up
	var inside := _ctx(1.0, false)
	inside["dungeon_active"] = true
	t.check_eq(AIDecision.resolve_state(inside)["state"], "dungeon_advance", "inside the dungeon: press on")
	var inside_fight := _ctx(1.0, true)
	inside_fight["dungeon_active"] = true
	t.check_eq(AIDecision.resolve_state(inside_fight)["state"], "chase", "a hostile in aggro range: chase first")
	var inside_loot := _ctx(1.0, false)
	inside_loot["dungeon_active"] = true
	inside_loot["item_nearby"] = true
	t.check_eq(AIDecision.resolve_state(inside_loot)["state"], "loot", "loot before pressing on")
	var inside_travel := _ctx(1.0, false)
	inside_travel["dungeon_active"] = true
	inside_travel["ready_to_travel"] = true
	t.check_eq(AIDecision.resolve_state(inside_travel)["state"], "dungeon_advance", "pressing on beats travel")
	t.check_eq(AIDecision.resolve_state(_ctx(1.0, false))["state"], "wander", "no keys: unchanged")
```

- [ ] **Step 2: Implement `AIDecision`**

Add doc-comment entries for `dungeon_ready`, `dungeon_active` and the states `dungeon_enter`, `dungeon_advance`. Read the two keys near the others; after the `job_change_ready` block add:

```gdscript
	if dungeon_ready:
		return {"state": "dungeon_enter", "reason": "Heading to the Vault Gate"}
```

and after the `item_nearby` loot block and before `ready_to_travel` add:

```gdscript
	if dungeon_active:
		return {"state": "dungeon_advance", "reason": "Pressing on through the Vault"}
```

Run the tests: `0 failures`.

- [ ] **Step 3: `Character`**

1. Constants/vars near the job-switching ones:

```gdscript
const DUNGEON_MIN_LEVEL := 8
const DUNGEON_COOLDOWN_MS := 900000.0
const DUNGEON_ENTER_RANGE := 30.0
var dungeon_cooldown_until_ms: float = 0.0
var dungeons_cleared: int = 0
```

   and `"dungeon_enter": "Entering the Vault", "dungeon_advance": "Pressing on"` in `STATE_DISPLAY_NAMES`.
2. Helpers:

```gdscript
## The Vault Gate in the current zone, or null.
func _vault_gate_here() -> Node2D:
	var gate := _find_nearest_in_group("vault_gates")
	if gate != null and _zone_id_for_position(gate.global_position) == current_zone_id:
		return gate
	return null

func _dungeon_ready() -> bool:
	if not GameState.dungeon_enabled or GameState.in_dungeon:
		return false
	if level < DUNGEON_MIN_LEVEL or float(hp) < float(max_hp) * 0.7 or game_time_ms < dungeon_cooldown_until_ms:
		return false
	return _vault_gate_here() != null

## Bonus for clearing the dungeon (called by DungeonRun).
func grant_dungeon_reward(bonus_xp: int, bonus_gold: int) -> void:
	dungeons_cleared += 1
	gain_xp(bonus_xp)
	_gain_gold(bonus_gold)
```

3. `_build_context`: add `"dungeon_ready": _dungeon_ready(), "dungeon_active": GameState.in_dungeon,`; make `ready_to_travel` false inside a dungeon by prefixing the whole expression with `not GameState.in_dungeon and (...)`; and make `_job_crystal_here()` return null when `GameState.in_dungeon` (first line).
4. `_act`: add arms

```gdscript
		"dungeon_enter":
			var gate := _vault_gate_here()
			if gate:
				var to_gate := gate.global_position - global_position
				if to_gate.length() <= DUNGEON_ENTER_RANGE:
					var run = get_tree().get_first_node_in_group("dungeon_run")
					if run != null:
						run.start(self, gate.global_position)
					else:
						dungeon_cooldown_until_ms = game_time_ms + 60000.0
				else:
					_move_toward(to_gate, MOVE_SPEED)
			base_anim = "walk"
		"dungeon_advance":
			var foe := _find_nearest_in_group("dungeon_enemies")
			if foe:
				_move_toward(foe.global_position - global_position, MOVE_SPEED)
			base_anim = "run"
```

- [ ] **Step 4: Tests and parse**

Run the tests (`0 failures`) and the parse check.

- [ ] **Step 5: Commit**

```bash
git add scripts/ai/ai_decision.gd scripts/entities/character.gd tests/suite_ai_decision.gd
git commit -m "AI: dungeon_enter and dungeon_advance states, Character dungeon wiring

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Scenes, the run, party frames

**Files:**
- Create: `scenes/world/VaultGate.tscn`, `scripts/world/vault_gate.gd`, `scenes/world/HollowedVault.tscn`, `scripts/world/dungeon_run.gd`
- Modify: `scenes/world/SunderedCrypt.tscn`, `scripts/main.gd`, `scripts/ui/party_frames.gd` (and the chat/log positions in `scenes/ui/SpectatorUI.tscn` if needed)

- [ ] **Step 1: Vault Gate**

`scripts/world/vault_gate.gd`:

```gdscript
extends Node2D

## The portal into the Hollowed Vault (see DungeonRun). Drawn in code.

func _ready() -> void:
	add_to_group("vault_gates")
	var ring := Polygon2D.new()
	ring.polygon = _circle(30.0, 24)
	ring.color = Color(0.55, 0.25, 0.85, 0.85)
	add_child(ring)
	var core := Polygon2D.new()
	core.polygon = _circle(18.0, 20)
	core.color = Color(0.12, 0.04, 0.22, 0.95)
	add_child(core)
	var label := Label.new()
	label.text = "Vault Gate"
	label.position = Vector2(-32, 34)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.85, 0.7, 1.0, 1.0))
	add_child(label)
	var tween := create_tween().set_loops()
	tween.tween_property(ring, "scale", Vector2(1.12, 1.12), 1.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(ring, "scale", Vector2(1.0, 1.0), 1.0).set_trans(Tween.TRANS_SINE)

func _circle(radius: float, points: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(points):
		var angle := TAU * float(i) / float(points)
		result.append(Vector2(cos(angle), sin(angle)) * radius)
	return result
```

`scenes/world/VaultGate.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/world/vault_gate.gd" id="1_gate"]

[node name="VaultGate" type="Node2D"]
script = ExtResource("1_gate")
```

Place one instance in `scenes/world/SunderedCrypt.tscn` (CRLF file; add an `ext_resource`, bump `load_steps`, node `VaultGate` at `Vector2(-120, 120)`; the crypt room is 360x360 centered on the scene origin, so this is inside it and away from the Crypt Lord).

- [ ] **Step 2: The vault scene**

Create `scenes/world/HollowedVault.tscn` (text scene; root `Node2D` named `HollowedVault`): a `ColorRect` floor `Color(0.09, 0.07, 0.12, 1)` covering `Rect2(-750, -200, 1500, 400)`, two dividing wall `ColorRect`s (thin dark bars with 120 px gaps) at x = -250 and x = 250, and `SpawnPoint` instances (`res://scenes/entities/SpawnPoint.tscn`, `enemy_scene` = `res://scenes/entities/Enemy.tscn`, `dungeon = true`, `respawn_delay_s` irrelevant). Positions are local (the scene is placed at world (12000, 0)):

| enemy_id | positions |
|---|---|
| `vault_skeleton` (room 1: three packs of two) | (-500,-70), (-500,70), (-400,-110), (-400,110), (-320,-40), (-320,40) |
| `bone_warden` (room 2, mini-boss) | (0, 0) |
| `vault_skeleton` (room 2 guards) | (40,-90), (40,90) |
| `hollow_king` (room 3, `final_boss = true`) | (520, 0) |

Copy the header/`ext_resource` pattern from an existing zone scene such as `scenes/world/MirewaterSwamp.tscn` (SpawnPoint scene path and Enemy scene path). The entrance is at local (-700, 0).

- [ ] **Step 3: `DungeonRun`**

Create `scripts/world/dungeon_run.gd`:

```gdscript
class_name DungeonRun
extends Node

## Runs one Hollowed Vault instance: builds the five-person party (PartyBuilder),
## instantiates the vault far from the open world, teleports everyone in, and
## ends the run on a clear, the hero's death or a timeout, restoring the party.

const VAULT_SCENE := "res://scenes/world/HollowedVault.tscn"
const VAULT_ORIGIN := Vector2(12000, 0)
const ENTRANCE_OFFSET := Vector2(-700, 0)
const PARTY_SIZE := 5
const RUN_TIMEOUT_S := 720.0
const CLEAR_DELAY_S := 6.0
const CLEAR_BONUS_XP := 600
const CLEAR_BONUS_GOLD := 150
const LEFTOVER_ITEM_X := 11000.0

var running: bool = false
var hero: Node2D = null
var vault: Node2D = null
var run_time_s: float = 0.0
var clear_timer_s: float = -1.0
var gate_position: Vector2 = Vector2.ZERO
var pulled: Array = []

func _ready() -> void:
	add_to_group("dungeon_run")
	GameState.enemy_died.connect(_on_enemy_died)

## Starts a run for `hero_node` (the Character) from a gate at `gate_pos`.
func start(hero_node: Node2D, gate_pos: Vector2) -> bool:
	if running or hero_node == null:
		return false
	hero = hero_node
	gate_position = gate_pos
	pulled.clear()
	var party_entries: Array = []
	for ally in hero.party:
		if is_instance_valid(ally):
			party_entries.append({"id": ally.player_name, "name": ally.player_name, "role": str(ally.get("job_role"))})
	var pool: Array = []
	for sp in get_tree().get_nodes_in_group("simulated_players"):
		if is_instance_valid(sp) and sp.group_leader == null and not sp.is_dead:
			pool.append({"id": sp.player_name, "name": sp.player_name, "role": str(sp.get("job_role")), "node": sp})
	for pick in PartyBuilder.missing_members(str(hero.get("job_role")), party_entries, pool, PARTY_SIZE):
		var ally = pick["node"]
		ally.group_leader = hero
		hero.party.append(ally)
		pulled.append(ally)
		GameState.log_event("%s answers the call" % ally.player_name)
	GameState.emit_signal("party_changed")
	vault = (load(VAULT_SCENE) as PackedScene).instantiate()
	vault.position = VAULT_ORIGIN
	get_parent().add_child(vault)
	var entrance := VAULT_ORIGIN + ENTRANCE_OFFSET
	hero.global_position = entrance
	hero.wander_target = entrance
	hero.travel_destination_id = ""
	var slot := 0
	for ally in hero.party:
		if is_instance_valid(ally) and not ally.is_dead:
			ally.global_position = entrance + Vector2(-30.0, -60.0 + 30.0 * float(slot))
			slot += 1
	GameState.in_dungeon = true
	running = true
	run_time_s = 0.0
	clear_timer_s = -1.0
	GameState.log_event("The party enters the Hollowed Vault")
	GameState.emit_signal("dungeon_event", "enter", "Hollowed Vault")
	return true

func _physics_process(delta: float) -> void:
	if not running:
		return
	run_time_s += delta
	if not is_instance_valid(hero) or bool(hero.get("is_dead")):
		_end_run("failed")
	elif clear_timer_s >= 0.0:
		clear_timer_s -= delta
		if clear_timer_s <= 0.0:
			_end_run("cleared")
	elif run_time_s >= RUN_TIMEOUT_S:
		_end_run("timeout")

func _on_enemy_died(enemy: Node2D) -> void:
	if running and clear_timer_s < 0.0 and is_instance_valid(enemy) and enemy.is_in_group("dungeon_final"):
		clear_timer_s = CLEAR_DELAY_S
		hero.grant_dungeon_reward(CLEAR_BONUS_XP, CLEAR_BONUS_GOLD)
		GameState.log_event("The Hollow King falls: dungeon cleared!")
		GameState.emit_signal("dungeon_event", "clear", "Hollowed Vault")

func _end_run(result: String) -> void:
	running = false
	for enemy in get_tree().get_nodes_in_group("dungeon_enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	for item in get_tree().get_nodes_in_group("items"):
		if is_instance_valid(item) and item.global_position.x > LEFTOVER_ITEM_X:
			item.queue_free()
	if is_instance_valid(vault):
		vault.queue_free()
	GameState.in_dungeon = false
	var home := gate_position + Vector2(0.0, 60.0)
	if is_instance_valid(hero):
		if not bool(hero.get("is_dead")):
			hero.global_position = home
			hero.wander_target = home
		hero.dungeon_cooldown_until_ms = float(hero.get("game_time_ms")) + hero.DUNGEON_COOLDOWN_MS
		var slot := 0
		for ally in hero.party.duplicate():
			if not is_instance_valid(ally):
				continue
			if pulled.has(ally):
				hero.party.erase(ally)
				ally.group_leader = null
				ally.global_position = ally.spawn_position
			elif not ally.is_dead:
				ally.global_position = home + Vector2(-30.0, -30.0 + 30.0 * float(slot))
				slot += 1
	pulled.clear()
	GameState.emit_signal("party_changed")
	if result != "cleared":
		GameState.log_event("The dungeon run ended (%s)" % result)
		GameState.emit_signal("dungeon_event", "fail", "Hollowed Vault")
	GameState.emit_signal("dungeon_finished", result, run_time_s)
```

- [ ] **Step 4: `main.gd` wiring**

In `_ready`, after the other `add_child(...)` nodes: `add_child(DungeonRun.new())`.

- [ ] **Step 5: Party frames for five**

`PartyFrames` currently lists every `leader.party` member (up to 2, now up to 4 inside a dungeon). At 1152x648 four frames of `FRAME_SIZE` (224x40, separation 6) end near y = 176 + 4 * 46 = 360, which overlaps the chat panel (starts about y = 270). Fix the layout without hiding anything: reduce `FRAME_SIZE.y` to 32 and shift the bar/text positions accordingly (name label at y = 0, bar at y = 17, bar height 10), keep the 6 px separation (4 frames end at about y = 320), and move `ChatPanel` and `ActivityLog` down in `scenes/ui/SpectatorUI.tscn` by 56 px (chat about y = 326 to 448, log about y = 456 to 616; verify nothing collides with the ability bar at the bottom centre). Check with a screenshot at 1152x648 with four allies (see the live check).

- [ ] **Step 6: Import, test, boot**

Import once (new scenes); run the tests (`0 failures`, including `suite_spawn_points` now reading `HollowedVault.tscn`: each `enemy_id` there must have `zone == "hollowed_vault"`). Boot with the Godot MCP (`run_project` with the worktree path; pick a job on the select screen: `for b in get_tree().root.find_children("*", "Button", true, false): if b.text.begins_with("Warrior"): b.pressed.emit()` then `return 1`; ~15 s until `game_eval` connects; do not probe port 9090 from bash) and confirm: the Vault Gate is visible in the crypt; `get_tree().get_first_node_in_group("dungeon_run")` exists; forcing a run (`GameState.character.level = 8`, teleport the hero to the crypt gate position and call `get_tree().get_first_node_in_group("dungeon_run").start(GameState.character, gate.global_position)`) builds a party of five, moves everyone to `(11300, 0)`, spawns the rooms' enemies, and `_end_run` (call it directly) restores everything. No errors. Stop the project.

- [ ] **Step 7: Commit**

```bash
git add scenes scripts
git commit -m "Vault Gate, the Hollowed Vault, DungeonRun and party frames for five

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

(Include the new `.uid` files for scripts and any generated for the scenes.)

---

### Task 6: UI, narrator and journal

**Files:**
- Modify: `scripts/ui/boss_events.gd`, `scripts/systems/narrator_lines.gd`, `scripts/ui/narrator_director.gd`, `scripts/ui/journal_recorder.gd`
- Modify: `tests/suite_narrator_lines.gd`

- [ ] **Step 1: Failing test**

In `tests/suite_narrator_lines.gd` change the events count assertion to 14 (`"fourteen narrated events"`), add `"dungeon": "the Hollowed Vault"` to `CONTEXT`, and before `t.done()` add:

```gdscript
	t.check(NarratorLines.line_for("dungeon_enter", "steady", CONTEXT, 0.1).contains("Hollowed Vault"), "dungeon entry line names the dungeon")
	t.check(NarratorLines.line_for("dungeon_clear", "steady", CONTEXT, 0.1).contains("Hollowed Vault"), "clear line names the dungeon")
	t.check(NarratorLines.line_for("dungeon_fail", "steady", CONTEXT, 0.1) != "", "fail line exists")
```

Run the tests: expect failures.

- [ ] **Step 2: `NarratorLines`**

Add `"dungeon_enter", "dungeon_clear", "dungeon_fail"` to `EVENTS`, add `"dungeon": "the dungeon"` to `FALLBACKS`, and to `TEMPLATES` (placeholders `{name}`, `{dungeon}`; keep to plain text, no `%`, `[` or `{` besides placeholders):

```gdscript
	"dungeon_enter": {
		"neutral": ["The party gathers and steps through the gate into {dungeon}.", "{name} leads four companions into {dungeon}."],
		"cautious": ["{name} counts the party twice before entering {dungeon}."],
		"reckless": ["{name} is through the gate into {dungeon} before the others can speak."],
		"greedy": ["{dungeon} must be full of treasure. {name} goes in first."],
		"explorer": ["A place no map shows: {name} enters {dungeon}."],
	},
	"dungeon_clear": {
		"neutral": ["{dungeon} is cleared. The party walks out victorious.", "Silence falls in {dungeon}. It is done."],
		"cautious": ["{dungeon} is cleared, and everyone is still standing. {name} exhales."],
		"reckless": ["{dungeon} is cleared. {name} wants to do it again."],
		"greedy": ["{dungeon} is cleared, and the loot is even better than hoped."],
		"explorer": ["{dungeon} is cleared. {name} is already thinking about the next one."],
	},
	"dungeon_fail": {
		"neutral": ["{dungeon} was too much. The party retreats.", "The run in {dungeon} ends in defeat."],
		"cautious": ["{name} should have known better than to trust the odds in {dungeon}."],
		"reckless": ["{name} pushed too far in {dungeon}."],
		"greedy": ["{dungeon} keeps its treasure, this time."],
		"explorer": ["{dungeon} was a road too far, for now."],
	},
```

- [ ] **Step 3: Listeners**

`narrator_director.gd` `_ready`: connect `GameState.dungeon_event` to a handler mapping kinds `enter` -> `dungeon_enter`, `clear` -> `dungeon_clear`, `fail` -> `dungeon_fail` with context `{"dungeon": "the Hollowed Vault"}`; these three events bypass the cooldown like the boss events (read `_say` and follow how boss events bypass). `journal_recorder.gd` `_ready`: connect `GameState.dungeon_event` and add `Entered the Hollowed Vault`, `Cleared the Hollowed Vault` (also `Cleared` once per clear) and `Fell in the Hollowed Vault` for `enter`/`clear`/`fail` (ignore `warning`).

- [ ] **Step 4: Banners**

`boss_events.gd`: connect `GameState.dungeon_event` to `_on_dungeon_event(kind, text)` and show banners with the existing `_show_banner(text, color)` helper: `enter` -> `"ENTERING THE HOLLOW VAULT"` style text `"ENTERING THE HOLLOWED VAULT"` (violet), `warning` -> the given text uppercased with an exclamation, red, short hold; `clear` -> `"DUNGEON CLEARED"` (gold); `fail` -> `"DUNGEON FAILED"` (red).

- [ ] **Step 5: Tests and boot check**

Run the tests (`0 failures`). Boot with the Godot MCP and force `GameState.emit_signal("dungeon_event", "clear", "Hollowed Vault")` etc.: the banners show, a Story line appears (cooldown bypassed), the journal (`J`) has the entry. No ERROR lines. Stop the project.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui scripts/systems/narrator_lines.gd tests/suite_narrator_lines.gd
git commit -m "Dungeon banners, narrator lines and journal entries

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Sim flag, logging, regression

**Files:**
- Modify: `tests/sim/sim_run.gd`, `tests/sim/sim_monitor.gd`, `tests/sim/summarize.py`

- [ ] **Step 1: Sim**

`sim_run.gd`: next to the other flags add `GameState.dungeon_enabled = args.get("dungeon", "0") == "1"` and document `dungeon=0|1` (default 0) in the header. `sim_monitor.gd`: connect `GameState.dungeon_finished` to `_on_dungeon_finished(result, duration)` emitting `_emit("dungeon", {"result": result, "dur": "%.0f" % duration})`, and `GameState.dungeon_event` for kind `enter` emitting `_emit("dungeon_enter", {"level": ch.level})`. `summarize.py`: parse `dungeon` events into `run["dungeons"]` (result, dur) and add per-class aggregate rows `dungeon runs`, `dungeon clear rate` (`cleared/total`), `dungeon mean minutes`, and `dungeon timeouts`, without changing the per-run table columns.

- [ ] **Step 2: Regression with the dungeon off**

```bash
export GODOT="C:/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
rm -rf "$TEMP/simD0" && tests/sim/run_batch.sh "$TEMP/simD0" 45 "warrior mage white_mage thief black_belt dragoon red_mage" "1 2" 12 trait=steady > /dev/null 2>&1
for f in "$TEMP"/simD0/*.log; do b=$(basename $f); c=${b%_s*}; a=$(python tests/sim/summarize.py "$TEMP/simJC_$c/$b" | head -2 | tail -1 | tr -s ' '); d=$(python tests/sim/summarize.py "$f" | head -2 | tail -1 | tr -s ' '); [ "$a" == "$d" ] && echo "SAME $b" || echo "DIFF $b"; done
```

Expected: 14 `SAME`. A `DIFF` means something in Tasks 2 to 4 changed behavior with the dungeon off (likely the `SpawnPoint` refactor, the new spawn order, the loot bonus argument or a context change): find and fix before continuing.

- [ ] **Step 3: Smoke run with the dungeon on**

`tests/sim/run_batch.sh "$TEMP/simD_smoke" 40 "warrior" "1" 1 trait=steady dungeon=1`: the log has no SCRIPT ERROR (a dungeon attempt may not happen yet; that is checked in Task 9).

- [ ] **Step 4: Commit**

```bash
git add tests/sim
git commit -m "Sim: dungeon flag, logging and summary

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Live check

- [ ] **Step 1: Run the checks** (Godot MCP; worktree path; ~15 s until `game_eval` connects; no bash probes of port 9090; explicit `return` in `game_eval`; use `Engine.time_scale = 4.0` to speed up, reset to 1.0 for screenshots)

1. Start as a Warrior. Give the hero level 8 (`gain_xp(4000)`), teleport it into the Sundered Crypt near the gate (`global_position = crypt_gate.global_position + Vector2(-60, 0)`, gate found by `get_tree().get_first_node_in_group("vault_gates")`), and let the AI run: the state becomes `dungeon_enter`, the hero walks to the gate and the run starts by itself (log `The party enters the Hollowed Vault`, banner `ENTERING THE HOLLOWED VAULT`).
2. The party is five (`GameState.character.party.size() == 4`), with a tank and a healer when the pool has them (check roles via `job_role`); screenshot the HUD with four party frames (no overlap with the chat panel or the activity log at 1152x648).
3. Watch the run at 4x: enemies in room 1 engage; the tank ally (Kaelen, Warrior) draws the enemies (check a few enemies' targets or the party frame HP); the hero advances (`dungeon_advance`, `Pressing on`). At the Hollow King: the warning banner `HOLLOW KING WINDS UP!` appears about 1.5 s before a big hit on the tank; at 50% HP two Vault Wraiths spawn.
4. Kill the king (`take_damage(99999, GameState.character)` on it if needed): `DUNGEON CLEARED` banner, the hero picks up loot (`wardens_plate` or `hollow_crown` or a dungeon epic) within the 6 s delay, then everyone returns to the crypt; allies pulled from other zones return to their spawn positions; `GameState.in_dungeon == false`; `dungeons_cleared == 1`; the journal has `Entered ...` and `Cleared the Hollowed Vault`.
5. Failure path: start another run (clear `dungeon_cooldown_until_ms`), set `GameState.character.hp = 1` and hit it with a huge `take_damage`: the run ends as failed (banner `DUNGEON FAILED`), the vault instance and enemies are gone, allies are released and the hero respawns in the meadow.
6. No ERROR lines in `get_debug_output` (ignore `mcp_interaction_server.gd` warnings). Note stuck states: the hero never entering the gate, everyone standing still in the vault, enemies left behind after the run.

- [ ] **Step 2: Fix anything found** in the relevant script (keep `dungeon=0` behavior identical), re-run the tests and, if `Character`, `Enemy` or `SpawnPoint` changed, the Task 7 regression; commit as `Fix: <what>`.

---

### Task 9: Balance measurement (dungeon on)

**Files:**
- Modify (only if tuning is needed): `scripts/systems/enemy_table.gd`, `scripts/systems/encounter_logic.gd`, `scripts/entities/character.gd` (`DUNGEON_COOLDOWN_MS`, `DUNGEON_MIN_LEVEL`)
- Modify: `docs/superpowers/balance/2026-09-25-balance-report.md` (section 11)

- [ ] **Step 1: Measure**

```bash
export GODOT="C:/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
for j in warrior white_mage thief; do
  rm -rf "$TEMP/simV_$j"; tests/sim/run_batch.sh "$TEMP/simV_$j" 120 "$j" "$(seq -s ' ' 1 8)" 12 trait=steady switching=1 dungeon=1 > /dev/null 2>&1
  echo "== $j"; python tests/sim/summarize.py "$TEMP/simV_$j"/*.log | grep -E "^\s*$j\s+[0-9]+\s+(final level|deaths\s|deaths / 10|job switches|dungeon)" | sed 's/  */ /g'
done > "$TEMP/simV.txt" 2>&1
```

Run in the background (30 to 45 minutes) and wait for `== thief` to have its rows.

- [ ] **Step 2: Acceptance** per starting job: at least one dungeon attempt per run; clear rate 60% to 90%; mean run time 3 to 8 minutes; timeouts at most 15% of runs; hero deaths per 10 minutes at most 1.0 for the whole run; no run stuck. Tune in small steps and re-run only the failing job: clear rate too low: lower `hollow_king`/`bone_warden` HP or damage or `HEAVY_MULT`; too high: raise them; runs too long: lower boss HP or trash counts; no attempts: `DUNGEON_MIN_LEVEL`/cooldown or the entry HP threshold. Update pinned numbers in the enemy/encounter tests in the same commit.

- [ ] **Step 3: Report and commit**

Add section 11 to the balance report: a table per starting job (attempts, clear rate, mean minutes, timeouts, deaths per 10 minutes), the tuning applied and why:

```bash
git add scripts docs tests
git commit -m "Balance: measure and tune the Hollowed Vault

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: README, final review and merge

- [ ] **Step 1: README**

Add a feature bullet (`Five-man dungeon: the Hollowed Vault, an instanced three-room dungeon entered from the Vault Gate in the Sundered Crypt. A role party of five (tank, healer, three damage) forms at the gate; enemies attack the tank, the final boss telegraphs heavy strikes and summons adds, and clearing it drops dungeon-only epics`) and, if the live check gave a good screenshot of the vault or the five party frames, save it to `docs/screenshots/` and add it to the Screenshots section.

- [ ] **Step 2: Final tests and review**

Run the tests (`0 failures`). Dispatch a review subagent over `git diff main...dungeon` focused on: exactness with `dungeon_enabled = false` (the `SpawnPoint`/`EnemyFactory` refactor, the loot bonus argument, context keys, `ready_to_travel` expression); `DungeonRun` edge cases (hero dying during the clear delay, allies dying or being freed mid-run, `pulled` allies already grouped, pool empty, the run starting twice, `party_changed` and party frames, the hero respawning while `in_dungeon` is still true, leftover items/enemies, leaked vault instance); threat rules (allies that lack `job_role`, dead targets, the tank out of range); `BossMechanics` (boss freed mid-wind-up, victim freed, timers while the game is paused or slowed, `game_time_ms` source, adds spawning after death); zone/world-bounds changes (`WORLD_BOUNDS_MAX`, hero wandering into the empty corridor, camera, allies' clamp, codex `zone_order`); UI fit at 1152x648; test pins. Fix real findings.

- [ ] **Step 3: Commit and merge**

```bash
git add README.md docs
git commit -m "Docs: five-man dungeon

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

Fast-forward merge `dungeon` into `main` from the main checkout, re-import and re-run the tests on `main`, remove the worktree (`git worktree remove --force .claude/worktrees/dungeon`; a Windows "Permission denied" on the folder is harmless) and delete the branch. Push only when the user asks.
