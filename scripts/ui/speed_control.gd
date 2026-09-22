extends HBoxContainer

@onready var pause_button: Button = $PauseButton
@onready var speed1_button: Button = $Speed1Button
@onready var speed2_button: Button = $Speed2Button
@onready var speed4_button: Button = $Speed4Button
@onready var recenter_button: Button = $RecenterButton

func _ready() -> void:
	pause_button.pressed.connect(func(): Engine.time_scale = 0.0)
	speed1_button.pressed.connect(func(): Engine.time_scale = 1.0)
	speed2_button.pressed.connect(func(): Engine.time_scale = 2.0)
	speed4_button.pressed.connect(func(): Engine.time_scale = 4.0)
	recenter_button.pressed.connect(func():
		if GameState.camera:
			GameState.camera.recenter()
	)
