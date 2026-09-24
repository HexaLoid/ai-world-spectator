# Loot & Gear Depth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Six-slot, multi-stat gear with class-weighted equip decisions, armor mitigation, level requirements, gold drops, and a HUD that shows all six slots and gold.

**Architecture:** Pure, headless-testable rule classes (`ItemScoring`, `StatCalculator`) sit beside the existing static-table classes (`LootTable`, `AbilityTable`). `Character` keeps *base* stats and an `equipment` dictionary and derives `max_hp`, damage, crit and armor through `StatCalculator` (replacing the fragile delta arithmetic). The HUD listens to a changed `GameState.character_equipment_changed(equipment)` signal and a new `gold_changed` signal.

**Tech Stack:** Godot 4.7 (mono build, GDScript only), headless `--script` test runner.

**Spec:** `docs/superpowers/specs/2026-09-25-loot-and-gear-depth-design.md`

---

## Conventions used in every task

- Work in a dedicated git worktree/branch (e.g. `loot-gear-depth`). A fresh checkout needs **two** headless editor passes before scripts and textures resolve.
- Shell variable used below (bash on Windows):

```bash
GODOT="/c/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
```

- **Import pass** (registers new `class_name` scripts, writes `.gd.uid` sidecars, imports new images). Run from the project root whenever a task adds a new script or image, *before* running tests:

```bash
"$GODOT" --headless --path . --editor --quit
```

- **Run tests** (from the project root):

```bash
"$GODOT" --headless --path . --script res://tests/run_tests.gd
```

  Exit code 0 = all pass. Failures print lines starting `FAIL:`.
- Commit `.gd.uid` sidecars and `.png.import` files next to new scripts/images (repo convention). Do **not** commit Godot's line-ending-only rewrites of unrelated `.import` files or the `mcp_interaction_server` autoload line in `project.godot`.
- Commit messages end with: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`
- Line endings: files here are LF. If an edit tool fails to match, match on a single line without leading tabs.
- **The game is not runnable between Task 4 and Task 8** (the item schema changes before `Character` and the HUD are migrated). Tests run fine throughout; run the game only from Task 8 on.

## File structure

| File | Action | Responsibility |
|---|---|---|
| `tests/run_tests.gd` | create | Headless test runner and check helpers |
| `tests/suite_ability_table.gd` | create | Class stat-weight/primary-stat data checks |
| `tests/suite_loot_table.gd` | create | Item-table validation and drop-roll checks |
| `tests/suite_item_scoring.gd` | create | Scoring, level gating, upgrade decision, stat text |
| `tests/suite_stat_calculator.gd` | create | Derived stats and armor mitigation |
| `scripts/systems/ability_table.gd` | modify | Add `primary_stat`, `stat_weights` per class |
| `scripts/systems/loot_table.gd` | modify | New item schema, ~27 items, slot/label constants |
| `scripts/systems/item_scoring.gd` | create | Pure scoring / upgrade rules |
| `scripts/systems/stat_calculator.gd` | create | Pure derived-stat and armor math |
| `scripts/autoload/game_state.gd` | modify | New equipment signal signature, `gold_changed` |
| `scripts/entities/character.gd` | modify | `equipment`, `gold`, base stats, recompute, armor, wanted-item targeting |
| `scripts/entities/item_pickup.gd`, `scenes/entities/ItemPickup.tscn` | modify | Gold pickups and 30 s lifetime |
| `scripts/entities/enemy.gd` | modify | Gold drops |
| `scenes/ui/SpectatorUI.tscn`, `scripts/ui/unit_frame.gd` | modify | Six slot icons, gold counter |
| `assets/icons/*.png` (+ `.import`), `assets/CREDITS.txt` | add/modify | New item icons |
| `docs/superpowers/specs/2026-09-25-loot-and-gear-depth-design.md`, `README.md` | modify | Slot change note, features |

---

### Task 1: Amend the spec's slot list

The Kyrise icon pack (the project's icon source) has helmets, shields, necklaces and rings but **no leg or boot icons**, so the spec's `legs`/`boots` slots are replaced by `offhand` and `neck`, and `trinket` becomes `ring`. Final slots: `weapon`, `offhand`, `head`, `chest`, `neck`, `ring`.

**Files:**
- Modify: `docs/superpowers/specs/2026-09-25-loot-and-gear-depth-design.md`

- [ ] **Step 1: Apply the amendment**

Run this Python from the project root:

```python
p = 'docs/superpowers/specs/2026-09-25-loot-and-gear-depth-design.md'
s = open(p, newline='').read()

def sub(a, b):
    global s
    assert a in s, a
    s = s.replace(a, b)

sub('- Six equipment slots with multi-stat items', '- Six equipment slots (weapon, offhand, head, chest, neck, ring) with multi-stat items')
sub('**Slots:** `weapon`, `head`, `chest`, `legs`, `boots`, `trinket`.',
    '**Slots:** `weapon`, `offhand`, `head`, `chest`, `neck`, `ring`. (Amended during planning: the project\'s icon pack has no leg or boot icons, so `legs`/`boots` became `offhand` (shields) and `neck`, and `trinket` became `ring`.)')
sub('(weapon); `leather_armor`, `chainmail_armor`,\n`champions_plate` (chest); `lucky_charm`, `ring_of_fortune`, `amulet_of_wrath`,\n`crown_of_thornfield` (trinket). New head/legs/boots items are added',
    '(weapon); `leather_armor`, `chainmail_armor`,\n`champions_plate` (chest); `lucky_charm`, `amulet_of_wrath` (neck); `ring_of_fortune` (ring);\n`crown_of_thornfield` (head). New offhand/head/neck/ring items are added')
sub('(about 30-40 items total)', '(about 27 items to start)')
open(p, 'w', newline='').write(s)
```

Expected: no assertion error. (If a `sub` fails because of wrapped text, open the spec and make the same wording change by hand.)

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-09-25-loot-and-gear-depth-design.md
git commit -m "Amend gear spec: offhand/neck/ring slots instead of legs/boots/trinket

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Headless test runner and class stat data

**Files:**
- Create: `tests/run_tests.gd`, `tests/suite_ability_table.gd`
- Modify: `scripts/systems/ability_table.gd`

- [ ] **Step 1: Create the runner**

`tests/run_tests.gd`:

```gdscript
extends SceneTree

## Headless test runner. Run with:
##   godot --headless --path . --script res://tests/run_tests.gd
## Each suite is a script with a `run(t)` method that calls `t.check(...)` /
## `t.check_eq(...)`. Exit code is 1 if any check fails.

const SUITES := [
	"res://tests/suite_ability_table.gd",
]

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func check_eq(actual, expected, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])

func check_near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])

func _init() -> void:
	for path in SUITES:
		print("Running ", path.get_file())
		var suite = load(path).new()
		suite.run(self)
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
```

- [ ] **Step 2: Write the failing suite**

`tests/suite_ability_table.gd`:

```gdscript
extends RefCounted

const VALID_PRIMARY_STATS := ["strength", "intellect"]

func run(t) -> void:
	t.check(AbilityTable.CLASSES.size() >= 2, "at least two classes exist")
	for class_id in AbilityTable.CLASSES:
		var def: Dictionary = AbilityTable.CLASSES[class_id]
		t.check(VALID_PRIMARY_STATS.has(def.get("primary_stat", "")), "%s has a valid primary_stat" % class_id)
		var weights: Dictionary = def.get("stat_weights", {})
		t.check(float(weights.get("damage", 0.0)) > 0.0, "%s weights damage" % class_id)
		t.check(float(weights.get(def.get("primary_stat", ""), 0.0)) > 0.0, "%s weights its primary stat" % class_id)
	t.check_near(float(AbilityTable.CLASSES["warrior"]["stat_weights"]["damage"]), 3.0, "warrior damage weight")
	t.check_near(float(AbilityTable.CLASSES["mage"]["stat_weights"]["intellect"]), 2.0, "mage intellect weight")
```

- [ ] **Step 3: Run the tests to verify they fail**

Run the import pass, then the tests (see Conventions).
Expected: `FAIL: warrior has a valid primary_stat`, and so on; exit code 1. (Also confirms the runner itself works.)

- [ ] **Step 4: Add the class data**

In `scripts/systems/ability_table.gd`, in the `"warrior"` class, insert directly after the line `"rage_per_hit_taken": 3.0,`:

```gdscript
		"primary_stat": "strength",
		"stat_weights": {
			"damage": 3.0, "strength": 2.0, "armor": 2.0, "max_hp": 0.5, "crit_chance": 20.0,
		},
```

In the `"mage"` class, insert directly after the line `"resource_regen_per_second": 6.0,`:

```gdscript
		"primary_stat": "intellect",
		"stat_weights": {
			"damage": 3.0, "intellect": 2.0, "armor": 0.5, "max_hp": 0.3, "crit_chance": 20.0,
		},
```

- [ ] **Step 5: Run the tests to verify they pass**

Run the tests. Expected: `N checks, 0 failures`, exit code 0.

- [ ] **Step 6: Commit**

Run the import pass first so the `.uid` sidecars exist, then:

```bash
git add tests scripts/systems/ability_table.gd
git commit -m "Add headless test runner and per-class stat weights

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: New item icons

**Files:**
- Create: `assets/icons/{wooden_shield,iron_shield,tower_shield,leather_cap,iron_helm,steel_helm,silver_necklace,sage_pendant,copper_ring,ring_of_vigor,signet_of_power,apprentice_staff,oak_staff,arcane_staff,greater_health_potion,gold}_icon.png` (+ `.import` sidecars)
- Modify: `assets/CREDITS.txt`

The icons come from Kyrise's 16x16 RPG Icon Pack (32x32 variant), already downloaded and extracted this session. Source directory (session scratchpad):

```
C:/Users/n1njaz/AppData/Local/Temp/claude/C--Users-n1njaz-Desktop-New-folder/e6861214-ad52-4843-8a17-2a61398b9a86/scratchpad/kyrise_icons/extracted/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/32x32
```

If that directory no longer exists, ask the user before re-downloading the pack from https://opengameart.org/content/kyrises-free-16x16-rpg-icon-pack (downloads need explicit permission).

- [ ] **Step 1: Copy the icons under their item names**

```bash
SRC="/c/Users/n1njaz/AppData/Local/Temp/claude/C--Users-n1njaz-Desktop-New-folder/e6861214-ad52-4843-8a17-2a61398b9a86/scratchpad/kyrise_icons/extracted/Kyrise's 16x16 RPG Icon Pack - V1.2/icons/32x32"
DST=assets/icons
cp "$SRC/shield_01a.png" $DST/wooden_shield_icon.png
cp "$SRC/shield_02b.png" $DST/iron_shield_icon.png
cp "$SRC/shield_03d.png" $DST/tower_shield_icon.png
cp "$SRC/helmet_01a.png" $DST/leather_cap_icon.png
cp "$SRC/helmet_01c.png" $DST/iron_helm_icon.png
cp "$SRC/helmet_02c.png" $DST/steel_helm_icon.png
cp "$SRC/necklace_01b.png" $DST/silver_necklace_icon.png
cp "$SRC/necklace_02c.png" $DST/sage_pendant_icon.png
cp "$SRC/ring_01a.png" $DST/copper_ring_icon.png
cp "$SRC/ring_02b.png" $DST/ring_of_vigor_icon.png
cp "$SRC/ring_03d.png" $DST/signet_of_power_icon.png
cp "$SRC/staff_01a.png" $DST/apprentice_staff_icon.png
cp "$SRC/staff_02b.png" $DST/oak_staff_icon.png
cp "$SRC/staff_03d.png" $DST/arcane_staff_icon.png
cp "$SRC/potion_02c.png" $DST/greater_health_potion_icon.png
cp "$SRC/coin_01a.png" $DST/gold_icon.png
for n in wooden_shield iron_shield tower_shield leather_cap iron_helm steel_helm silver_necklace sage_pendant copper_ring ring_of_vigor signet_of_power apprentice_staff oak_staff arcane_staff greater_health_potion gold; do
  [ -f "$DST/${n}_icon.png" ] && echo "ok $n" || echo "MISSING $n"
done
```

Expected: sixteen `ok` lines and no `MISSING`.

- [ ] **Step 2: Import and eyeball**

Run the import pass **twice**. Then open a few of the new PNGs with the Read tool (e.g. `assets/icons/iron_helm_icon.png`, `assets/icons/arcane_staff_icon.png`, `assets/icons/gold_icon.png`) and confirm each looks like its item (helmet, staff, coin). If one is clearly wrong, swap in another file of the same category from `$SRC` (`ls "$SRC" | grep helmet`, etc.), keeping the destination name.

- [ ] **Step 3: Credit the icons**

In `assets/CREDITS.txt`, in the Kyrise section, extend the file list line that ends with `potion_icon.png (for the "health_potion" item)` so it also names the new files. Add this paragraph directly after that list:

```
Also from the same pack (32x32 variant): wooden_shield_icon.png,
iron_shield_icon.png, tower_shield_icon.png, leather_cap_icon.png,
iron_helm_icon.png, steel_helm_icon.png, silver_necklace_icon.png,
sage_pendant_icon.png, copper_ring_icon.png, ring_of_vigor_icon.png,
signet_of_power_icon.png, apprentice_staff_icon.png, oak_staff_icon.png,
arcane_staff_icon.png, greater_health_potion_icon.png, gold_icon.png.
```

- [ ] **Step 4: Commit**

```bash
git add assets/icons assets/CREDITS.txt
git commit -m "Add icons for new gear, staves, greater potion and gold

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

(Stage only the new `*_icon.png` and `*_icon.png.import` files plus CREDITS; skip unrelated line-ending rewrites.)

---

### Task 4: New item schema in `LootTable`

**Files:**
- Create: `tests/suite_loot_table.gd`
- Modify: `tests/run_tests.gd`, `scripts/systems/loot_table.gd`

- [ ] **Step 1: Write the failing suite**

`tests/suite_loot_table.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	t.check(LootTable.SLOTS.size() == 6, "six equipment slots")
	var items_per_slot := {}
	var has_level_one_common := {}
	for item_id in LootTable.ITEMS:
		var item: Dictionary = LootTable.ITEMS[item_id]
		t.check(LootTable.RARITY_WEIGHTS.has(item.get("rarity", "")), "%s has a valid rarity" % item_id)
		var icon: String = item.get("icon", "")
		t.check(icon != "" and FileAccess.file_exists(icon), "%s icon exists (%s)" % [item_id, icon])
		if item.get("type", "") == "consumable":
			t.check(int(item.get("heal", 0)) > 0, "%s heals" % item_id)
			t.check(not item.has("slot"), "%s (consumable) has no slot" % item_id)
			continue
		var slot: String = item.get("slot", "")
		t.check(LootTable.SLOTS.has(slot), "%s has a valid slot (%s)" % [item_id, slot])
		var stats: Dictionary = item.get("stats", {})
		t.check(not stats.is_empty(), "%s has stats" % item_id)
		for stat in stats:
			t.check(LootTable.STAT_LABELS.has(stat), "%s stat %s is known" % [item_id, stat])
		var level_req := int(item.get("level_req", 0))
		t.check(level_req >= 1 and level_req <= LevelingSystem.MAX_LEVEL, "%s level_req in range" % item_id)
		if item.get("rarity", "") == "epic":
			t.check(level_req <= 3, "%s (epic) is equippable by the level a boss/quest hands it out" % item_id)
		items_per_slot[slot] = int(items_per_slot.get(slot, 0)) + 1
		if item.get("rarity", "") == "common" and level_req == 1:
			has_level_one_common[slot] = true
	for slot in LootTable.SLOTS:
		t.check(int(items_per_slot.get(slot, 0)) >= 3, "slot %s has at least three items" % slot)
		t.check(has_level_one_common.has(slot), "slot %s has a common level-1 item" % slot)
	for quest in QuestTable.QUESTS:
		var reward: String = quest.get("item_reward", "")
		if reward != "":
			t.check(LootTable.ITEMS.has(reward), "quest %s reward %s exists" % [quest["id"], reward])
	for boss_drop in ["iron_sword", "warlords_greatsword"]:
		t.check(LootTable.ITEMS.has(boss_drop), "guaranteed drop %s exists" % boss_drop)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 300:
		var rolled := LootTable.roll_drop(rng)
		t.check(LootTable.ITEMS.has(rolled), "rolled item exists")
		t.check(LootTable.ITEMS[rolled]["rarity"] != "epic", "epic items never roll randomly")
	t.check_eq(LootTable.display_name("iron_helm"), "Iron Helm", "display_name capitalizes")
```

Add it to `SUITES` in `tests/run_tests.gd`:

```gdscript
const SUITES := [
	"res://tests/suite_ability_table.gd",
	"res://tests/suite_loot_table.gd",
]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the import pass, then the tests. Expected: many `FAIL:` lines (e.g. `six equipment slots`) — `LootTable.SLOTS` does not exist yet, so the suite may instead abort with a script error; either way the exit code is nonzero.

- [ ] **Step 3: Replace the item data**

In `scripts/systems/loot_table.gd`, replace everything from the doc comment above `const ITEMS := {` through the closing `}` of `ITEMS` (keep `RARITY_WEIGHTS`, `RARITY_COLORS`, `roll_drop`, and `display_name`) with:

```gdscript
## Equipment slots, in HUD display order.
const SLOTS := ["weapon", "offhand", "head", "chest", "neck", "ring"]

## Display names for each slot (HUD tooltips).
const SLOT_LABELS := {
	"weapon": "Weapon", "offhand": "Off-hand", "head": "Head",
	"chest": "Chest", "neck": "Neck", "ring": "Ring",
}

## Stat keys an item's "stats" dictionary may use, in the order they are
## listed in text ("+7 damage, +2 STR"), with their short display labels.
const STAT_ORDER := ["damage", "armor", "max_hp", "crit_chance", "strength", "intellect"]
const STAT_LABELS := {
	"damage": "damage", "armor": "armor", "max_hp": "HP",
	"crit_chance": "crit", "strength": "STR", "intellect": "INT",
}

## Static item definitions. Gear entries have "slot" (one of SLOTS), "rarity"
## (common/uncommon/rare/epic — drives RARITY_COLORS and RARITY_WEIGHTS),
## "level_req", "icon", and a "stats" dictionary using STAT_LABELS keys
## ("crit_chance" is a 0.0-1.0 fraction). Consumables have "type":
## "consumable" and a "heal" amount, and no slot. Equip decisions live in
## ItemScoring; derived-stat math lives in StatCalculator.
const ITEMS := {
	# Weapons
	"rusty_sword": {"slot": "weapon", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/sword_rusty_icon.png", "stats": {"damage": 4}},
	"iron_sword": {"slot": "weapon", "rarity": "uncommon", "level_req": 1, "icon": "res://assets/icons/sword_iron_icon.png", "stats": {"damage": 7}},
	"steel_sword": {"slot": "weapon", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/steel_sword_icon.png", "stats": {"damage": 11, "strength": 2}},
	"warlords_greatsword": {"slot": "weapon", "rarity": "epic", "level_req": 3, "icon": "res://assets/icons/warlords_greatsword_icon.png", "stats": {"damage": 18, "strength": 4}},
	"apprentice_staff": {"slot": "weapon", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/apprentice_staff_icon.png", "stats": {"damage": 3, "intellect": 2}},
	"oak_staff": {"slot": "weapon", "rarity": "uncommon", "level_req": 2, "icon": "res://assets/icons/oak_staff_icon.png", "stats": {"damage": 5, "intellect": 4}},
	"arcane_staff": {"slot": "weapon", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/arcane_staff_icon.png", "stats": {"damage": 8, "intellect": 7}},
	# Off-hand
	"wooden_shield": {"slot": "offhand", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/wooden_shield_icon.png", "stats": {"armor": 3}},
	"iron_shield": {"slot": "offhand", "rarity": "uncommon", "level_req": 2, "icon": "res://assets/icons/iron_shield_icon.png", "stats": {"armor": 5, "max_hp": 8}},
	"tower_shield": {"slot": "offhand", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/tower_shield_icon.png", "stats": {"armor": 8, "max_hp": 15, "strength": 1}},
	# Head
	"leather_cap": {"slot": "head", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/leather_cap_icon.png", "stats": {"armor": 1, "max_hp": 5}},
	"iron_helm": {"slot": "head", "rarity": "uncommon", "level_req": 2, "icon": "res://assets/icons/iron_helm_icon.png", "stats": {"armor": 2, "max_hp": 10}},
	"steel_helm": {"slot": "head", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/steel_helm_icon.png", "stats": {"armor": 4, "max_hp": 15, "strength": 2}},
	"crown_of_thornfield": {"slot": "head", "rarity": "epic", "level_req": 3, "icon": "res://assets/icons/crown_of_thornfield_icon.png", "stats": {"armor": 3, "max_hp": 15, "crit_chance": 0.10, "strength": 3, "intellect": 3}},
	# Chest
	"leather_armor": {"slot": "chest", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/armor_icon.png", "stats": {"armor": 2, "max_hp": 15}},
	"chainmail_armor": {"slot": "chest", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/chainmail_armor_icon.png", "stats": {"armor": 5, "max_hp": 25}},
	"champions_plate": {"slot": "chest", "rarity": "epic", "level_req": 3, "icon": "res://assets/icons/champions_plate_icon.png", "stats": {"armor": 9, "max_hp": 40, "strength": 3}},
	# Neck
	"lucky_charm": {"slot": "neck", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/lucky_charm_icon.png", "stats": {"crit_chance": 0.05}},
	"silver_necklace": {"slot": "neck", "rarity": "uncommon", "level_req": 2, "icon": "res://assets/icons/silver_necklace_icon.png", "stats": {"max_hp": 10, "crit_chance": 0.06}},
	"sage_pendant": {"slot": "neck", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/sage_pendant_icon.png", "stats": {"intellect": 5, "crit_chance": 0.08}},
	"amulet_of_wrath": {"slot": "neck", "rarity": "epic", "level_req": 3, "icon": "res://assets/icons/amulet_of_wrath_icon.png", "stats": {"damage": 2, "strength": 3, "crit_chance": 0.20}},
	# Ring
	"copper_ring": {"slot": "ring", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/copper_ring_icon.png", "stats": {"crit_chance": 0.03, "max_hp": 5}},
	"ring_of_vigor": {"slot": "ring", "rarity": "uncommon", "level_req": 2, "icon": "res://assets/icons/ring_of_vigor_icon.png", "stats": {"max_hp": 20}},
	"ring_of_fortune": {"slot": "ring", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/ring_of_fortune_icon.png", "stats": {"crit_chance": 0.12}},
	"signet_of_power": {"slot": "ring", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/signet_of_power_icon.png", "stats": {"damage": 3, "strength": 2, "intellect": 2}},
	# Consumables
	"health_potion": {"type": "consumable", "heal": 20, "rarity": "common", "icon": "res://assets/icons/potion_icon.png"},
	"greater_health_potion": {"type": "consumable", "heal": 45, "rarity": "uncommon", "icon": "res://assets/icons/greater_health_potion_icon.png"},
}
```

Then delete `should_equip()` and `_stat_key_for_type()` (the whole block from the `## Returns true if candidate_item_id should replace` comment to the end of `_stat_key_for_type`). Their replacement is `ItemScoring` (Task 5). Keep `RARITY_WEIGHTS`, `RARITY_COLORS`, `roll_drop()`, and `display_name()`.

- [ ] **Step 4: Run the tests to verify they pass**

Import pass, then run the tests. Expected: `N checks, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add tests scripts/systems/loot_table.gd
git commit -m "Give items slots and multi-stat definitions (27 items, six slots)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: `ItemScoring`

**Files:**
- Create: `scripts/systems/item_scoring.gd`, `tests/suite_item_scoring.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing suite**

`tests/suite_item_scoring.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	var warrior: Dictionary = AbilityTable.CLASSES["warrior"]
	var mage: Dictionary = AbilityTable.CLASSES["mage"]

	# score()
	t.check_near(ItemScoring.score("iron_sword", warrior), 21.0, "warrior scores iron_sword (7 damage x3)")
	t.check_near(ItemScoring.score("steel_sword", warrior), 37.0, "warrior scores steel_sword (11x3 + 2 STR x2)")
	t.check_near(ItemScoring.score("steel_sword", mage), 33.0, "mage ignores strength")
	t.check_near(ItemScoring.score("arcane_staff", mage), 38.0, "mage scores arcane_staff (8x3 + 7 INT x2)")
	t.check_near(ItemScoring.score("arcane_staff", warrior), 24.0, "warrior ignores intellect")
	t.check_near(ItemScoring.score("", warrior), 0.0, "empty slot scores 0")
	t.check_near(ItemScoring.score("no_such_item", warrior), 0.0, "unknown item scores 0")

	# meets_level()
	t.check(ItemScoring.meets_level("steel_sword", 3), "level 3 meets steel_sword's requirement")
	t.check(not ItemScoring.meets_level("steel_sword", 2), "level 2 does not meet steel_sword's requirement")

	# is_upgrade()
	t.check(ItemScoring.is_upgrade("", "rusty_sword", warrior, 1), "anything useful beats an empty slot")
	t.check(ItemScoring.is_upgrade("iron_sword", "steel_sword", warrior, 3), "steel beats iron at level 3")
	t.check(not ItemScoring.is_upgrade("iron_sword", "steel_sword", warrior, 2), "level requirement blocks an upgrade")
	t.check(not ItemScoring.is_upgrade("steel_sword", "iron_sword", warrior, 5), "a downgrade is not an upgrade")
	t.check(not ItemScoring.is_upgrade("iron_sword", "iron_sword", warrior, 5), "an equal item is not an upgrade (strict >)")
	t.check(not ItemScoring.is_upgrade("", "health_potion", warrior, 5), "consumables are never equipped")
	t.check(not ItemScoring.is_upgrade("", "no_such_item", warrior, 5), "unknown items are never equipped")
	t.check(ItemScoring.is_upgrade("", "tower_shield", mage, 5), "a mage still values a shield's armor over nothing")
	t.check(ItemScoring.is_upgrade("rusty_sword", "arcane_staff", mage, 3), "mage prefers the staff")
	t.check(not ItemScoring.is_upgrade("", "champions_plate", {}, 5), "an empty class_def scores everything 0, so nothing is an upgrade")

	# describe_stats()
	t.check_eq(ItemScoring.describe_stats("iron_helm"), "+2 armor, +10 HP", "describe iron_helm")
	t.check_eq(ItemScoring.describe_stats("lucky_charm"), "+5% crit", "describe crit as a percentage")
	t.check_eq(ItemScoring.describe_stats("steel_sword"), "+11 damage, +2 STR", "describe uses STAT_ORDER")
	t.check_eq(ItemScoring.describe_stats("health_potion"), "", "consumables have no stat text")
```

Add `"res://tests/suite_item_scoring.gd"` to `SUITES` in `tests/run_tests.gd`.

- [ ] **Step 2: Run the tests to verify they fail**

Import pass, then the tests. Expected: failure/abort because `ItemScoring` is not defined.

- [ ] **Step 3: Implement**

`scripts/systems/item_scoring.gd`:

```gdscript
class_name ItemScoring
extends RefCounted

## Pure equip-decision rules. Every function takes item ids and a class
## definition (an AbilityTable.CLASSES entry) and reads LootTable.ITEMS;
## nothing here touches nodes, so it is all unit-tested headlessly.

## Class-weighted value of an item: sum of (stat value * the class's weight
## for that stat). Unknown items and empty ids ("" = empty slot) score 0.
static func score(item_id: String, class_def: Dictionary) -> float:
	var stats: Dictionary = LootTable.ITEMS.get(item_id, {}).get("stats", {})
	var weights: Dictionary = class_def.get("stat_weights", {})
	var total := 0.0
	for stat in stats:
		total += float(stats[stat]) * float(weights.get(stat, 0.0))
	return total

static func meets_level(item_id: String, level: int) -> bool:
	return level >= int(LootTable.ITEMS.get(item_id, {}).get("level_req", 1))

## True if `candidate_id` should replace `current_id` ("" for an empty slot)
## in its slot: it must be a real gear item, the character must meet its
## level requirement, and it must score strictly higher. Callers pass the
## item currently in the CANDIDATE'S slot. Unknown/malformed items and
## consumables (no slot) fail closed.
static func is_upgrade(current_id: String, candidate_id: String, class_def: Dictionary, level: int) -> bool:
	var candidate: Dictionary = LootTable.ITEMS.get(candidate_id, {})
	if not LootTable.SLOTS.has(candidate.get("slot", "")):
		return false
	if not meets_level(candidate_id, level):
		return false
	return score(candidate_id, class_def) > score(current_id, class_def)

## "+2 armor, +10 HP" style text for logs and tooltips; "" if the item has no stats.
static func describe_stats(item_id: String) -> String:
	var stats: Dictionary = LootTable.ITEMS.get(item_id, {}).get("stats", {})
	var parts: Array[String] = []
	for stat in LootTable.STAT_ORDER:
		if not stats.has(stat):
			continue
		var value := float(stats[stat])
		if stat == "crit_chance":
			parts.append("+%d%% %s" % [roundi(value * 100.0), LootTable.STAT_LABELS[stat]])
		else:
			parts.append("+%d %s" % [roundi(value), LootTable.STAT_LABELS[stat]])
	return ", ".join(parts)
```

- [ ] **Step 4: Run the tests to verify they pass**

Import pass (new class), then the tests. Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add tests scripts/systems/item_scoring.gd scripts/systems/item_scoring.gd.uid
git commit -m "Add ItemScoring: class-weighted upgrade decisions

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: `StatCalculator`

**Files:**
- Create: `scripts/systems/stat_calculator.gd`, `tests/suite_stat_calculator.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing suite**

`tests/suite_stat_calculator.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	var warrior: Dictionary = AbilityTable.CLASSES["warrior"]
	var mage: Dictionary = AbilityTable.CLASSES["mage"]
	var base := {"max_hp": 60, "damage_min": 4, "damage_max": 8, "crit_chance": 0.0}

	# gear_totals()
	var totals := StatCalculator.gear_totals({"weapon": "steel_sword", "head": "iron_helm"})
	t.check_near(float(totals.get("damage", 0.0)), 11.0, "totals sum damage")
	t.check_near(float(totals.get("armor", 0.0)), 2.0, "totals sum armor")
	t.check_near(float(totals.get("max_hp", 0.0)), 10.0, "totals sum max_hp")
	t.check_eq(StatCalculator.gear_totals({}).size(), 0, "no gear, no totals")
	t.check_eq(StatCalculator.gear_totals({"weapon": "no_such_item", "head": ""}).size(), 0, "unknown/empty ids contribute nothing")

	# derive(): no gear leaves base stats untouched
	var bare := StatCalculator.derive(base, {}, warrior)
	t.check_eq(bare["max_hp"], 60, "bare max_hp")
	t.check_eq(bare["damage_min"], 4, "bare damage_min")
	t.check_eq(bare["damage_max"], 8, "bare damage_max")
	t.check_near(float(bare["crit_chance"]), 0.0, "bare crit")
	t.check_eq(bare["armor"], 0, "bare armor")

	# derive(): warrior with steel_sword (+11 dmg, +2 STR -> x1.02) and iron_helm (+2 armor, +10 HP)
	var geared := StatCalculator.derive(base, {"weapon": "steel_sword", "head": "iron_helm"}, warrior)
	t.check_eq(geared["damage_min"], 15, "(4+11) x 1.02 = 15.3 -> 15")
	t.check_eq(geared["damage_max"], 19, "(8+11) x 1.02 = 19.38 -> 19")
	t.check_eq(geared["max_hp"], 70, "max_hp includes helm")
	t.check_eq(geared["armor"], 2, "armor from helm")

	# derive(): a mage's strength is not its primary stat, so it does not boost damage
	var mage_geared := StatCalculator.derive(base, {"weapon": "steel_sword"}, mage)
	t.check_eq(mage_geared["damage_min"], 15, "mage: (4+11) x 1.0 = 15")
	# ...but its intellect is
	var mage_staff := StatCalculator.derive(base, {"weapon": "arcane_staff"}, mage)
	t.check_eq(mage_staff["damage_min"], 13, "(4+8) x 1.07 = 12.84 -> 13")

	# derive(): crit adds up
	var crit := StatCalculator.derive(base, {"neck": "lucky_charm", "ring": "ring_of_fortune"}, warrior)
	t.check_near(float(crit["crit_chance"]), 0.17, "crit from neck + ring")

	# mitigate()
	t.check_eq(StatCalculator.mitigate(10, 0), 10, "no armor, no reduction")
	t.check_eq(StatCalculator.mitigate(10, 25), 5, "25 armor halves damage (100 / (100 + 25x4))")
	t.check_eq(StatCalculator.mitigate(1, 100), 1, "damage never mitigated below 1")
	t.check_eq(StatCalculator.mitigate(0, 50), 0, "zero damage stays zero")
```

Add `"res://tests/suite_stat_calculator.gd"` to `SUITES`.

- [ ] **Step 2: Run the tests to verify they fail**

Import pass, then tests. Expected: failure/abort (`StatCalculator` undefined).

- [ ] **Step 3: Implement**

`scripts/systems/stat_calculator.gd`:

```gdscript
class_name StatCalculator
extends RefCounted

## Pure derived-stat math. `Character` keeps base stats and an equipment
## dictionary (slot -> item id) and calls derive() whenever either changes,
## instead of applying per-item deltas.

## Each armor point shrinks incoming damage: damage * 100 / (100 + armor * ARMOR_FACTOR).
const ARMOR_FACTOR := 4.0
## Each point of the class's primary stat (strength/intellect) adds this
## fraction to weapon damage.
const PRIMARY_STAT_DAMAGE_PER_POINT := 0.01

## Sums every equipped item's stats: {stat_key: total}. Unknown ids and
## empty ("") slots contribute nothing.
static func gear_totals(equipment: Dictionary) -> Dictionary:
	var totals := {}
	for slot in equipment:
		var stats: Dictionary = LootTable.ITEMS.get(equipment[slot], {}).get("stats", {})
		for stat in stats:
			totals[stat] = float(totals.get(stat, 0.0)) + float(stats[stat])
	return totals

## `base` has max_hp, damage_min, damage_max, crit_chance (the character's
## own stats before gear). Returns {max_hp, damage_min, damage_max,
## crit_chance, armor} with equipment and the class's primary stat applied.
static func derive(base: Dictionary, equipment: Dictionary, class_def: Dictionary) -> Dictionary:
	var gear := gear_totals(equipment)
	var primary: String = class_def.get("primary_stat", "")
	var damage_multiplier := 1.0
	if primary != "":
		damage_multiplier += float(gear.get(primary, 0.0)) * PRIMARY_STAT_DAMAGE_PER_POINT
	var gear_damage := float(gear.get("damage", 0.0))
	return {
		"max_hp": int(base["max_hp"]) + roundi(float(gear.get("max_hp", 0.0))),
		"damage_min": roundi((float(base["damage_min"]) + gear_damage) * damage_multiplier),
		"damage_max": roundi((float(base["damage_max"]) + gear_damage) * damage_multiplier),
		"crit_chance": float(base["crit_chance"]) + float(gear.get("crit_chance", 0.0)),
		"armor": roundi(float(gear.get("armor", 0.0))),
	}

## Damage actually taken after armor. Zero stays zero; any positive damage
## deals at least 1 so enemies can always hurt the character.
static func mitigate(damage: int, armor: int) -> int:
	if damage <= 0:
		return 0
	return maxi(1, roundi(float(damage) * 100.0 / (100.0 + float(armor) * ARMOR_FACTOR)))
```

- [ ] **Step 4: Run the tests to verify they pass**

Import pass, then tests. Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add tests scripts/systems/stat_calculator.gd scripts/systems/stat_calculator.gd.uid
git commit -m "Add StatCalculator: derived stats and armor mitigation

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Migrate `Character` to equipment, base stats and armor

**Files:**
- Modify: `scripts/autoload/game_state.gd`, `scripts/entities/character.gd`

The HUD is migrated in Task 9 — until then the unit frame's old signal handler will error if the game is run. Do not run the game yet.

- [ ] **Step 1: Change the signals**

In `scripts/autoload/game_state.gd`, replace the equipment signal (and its doc comment) with:

```gdscript
## Emitted whenever the character's equipment changes; `equipment` maps each
## slot name (see LootTable.SLOTS) to the equipped item id — a slot with no
## item is absent or "". Always a copy, safe for listeners to keep.
signal character_equipment_changed(equipment: Dictionary)
## Emitted whenever the character's gold total changes; amount is the new total.
signal gold_changed(amount: int)
```

- [ ] **Step 2: Replace the equipment/stat variables**

In `scripts/entities/character.gd`, replace these four lines:

```gdscript
var equipped_weapon_id: String = ""
var equipped_armor_id: String = ""
var equipped_trinket_id: String = ""
var crit_chance: float = 0.0
```

with:

```gdscript
## Slot name -> equipped item id (see LootTable.SLOTS); a missing key means
## the slot is empty. max_hp, attack_damage_min/max, crit_chance and armor are
## DERIVED from the base_* values plus equipment by _recompute_stats() —
## never adjust them directly for gear or level-ups, change the base and recompute.
var equipment: Dictionary = {}
var gold: int = 0
var armor: int = 0
var base_max_hp: int = 0
var base_damage_min: int = 0
var base_damage_max: int = 0
var crit_chance: float = 0.0
```

- [ ] **Step 3: Initialise base stats in `_ready()`**

In `_ready()`, directly after the line `sprite.modulate = class_def.get("sprite_tint", Color(1.0, 1.0, 1.0, 1.0))`, add:

```gdscript
	base_max_hp = max_hp
	base_damage_min = attack_damage_min
	base_damage_max = attack_damage_max
	_recompute_stats()
```

- [ ] **Step 4: Add `_recompute_stats()` and the gold helper**

Add these functions directly above `func gain_xp(amount: int) -> void:`:

```gdscript
## Recomputes every gear-dependent stat from the base_* values and the
## current equipment. Current HP is only ever clamped down to the new max
## (equipping HP gear raises the ceiling, it does not heal).
func _recompute_stats() -> void:
	var derived := StatCalculator.derive(
		{"max_hp": base_max_hp, "damage_min": base_damage_min, "damage_max": base_damage_max, "crit_chance": 0.0},
		equipment, class_def)
	max_hp = derived["max_hp"]
	attack_damage_min = derived["damage_min"]
	attack_damage_max = derived["damage_max"]
	crit_chance = derived["crit_chance"]
	armor = derived["armor"]
	hp = mini(hp, max_hp)

func _gain_gold(amount: int) -> void:
	gold += amount
	GameState.emit_signal("gold_changed", gold)
```

- [ ] **Step 5: Level-ups adjust the base, not the derived stats**

In `gain_xp`, replace:

```gdscript
		max_hp += result["hp_bonus"]
		hp += result["hp_bonus"]
		attack_damage_min += result["damage_bonus"]
		attack_damage_max += result["damage_bonus"]
```

with:

```gdscript
		base_max_hp += result["hp_bonus"]
		base_damage_min += result["damage_bonus"]
		base_damage_max += result["damage_bonus"]
		_recompute_stats()
		hp += result["hp_bonus"]
```

- [ ] **Step 6: Armor reduces damage taken**

In `take_damage`, replace the whole function body's first lines so it reads:

```gdscript
func take_damage(amount: int) -> void:
	if is_dead:
		return
	amount = StatCalculator.mitigate(amount, armor)
	hp = max(0, hp - amount)
	GameState.emit_signal("character_hp_changed", hp, max_hp)
	GameState.emit_signal("damage_dealt", global_position, amount, false)
	_gain_resource(float(class_def.get("rage_per_hit_taken", 0.0)))
	if hp <= 0:
		_die()
```

- [ ] **Step 7: Replace `_acquire_item` and `_pickup_item`**

Run this Python from the project root. It swaps the old `_pickup_item` + `_acquire_item` (everything from `func _pickup_item` up to, not including, `func _find_quest`) for the new versions:

```python
p = 'scripts/entities/character.gd'
s = open(p, newline='').read()
start = s.index('func _pickup_item(item: Node2D) -> void:')
end = s.index('func _find_quest(')
new = '''func _pickup_item(item: Node2D) -> void:
	if item.gold_amount > 0:
		_gain_gold(item.gold_amount)
	else:
		_acquire_item(item.item_id)
	item.queue_free()

## Shared by picking an item up off the ground and turning in a quest's
## item reward — both are "the character now owns this item". Consumables
## are used immediately; gear is equipped only if ItemScoring says it is an
## upgrade for this class and level, and the log says why either way.
func _acquire_item(item_id: String) -> void:
	var item_def: Dictionary = LootTable.ITEMS.get(item_id, {})
	if item_def.is_empty():
		return
	var display_name := LootTable.display_name(item_id)
	if item_def.get("type", "") == "consumable":
		var old_hp := hp
		hp = min(max_hp, hp + int(item_def.get("heal", 0)))
		var healed := hp - old_hp
		GameState.log_event("Used %s" % display_name)
		GameState.emit_signal("character_hp_changed", hp, max_hp)
		if healed > 0:
			GameState.emit_signal("damage_dealt", global_position, healed, true)
		return
	var slot: String = item_def.get("slot", "")
	if not LootTable.SLOTS.has(slot):
		push_warning("Item %s has no valid slot" % item_id)
		return
	if not ItemScoring.meets_level(item_id, level):
		GameState.log_event("Received %s - needs level %d" % [display_name, int(item_def.get("level_req", 1))])
		return
	if not ItemScoring.is_upgrade(equipment.get(slot, ""), item_id, class_def, level):
		GameState.log_event("Found %s - current gear is better" % display_name)
		return
	equipment[slot] = item_id
	_recompute_stats()
	GameState.log_event("Equipped %s (%s)" % [display_name, ItemScoring.describe_stats(item_id)])
	GameState.emit_signal("character_equipment_changed", equipment.duplicate())
	GameState.emit_signal("character_hp_changed", hp, max_hp)

'''
s = s[:start] + new + s[end:]
open(p, 'w', newline='').write(s)
```

`item.gold_amount` is added to `ItemPickup` in Task 8; the game must not run until then.

- [ ] **Step 8: Verify**

Run the import pass and the tests. Expected: `0 failures`. Then confirm no stale references to the removed names remain anywhere except the HUD script (fixed in Task 9):

```bash
grep -rn "equipped_weapon_id\|equipped_armor_id\|equipped_trinket_id\|should_equip" scripts scenes
```

Expected: matches only in `scripts/ui/unit_frame.gd`. (A live smoke run is not meaningful yet: the HUD still reads the old fields until Task 9.)

- [ ] **Step 9: Commit**

```bash
git add scripts/autoload/game_state.gd scripts/entities/character.gd
git commit -m "Migrate Character to equipment slots, base stats and armor

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Gold, pickups and "wanted item" targeting

**Files:**
- Modify: `scripts/entities/item_pickup.gd`, `scenes/entities/ItemPickup.tscn` (no scene change needed), `scripts/entities/enemy.gd`, `scripts/entities/character.gd`

- [ ] **Step 1: Gold pickups and a lifetime**

Replace `scripts/entities/item_pickup.gd` with:

```gdscript
extends Node2D

const GOLD_ICON := "res://assets/icons/gold_icon.png"
## Unclaimed drops (e.g. gear the character has no use for) vanish after this
## many seconds so they don't pile up in a zone.
const LIFETIME_S := 30.0

@export var item_id: String = "rusty_sword"
## When > 0 this pickup is a pile of gold worth that much and item_id is ignored.
@export var gold_amount: int = 0

@onready var icon: Sprite2D = $Icon

func _ready() -> void:
	add_to_group("items")
	var icon_path: String = GOLD_ICON if gold_amount > 0 else LootTable.ITEMS.get(item_id, {}).get("icon", "")
	if icon_path != "":
		icon.texture = load(icon_path)
	# A gentle bob so drops read as pickups rather than scenery.
	var tween := create_tween().set_loops()
	tween.tween_property(icon, "position:y", -3.0, 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(icon, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_SINE)
	get_tree().create_timer(LIFETIME_S).timeout.connect(queue_free)
```

- [ ] **Step 2: Enemies drop gold**

In `scripts/entities/enemy.gd`, add two exports directly under `@export var xp_reward: int = 25`:

```gdscript
@export var gold_min: int = 1
@export var gold_max: int = 3
```

Replace `_drop_loot()` with:

```gdscript
func _drop_loot() -> void:
	var item_id := guaranteed_drop_id if guaranteed_drop_id != "" else LootTable.roll_drop(rng)
	var item_scene: PackedScene = load("res://scenes/entities/ItemPickup.tscn")
	var item := item_scene.instantiate()
	item.item_id = item_id
	item.global_position = global_position
	get_tree().current_scene.add_child.call_deferred(item)
	# Elites/bosses (the ones with a guaranteed drop) pay out five times more gold.
	var gold_multiplier := 5 if guaranteed_drop_id != "" else 1
	var gold := item_scene.instantiate()
	gold.item_id = ""
	gold.gold_amount = rng.randi_range(gold_min, gold_max) * gold_multiplier
	gold.global_position = global_position + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
	get_tree().current_scene.add_child.call_deferred(gold)
```

- [ ] **Step 3: Only walk to items worth having**

In `scripts/entities/character.gd`, add these two functions directly below `_find_nearest_in_group`:

```gdscript
## True if this ground pickup is worth walking to right now: gold, a potion
## while hurt, or gear ItemScoring says would actually be equipped. Junk
## (non-upgrades, gear above the character's level) is ignored entirely.
func _wants_item(item: Node2D) -> bool:
	if item.gold_amount > 0:
		return true
	var item_def: Dictionary = LootTable.ITEMS.get(item.item_id, {})
	if item_def.get("type", "") == "consumable":
		return hp < max_hp
	var slot: String = item_def.get("slot", "")
	return ItemScoring.is_upgrade(equipment.get(slot, ""), item.item_id, class_def, level)

func _find_nearest_wanted_item() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for node in get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(node) or not _wants_item(node):
			continue
		var d := global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = node
	return nearest
```

Then replace the two lookups (each string appears exactly once):

- In `_build_context`: `var nearest_item := _find_nearest_in_group("items")` → `var nearest_item := _find_nearest_wanted_item()`
- In `_act`, the `"loot"` branch: `var item := _find_nearest_in_group("items")` → `var item := _find_nearest_wanted_item()`

```python
p = 'scripts/entities/character.gd'
s = open(p, newline='').read()
for a, b in [
    ('var nearest_item := _find_nearest_in_group("items")', 'var nearest_item := _find_nearest_wanted_item()'),
    ('var item := _find_nearest_in_group("items")', 'var item := _find_nearest_wanted_item()'),
]:
    assert s.count(a) == 1, a
    s = s.replace(a, b)
open(p, 'w', newline='').write(s)
```

- [ ] **Step 4: Verify**

Import pass, then the tests (expect `0 failures`). Then confirm both lookups were replaced and gold is wired through:

```bash
grep -n '_find_nearest_in_group("items")' scripts/entities/character.gd
grep -n "gold_amount" scripts/entities/character.gd scripts/entities/enemy.gd scripts/entities/item_pickup.gd
```

Expected: the first command prints nothing; the second prints matches in all three files.

- [ ] **Step 5: Commit**

```bash
git add scripts/entities/item_pickup.gd scripts/entities/enemy.gd scripts/entities/character.gd
git commit -m "Add gold drops, expiring pickups, and upgrade-only loot targeting

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: HUD — six slots and gold

**Files:**
- Modify: `scenes/ui/SpectatorUI.tscn`, `scripts/ui/unit_frame.gd`

- [ ] **Step 1: Replace the old equipment rows in the scene**

Run from the project root:

```python
import re
p = 'scenes/ui/SpectatorUI.tscn'
s = open(p, newline='').read()
nl = '\r\n' if '\r\n' in s else '\n'

# Remove the six old equipment nodes (WeaponIcon..TrinketLabel), which sit in one block.
start = s.index('[node name="WeaponIcon"')
end = s.index('[node name="ActivityLog"')
new_nodes = (
    '[node name="EquipRow" type="HBoxContainer" parent="UnitFrame"]' + nl +
    'offset_left = 8.0' + nl +
    'offset_top = 92.0' + nl +
    'offset_right = 208.0' + nl +
    'offset_bottom = 122.0' + nl +
    'theme_override_constants/separation = 6' + nl + nl +
    '[node name="GoldLabel" type="Label" parent="UnitFrame"]' + nl +
    'offset_left = 8.0' + nl +
    'offset_top = 126.0' + nl +
    'offset_right = 208.0' + nl +
    'offset_bottom = 148.0' + nl +
    'text = "Gold: 0"' + nl + nl
)
s = s[:start] + new_nodes + s[end:]
# Shrink the unit frame to fit.
assert 'size = Vector2(224, 174)' in s
s = s.replace('size = Vector2(224, 174)', 'size = Vector2(224, 154)')
open(p, 'w', newline='').write(s)
```

Expected: no assertion error; the scene now has `EquipRow` and `GoldLabel` and no `WeaponIcon`/`ArmorLabel`/… nodes.

- [ ] **Step 2: Rewrite the equipment part of `unit_frame.gd`**

Make these edits to `scripts/ui/unit_frame.gd`:

1. Replace the six equipment `@onready` lines (`weapon_icon`, `weapon_label`, `armor_icon`, `armor_label`, `trinket_icon`, `trinket_label`) with:

```gdscript
@onready var equip_row: HBoxContainer = $EquipRow
@onready var gold_label: Label = $GoldLabel
```

2. Replace the constant `DEFAULT_LABEL_COLOR` line with:

```gdscript
const SLOT_SIZE := 28
const EMPTY_SLOT_BORDER := Color(0.45, 0.33, 0.15, 1.0)

var slot_panels: Dictionary = {}
var slot_icons: Dictionary = {}
```

3. In `_ready()`, add `_build_slots()` as the first line after the size-fix lines (before the `GameState.…connect` lines), add `GameState.gold_changed.connect(_on_gold_changed)` next to the other connects, and replace the final `_on_equipment_changed(GameState.character.equipped_weapon_id, ...)` call with:

```gdscript
		_on_equipment_changed(GameState.character.equipment)
		_on_gold_changed(GameState.character.gold)
```

4. Replace `_on_equipment_changed` and `_update_equipment_slot` (delete both old functions) with:

```gdscript
func _build_slots() -> void:
	for slot in LootTable.SLOTS:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 2.0
		icon.offset_top = 2.0
		icon.offset_right = -2.0
		icon.offset_bottom = -2.0
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)
		equip_row.add_child(panel)
		slot_panels[slot] = panel
		slot_icons[slot] = icon

func _slot_style(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.22, 0.14, 0.08, 1.0)
	style.set_border_width_all(2)
	style.border_color = border
	style.set_corner_radius_all(4)
	return style

func _slot_tooltip(slot: String, item_id: String) -> String:
	var slot_label: String = LootTable.SLOT_LABELS.get(slot, slot)
	if item_id == "":
		return "%s: empty" % slot_label
	var item_def: Dictionary = LootTable.ITEMS.get(item_id, {})
	return "%s\n%s\n%s - level %d %s" % [
		LootTable.display_name(item_id),
		ItemScoring.describe_stats(item_id),
		slot_label,
		int(item_def.get("level_req", 1)),
		String(item_def.get("rarity", "")).capitalize(),
	]

func _on_equipment_changed(equipment: Dictionary) -> void:
	for slot in LootTable.SLOTS:
		var item_id: String = equipment.get(slot, "")
		var item_def: Dictionary = LootTable.ITEMS.get(item_id, {})
		var icon_path: String = item_def.get("icon", "")
		slot_icons[slot].texture = load(icon_path) if icon_path != "" else null
		var border: Color = LootTable.RARITY_COLORS.get(item_def.get("rarity", ""), EMPTY_SLOT_BORDER)
		slot_panels[slot].add_theme_stylebox_override("panel", _slot_style(border))
		slot_panels[slot].tooltip_text = _slot_tooltip(slot, item_id)

func _on_gold_changed(amount: int) -> void:
	gold_label.text = "Gold: %d" % amount
```

- [ ] **Step 3: Run the game and look**

Import pass (twice on a fresh worktree), then launch the project (Godot MCP `run_project`, or open in the editor and press F5). Take a screenshot (`game_screenshot`) and check:
- The unit frame shows six empty slot boxes in one row (tan borders) and "Gold: 0" beneath, with nothing overlapping the HP/XP/resource bars.
- `game_get_errors` reports no script errors.

Set the game to 4x (click the `4x` button) and watch until at least one item is equipped: its slot icon appears with a rarity-colored border, and hovering the slot shows the tooltip (use `game_get_property`/screenshot; hover with `game_mouse_move` if available).

- [ ] **Step 4: Commit**

```bash
git add scenes/ui/SpectatorUI.tscn scripts/ui/unit_frame.gd
git commit -m "Show six equipment slots with rarity borders and a gold counter

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: Live verification, balance check and docs

**Files:**
- Modify: `README.md`, possibly `scripts/systems/stat_calculator.gd` / `loot_table.gd` (balance tweaks only)

- [ ] **Step 1: Watch a long run**

Run the game at 4x for at least three minutes of real time, taking a screenshot every ~30 s. Check off each of these (record what you saw in the commit message or a note to the user):
- Gear fills several slots; log lines read `Equipped Iron Helm (+2 armor, +10 HP)`.
- No `Found X - current gear is better` lines for drops the character ignored; the character no longer walks to junk. (That line can still appear for quest-reward items.)
- Gold rises in the HUD after kills; a boss kill adds a bigger jump.
- Leveling still works and HP/XP bars update; `Level N` text updates.
- No script errors in `game_get_errors`.

- [ ] **Step 2: Balance sanity check**

The character should still occasionally take real damage (HP dropping, flee/rest states) even with armor. If, with a full set of gear, the character effectively never drops below 70% HP, lower armor's strength by changing `ARMOR_FACTOR` in `scripts/systems/stat_calculator.gd` from `4.0` to `3.0` — and update the matching expectations in `tests/suite_stat_calculator.gd` (`mitigate(10, 25)` becomes `10 * 100 / 175 = 5.71 -> 6`; expected value `6`). Re-run the tests. If no change is needed, leave both alone.

- [ ] **Step 3: README**

In `README.md`, in the "What you'll see" list, replace the bullet beginning `- **Loot and leveling**` with:

```markdown
- **Loot, gear and leveling** — enemies drop gear across six slots (weapon,
  off-hand, head, chest, neck, ring) with multiple stats each, plus gold and
  potions. The character equips only real upgrades for its class and level and
  ignores the rest; armor reduces damage taken. Kills grant XP and level-ups
  increase HP and damage.
```

and in the HUD bullet list replace `HP bar, XP bar, level, and equipped weapon/armor with icons` with `HP bar, XP bar, level, six equipment slots with rarity-colored icons and hover tooltips, and a gold counter`.

Also add to the project-layout block, under `scripts/systems/`, the description `Combat, leveling, loot, item scoring, and stat rules`, and add a line `tests/  Headless test suites (run with: godot --headless --path . --script res://tests/run_tests.gd)`.

- [ ] **Step 4: Final full test run and commit**

Run the tests (expect `0 failures`), then:

```bash
git add README.md scripts tests
git commit -m "Document gear system; tune armor if needed after live run

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Self-review notes (completed by the plan author)

- **Spec coverage:** slots/data model → Tasks 1, 4; scoring & upgrade rule → 5; level requirement → 5, 7; log lines → 7; ignore-junk targeting → 8; gold drops + HUD counter → 8, 9; armor mitigation → 6, 7; derived-stat recompute → 6, 7; HUD slots → 9; tests → 2, 4, 5, 6; docs → 1, 10. Amended in Task 1: legs/boots → offhand/neck (no icons available). Small addition beyond the spec: 30 s pickup lifetime (Task 8) so ignored drops don't accumulate.
- **Type consistency:** `ItemScoring.score/meets_level/is_upgrade/describe_stats`, `StatCalculator.gear_totals/derive/mitigate`, `LootTable.SLOTS/SLOT_LABELS/STAT_ORDER/STAT_LABELS`, `Character.equipment/gold/armor/base_*`, signals `character_equipment_changed(equipment)` and `gold_changed(amount)` are used with identical names across tasks.
- **Known intermediate state:** the game does not run between Tasks 4 and 8/9 (documented in Conventions); tests run throughout.
