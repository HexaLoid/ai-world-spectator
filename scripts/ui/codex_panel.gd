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
	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color(0.07, 0.05, 0.03, 1.0)
	list_style.set_border_width_all(1)
	list_style.border_color = Color(0.55, 0.4, 0.15, 1.0)
	entry_list.add_theme_stylebox_override("panel", list_style)
	entry_list.add_theme_color_override("font_selected_color", Color(1, 0.9, 0.5, 1.0))
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
	GameState.panel_opened.connect(func(panel_name: String): if panel_name != "codex": visible = false)

func toggle() -> void:
	visible = not visible

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		toggle()
		get_viewport().set_input_as_handled()

func _on_visibility_changed() -> void:
	if visible:
		GameState.emit_signal("panel_opened", "codex")
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
