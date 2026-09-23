extends ProgressBar

func _ready() -> void:
	# The scene's declared `size` doesn't survive Godot's internal ProgressBar
	# setup (it gets reset to a larger built-in default before this runs) —
	# reassigning it here is what actually makes the small size stick.
	size = Vector2(32, 6)
	visible = false
	GameState.combat_target_changed.connect(_on_combat_target_changed)

func _on_combat_target_changed(target: Node2D) -> void:
	visible = target == get_parent()
