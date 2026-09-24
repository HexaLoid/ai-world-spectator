extends CharacterBody2D

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
@export var gold_min: int = 1
@export var gold_max: int = 3
@export var sprite_size: float = 40.0
@export var sprite_tint: Color = Color(1, 1, 1, 1)
## When set, always drops this item on death instead of a random LootTable
## roll — used by elites to guarantee a worthwhile drop for the fight.
@export var guaranteed_drop_id: String = ""

var hp: int
var last_attack_time_ms: int = 0
var rng := RandomNumberGenerator.new()
var spawn_point: Node2D = null
var is_dead: bool = false
var game_time_ms: float = 0.0

# Whoever last landed a hit (direct or via a bleed tick — see apply_bleed) —
# either the spectated Character or a SimulatedPlayer, the only two things
# that ever call take_damage() on an Enemy. Used in _die() to decide who
# gets quest/XP kill credit (only the spectated Character ever does) versus
# just a flavor log line (a SimulatedPlayer's kill).
var last_attacker: Node2D = null

# Rend's bleed: a per-instance DoT applied by Character, ticked here rather
# than in a shared status-effect system since Enemy is the only entity type
# that ever receives one in this slice.
var bleed_damage_min: int = 0
var bleed_damage_max: int = 0
var bleed_ticks_remaining: int = 0
var bleed_tick_interval_ms: float = 0.0
var bleed_next_tick_ms: float = 0.0
var bleed_source: Node2D = null

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var health_bar: ProgressBar = $EnemyHealthBar
var attack_anim_until_ms: float = 0.0

func _ready() -> void:
	hp = max_hp
	rng.randomize()
	add_to_group("enemies")
	health_bar.max_value = max_hp
	health_bar.value = hp
	sprite.modulate = sprite_tint

## Applies (or refreshes) a bleed DoT: `tick_count` hits of
## [damage_min, damage_max] damage, one every `tick_interval_ms`. `source`
## is who applied it (for kill-credit purposes if a tick lands the kill).
func apply_bleed(damage_min: int, damage_max: int, tick_count: int, tick_interval_ms: int, source: Node2D = null) -> void:
	bleed_damage_min = damage_min
	bleed_damage_max = damage_max
	bleed_ticks_remaining = tick_count
	bleed_tick_interval_ms = tick_interval_ms
	bleed_next_tick_ms = game_time_ms + tick_interval_ms
	bleed_source = source

func _physics_process(delta: float) -> void:
	game_time_ms += delta * 1000.0
	if hp <= 0:
		return
	if bleed_ticks_remaining > 0 and game_time_ms >= bleed_next_tick_ms:
		bleed_ticks_remaining -= 1
		bleed_next_tick_ms = game_time_ms + bleed_tick_interval_ms
		take_damage(rng.randi_range(bleed_damage_min, bleed_damage_max), bleed_source)
		if hp <= 0:
			return
	var target := _find_nearest_target()
	if target == null:
		velocity = Vector2.ZERO
		_play_animation("idle", "down")
		return
	var dist := global_position.distance_to(target.global_position)
	if dist <= attack_range:
		velocity = Vector2.ZERO
		_attack(target)
	elif dist <= aggro_range:
		velocity = (target.global_position - global_position).normalized() * move_speed
		move_and_slide()
	else:
		velocity = Vector2.ZERO
	var facing := _facing_from_velocity(velocity)
	if dist <= attack_range:
		facing = _facing_from_velocity(target.global_position - global_position)
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
			var s: float = sprite_size / max(native_size.x, native_size.y)
			sprite.scale = Vector2(s, s)

## Nearest node in the "combat_targets" group (the spectated Character and
## every SimulatedPlayer both register into it) — lets an Enemy fight
## whichever adventurer is closest rather than only ever the spectated one,
## the same "populated world" illusion Erenshor's simulated players give.
func _find_nearest_target() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for node in get_tree().get_nodes_in_group("combat_targets"):
		if not is_instance_valid(node) or node.is_dead:
			continue
		var d := global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = node
	return nearest

func _attack(target: Node2D) -> void:
	var now := int(game_time_ms)
	if not CombatSystem.is_off_cooldown(last_attack_time_ms, attack_cooldown_ms, now):
		return
	last_attack_time_ms = now
	var damage := CombatSystem.roll_damage(attack_damage_min, attack_damage_max, rng)
	target.take_damage(damage)
	attack_anim_until_ms = game_time_ms + ATTACK_ANIM_DURATION_MS

func take_damage(amount: int, attacker: Node2D = null) -> void:
	if is_dead:
		return
	if attacker != null:
		last_attacker = attacker
	# Only damage that actually lands counts (no overkill), and only the
	# spectated character's own hits: auto-attacks, ability hits and bleed
	# ticks all pass the attacker through here.
	if attacker != null and attacker == GameState.character:
		attacker.damage_dealt_total += mini(amount, hp)
	hp = max(0, hp - amount)
	health_bar.value = hp
	GameState.emit_signal("damage_dealt", global_position, amount, false)
	if hp <= 0:
		_die()

func _die() -> void:
	is_dead = true
	if last_attacker != null and is_instance_valid(last_attacker):
		if last_attacker == GameState.character:
			last_attacker.take_kill_credit(enemy_name, xp_reward)
		elif "player_name" in last_attacker:
			GameState.log_event("[Ally] %s defeats %s!" % [last_attacker.player_name, enemy_name])
			last_attacker.take_kill_credit(enemy_name, xp_reward)
	_drop_loot()
	if spawn_point and is_instance_valid(spawn_point):
		spawn_point.on_enemy_died()
	queue_free()

func _drop_loot() -> void:
	var item_id := guaranteed_drop_id if guaranteed_drop_id != "" else LootTable.roll_drop(rng)
	var item_scene: PackedScene = load("res://scenes/entities/ItemPickup.tscn")
	var item := item_scene.instantiate()
	item.item_id = item_id
	item.global_position = global_position
	get_tree().current_scene.add_child.call_deferred(item)
	# Elites/bosses (the ones with a guaranteed drop) pay out five times more gold.
	var gold_multiplier := 5 if guaranteed_drop_id != "" else 1
	var gold := item_scene.instantiate()
	gold.item_id = ""
	gold.gold_amount = rng.randi_range(gold_min, gold_max) * gold_multiplier
	gold.global_position = global_position + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
	get_tree().current_scene.add_child.call_deferred(gold)
