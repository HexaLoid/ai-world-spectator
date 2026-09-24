extends CharacterBody2D

## A background "other adventurer" populating a zone — the Erenshor-style
## illusion of a live world, without being the spectated character. Reuses
## AIDecision.resolve_state() directly (the same pure function Character
## uses): passing a context with quest/travel/loot fields always false
## naturally limits it to flee/rest/combat/chase/wander, exactly the subset
## that makes sense for a wandering companion with no quests, loot, or
## inter-zone travel of its own. No XP/leveling/loot either — this is
## atmosphere, not a second progression system to keep balanced.

const MOVE_SPEED := 75.0
const ATTACK_RANGE := 28.0
const AGGRO_RANGE := 150.0
const ATTACK_COOLDOWN_MS := 1000
const RESPAWN_DELAY_S := 3.0
const HP_REGEN_PER_SECOND := 2.5
const TARGET_SPRITE_SIZE := 40.0
const ATTACK_ANIM_DURATION_MS := 400.0

@export var player_name: String = "Adventurer"
@export var max_hp: int = 45
@export var attack_damage_min: int = 5
@export var attack_damage_max: int = 9
@export var sprite_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var home_zone_id: String = "thornfield_meadow"

var hp: int
var current_state: String = "wander"
var last_attack_time_ms: int = 0
var wander_target: Vector2 = Vector2.ZERO
var rng := RandomNumberGenerator.new()
var is_dead: bool = false
var game_time_ms: float = 0.0
var hp_regen_accumulator: float = 0.0
var spawn_position: Vector2 = Vector2.ZERO
var attack_anim_until_ms: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var name_label: Label = $NameLabel

func _ready() -> void:
	rng.randomize()
	spawn_position = global_position
	wander_target = global_position
	hp = max_hp
	sprite.modulate = sprite_tint
	name_label.text = player_name
	add_to_group("combat_targets")

func _physics_process(delta: float) -> void:
	game_time_ms += delta * 1000.0
	if hp <= 0:
		return
	var context := _build_context()
	current_state = AIDecision.resolve_state(context)["state"]
	_act(delta, context)

func _build_context() -> Dictionary:
	var nearest_hostile := _find_nearest_in_group("enemies")
	var context := {
		"hp_percent": float(hp) / float(max_hp),
		"hostile_in_attack_range": false,
		"hostile_in_aggro_range": false,
		"hostile_name": "",
		"item_nearby": false,
		"ready_to_travel": false,
		"quest_giver_in_zone": false,
		"quest_ready": false,
	}
	if nearest_hostile:
		var dist := global_position.distance_to(nearest_hostile.global_position)
		context["hostile_in_attack_range"] = dist <= ATTACK_RANGE
		context["hostile_in_aggro_range"] = dist <= AGGRO_RANGE
		context["hostile_name"] = nearest_hostile.enemy_name
	return context

func _find_nearest_in_group(group_name: String) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node):
			continue
		var d := global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = node
	return nearest

func _act(delta: float, context: Dictionary) -> void:
	var base_anim := "idle"
	var combat_hostile: Node2D = null
	match current_state:
		"flee":
			var hostile := _find_nearest_in_group("enemies")
			if hostile:
				_move_toward(global_position - hostile.global_position)
			base_anim = "run"
		"rest":
			velocity = Vector2.ZERO
			_regen_hp(delta)
		"combat":
			velocity = Vector2.ZERO
			combat_hostile = _find_nearest_in_group("enemies")
			_attack_nearest_hostile(combat_hostile)
		"chase":
			var hostile := _find_nearest_in_group("enemies")
			if hostile:
				_move_toward(hostile.global_position - global_position)
			base_anim = "run"
		"wander":
			var zone: Dictionary = ZoneTable.ZONES[home_zone_id]
			if global_position.distance_to(wander_target) < 8.0:
				wander_target = (global_position + Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))).clamp(zone["bounds_min"], zone["bounds_max"])
			_move_toward((wander_target - global_position) * 0.5)
			base_anim = "walk"
	var facing := _facing_from_velocity(velocity)
	if combat_hostile:
		facing = _facing_from_velocity(combat_hostile.global_position - global_position)
	if game_time_ms < attack_anim_until_ms:
		base_anim = "slash"
	_play_animation(base_anim, facing)
	var zone: Dictionary = ZoneTable.ZONES[home_zone_id]
	global_position = global_position.clamp(zone["bounds_min"], zone["bounds_max"])

func _move_toward(direction: Vector2) -> void:
	velocity = direction.normalized() * MOVE_SPEED
	move_and_slide()

func _regen_hp(delta: float) -> void:
	hp_regen_accumulator += HP_REGEN_PER_SECOND * delta
	while hp_regen_accumulator >= 1.0 and hp < max_hp:
		hp += 1
		hp_regen_accumulator -= 1.0

func _attack_nearest_hostile(hostile: Node2D) -> void:
	var now := int(game_time_ms)
	if hostile == null or not CombatSystem.is_off_cooldown(last_attack_time_ms, ATTACK_COOLDOWN_MS, now):
		return
	last_attack_time_ms = now
	var damage := CombatSystem.roll_damage(attack_damage_min, attack_damage_max, rng)
	hostile.take_damage(damage, self)
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
	GameState.log_event("%s has fallen - respawning" % player_name)
	visible = false
	set_physics_process(false)
	await get_tree().create_timer(RESPAWN_DELAY_S).timeout
	hp = max_hp
	global_position = spawn_position
	wander_target = spawn_position
	visible = true
	set_physics_process(true)
	is_dead = false

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
		var fallback := base_anim + "_right"
		if not sprite.sprite_frames.has_animation(fallback):
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
