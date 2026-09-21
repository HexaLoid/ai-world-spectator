extends Node2D

@export var item_id: String = "rusty_sword"

func _ready() -> void:
	add_to_group("items")
