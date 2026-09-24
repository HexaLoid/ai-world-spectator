extends Control

const DEFAULT_LABEL_COLOR := Color(0.2, 0.12, 0.05, 1.0)

@onready var hp_bar: ProgressBar = $HPBar
@onready var level_label: Label = $LevelLabel
@onready var xp_bar: ProgressBar = $XPBar
@onready var hp_text: Label = $HPText
@onready var xp_text: Label = $XPText
@onready var resource_bar: ProgressBar = $ResourceBar
@onready var weapon_icon: TextureRect = $WeaponIcon
@onready var weapon_label: Label = $WeaponLabel
@onready var armor_icon: TextureRect = $ArmorIcon
@onready var armor_label: Label = $ArmorLabel
@onready var trinket_icon: TextureRect = $TrinketIcon
@onready var trinket_label: Label = $TrinketLabel

func _ready() -> void:
	# Godot resets a ProgressBar's scene-declared size during its internal
	# setup, inflating the bars — reassign after that (see enemy_health_bar.gd).
	hp_bar.size = Vector2(200, 20)
	xp_bar.size = Vector2(200, 12)
	resource_bar.size = Vector2(200, 10)
	GameState.character_hp_changed.connect(_on_hp_changed)
	GameState.character_xp_changed.connect(_on_xp_changed)
	GameState.character_resource_changed.connect(_on_resource_changed)
	GameState.character_leveled_up.connect(_on_leveled_up)
	GameState.character_equipment_changed.connect(_on_equipment_changed)
	if GameState.character:
		# The resource bar's fill color is per-class (e.g. orange Rage vs.
		# blue Mana) — recolored once here rather than per-update, since the
		# class never changes after spawn. Duplicated so this doesn't mutate
		# the shared StyleBoxFlat resource other instances might reference.
		var resource_color: Color = GameState.character.class_def.get("resource_color", Color(0.8, 0.35, 0.05, 1.0))
		var resource_style: StyleBox = resource_bar.get_theme_stylebox("fill").duplicate()
		resource_style.bg_color = resource_color
		resource_bar.add_theme_stylebox_override("fill", resource_style)
		_on_hp_changed(GameState.character.hp, GameState.character.max_hp)
		_on_leveled_up(GameState.character.level)
		_on_xp_changed(GameState.character.xp)
		_on_resource_changed(GameState.character.resource_amount, GameState.character.max_resource)
		_on_equipment_changed(GameState.character.equipped_weapon_id, GameState.character.equipped_armor_id, GameState.character.equipped_trinket_id)

func _on_hp_changed(hp: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_text.text = "%d / %d" % [hp, max_hp]

func _on_resource_changed(resource_amount: float, max_resource: float) -> void:
	resource_bar.visible = max_resource > 0.0
	resource_bar.max_value = max_resource
	resource_bar.value = resource_amount

func _on_xp_changed(xp: int) -> void:
	var level: int = GameState.character.level if GameState.character else 1
	var next_threshold: int = LevelingSystem.get_next_threshold(level)
	if next_threshold <= 0:
		# Max level: show the bar as full rather than letting it overflow with
		# further (now purely cosmetic) XP gains.
		xp_bar.max_value = 1
		xp_bar.value = 1
		xp_text.text = "MAX"
		return
	var prev_threshold: int = LevelingSystem.XP_THRESHOLDS[level - 2] if level > 1 else 0
	xp_bar.max_value = next_threshold - prev_threshold
	xp_bar.value = xp - prev_threshold
	xp_text.text = "XP %d / %d" % [xp - prev_threshold, next_threshold - prev_threshold]

func _on_leveled_up(level: int) -> void:
	var class_name_display := ""
	if GameState.character:
		class_name_display = " %s" % GameState.character.character_class.capitalize()
	level_label.text = "Level %d%s" % [level, class_name_display]

func _on_equipment_changed(weapon_id: String, armor_id: String, trinket_id: String) -> void:
	_update_equipment_slot(weapon_label, weapon_icon, "Weapon", weapon_id)
	_update_equipment_slot(armor_label, armor_icon, "Armor", armor_id)
	_update_equipment_slot(trinket_label, trinket_icon, "Trinket", trinket_id)

## Shared by all three equipment slots: sets "<slot>: <item or None>" text
## colored by the item's rarity (RARITY_COLORS), and loads its icon.
func _update_equipment_slot(label: Label, icon: TextureRect, slot_name: String, item_id: String) -> void:
	label.text = "%s: %s" % [slot_name, item_id if item_id != "" else "None"]
	var item_def: Dictionary = LootTable.ITEMS.get(item_id, {})
	var rarity: String = item_def.get("rarity", "")
	label.add_theme_color_override("font_color", LootTable.RARITY_COLORS.get(rarity, DEFAULT_LABEL_COLOR))
	var icon_path: String = item_def.get("icon", "")
	icon.texture = load(icon_path) if icon_path != "" else null
