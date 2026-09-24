extends Node2D

## Spawns one enemy described by EnemyTable[enemy_id] and respawns it
## `respawn_delay_s` after it dies.
@export var enemy_scene: PackedScene
@export var enemy_id: String = ""
@export var respawn_delay_s: float = 8.0

var current_enemy: Node2D = null

func _ready() -> void:
	_spawn()

func _spawn() -> void:
	if enemy_scene == null:
		return
	var def := EnemyTable.get_def(enemy_id)
	if def.is_empty():
		push_warning("SpawnPoint %s has unknown enemy_id '%s'" % [name, enemy_id])
		return
	current_enemy = enemy_scene.instantiate()
	current_enemy.global_position = global_position
	current_enemy.spawn_point = self
	current_enemy.enemy_name = def["name"]
	current_enemy.max_hp = def["max_hp"]
	current_enemy.move_speed = def["move_speed"]
	current_enemy.attack_damage_min = def["attack_min"]
	current_enemy.attack_damage_max = def["attack_max"]
	current_enemy.aggro_range = def["aggro_range"]
	current_enemy.xp_reward = def["xp_reward"]
	current_enemy.gold_min = def["gold_min"]
	current_enemy.gold_max = def["gold_max"]
	current_enemy.loot_level = def["loot_level"]
	current_enemy.sprite_size = def["sprite_size"]
	current_enemy.sprite_tint = def["tint"]
	current_enemy.guaranteed_drop_id = def["guaranteed_drop"]
	current_enemy.get_node("AnimatedSprite2D").sprite_frames = load(EnemyTable.SPRITE_FRAMES[def["sprite"]])
	get_tree().current_scene.add_child.call_deferred(current_enemy)

func on_enemy_died() -> void:
	current_enemy = null
	await get_tree().create_timer(respawn_delay_s).timeout
	_spawn()
