class_name BossMechanics
extends Node

## The Hollow King's mechanics (child of the Enemy): a telegraphed heavy strike
## on the tank every EncounterLogic.HEAVY_INTERVAL_MS and, once at 50% HP, two
## adds. Timing and numbers live in EncounterLogic.

const VICTIM_RANGE := 320.0
const ENEMY_SCENE := "res://scenes/entities/Enemy.tscn"

var boss: Node2D
var next_heavy_ms: float = 0.0
var windup_end_ms: float = -1.0
var adds_done: bool = false

func _ready() -> void:
	boss = get_parent()
	next_heavy_ms = _now() + EncounterLogic.HEAVY_INTERVAL_MS

func _now() -> float:
	return float(boss.get("game_time_ms"))

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(boss) or bool(boss.get("is_dead")):
		return
	var now := _now()
	if windup_end_ms >= 0.0:
		if now >= windup_end_ms:
			_strike()
			windup_end_ms = -1.0
			next_heavy_ms = now + EncounterLogic.HEAVY_INTERVAL_MS
	elif EncounterLogic.heavy_due(now, next_heavy_ms) and _pick_victim() != null:
		windup_end_ms = now + EncounterLogic.HEAVY_WINDUP_MS
		GameState.emit_signal("dungeon_event", "warning", "%s winds up!" % String(boss.get("enemy_name")))
		_flash_red()
	if EncounterLogic.add_phase_due(int(boss.get("hp")), int(boss.get("max_hp")), adds_done):
		adds_done = true
		_spawn_adds()

func _pick_victim() -> Node2D:
	var nodes: Array = []
	var candidates: Array = []
	for node in get_tree().get_nodes_in_group("combat_targets"):
		if not is_instance_valid(node) or node.is_dead:
			continue
		var dist := boss.global_position.distance_to(node.global_position)
		if dist > VICTIM_RANGE:
			continue
		nodes.append(node)
		candidates.append({"dist": dist, "is_tank": str(node.get("job_role")) == "tank"})
	var index := ThreatRules.pick_target(candidates, VICTIM_RANGE)
	return null if index < 0 else nodes[index]

func _strike() -> void:
	var victim := _pick_victim()
	if victim == null:
		return
	var damage := EncounterLogic.heavy_damage(int(boss.get("attack_damage_max")))
	if victim == GameState.character:
		victim.take_damage(damage, false, boss)
	else:
		victim.take_damage(damage)

func _flash_red() -> void:
	if not GameState.fx_enabled:
		return
	var sprite := boss.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null:
		return
	var base: Color = sprite.get_meta("fx_base_modulate", sprite.modulate) if sprite.has_meta("fx_base_modulate") else sprite.modulate
	sprite.modulate = Color(1.6, 0.4, 0.4, 1.0)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", base, EncounterLogic.HEAVY_WINDUP_MS / 1000.0)

func _spawn_adds() -> void:
	var scene: PackedScene = load(ENEMY_SCENE)
	for i in range(EncounterLogic.ADD_COUNT):
		var offset := Vector2(60.0 if i == 0 else -60.0, 50.0)
		var add := EnemyFactory.create(scene, "vault_wraith", boss.global_position + offset, null)
		if add == null:
			continue
		add.add_to_group("dungeon_enemies")
		get_tree().current_scene.add_child.call_deferred(add)
