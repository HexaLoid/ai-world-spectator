extends Node2D

## Sentinel-value overrides: 0 / "" / Color.WHITE all mean "don't override the
## enemy's default for this field." There's currently no way to force an
## override TO zero/empty/white — acceptable for v1's fixed 2-enemy-type scope.
@export var enemy_scene: PackedScene
@export var respawn_delay_s: float = 8.0
@export var enemy_name_override: String = ""
@export var max_hp_override: int = 0
@export var move_speed_override: float = 0.0
@export var attack_damage_min_override: int = 0
@export var attack_damage_max_override: int = 0
@export var xp_reward_override: int = 0
@export var aggro_range_override: float = 0.0
@export var color_override: Color = Color.WHITE

var current_enemy: Node2D = null

func _ready() -> void:
	_spawn()

func _spawn() -> void:
	if enemy_scene == null:
		return
	current_enemy = enemy_scene.instantiate()
	current_enemy.global_position = global_position
	current_enemy.spawn_point = self
	if enemy_name_override != "":
		current_enemy.enemy_name = enemy_name_override
	if max_hp_override > 0:
		current_enemy.max_hp = max_hp_override
	if move_speed_override > 0.0:
		current_enemy.move_speed = move_speed_override
	if attack_damage_min_override > 0:
		current_enemy.attack_damage_min = attack_damage_min_override
	if attack_damage_max_override > 0:
		current_enemy.attack_damage_max = attack_damage_max_override
	if xp_reward_override > 0:
		current_enemy.xp_reward = xp_reward_override
	if aggro_range_override > 0.0:
		current_enemy.aggro_range = aggro_range_override
	if color_override != Color.WHITE and current_enemy.has_node("ColorRect"):
		# Assumes enemy_scene's root has a child literally named "ColorRect"
		# (true of Enemy.tscn today) — a rename there would break this silently.
		current_enemy.get_node("ColorRect").color = color_override
	get_tree().current_scene.add_child.call_deferred(current_enemy)

func on_enemy_died() -> void:
	current_enemy = null
	await get_tree().create_timer(respawn_delay_s).timeout
	_spawn()
