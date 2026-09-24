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
