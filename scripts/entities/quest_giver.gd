extends Node2D

@onready var marker_label: Label = $MarkerLabel

func _ready() -> void:
	add_to_group("quest_givers")
	# Starting condition is "no active quest", which is exactly when the
	# marker should show — matches the (quest_name="", 0, 0) signal shape
	# emitted whenever there's nothing active, without needing Character to
	# fire an extra signal on startup just to prime this.
	marker_label.visible = true
	GameState.quest_changed.connect(_on_quest_changed)

func _on_quest_changed(_quest_name: String, progress: int, count: int) -> void:
	marker_label.visible = count == 0 or progress >= count
