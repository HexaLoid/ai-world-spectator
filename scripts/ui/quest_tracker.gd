extends Panel

@onready var quest_label: Label = $QuestLabel

func _ready() -> void:
	GameState.quest_changed.connect(_on_quest_changed)
	_on_quest_changed("", 0, 0)

func _on_quest_changed(quest_name: String, progress: int, count: int) -> void:
	quest_label.text = "Quest: None active" if quest_name == "" else "Quest: %s (%d/%d)" % [quest_name, progress, count]
