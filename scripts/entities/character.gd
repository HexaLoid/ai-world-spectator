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
# Inset from ThornfieldMeadow's 800x600 background rect
# (scenes/world/ThornfieldMeadow.tscn) by 20px on each side.
const MEADOW_MIN := Vector2(-380, -280)
const MEADOW_MAX := Vector2(380, 280)

const STATE_DISPLAY_NAMES := {
	"wander": "Wandering",
	"chase": "Chasing",
	"combat": "Fighting",
	"flee": "Fleeing",
	"loot": "Looting",
	"rest": "Resting",
}

@export var max_hp: int = 60
@export var hp: int = 60
@export var level: int = 1
@export var xp: int = 0
@export var attack_damage_min: int = 4
@export var attack_damage_max: int = 8
@export var character_class: String = "warrior"

var equipped_weapon_id: String = ""
var equipped_armor_id: String = ""
var current_state: String = "wander"
var last_attack_time_ms: int = 0
var wander_target: Vector2 = Vector2.ZERO
var rng := RandomNumberGenerator.new()
var is_dead: bool = false
var game_time_ms: float = 0.0
var hp_regen_accumulator: float = 0.0
var last_combat_target: Node2D = null
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var action_label: Label = $ActionLabel
var attack_anim_until_ms: float = 0.0

# Class resource (Rage for the warrior) and per-ability cooldown tracking.
# `class_def`/`ABILITIES` come from AbilityTable, keyed by `character_class`,
# so a second class can be added there later without touching this script's
# structure.
var class_def: Dictionary = {}
var resource_amount: float = 0.0
var max_resource: float = 0.0
var ability_cooldowns: Dictionary = {}

func _ready() -> void:
	rng.randomize()
	wander_target = global_position
	GameState.character = self
	class_def = AbilityTable.CLASSES.get(character_class, {})
	max_resource = float(class_def.get("max_resource", 0.0))
	GameState.emit_signal("character_resource_changed", resource_amount, max_resource)

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
		action_label.text = STATE_DISPLAY_NAMES.get(current_state, current_state.capitalize())
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
			_try_second_wind()
			var hostile := _find_nearest_in_group("enemies")
			if hostile:
				_move_toward(global_position - hostile.global_position, MOVE_SPEED)
			base_anim = "run"
		"rest":
			_try_second_wind()
			velocity = Vector2.ZERO
			_regen_hp(delta)
			_decay_resource(delta)
		"combat":
			velocity = Vector2.ZERO
			combat_hostile = _find_nearest_in_group("enemies")
			_attack_nearest_hostile()
			if combat_hostile:
				_try_combat_abilities(combat_hostile)
		"chase":
			var hostile := _find_nearest_in_group("enemies")
			if hostile:
				if not _try_charge(hostile):
					_move_toward(hostile.global_position - global_position, MOVE_SPEED)
			base_anim = "run"
		"loot":
			var item := _find_nearest_in_group("items")
			if item:
				var to_item := item.global_position - global_position
				if to_item.length() <= PICKUP_RANGE:
					_pickup_item(item)
				else:
					_move_toward(to_item, MOVE_SPEED)
			base_anim = "walk"
			_decay_resource(delta)
		"wander":
			if global_position.distance_to(wander_target) < 8.0:
				wander_target = (global_position + Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))).clamp(MEADOW_MIN, MEADOW_MAX)
			_move_toward(wander_target - global_position, MOVE_SPEED * 0.5)
			base_anim = "walk"
			_decay_resource(delta)
	var facing := _facing_from_velocity(velocity)
	if combat_hostile:
		facing = _facing_from_velocity(combat_hostile.global_position - global_position)
	_update_combat_target(combat_hostile)
	if game_time_ms < attack_anim_until_ms:
		base_anim = "slash"
	_play_animation(base_anim, facing)
	global_position = global_position.clamp(MEADOW_MIN, MEADOW_MAX)

func _move_toward(direction: Vector2, speed: float) -> void:
	velocity = direction.normalized() * speed
	move_and_slide()

func _regen_hp(delta: float) -> void:
	hp_regen_accumulator += HP_REGEN_PER_SECOND * delta
	while hp_regen_accumulator >= 1.0 and hp < max_hp:
		hp += 1
		hp_regen_accumulator -= 1.0

func _update_combat_target(combat_hostile: Node2D) -> void:
	if combat_hostile != last_combat_target:
		last_combat_target = combat_hostile
		GameState.emit_signal("combat_target_changed", combat_hostile)

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
	_gain_resource(float(class_def.get("rage_per_swing", 0.0)))

func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp = max(0, hp - amount)
	GameState.emit_signal("character_hp_changed", hp, max_hp)
	GameState.emit_signal("damage_dealt", global_position, amount, false)
	_gain_resource(float(class_def.get("rage_per_hit_taken", 0.0)))
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
	ability_cooldowns.clear()
	resource_amount = 0.0
	GameState.emit_signal("character_hp_changed", hp, max_hp)
	GameState.emit_signal("character_resource_changed", resource_amount, max_resource)

## Returns seconds remaining before `ability_id` is off cooldown (0 if ready).
## Polled directly by the HUD's ability bar each frame, the same way
## CameraController polls GameState.character's position — cooldown sweeps
## need continuous updates, not a discrete signal per tick.
func get_ability_cooldown_remaining(ability_id: String) -> float:
	var ready_at: float = ability_cooldowns.get(ability_id, 0.0)
	return max(0.0, (ready_at - game_time_ms) / 1000.0)

func _ability_ready(ability_id: String, cost: float) -> bool:
	return get_ability_cooldown_remaining(ability_id) <= 0.0 and resource_amount >= cost

func _start_cooldown(ability_id: String, cooldown_ms: int) -> void:
	ability_cooldowns[ability_id] = game_time_ms + cooldown_ms

func _gain_resource(amount: float) -> void:
	if amount == 0.0 or max_resource <= 0.0:
		return
	resource_amount = clampf(resource_amount + amount, 0.0, max_resource)
	GameState.emit_signal("character_resource_changed", resource_amount, max_resource)

func _spend_resource(amount: float) -> void:
	_gain_resource(-amount)

func _decay_resource(delta: float) -> void:
	_gain_resource(-float(class_def.get("resource_decay_per_second", 0.0)) * delta)

## Gap closer used from the "chase" state instead of walking, when off
## cooldown. Returns true if it fired (caller skips its normal move step).
func _try_charge(hostile: Node2D) -> bool:
	var def: Dictionary = AbilityTable.ABILITIES.get("charge", {})
	if not _ability_ready("charge", float(def.get("resource_cost", 0.0))):
		return false
	_start_cooldown("charge", int(def.get("cooldown_ms", 0)))
	var to_hostile := hostile.global_position - global_position
	# Land just outside melee range rather than exactly on top of the target.
	global_position = hostile.global_position - to_hostile.normalized() * (ATTACK_RANGE * 0.9)
	_gain_resource(float(def.get("resource_gain", 0.0)))
	GameState.log_event("Charges at %s!" % hostile.enemy_name)
	return true

## Layers Rend/Heroic Strike on top of the normal auto-attack, each on its
## own independent cooldown, while in the "combat" state.
func _try_combat_abilities(hostile: Node2D) -> void:
	var rend: Dictionary = AbilityTable.ABILITIES.get("rend", {})
	if _ability_ready("rend", float(rend.get("resource_cost", 0.0))):
		_use_rend(hostile, rend)
		return
	var heroic_strike: Dictionary = AbilityTable.ABILITIES.get("heroic_strike", {})
	if _ability_ready("heroic_strike", float(heroic_strike.get("resource_cost", 0.0))):
		_use_heroic_strike(hostile, heroic_strike)

func _use_rend(hostile: Node2D, def: Dictionary) -> void:
	_spend_resource(float(def.get("resource_cost", 0.0)))
	_start_cooldown("rend", int(def.get("cooldown_ms", 0)))
	hostile.apply_bleed(
		int(def.get("tick_damage_min", 0)),
		int(def.get("tick_damage_max", 0)),
		int(def.get("tick_count", 0)),
		int(def.get("tick_interval_ms", 0))
	)
	attack_anim_until_ms = game_time_ms + ATTACK_ANIM_DURATION_MS
	GameState.log_event("Rends %s - bleeding!" % hostile.enemy_name)

func _use_heroic_strike(hostile: Node2D, def: Dictionary) -> void:
	_spend_resource(float(def.get("resource_cost", 0.0)))
	_start_cooldown("heroic_strike", int(def.get("cooldown_ms", 0)))
	var base_damage := CombatSystem.roll_damage(attack_damage_min, attack_damage_max, rng)
	var damage := int(round(base_damage * float(def.get("damage_multiplier", 1.0))))
	hostile.take_damage(damage)
	attack_anim_until_ms = game_time_ms + ATTACK_ANIM_DURATION_MS
	GameState.log_event("Heroic Strike hits %s for %d!" % [hostile.enemy_name, damage])

## Checked at the start of the "flee"/"rest" states rather than folded into
## AIDecision, so the FSM's pure state-selection logic stays untouched — this
## only changes how much HP the character has by the time flee/rest run.
func _try_second_wind() -> void:
	var def: Dictionary = AbilityTable.ABILITIES.get("second_wind", {})
	if not _ability_ready("second_wind", float(def.get("resource_cost", 0.0))):
		return
	_start_cooldown("second_wind", int(def.get("cooldown_ms", 0)))
	var old_hp := hp
	hp = min(max_hp, hp + int(max_hp * float(def.get("heal_percent", 0.0))))
	var healed := hp - old_hp
	if healed <= 0:
		return
	GameState.emit_signal("character_hp_changed", hp, max_hp)
	GameState.emit_signal("damage_dealt", global_position, healed, true)
	GameState.log_event("Uses Second Wind - recovers %d HP!" % healed)

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
		GameState.emit_signal("character_hp_changed", hp, max_hp)
	GameState.emit_signal("character_xp_changed", xp)

func take_kill_credit(enemy_name: String, xp_reward: int) -> void:
	GameState.log_event("Defeated %s" % enemy_name)
	gain_xp(xp_reward)

func _pickup_item(item: Node2D) -> void:
	var item_id: String = item.item_id
	var item_def: Dictionary = LootTable.ITEMS.get(item_id, {})
	var item_type: String = item_def.get("type", "")
	if item_type == "consumable":
		var old_hp := hp
		hp = min(max_hp, hp + int(item_def.get("heal", 0)))
		var healed := hp - old_hp
		GameState.log_event("Used %s" % item_id)
		GameState.emit_signal("character_hp_changed", hp, max_hp)
		if healed > 0:
			GameState.emit_signal("damage_dealt", global_position, healed, true)
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
		else:
			GameState.log_event("Found %s - current gear is better" % item_id)
	elif item_type == "armor":
		if LootTable.should_equip(equipped_armor_id, item_id):
			var old_bonus: int = int(LootTable.ITEMS.get(equipped_armor_id, {}).get("max_hp", 0))
			var new_bonus: int = int(item_def.get("max_hp", 0))
			max_hp += new_bonus - old_bonus
			equipped_armor_id = item_id
			GameState.log_event("Equipped %s" % item_id)
			GameState.emit_signal("character_equipment_changed", equipped_weapon_id, equipped_armor_id)
			GameState.emit_signal("character_hp_changed", hp, max_hp)
		else:
			GameState.log_event("Found %s - current gear is better" % item_id)
	item.queue_free()
