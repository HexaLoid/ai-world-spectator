extends Control

const MAX_ENTRIES := 100

@onready var log_list: ItemList = $LogList

func _ready() -> void:
	GameState.activity_logged.connect(_on_logged)

func _on_logged(message: String) -> void:
	log_list.add_item(message)
	if log_list.item_count > MAX_ENTRIES:
		log_list.remove_item(0)
	log_list.ensure_current_is_visible()
