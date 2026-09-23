extends ProgressBar

func _ready() -> void:
	visible = false
	GameState.combat_target_changed.connect(_on_combat_target_changed)

func _on_combat_target_changed(target: Node2D) -> void:
	visible = target == get_parent()
