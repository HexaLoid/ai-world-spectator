extends CharacterBody2D

const MOVE_SPEED := 80.0
const ATTACK_RANGE := 28.0
const AGGRO_RANGE := 160.0
const PICKUP_RANGE := 20.0
const ATTACK_COOLDOWN_MS := 900
const RESPAWN_DELAY_S := 2.0
const RESPAWN_POSITION := Vector2(0, 0)
const HP_REGEN_PER_SECOND := 3.0
const TARGET_SPRITE_SIZE := 40.0
const ATTACK_ANIM_DURATION_MS := 400.0

@export var max_hp: int = 60
@export var hp: int = 60
@export var level: int = 1
@export var xp: int = 0
@export var attack_damage_min: int = 4
@export var attack_damage_max: int = 8

var equipped_weapon_id: String = ""
var equipped_armor_id: String = ""
var current_state: String = "wander"
var last_attack_time_ms: int = 0
var wander_target: Vector2 = Vector2.ZERO
var rng := RandomNumberGenerator.new()
var is_dead: bool = false
var game_time_ms: float = 0.0
var hp_regen_accumulator: float = 0.0
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var attack_anim_until_ms: float = 0.0

func _ready() -> void:
	rng.randomize()
	wander_target = global_position
	GameState.character = self

func _physics_process(delta: float) -> void:
	game_time_ms += delta * 1000.0
	if hp <= 0:
		return
	var context := _build_context()
	var decision := AIDecision.resolve_state(context)
	var new_state: String = decision["state"]
	if new_state != current_state:
		current_state = new_state
		GameState.log_event(decision["reason"])
		GameState.emit_signal("character_state_changed", current_state)
	_act(delta, context)

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
		# Sheets without a dedicated up/down pose (e.g. the Wolf) only have a
		# "_right" animation; mirror it via flip_h for left, but up/down just
		# reuse the right-facing pose unmirrored since there's no better option.
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

func _build_context() -> Dictionary:
	var nearest_hostile := _find_nearest_in_group("enemies")
	var nearest_item := _find_nearest_in_group("items")
	var context := {
		"hp_percent": float(hp) / float(max_hp),
		"hostile_in_attack_range": false,
		"hostile_in_aggro_range": false,
		"hostile_name": "",
		"item_nearby": false,
	}
	if nearest_hostile:
		var dist := global_position.distance_to(nearest_hostile.global_position)
		context["hostile_in_attack_range"] = dist <= ATTACK_RANGE
		context["hostile_in_aggro_range"] = dist <= AGGRO_RANGE
		context["hostile_name"] = nearest_hostile.enemy_name
	if nearest_item:
		var item_dist := global_position.distance_to(nearest_item.global_position)
		context["item_nearby"] = item_dist <= AGGRO_RANGE
	return context

func _find_nearest_in_group(group_name: String) -> Node2D:
	var nodes := get_tree().get_nodes_in_group(group_name)
	var nearest: Node2D = null
	var nearest_dist := INF
	for node in nodes:
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
				velocity = (global_position - hostile.global_position).normalized() * MOVE_SPEED
				move_and_slide()
			base_anim = "run"
		"rest":
			velocity = Vector2.ZERO
			hp_regen_accumulator += HP_REGEN_PER_SECOND * delta
			while hp_regen_accumulator >= 1.0 and hp < max_hp:
				hp += 1
				hp_regen_accumulator -= 1.0
		"combat":
			velocity = Vector2.ZERO
			combat_hostile = _find_nearest_in_group("enemies")
			_attack_nearest_hostile()
		"chase":
			var hostile := _find_nearest_in_group("enemies")
			if hostile:
				velocity = (hostile.global_position - global_position).normalized() * MOVE_SPEED
				move_and_slide()
			base_anim = "run"
		"loot":
			var item := _find_nearest_in_group("items")
			if item:
				var to_item := item.global_position - global_position
				if to_item.length() <= PICKUP_RANGE:
					_pickup_item(item)
				else:
					velocity = to_item.normalized() * MOVE_SPEED
					move_and_slide()
			base_anim = "walk"
		"wander":
			if global_position.distance_to(wander_target) < 8.0:
				wander_target = global_position + Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
			velocity = (wander_target - global_position).normalized() * MOVE_SPEED * 0.5
			move_and_slide()
			base_anim = "walk"
	var facing := _facing_from_velocity(velocity)
	if combat_hostile:
		facing = _facing_from_velocity(combat_hostile.global_position - global_position)
	if game_time_ms < attack_anim_until_ms:
		base_anim = "slash"
	_play_animation(base_anim, facing)

func _attack_nearest_hostile() -> void:
	var now := int(game_time_ms)
	if not CombatSystem.is_off_cooldown(last_attack_time_ms, ATTACK_COOLDOWN_MS, now):
		return
	var hostile := _find_nearest_in_group("enemies")
	if hostile == null:
		return
	last_attack_time_ms = now
	var damage := CombatSystem.roll_damage(attack_damage_min, attack_damage_max, rng)
	hostile.take_damage(damage)
	attack_anim_until_ms = game_time_ms + ATTACK_ANIM_DURATION_MS

func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp = max(0, hp - amount)
	GameState.emit_signal("character_hp_changed", hp, max_hp)
	if hp <= 0:
		_die()

func _die() -> void:
	is_dead = true
	GameState.log_event("Character died - respawning")
	visible = false
	set_physics_process(false)
	await get_tree().create_timer(RESPAWN_DELAY_S).timeout
	hp = max_hp
	global_position = RESPAWN_POSITION
	wander_target = RESPAWN_POSITION
	visible = true
	set_physics_process(true)
	is_dead = false
	GameState.emit_signal("character_hp_changed", hp, max_hp)

func gain_xp(amount: int) -> void:
	var result := LevelingSystem.apply_xp(level, xp, amount)
	level = result["level"]
	xp = result["xp"]
	if result["leveled_up"]:
		max_hp += result["hp_bonus"]
		hp += result["hp_bonus"]
		attack_damage_min += result["damage_bonus"]
		attack_damage_max += result["damage_bonus"]
		GameState.log_event("Leveled up to %d!" % level)
		GameState.emit_signal("character_leveled_up", level)
	GameState.emit_signal("character_xp_changed", xp)

func take_kill_credit(enemy_name: String, xp_reward: int) -> void:
	GameState.log_event("Defeated %s" % enemy_name)
	gain_xp(xp_reward)

func _pickup_item(item: Node2D) -> void:
	var item_id: String = item.item_id
	var item_def: Dictionary = LootTable.ITEMS.get(item_id, {})
	var item_type: String = item_def.get("type", "")
	if item_type == "consumable":
		hp = min(max_hp, hp + int(item_def.get("heal", 0)))
		GameState.log_event("Used %s" % item_id)
		GameState.emit_signal("character_hp_changed", hp, max_hp)
	elif item_type == "weapon":
		if LootTable.should_equip(equipped_weapon_id, item_id):
			var old_bonus: int = int(LootTable.ITEMS.get(equipped_weapon_id, {}).get("damage", 0))
			var new_bonus: int = int(item_def.get("damage", 0))
			var delta: int = new_bonus - old_bonus
			attack_damage_min += delta
			attack_damage_max += delta
			equipped_weapon_id = item_id
			GameState.log_event("Equipped %s" % item_id)
			GameState.emit_signal("character_equipment_changed", equipped_weapon_id, equipped_armor_id)
	elif item_type == "armor":
		if LootTable.should_equip(equipped_armor_id, item_id):
			var old_bonus: int = int(LootTable.ITEMS.get(equipped_armor_id, {}).get("max_hp", 0))
			var new_bonus: int = int(item_def.get("max_hp", 0))
			max_hp += new_bonus - old_bonus
			equipped_armor_id = item_id
			GameState.log_event("Equipped %s" % item_id)
			GameState.emit_signal("character_equipment_changed", equipped_weapon_id, equipped_armor_id)
	item.queue_free()
