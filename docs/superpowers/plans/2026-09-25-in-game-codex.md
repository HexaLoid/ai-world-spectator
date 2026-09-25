# In-Game Codex Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A toggleable codex panel (Bestiary / Items / Zones) whose entries fill in as the spectated character discovers them.

**Architecture:** Pure, headless-tested classes hold the logic (`CodexState` discovery flags, `CodexData` derived facts, `CodexText` BBCode). `Character` reports discoveries into `GameState.codex`; a thin `CodexPanel` node renders it.

**Tech Stack:** Godot 4.7 (mono build, GDScript only), headless `--script` test runner.

**Spec:** `docs/superpowers/specs/2026-09-25-in-game-codex-design.md`

---

## Conventions used in every task

- Work in a dedicated git worktree/branch (e.g. `codex`). A fresh checkout needs **two** headless editor passes before scripts and textures resolve.
- Shell variable (bash on Windows):

```bash
GODOT="/c/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
```

- **Import pass** (registers new `class_name` scripts, writes `.gd.uid` sidecars). Run from the project root whenever a task adds a script, *before* running tests:

```bash
"$GODOT" --headless --path . --editor --quit
```

- **Run tests** (from the project root; `timeout` guards against a hung console exe):

```bash
timeout 90 "$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1 | tail -3
```

  Baseline before this plan: `8955 checks, 0 failures`. Failures print lines starting `FAIL:`; a suite that fails to parse is reported as `FAIL: suite failed to load`. **Every suite's `run(t)` must end with `t.done()`**, and the runner fails a suite that ends early. Always also confirm `... 2>&1 | grep -c "SCRIPT ERROR"` prints `0`.
- Commit `.gd.uid` sidecars next to new scripts. Do **not** commit Godot's line-ending-only rewrites of `.import` files, the `mcp_interaction_server` autoload line in `project.godot`, or `mcp_interaction_server.gd*`.
- Commit messages end with: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`
- **Line endings:** many files are CRLF in the working tree (git normalizes to LF in commits). Preserve each file's existing line endings when editing (Python with `newline=''`, inserting text with the file's own ending) and check `git diff --stat` shows only the lines you meant to change. New files may be LF.
- If an edit tool fails to match multi-line text, match on a single line without leading tabs, or use a small Python script.
- **Live checks** use the Godot MCP tools (`mcp__godot__run_project` with `projectPath` = the worktree, then `game_screenshot`, `game_get_errors`, `get_debug_output`, `game_click`, `game_key_press`, `game_eval`, `stop_project`). They may be deferred: load with ToolSearch `select:`. The `game_*` tools need several seconds after `run_project` to connect; retry. Window is 1152x648; click the HUD `4x` button (~x=613,y=28) to speed up. Teleport with `game_eval`: `get_node("/root/Main/Character").global_position = Vector2(x, y)`. Only the MCP plugin's own warnings from `mcp_interaction_server.gd` are acceptable in `game_get_errors`. Never call `game_get_property` with an unknown property name, and never read a key that may not exist in a `game_eval` snippet (a script error halts the debugger).

## File structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/systems/codex_state.gd` | create | Pure discovery flags |
| `scripts/systems/codex_data.gd` | create | Pure derived facts (item sources, zone rosters, orderings) |
| `scripts/ui/codex_text.gd` | create | Pure BBCode entry text |
| `scripts/ui/codex_panel.gd` | create | Panel: tabs, list, portrait, detail |
| `scripts/systems/enemy_table.gd` | modify | `zone` field per enemy |
| `scripts/autoload/game_state.gd` | modify | `codex`, `codex_changed` |
| `scripts/entities/character.gd` | modify | Discovery hooks |
| `scenes/ui/SpectatorUI.tscn` | modify | `CodexPanel`, `CodexButton` |
| `tests/suite_codex_state.gd`, `suite_codex_data.gd`, `suite_codex_text.gd` | create | Unit tests |
| `tests/suite_enemy_table.gd`, `tests/suite_spawn_points.gd`, `tests/run_tests.gd` | modify | Zone checks, registration |
| `README.md` | modify | Controls and features |

---

### Task 1: Enemy `zone` field and consistency tests

**Files:**
- Modify: `scripts/systems/enemy_table.gd`, `tests/suite_enemy_table.gd`, `tests/suite_spawn_points.gd`

- [ ] **Step 1: Write the failing tests**

In `tests/suite_enemy_table.gd`, inside the `for id in EnemyTable.ENEMIES:` loop (next to the other per-enemy checks) add:

```gdscript
		t.check(ZoneTable.ZONES.has(def.get("zone", "")), "%s has a valid zone (%s)" % [id, def.get("zone", "")])
```

In `tests/suite_spawn_points.gd`, replace the whole `run` function with a version that also checks that each spawn's enemy zone matches the scene's zone. The scene file name maps to a zone id through this table (add it above `run`):

```gdscript
const SCENE_ZONES := {
	"ThornfieldMeadow.tscn": "thornfield_meadow",
	"BlackthornForest.tscn": "blackthorn_forest",
	"SunderedCrypt.tscn": "sundered_crypt",
	"MirewaterSwamp.tscn": "mirewater_swamp",
	"FrostpeakPass.tscn": "frostpeak_pass",
}
```

and, inside the per-match loop, after the existing `EnemyTable.get_def(id)` check, add:

```gdscript
			var scene_zone: String = SCENE_ZONES.get(file_name, "")
			t.check(scene_zone != "", "%s is a known zone scene" % file_name)
			t.check_eq(EnemyTable.get_def(id).get("zone", ""), scene_zone, "%s: enemy %s belongs to this scene's zone" % [file_name, id])
```

Keep the rest of the function and its final `t.done()`.

- [ ] **Step 2: Run tests to verify they fail**

Import pass, then tests. Expected: failures for the missing `zone` key (`has a valid zone` for all 12 enemies, and the scene-zone checks).

- [ ] **Step 3: Add the `zone` field**

In `scripts/systems/enemy_table.gd` add a `"zone": "<id>",` entry to each enemy dictionary (put it right after the `"name"` entry, keeping the file's line endings):

| enemy id | zone |
|---|---|
| `wolf`, `bandit` | `thornfield_meadow` |
| `dire_wolf`, `bandit_captain` | `blackthorn_forest` |
| `crypt_lord` | `sundered_crypt` |
| `mire_wolf`, `bog_bandit`, `mire_tyrant` | `mirewater_swamp` |
| `frost_wolf`, `frost_raider`, `raider_captain`, `frostpeak_warlord` | `frostpeak_pass` |

Update the doc comment above the table to mention `zone` (the home zone shown by the codex).

- [ ] **Step 4: Run tests to verify they pass**

Import pass, then tests: `0 failures`, no `SCRIPT ERROR`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/enemy_table.gd tests/suite_enemy_table.gd tests/suite_spawn_points.gd
git commit -m "Give every enemy a home zone and validate it against the zone scenes

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `CodexState`

**Files:**
- Create: `scripts/systems/codex_state.gd`, `tests/suite_codex_state.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing suite**

`tests/suite_codex_state.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	var state := CodexState.new()
	t.check_eq(state.enemies_met_count(), 0, "starts with no enemies met")
	t.check_eq(state.items_found_count(), 0, "starts with no items found")
	t.check_eq(state.zones_visited_count(), 0, "starts with no zones visited")

	# enemies
	t.check(state.discover_enemy("wolf"), "first meeting is new")
	t.check(not state.discover_enemy("wolf"), "second meeting is not new")
	t.check(state.enemy_met("wolf"), "wolf is met")
	t.check(not state.enemy_met("dire_wolf"), "dire wolf is not met")
	t.check(not state.discover_enemy("no_such_enemy"), "unknown enemy ids are ignored")
	t.check(not state.enemy_met("no_such_enemy"), "unknown enemy is never met")
	t.check_eq(state.enemies_met_count(), 1, "one enemy met")

	# items
	t.check(state.discover_item("iron_sword"), "first find is new")
	t.check(not state.discover_item("iron_sword"), "second find is not new")
	t.check(state.item_found("iron_sword"), "iron sword is found")
	t.check(state.discover_item("health_potion"), "consumables can be discovered")
	t.check(not state.discover_item("no_such_item"), "unknown item ids are ignored")
	t.check_eq(state.items_found_count(), 2, "two items found")

	# zones
	t.check(state.visit_zone("thornfield_meadow"), "first visit is new")
	t.check(not state.visit_zone("thornfield_meadow"), "second visit is not new")
	t.check(state.zone_visited("thornfield_meadow"), "meadow is visited")
	t.check(not state.visit_zone("no_such_zone"), "unknown zone ids are ignored")
	t.check_eq(state.zones_visited_count(), 1, "one zone visited")

	# independence
	t.check(not state.item_found("wolf"), "kinds do not share ids")
	t.check(not state.zone_visited("iron_sword"), "kinds do not share ids (zone)")

	# separate instances are separate
	var other := CodexState.new()
	t.check_eq(other.enemies_met_count(), 0, "a new instance starts empty")
	t.done()
```

Add `"res://tests/suite_codex_state.gd"` to `SUITES` in `tests/run_tests.gd`.

- [ ] **Step 2: Run tests to verify they fail**

Import pass, then tests. Expected: `FAIL: suite failed to load: res://tests/suite_codex_state.gd`.

- [ ] **Step 3: Implement**

`scripts/systems/codex_state.gd`:

```gdscript
class_name CodexState
extends RefCounted

## What the spectated character has discovered so far (session only). Pure
## data: no nodes, no signals; GameState wraps it and emits codex_changed.

var enemies_met: Dictionary = {}
var items_found: Dictionary = {}
var zones_visited: Dictionary = {}

## Each discover/visit call returns true only when the entry was new; unknown
## ids are ignored and return false.
func discover_enemy(id: String) -> bool:
	if not EnemyTable.ENEMIES.has(id) or enemies_met.has(id):
		return false
	enemies_met[id] = true
	return true

func discover_item(id: String) -> bool:
	if not LootTable.ITEMS.has(id) or items_found.has(id):
		return false
	items_found[id] = true
	return true

func visit_zone(id: String) -> bool:
	if not ZoneTable.ZONES.has(id) or zones_visited.has(id):
		return false
	zones_visited[id] = true
	return true

func enemy_met(id: String) -> bool:
	return enemies_met.has(id)

func item_found(id: String) -> bool:
	return items_found.has(id)

func zone_visited(id: String) -> bool:
	return zones_visited.has(id)

func enemies_met_count() -> int:
	return enemies_met.size()

func items_found_count() -> int:
	return items_found.size()

func zones_visited_count() -> int:
	return zones_visited.size()
```

- [ ] **Step 4: Run tests to verify they pass**

Import pass (new class + sidecar), then tests: `0 failures`, no `SCRIPT ERROR`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/codex_state.gd scripts/systems/codex_state.gd.uid tests/suite_codex_state.gd tests/suite_codex_state.gd.uid tests/run_tests.gd
git commit -m "Add CodexState: pure discovery flags with tests

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: `CodexData`

**Files:**
- Create: `scripts/systems/codex_data.gd`, `tests/suite_codex_data.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing suite**

`tests/suite_codex_data.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	# item sources
	var maul := CodexData.item_sources("tyrants_maul")
	t.check_eq(maul["guaranteed"], ["Mire Tyrant"], "tyrants_maul is a guaranteed Mire Tyrant drop")
	t.check_eq(maul["random_from_loot_level"], -1, "an epic never drops randomly")
	var mail := CodexData.item_sources("reinforced_mail")
	t.check_eq(mail["quests"], ["The Mire Tyrant"], "reinforced_mail is a quest reward")
	var rusty := CodexData.item_sources("rusty_sword")
	t.check_eq(rusty["random_from_loot_level"], 2, "rusty_sword first drops from loot level 2 enemies (lowest loot_level in the table)")
	t.check(rusty["guaranteed"].is_empty() and rusty["quests"].is_empty(), "rusty_sword has no fixed sources")
	var potion := CodexData.item_sources("health_potion")
	t.check_eq(potion["random_from_loot_level"], 2, "potions drop randomly like gear")
	var iron_sword := CodexData.item_sources("iron_sword")
	t.check(iron_sword["guaranteed"].has("Bandit Captain"), "iron_sword is guaranteed from the Bandit Captain")
	t.check(iron_sword["quests"].has("The Captain's Head"), "iron_sword is also a quest reward")
	var none := CodexData.item_sources("no_such_item")
	t.check(none["guaranteed"].is_empty() and none["quests"].is_empty() and int(none["random_from_loot_level"]) == -1, "unknown item has empty sources")

	# every non-epic item can be found somewhere
	for item_id in LootTable.ITEMS:
		var src := CodexData.item_sources(item_id)
		var has_source: bool = not src["guaranteed"].is_empty() or not src["quests"].is_empty() or int(src["random_from_loot_level"]) >= 0
		t.check(has_source, "%s has at least one source" % item_id)

	# zones
	t.check_eq(CodexData.zone_order(), ZoneTable.TRAVEL_ORDER, "zone_order follows the travel order")
	for zone_id in ZoneTable.ZONES:
		t.check(not CodexData.zone_enemy_ids(zone_id).is_empty(), "%s has enemies" % zone_id)
	t.check_eq(CodexData.zone_enemy_ids("mirewater_swamp"), ["mire_wolf", "bog_bandit", "mire_tyrant"], "swamp roster is ordered by hp")
	t.check_eq(CodexData.zone_boss_id("mirewater_swamp"), "mire_tyrant", "swamp boss")
	t.check_eq(CodexData.zone_boss_id("frostpeak_pass"), "frostpeak_warlord", "the pass boss is the strongest guaranteed-drop enemy")
	t.check_eq(CodexData.zone_boss_id("thornfield_meadow"), "", "the meadow has no boss")
	t.check_eq(CodexData.zone_boss_id("no_such_zone"), "", "unknown zone has no boss")
	t.check_eq(CodexData.zone_level_range("thornfield_meadow"), [1, 1], "meadow level range (the forest has no gate, so the range is one level)")
	t.check_eq(CodexData.zone_level_range("sundered_crypt"), [3, 3], "crypt level range")
	t.check_eq(CodexData.zone_level_range("frostpeak_pass"), [7, LevelingSystem.MAX_LEVEL], "the last zone runs to the level cap")

	# orderings contain every id exactly once
	var enemies := CodexData.enemy_order()
	t.check_eq(enemies.size(), EnemyTable.ENEMIES.size(), "enemy_order has every enemy")
	t.check_eq(enemies.duplicate().size(), _unique(enemies).size(), "enemy_order has no duplicates")
	t.check_eq(enemies[0], "wolf", "the weakest meadow enemy is first")
	t.check_eq(enemies[enemies.size() - 1], "frostpeak_warlord", "the final boss is last")
	var items := CodexData.item_order()
	t.check_eq(items.size(), LootTable.ITEMS.size(), "item_order has every item")
	t.check_eq(items.size(), _unique(items).size(), "item_order has no duplicates")
	t.check_eq(LootTable.ITEMS[items[0]].get("slot", ""), "weapon", "weapons come first")
	t.check_eq(LootTable.ITEMS[items[items.size() - 1]].get("type", ""), "consumable", "consumables come last")
	t.done()

func _unique(values: Array) -> Dictionary:
	var seen := {}
	for v in values:
		seen[v] = true
	return seen
```

Add `"res://tests/suite_codex_data.gd"` to `SUITES`.

- [ ] **Step 2: Run tests to verify they fail**

Import pass, then tests. Expected: `FAIL: suite failed to load: res://tests/suite_codex_data.gd`.

- [ ] **Step 3: Implement**

`scripts/systems/codex_data.gd`:

```gdscript
class_name CodexData
extends RefCounted

## Pure derived facts for the codex, computed from the static tables.

## {"guaranteed": [enemy names], "quests": [quest names],
##  "random_from_loot_level": int} for an item. `random_from_loot_level` is the
## lowest enemy loot_level at which the item can drop randomly, or -1 when it
## never drops randomly (epic items, or nothing has a high enough loot level).
static func item_sources(item_id: String) -> Dictionary:
	var result := {"guaranteed": [], "quests": [], "random_from_loot_level": -1}
	var item: Dictionary = LootTable.ITEMS.get(item_id, {})
	if item.is_empty():
		return result
	for enemy_id in EnemyTable.ENEMIES:
		var def: Dictionary = EnemyTable.ENEMIES[enemy_id]
		if def.get("guaranteed_drop", "") == item_id:
			result["guaranteed"].append(def["name"])
	for quest in QuestTable.QUESTS:
		if quest.get("item_reward", "") == item_id:
			result["quests"].append(quest["name"])
	var weight := int(LootTable.RARITY_WEIGHTS.get(item.get("rarity", "common"), 0))
	if weight > 0:
		var needed := int(item.get("level_req", 1))
		var lowest := -1
		for enemy_id in EnemyTable.ENEMIES:
			var loot_level := int(EnemyTable.ENEMIES[enemy_id]["loot_level"])
			if loot_level >= needed and (lowest == -1 or loot_level < lowest):
				lowest = loot_level
		result["random_from_loot_level"] = lowest
	return result

## Enemy ids whose home zone is `zone_id`, weakest first (by max_hp, then id).
static func zone_enemy_ids(zone_id: String) -> Array:
	var ids: Array = []
	for enemy_id in EnemyTable.ENEMIES:
		if EnemyTable.ENEMIES[enemy_id].get("zone", "") == zone_id:
			ids.append(enemy_id)
	ids.sort_custom(_enemy_before)
	return ids

## The strongest enemy in the zone that has a guaranteed drop, or "".
static func zone_boss_id(zone_id: String) -> String:
	var boss := ""
	for enemy_id in zone_enemy_ids(zone_id):
		if EnemyTable.ENEMIES[enemy_id].get("guaranteed_drop", "") != "":
			boss = enemy_id  # ids are weakest-first, so the last match is the strongest
	return boss

## [first level, last level] the zone is aimed at: its min_level up to one
## below the next zone's min_level (at least the same level), or the level cap
## for the last zone in the travel order.
static func zone_level_range(zone_id: String) -> Array:
	var low := int(ZoneTable.ZONES.get(zone_id, {}).get("min_level", 1))
	var index := ZoneTable.TRAVEL_ORDER.find(zone_id)
	var high := LevelingSystem.MAX_LEVEL
	if index >= 0 and index + 1 < ZoneTable.TRAVEL_ORDER.size():
		var next_min := int(ZoneTable.ZONES[ZoneTable.TRAVEL_ORDER[index + 1]].get("min_level", 1))
		high = maxi(low, next_min - 1)
	return [low, high]

static func zone_order() -> Array:
	return ZoneTable.TRAVEL_ORDER.duplicate()

## Every enemy id: by zone in travel order, then weakest first.
static func enemy_order() -> Array:
	var ids: Array = []
	for zone_id in ZoneTable.TRAVEL_ORDER:
		ids.append_array(zone_enemy_ids(zone_id))
	return ids

## Every item id: by slot (LootTable.SLOTS order), consumables last, then by
## level requirement, then id.
static func item_order() -> Array:
	var ids: Array = LootTable.ITEMS.keys()
	ids.sort_custom(_item_before)
	return ids

static func _enemy_before(a: String, b: String) -> bool:
	var hp_a := int(EnemyTable.ENEMIES[a]["max_hp"])
	var hp_b := int(EnemyTable.ENEMIES[b]["max_hp"])
	if hp_a != hp_b:
		return hp_a < hp_b
	return a < b

static func _item_before(a: String, b: String) -> bool:
	var slot_a := _slot_rank(a)
	var slot_b := _slot_rank(b)
	if slot_a != slot_b:
		return slot_a < slot_b
	var level_a := int(LootTable.ITEMS[a].get("level_req", 1))
	var level_b := int(LootTable.ITEMS[b].get("level_req", 1))
	if level_a != level_b:
		return level_a < level_b
	return a < b

static func _slot_rank(item_id: String) -> int:
	var slot: String = LootTable.ITEMS[item_id].get("slot", "")
	var rank := LootTable.SLOTS.find(slot)
	return rank if rank >= 0 else LootTable.SLOTS.size()
```

- [ ] **Step 4: Run tests to verify they pass**

Import pass, then tests: `0 failures`, no `SCRIPT ERROR`. Verify each expectation against the real tables while running. If a plan expectation is wrong for the data, decide which side is wrong and report it. Points to double-check: (a) the lowest `loot_level` among enemies is 2 (Wolf/Bandit), so `rusty_sword` (level_req 1) reports `2`, and `health_potion` (consumable, no `level_req`, counts as 1) also `2`; (b) `zone_level_range("thornfield_meadow")` is `[1, 2]` given the forest has `min_level` 1 (no gate), so if the forest's min level is 1 the range is `[1, max(1, 1-1)] = [1, 1]`: **check the real values** and set the test's expectation to what the formula gives, keeping the formula (report both ranges you used); (c) the crypt range is `[3, 3]` (swamp min 4).

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/codex_data.gd scripts/systems/codex_data.gd.uid tests/suite_codex_data.gd tests/suite_codex_data.gd.uid tests/run_tests.gd
git commit -m "Add CodexData: item sources, zone rosters and orderings with tests

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: `CodexText`

**Files:**
- Create: `scripts/ui/codex_text.gd`, `tests/suite_codex_text.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing suite**

`tests/suite_codex_text.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	# list labels
	t.check_eq(CodexText.list_label(true, "Mire Wolf"), "Mire Wolf", "discovered label is the name")
	t.check_eq(CodexText.list_label(false, "Mire Wolf"), "???", "undiscovered label is hidden")

	# tab titles
	t.check_eq(CodexText.tab_title("Bestiary", 5, 12), "Bestiary 5/12", "tab title")

	# enemies
	var not_met := CodexText.enemy_entry("mire_wolf", false, 0, false)
	t.check(not_met.contains("Not yet discovered"), "unmet enemy is undiscovered")
	t.check(not not_met.contains("Mire Wolf"), "unmet enemy does not reveal its name")
	t.check(not not_met.contains("Mirewater"), "no zone hint before the zone is visited")
	var hinted := CodexText.enemy_entry("mire_wolf", false, 0, true)
	t.check(hinted.contains("Lurks somewhere in Mirewater Swamp"), "zone hint once visited")
	t.check(not hinted.contains("Mire Wolf"), "the hint still hides the name")
	var met := CodexText.enemy_entry("mire_wolf", true, 0, true)
	t.check(met.contains("Mire Wolf"), "met enemy shows its name")
	t.check(met.contains("HP: 45"), "met enemy shows hp")
	t.check(met.contains("Damage: 5 - 9"), "met enemy shows damage")
	t.check(met.contains("Mirewater Swamp"), "met enemy shows its zone")
	t.check(not met.contains("XP"), "xp is hidden until the first kill")
	var killed := CodexText.enemy_entry("mire_wolf", true, 3, true)
	t.check(killed.contains("XP: 55"), "xp shown after a kill")
	t.check(killed.contains("Gold: 3 - 6"), "gold range shown after a kill")
	t.check(killed.contains("Kills: 3"), "kill count shown")
	t.check(killed.contains("Drops:"), "drops shown after a kill")
	var boss := CodexText.enemy_entry("mire_tyrant", true, 1, true)
	t.check(boss.contains("Boss"), "guaranteed-drop enemies are tagged")
	var maul_hex: String = LootTable.RARITY_COLORS["epic"].to_html(false)
	t.check(boss.contains("[color=#%s]Tyrants Maul[/color]" % maul_hex), "the guaranteed drop is shown in its rarity color")
	t.check_eq(CodexText.enemy_entry("no_such_enemy", true, 1, true), "", "unknown enemy has no entry")

	# items
	var unfound := CodexText.item_entry("iron_sword", false)
	t.check(unfound.contains("Not yet discovered"), "unfound item is undiscovered")
	t.check(not unfound.contains("Iron Sword"), "unfound item hides its name")
	t.check(unfound.contains("Weapon"), "unfound item hints its slot")
	var found := CodexText.item_entry("iron_sword", true)
	var uncommon_hex: String = LootTable.RARITY_COLORS["uncommon"].to_html(false)
	t.check(found.contains("[color=#%s]Iron Sword[/color]" % uncommon_hex), "found item is rarity-colored")
	t.check(found.contains("+7 damage"), "stat line")
	t.check(found.contains("Level 1"), "level requirement")
	t.check(found.contains("Guaranteed drop: Bandit Captain"), "guaranteed source")
	t.check(found.contains("Quest reward: The Captain's Head"), "quest source")
	var random_item := CodexText.item_entry("rusty_sword", true)
	t.check(random_item.contains("Random drops from level 2 enemies"), "random source line")
	var potion := CodexText.item_entry("health_potion", true)
	t.check(potion.contains("Heals 20 HP"), "consumables show their heal")
	var epic := CodexText.item_entry("tyrants_maul", true)
	t.check(not epic.contains("Random drops"), "epics have no random source line")
	t.check_eq(CodexText.item_entry("no_such_item", true), "", "unknown item has no entry")

	# zones
	var unvisited := CodexText.zone_entry("mirewater_swamp", false, [])
	t.check(unvisited.contains("Not yet discovered"), "unvisited zone is undiscovered")
	t.check(not unvisited.contains("Mirewater"), "unvisited zone hides its name")
	var visited := CodexText.zone_entry("mirewater_swamp", true, ["mire_wolf"])
	t.check(visited.contains("Mirewater Swamp"), "visited zone shows its name")
	t.check(visited.contains("Levels 4"), "level range shown")
	t.check(visited.contains("Mire Wolf"), "met enemies are listed by name")
	t.check(visited.contains("???"), "unmet enemies are hidden")
	t.check(not visited.contains("Bog Bandit"), "unmet enemies are not named")
	t.check(visited.contains("Discovered: 1/3"), "discovered count")
	var boss_met := CodexText.zone_entry("mirewater_swamp", true, ["mire_tyrant"])
	t.check(boss_met.contains("Boss: Mire Tyrant"), "the boss is named once met")
	var boss_hidden := CodexText.zone_entry("mirewater_swamp", true, [])
	t.check(boss_hidden.contains("Boss: ???"), "the boss is hidden until met")
	var no_boss := CodexText.zone_entry("thornfield_meadow", true, [])
	t.check(not no_boss.contains("Boss:"), "zones without a boss have no boss line")
	t.check_eq(CodexText.zone_entry("no_such_zone", true, []), "", "unknown zone has no entry")
	t.done()
```

Add `"res://tests/suite_codex_text.gd"` to `SUITES`.

- [ ] **Step 2: Run tests to verify they fail**

Import pass, then tests. Expected: `FAIL: suite failed to load: res://tests/suite_codex_text.gd`.

- [ ] **Step 3: Implement**

`scripts/ui/codex_text.gd`:

```gdscript
class_name CodexText
extends RefCounted

## Pure BBCode builders for the codex panel. Every input is a plain value
## (ids, flags, counts), so it is all unit-tested headlessly.

const UNDISCOVERED := "[color=#8a7a65]Not yet discovered.[/color]"

static func list_label(discovered: bool, entry_name: String) -> String:
	return entry_name if discovered else "???"

static func tab_title(tab: String, discovered: int, total: int) -> String:
	return "%s %d/%d" % [tab, discovered, total]

static func enemy_entry(id: String, met: bool, kills: int, zone_visited: bool) -> String:
	var def: Dictionary = EnemyTable.get_def(id)
	if def.is_empty():
		return ""
	var zone_name := String(ZoneTable.ZONES.get(def.get("zone", ""), {}).get("name", "?"))
	if not met:
		var text := UNDISCOVERED
		if zone_visited:
			text += "\nLurks somewhere in %s." % zone_name
		return text
	var lines: Array[String] = []
	var tag := ""
	if def.get("guaranteed_drop", "") != "":
		tag = "  [color=#d9a441]Boss[/color]"
	lines.append("[b]%s[/b]%s" % [def["name"], tag])
	lines.append("Zone: %s" % zone_name)
	lines.append("HP: %d" % int(def["max_hp"]))
	lines.append("Damage: %d - %d" % [int(def["attack_min"]), int(def["attack_max"])])
	if kills >= 1:
		lines.append("XP: %d" % int(def["xp_reward"]))
		lines.append("Gold: %d - %d" % [int(def["gold_min"]), int(def["gold_max"])])
		lines.append("Kills: %d" % kills)
		var drop: String = def.get("guaranteed_drop", "")
		if drop != "":
			lines.append("Drops: %s" % _colored_item_name(drop))
		else:
			lines.append("Drops: possible gear up to level %d" % int(def["loot_level"]))
	return "\n".join(lines)

static func item_entry(id: String, found: bool) -> String:
	var item: Dictionary = LootTable.ITEMS.get(id, {})
	if item.is_empty():
		return ""
	var slot_label := "Consumable" if item.get("type", "") == "consumable" else String(LootTable.SLOT_LABELS.get(item.get("slot", ""), ""))
	if not found:
		var hint := UNDISCOVERED
		if slot_label != "":
			hint += "\n%s" % slot_label
		return hint
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % _colored_item_name(id))
	lines.append("%s - %s - Level %d" % [slot_label, String(item.get("rarity", "")).capitalize(), int(item.get("level_req", 1))])
	if item.get("type", "") == "consumable":
		lines.append("Heals %d HP" % int(item.get("heal", 0)))
	else:
		var stats := ItemScoring.describe_stats(id)
		if stats != "":
			lines.append(stats)
	var sources := CodexData.item_sources(id)
	for enemy_name in sources["guaranteed"]:
		lines.append("Guaranteed drop: %s" % enemy_name)
	for quest_name in sources["quests"]:
		lines.append("Quest reward: %s" % quest_name)
	if int(sources["random_from_loot_level"]) >= 0:
		lines.append("Random drops from level %d enemies" % int(sources["random_from_loot_level"]))
	return "\n".join(lines)

## `enemies_met_in_zone`: ids of the zone's enemies the character has met.
static func zone_entry(id: String, visited: bool, enemies_met_in_zone: Array) -> String:
	var zone: Dictionary = ZoneTable.ZONES.get(id, {})
	if zone.is_empty():
		return ""
	if not visited:
		return UNDISCOVERED
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % zone["name"])
	var range := CodexData.zone_level_range(id)
	lines.append("Levels %d - %d" % [range[0], range[1]])
	var roster := CodexData.zone_enemy_ids(id)
	var met_count := 0
	lines.append("Enemies:")
	for enemy_id in roster:
		if enemies_met_in_zone.has(enemy_id):
			met_count += 1
			lines.append("  - %s" % EnemyTable.name_of(enemy_id))
		else:
			lines.append("  - ???")
	var boss_id := CodexData.zone_boss_id(id)
	if boss_id != "":
		lines.append("Boss: %s" % (EnemyTable.name_of(boss_id) if enemies_met_in_zone.has(boss_id) else "???"))
	lines.append("Discovered: %d/%d" % [met_count, roster.size()])
	return "\n".join(lines)

static func _colored_item_name(item_id: String) -> String:
	var rarity: String = LootTable.ITEMS.get(item_id, {}).get("rarity", "")
	var color: Color = LootTable.RARITY_COLORS.get(rarity, Color.WHITE)
	return "[color=#%s]%s[/color]" % [color.to_html(false), LootTable.display_name(item_id)]
```

- [ ] **Step 4: Run tests to verify they pass**

Import pass (new class + sidecar), then tests: `0 failures`, no `SCRIPT ERROR`. Verify expectations against the real tables (item names come from `LootTable.display_name`, e.g. `Tyrants Maul`; the `Levels 4` check assumes the swamp range starts at 4). If GDScript rejects the local variable name `range` (it shadows a built-in), rename it to `level_range` in the implementation; report any other adjustment.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/codex_text.gd scripts/ui/codex_text.gd.uid tests/suite_codex_text.gd tests/suite_codex_text.gd.uid tests/run_tests.gd
git commit -m "Add CodexText: pure BBCode entry text with tests

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Discovery hooks in `GameState` and `Character`

**Files:**
- Modify: `scripts/autoload/game_state.gd`, `scripts/entities/character.gd`

The game stays runnable; nothing consumes the signal yet. Verify with tests, a smoke run and a short live check.

- [ ] **Step 1: `GameState`**

In `scripts/autoload/game_state.gd`, directly under the line `var camera: Camera2D = null`, add:

```gdscript
## What the spectated character has discovered (see CodexState). Session only.
var codex := CodexState.new()
```

and directly under the `signal party_changed()` line add:

```gdscript
## Emitted when the character discovers a codex entry; `kind` is "enemy",
## "item" or "zone" and `id` the EnemyTable / LootTable / ZoneTable key.
signal codex_changed(kind: String, id: String)
```

Add this helper function at the end of the file (after `log_event`):

```gdscript
## Records a discovery and, if it is new, announces it. `kind` is "enemy",
## "item" or "zone".
func discover(kind: String, id: String) -> void:
	var is_new := false
	var display := ""
	match kind:
		"enemy":
			is_new = codex.discover_enemy(id)
			display = EnemyTable.name_of(id)
		"item":
			is_new = codex.discover_item(id)
			display = LootTable.display_name(id)
		"zone":
			is_new = codex.visit_zone(id)
			display = String(ZoneTable.ZONES.get(id, {}).get("name", id))
	if not is_new:
		return
	log_event("Codex: new entry - %s" % display)
	codex_changed.emit(kind, id)
```

- [ ] **Step 2: `Character` hooks**

Edit `scripts/entities/character.gd` (CRLF; Python with `newline=''`, assert each anchor occurs exactly once):

1. In `_update_combat_target`, replace the body's last line so the function reads:
```gdscript
func _update_combat_target(combat_hostile: Node2D) -> void:
	if combat_hostile != last_combat_target:
		last_combat_target = combat_hostile
		GameState.emit_signal("combat_target_changed", combat_hostile)
		if combat_hostile != null and is_instance_valid(combat_hostile):
			for enemy_id in EnemyTable.ids_named(combat_hostile.enemy_name):
				GameState.discover("enemy", enemy_id)
```
2. In `take_kill_credit`, directly after the line `kills_by_name[enemy_name] = int(kills_by_name.get(enemy_name, 0)) + 1` add:
```gdscript
	for enemy_id in EnemyTable.ids_named(enemy_name):
		GameState.discover("enemy", enemy_id)
```
3. In `_acquire_item`, directly after the line `var display_name := LootTable.display_name(item_id)` add:
```gdscript
	GameState.discover("item", item_id)
```
4. In `_sync_current_zone`, directly after the line `GameState.emit_signal("zone_changed", zone_id)` add:
```gdscript
	GameState.discover("zone", zone_id)
```
5. In `_ready()`, directly after the line `_recruit_companions_in_zone(current_zone_id)` add:
```gdscript
	GameState.discover("zone", current_zone_id)
```

(The `_ready` hook runs before the activity-log UI listens, so the starting zone is discovered silently in the log; that is fine, the codex state is what matters.)

- [ ] **Step 3: Verify**

Run the import pass, the tests (`0 failures`, `SCRIPT ERROR` count 0), and the smoke run:

```bash
timeout 90 "$GODOT" --headless --path . --quit-after 1200 2>&1 | grep -i "SCRIPT ERROR\|Parse Error" ; echo "grep-exit=$?"
```

Expected: no matches (`grep-exit=1`). Then a live check (Godot MCP): launch, wait until connected, 4x for about a minute, then read the state with `game_eval`:

```gdscript
return [GameState.codex.enemies_met.keys(), GameState.codex.items_found.keys(), GameState.codex.zones_visited.keys()]
```

Expected: the meadow in zones_visited from the start; enemies appear as fights start; items appear as loot is acquired; `Codex: new entry - ...` lines show up in the activity log (screenshot). Teleport to the swamp (`Vector2(6600, 0)`) and confirm `mirewater_swamp` becomes visited and the log announces it. `game_get_errors`: only the MCP plugin's warnings. Stop the game.

- [ ] **Step 4: Commit**

```bash
git add scripts/autoload/game_state.gd scripts/entities/character.gd
git commit -m "Record codex discoveries from the spectated character

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Codex panel

**Files:**
- Create: `scripts/ui/codex_panel.gd`
- Modify: `scenes/ui/SpectatorUI.tscn`

- [ ] **Step 1: The panel script**

`scripts/ui/codex_panel.gd`:

```gdscript
extends Panel

## Toggleable codex: press B or click the Codex (B) button. Three tabs
## (Bestiary, Items, Zones); undiscovered entries show as ???. Entry text comes
## from the pure CodexText/CodexData classes.

const TABS := ["Bestiary", "Items", "Zones"]
const BODY_COLOR := Color(0.93, 0.88, 0.75, 1.0)
const PORTRAIT_SIZE := Vector2(64, 64)

@onready var tab_bar: HBoxContainer = $Tabs
@onready var entry_list: ItemList = $List
@onready var portrait: TextureRect = $Portrait
@onready var detail: RichTextLabel = $Detail
@onready var codex_button: Button = get_node("../SpeedControl/CodexButton")

var tab_buttons: Array[Button] = []
var current_tab := 0
var entry_ids: Array = []
var selected_by_tab := [0, 0, 0]

func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.09, 0.05, 0.96)
	style.set_border_width_all(2)
	style.border_color = Color(0.55, 0.4, 0.15, 1.0)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	detail.add_theme_color_override("default_color", BODY_COLOR)
	entry_list.add_theme_color_override("font_color", BODY_COLOR)
	for i in TABS.size():
		var button := Button.new()
		button.toggle_mode = true
		button.pressed.connect(_on_tab_pressed.bind(i))
		tab_bar.add_child(button)
		tab_buttons.append(button)
	entry_list.item_selected.connect(_on_item_selected)
	codex_button.pressed.connect(toggle)
	GameState.codex_changed.connect(_on_codex_changed)
	visibility_changed.connect(_on_visibility_changed)

func toggle() -> void:
	visible = not visible

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		toggle()
		get_viewport().set_input_as_handled()

func _on_visibility_changed() -> void:
	if visible:
		_refresh()

func _on_tab_pressed(index: int) -> void:
	current_tab = index
	_refresh()

func _on_codex_changed(_kind: String, _id: String) -> void:
	if visible:
		_refresh()

func _on_item_selected(index: int) -> void:
	selected_by_tab[current_tab] = index
	_show_entry(index)

func _refresh() -> void:
	var codex := GameState.codex
	var character = GameState.character
	for i in tab_buttons.size():
		tab_buttons[i].button_pressed = i == current_tab
	tab_buttons[0].text = CodexText.tab_title(TABS[0], codex.enemies_met_count(), EnemyTable.ENEMIES.size())
	tab_buttons[1].text = CodexText.tab_title(TABS[1], codex.items_found_count(), LootTable.ITEMS.size())
	tab_buttons[2].text = CodexText.tab_title(TABS[2], codex.zones_visited_count(), ZoneTable.ZONES.size())
	entry_list.clear()
	match current_tab:
		0: entry_ids = CodexData.enemy_order()
		1: entry_ids = CodexData.item_order()
		_: entry_ids = CodexData.zone_order()
	for id in entry_ids:
		entry_list.add_item(CodexText.list_label(_is_discovered(id, character), _entry_name(id)))
	if entry_ids.is_empty():
		portrait.texture = null
		detail.text = ""
		return
	var index: int = clampi(selected_by_tab[current_tab], 0, entry_ids.size() - 1)
	entry_list.select(index)
	entry_list.ensure_current_is_visible()
	_show_entry(index)

func _is_discovered(id: String, character) -> bool:
	var codex := GameState.codex
	match current_tab:
		0: return codex.enemy_met(id) or _kills_of(id, character) > 0
		1: return codex.item_found(id)
		_: return codex.zone_visited(id)

func _entry_name(id: String) -> String:
	match current_tab:
		0: return EnemyTable.name_of(id)
		1: return LootTable.display_name(id)
		_: return String(ZoneTable.ZONES[id]["name"])

func _kills_of(enemy_id: String, character) -> int:
	if character == null or not is_instance_valid(character):
		return 0
	return int(character.kills_by_name.get(EnemyTable.name_of(enemy_id), 0))

func _show_entry(index: int) -> void:
	if index < 0 or index >= entry_ids.size():
		return
	var id: String = entry_ids[index]
	var character = GameState.character
	var codex := GameState.codex
	portrait.texture = null
	portrait.modulate = Color(1, 1, 1, 1)
	match current_tab:
		0:
			var kills := _kills_of(id, character)
			var met := codex.enemy_met(id) or kills > 0
			var zone_id: String = EnemyTable.get_def(id).get("zone", "")
			detail.text = CodexText.enemy_entry(id, met, kills, codex.zone_visited(zone_id))
			if met:
				_show_enemy_portrait(id)
		1:
			var found := codex.item_found(id)
			detail.text = CodexText.item_entry(id, found)
			if found:
				var icon_path: String = LootTable.ITEMS[id].get("icon", "")
				if icon_path != "":
					portrait.texture = load(icon_path)
		_:
			var met_here: Array = []
			for enemy_id in CodexData.zone_enemy_ids(id):
				if codex.enemy_met(enemy_id) or _kills_of(enemy_id, character) > 0:
					met_here.append(enemy_id)
			detail.text = CodexText.zone_entry(id, codex.zone_visited(id), met_here)

## First frame of the enemy's idle animation, tinted like the real enemy.
func _show_enemy_portrait(enemy_id: String) -> void:
	var def: Dictionary = EnemyTable.get_def(enemy_id)
	var frames: SpriteFrames = load(EnemyTable.SPRITE_FRAMES[def["sprite"]])
	for animation in ["idle_down", "idle_right"]:
		if frames.has_animation(animation) and frames.get_frame_count(animation) > 0:
			portrait.texture = frames.get_frame_texture(animation, 0)
			portrait.modulate = def["tint"]
			return
```

- [ ] **Step 2: Scene nodes**

In `scenes/ui/SpectatorUI.tscn` (Python with `newline=''`, using the file's line ending; read the current file first):

1. Add an ext_resource after the existing ones and bump `load_steps` by 1:
```
[ext_resource type="Script" path="res://scripts/ui/codex_panel.gd" id="13_codexpanel"]
```
2. Add a `CodexButton` as the LAST child of `SpeedControl` (directly after the `SheetButton` node block):
```
[node name="CodexButton" type="Button" parent="SpeedControl"]
text = "Codex (B)"
```
3. Append at the end of the file:
```
[node name="CodexPanel" type="Panel" parent="."]
visible = false
theme = ExtResource("4_theme")
script = ExtResource("13_codexpanel")
offset_left = 256.0
offset_top = 110.0
offset_right = 896.0
offset_bottom = 540.0

[node name="Tabs" type="HBoxContainer" parent="CodexPanel"]
offset_left = 12.0
offset_top = 10.0
offset_right = 628.0
offset_bottom = 42.0

[node name="List" type="ItemList" parent="CodexPanel"]
offset_left = 12.0
offset_top = 52.0
offset_right = 232.0
offset_bottom = 418.0

[node name="Portrait" type="TextureRect" parent="CodexPanel"]
offset_left = 246.0
offset_top = 52.0
offset_right = 310.0
offset_bottom = 116.0
expand_mode = 1
stretch_mode = 5

[node name="Detail" type="RichTextLabel" parent="CodexPanel"]
offset_left = 318.0
offset_top = 52.0
offset_right = 628.0
offset_bottom = 418.0
theme_override_font_sizes/normal_font_size = 13
theme_override_font_sizes/bold_font_size = 13
bbcode_enabled = true
```

- [ ] **Step 3: Live check**

Import pass, run the tests (`0 failures`, `SCRIPT ERROR` count 0), then launch via the Godot MCP tools:
- At start the codex is hidden and the speed row ends with a `Codex (B)` button after `Sheet (C)` without overlapping the quest tracker.
- Press `B` (`game_key_press`) and screenshot: the panel opens centred (x 256-896, y 110-540) with three tabs showing counters (`Bestiary 0/12` etc. — at least the meadow zone counts as visited: `Zones 1/5`), a list where undiscovered entries read `???` and discovered ones show names, and a detail area. Select entries (click list rows with `game_click`) in each tab and verify the detail text: an undiscovered entry reads `Not yet discovered.`; a met enemy shows a tinted portrait, zone, HP and damage (and XP/gold/drops after a kill); a found item shows its icon, rarity-colored name, slot, stats and sources; the visited meadow shows level range, roster and `Boss` handling (no boss line).
- Play at 4x for about a minute with the panel open: counters and `???` rows update as discoveries happen; the selection is kept.
- Teleport to the swamp and to the pass (`Vector2(6600, 0)`, `Vector2(8800, 0)`) and fight briefly: zones become discovered, the Bestiary shows Mirewater/Frostpeak enemies with their tinted portraits, the zone entries show names for met enemies and `???` for others.
- `B` and the button both close the panel; nothing errors; no overlap with the sheet (`C` opens on the right; both can be open, the codex sits left of it or overlaps it a little — if they overlap badly, shift the codex panel left/narrower and report). `game_get_errors`: only the MCP plugin's warnings. Stop the game.

If something looks wrong (unreadable text, clipped list, portrait too small), fix within the plan's intent and report exactly what you changed.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/codex_panel.gd scripts/ui/codex_panel.gd.uid scenes/ui/SpectatorUI.tscn
git commit -m "Add the codex panel: bestiary, items and zones that fill in as discovered

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Docs and final run

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README**

In the controls table add (matching the existing rows):

```markdown
| **B** key / **Codex (B)** button | Open or close the codex (bestiary, items, zones) |
```

In the HUD bullet list add:

```markdown
  - A codex that fills in as the character discovers enemies, items and zones
```

Preserve line endings (README.md is CRLF).

- [ ] **Step 2: Final run**

Run the tests (`0 failures`, count above 8955, `SCRIPT ERROR` count 0). Then a ~3 minute live run at 4x from a normal start with no teleports, with the codex open for part of it: entries fill in as the character explores; `Codex: new entry - ...` lines appear in the activity log; the counters on the tabs match what you see; killing an enemy reveals its XP/gold/drops; finding an item shows its sources; no errors beyond the MCP plugin's warnings; nothing else in the HUD is broken (sheet, party frames, chat, target frame). Report any real bug precisely (file, line, symptom); fix only if small and obviously correct.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document the codex

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Self-review notes (completed by the plan author)

- **Spec coverage:** enemy `zone` + consistency tests -> Task 1; `CodexState` -> 2; `CodexData` (item sources, rosters, boss, level range, orderings) -> 3; `CodexText` (reveal tiers, hints, item/zone entries, tab titles) -> 4; `GameState.codex`/`codex_changed` and all four discovery triggers plus log line -> 5; panel with tabs, list, portraits, `B`/button, refresh on discovery -> 6; README + full run -> 7.
- **Known judgement call:** the plan's Task 3 range expectations depend on the forest's real `min_level`; the task tells the implementer to verify against the data and keep the formula.
- **Name consistency:** `CodexState` methods (`discover_enemy/item`, `visit_zone`, `enemy_met`, `item_found`, `zone_visited`, `*_count`), `CodexData` functions (`item_sources`, `zone_enemy_ids`, `zone_boss_id`, `zone_level_range`, `zone_order`, `enemy_order`, `item_order`) and `CodexText` functions (`list_label`, `tab_title`, `enemy_entry`, `item_entry`, `zone_entry`) are used with identical signatures across the plan.
