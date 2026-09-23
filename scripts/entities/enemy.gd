extends CharacterBody2D

const TARGET_SPRITE_SIZE := 40.0
const ATTACK_ANIM_DURATION_MS := 400.0

@export var enemy_name: String = "Enemy"
@export var max_hp: int = 20
@export var move_speed: float = 60.0
@export var attack_damage_min: int = 2
@export var attack_damage_max: int = 5
@export var attack_range: float = 24.0
@export var aggro_range: float = 120.0
@export var attack_cooldown_ms: int = 1200
@export var xp_reward: int = 25

var hp: int
var last_attack_time_ms: int = 0
var rng := RandomNumberGenerator.new()
var spawn_point: Node2D = null
var is_dead: bool = false
var game_time_ms: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var attack_anim_until_ms: float = 0.0

func _ready() -> void:
	hp = max_hp
	rng.randomize()
	add_to_group("enemies")

func _physics_process(delta: float) -> void:
	game_time_ms += delta * 1000.0
	if hp <= 0:
		return
	var character := GameState.character
	if character == null or not is_instance_valid(character):
		velocity = Vector2.ZERO
		_play_animation("idle", "down")
		return
	var dist := global_position.distance_to(character.global_position)
	if dist <= attack_range:
		velocity = Vector2.ZERO
		_attack(character)
	elif dist <= aggro_range:
		velocity = (character.global_position - global_position).normalized() * move_speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO
	var facing := _facing_from_velocity(velocity)
	if dist <= attack_range:
		facing = _facing_from_velocity(character.global_position - global_position)
	var base_anim := "idle" if velocity.length() < 1.0 else "walk"
	if game_time_ms < attack_anim_until_ms:
		base_anim = "slash"
	_play_animation(base_anim, facing)

func _facing_from_velocity(vel: Vector2) -> String:
	if vel.length() < 1.0:
		return "down"
	if abs(vel.x) > abs(vel.y):
		return "right" if vel.x > 0.0 else "left"
	return "down" if vel.y > 0.0 else "up"

func _play_animation(base_anim: String, facing: String) -> void:
	if sprite.sprite_frames == null:
		return
	var anim_name := base_anim + "_" + facing
	var mirrored := false
	if not sprite.sprite_frames.has_animation(anim_name):
		# Some sheets (e.g. Wolf's) only have a "_right" animation. Mirror it via
		# flip_h for left, but reuse it unmirrored for up/down — there's no better option.
		var fallback := base_anim + "_right"
		if not sprite.sprite_frames.has_animation(fallback):
			# The Wolf's attack animation predates the LPC "slash" naming used by
			# Bandit/Character and is still named "combat_right" in its SpriteFrames.
			# Fall back to that legacy alias before giving up.
			if base_anim == "slash" and sprite.sprite_frames.has_animation("combat_right"):
				fallback = "combat_right"
			else:
				return
		anim_name = fallback
		mirrored = facing == "left"
	sprite.flip_h = mirrored
	if sprite.animation != anim_name or not sprite.is_playing():
		sprite.play(anim_name)
	var first_frame := sprite.sprite_frames.get_frame_texture(anim_name, 0)
	if first_frame:
		var native_size: Vector2 = first_frame.get_size()
		if native_size.x > 0.0 and native_size.y > 0.0:
			var s: float = TARGET_SPRITE_SIZE / max(native_size.x, native_size.y)
			sprite.scale = Vector2(s, s)

func _attack(character: Node2D) -> void:
	var now := int(game_time_ms)
	if not CombatSystem.is_off_cooldown(last_attack_time_ms, attack_cooldown_ms, now):
		return
	last_attack_time_ms = now
	var damage := CombatSystem.roll_damage(attack_damage_min, attack_damage_max, rng)
	character.take_damage(damage)
	attack_anim_until_ms = game_time_ms + ATTACK_ANIM_DURATION_MS

func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp = max(0, hp - amount)
	GameState.emit_signal("damage_dealt", global_position, amount, false)
	if hp <= 0:
		_die()

func _die() -> void:
	is_dead = true
	var character := GameState.character
	if character and is_instance_valid(character):
		character.take_kill_credit(enemy_name, xp_reward)
	_drop_loot()
	if spawn_point and is_instance_valid(spawn_point):
		spawn_point.on_enemy_died()
	queue_free()

func _drop_loot() -> void:
	var item_id := LootTable.roll_drop(rng)
	var item_scene: PackedScene = load("res://scenes/entities/ItemPickup.tscn")
	var item := item_scene.instantiate()
	item.item_id = item_id
	item.global_position = global_position
	get_tree().current_scene.add_child.call_deferred(item)
