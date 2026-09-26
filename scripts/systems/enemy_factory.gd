class_name EnemyFactory
extends RefCounted

## Builds an enemy node from EnemyTable[enemy_id] (shared by SpawnPoint and the
## boss's adds). The caller adds it to the tree. Returns null for an unknown id.
static func create(scene: PackedScene, enemy_id: String, at: Vector2, spawn_point: Node2D) -> Node2D:
	var def := EnemyTable.get_def(enemy_id)
	if scene == null or def.is_empty():
		return null
	var enemy: Node2D = scene.instantiate()
	enemy.global_position = at
	enemy.spawn_point = spawn_point
	enemy.enemy_name = def["name"]
	enemy.max_hp = def["max_hp"]
	enemy.move_speed = def["move_speed"]
	enemy.attack_damage_min = def["attack_min"]
	enemy.attack_damage_max = def["attack_max"]
	enemy.aggro_range = def["aggro_range"]
	enemy.xp_reward = def["xp_reward"]
	enemy.gold_min = def["gold_min"]
	enemy.gold_max = def["gold_max"]
	enemy.loot_level = def["loot_level"]
	enemy.sprite_size = def["sprite_size"]
	enemy.sprite_tint = def["tint"]
	enemy.guaranteed_drop_id = def["guaranteed_drop"]
	enemy.mechanics = String(def.get("mechanics", ""))
	enemy.get_node("AnimatedSprite2D").sprite_frames = load(EnemyTable.SPRITE_FRAMES[def["sprite"]])
	return enemy
