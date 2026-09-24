extends VBoxContainer

## One compact frame per member of the character's party: name, level, HP bar
## with numbers; an ally that is down shows "Down" and is dimmed. Rebuilds on
## GameState.party_changed and polls each member every frame (like the target
## frame), so it needs no per-member signals.

const FRAME_SIZE := Vector2(224, 40)
const BAR_SIZE := Vector2(208, 12)
const DOWN_MODULATE := Color(1.0, 1.0, 1.0, 0.5)

# Each row: {"member": Node, "panel": Panel, "name": Label, "bar": ProgressBar, "text": Label}
var rows: Array = []

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	GameState.party_changed.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	for row in rows:
		row["panel"].queue_free()
	rows.clear()
	var leader = GameState.character
	if leader == null or not is_instance_valid(leader):
		return
	for member in leader.party:
		if is_instance_valid(member):
			rows.append(_make_row(member))

func _make_row(member: Node) -> Dictionary:
	var panel := Panel.new()
	panel.custom_minimum_size = FRAME_SIZE
	var name_label := Label.new()
	name_label.position = Vector2(8, 1)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = BAR_SIZE
	bar.position = Vector2(8, 22)
	bar.show_percentage = false
	var text := Label.new()
	text.position = Vector2(8, 22)
	text.size = BAR_SIZE
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_size_override("font_size", 10)
	text.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	text.add_theme_constant_override("outline_size", 4)
	panel.add_child(name_label)
	panel.add_child(bar)
	panel.add_child(text)
	add_child(panel)
	# Godot resets a ProgressBar's size during its setup, so reassign it once
	# it is in the tree (same workaround as the unit and target frames).
	bar.size = BAR_SIZE
	return {"member": member, "panel": panel, "name": name_label, "bar": bar, "text": text}

func _process(_delta: float) -> void:
	for row in rows:
		var member = row["member"]
		if not is_instance_valid(member):
			row["panel"].visible = false
			continue
		row["name"].text = "%s  Lv %d" % [member.player_name, member.level]
		var bar: ProgressBar = row["bar"]
		bar.max_value = member.max_hp
		bar.value = member.hp
		if member.is_dead:
			row["text"].text = "Down"
			row["panel"].modulate = DOWN_MODULATE
		else:
			row["text"].text = "%d / %d" % [member.hp, member.max_hp]
			row["panel"].modulate = Color(1, 1, 1, 1)
