class_name HitFeedback
extends Node2D

## Visual reaction to hits: the target's sprite flashes white and is nudged
## away from the fight, and a dying enemy leaves a short "pop" ghost. Only the
## sprite child is touched (never the body's position), so AI and physics are
## unaffected. Does nothing while GameState.fx_enabled is false.

const FLASH_S := 0.12
const KNOCK_PX := 4.0
const POP_S := 0.25
const POP_SCALE := 1.4
const FLASH_COLOR := Color(2.2, 2.2, 2.2, 1.0)

func _ready() -> void:
	GameState.hit_landed.connect(_on_hit_landed)
	GameState.enemy_died.connect(_on_enemy_died)

## True when a hit belongs to a boss fight: the target is a boss, or the
## spectated character is hit while fighting a boss.
static func is_boss_hit(target: Node, on_character: bool) -> bool:
	if not is_instance_valid(target):
		return false
	if on_character:
		var foe = target.get("last_combat_target")
		return is_instance_valid(foe) and foe.has_method("is_boss") and bool(foe.call("is_boss"))
	return target.has_method("is_boss") and bool(target.call("is_boss"))

func _on_hit_landed(target: Node2D, _amount: int, _is_crit: bool, on_character: bool) -> void:
	if not GameState.fx_enabled or not is_instance_valid(target):
		return
	var spr := target.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if spr == null:
		return
	if not spr.has_meta("fx_base_modulate"):
		spr.set_meta("fx_base_modulate", spr.modulate)
		spr.set_meta("fx_base_position", spr.position)
	var base_modulate: Color = spr.get_meta("fx_base_modulate")
	var base_position: Vector2 = spr.get_meta("fx_base_position")
	if spr.has_meta("fx_tween"):
		var running = spr.get_meta("fx_tween")
		if running is Tween and running.is_valid():
			running.kill()
	spr.modulate = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, base_modulate.a)
	spr.position = base_position + _knock_direction(target, on_character) * KNOCK_PX
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(spr, "modulate", base_modulate, FLASH_S)
	tween.tween_property(spr, "position", base_position, FLASH_S * 1.5)
	spr.set_meta("fx_tween", tween)

func _knock_direction(target: Node2D, on_character: bool) -> Vector2:
	var from := Vector2.ZERO
	var c = GameState.character
	if not on_character and is_instance_valid(c) and c != target:
		from = c.global_position
	elif on_character:
		var foe = target.get("last_combat_target")
		if is_instance_valid(foe):
			from = foe.global_position
	var away := target.global_position - from
	if away.length() < 1.0:
		return Vector2.RIGHT
	return away.normalized()

func _on_enemy_died(enemy: Node2D) -> void:
	if not GameState.fx_enabled or not is_instance_valid(enemy):
		return
	var src := enemy.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if src == null or src.sprite_frames == null:
		return
	var texture := src.sprite_frames.get_frame_texture(src.animation, src.frame)
	if texture == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = texture
	ghost.flip_h = src.flip_h
	add_child(ghost)
	ghost.global_position = src.global_position
	ghost.global_scale = src.global_scale
	ghost.modulate = src.get_meta("fx_base_modulate") if src.has_meta("fx_base_modulate") else src.modulate
	var tween := ghost.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ghost, "scale", ghost.scale * POP_SCALE, POP_S)
	tween.tween_property(ghost, "modulate:a", 0.0, POP_S)
	tween.finished.connect(ghost.queue_free)
