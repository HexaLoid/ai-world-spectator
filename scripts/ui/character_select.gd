extends Control

## Pick a job to start a new run. Cards are built in code from AbilityTable.

const MAIN_SCENE := "res://scenes/Main.tscn"
const ROLE_LABELS := {"tank": "Tank", "healer": "Healer", "melee": "Melee DPS", "magic": "Magic DPS"}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme_res := load("res://assets/theme/spectator_theme.tres")
	if theme_res is Theme:
		theme = theme_res
	var background := ColorRect.new()
	background.color = Color(0.07, 0.06, 0.09, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40.0
	root.offset_right = -40.0
	root.offset_top = 30.0
	root.offset_bottom = -30.0
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	var title := Label.new()
	title.text = "Choose a job"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8, 1.0))
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Your character plays itself. You just watch."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.76, 0.68, 1.0))
	root.add_child(subtitle)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(grid)
	for job_id in AbilityTable.job_ids():
		grid.add_child(_make_card(job_id))
	grid.add_child(_make_random_card())
	# Keyboard users can pick with the arrow keys and Enter.
	grid.get_child(0).call_deferred("grab_focus")

func _make_card(job_id: String) -> Button:
	var def: Dictionary = AbilityTable.CLASSES[job_id]
	var button := Button.new()
	button.custom_minimum_size = Vector2(250.0, 130.0)
	button.text = "%s\n[%s]\n%s" % [def["name"], ROLE_LABELS.get(def["role"], def["role"]), def["blurb"]]
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tint: Color = def["sprite_tint"]
	button.add_theme_color_override("font_color", tint.lightened(0.6))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	button.pressed.connect(_start.bind(job_id))
	return button

func _make_random_card() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(250.0, 130.0)
	button.text = "Random\n[Any job]\nLet fate decide."
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(func(): _start(AbilityTable.job_ids()[randi() % AbilityTable.job_ids().size()]))
	return button

func _start(job_id: String) -> void:
	GameState.reset_run()
	GameState.selected_job = job_id
	GameState.job_chosen = true
	get_tree().change_scene_to_file(MAIN_SCENE)
