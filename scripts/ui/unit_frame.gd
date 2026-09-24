extends Control

const SLOT_SIZE := 28
const EMPTY_SLOT_BORDER := Color(0.45, 0.33, 0.15, 1.0)

var slot_panels: Dictionary = {}
var slot_icons: Dictionary = {}

@onready var hp_bar: ProgressBar = $HPBar
@onready var level_label: Label = $LevelLabel
@onready var xp_bar: ProgressBar = $XPBar
@onready var hp_text: Label = $HPText
@onready var xp_text: Label = $XPText
@onready var resource_text: Label = $ResourceText
@onready var resource_bar: ProgressBar = $ResourceBar
@onready var equip_row: HBoxContainer = $EquipRow
@onready var gold_label: Label = $GoldLabel

func _ready() -> void:
	# Godot resets a ProgressBar's scene-declared size during its internal
	# setup, inflating the bars — reassign after that (see enemy_health_bar.gd).
	hp_bar.size = Vector2(200, 20)
	xp_bar.size = Vector2(200, 12)
	resource_bar.size = Vector2(200, 10)
	_build_slots()
	GameState.character_hp_changed.connect(_on_hp_changed)
	GameState.character_xp_changed.connect(_on_xp_changed)
	GameState.character_resource_changed.connect(_on_resource_changed)
	GameState.character_leveled_up.connect(_on_leveled_up)
	GameState.character_equipment_changed.connect(_on_equipment_changed)
	GameState.gold_changed.connect(_on_gold_changed)
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
		_on_equipment_changed(GameState.character.equipment)
		_on_gold_changed(GameState.character.gold)

func _on_hp_changed(hp: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_text.text = "%d / %d" % [hp, max_hp]

func _on_resource_changed(resource_amount: float, max_resource: float) -> void:
	resource_bar.visible = max_resource > 0.0
	resource_text.visible = resource_bar.visible
	var resource_name: String = GameState.character.class_def.get("resource_name", "") if GameState.character else ""
	resource_text.text = "%s %d / %d" % [resource_name, int(resource_amount), int(max_resource)]
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
	return "%s
%s
%s - level %d %s" % [
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
