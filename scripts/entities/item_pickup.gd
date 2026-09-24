extends Node2D

const GOLD_ICON := "res://assets/icons/gold_icon.png"
## Unclaimed drops (e.g. gear the character has no use for) vanish after this
## many seconds so they don't pile up in a zone.
const LIFETIME_S := 30.0

@export var item_id: String = "rusty_sword"
## When > 0 this pickup is a pile of gold worth that much and item_id is ignored.
@export var gold_amount: int = 0

@onready var icon: Sprite2D = $Icon

func _ready() -> void:
	add_to_group("items")
	var icon_path: String = GOLD_ICON if gold_amount > 0 else LootTable.ITEMS.get(item_id, {}).get("icon", "")
	if icon_path != "":
		icon.texture = load(icon_path)
	# A gentle bob so drops read as pickups rather than scenery.
	var tween := create_tween().set_loops()
	tween.tween_property(icon, "position:y", -3.0, 0.7).set_trans(Tween.TRANS_SINE)
	tween.tween_property(icon, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_SINE)
	get_tree().create_timer(LIFETIME_S).timeout.connect(queue_free)
