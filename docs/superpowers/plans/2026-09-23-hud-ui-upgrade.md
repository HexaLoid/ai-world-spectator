# HUD/UI Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unstyled default-Godot spectator HUD with a themed fantasy/parchment UI, add equipment icons, floating damage numbers, a current-target enemy health bar, and a floating action-state label above the character — plus fold in two small AI-behavior fixes (a wander/flee movement boundary, and a log line for rejected loot).

**Architecture:** A procedural Godot `Theme` resource (no new panel/button texture art) restyles the existing `UnitFrame`/`ActivityLog`/`SpeedControl` controls. Two new `GameState` signals (`damage_dealt`, `combat_target_changed`) keep gameplay code emitting-only and UI listening-only, matching the decoupling rule already established in this project. Equipment icons are sourced pixel-art (Kyrise's Free 16x16 RPG Icon Pack, CC-BY 4.0), already downloaded and committed to `assets/icons/`.

**Tech Stack:** Godot 4.7 (mono/C#), GDScript, hand-authored `.tscn`/`.tres` text resources.

---

## Conventions (read first)

- **Hand-edit scenes via `write_file`, not `save_scene`/`add_node` MCP tools.** Every `.tscn` this plan touches has a root (or will gain a root) whose script references the `GameState` autoload; this project has consistently found the Godot MCP server's scene-mutation tools unreliable on such scenes. Read the current file in full, then write the complete new content.
- **Fresh worktree needs an import pass.** If executing this plan in a new worktree, run a headless editor pass *twice* before the first `game_eval`/`run_project` call — the first pass builds `.godot/global_script_class_cache.cfg` but does not reliably trigger the asset import scan; a second identical pass does:
  ```
  & "C:\Users\n1njaz\Desktop\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe" --headless --path . --editor --quit-after 300
  ```
  (run via PowerShell, not Bash). Confirm `.godot/imported/` is non-empty before proceeding; if still empty after two passes, run it a third time.
- **`project.godot` drift:** running the Godot editor/game via MCP tooling repeatedly adds blank lines under `[autoload]`. Always `git checkout -- project.godot` before committing if that's the only change to it.
- **`.import` sidecar line-ending noise:** after an editor pass, `git status` may show existing `.import` files as modified with zero real diff (just LF→CRLF normalization). Verify with `git diff <file>` (empty output = just the warning, no real change) and discard with `git checkout --` before committing.
- **Keep `game_eval` scripts short-lived.** A bad property access (e.g. a typo'd node/property name) can trip a debugger breakpoint that hangs every subsequent `game_eval`/`game_screenshot` call until the project is stopped and restarted. Double-check property/node names against the actual file before using them, and keep any in-script `await` loop to a few seconds.
- Every task's verification step assumes `game_get_errors` stays clean of anything beyond this known, pre-existing background noise: `mcp_interaction_server.gd` shadowing/enum warnings, unused `GameState` signal warnings (until a task's new signal starts being used, after which its "unused" warning should disappear), unused `context`/`delta` parameter warnings in `character.gd`/`camera_controller.gd`.

---

### Task 1: Build the spectator theme and restyle the HUD

**Files:**
- Create: `assets/theme/spectator_theme.tres`
- Modify: `scenes/ui/SpectatorUI.tscn`
- Modify: `scripts/systems/loot_table.gd`
- Modify: `scripts/ui/unit_frame.gd`

- [ ] **Step 1: Create the theme resource**

Create `assets/theme/spectator_theme.tres` with exactly this content:

```
[gd_resource type="Theme" load_steps=7 format=3]

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_panel"]
bg_color = Color(0.82, 0.72, 0.55, 0.92)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.55, 0.4, 0.15, 1)
corner_radius_top_left = 6
corner_radius_top_right = 6
corner_radius_bottom_right = 6
corner_radius_bottom_left = 6

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_bar_bg"]
bg_color = Color(0.22, 0.14, 0.08, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_hp_fill"]
bg_color = Color(0.75, 0.15, 0.15, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_button_normal"]
bg_color = Color(0.55, 0.42, 0.25, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.55, 0.4, 0.15, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_button_hover"]
bg_color = Color(0.63, 0.49, 0.3, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.7, 0.55, 0.2, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_button_pressed"]
bg_color = Color(0.42, 0.32, 0.18, 1)
border_width_left = 2
border_width_top = 2
border_width_right = 2
border_width_bottom = 2
border_color = Color(0.55, 0.4, 0.15, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[resource]
default_font_size = 14
Panel/styles/panel = SubResource("StyleBoxFlat_panel")
Label/colors/font_color = Color(0.2, 0.12, 0.05, 1)
Button/styles/normal = SubResource("StyleBoxFlat_button_normal")
Button/styles/hover = SubResource("StyleBoxFlat_button_hover")
Button/styles/pressed = SubResource("StyleBoxFlat_button_pressed")
Button/colors/font_color = Color(0.95, 0.9, 0.75, 1)
Button/colors/font_hover_color = Color(1, 0.95, 0.8, 1)
Button/colors/font_pressed_color = Color(0.85, 0.8, 0.65, 1)
ProgressBar/styles/background = SubResource("StyleBoxFlat_bar_bg")
ProgressBar/styles/fill = SubResource("StyleBoxFlat_hp_fill")
ItemList/styles/panel = SubResource("StyleBoxFlat_panel")
ItemList/colors/font_color = Color(0.2, 0.12, 0.05, 1)
HBoxContainer/constants/separation = 6
```

- [ ] **Step 2: Add icon paths to the loot table**

Read `scripts/systems/loot_table.gd` in full to confirm current content, then replace the `ITEMS` block:

Find:
```gdscript
const ITEMS := {
	"rusty_sword": {"type": "weapon", "damage": 4},
	"iron_sword": {"type": "weapon", "damage": 7},
	"leather_armor": {"type": "armor", "max_hp": 15},
	"health_potion": {"type": "consumable", "heal": 20},
}
```

Replace with:
```gdscript
const ITEMS := {
	"rusty_sword": {"type": "weapon", "damage": 4, "icon": "res://assets/icons/sword_rusty_icon.png"},
	"iron_sword": {"type": "weapon", "damage": 7, "icon": "res://assets/icons/sword_iron_icon.png"},
	"leather_armor": {"type": "armor", "max_hp": 15, "icon": "res://assets/icons/armor_icon.png"},
	"health_potion": {"type": "consumable", "heal": 20, "icon": "res://assets/icons/potion_icon.png"},
}
```

- [ ] **Step 3: Rewrite SpectatorUI.tscn with the theme, panels, and icon slots**

Read `scenes/ui/SpectatorUI.tscn` in full first to confirm it matches the expected current content (no other session has changed it). Replace the entire file content with:

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/ui/unit_frame.gd" id="1_unitframe"]
[ext_resource type="Script" path="res://scripts/ui/activity_log.gd" id="2_activitylog"]
[ext_resource type="Script" path="res://scripts/ui/speed_control.gd" id="3_speedcontrol"]
[ext_resource type="Theme" path="res://assets/theme/spectator_theme.tres" id="4_theme"]

[sub_resource type="StyleBoxFlat" id="StyleBoxFlat_xpfill"]
bg_color = Color(0.82, 0.65, 0.15, 1)
corner_radius_top_left = 4
corner_radius_top_right = 4
corner_radius_bottom_right = 4
corner_radius_bottom_left = 4

[node name="SpectatorUI" type="CanvasLayer"]

[node name="UnitFrame" type="Panel" parent="."]
script = ExtResource("1_unitframe")
theme = ExtResource("4_theme")
position = Vector2(16, 16)
size = Vector2(224, 132)

[node name="HPBar" type="ProgressBar" parent="UnitFrame"]
position = Vector2(8, 8)
size = Vector2(200, 20)
show_percentage = false

[node name="LevelLabel" type="Label" parent="UnitFrame"]
position = Vector2(8, 32)
text = "Level 1"

[node name="XPBar" type="ProgressBar" parent="UnitFrame"]
position = Vector2(8, 56)
size = Vector2(200, 12)
show_percentage = false
theme_override_styles/fill = SubResource("StyleBoxFlat_xpfill")

[node name="WeaponIcon" type="TextureRect" parent="UnitFrame"]
position = Vector2(8, 72)
size = Vector2(20, 20)
expand_mode = 1
stretch_mode = 5

[node name="WeaponLabel" type="Label" parent="UnitFrame"]
position = Vector2(34, 76)
text = "Weapon: None"

[node name="ArmorIcon" type="TextureRect" parent="UnitFrame"]
position = Vector2(8, 96)
size = Vector2(20, 20)
expand_mode = 1
stretch_mode = 5

[node name="ArmorLabel" type="Label" parent="UnitFrame"]
position = Vector2(34, 100)
text = "Armor: None"

[node name="ActivityLog" type="Panel" parent="."]
script = ExtResource("2_activitylog")
theme = ExtResource("4_theme")
position = Vector2(16, 400)
size = Vector2(320, 160)

[node name="LogList" type="ItemList" parent="ActivityLog"]
position = Vector2(4, 4)
size = Vector2(312, 152)

[node name="SpeedControl" type="HBoxContainer" parent="."]
script = ExtResource("3_speedcontrol")
theme = ExtResource("4_theme")
position = Vector2(500, 16)

[node name="PauseButton" type="Button" parent="SpeedControl"]
text = "Pause"

[node name="Speed1Button" type="Button" parent="SpeedControl"]
text = "1x"

[node name="Speed2Button" type="Button" parent="SpeedControl"]
text = "2x"

[node name="Speed4Button" type="Button" parent="SpeedControl"]
text = "4x"

[node name="RecenterButton" type="Button" parent="SpeedControl"]
text = "Recenter"
```

Note: `UnitFrame`/`ActivityLog` change from `type="Control"` to `type="Panel"` so they render the theme's `Panel/styles/panel` background automatically. Their scripts (`unit_frame.gd`, `activity_log.gd`) still say `extends Control` — leave that as-is, it's unchanged and still valid, since `Panel` is a `Control` and a script may extend any ancestor of the node's actual type.

- [ ] **Step 4: Wire icons into unit_frame.gd**

Read `scripts/ui/unit_frame.gd` in full to confirm current content, then replace the whole file with:

```gdscript
extends Control

@onready var hp_bar: ProgressBar = $HPBar
@onready var level_label: Label = $LevelLabel
@onready var xp_bar: ProgressBar = $XPBar
@onready var weapon_icon: TextureRect = $WeaponIcon
@onready var weapon_label: Label = $WeaponLabel
@onready var armor_icon: TextureRect = $ArmorIcon
@onready var armor_label: Label = $ArmorLabel

func _ready() -> void:
	GameState.character_hp_changed.connect(_on_hp_changed)
	GameState.character_xp_changed.connect(_on_xp_changed)
	GameState.character_leveled_up.connect(_on_leveled_up)
	GameState.character_equipment_changed.connect(_on_equipment_changed)
	if GameState.character:
		_on_hp_changed(GameState.character.hp, GameState.character.max_hp)
		_on_leveled_up(GameState.character.level)
		_on_xp_changed(GameState.character.xp)
		_on_equipment_changed(GameState.character.equipped_weapon_id, GameState.character.equipped_armor_id)

func _on_hp_changed(hp: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp

func _on_xp_changed(xp: int) -> void:
	var next_threshold: int = LevelingSystem.get_next_threshold(GameState.character.level) if GameState.character else -1
	if next_threshold <= 0:
		next_threshold = LevelingSystem.XP_THRESHOLDS[-1]
	xp_bar.max_value = next_threshold
	xp_bar.value = xp

func _on_leveled_up(level: int) -> void:
	level_label.text = "Level %d" % level

func _on_equipment_changed(weapon_id: String, armor_id: String) -> void:
	weapon_label.text = "Weapon: %s" % (weapon_id if weapon_id != "" else "None")
	weapon_icon.texture = load(LootTable.ITEMS[weapon_id]["icon"]) if weapon_id != "" else null
	armor_label.text = "Armor: %s" % (armor_id if armor_id != "" else "None")
	armor_icon.texture = load(LootTable.ITEMS[armor_id]["icon"]) if armor_id != "" else null
```

(Only change from the current file: the four new `@onready` icon-related lines and the two new `weapon_icon.texture`/`armor_icon.texture` lines in `_on_equipment_changed`. Everything else is unchanged — `extends Control` stays as-is, see Step 3's note.)

- [ ] **Step 5: Verify**

Run `mcp__godot__run_project` with projectPath `C:\Users\n1njaz\Desktop\New folder\.claude\worktrees\hud-ui-upgrade` (adjust path if this plan is executed in a different worktree). Run `game_get_errors` — expect clean (known noise only, no "Invalid theme property" or resource-load errors). Take a `mcp__godot__game_screenshot` and confirm: the unit frame and activity log now show a parchment-tan panel background with a gold border instead of default grey; the speed control buttons are themed (tan/gold, not default grey); the HP bar fill is dark red and the XP bar fill is gold (visibly different colors from each other).

Then confirm icons load: run `game_eval`:
```gdscript
return {
	"weapon_icon_tex": GameState.character.get_node("/root/Main/UI/UnitFrame").weapon_icon.texture != null,
	"armor_icon_tex": GameState.character.get_node("/root/Main/UI/UnitFrame").armor_icon.texture != null
}
```
Expected: both `true` once the character has picked up a weapon/armor (if both are still `false` because nothing has dropped yet, wait ~20-30 real seconds and retry, or force a pickup: `GameState.character._pickup_item(...)` is not directly callable with a fake item easily, so prefer waiting for a natural drop — this project's loot table drops uniformly at random on every kill, so a short wait is reliable). Take a screenshot once at least one icon is visible and visually confirm it renders as a small pixel-art icon next to the corresponding label, not a blank/broken texture box.

Run `stop_project`.

- [ ] **Step 6: Commit**

Clean up `project.godot` drift first (see Conventions).

```bash
git add assets/theme/spectator_theme.tres scenes/ui/SpectatorUI.tscn scripts/systems/loot_table.gd scripts/ui/unit_frame.gd
git commit -m "$(cat <<'EOF'
Restyle the spectator HUD with a fantasy theme and equipment icons

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Floating damage numbers

**Files:**
- Create: `scenes/ui/FloatingText.tscn`
- Create: `scripts/ui/floating_text.gd`
- Create: `scripts/main.gd`
- Modify: `scenes/Main.tscn`
- Modify: `scripts/autoload/game_state.gd`
- Modify: `scripts/entities/character.gd`
- Modify: `scripts/entities/enemy.gd`

- [ ] **Step 1: Add the damage_dealt signal**

Read `scripts/autoload/game_state.gd` in full to confirm current content. Find:

```gdscript
## Emitted for every logged activity event; message is the human-readable
## text describing what happened, for the spectator UI's activity feed.
signal activity_logged(message: String)

var character: Node2D = null
```

Replace with:

```gdscript
## Emitted for every logged activity event; message is the human-readable
## text describing what happened, for the spectator UI's activity feed.
signal activity_logged(message: String)
## Emitted whenever damage is dealt or healing is applied, so the UI can
## spawn a floating number at the location; position is the world position
## to spawn it at, amount is the value (always positive), is_heal
## distinguishes healing (green) from damage (red).
signal damage_dealt(position: Vector2, amount: int, is_heal: bool)

var character: Node2D = null
```

- [ ] **Step 2: Build the FloatingText scene and script**

Create `scripts/ui/floating_text.gd`:

```gdscript
extends Node2D

var amount: int = 0
var is_heal: bool = false

@onready var label: Label = $Label

func _ready() -> void:
	label.text = ("+%d" % amount) if is_heal else ("-%d" % amount)
	label.modulate = Color(0.3, 0.9, 0.3, 1.0) if is_heal else Color(0.95, 0.25, 0.2, 1.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 24.0, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.finished.connect(queue_free)
```

Create `scenes/ui/FloatingText.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/floating_text.gd" id="1_floattext"]

[node name="FloatingText" type="Node2D"]
script = ExtResource("1_floattext")

[node name="Label" type="Label" parent="."]
offset_left = -30.0
offset_top = -20.0
offset_right = 30.0
offset_bottom = 4.0
horizontal_alignment = 1
```

(`amount`/`is_heal` are set on the instance by the spawner *before* it's added to the tree — see Step 3 — so `_ready()` can read them the moment `@onready` resolves, with no separate `setup()` call needed after insertion.)

- [ ] **Step 3: Build the spawner listener on Main**

Create `scripts/main.gd`:

```gdscript
extends Node2D

const FLOATING_TEXT_SCENE: PackedScene = preload("res://scenes/ui/FloatingText.tscn")

func _ready() -> void:
	GameState.damage_dealt.connect(_on_damage_dealt)

func _on_damage_dealt(damage_position: Vector2, amount: int, is_heal: bool) -> void:
	var floating_text := FLOATING_TEXT_SCENE.instantiate()
	floating_text.global_position = damage_position
	floating_text.amount = amount
	floating_text.is_heal = is_heal
	add_child.call_deferred(floating_text)
```

Read `scenes/Main.tscn` in full to confirm current content, then replace the whole file with:

```
[gd_scene load_steps=6 format=3]

[ext_resource type="PackedScene" path="res://scenes/entities/Character.tscn" id="1_character"]
[ext_resource type="PackedScene" path="res://scenes/world/ThornfieldMeadow.tscn" id="2_world"]
[ext_resource type="Script" path="res://scripts/ui/camera_controller.gd" id="3_camera"]
[ext_resource type="PackedScene" path="res://scenes/ui/SpectatorUI.tscn" id="4_ui"]
[ext_resource type="Script" path="res://scripts/main.gd" id="5_main"]

[node name="Main" type="Node2D"]
script = ExtResource("5_main")

[node name="World" parent="." instance=ExtResource("2_world")]

[node name="Character" parent="." instance=ExtResource("1_character")]

[node name="Camera2D" type="Camera2D" parent="."]
script = ExtResource("3_camera")
enabled = true

[node name="UI" parent="." instance=ExtResource("4_ui")]
```

- [ ] **Step 4: Emit damage_dealt from character.gd**

Read `scripts/entities/character.gd` in full to confirm current content (it was last touched by the combat-facing fix). Find:

```gdscript
func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp = max(0, hp - amount)
	GameState.emit_signal("character_hp_changed", hp, max_hp)
	if hp <= 0:
		_die()
```

Replace with:

```gdscript
func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp = max(0, hp - amount)
	GameState.emit_signal("character_hp_changed", hp, max_hp)
	GameState.emit_signal("damage_dealt", global_position, amount, false)
	if hp <= 0:
		_die()
```

Find:

```gdscript
	if item_type == "consumable":
		hp = min(max_hp, hp + int(item_def.get("heal", 0)))
		GameState.log_event("Used %s" % item_id)
		GameState.emit_signal("character_hp_changed", hp, max_hp)
```

Replace with:

```gdscript
	if item_type == "consumable":
		var old_hp := hp
		hp = min(max_hp, hp + int(item_def.get("heal", 0)))
		var healed := hp - old_hp
		GameState.log_event("Used %s" % item_id)
		GameState.emit_signal("character_hp_changed", hp, max_hp)
		if healed > 0:
			GameState.emit_signal("damage_dealt", global_position, healed, true)
```

(The `if healed > 0` guard skips spawning a "+0" floating number when a potion is used at full HP.)

- [ ] **Step 5: Emit damage_dealt from enemy.gd**

Read `scripts/entities/enemy.gd` in full to confirm current content. Find:

```gdscript
func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp = max(0, hp - amount)
	if hp <= 0:
		_die()
```

Replace with:

```gdscript
func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp = max(0, hp - amount)
	GameState.emit_signal("damage_dealt", global_position, amount, false)
	if hp <= 0:
		_die()
```

- [ ] **Step 6: Verify**

Run `mcp__godot__run_project`. Run `game_get_errors` — clean (known noise only). Let the game play naturally for 20-30 real seconds so combat occurs, then take a `mcp__godot__game_screenshot` timed during an active fight and confirm a red "-N" floating number is visible near the character or an enemy. Force a heal to check the green case:

```gdscript
GameState.character.hp = max(1, GameState.character.max_hp - 15)
var old_hp = GameState.character.hp
GameState.character.hp = min(GameState.character.max_hp, GameState.character.hp + 15)
GameState.emit_signal("damage_dealt", GameState.character.global_position, GameState.character.hp - old_hp, true)
return "done"
```
Take a screenshot immediately after and confirm a green "+15" appears and rises/fades over about half a second (poll a screenshot again ~0.5-1s later and confirm it's gone). Run `stop_project`.

- [ ] **Step 7: Commit**

Clean up `project.godot` drift first.

```bash
git add scenes/ui/FloatingText.tscn scripts/ui/floating_text.gd scripts/main.gd scenes/Main.tscn scripts/autoload/game_state.gd scripts/entities/character.gd scripts/entities/enemy.gd
git commit -m "$(cat <<'EOF'
Add floating damage/heal numbers on hits and potion use

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Enemy health bar over the current combat target

**Files:**
- Create: `scripts/ui/enemy_health_bar.gd`
- Modify: `scenes/entities/Enemy.tscn`
- Modify: `scripts/autoload/game_state.gd`
- Modify: `scripts/entities/character.gd`
- Modify: `scripts/entities/enemy.gd`

- [ ] **Step 1: Add the combat_target_changed signal**

Read `scripts/autoload/game_state.gd` in full (it now has `damage_dealt` from Task 2). Find:

```gdscript
signal damage_dealt(position: Vector2, amount: int, is_heal: bool)

var character: Node2D = null
```

Replace with:

```gdscript
signal damage_dealt(position: Vector2, amount: int, is_heal: bool)
## Emitted whenever the character's current combat target changes (or
## becomes/stops being null); target is the Enemy node being fought, or
## null if not currently in combat. Enemy health bars listen to this to
## decide whether to show themselves.
signal combat_target_changed(target: Node2D)

var character: Node2D = null
```

- [ ] **Step 2: Build the enemy health bar script**

Create `scripts/ui/enemy_health_bar.gd`:

```gdscript
extends ProgressBar

func _ready() -> void:
	visible = false
	GameState.combat_target_changed.connect(_on_combat_target_changed)

func _on_combat_target_changed(target: Node2D) -> void:
	visible = target == get_parent()
```

- [ ] **Step 3: Add the health bar node to Enemy.tscn**

Read `scenes/entities/Enemy.tscn` in full to confirm current content. Replace the whole file with:

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/entities/enemy.gd" id="1_enscr"]
[ext_resource type="SpriteFrames" path="res://assets/sprites/wolf/wolf_frames.tres" id="2_frames"]
[ext_resource type="Script" path="res://scripts/ui/enemy_health_bar.gd" id="3_healthbar"]

[node name="Enemy" type="CharacterBody2D"]
script = ExtResource("1_enscr")

[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]
sprite_frames = ExtResource("2_frames")
animation = &"idle_right"

[node name="EnemyHealthBar" type="ProgressBar" parent="."]
script = ExtResource("3_healthbar")
position = Vector2(-16, -30)
size = Vector2(32, 6)
show_percentage = false
visible = false
```

- [ ] **Step 4: Sync the health bar's value from enemy.gd**

Read `scripts/entities/enemy.gd` in full (it now has the `damage_dealt` emit from Task 2). Find:

```gdscript
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var attack_anim_until_ms: float = 0.0

func _ready() -> void:
	hp = max_hp
	rng.randomize()
	add_to_group("enemies")
```

Replace with:

```gdscript
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: ProgressBar = $EnemyHealthBar
var attack_anim_until_ms: float = 0.0

func _ready() -> void:
	hp = max_hp
	rng.randomize()
	add_to_group("enemies")
	health_bar.max_value = max_hp
	health_bar.value = hp
```

Find:

```gdscript
func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp = max(0, hp - amount)
	GameState.emit_signal("damage_dealt", global_position, amount, false)
	if hp <= 0:
		_die()
```

Replace with:

```gdscript
func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp = max(0, hp - amount)
	health_bar.value = hp
	GameState.emit_signal("damage_dealt", global_position, amount, false)
	if hp <= 0:
		_die()
```

- [ ] **Step 5: Emit combat_target_changed from character.gd**

Read `scripts/entities/character.gd` in full (it now has the Task 2 edits). Find:

```gdscript
var is_dead: bool = false
var game_time_ms: float = 0.0
var hp_regen_accumulator: float = 0.0
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var attack_anim_until_ms: float = 0.0
```

Replace with:

```gdscript
var is_dead: bool = false
var game_time_ms: float = 0.0
var hp_regen_accumulator: float = 0.0
var last_combat_target: Node2D = null
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var attack_anim_until_ms: float = 0.0
```

Find:

```gdscript
	var facing := _facing_from_velocity(velocity)
	if combat_hostile:
		facing = _facing_from_velocity(combat_hostile.global_position - global_position)
	if game_time_ms < attack_anim_until_ms:
		base_anim = "slash"
	_play_animation(base_anim, facing)
```

Replace with:

```gdscript
	var facing := _facing_from_velocity(velocity)
	if combat_hostile:
		facing = _facing_from_velocity(combat_hostile.global_position - global_position)
	if combat_hostile != last_combat_target:
		last_combat_target = combat_hostile
		GameState.emit_signal("combat_target_changed", combat_hostile)
	if game_time_ms < attack_anim_until_ms:
		base_anim = "slash"
	_play_animation(base_anim, facing)
```

- [ ] **Step 6: Verify**

Run `mcp__godot__run_project`. Run `game_get_errors` — clean. Let combat occur naturally, then poll for the current combat target and confirm its health bar is visible and only its bar is visible:

```gdscript
var enemies = get_tree().get_nodes_in_group("enemies")
var result = []
for e in enemies:
	result.append({"name": e.enemy_name, "hp": e.hp, "bar_visible": e.health_bar.visible, "bar_value": e.health_bar.value})
return result
```

Expected: at most one entry has `bar_visible: true` at any given moment (whichever enemy is currently being fought — it's fine if none are visible between fights), and that entry's `bar_value` matches its `hp`. Take a screenshot during an active fight and visually confirm a small health bar over the targeted enemy's sprite, and confirm via a second screenshot moments after that enemy is defeated or the character disengages that no bar is left floating over empty space. Run `stop_project`.

- [ ] **Step 7: Commit**

Clean up `project.godot` drift first.

```bash
git add scripts/ui/enemy_health_bar.gd scenes/entities/Enemy.tscn scripts/autoload/game_state.gd scripts/entities/character.gd scripts/entities/enemy.gd
git commit -m "$(cat <<'EOF'
Show a health bar over the character's current combat target

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Current-action indicator above the character

**Files:**
- Modify: `scenes/entities/Character.tscn`
- Modify: `scripts/entities/character.gd`

- [ ] **Step 1: Add the ActionLabel node**

Read `scenes/entities/Character.tscn` in full to confirm current content. Replace the whole file with:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/entities/character.gd" id="1_chscr"]
[ext_resource type="SpriteFrames" path="res://assets/sprites/character/character_frames.tres" id="2_frames"]

[node name="root" type="CharacterBody2D"]
script = ExtResource("1_chscr")

[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]
sprite_frames = ExtResource("2_frames")
animation = &"idle_down"

[node name="ActionLabel" type="Label" parent="."]
offset_left = -40.0
offset_top = -52.0
offset_right = 40.0
offset_bottom = -36.0
horizontal_alignment = 1
text = "Wandering"
```

- [ ] **Step 2: Wire state-to-text updates in character.gd**

Read `scripts/entities/character.gd` in full (it now has the Task 3 edits). Find:

```gdscript
const TARGET_SPRITE_SIZE := 40.0
const ATTACK_ANIM_DURATION_MS := 400.0

@export var max_hp: int = 60
```

Replace with:

```gdscript
const TARGET_SPRITE_SIZE := 40.0
const ATTACK_ANIM_DURATION_MS := 400.0

const STATE_DISPLAY_NAMES := {
	"wander": "Wandering",
	"chase": "Chasing",
	"combat": "Fighting",
	"flee": "Fleeing",
	"loot": "Looting",
	"rest": "Resting",
}

@export var max_hp: int = 60
```

Find:

```gdscript
var last_combat_target: Node2D = null
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var attack_anim_until_ms: float = 0.0
```

Replace with:

```gdscript
var last_combat_target: Node2D = null
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var action_label: Label = $ActionLabel
var attack_anim_until_ms: float = 0.0
```

Find:

```gdscript
	if new_state != current_state:
		current_state = new_state
		GameState.log_event(decision["reason"])
		GameState.emit_signal("character_state_changed", current_state)
	_act(delta, context)
```

Replace with:

```gdscript
	if new_state != current_state:
		current_state = new_state
		GameState.log_event(decision["reason"])
		GameState.emit_signal("character_state_changed", current_state)
		action_label.text = STATE_DISPLAY_NAMES.get(current_state, current_state.capitalize())
	_act(delta, context)
```

- [ ] **Step 3: Verify**

Run `mcp__godot__run_project`. Run `game_get_errors` — clean. Poll the character's state and label text together a few times over ~20-30 real seconds (short individual `game_eval` calls, not one long in-script loop):

```gdscript
return {"state": GameState.character.current_state, "label": GameState.character.action_label.text}
```

Expected: `label` always matches `STATE_DISPLAY_NAMES[state]` (e.g. `state: "chase"` pairs with `label: "Chasing"`), and it changes as the character cycles through wander/chase/combat/flee/loot/rest. Take a screenshot and visually confirm the label is legible, positioned above the character's head, and doesn't overlap the sprite. Run `stop_project`.

- [ ] **Step 4: Commit**

Clean up `project.godot` drift first.

```bash
git add scenes/entities/Character.tscn scripts/entities/character.gd
git commit -m "$(cat <<'EOF'
Show the character's current AI action as a floating label

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Wander/flee movement boundary

**Files:**
- Modify: `scripts/entities/character.gd`

- [ ] **Step 1: Add meadow bound consts**

Read `scripts/entities/character.gd` in full (it now has the Task 4 edits). Find:

```gdscript
const TARGET_SPRITE_SIZE := 40.0
const ATTACK_ANIM_DURATION_MS := 400.0

const STATE_DISPLAY_NAMES := {
```

Replace with:

```gdscript
const TARGET_SPRITE_SIZE := 40.0
const ATTACK_ANIM_DURATION_MS := 400.0
const MEADOW_MIN := Vector2(-380, -280)
const MEADOW_MAX := Vector2(380, 280)

const STATE_DISPLAY_NAMES := {
```

- [ ] **Step 2: Clamp wander_target generation**

Find:

```gdscript
		"wander":
			if global_position.distance_to(wander_target) < 8.0:
				wander_target = global_position + Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
			velocity = (wander_target - global_position).normalized() * MOVE_SPEED * 0.5
			move_and_slide()
			base_anim = "walk"
```

Replace with:

```gdscript
		"wander":
			if global_position.distance_to(wander_target) < 8.0:
				wander_target = global_position + Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
				wander_target = wander_target.clamp(MEADOW_MIN, MEADOW_MAX)
			velocity = (wander_target - global_position).normalized() * MOVE_SPEED * 0.5
			move_and_slide()
			base_anim = "walk"
```

- [ ] **Step 3: Clamp actual position as a backstop (covers flee too)**

Find:

```gdscript
	if combat_hostile != last_combat_target:
		last_combat_target = combat_hostile
		GameState.emit_signal("combat_target_changed", combat_hostile)
	if game_time_ms < attack_anim_until_ms:
		base_anim = "slash"
	_play_animation(base_anim, facing)
```

Replace with:

```gdscript
	if combat_hostile != last_combat_target:
		last_combat_target = combat_hostile
		GameState.emit_signal("combat_target_changed", combat_hostile)
	if game_time_ms < attack_anim_until_ms:
		base_anim = "slash"
	_play_animation(base_anim, facing)
	global_position = global_position.clamp(MEADOW_MIN, MEADOW_MAX)
```

- [ ] **Step 4: Verify**

Run `mcp__godot__run_project`. Run `game_get_errors` — clean. Set `Engine.time_scale` to 4.0 (matching the fast-forward speed control already in this game) and let the character wander/flee for at least 60 real seconds (poll every ~10s with short individual `game_eval` calls, not one long loop), tracking the furthest `global_position` seen:

```gdscript
var pos = GameState.character.global_position
return {"x": pos.x, "y": pos.y}
```

Expected: every reading has `x` between -380 and 380 and `y` between -280 and 280. Reset `Engine.time_scale = 1.0` when done. Take a screenshot and visually confirm the character stays within the tree-lined meadow. Run `stop_project`.

- [ ] **Step 5: Commit**

Clean up `project.godot` drift first.

```bash
git add scripts/entities/character.gd
git commit -m "$(cat <<'EOF'
Keep wander/flee movement within the meadow's visible area

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Log rejected loot

**Files:**
- Modify: `scripts/entities/character.gd`

- [ ] **Step 1: Log when a worse weapon/armor is found**

Read `scripts/entities/character.gd` in full (it now has the Task 5 edits). Find:

```gdscript
	elif item_type == "weapon":
		if LootTable.should_equip(equipped_weapon_id, item_id):
			var old_bonus: int = int(LootTable.ITEMS.get(equipped_weapon_id, {}).get("damage", 0))
			var new_bonus: int = int(item_def.get("damage", 0))
			var delta: int = new_bonus - old_bonus
			attack_damage_min += delta
			attack_damage_max += delta
			equipped_weapon_id = item_id
			GameState.log_event("Equipped %s" % item_id)
			GameState.emit_signal("character_equipment_changed", equipped_weapon_id, equipped_armor_id)
	elif item_type == "armor":
		if LootTable.should_equip(equipped_armor_id, item_id):
			var old_bonus: int = int(LootTable.ITEMS.get(equipped_armor_id, {}).get("max_hp", 0))
			var new_bonus: int = int(item_def.get("max_hp", 0))
			max_hp += new_bonus - old_bonus
			equipped_armor_id = item_id
			GameState.log_event("Equipped %s" % item_id)
			GameState.emit_signal("character_equipment_changed", equipped_weapon_id, equipped_armor_id)
			GameState.emit_signal("character_hp_changed", hp, max_hp)
	item.queue_free()
```

Replace with:

```gdscript
	elif item_type == "weapon":
		if LootTable.should_equip(equipped_weapon_id, item_id):
			var old_bonus: int = int(LootTable.ITEMS.get(equipped_weapon_id, {}).get("damage", 0))
			var new_bonus: int = int(item_def.get("damage", 0))
			var delta: int = new_bonus - old_bonus
			attack_damage_min += delta
			attack_damage_max += delta
			equipped_weapon_id = item_id
			GameState.log_event("Equipped %s" % item_id)
			GameState.emit_signal("character_equipment_changed", equipped_weapon_id, equipped_armor_id)
		else:
			GameState.log_event("Found %s - current gear is better" % item_id)
	elif item_type == "armor":
		if LootTable.should_equip(equipped_armor_id, item_id):
			var old_bonus: int = int(LootTable.ITEMS.get(equipped_armor_id, {}).get("max_hp", 0))
			var new_bonus: int = int(item_def.get("max_hp", 0))
			max_hp += new_bonus - old_bonus
			equipped_armor_id = item_id
			GameState.log_event("Equipped %s" % item_id)
			GameState.emit_signal("character_equipment_changed", equipped_weapon_id, equipped_armor_id)
			GameState.emit_signal("character_hp_changed", hp, max_hp)
		else:
			GameState.log_event("Found %s - current gear is better" % item_id)
	item.queue_free()
```

- [ ] **Step 2: Verify**

Run `mcp__godot__run_project`. Run `game_get_errors` — clean. Force a guaranteed-worse pickup to test deterministically (equip the strong item first, then simulate finding the weak one):

```gdscript
var c = GameState.character
c.equipped_weapon_id = "iron_sword"
c.call("_pickup_item", null)
return "n/a - see next call"
```

That call will fail since `_pickup_item` expects a real item node with an `item_id` property — instead, drive it through the actual item-drop path, which is simpler and exercises real code: wait for a natural drop (this project's loot table is uniform-random across all 4 items, so a `rusty_sword` drop while `iron_sword` is already equipped will happen within a few kills), then check the log:

```gdscript
return GameState.character.equipped_weapon_id
```

Once it reads `"iron_sword"`, keep playing and watch `game_get_logs` for a line reading `"Found rusty_sword - current gear is better"` the next time a weaker weapon drops. Also confirm a *better* item (e.g. `iron_sword` while `rusty_sword` or nothing is equipped) still logs `"Equipped iron_sword"` as before — this project's `LootTable.should_equip` logic is unchanged, only the `else` branch is new. Run `stop_project`.

- [ ] **Step 3: Commit**

Clean up `project.godot` drift first.

```bash
git add scripts/entities/character.gd
git commit -m "$(cat <<'EOF'
Log a line when found loot isn't equipped instead of silently discarding it

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Full integration verification

**Files:** none (verification only; fix forward in the relevant file if something's broken)

- [ ] **Step 1: Run the complete game and confirm everything works together**

Run `mcp__godot__run_project` (full `Main.tscn`, no scene override). Let it play for at least 90 real seconds, polling `game_get_logs`/`game_get_errors` periodically (short individual calls, not one long blocking wait). Confirm:
- The AI still cycles through wander/chase/combat/flee/rest/loot with no stuck states and no new errors — this whole plan should be behaviorally invisible to the FSM's *decisions*, only to what's rendered/logged.
- `game_get_errors` stays clean throughout (known noise only).

- [ ] **Step 2: Visual confirmation of every new element together**

Take several screenshots across the play session and confirm, all present at once in a natural playthrough (not just each in isolation from earlier tasks):
- The parchment-themed panels, styled bars/buttons from Task 1.
- Equipment icons next to the Weapon/Armor lines once something's equipped.
- A floating damage number during at least one hit.
- A health bar over the enemy currently being fought, and no bar over any other enemy.
- The floating action label above the character's head, matching its current state.
- The character staying within the meadow's tree line even during a flee.
- No pink-and-black "missing texture" checkerboards anywhere, no overlapping/illegible text.

- [ ] **Step 3: Confirm the rejected-loot log line appears in a natural playthrough**

Watch the activity log (via `game_get_logs` or the on-screen `ActivityLog` panel in a screenshot) for at least one `"Found <item> - current gear is better"` line over the course of natural play — this is likely already covered by Task 6's own verification, but confirm it also shows up correctly formatted in the actual themed `ItemList` panel, not just via `game_eval`.

- [ ] **Step 4: Fix forward if anything is broken**

If any regression or visual bug is found, diagnose and fix it in the relevant file with the same rigor as every other task in this plan — read the file fully, understand the root cause, apply a minimal fix, verify live, commit separately with a message describing the actual bug fixed.

- [ ] **Step 5: Stop the project and final check**

Run `mcp__godot__stop_project`. Clean up any `project.godot` drift. Confirm `git status` is clean (or contains only an already-committed Step-4 fix).

---

## Self-review notes

- **Spec coverage**: fantasy/parchment theme → Task 1. Equipment icons → Task 1. Floating damage numbers → Task 2. Enemy health bar (current target only) → Task 3. Action indicator → Task 4. Wander/flee boundary → Task 5. Rejected loot logging → Task 6. Holistic check → Task 7.
- **Deviation from the spec's literal file list, both intentional and minor**: the spec suggested `EnemyHealthBar.tscn` as a separate scene file; this plan instead declares the health bar as a plain `ProgressBar` node with a script directly inside `Enemy.tscn`, since it's never instantiated standalone — one fewer file for identical behavior, consistent with this project's stated preference against unnecessary structure. The spec suggested an `AnimationPlayer` for `FloatingText`'s rise-and-fade; this plan uses a `Tween` created in script instead, which is simpler to author correctly as plan text than a hand-written `Animation` resource, and produces the same documented behavior (rises and fades over ~0.6s, frees itself).
- **Type/signature consistency checked**: `damage_dealt(position: Vector2, amount: int, is_heal: bool)` is emitted identically (3 args, same order) from all three call sites (`character.gd` ×2, `enemy.gd` ×1) and consumed with matching parameter names in `main.gd`'s listener. `combat_target_changed(target: Node2D)` is emitted from `character.gd` and consumed identically in every `enemy_health_bar.gd` instance (compared against `get_parent()`, which is always the `Enemy` node each bar is a child of). `STATE_DISPLAY_NAMES` keys (`wander`/`chase`/`combat`/`flee`/`loot`/`rest`) match `AIDecision`'s actual state strings exactly (verified against `current_state`'s existing usage throughout `character.gd`).
- **Task ordering matters**: Tasks 2-6 all touch `scripts/entities/character.gd`, each building on the previous task's edits. Every "Find:" snippet in Tasks 3-6 is written to match the file's state *after* the prior tasks in this plan, not the original pre-plan file — execute tasks in order.
