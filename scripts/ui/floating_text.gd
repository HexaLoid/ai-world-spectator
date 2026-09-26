extends Node2D

var amount: int = 0
var is_heal: bool = false
var is_crit: bool = false
var text_scale: float = 1.0
var text_color: Color = Color(0.95, 0.25, 0.2, 1.0)

@onready var label: Label = $Label

func _ready() -> void:
	var text := ("+%d" % amount) if is_heal else ("-%d" % amount)
	if is_crit:
		text += "!"
	label.text = text
	label.modulate = text_color
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2.ONE * text_scale
	var rise := 36.0 if is_crit else 24.0
	var duration := 0.85 if is_crit else 0.6
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - rise, duration)
	tween.tween_property(label, "modulate:a", 0.0, duration)
	tween.finished.connect(queue_free)
