extends Node2D

@export var item_id: String = "rusty_sword"

@onready var icon: Sprite2D = $Icon

func _ready() -> void:
	add_to_group("items")
	var icon_path: String = LootTable.ITEMS.get(item_id, {}).get("icon", "")
	if icon_path != "":
		icon.texture = load(icon_path)
	# A gentle bob so drops read as pickups rather than scenery.
	var tween := create_tween().set_loops()
	tween.tween_property(icon, "position:y", -3.0, 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(icon, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_SINE)
