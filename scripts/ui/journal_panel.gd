class_name JournalPanel
extends Panel

## The run's milestones, newest first. J key or the Journal button toggles it;
## it does not pause the game.

var text: RichTextLabel

func _ready() -> void:
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -210.0
	offset_right = 210.0
	offset_top = 110.0
	offset_bottom = 470.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.07, 0.05, 0.96)
	style.border_color = Color(0.55, 0.42, 0.2, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.offset_left = 12.0
	text.offset_top = 10.0
	text.offset_right = -12.0
	text.offset_bottom = -10.0
	add_child(text)
	GameState.journal_changed.connect(func(): if visible: _refresh())
	GameState.journal_toggle_requested.connect(toggle)
	GameState.panel_opened.connect(func(panel_name: String): if panel_name != "journal": visible = false)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J:
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	visible = not visible
	if visible:
		GameState.emit_signal("panel_opened", "journal")
		_refresh()

func _refresh() -> void:
	var lines: Array[String] = ["[b]Journal[/b]"]
	var c = GameState.character
	if c != null and is_instance_valid(c):
		var trait_def := TraitTable.get_def(c.character_trait)
		lines.append("[i]%s %s - %s[/i]" % [c.character_name, String(trait_def.get("title", "")), String(trait_def.get("blurb", ""))])
	lines.append("")
	var entries := GameState.journal.entries()
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		lines.append("[color=#9a8f7a]%s[/color]  %s" % [Journal.format_time(float(entry["t_ms"])), String(entry["text"])])
	text.text = "\n".join(lines)
