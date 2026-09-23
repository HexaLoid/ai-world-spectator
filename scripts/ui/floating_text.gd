extends Node2D

var amount: int = 0
var is_heal: bool = false

@onready var label: Label = $Label

func _ready() -> void:
	label.text = ("+%d" % amount) if is_heal else ("-%d" % amount)
	label.modulate = Color(0.3, 0.9, 0.3, 1.0) if is_heal else Color(0.95, 0.25, 0.2, 1.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 24.0, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.finished.connect(queue_free)
