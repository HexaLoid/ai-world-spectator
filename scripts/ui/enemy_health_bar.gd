extends ProgressBar

func _ready() -> void:
	# The scene's declared `size` doesn't survive Godot's internal ProgressBar
	# setup (it gets reset to a larger built-in default before this runs) —
	# reassigning it here, plus the node's own `custom_minimum_size` in the
	# scene, is what makes the small size stick. Both also rely on this
	# node's `spectator_theme` having no forced ProgressBar minimum size,
	# unlike Godot's default theme — swapping the theme reference back would
	# silently reintroduce the oversized-bar bug this works around.
	size = Vector2(32, 6)
	visible = false
	GameState.combat_target_changed.connect(_on_combat_target_changed)

func _on_combat_target_changed(target: Node2D) -> void:
	visible = target == get_parent()
