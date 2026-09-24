extends Node2D

## Scatters purely-cosmetic sprites (flowers, rocks, grass tufts) across a
## rectangular area at random positions/scales — no collision, no gameplay
## effect. Placed as a scene node after the zone's Ground sprite so normal
## scene-tree draw order puts it above the terrain and below the
## dynamically-added Character/Enemy nodes (which live under Main, added
## after World).
@export var decoration_textures: Array[Texture2D] = []
@export var count: int = 20
@export var area_min: Vector2 = Vector2(-380, -280)
@export var area_max: Vector2 = Vector2(380, 280)
@export var min_scale: float = 0.9
@export var max_scale: float = 1.4

func _ready() -> void:
	if decoration_textures.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(count):
		var sprite := Sprite2D.new()
		sprite.texture = decoration_textures[rng.randi_range(0, decoration_textures.size() - 1)]
		sprite.position = Vector2(rng.randf_range(area_min.x, area_max.x), rng.randf_range(area_min.y, area_max.y))
		sprite.scale = Vector2.ONE * rng.randf_range(min_scale, max_scale)
		sprite.rotation = rng.randf_range(-0.15, 0.15)
		add_child(sprite)
