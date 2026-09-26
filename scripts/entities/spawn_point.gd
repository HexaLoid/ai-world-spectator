extends Node2D

## Spawns one enemy described by EnemyTable[enemy_id] and respawns it
## `respawn_delay_s` after it dies.
@export var enemy_scene: PackedScene
@export var enemy_id: String = ""
@export var respawn_delay_s: float = 8.0
## Dungeon spawn points spawn once (no respawn) and mark their enemy for the run.
@export var dungeon: bool = false
## The final boss of a dungeon: its death clears the run.
@export var final_boss: bool = false

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
	current_enemy = EnemyFactory.create(enemy_scene, enemy_id, global_position, self)
	if dungeon:
		current_enemy.add_to_group("dungeon_enemies")
	if final_boss:
		current_enemy.add_to_group("dungeon_final")
	get_tree().current_scene.add_child.call_deferred(current_enemy)

func on_enemy_died() -> void:
	current_enemy = null
	if dungeon:
		return
	await get_tree().create_timer(respawn_delay_s).timeout
	_spawn()
