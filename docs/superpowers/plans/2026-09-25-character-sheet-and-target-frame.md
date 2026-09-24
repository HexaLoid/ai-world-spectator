# Character Sheet & Target Frame Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A toggleable character sheet (stats, gear, gold, quest, session statistics) and a target frame for the enemy being fought.

**Architecture:** A pure `SheetText` class turns a snapshot dictionary into BBCode (headless-testable). `Character` gains session counters and `get_sheet_snapshot()`. Two new HUD scripts (`character_sheet.gd`, `target_frame.gd`) live in the existing `SpectatorUI` scene and use the parchment theme.

**Tech Stack:** Godot 4.7 (mono build, GDScript only), headless `--script` test runner (added in phase 1).

**Spec:** `docs/superpowers/specs/2026-09-25-character-sheet-and-target-frame-design.md`

---

## Conventions used in every task

- Work in a dedicated git worktree/branch (e.g. `character-sheet`). A fresh checkout needs **two** headless editor passes before scripts and textures resolve.
- Shell variable (bash on Windows):

```bash
GODOT="/c/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
```

- **Import pass** (registers new `class_name` scripts, writes `.gd.uid` sidecars). Run from the project root whenever a task adds a script, *before* running tests:

```bash
"$GODOT" --headless --path . --editor --quit
```

- **Run tests** (from the project root; the `timeout` guards against a hung console exe):

```bash
timeout 90 "$GODOT" --headless --path . --script res://tests/run_tests.gd
```

  Exit code 0 = all pass; failures print lines starting `FAIL:`. The runner reports a suite that fails to parse as `FAIL: suite failed to load: ...`.
- Commit `.gd.uid` sidecars next to new scripts (repo convention). Do **not** commit Godot's line-ending-only rewrites of `.import` files, the `mcp_interaction_server` autoload line in `project.godot`, or `mcp_interaction_server.gd*`.
- Commit messages end with: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`
- **Line endings:** many files here are CRLF in the working tree (git normalizes to LF in commits). Preserve each file's existing line endings when editing, and check `git diff --stat` shows only the lines you meant to change. New files may be LF.
- If an edit tool fails to match multi-line text, match on a single line without leading tabs, or use a small Python script that reads/writes with `newline=''`.
- **Live checks** use the Godot MCP tools (`mcp__godot__run_project` with `projectPath` = the worktree, then `game_screenshot`, `game_get_errors`, `get_debug_output`, `game_click`, `game_key_press`, `stop_project`). They may be deferred: load with ToolSearch `select:`. The `game_*` tools need several seconds after `run_project` to connect; retry. The window is 1152x648. `game_wait` returns immediately, so pace with repeated screenshots. Only the MCP plugin's own warnings from `mcp_interaction_server.gd` are acceptable in `game_get_errors`. Never call `game_eval`/`game_get_property` with an unknown property name (a bad name halts the game).

## File structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/ui/sheet_text.gd` | create | Pure: snapshot dictionary -> BBCode; `format_time()` |
| `tests/suite_sheet_text.gd` | create | Unit tests for `SheetText` |
| `tests/run_tests.gd` | modify | Register the new suite |
| `scripts/entities/character.gd` | modify | Session counters, `get_sheet_snapshot()` |
| `scripts/entities/enemy.gd` | modify | Count damage dealt by the spectated character |
| `scripts/ui/character_sheet.gd` | create | Sheet panel: toggle (`C` / button), refresh timer |
| `scripts/ui/target_frame.gd` | create | Target frame behavior |
| `scenes/ui/SpectatorUI.tscn` | modify | `CharacterSheet`, `TargetFrame`, `SheetButton` nodes |
| `README.md` | modify | Controls and HUD list |

---

### Task 1: `SheetText` (pure formatter) with tests

**Files:**
- Create: `scripts/ui/sheet_text.gd`, `tests/suite_sheet_text.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing suite**

`tests/suite_sheet_text.gd`:

```gdscript
extends RefCounted

func _full_snapshot() -> Dictionary:
	return {
		"level": 3, "class_name": "warrior", "zone_name": "Blackthorn Forest",
		"xp": 40, "xp_next": 100,
		"hp": 60, "max_hp": 95, "damage_min": 12, "damage_max": 16, "armor": 4,
		"crit_chance": 0.17,
		"primary_stat": "strength", "primary_value": 5.0, "primary_bonus_percent": 5.0,
		"equipment": {"weapon": "iron_sword", "head": "iron_helm"},
		"gold": 44, "quest_text": "Cull the Wolves 2/3", "quests_completed": 2,
		"kills_by_name": {"Wolf": 12, "Bandit": 3, "Dire Wolf": 3, "Crypt Lord": 1},
		"deaths": 1, "damage_dealt": 950, "damage_taken": 310, "gold_earned": 120,
		"time_played_ms": 65000.0,
	}

func run(t) -> void:
	# format_time()
	t.check_eq(SheetText.format_time(0.0), "00:00", "zero time")
	t.check_eq(SheetText.format_time(65000.0), "01:05", "65 seconds")
	t.check_eq(SheetText.format_time(3725000.0), "62:05", "hours roll into minutes")
	t.check_eq(SheetText.format_time(-500.0), "00:00", "negative time clamps to zero")

	# build() with a full snapshot
	var text := SheetText.build(_full_snapshot())
	t.check(text.contains("Level 3 Warrior"), "header has level and capitalized class")
	t.check(text.contains("Blackthorn Forest"), "header has zone")
	t.check(text.contains("XP: 40 / 100"), "xp line")
	t.check(text.contains("HP: 60 / 95"), "hp line")
	t.check(text.contains("Damage: 12 - 16"), "damage line")
	t.check(text.contains("Armor: 4"), "armor line")
	t.check(text.contains("Crit chance: 17%"), "crit line")
	t.check(text.contains("Strength: 5 (+5% damage)"), "primary stat line")
	var uncommon_hex: String = LootTable.RARITY_COLORS["uncommon"].to_html(false)
	t.check(text.contains("Weapon: [color=#%s]Iron Sword[/color] (+7 damage)" % uncommon_hex),
		"equipment line: slot, rarity-colored name, stats")
	t.check(text.contains("Head: [color=#%s]Iron Helm[/color] (+2 armor, +10 HP)" % uncommon_hex),
		"second equipment line")
	t.check(text.contains("Off-hand: [color=#%s]empty[/color]" % SheetText.EMPTY_COLOR), "empty slot is marked empty")
	t.check(text.contains("Gold: 44"), "gold line")
	t.check(text.contains("Quest: Cull the Wolves 2/3"), "quest line")
	t.check(text.contains("Quests completed: 2"), "completed quests line")
	t.check(text.contains("Kills: 19"), "total kills")
	t.check(text.contains("Wolf x12, Bandit x3, Dire Wolf x3"), "top three kills, ties broken by name")
	t.check(not text.contains("Crypt Lord"), "fourth-place kill type is not listed")
	t.check(text.contains("Deaths: 1"), "deaths line")
	t.check(text.contains("Damage dealt: 950"), "damage dealt line")
	t.check(text.contains("Damage taken: 310"), "damage taken line")
	t.check(text.contains("Gold earned: 120"), "gold earned line")
	t.check(text.contains("Time played: 01:05"), "time played line")

	# max level
	var maxed := _full_snapshot()
	maxed["xp_next"] = 0
	t.check(SheetText.build(maxed).contains("XP: MAX"), "max level shows MAX")

	# no primary stat -> no primary line
	var no_primary := _full_snapshot()
	no_primary["primary_stat"] = ""
	t.check(not SheetText.build(no_primary).contains("(+5% damage)"), "no primary stat, no primary line")

	# an empty snapshot must not error and uses defaults
	var empty_text := SheetText.build({})
	t.check(empty_text.contains("Level 1 Adventurer"), "empty snapshot: default header")
	t.check(empty_text.contains("HP: 0 / 0"), "empty snapshot: default hp")
	t.check(empty_text.contains("Kills: 0"), "empty snapshot: zero kills")
	t.check(empty_text.contains("Quest: none active"), "empty snapshot: default quest")
	t.check(empty_text.contains("Time played: 00:00"), "empty snapshot: zero time")
	for slot_label in LootTable.SLOT_LABELS.values():
		t.check(empty_text.contains("%s: [color=#%s]empty[/color]" % [slot_label, SheetText.EMPTY_COLOR]),
			"empty snapshot: %s slot is empty" % slot_label)
```

Add `"res://tests/suite_sheet_text.gd"` to `SUITES` in `tests/run_tests.gd`.

- [ ] **Step 2: Run the tests to verify they fail**

Run the import pass, then the tests. Expected: `FAIL: suite failed to load: res://tests/suite_sheet_text.gd` (parse error: `SheetText` not declared), exit 1.

- [ ] **Step 3: Implement**

`scripts/ui/sheet_text.gd`:

```gdscript
class_name SheetText
extends RefCounted

## Pure formatting for the character sheet: a snapshot dictionary (see
## Character.get_sheet_snapshot) in, a BBCode string out. Every key is
## optional so a partial or empty snapshot never errors.

const HEADER_COLOR := "d9a441"
const EMPTY_COLOR := "8a7a65"
const TOP_KILLS_SHOWN := 3

## "mm:ss"; hours roll into minutes (62:05), negatives clamp to 00:00.
static func format_time(ms: float) -> String:
	var total_seconds := int(maxf(ms, 0.0) / 1000.0)
	return "%02d:%02d" % [floori(total_seconds / 60.0), total_seconds % 60]

static func build(snap: Dictionary) -> String:
	var lines: Array[String] = []

	var class_text := String(snap.get("class_name", "")).capitalize()
	if class_text == "":
		class_text = "Adventurer"
	lines.append("[b]Level %d %s[/b] - %s" % [int(snap.get("level", 1)), class_text, String(snap.get("zone_name", "?"))])
	var xp_next := int(snap.get("xp_next", 0))
	lines.append("XP: MAX" if xp_next <= 0 else "XP: %d / %d" % [int(snap.get("xp", 0)), xp_next])
	lines.append("")

	lines.append(_header("Stats"))
	lines.append("HP: %d / %d" % [int(snap.get("hp", 0)), int(snap.get("max_hp", 0))])
	lines.append("Damage: %d - %d" % [int(snap.get("damage_min", 0)), int(snap.get("damage_max", 0))])
	lines.append("Armor: %d" % int(snap.get("armor", 0)))
	lines.append("Crit chance: %d%%" % roundi(float(snap.get("crit_chance", 0.0)) * 100.0))
	var primary := String(snap.get("primary_stat", ""))
	if primary != "":
		lines.append("%s: %d (+%d%% damage)" % [primary.capitalize(), roundi(float(snap.get("primary_value", 0.0))), roundi(float(snap.get("primary_bonus_percent", 0.0)))])
	lines.append("")

	lines.append(_header("Equipment"))
	var equipment: Dictionary = snap.get("equipment", {})
	for slot in LootTable.SLOTS:
		lines.append(_equipment_line(slot, String(equipment.get(slot, ""))))
	lines.append("")

	lines.append(_header("Progress"))
	lines.append("Gold: %d" % int(snap.get("gold", 0)))
	lines.append("Quest: %s" % String(snap.get("quest_text", "none active")))
	lines.append("Quests completed: %d" % int(snap.get("quests_completed", 0)))
	lines.append("")

	lines.append(_header("Session"))
	var kills: Dictionary = snap.get("kills_by_name", {})
	var kills_total := 0
	for enemy_name in kills:
		kills_total += int(kills[enemy_name])
	lines.append("Kills: %d" % kills_total)
	var top := _top_kills(kills)
	if not top.is_empty():
		lines.append("Top: %s" % ", ".join(top))
	lines.append("Deaths: %d" % int(snap.get("deaths", 0)))
	lines.append("Damage dealt: %d" % int(snap.get("damage_dealt", 0)))
	lines.append("Damage taken: %d" % int(snap.get("damage_taken", 0)))
	lines.append("Gold earned: %d" % int(snap.get("gold_earned", 0)))
	lines.append("Time played: %s" % format_time(float(snap.get("time_played_ms", 0.0))))

	return "\n".join(lines)

static func _header(title: String) -> String:
	return "[b][color=#%s]%s[/color][/b]" % [HEADER_COLOR, title]

static func _equipment_line(slot: String, item_id: String) -> String:
	var slot_label: String = LootTable.SLOT_LABELS.get(slot, slot)
	if item_id == "":
		return "%s: [color=#%s]empty[/color]" % [slot_label, EMPTY_COLOR]
	var rarity: String = LootTable.ITEMS.get(item_id, {}).get("rarity", "")
	var color: Color = LootTable.RARITY_COLORS.get(rarity, Color.WHITE)
	var line := "%s: [color=#%s]%s[/color]" % [slot_label, color.to_html(false), LootTable.display_name(item_id)]
	var stats := ItemScoring.describe_stats(item_id)
	if stats != "":
		line += " (%s)" % stats
	return line

## "Wolf x12" entries for the most-killed enemy types, highest first, ties
## broken alphabetically so the order is deterministic.
static func _top_kills(kills: Dictionary) -> Array[String]:
	var names: Array = kills.keys()
	names.sort_custom(func(a, b): return _kills_before(kills, a, b))
	var top: Array[String] = []
	for i in mini(names.size(), TOP_KILLS_SHOWN):
		top.append("%s x%d" % [names[i], int(kills[names[i]])])
	return top

static func _kills_before(kills: Dictionary, a, b) -> bool:
	var count_a := int(kills[a])
	var count_b := int(kills[b])
	if count_a != count_b:
		return count_a > count_b
	return String(a) < String(b)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the import pass (new class + `.gd.uid` sidecars), then the tests. Expected: `0 failures`. If a check fails because a plan expectation disagrees with the code (e.g. the sort order), verify the arithmetic/logic against the check and fix the wrong side (implementation bug vs test typo), and say which.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/sheet_text.gd scripts/ui/sheet_text.gd.uid tests/suite_sheet_text.gd tests/suite_sheet_text.gd.uid tests/run_tests.gd
git commit -m "Add SheetText: pure character sheet formatting with tests

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: Session counters and `get_sheet_snapshot()`

**Files:**
- Modify: `scripts/entities/character.gd`, `scripts/entities/enemy.gd`

The counters are simple increments at existing code paths; the game is runnable after this task (nothing consumes them yet), so verify with a short smoke run.

- [ ] **Step 1: Add the counter fields**

In `scripts/entities/character.gd`, directly under the line `var gold: int = 0`, add:

```gdscript
# Session statistics (shown on the character sheet); reset only by relaunching.
var kills_by_name: Dictionary = {}
var deaths: int = 0
var damage_dealt_total: int = 0
var damage_taken_total: int = 0
var gold_earned: int = 0
```

- [ ] **Step 2: Increment sites**

Apply these five edits to `scripts/entities/character.gd` (each old string is unique in the file; use a Python script with `newline=''` if a multi-line match fails):

1. In `take_damage`, replace
```gdscript
	amount = StatCalculator.mitigate(amount, armor)
	hp = max(0, hp - amount)
```
with
```gdscript
	amount = StatCalculator.mitigate(amount, armor)
	damage_taken_total += mini(amount, hp)
	hp = max(0, hp - amount)
```
2. In `_die`, replace `is_dead = true` (the first line of the function body, directly followed by `GameState.log_event("Character died - respawning")`) with
```gdscript
	is_dead = true
	deaths += 1
```
3. In `_gain_gold`, replace `gold += amount` with
```gdscript
	gold += amount
	gold_earned += amount
```
4. In `take_kill_credit`, replace `GameState.log_event("Defeated %s" % enemy_name)` with
```gdscript
	kills_by_name[enemy_name] = int(kills_by_name.get(enemy_name, 0)) + 1
	GameState.log_event("Defeated %s" % enemy_name)
```
5. (Snapshot, next step.)

- [ ] **Step 3: Add `get_sheet_snapshot()`**

Add this function to `scripts/entities/character.gd` directly above `func gain_xp(amount: int) -> void:`:

```gdscript
## Everything the character sheet displays, as a plain dictionary (see
## SheetText.build). `xp` is XP earned within the current level and `xp_next`
## the XP span of this level (0 at max level), matching the unit frame's bar.
func get_sheet_snapshot() -> Dictionary:
	var primary: String = class_def.get("primary_stat", "")
	var gear := StatCalculator.gear_totals(equipment)
	var primary_value := float(gear.get(primary, 0.0)) if primary != "" else 0.0
	var next_threshold := LevelingSystem.get_next_threshold(level)
	var prev_threshold: int = LevelingSystem.XP_THRESHOLDS[level - 2] if level > 1 else 0
	var quest: Dictionary = _find_quest(active_quest_id) if active_quest_id != "" else {}
	var quest_text := "none active"
	if not quest.is_empty():
		quest_text = "%s %d/%d" % [quest.get("name", ""), quest_progress, int(quest.get("count", 0))]
	return {
		"level": level,
		"class_name": character_class,
		"zone_name": String(ZoneTable.ZONES[current_zone_id]["name"]),
		"xp": xp - prev_threshold,
		"xp_next": 0 if next_threshold <= 0 else next_threshold - prev_threshold,
		"hp": hp,
		"max_hp": max_hp,
		"damage_min": attack_damage_min,
		"damage_max": attack_damage_max,
		"armor": armor,
		"crit_chance": crit_chance,
		"primary_stat": primary,
		"primary_value": primary_value,
		"primary_bonus_percent": primary_value * StatCalculator.PRIMARY_STAT_DAMAGE_PER_POINT * 100.0,
		"equipment": equipment.duplicate(),
		"gold": gold,
		"quest_text": quest_text,
		"quests_completed": completed_quest_ids.size(),
		"kills_by_name": kills_by_name.duplicate(),
		"deaths": deaths,
		"damage_dealt": damage_dealt_total,
		"damage_taken": damage_taken_total,
		"gold_earned": gold_earned,
		"time_played_ms": game_time_ms,
	}
```

- [ ] **Step 4: Count damage dealt in `Enemy.take_damage`**

In `scripts/entities/enemy.gd`, in `take_damage`, replace
```gdscript
	hp = max(0, hp - amount)
	health_bar.value = hp
```
with
```gdscript
	# Only damage that actually lands counts (no overkill), and only the
	# spectated character's own hits: auto-attacks, ability hits and bleed
	# ticks all pass the attacker through here.
	if attacker != null and attacker == GameState.character:
		attacker.damage_dealt_total += mini(amount, hp)
	hp = max(0, hp - amount)
	health_bar.value = hp
```

- [ ] **Step 5: Verify**

Run the tests (expect `0 failures`), then a smoke run and read the log for script errors:

```bash
timeout 90 "$GODOT" --headless --path . --quit-after 1200 2>&1 | grep -i "SCRIPT ERROR\|Parse Error" ; echo "grep-exit=$?"
```

Expected: no matching lines (`grep-exit=1`). Then a live check: launch the project via the Godot MCP tools, run at 4x for ~1 minute, and read the counters with `game_get_property` on the Character node for `kills_by_name`, `damage_dealt_total`, `gold_earned` and `deaths` (find the node path with `game_get_scene_tree`; the Character is a child of the world/Main scene). Expected: `damage_dealt_total > 0` and `kills_by_name` non-empty once a wolf died to the character. Stop the game afterwards.

- [ ] **Step 6: Commit**

```bash
git add scripts/entities/character.gd scripts/entities/enemy.gd
git commit -m "Track session statistics and expose a character sheet snapshot

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Character sheet panel

**Files:**
- Create: `scripts/ui/character_sheet.gd`
- Modify: `scenes/ui/SpectatorUI.tscn`

- [ ] **Step 1: Create the script**

`scripts/ui/character_sheet.gd`:

```gdscript
extends Panel

## Toggleable character sheet: press C or click the Sheet button. Polls the
## character's snapshot twice a second while visible, so it needs no signals.

const REFRESH_INTERVAL_S := 0.5
const BODY_COLOR := Color(0.93, 0.88, 0.75, 1.0)

@onready var body: RichTextLabel = $Body
@onready var sheet_button: Button = get_node("../SpeedControl/SheetButton")

var refresh_timer := Timer.new()

func _ready() -> void:
	# A dark panel (instead of the parchment theme) so the rarity colors in
	# the body text stay readable.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.09, 0.05, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.55, 0.4, 0.15, 1.0)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	body.add_theme_color_override("default_color", BODY_COLOR)
	refresh_timer.wait_time = REFRESH_INTERVAL_S
	refresh_timer.timeout.connect(_refresh)
	add_child(refresh_timer)
	sheet_button.pressed.connect(toggle)
	visibility_changed.connect(_on_visibility_changed)

func toggle() -> void:
	visible = not visible

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		toggle()
		get_viewport().set_input_as_handled()

func _on_visibility_changed() -> void:
	if visible:
		_refresh()
		refresh_timer.start()
	else:
		refresh_timer.stop()

func _refresh() -> void:
	var character = GameState.character
	if character == null:
		body.text = "No character"
		return
	body.text = SheetText.build(character.get_sheet_snapshot())
```

- [ ] **Step 2: Add the nodes to the HUD scene**

In `scenes/ui/SpectatorUI.tscn` (edit with a Python script using `newline=''` and the file's own line ending):

1. Add an `ext_resource` line after the existing ones, and bump `load_steps` in the first line by 1:
```
[ext_resource type="Script" path="res://scripts/ui/character_sheet.gd" id="8_charsheet"]
```
2. Add a `SheetButton` as the LAST child of `SpeedControl` (directly after the `RecenterButton` node block):
```
[node name="SheetButton" type="Button" parent="SpeedControl"]
text = "Sheet (C)"
```
3. Append at the very end of the file:
```
[node name="CharacterSheet" type="Panel" parent="."]
visible = false
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -364.0
offset_top = 56.0
offset_right = -16.0
offset_bottom = 516.0
grow_horizontal = 0
theme = ExtResource("4_theme")
script = ExtResource("8_charsheet")

[node name="Body" type="RichTextLabel" parent="CharacterSheet"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 12.0
offset_top = 12.0
offset_right = -12.0
offset_bottom = -12.0
bbcode_enabled = true
```

- [ ] **Step 3: Live check**

Import pass, then launch the project (MCP `run_project`). Verify with screenshots:
- Initially the sheet is hidden and the speed row now ends with a `Sheet (C)` button, not overlapping the quest tracker.
- `game_key_press` with key `C` opens the sheet on the right side; it shows all five sections (header with level/class/zone, Stats, Equipment with six rows, Progress, Session) with readable text. Press `C` again: it hides. Click the `Sheet (C)` button (find it via `read_page`/screenshot): it toggles as well.
- With the sheet open at 4x for ~30 s: Kills, Damage dealt, Gold earned and Time played change between screenshots; equipment rows show rarity-colored names once items are equipped.
- `game_get_errors`: only the MCP plugin's warnings.
Stop the game.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/character_sheet.gd scripts/ui/character_sheet.gd.uid scenes/ui/SpectatorUI.tscn
git commit -m "Add toggleable character sheet (C key / Sheet button)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Target frame

**Files:**
- Create: `scripts/ui/target_frame.gd`
- Modify: `scenes/ui/SpectatorUI.tscn`

- [ ] **Step 1: Create the script**

`scripts/ui/target_frame.gd`:

```gdscript
extends Panel

## Shows the enemy the spectated character is fighting: name (with an Elite
## tag for guaranteed-drop enemies), HP bar with numbers, and damage range.
## Driven by GameState.combat_target_changed; HP is read from the enemy each
## frame so no enemy-side changes are needed.

const BAR_SIZE := Vector2(264, 16)

@onready var name_label: Label = $NameLabel
@onready var hp_bar: ProgressBar = $HPBar
@onready var hp_text: Label = $HPText
@onready var damage_label: Label = $DamageLabel

var target: Node2D = null

func _ready() -> void:
	# Godot resets a ProgressBar's scene-declared size during its internal
	# setup — reassign it here (same workaround as the unit frame).
	hp_bar.size = BAR_SIZE
	visible = false
	GameState.combat_target_changed.connect(_on_combat_target_changed)

func _on_combat_target_changed(new_target: Node2D) -> void:
	target = new_target
	visible = target != null
	if target == null:
		return
	var elite_tag := " (Elite)" if target.guaranteed_drop_id != "" else ""
	name_label.text = "%s%s" % [target.enemy_name, elite_tag]
	damage_label.text = "%d - %d damage" % [target.attack_damage_min, target.attack_damage_max]
	_update_hp()

func _process(_delta: float) -> void:
	if target == null:
		return
	if not is_instance_valid(target):
		target = null
		visible = false
		return
	_update_hp()

func _update_hp() -> void:
	hp_bar.max_value = target.max_hp
	hp_bar.value = target.hp
	hp_text.text = "%d / %d" % [target.hp, target.max_hp]
```

- [ ] **Step 2: Add the nodes to the HUD scene**

In `scenes/ui/SpectatorUI.tscn` (Python with `newline=''`, keeping the file's line ending): add `[ext_resource type="Script" path="res://scripts/ui/target_frame.gd" id="9_targetframe"]` next to the other ext_resources (bump `load_steps` by 1 again), and append at the end of the file:

```
[node name="TargetFrame" type="Panel" parent="."]
visible = false
theme = ExtResource("4_theme")
script = ExtResource("9_targetframe")
position = Vector2(500, 104)
size = Vector2(280, 66)

[node name="NameLabel" type="Label" parent="TargetFrame"]
position = Vector2(8, 4)
text = "Enemy"

[node name="HPBar" type="ProgressBar" parent="TargetFrame"]
custom_minimum_size = Vector2(264, 16)
position = Vector2(8, 28)
size = Vector2(264, 16)
show_percentage = false

[node name="HPText" type="Label" parent="TargetFrame"]
offset_left = 8.0
offset_top = 28.0
offset_right = 272.0
offset_bottom = 44.0
theme_override_colors/font_color = Color(1, 1, 1, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 12
horizontal_alignment = 1
vertical_alignment = 1
mouse_filter = 2

[node name="DamageLabel" type="Label" parent="TargetFrame"]
position = Vector2(8, 44)
theme_override_font_sizes/font_size = 12
text = ""
```

- [ ] **Step 3: Live check**

Import pass, launch via MCP, 4x. Verify with screenshots:
- The frame is hidden when not fighting; it appears under the quest tracker (x 500-780, y 104-170) during a fight showing e.g. `Wolf`, an HP bar that drains with numbers (`12 / 18`) and `2 - 4 damage`; it hides shortly after the enemy dies. A guaranteed-drop enemy (Bandit Captain in Blackthorn Forest, Crypt Lord in the Crypt) shows `(Elite)` if the character fights one during your run (not required).
- The HP bar is 16 px tall (not inflated) and the text is centered on it; nothing overlaps the quest tracker or the ability bar.
- With the character sheet open (`C`) at the same time the two panels do not overlap.
- `game_get_errors`: only the MCP plugin's warnings. No errors when the enemy dies mid-frame (watch the debug output through a few kills).
Stop the game.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/target_frame.gd scripts/ui/target_frame.gd.uid scenes/ui/SpectatorUI.tscn
git commit -m "Add target frame showing the enemy being fought

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Final verification and docs

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README**

In the controls table add these two rows (matching the table's existing style):

```markdown
| **C** key / **Sheet (C)** button | Open or close the character sheet |
```

In the HUD bullet list add:

```markdown
  - A character sheet (stats, gear, quest, kills/deaths/damage/gold statistics)
  - A target frame showing the enemy being fought
```

Also add `sheet_text.gd, character_sheet.gd, target_frame.gd` to the `scripts/ui/` line of the project-layout block if that block lists individual UI scripts (otherwise leave the layout block alone). Preserve the file's line endings.

- [ ] **Step 2: Full run**

Run the tests (expect `0 failures`). Then a live run of ~3 minutes at 4x with the sheet open part of the time. Check off: sheet toggles by key and button; every section renders; the counters increase (kills, damage dealt, damage taken after a hit, gold earned, time played); a death (if one happens) increments Deaths; the target frame appears/hides with fights; no errors. If the class rolled is a Mage, confirm the sheet's primary stat line reads `Intellect: ...`; if Warrior, `Strength: ...` (restart up to two times to see the other class; not required).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document the character sheet and target frame

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Self-review notes (completed by the plan author)

- **Spec coverage:** sheet contents and snapshot keys -> Tasks 1, 2; toggle by `C` and button -> Task 3; refresh timer -> Task 3; counters and increment sites (kills, deaths, gold earned, damage taken after armor, damage dealt in `Enemy.take_damage` without overkill) -> Task 2; target frame with Elite tag/HP numbers/damage range and the ProgressBar size workaround -> Task 4; error handling (defaults, null character, freed enemy) -> Tasks 1, 3, 4; README -> Task 5; unit tests -> Task 1.
- **Interface consistency:** snapshot keys are identical in `SheetText.build`, its tests and `Character.get_sheet_snapshot`. `xp`/`xp_next` mean "XP into the current level"/"span of this level", matching the unit frame. `SheetText.EMPTY_COLOR` is used by both code and tests.
- **Spec note:** the spec says the snapshot's `xp` is shown as `XP 40 / 100`; the implementation shows `XP: 40 / 100` (colon, consistent with the other lines).
