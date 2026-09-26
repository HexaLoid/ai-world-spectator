extends Node2D

## The portal into the Hollowed Vault (see DungeonRun). Drawn in code.

func _ready() -> void:
	add_to_group("vault_gates")
	var ring := Polygon2D.new()
	ring.polygon = _circle(30.0, 24)
	ring.color = Color(0.55, 0.25, 0.85, 0.85)
	add_child(ring)
	var core := Polygon2D.new()
	core.polygon = _circle(18.0, 20)
	core.color = Color(0.12, 0.04, 0.22, 0.95)
	add_child(core)
	var label := Label.new()
	label.text = "Vault Gate"
	label.position = Vector2(-32, 34)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.85, 0.7, 1.0, 1.0))
	add_child(label)
	var tween := create_tween().set_loops()
	tween.tween_property(ring, "scale", Vector2(1.12, 1.12), 1.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(ring, "scale", Vector2(1.0, 1.0), 1.0).set_trans(Tween.TRANS_SINE)

func _circle(radius: float, points: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(points):
		var angle := TAU * float(i) / float(points)
		result.append(Vector2(cos(angle), sin(angle)) * radius)
	return result
