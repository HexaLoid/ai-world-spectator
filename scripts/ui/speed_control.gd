extends HBoxContainer

@onready var pause_button: Button = $PauseButton
@onready var speed1_button: Button = $Speed1Button
@onready var speed2_button: Button = $Speed2Button
@onready var speed4_button: Button = $Speed4Button
@onready var recenter_button: Button = $RecenterButton

func _ready() -> void:
	pause_button.pressed.connect(func(): _set_speed(0.0))
	speed1_button.pressed.connect(func(): _set_speed(1.0))
	speed2_button.pressed.connect(func(): _set_speed(2.0))
	speed4_button.pressed.connect(func(): _set_speed(4.0))
	recenter_button.pressed.connect(func():
		if GameState.camera:
			GameState.camera.recenter()
	)
	# Appended after the Sheet and Codex buttons.
	var director_button := Button.new()
	director_button.text = "Director: On"
	director_button.pressed.connect(func():
		if GameState.camera:
			var on: bool = GameState.camera.toggle_director()
			director_button.text = "Director: On" if on else "Director: Off"
	)
	add_child(director_button)
	var journal_button := Button.new()
	journal_button.text = "Journal (J)"
	journal_button.pressed.connect(func(): GameState.journal_toggle_requested.emit())
	add_child(journal_button)

## Remembers the human's speed so boss slow-motion can restore it exactly.
func _set_speed(new_scale: float) -> void:
	GameState.user_time_scale = new_scale
	Engine.time_scale = new_scale
