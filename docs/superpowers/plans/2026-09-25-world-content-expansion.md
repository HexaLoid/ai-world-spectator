# World Content Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A data-driven enemy table, two new zones (Mirewater Swamp, Frostpeak Pass) with seven new enemies, level cap 10, 15 new gear items with level-aware drops, seven new quests and two new allies.

**Architecture:** Static data tables (`EnemyTable`, extended `ZoneTable` / `QuestTable` / `LootTable` / `LevelingSystem`) validated by headless tests; `SpawnPoint` reads an `enemy_id` from `EnemyTable`; new zone scenes are re-tinted copies of `BlackthornForest.tscn` placed further along the world line.

**Tech Stack:** Godot 4.7 (mono build, GDScript only), headless `--script` test runner.

**Spec:** `docs/superpowers/specs/2026-09-25-world-content-expansion-design.md`

---

## Conventions used in every task

- Work in a dedicated git worktree/branch (e.g. `world-content`). A fresh checkout needs **two** headless editor passes before scripts and textures resolve.
- Shell variable (bash on Windows):

```bash
GODOT="/c/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
```

- **Import pass** (registers new `class_name` scripts, writes `.gd.uid` sidecars, imports new images). Run from the project root whenever a task adds a script or image, *before* running tests:

```bash
"$GODOT" --headless --path . --editor --quit
```

- **Run tests** (from the project root; `timeout` guards against a hung console exe):

```bash
timeout 90 "$GODOT" --headless --path . --script res://tests/run_tests.gd
```

  Exit code 0 = all pass; failures print lines starting `FAIL:`. A suite that fails to parse is reported as `FAIL: suite failed to load: ...`. The baseline before this plan is `1945 checks, 0 failures`. Every suite's `run(t)` must end with `t.done()`; the runner reports a suite that ends early.
- Commit `.gd.uid` sidecars and `.png.import` files next to new scripts/images (repo convention). Do **not** commit Godot's line-ending-only rewrites of unrelated `.import` files, the `mcp_interaction_server` autoload line in `project.godot`, or `mcp_interaction_server.gd*`.
- Commit messages end with: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`
- **Line endings:** many files are CRLF in the working tree (git normalizes to LF in commits). Preserve each file's existing line endings when editing (Python with `newline=''`, inserting text with the file's own ending) and check `git diff --stat` shows only the lines you meant to change. New files may be LF.
- If an edit tool fails to match multi-line text, match on a single line without leading tabs, or use a small Python script.
- **Live checks** use the Godot MCP tools (`mcp__godot__run_project` with `projectPath` = the worktree, then `game_screenshot`, `game_get_errors`, `get_debug_output`, `game_click`, `game_eval`, `game_get_property`, `game_set_property`, `stop_project`). They may be deferred: load with ToolSearch `select:`. The `game_*` tools need several seconds after `run_project` to connect; retry. Window is 1152x648; click the HUD `4x` button (~x=613,y=28) to speed up. `game_wait` returns immediately, so pace with repeated screenshots. `Engine.time_scale` can be set through `game_eval`. Teleport the character with `game_eval`: `get_node("/root/Main/Character").global_position = Vector2(x, y)`. Only the MCP plugin's own warnings from `mcp_interaction_server.gd` are acceptable in `game_get_errors`. Never call `game_get_property` with an unknown property name (a bad name halts the game).

## File structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/systems/leveling_system.gd` | modify | Level cap 10, XP curve |
| `scripts/systems/loot_table.gd` | modify | 15 new items, level-aware `roll_drop` |
| `scripts/systems/enemy_table.gd` | create | Central enemy definitions (12 enemies) |
| `scripts/systems/zone_table.gd` | modify | Two zones, travel order, world bounds |
| `scripts/systems/quest_table.gd` | modify | Seven new quests |
| `scripts/entities/spawn_point.gd` | modify | `enemy_id` instead of per-field overrides |
| `scripts/entities/enemy.gd` | modify | `loot_level`, level-aware drops |
| `scenes/world/ThornfieldMeadow.tscn`, `BlackthornForest.tscn`, `SunderedCrypt.tscn` | modify | Convert spawn points to `enemy_id` |
| `scenes/world/MirewaterSwamp.tscn`, `FrostpeakPass.tscn` | create | New zones |
| `scenes/world/World.tscn` | modify | Place new zones, corridors |
| `assets/icons/*.png` (+ `.import`), `assets/CREDITS.txt` | add/modify | New item icons |
| `tests/suite_leveling_system.gd`, `suite_enemy_table.gd`, `suite_zone_table.gd`, `suite_quest_table.gd`, `suite_spawn_points.gd` | create | New validation suites |
| `tests/suite_loot_table.gd`, `tests/suite_name_table.gd`, `tests/run_tests.gd` | modify | Extended/registered suites |
| `README.md` | modify | Feature list |

---

### Task 1: Level cap 10

**Files:**
- Create: `tests/suite_leveling_system.gd`
- Modify: `tests/run_tests.gd`, `scripts/systems/leveling_system.gd`

- [ ] **Step 1: Write the failing suite**

`tests/suite_leveling_system.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	t.check_eq(LevelingSystem.MAX_LEVEL, 10, "level cap is 10")
	t.check_eq(LevelingSystem.XP_THRESHOLDS.size(), LevelingSystem.MAX_LEVEL - 1, "one threshold per level above 1")
	var previous := 0
	for threshold in LevelingSystem.XP_THRESHOLDS:
		t.check(int(threshold) > previous, "thresholds strictly increase (%d after %d)" % [threshold, previous])
		previous = int(threshold)

	var below := LevelingSystem.apply_xp(1, 0, 99)
	t.check_eq(below["level"], 1, "99 xp is still level 1")
	t.check(not below["leveled_up"], "no level-up below the first threshold")

	var first := LevelingSystem.apply_xp(1, 0, 100)
	t.check_eq(first["level"], 2, "100 xp reaches level 2")
	t.check(first["leveled_up"], "level-up flagged")
	t.check_eq(first["hp_bonus"], LevelingSystem.HP_PER_LEVEL, "one level of hp bonus")
	t.check_eq(first["damage_bonus"], LevelingSystem.DAMAGE_PER_LEVEL, "one level of damage bonus")

	var top := LevelingSystem.apply_xp(1, 0, 3200)
	t.check_eq(top["level"], 10, "3200 xp reaches level 10")
	t.check_eq(top["hp_bonus"], 9 * LevelingSystem.HP_PER_LEVEL, "nine levels of hp bonus")
	t.check_eq(top["damage_bonus"], 9 * LevelingSystem.DAMAGE_PER_LEVEL, "nine levels of damage bonus")

	var capped := LevelingSystem.apply_xp(10, 3200, 5000)
	t.check_eq(capped["level"], 10, "cannot exceed the cap")
	t.check(not capped["leveled_up"], "no level-up at the cap")

	t.check_eq(LevelingSystem.get_next_threshold(1), 100, "next threshold from level 1")
	t.check_eq(LevelingSystem.get_next_threshold(9), 3200, "next threshold from level 9")
	t.check_eq(LevelingSystem.get_next_threshold(10), -1, "no threshold at the cap")
	t.check_eq(LevelingSystem.get_next_threshold(0), -1, "invalid level has no threshold")
```

Add `"res://tests/suite_leveling_system.gd"` to `SUITES` in `tests/run_tests.gd`.

- [ ] **Step 2: Run tests to verify they fail**

Import pass, then tests. Expected: `FAIL: level cap is 10` and other failures (thresholds and level 10).

- [ ] **Step 3: Implement**

In `scripts/systems/leveling_system.gd`, replace the two lines

```gdscript
## Cumulative XP required to REACH levels 2-5 (index 0 = threshold for level 2, etc).
const XP_THRESHOLDS := [100, 250, 450, 700]
const MAX_LEVEL := 5
```

with

```gdscript
## Cumulative XP required to REACH levels 2-10 (index 0 = threshold for level 2, etc).
const XP_THRESHOLDS := [100, 250, 450, 700, 1000, 1400, 1900, 2500, 3200]
const MAX_LEVEL := 10
```

(Match the file's own line endings; the comment line may differ slightly in the file — replace whichever `XP_THRESHOLDS` / `MAX_LEVEL` lines exist and update the comment.)

- [ ] **Step 4: Run tests to verify they pass**

Import pass (new suite sidecar), then tests. Expected: `0 failures`. If an existing check elsewhere failed only because the cap moved, report it.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/leveling_system.gd tests/suite_leveling_system.gd tests/suite_leveling_system.gd.uid tests/run_tests.gd
git commit -m "Raise the level cap to 10 with a longer XP curve

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: New items, icons and level-aware drops

**Files:**
- Modify: `scripts/systems/loot_table.gd`, `tests/suite_loot_table.gd`, `assets/CREDITS.txt`
- Create: `assets/icons/{tempered_sword,mirewood_staff,tyrants_maul,frostbrand,glacier_staff,bog_bulwark,frostguard_shield,marsh_helm,rimewatch_helm,swamp_charm,rimewatch_amulet,ring_of_the_mire,frozen_band}_icon.png` (+ `.import`)

Icons come from Kyrise's RPG Icon Pack (32x32), already extracted this session (or in the scratchpad of an earlier session). Source directory (may differ per session; find it with `find` under the scratchpad for a folder named `32x32` containing `helmet_01a.png`):

```
C:/Users/n1njaz/AppData/Local/Temp/claude/C--Users-n1njaz-Desktop-New-folder/e6861214-ad52-4843-8a17-2a61398b9a86/scratchpad/kyrise_icons/extracted/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/32x32
```

If it no longer exists, ask the user before re-downloading the pack from https://opengameart.org/content/kyrises-free-16x16-rpg-icon-pack (downloads need explicit permission). The two new chest items reuse existing icons (`chainmail_armor_icon.png`, `champions_plate_icon.png`), so no new file is needed for them.

- [ ] **Step 1: Copy the icons**

```bash
SRC="<the 32x32 directory above>"
DST=assets/icons
cp "$SRC/sword_02c.png" $DST/tempered_sword_icon.png
cp "$SRC/staff_02e.png" $DST/mirewood_staff_icon.png
cp "$SRC/sword_03e.png" $DST/tyrants_maul_icon.png
cp "$SRC/sword_03c.png" $DST/frostbrand_icon.png
cp "$SRC/staff_03b.png" $DST/glacier_staff_icon.png
cp "$SRC/shield_02d.png" $DST/bog_bulwark_icon.png
cp "$SRC/shield_03b.png" $DST/frostguard_shield_icon.png
cp "$SRC/helmet_01d.png" $DST/marsh_helm_icon.png
cp "$SRC/helmet_02a.png" $DST/rimewatch_helm_icon.png
cp "$SRC/necklace_01d.png" $DST/swamp_charm_icon.png
cp "$SRC/necklace_03c.png" $DST/rimewatch_amulet_icon.png
cp "$SRC/ring_02d.png" $DST/ring_of_the_mire_icon.png
cp "$SRC/ring_03b.png" $DST/frozen_band_icon.png
```

Run the import pass **twice**, then open each new PNG with the Read tool and confirm it looks like its item (sword, staff, shield, helmet, necklace, ring). If one is clearly wrong or a source file is missing, swap in another file of the same category from `$SRC` and note it in your report. Avoid picking a source image identical to an icon already in `assets/icons/`.

Append to `assets/CREDITS.txt` in the Kyrise section (after the phase-1 "Also from the same pack" paragraph), preserving line endings:

```
Also from the same pack (32x32 variant): tempered_sword_icon.png,
mirewood_staff_icon.png, tyrants_maul_icon.png, frostbrand_icon.png,
glacier_staff_icon.png, bog_bulwark_icon.png, frostguard_shield_icon.png,
marsh_helm_icon.png, rimewatch_helm_icon.png, swamp_charm_icon.png,
rimewatch_amulet_icon.png, ring_of_the_mire_icon.png, frozen_band_icon.png.
```

- [ ] **Step 2: Write the failing tests**

In `tests/suite_loot_table.gd`:

1. **Delete** the hard-coded epic check (the two lines `if item.get("rarity", "") == "epic":` followed by `t.check(level_req <= 3, ...)`); reachability of epic drops is now covered data-driven by `suite_enemy_table.gd` and the quest checks.
2. Append at the end of `run()`:

```gdscript
	# level-aware drops
	var drop_rng := RandomNumberGenerator.new()
	drop_rng.seed = 99
	for loot_level in [1, 2, 3, 5, 6, 9, 10]:
		for i in 300:
			var rolled := LootTable.roll_drop(drop_rng, loot_level)
			t.check(LootTable.ITEMS.has(rolled), "level-%d roll returns a real item" % loot_level)
			var rolled_def: Dictionary = LootTable.ITEMS[rolled]
			t.check(int(rolled_def.get("level_req", 1)) <= loot_level, "level-%d roll never returns %s (level_req %d)" % [loot_level, rolled, int(rolled_def.get("level_req", 1))])
			t.check(rolled_def["rarity"] != "epic", "level-%d roll never returns an epic" % loot_level)
	t.check(LootTable.roll_drop(drop_rng, 1) != "", "a level-1 roll always finds something")
	# new content sanity
	for item_id in ["tempered_sword", "mirewood_staff", "tyrants_maul", "frostbrand", "glacier_staff", "bog_bulwark",
			"frostguard_shield", "marsh_helm", "rimewatch_helm", "reinforced_mail", "glacier_plate", "swamp_charm",
			"rimewatch_amulet", "ring_of_the_mire", "frozen_band"]:
		t.check(LootTable.ITEMS.has(item_id), "new item %s exists" % item_id)
```

- [ ] **Step 3: Run tests to verify they fail**

Import pass, then tests. Expected: failures for the missing new items, and `roll_drop` rejecting a second argument (parse error -> `suite failed to load`).

- [ ] **Step 4: Implement the items**

In `scripts/systems/loot_table.gd`, add these entries to `ITEMS`, each directly after the last existing item of the same slot (keep the file's line endings):

```gdscript
	# Weapons (levels 5-8)
	"tempered_sword": {"slot": "weapon", "rarity": "rare", "level_req": 5, "icon": "res://assets/icons/tempered_sword_icon.png", "stats": {"damage": 15, "strength": 3}},
	"mirewood_staff": {"slot": "weapon", "rarity": "rare", "level_req": 5, "icon": "res://assets/icons/mirewood_staff_icon.png", "stats": {"damage": 11, "intellect": 9}},
	"tyrants_maul": {"slot": "weapon", "rarity": "epic", "level_req": 6, "icon": "res://assets/icons/tyrants_maul_icon.png", "stats": {"damage": 20, "strength": 5, "intellect": 3}},
	"frostbrand": {"slot": "weapon", "rarity": "epic", "level_req": 8, "icon": "res://assets/icons/frostbrand_icon.png", "stats": {"damage": 24, "strength": 6}},
	"glacier_staff": {"slot": "weapon", "rarity": "epic", "level_req": 8, "icon": "res://assets/icons/glacier_staff_icon.png", "stats": {"damage": 18, "intellect": 12}},
	# Off-hand
	"bog_bulwark": {"slot": "offhand", "rarity": "rare", "level_req": 6, "icon": "res://assets/icons/bog_bulwark_icon.png", "stats": {"armor": 11, "max_hp": 20}},
	"frostguard_shield": {"slot": "offhand", "rarity": "epic", "level_req": 8, "icon": "res://assets/icons/frostguard_shield_icon.png", "stats": {"armor": 15, "max_hp": 30, "strength": 2}},
	# Head
	"marsh_helm": {"slot": "head", "rarity": "rare", "level_req": 5, "icon": "res://assets/icons/marsh_helm_icon.png", "stats": {"armor": 5, "max_hp": 20, "strength": 1}},
	"rimewatch_helm": {"slot": "head", "rarity": "rare", "level_req": 7, "icon": "res://assets/icons/rimewatch_helm_icon.png", "stats": {"armor": 7, "max_hp": 25, "strength": 3, "intellect": 3}},
	# Chest
	"reinforced_mail": {"slot": "chest", "rarity": "rare", "level_req": 5, "icon": "res://assets/icons/chainmail_armor_icon.png", "stats": {"armor": 8, "max_hp": 35}},
	"glacier_plate": {"slot": "chest", "rarity": "epic", "level_req": 9, "icon": "res://assets/icons/champions_plate_icon.png", "stats": {"armor": 13, "max_hp": 55, "strength": 4, "intellect": 4}},
	# Neck
	"swamp_charm": {"slot": "neck", "rarity": "uncommon", "level_req": 5, "icon": "res://assets/icons/swamp_charm_icon.png", "stats": {"crit_chance": 0.08, "max_hp": 15}},
	"rimewatch_amulet": {"slot": "neck", "rarity": "epic", "level_req": 8, "icon": "res://assets/icons/rimewatch_amulet_icon.png", "stats": {"damage": 4, "strength": 4, "intellect": 4, "crit_chance": 0.16}},
	# Ring
	"ring_of_the_mire": {"slot": "ring", "rarity": "rare", "level_req": 6, "icon": "res://assets/icons/ring_of_the_mire_icon.png", "stats": {"max_hp": 30, "crit_chance": 0.06}},
	"frozen_band": {"slot": "ring", "rarity": "epic", "level_req": 8, "icon": "res://assets/icons/frozen_band_icon.png", "stats": {"damage": 5, "crit_chance": 0.12}},
```

Replace `roll_drop` (the whole function, keeping its doc comment updated) with:

```gdscript
## Picks a random item key from ITEMS using the given rng, weighted by
## RARITY_WEIGHTS (so epic items, at weight 0, are never picked here) and
## limited to items whose level_req is at most `loot_level` (consumables count
## as level 1), so early enemies never drop gear a character of their zone
## cannot use.
static func roll_drop(rng: RandomNumberGenerator, loot_level: int = LevelingSystem.MAX_LEVEL) -> String:
	var eligible: Array = []
	var total_weight := 0
	for item_id in ITEMS:
		var item: Dictionary = ITEMS[item_id]
		if int(item.get("level_req", 1)) > loot_level:
			continue
		var weight := int(RARITY_WEIGHTS.get(item.get("rarity", "common"), 0))
		if weight <= 0:
			continue
		eligible.append([item_id, weight])
		total_weight += weight
	if eligible.is_empty():
		return "health_potion"
	var roll := rng.randi_range(1, total_weight)
	var cumulative := 0
	for entry in eligible:
		cumulative += int(entry[1])
		if roll <= cumulative:
			return String(entry[0])
	return String(eligible[0][0])
```

- [ ] **Step 5: Run tests to verify they pass**

Import pass, then tests. Expected: `0 failures`. If GDScript rejects `LevelingSystem.MAX_LEVEL` as a default parameter value, use the literal `99` instead and say so. (The existing loot-table checks — per-slot counts, each slot has a level-1 common, quest reward reachability, STAT_ORDER/LABELS — must still pass.)

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/loot_table.gd tests/suite_loot_table.gd assets/CREDITS.txt assets/icons
git commit -m "Add 15 items for levels 5-9 and level-aware random drops

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

(Stage only the new `*_icon.png` and `*_icon.png.import` files under `assets/icons`, not unrelated rewrites.)

---

### Task 3: `EnemyTable` with tests

**Files:**
- Create: `scripts/systems/enemy_table.gd`, `tests/suite_enemy_table.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing suite**

`tests/suite_enemy_table.gd`:

```gdscript
extends RefCounted

const ORIGINAL := {
	"wolf": {"name": "Wolf", "max_hp": 18, "move_speed": 70.0, "attack_min": 2, "attack_max": 4, "xp_reward": 20, "sprite": "wolf"},
	"dire_wolf": {"name": "Dire Wolf", "max_hp": 30, "move_speed": 75.0, "attack_min": 4, "attack_max": 7, "xp_reward": 35, "sprite": "wolf"},
	"bandit": {"name": "Bandit", "max_hp": 35, "move_speed": 45.0, "attack_min": 4, "attack_max": 8, "xp_reward": 35, "sprite": "bandit"},
	"bandit_captain": {"name": "Bandit Captain", "max_hp": 70, "move_speed": 50.0, "attack_min": 8, "attack_max": 14, "xp_reward": 90, "sprite": "bandit", "guaranteed_drop": "iron_sword"},
	"crypt_lord": {"name": "Crypt Lord", "max_hp": 150, "move_speed": 45.0, "attack_min": 10, "attack_max": 18, "xp_reward": 300, "sprite": "bandit", "guaranteed_drop": "warlords_greatsword"},
}

const NEW_IDS := ["mire_wolf", "bog_bandit", "mire_tyrant", "frost_wolf", "frost_raider", "raider_captain", "frostpeak_warlord"]

## Zone min_level for each guaranteed-drop enemy's home zone (the drop's
## level_req may be at most 2 above it).
const BOSS_ZONE_MIN_LEVEL := {
	"bandit_captain": 1, "crypt_lord": 3, "mire_tyrant": 4, "raider_captain": 7, "frostpeak_warlord": 7,
}

func run(t) -> void:
	t.check_eq(EnemyTable.ENEMIES.size(), 12, "twelve enemies")
	var names := {}
	for id in EnemyTable.ENEMIES:
		var def: Dictionary = EnemyTable.ENEMIES[id]
		t.check(EnemyTable.SPRITE_FRAMES.has(def.get("sprite", "")), "%s has a known sprite" % id)
		for path in EnemyTable.SPRITE_FRAMES.values():
			t.check(FileAccess.file_exists(path), "sprite frames file exists: %s" % path)
		t.check(String(def.get("name", "")) != "", "%s has a name" % id)
		t.check(not names.has(def["name"]), "enemy name %s is unique" % def["name"])
		names[def["name"]] = id
		t.check(int(def["max_hp"]) > 0, "%s has hp" % id)
		t.check(float(def["move_speed"]) > 0.0, "%s moves" % id)
		t.check(int(def["attack_min"]) >= 1 and int(def["attack_min"]) <= int(def["attack_max"]), "%s attack range is valid" % id)
		t.check(int(def["xp_reward"]) > 0, "%s gives xp" % id)
		t.check(int(def["gold_min"]) >= 0 and int(def["gold_min"]) <= int(def["gold_max"]), "%s gold range is valid" % id)
		t.check(int(def["loot_level"]) >= 1 and int(def["loot_level"]) <= LevelingSystem.MAX_LEVEL, "%s loot_level in range" % id)
		t.check(float(def["sprite_size"]) >= 32.0 and float(def["sprite_size"]) <= 96.0, "%s sprite size is sane" % id)
		t.check(float(def["aggro_range"]) >= 80.0, "%s aggro range is sane" % id)
		t.check(def["tint"] is Color, "%s tint is a Color" % id)
		var drop: String = def.get("guaranteed_drop", "")
		if drop != "":
			t.check(LootTable.ITEMS.has(drop), "%s guaranteed drop %s exists" % [id, drop])
			t.check(BOSS_ZONE_MIN_LEVEL.has(id), "%s (guaranteed drop) is listed in this suite's zone table" % id)
			if LootTable.ITEMS.has(drop) and BOSS_ZONE_MIN_LEVEL.has(id):
				var level_req := int(LootTable.ITEMS[drop].get("level_req", 1))
				t.check(level_req <= int(BOSS_ZONE_MIN_LEVEL[id]) + 2, "%s drop %s (level_req %d) is reachable from its zone" % [id, drop, level_req])

	# the five original enemies keep their previous stats
	for id in ORIGINAL:
		var expected: Dictionary = ORIGINAL[id]
		var def := EnemyTable.get_def(id)
		t.check(not def.is_empty(), "original enemy %s exists" % id)
		for key in expected:
			var actual = def.get("guaranteed_drop", "") if key == "guaranteed_drop" else def.get(key)
			t.check_eq(actual, expected[key], "%s keeps its original %s" % [id, key])

	# new enemies exist
	for id in NEW_IDS:
		t.check(not EnemyTable.get_def(id).is_empty(), "new enemy %s exists" % id)

	# helpers
	t.check_eq(EnemyTable.name_of("wolf"), "Wolf", "name_of")
	t.check_eq(EnemyTable.name_of("nope"), "", "name_of unknown")
	t.check_eq(EnemyTable.ids_named("Dire Wolf"), ["dire_wolf"], "ids_named")
	t.check_eq(EnemyTable.ids_named("Nobody"), [], "ids_named unknown")
	t.check(EnemyTable.get_def("nope").is_empty(), "get_def unknown is empty")
```

Add `"res://tests/suite_enemy_table.gd"` to `SUITES`.

- [ ] **Step 2: Run tests to verify they fail**

Import pass, then tests. Expected: `FAIL: suite failed to load: res://tests/suite_enemy_table.gd`.

- [ ] **Step 3: Implement**

`scripts/systems/enemy_table.gd`:

```gdscript
class_name EnemyTable
extends RefCounted

## Central enemy definitions. SpawnPoint reads an entry by id; quests match
## kills by `name`; the (future) codex lists these. Sprites are recolored /
## rescaled versions of the two existing sheets ("wolf", "bandit").
## `loot_level`: random drops only pick items with level_req <= this.
## `guaranteed_drop` (bosses/elites): always dropped, and gold is x5.

const SPRITE_FRAMES := {
	"wolf": "res://assets/sprites/wolf/wolf_frames.tres",
	"bandit": "res://assets/sprites/bandit/bandit_frames.tres",
}

const ENEMIES := {
	# --- Thornfield Meadow / Blackthorn Forest / Sundered Crypt (unchanged stats) ---
	"wolf": {
		"name": "Wolf", "sprite": "wolf", "tint": Color(1, 1, 1, 1), "sprite_size": 40.0,
		"max_hp": 18, "move_speed": 70.0, "attack_min": 2, "attack_max": 4, "aggro_range": 120.0,
		"xp_reward": 20, "gold_min": 1, "gold_max": 3, "loot_level": 2, "guaranteed_drop": "",
	},
	"dire_wolf": {
		"name": "Dire Wolf", "sprite": "wolf", "tint": Color(1, 1, 1, 1), "sprite_size": 40.0,
		"max_hp": 30, "move_speed": 75.0, "attack_min": 4, "attack_max": 7, "aggro_range": 120.0,
		"xp_reward": 35, "gold_min": 1, "gold_max": 3, "loot_level": 3, "guaranteed_drop": "",
	},
	"bandit": {
		"name": "Bandit", "sprite": "bandit", "tint": Color(1, 1, 1, 1), "sprite_size": 40.0,
		"max_hp": 35, "move_speed": 45.0, "attack_min": 4, "attack_max": 8, "aggro_range": 120.0,
		"xp_reward": 35, "gold_min": 1, "gold_max": 3, "loot_level": 2, "guaranteed_drop": "",
	},
	"bandit_captain": {
		"name": "Bandit Captain", "sprite": "bandit", "tint": Color(0.65, 0.3, 0.85, 1.0), "sprite_size": 56.0,
		"max_hp": 70, "move_speed": 50.0, "attack_min": 8, "attack_max": 14, "aggro_range": 120.0,
		"xp_reward": 90, "gold_min": 1, "gold_max": 3, "loot_level": 3, "guaranteed_drop": "iron_sword",
	},
	# A small, enclosed dungeon room (360x360): this aggro range exceeds the
	# worst-case corner-to-center distance (~255), so the boss reliably notices
	# the character on every visit instead of possibly never coming into range
	# during a short wander before the zone's dwell timer expires.
	"crypt_lord": {
		"name": "Crypt Lord", "sprite": "bandit", "tint": Color(0.2, 0.06, 0.1, 1.0), "sprite_size": 64.0,
		"max_hp": 150, "move_speed": 45.0, "attack_min": 10, "attack_max": 18, "aggro_range": 280.0,
		"xp_reward": 300, "gold_min": 1, "gold_max": 3, "loot_level": 4, "guaranteed_drop": "warlords_greatsword",
	},
	# --- Mirewater Swamp (levels 4+) ---
	"mire_wolf": {
		"name": "Mire Wolf", "sprite": "wolf", "tint": Color(0.55, 0.85, 0.6, 1.0), "sprite_size": 40.0,
		"max_hp": 45, "move_speed": 72.0, "attack_min": 5, "attack_max": 9, "aggro_range": 120.0,
		"xp_reward": 55, "gold_min": 3, "gold_max": 6, "loot_level": 6, "guaranteed_drop": "",
	},
	"bog_bandit": {
		"name": "Bog Bandit", "sprite": "bandit", "tint": Color(0.5, 0.85, 0.55, 1.0), "sprite_size": 40.0,
		"max_hp": 55, "move_speed": 46.0, "attack_min": 6, "attack_max": 11, "aggro_range": 120.0,
		"xp_reward": 65, "gold_min": 4, "gold_max": 7, "loot_level": 6, "guaranteed_drop": "",
	},
	"mire_tyrant": {
		"name": "Mire Tyrant", "sprite": "bandit", "tint": Color(0.25, 0.5, 0.3, 1.0), "sprite_size": 64.0,
		"max_hp": 260, "move_speed": 50.0, "attack_min": 14, "attack_max": 24, "aggro_range": 200.0,
		"xp_reward": 600, "gold_min": 6, "gold_max": 10, "loot_level": 6, "guaranteed_drop": "tyrants_maul",
	},
	# --- Frostpeak Pass (levels 7+) ---
	"frost_wolf": {
		"name": "Frost Wolf", "sprite": "wolf", "tint": Color(0.7, 0.88, 1.0, 1.0), "sprite_size": 42.0,
		"max_hp": 70, "move_speed": 78.0, "attack_min": 8, "attack_max": 13, "aggro_range": 130.0,
		"xp_reward": 90, "gold_min": 5, "gold_max": 9, "loot_level": 9, "guaranteed_drop": "",
	},
	"frost_raider": {
		"name": "Frost Raider", "sprite": "bandit", "tint": Color(0.6, 0.8, 1.0, 1.0), "sprite_size": 42.0,
		"max_hp": 85, "move_speed": 50.0, "attack_min": 9, "attack_max": 15, "aggro_range": 130.0,
		"xp_reward": 105, "gold_min": 6, "gold_max": 10, "loot_level": 9, "guaranteed_drop": "",
	},
	"raider_captain": {
		"name": "Raider Captain", "sprite": "bandit", "tint": Color(0.35, 0.55, 0.95, 1.0), "sprite_size": 58.0,
		"max_hp": 180, "move_speed": 55.0, "attack_min": 12, "attack_max": 20, "aggro_range": 160.0,
		"xp_reward": 260, "gold_min": 10, "gold_max": 16, "loot_level": 9, "guaranteed_drop": "rimewatch_helm",
	},
	"frostpeak_warlord": {
		"name": "Frostpeak Warlord", "sprite": "bandit", "tint": Color(0.9, 0.95, 1.0, 1.0), "sprite_size": 72.0,
		"max_hp": 420, "move_speed": 50.0, "attack_min": 18, "attack_max": 30, "aggro_range": 220.0,
		"xp_reward": 1200, "gold_min": 20, "gold_max": 30, "loot_level": 9, "guaranteed_drop": "glacier_plate",
	},
}

static func get_def(id: String) -> Dictionary:
	return ENEMIES.get(id, {})

static func name_of(id: String) -> String:
	return String(ENEMIES.get(id, {}).get("name", ""))

## Ids of every enemy with this display name (quests match kills by name).
static func ids_named(enemy_name: String) -> Array:
	var ids: Array = []
	for id in ENEMIES:
		if ENEMIES[id]["name"] == enemy_name:
			ids.append(id)
	return ids
```

- [ ] **Step 4: Run tests to verify they pass**

Import pass (new class + sidecars), then tests. Expected: `0 failures`. If a check in the plan's suite is wrong for the data (for example a gold range of `0`), fix whichever side is wrong and report it.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/enemy_table.gd scripts/systems/enemy_table.gd.uid tests/suite_enemy_table.gd tests/suite_enemy_table.gd.uid tests/run_tests.gd
git commit -m "Add EnemyTable: central definitions for twelve enemies

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Spawn points read the enemy table

**Files:**
- Create: `tests/suite_spawn_points.gd`
- Modify: `scripts/entities/spawn_point.gd`, `scripts/entities/enemy.gd`, `scenes/world/ThornfieldMeadow.tscn`, `scenes/world/BlackthornForest.tscn`, `scenes/world/SunderedCrypt.tscn`, `tests/run_tests.gd`

- [ ] **Step 1: Write the failing suite**

`tests/suite_spawn_points.gd`:

```gdscript
extends RefCounted

## Every `enemy_id = "..."` line in the world scenes must name a real
## EnemyTable entry, and no scene may still use the old per-field overrides.

const OLD_OVERRIDES := ["enemy_name_override", "max_hp_override", "move_speed_override", "attack_damage_min_override",
	"attack_damage_max_override", "xp_reward_override", "aggro_range_override", "sprite_frames_override",
	"sprite_size_override", "sprite_tint_override", "guaranteed_drop_id_override"]

func run(t) -> void:
	var regex := RegEx.new()
	regex.compile("enemy_id = \"([a-z_]+)\"")
	var total := 0
	for file_name in DirAccess.get_files_at("res://scenes/world"):
		if not file_name.ends_with(".tscn"):
			continue
		var text := FileAccess.get_file_as_string("res://scenes/world/" + file_name)
		for m in regex.search_all(text):
			total += 1
			var id := m.get_string(1)
			t.check(not EnemyTable.get_def(id).is_empty(), "%s: enemy_id '%s' exists in EnemyTable" % [file_name, id])
		for key in OLD_OVERRIDES:
			t.check(not text.contains(key + " ="), "%s no longer uses %s" % [file_name, key])
	t.check(total >= 7, "at least seven spawn points name an enemy (found %d)" % total)
```

Add `"res://tests/suite_spawn_points.gd"` to `SUITES`.

- [ ] **Step 2: Run tests to verify they fail**

Import pass, tests. Expected: `at least seven spawn points name an enemy (found 0)` and the old-override checks failing.

- [ ] **Step 3: Replace `spawn_point.gd`**

`scripts/entities/spawn_point.gd` (whole file; keep its line endings):

```gdscript
extends Node2D

## Spawns one enemy described by EnemyTable[enemy_id] and respawns it
## `respawn_delay_s` after it dies.
@export var enemy_scene: PackedScene
@export var enemy_id: String = ""
@export var respawn_delay_s: float = 8.0

var current_enemy: Node2D = null

func _ready() -> void:
	_spawn()

func _spawn() -> void:
	if enemy_scene == null:
		return
	var def := EnemyTable.get_def(enemy_id)
	if def.is_empty():
		push_warning("SpawnPoint %s has unknown enemy_id '%s'" % [name, enemy_id])
		return
	current_enemy = enemy_scene.instantiate()
	current_enemy.global_position = global_position
	current_enemy.spawn_point = self
	current_enemy.enemy_name = def["name"]
	current_enemy.max_hp = def["max_hp"]
	current_enemy.move_speed = def["move_speed"]
	current_enemy.attack_damage_min = def["attack_min"]
	current_enemy.attack_damage_max = def["attack_max"]
	current_enemy.aggro_range = def["aggro_range"]
	current_enemy.xp_reward = def["xp_reward"]
	current_enemy.gold_min = def["gold_min"]
	current_enemy.gold_max = def["gold_max"]
	current_enemy.loot_level = def["loot_level"]
	current_enemy.sprite_size = def["sprite_size"]
	current_enemy.sprite_tint = def["tint"]
	current_enemy.guaranteed_drop_id = def["guaranteed_drop"]
	current_enemy.get_node("AnimatedSprite2D").sprite_frames = load(EnemyTable.SPRITE_FRAMES[def["sprite"]])
	get_tree().current_scene.add_child.call_deferred(current_enemy)

func on_enemy_died() -> void:
	current_enemy = null
	await get_tree().create_timer(respawn_delay_s).timeout
	_spawn()
```

- [ ] **Step 4: `Enemy` loot level**

In `scripts/entities/enemy.gd`:
1. Add directly under `@export var gold_max: int = 3`:
```gdscript
## Random drops only pick items with level_req <= this (see LootTable.roll_drop).
@export var loot_level: int = 1
```
2. In `_drop_loot`, replace `LootTable.roll_drop(rng)` with `LootTable.roll_drop(rng, loot_level)`.

- [ ] **Step 5: Convert the three zone scenes**

Run this Python from the project root. It rewrites every `SpawnPoint*` node block: removes the old override lines (and the `#` comment lines inside the block), and adds `enemy_id` after the `enemy_scene` line. It keeps `position`, `respawn_delay_s` and `enemy_scene`.

```python
NAME_TO_ID = {"Wolf": "wolf", "Dire Wolf": "dire_wolf", "Bandit": "bandit",
              "Bandit Captain": "bandit_captain", "Crypt Lord": "crypt_lord"}
OLD = ("enemy_name_override", "max_hp_override", "move_speed_override", "attack_damage_min_override",
       "attack_damage_max_override", "xp_reward_override", "aggro_range_override", "sprite_frames_override",
       "sprite_size_override", "sprite_tint_override", "guaranteed_drop_id_override")

for path in ("scenes/world/ThornfieldMeadow.tscn", "scenes/world/BlackthornForest.tscn", "scenes/world/SunderedCrypt.tscn"):
    s = open(path, newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    chunks = s.split(nl + nl)
    out = []
    for chunk in chunks:
        if chunk.startswith('[node name="SpawnPoint'):
            lines = chunk.split(nl)
            enemy_name = None
            kept = []
            for line in lines:
                if line.startswith("enemy_name_override"):
                    enemy_name = line.split("=", 1)[1].strip().strip('"')
                if line.startswith(OLD) or line.startswith("#"):
                    continue
                kept.append(line)
            assert enemy_name in NAME_TO_ID, (path, enemy_name)
            final = []
            for line in kept:
                final.append(line)
                if line.startswith("enemy_scene"):
                    final.append('enemy_id = "%s"' % NAME_TO_ID[enemy_name])
            chunk = nl.join(final)
        out.append(chunk)
    open(path, 'w', newline='').write((nl + nl).join(out))
print("converted")
```

Afterwards check `git diff --stat` (only the three scene files) and open one converted block, for example:

```
[node name="SpawnPointWolf1" parent="." instance=ExtResource("1_spawnpoint")]
position = Vector2(150, -80)
enemy_scene = ExtResource("2_enemy")
enemy_id = "wolf"
```

The now-unused `SpriteFrames` ext_resources in those scenes may stay (harmless), or be removed if you also lower `load_steps` accordingly.

- [ ] **Step 6: Verify**

Import pass, then tests (`0 failures`; the spawn suite finds 7 spawn points). Then a live regression check (Godot MCP): launch, wait until connected, and confirm the three original zones behave as before:
- `game_eval` listing `get_tree().get_nodes_in_group("enemies")` gives, in Thornfield/Blackthorn/Crypt, the same enemies as before with the same name/hp/damage (compare against `EnemyTable`): 2 Wolf (hp 18), 1 Bandit (hp 35) in the meadow; 2 Dire Wolf (hp 30) and a Bandit Captain (hp 70, guaranteed_drop_id `iron_sword`, tinted purple, larger) in Blackthorn Forest; Crypt Lord (hp 150, guaranteed_drop_id `warlords_greatsword`, aggro_range 280) in the Crypt.
- Play at 4x for ~1 minute: fights work, enemies drop loot and gold, no errors (only the MCP plugin's warnings).
Stop the game.

- [ ] **Step 7: Commit**

```bash
git add scripts/entities/spawn_point.gd scripts/entities/enemy.gd scenes/world/ThornfieldMeadow.tscn scenes/world/BlackthornForest.tscn scenes/world/SunderedCrypt.tscn tests/suite_spawn_points.gd tests/suite_spawn_points.gd.uid tests/run_tests.gd
git commit -m "Spawn points read enemy definitions from EnemyTable

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Zone and quest tables

**Files:**
- Create: `tests/suite_zone_table.gd`, `tests/suite_quest_table.gd`
- Modify: `tests/run_tests.gd`, `scripts/systems/zone_table.gd`, `scripts/systems/quest_table.gd`

- [ ] **Step 1: Write the failing suites**

`tests/suite_zone_table.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	t.check_eq(ZoneTable.TRAVEL_ORDER.size(), ZoneTable.ZONES.size(), "travel order covers every zone")
	for id in ZoneTable.TRAVEL_ORDER:
		t.check(ZoneTable.ZONES.has(id), "travel order id %s exists" % id)
	for id in ZoneTable.ZONES:
		t.check(ZoneTable.TRAVEL_ORDER.has(id), "zone %s is in the travel order" % id)
	t.check(ZoneTable.ZONES.has("mirewater_swamp") and ZoneTable.ZONES.has("frostpeak_pass"), "new zones exist")
	t.check_eq(ZoneTable.ZONES["mirewater_swamp"]["min_level"], 4, "swamp min level")
	t.check_eq(ZoneTable.ZONES["frostpeak_pass"]["min_level"], 7, "pass min level")

	var previous_min := 1
	var previous_center_x := -INF
	for id in ZoneTable.TRAVEL_ORDER:
		var zone: Dictionary = ZoneTable.ZONES[id]
		var bmin: Vector2 = zone["bounds_min"]
		var bmax: Vector2 = zone["bounds_max"]
		var center: Vector2 = zone["center"]
		t.check(String(zone["name"]) != "", "%s has a name" % id)
		t.check(bmin.x < bmax.x and bmin.y < bmax.y, "%s bounds are a real rectangle" % id)
		t.check(center.x > bmin.x and center.x < bmax.x and center.y > bmin.y and center.y < bmax.y, "%s center is inside its bounds" % id)
		t.check(center.x > previous_center_x, "%s lies further along the world line than the previous zone" % id)
		previous_center_x = center.x
		var min_level := int(zone.get("min_level", 1))
		t.check(min_level >= previous_min, "%s min_level does not decrease along the travel order" % id)
		t.check(min_level <= LevelingSystem.MAX_LEVEL, "%s min_level is reachable" % id)
		previous_min = min_level
		t.check(bmin.x >= ZoneTable.WORLD_BOUNDS_MIN.x and bmin.y >= ZoneTable.WORLD_BOUNDS_MIN.y, "%s min bounds inside the world" % id)
		t.check(bmax.x <= ZoneTable.WORLD_BOUNDS_MAX.x and bmax.y <= ZoneTable.WORLD_BOUNDS_MAX.y, "%s max bounds inside the world" % id)
		t.check(ZoneTable.stay_duration_ms(id) > 0.0, "%s has a stay duration" % id)

	# zones must not overlap each other
	var ids: Array = ZoneTable.ZONES.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = ZoneTable.ZONES[ids[i]]
			var b: Dictionary = ZoneTable.ZONES[ids[j]]
			var overlap: bool = a["bounds_min"].x < b["bounds_max"].x and a["bounds_max"].x > b["bounds_min"].x \
				and a["bounds_min"].y < b["bounds_max"].y and a["bounds_max"].y > b["bounds_min"].y
			t.check(not overlap, "%s and %s do not overlap" % [ids[i], ids[j]])

	# travel loop by level
	t.check_eq(ZoneTable.next_zone_id("sundered_crypt", 4), "mirewater_swamp", "crypt -> swamp at level 4")
	t.check_eq(ZoneTable.next_zone_id("mirewater_swamp", 6), "thornfield_meadow", "swamp -> meadow below the pass's level")
	t.check_eq(ZoneTable.next_zone_id("mirewater_swamp", 7), "frostpeak_pass", "swamp -> pass at level 7")
	t.check_eq(ZoneTable.next_zone_id("frostpeak_pass", 10), "thornfield_meadow", "the loop wraps around")
```

`tests/suite_quest_table.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	var ids := {}
	for quest in QuestTable.QUESTS:
		t.check(not ids.has(quest["id"]), "quest id %s is unique" % quest["id"])
		ids[quest["id"]] = quest
	t.check_eq(QuestTable.QUESTS.size(), 13, "thirteen quests")
	for quest in QuestTable.QUESTS:
		var id: String = quest["id"]
		t.check(not EnemyTable.ids_named(quest["target_name"]).is_empty(), "%s targets a real enemy (%s)" % [id, quest["target_name"]])
		t.check(int(quest["count"]) >= 1, "%s has a positive count" % id)
		t.check(int(quest["xp_reward"]) > 0, "%s pays xp" % id)
		t.check(int(quest["min_level"]) >= 1 and int(quest["min_level"]) <= LevelingSystem.MAX_LEVEL, "%s min_level in range" % id)
		var reward: String = quest["item_reward"]
		if reward != "":
			t.check(LootTable.ITEMS.has(reward), "%s reward %s exists" % [id, reward])
			if LootTable.ITEMS.has(reward):
				t.check(int(LootTable.ITEMS[reward].get("level_req", 1)) <= int(quest["min_level"]), "%s reward %s is equippable at the quest's level" % [id, reward])
		for prereq in quest["requires"]:
			t.check(ids.has(prereq), "%s prerequisite %s exists" % [id, prereq])
			if ids.has(prereq):
				t.check(int(ids[prereq]["min_level"]) <= int(quest["min_level"]), "%s does not require a higher-level quest (%s)" % [id, prereq])
	# the chains have no cycles
	for quest in QuestTable.QUESTS:
		t.check(not _has_cycle(ids, quest["id"], []), "%s has no prerequisite cycle" % quest["id"])
	# the two intro quests are always available at level 1
	var intro := 0
	for quest in QuestTable.QUESTS:
		if quest["requires"].is_empty() and int(quest["min_level"]) == 1:
			intro += 1
	t.check(intro >= 2, "at least two level-1 quests without prerequisites")
	# the new chain
	for id in ["drain_the_mire", "bog_bandits", "the_mire_tyrant", "frozen_fangs", "raiders_of_the_pass", "raider_captain_bounty", "the_frostpeak_warlord"]:
		t.check(ids.has(id), "new quest %s exists" % id)

func _has_cycle(ids: Dictionary, id: String, path: Array) -> bool:
	if path.has(id):
		return true
	var next_path := path.duplicate()
	next_path.append(id)
	for prereq in ids[id]["requires"]:
		if ids.has(prereq) and _has_cycle(ids, prereq, next_path):
			return true
	return false
```

Add both suites to `SUITES`.

- [ ] **Step 2: Run tests to verify they fail**

Import pass, tests. Expected: failures (new zones/quests missing).

- [ ] **Step 3: Extend `ZoneTable`**

In `scripts/systems/zone_table.gd` (preserve line endings):
1. Add to `ZONES`, after the `sundered_crypt` entry:

```gdscript
	"mirewater_swamp": {
		"name": "Mirewater Swamp",
		"center": Vector2(6600, 0),
		"bounds_min": Vector2(6220, -280),
		"bounds_max": Vector2(6980, 280),
		"min_level": 4,
	},
	"frostpeak_pass": {
		"name": "Frostpeak Pass",
		"center": Vector2(8800, 0),
		"bounds_min": Vector2(8420, -280),
		"bounds_max": Vector2(9180, 280),
		"min_level": 7,
	},
```
2. `TRAVEL_ORDER := ["thornfield_meadow", "blackthorn_forest", "sundered_crypt", "mirewater_swamp", "frostpeak_pass"]`
3. `WORLD_BOUNDS_MAX := Vector2(9180, 280)`
4. Update the comment above `WORLD_BOUNDS_MIN` if it names specific zones.

- [ ] **Step 4: Add the quests**

In `scripts/systems/quest_table.gd`, append these entries to `QUESTS` after `hero_of_thornfield` (same dictionary format as the existing entries; preserve line endings):

```gdscript
	{
		"id": "drain_the_mire", "name": "Drain the Mire",
		"target_name": "Mire Wolf", "count": 4,
		"xp_reward": 250, "item_reward": "greater_health_potion", "min_level": 4,
		"requires": ["the_crypt_lord"],
	},
	{
		"id": "bog_bandits", "name": "Bog Bandits",
		"target_name": "Bog Bandit", "count": 3,
		"xp_reward": 250, "item_reward": "", "min_level": 4,
		"requires": ["the_crypt_lord"],
	},
	{
		"id": "the_mire_tyrant", "name": "The Mire Tyrant",
		"target_name": "Mire Tyrant", "count": 1,
		"xp_reward": 500, "item_reward": "reinforced_mail", "min_level": 5,
		"requires": ["drain_the_mire", "bog_bandits"],
	},
	{
		"id": "frozen_fangs", "name": "Frozen Fangs",
		"target_name": "Frost Wolf", "count": 4,
		"xp_reward": 450, "item_reward": "swamp_charm", "min_level": 7,
		"requires": ["the_mire_tyrant"],
	},
	{
		"id": "raiders_of_the_pass", "name": "Raiders of the Pass",
		"target_name": "Frost Raider", "count": 3,
		"xp_reward": 450, "item_reward": "bog_bulwark", "min_level": 7,
		"requires": ["the_mire_tyrant"],
	},
	{
		"id": "raider_captain_bounty", "name": "The Raider Captain",
		"target_name": "Raider Captain", "count": 1,
		"xp_reward": 700, "item_reward": "frozen_band", "min_level": 8,
		"requires": ["frozen_fangs", "raiders_of_the_pass"],
	},
	{
		"id": "the_frostpeak_warlord", "name": "The Frostpeak Warlord",
		"target_name": "Frostpeak Warlord", "count": 1,
		"xp_reward": 1000, "item_reward": "rimewatch_amulet", "min_level": 9,
		"requires": ["raider_captain_bounty", "hero_of_thornfield"],
	},
```

Update the doc comment above `QUESTS` (the ASCII chain diagram) to mention the two new chains.

- [ ] **Step 5: Run tests to verify they pass**

Import pass (new suites), then tests. Expected: `0 failures`. If an existing behavior depends on the old zone count (search `scripts/` for `TRAVEL_ORDER` and `ZONES` users) and breaks, report it.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/zone_table.gd scripts/systems/quest_table.gd tests/suite_zone_table.gd tests/suite_zone_table.gd.uid tests/suite_quest_table.gd tests/suite_quest_table.gd.uid tests/run_tests.gd
git commit -m "Add Mirewater Swamp and Frostpeak Pass zones and seven quests to the tables

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

The game is not fully consistent until Task 6 adds the zone scenes (the travel loop would send a level 4+ character toward a zone with no scene). Do not run the game between Task 5 and Task 6.

---

### Task 6: New zone scenes, world layout, allies

**Files:**
- Create: `scenes/world/MirewaterSwamp.tscn`, `scenes/world/FrostpeakPass.tscn`
- Modify: `scenes/world/World.tscn`, `tests/suite_name_table.gd`, `tests/suite_spawn_points.gd`

- [ ] **Step 1: Tests first**

1. `tests/suite_name_table.gd`: change `ALLY_NAMES` to `["Kaelen", "Elowen", "Brynhild", "Gorrim", "Vesper", "Hrolf"]`.
2. `tests/suite_spawn_points.gd`: change the last check to `t.check(total >= 18, "all 18 spawn points name an enemy (found %d)" % total)` (Thornfield 3 + Blackthorn 3 + Crypt 1 + Swamp 5 + Pass 6).
3. Run tests: expected failure `all 18 spawn points ... (found 7)`.

- [ ] **Step 2: Create `MirewaterSwamp.tscn`**

Start from a copy of `scenes/world/BlackthornForest.tscn` (`cp`; it has the background, tinted ground, decorations, pond, archway, 14 border trees and two simulated players) and edit the copy with Python/hand edits (preserve the file's line endings; it may be LF or CRLF):

- Header/ext_resources: keep them (they are all still used or harmless); make sure ids referenced by the nodes below exist (`1_spawnpoint`, `2_enemy`, `5_tree_pine`, `6_grass`, `7_decor`, `8_tuft`, `9_rock`, `10_pond`, `12_simplayer`). Add `[ext_resource type="PackedScene" path="res://scenes/entities/QuestGiver.tscn" id="20_questgiver"]` and bump `load_steps` by 1. Remove the two `SpriteFrames` ext_resources only if you also remove nothing else needs them (safe to leave).
- Root node name: `MirewaterSwamp`.
- `Background` color: `Color(0.10, 0.18, 0.14, 1.0)`.
- `Ground` modulate: `Color(0.30, 0.45, 0.42, 1.0)` (dark teal-green).
- Every tree's `modulate`: `Color(0.55, 0.70, 0.60, 1.0)`.
- `Pond`: `modulate = Color(0.60, 0.85, 0.75, 1.0)`, `scale = Vector2(2.2, 2.2)`, `position = Vector2(-200, -120)`.
- `RuinArchway`: delete the node (and its ext_resource is then unused, leave it).
- `Decorations`: `count = 40` (more tufts and rocks).
- Delete `SimulatedPlayerBrynhild`, `SimulatedPlayerGorrim` and all three `SpawnPoint*` nodes; add these instead (at the end of the scene):

```
[node name="QuestGiver" parent="." instance=ExtResource("20_questgiver")]
position = Vector2(-280, -160)

[node name="SimulatedPlayerVesper" parent="." instance=ExtResource("12_simplayer")]
position = Vector2(-40, 230)
player_name = "Vesper"
max_hp = 70
attack_damage_min = 9
attack_damage_max = 14
sprite_tint = Color(0.7, 0.9, 0.75, 1.0)
home_zone_id = "mirewater_swamp"

[node name="SpawnPointMireWolf1" parent="." instance=ExtResource("1_spawnpoint")]
position = Vector2(150, -80)
enemy_scene = ExtResource("2_enemy")
enemy_id = "mire_wolf"

[node name="SpawnPointMireWolf2" parent="." instance=ExtResource("1_spawnpoint")]
position = Vector2(-180, 100)
enemy_scene = ExtResource("2_enemy")
enemy_id = "mire_wolf"

[node name="SpawnPointBogBandit1" parent="." instance=ExtResource("1_spawnpoint")]
position = Vector2(-120, -150)
enemy_scene = ExtResource("2_enemy")
enemy_id = "bog_bandit"

[node name="SpawnPointBogBandit2" parent="." instance=ExtResource("1_spawnpoint")]
position = Vector2(200, 150)
enemy_scene = ExtResource("2_enemy")
enemy_id = "bog_bandit"

[node name="SpawnPointMireTyrant" parent="." instance=ExtResource("1_spawnpoint")]
position = Vector2(60, 150)
respawn_delay_s = 120.0
enemy_scene = ExtResource("2_enemy")
enemy_id = "mire_tyrant"
```

(If the ext_resource id for the SimulatedPlayer scene in the copied file is not `12_simplayer`, use whatever id it has.)

- [ ] **Step 3: Create `FrostpeakPass.tscn`**

Copy `BlackthornForest.tscn` again and edit:

- Root node `FrostpeakPass`.
- `Background` color `Color(0.75, 0.82, 0.90, 1.0)`.
- `Ground` (grass texture): start with `modulate = Color(2.2, 2.4, 2.8, 1.0)` to wash the grass out to a snowy pale blue; adjust visually (see Step 5) until it reads as snow rather than grass. If tinting cannot get there, swap the ground texture to `terrain_stone.png` (ext_resource `res://assets/tiles/terrain_stone.png`) with a light modulate such as `Color(1.05, 1.1, 1.2, 1.0)`.
- Every tree `modulate = Color(0.85, 0.95, 1.10, 1.0)`.
- `Pond`: `modulate = Color(0.85, 0.95, 1.0, 1.0)` (frozen look), `scale = Vector2(1.3, 1.3)`.
- `RuinArchway`: `modulate = Color(0.85, 0.9, 1.0, 1.0)` (keep it as a gateway landmark).
- `Decorations`: keep rocks/tufts, `count = 30`.
- Delete the two simulated players and three spawn points; add:

```
[node name="SimulatedPlayerHrolf" parent="." instance=ExtResource("12_simplayer")]
position = Vector2(0, 230)
player_name = "Hrolf"
max_hp = 90
attack_damage_min = 12
attack_damage_max = 18
sprite_tint = Color(0.75, 0.85, 1.0, 1.0)
home_zone_id = "frostpeak_pass"

[node name="SpawnPointFrostWolf1" parent="." instance=ExtResource("1_spawnpoint")]
position = Vector2(150, -80)
enemy_scene = ExtResource("2_enemy")
enemy_id = "frost_wolf"

[node name="SpawnPointFrostWolf2" parent="." instance=ExtResource("1_spawnpoint")]
position = Vector2(-180, 100)
enemy_scene = ExtResource("2_enemy")
enemy_id = "frost_wolf"

[node name="SpawnPointFrostRaider1" parent="." instance=ExtResource("1_spawnpoint")]
position = Vector2(-120, -150)
enemy_scene = ExtResource("2_enemy")
enemy_id = "frost_raider"

[node name="SpawnPointFrostRaider2" parent="." instance=ExtResource("1_spawnpoint")]
position = Vector2(200, 150)
enemy_scene = ExtResource("2_enemy")
enemy_id = "frost_raider"

[node name="SpawnPointRaiderCaptain" parent="." instance=ExtResource("1_spawnpoint")]
position = Vector2(60, 150)
respawn_delay_s = 90.0
enemy_scene = ExtResource("2_enemy")
enemy_id = "raider_captain"

[node name="SpawnPointFrostpeakWarlord" parent="." instance=ExtResource("1_spawnpoint")]
position = Vector2(0, 0)
respawn_delay_s = 150.0
enemy_scene = ExtResource("2_enemy")
enemy_id = "frostpeak_warlord"
```

- [ ] **Step 4: Place the zones in `World.tscn`**

In `scenes/world/World.tscn` (preserve line endings), add two ext_resources (ids `5_swamp`, `6_pass`) for the new scenes, bump `load_steps` by 2, and add these nodes at the end:

```
[node name="MirewaterSwamp" parent="." instance=ExtResource("5_swamp")]
position = Vector2(6600, 0)

[node name="FrostpeakPass" parent="." instance=ExtResource("6_pass")]
position = Vector2(8800, 0)

[node name="Corridor3" type="ColorRect" parent="."]
position = Vector2(4600, -50)
size = Vector2(1600, 100)
color = Color(0.22, 0.28, 0.24, 1.0)

[node name="Corridor3Path" type="Sprite2D" parent="."]
modulate = Color(0.55, 0.65, 0.58, 1.0)
texture = ExtResource("4_path")
centered = false
position = Vector2(4600, -50)
region_enabled = true
region_rect = Rect2(0, 0, 1600, 100)
texture_repeat = 2

[node name="Corridor4" type="ColorRect" parent="."]
position = Vector2(7000, -50)
size = Vector2(1400, 100)
color = Color(0.7, 0.76, 0.84, 1.0)

[node name="Corridor4Path" type="Sprite2D" parent="."]
modulate = Color(0.85, 0.92, 1.05, 1.0)
texture = ExtResource("4_path")
centered = false
position = Vector2(7000, -50)
region_enabled = true
region_rect = Rect2(0, 0, 1400, 100)
texture_repeat = 2
```

(The crypt room spans x 4200-4600 and the swamp x 6200-7000, the pass x 8400-9200, so Corridor3 covers 4600-6200 and Corridor4 covers 7000-8400.)

- [ ] **Step 5: Verify (tests + live)**

Import pass (twice: new scenes), then the tests (`0 failures`; the spawn suite now finds 18 spawn points). Then a live check with the Godot MCP tools:
- Launch; the game must start without errors. Use `game_eval` to teleport the character: to the swamp (`Vector2(6600, 0)`) and to the pass (`Vector2(8800, 0)`), taking screenshots each time (pull the camera in: it follows the character).
- **Swamp:** dark teal ground, green-tinted trees, larger pond, quest board visible at the upper left of the zone, allies, enemies with green tints (Mire Wolf, Bog Bandit) and the large dark-green Mire Tyrant; names show correctly on the target frame (`Mire Tyrant (Elite)`).
- **Pass:** snowy pale ground (adjust the `Ground` modulate/texture per Step 3 until it clearly reads as snow, not grass), blue-tinted trees, frozen pond, blue enemies (Frost Wolf, Frost Raider), Raider Captain (larger, deep blue, Elite tag) and the very large white Frostpeak Warlord.
- Corridors: walk/teleport along the corridor between the crypt and the swamp and between the swamp and the pass; the path sprites line up with the zone edges without gaps.
- `game_get_errors`: only the MCP plugin's warnings. Stop the game.

Fix visual problems within the intent above and report exactly what you changed (colors, positions).

- [ ] **Step 6: Commit**

```bash
git add scenes/world/MirewaterSwamp.tscn scenes/world/FrostpeakPass.tscn scenes/world/World.tscn tests/suite_name_table.gd tests/suite_spawn_points.gd
git commit -m "Add Mirewater Swamp and Frostpeak Pass scenes, corridors and allies

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Live tuning, docs and final verification

**Files:**
- Modify: `README.md`, possibly `scripts/systems/enemy_table.gd` (stat tuning only)

- [ ] **Step 1: Progression run**

Using the Godot MCP tools, verify the whole ladder. For each stage, raise the character with `get_node("/root/Main/Character").gain_xp(N)` (thresholds: level 4 needs 450 total xp, 5 -> 700, 6 -> 1000, 7 -> 1400, 8 -> 1900, 9 -> 2500, 10 -> 3200), teleport, run at 4x and watch a few fights (screenshots, log via `get_debug_output`):
- Level 4 in the swamp (`gain_xp(450)`): fights against Mire Wolves and Bog Bandits are winnable with some HP loss, the character sometimes flees/rests; the Mire Tyrant is a real fight (may need levels 5-6 or allies); drops there are usable (gear with level_req <= 6 only).
- Level 7 in the pass (`gain_xp(1400)`): Frost enemies are similarly challenging but winnable; Raider Captain and Frostpeak Warlord are boss fights.
- Level 10 (`gain_xp(3200)`): XP bar reads `MAX`; further xp does not level; sheet shows level 10.
- Boss kills drop their guaranteed items (`tyrants_maul`, `rimewatch_helm`, `glacier_plate`) and 5x gold; you can force this by dealing damage: `for e in get_tree().get_nodes_in_group("enemies"): if e.enemy_name == "Mire Tyrant": e.take_damage(9999, get_node("/root/Main/Character"))`.
- Quests: with the character at the swamp board (or `_accept_next_quest` via normal play) confirm a swamp quest can be accepted and progress when killing Mire Wolves (`Quest: Drain the Mire 1/4` on the tracker), and that turn-in works at the swamp board.
- The travel loop reaches all five zones in order (`Time to move on - heading to Mirewater Swamp` etc.); levels below a zone's `min_level` skip it (a level 3 character goes crypt -> meadow).

Tune only if clearly needed: if a normal-tier enemy one-shots or is one-shot at its intended level, adjust its `max_hp` / `attack_min` / `attack_max` in `scripts/systems/enemy_table.gd` by ~20% steps and re-run the tests (`suite_enemy_table.gd` re-checks validity; the five original enemies must keep their original stats). Record the evidence for each stage.

- [ ] **Step 2: README and credits check**

In `README.md`: update the "What you'll see" text to five zones (Thornfield Meadow, Blackthorn Forest, Sundered Crypt, Mirewater Swamp, Frostpeak Pass), level cap 10, and the bosses; add `enemy_table.gd` to the systems description if the layout block lists individual system files. Confirm `assets/CREDITS.txt` lists the new icons (Task 2). Preserve line endings.

- [ ] **Step 3: Final run**

Run the tests (`0 failures`, count above 1945). Do a ~3-minute live run at 4x from the default start (no teleports): the game starts cleanly, the log shows normal play, `game_get_errors` shows only the MCP plugin's warnings.

- [ ] **Step 4: Commit**

```bash
git add README.md scripts/systems/enemy_table.gd
git commit -m "Document the expanded world; tune enemy stats after a progression run

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

(Stage `enemy_table.gd` only if you changed it.)

---

## Self-review notes (completed by the plan author)

- **Spec coverage:** enemy table + spawn refactor -> Tasks 3-4; level cap/XP -> 1; new items, icons, level-aware drops, boss-drop rule (`+2`) -> 2, 3 (test); zones/travel order/world bounds -> 5; zone scenes, corridors, allies, swamp board -> 6; seven new enemies, tints/sizes and quest chains -> 3, 5; validation suites (enemy, zone, quest, leveling, loot, spawn scan) -> 1-6; live progression check -> 7.
- **Rule interplay checked:** the old "epic level_req <= 3" test is removed in Task 2 (new epics are level 6-9) and replaced by the boss-drop `zone min + 2` rule in `suite_enemy_table.gd` (`mire_tyrant`: `tyrants_maul` L6 <= 4+2; `raider_captain`: `rimewatch_helm` L7 <= 7+2; `frostpeak_warlord`: `glacier_plate` L9 <= 7+2; `crypt_lord`: `warlords_greatsword` L3 <= 3+2; `bandit_captain`: `iron_sword` L1). Quest rewards satisfy `level_req <= min_level` (`reinforced_mail` L5 at L5, `swamp_charm` L5 at L7, `bog_bulwark` L6 at L7, `frozen_band` L8 at L8, `rimewatch_amulet` L8 at L9, `greater_health_potion` consumable).
- **Intermediate states:** the game is runnable after Tasks 1-4; not between Tasks 5 and 6 (the travel loop would target scene-less zones); Task 6 restores it.
- **Name consistency:** enemy names in `EnemyTable` equal the quests' `target_name`; `enemy_id` values in the scene blocks equal `EnemyTable.ENEMIES` keys; ally names in the scenes equal the `suite_name_table.gd` list.
