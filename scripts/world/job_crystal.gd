extends Node2D

## A pulsing crystal where the hero changes job (see Character._change_job).
## Drawn in code; no art needed.

func _ready() -> void:
	add_to_group("job_crystals")
	var outer := Polygon2D.new()
	outer.polygon = PackedVector2Array([Vector2(0, -26), Vector2(15, 0), Vector2(0, 26), Vector2(-15, 0)])
	outer.color = Color(0.35, 0.85, 1.0, 0.9)
	add_child(outer)
	var inner := Polygon2D.new()
	inner.polygon = PackedVector2Array([Vector2(0, -14), Vector2(7, 0), Vector2(0, 14), Vector2(-7, 0)])
	inner.color = Color(0.85, 1.0, 1.0, 0.95)
	add_child(inner)
	var label := Label.new()
	label.text = "Job Crystal"
	label.position = Vector2(-34, 30)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0, 1.0))
	add_child(label)
	var tween := create_tween().set_loops()
	tween.tween_property(outer, "scale", Vector2(1.14, 1.14), 1.2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(outer, "scale", Vector2(1.0, 1.0), 1.2).set_trans(Tween.TRANS_SINE)
