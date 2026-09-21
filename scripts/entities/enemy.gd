extends CharacterBody2D

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

func _ready() -> void:
	hp = max_hp
	rng.randomize()
	add_to_group("enemies")

func _physics_process(delta: float) -> void:
	if hp <= 0:
		return
	var character := GameState.character
	if character == null or not is_instance_valid(character):
		velocity = Vector2.ZERO
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

func _attack(character: Node2D) -> void:
	var now := Time.get_ticks_msec()
	if not CombatSystem.is_off_cooldown(last_attack_time_ms, attack_cooldown_ms, now):
		return
	last_attack_time_ms = now
	var damage := CombatSystem.roll_damage(attack_damage_min, attack_damage_max, rng)
	character.take_damage(damage)

func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp = max(0, hp - amount)
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
	get_tree().current_scene.add_child(item)
