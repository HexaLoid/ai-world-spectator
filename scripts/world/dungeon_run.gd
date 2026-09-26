class_name DungeonRun
extends Node

## Runs one Hollowed Vault instance: builds the five-person party (PartyBuilder),
## instantiates the vault far from the open world, teleports everyone in, and
## ends the run on a clear, the hero's death or a timeout, restoring the party.

const VAULT_SCENE := "res://scenes/world/HollowedVault.tscn"
const VAULT_ORIGIN := Vector2(12000, 0)
const ENTRANCE_OFFSET := Vector2(-700, 0)
const PARTY_SIZE := 5
const RUN_TIMEOUT_S := 720.0
const CLEAR_DELAY_S := 6.0
const CLEAR_BONUS_XP := 600
const CLEAR_BONUS_GOLD := 150
const LEFTOVER_ITEM_X := 11000.0

var running: bool = false
var hero: Node2D = null
var vault: Node2D = null
var run_time_s: float = 0.0
var clear_timer_s: float = -1.0
var gate_position: Vector2 = Vector2.ZERO
var pulled: Array = []

func _ready() -> void:
	add_to_group("dungeon_run")
	GameState.enemy_died.connect(_on_enemy_died)

## Starts a run for `hero_node` (the Character) from a gate at `gate_pos`.
func start(hero_node: Node2D, gate_pos: Vector2) -> bool:
	if running or hero_node == null:
		return false
	hero = hero_node
	gate_position = gate_pos
	pulled.clear()
	var party_entries: Array = []
	for ally in hero.party:
		if is_instance_valid(ally):
			party_entries.append({"id": ally.player_name, "name": ally.player_name, "role": str(ally.get("job_role"))})
	var pool: Array = []
	for sp in get_tree().get_nodes_in_group("simulated_players"):
		if is_instance_valid(sp) and sp.group_leader == null and not sp.is_dead:
			pool.append({"id": sp.player_name, "name": sp.player_name, "role": str(sp.get("job_role")), "node": sp})
	for pick in PartyBuilder.missing_members(str(hero.get("job_role")), party_entries, pool, PARTY_SIZE):
		var ally = pick["node"]
		ally.group_leader = hero
		hero.party.append(ally)
		pulled.append(ally)
		GameState.log_event("%s answers the call" % ally.player_name)
	# Level sync: everyone in the party comes in one level below the hero.
	for ally in hero.party:
		if is_instance_valid(ally):
			ally.sync_to_level(int(hero.get("level")) - 1)
	GameState.emit_signal("party_changed")
	vault = (load(VAULT_SCENE) as PackedScene).instantiate()
	vault.position = VAULT_ORIGIN
	get_parent().add_child(vault)
	var entrance := VAULT_ORIGIN + ENTRANCE_OFFSET
	hero.global_position = entrance
	hero.wander_target = entrance
	hero.travel_destination_id = ""
	var slot := 0
	for ally in hero.party:
		if is_instance_valid(ally) and not ally.is_dead:
			ally.global_position = entrance + Vector2(-30.0, -60.0 + 30.0 * float(slot))
			slot += 1
	GameState.in_dungeon = true
	running = true
	run_time_s = 0.0
	clear_timer_s = -1.0
	GameState.log_event("The party enters the Hollowed Vault")
	GameState.emit_signal("dungeon_event", "enter", "Hollowed Vault")
	return true

func _physics_process(delta: float) -> void:
	if not running:
		return
	run_time_s += delta
	if clear_timer_s >= 0.0:
		# Once the final boss is down the run is a clear, whatever happens next.
		clear_timer_s -= delta
		if clear_timer_s <= 0.0:
			_end_run("cleared")
	elif not is_instance_valid(hero) or bool(hero.get("is_dead")):
		_end_run("failed")
	elif run_time_s >= RUN_TIMEOUT_S:
		_end_run("timeout")

func _on_enemy_died(enemy: Node2D) -> void:
	if running and clear_timer_s < 0.0 and is_instance_valid(enemy) and enemy.is_in_group("dungeon_final"):
		clear_timer_s = CLEAR_DELAY_S
		if is_instance_valid(hero):
			hero.grant_dungeon_reward(CLEAR_BONUS_XP, CLEAR_BONUS_GOLD)
		GameState.log_event("The Hollow King falls: dungeon cleared!")
		# The add phase's wraiths must not keep fighting (or block the loot walk).
		for other in get_tree().get_nodes_in_group("dungeon_enemies"):
			if is_instance_valid(other) and other != enemy:
				other.queue_free()

func _end_run(result: String) -> void:
	running = false
	for enemy in get_tree().get_nodes_in_group("dungeon_enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	var leftover_spot := gate_position + Vector2(0.0, 60.0)
	for item in get_tree().get_nodes_in_group("items"):
		# Drops nobody picked up move to the gate instead of vanishing.
		if is_instance_valid(item) and item.global_position.x > LEFTOVER_ITEM_X:
			item.global_position = leftover_spot + Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
	if is_instance_valid(vault):
		vault.queue_free()
	GameState.in_dungeon = false
	var home := gate_position + Vector2(0.0, 60.0)
	if is_instance_valid(hero):
		if not bool(hero.get("is_dead")):
			hero.global_position = home
			hero.wander_target = home
		hero.dungeon_cooldown_until_ms = float(hero.get("game_time_ms")) + hero.DUNGEON_COOLDOWN_MS
		var slot := 0
		for ally in hero.party.duplicate():
			if not is_instance_valid(ally):
				continue
			if pulled.has(ally):
				hero.party.erase(ally)
				ally.group_leader = null
				ally.global_position = ally.spawn_position
			elif not ally.is_dead:
				ally.global_position = home + Vector2(-30.0, -30.0 + 30.0 * float(slot))
				slot += 1
	pulled.clear()
	GameState.emit_signal("party_changed")
	if result == "cleared":
		# Announced on the way out, after the boss's own VICTORY banner has faded.
		GameState.emit_signal("dungeon_event", "clear", "Hollowed Vault")
	else:
		GameState.log_event("The dungeon run ended (%s)" % result)
		GameState.emit_signal("dungeon_event", "fail", "Hollowed Vault")
	GameState.emit_signal("dungeon_finished", result, run_time_s)
