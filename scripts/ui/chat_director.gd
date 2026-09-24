extends Node

## Decides who speaks and when. Gameplay code emits GameState.chat_event;
## this picks a speaker, applies ChatPolicy's probability and cooldowns, builds
## the text with ChatLines and emits GameState.chat_message. It also fires an
## occasional "ambient" zone line. All timing uses its own game clock, so it
## follows the speed control.

const NEVER_MS := -1000000000.0

var game_time_ms: float = 0.0
var last_global_ms: float = NEVER_MS
var last_spoke_ms: Dictionary = {}
var next_ambient_ms: float = 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	next_ambient_ms = ChatPolicy.next_ambient_delay_ms(rng.randf())
	GameState.chat_event.connect(_on_chat_event)
	# The character recruits its starting party in its own _ready, before this
	# node exists, so those greetings are replayed once everything is ready.
	_greet_existing_party.call_deferred()

func _process(delta: float) -> void:
	game_time_ms += delta * 1000.0
	if game_time_ms >= next_ambient_ms:
		next_ambient_ms = game_time_ms + ChatPolicy.next_ambient_delay_ms(rng.randf())
		_on_chat_event("ambient", {})

func _greet_existing_party() -> void:
	var leader = GameState.character
	if leader == null or not is_instance_valid(leader):
		return
	for member in leader.party:
		_on_chat_event("ally_joined", {"ally": member})

func _on_chat_event(event: String, context: Dictionary) -> void:
	if not ChatPolicy.should_fire(event, rng.randf()):
		return
	var leader = GameState.character
	if leader == null or not is_instance_valid(leader):
		return
	var speaker = _pick_speaker(event, context, leader)
	if speaker == null:
		return
	var speaker_name: String = speaker.player_name
	var last_speaker_ms := float(last_spoke_ms.get(speaker_name, NEVER_MS))
	if not ChatPolicy.can_speak(event, game_time_ms, last_global_ms, last_speaker_ms):
		return
	var zone_name := String(ZoneTable.ZONES[leader.current_zone_id]["name"])
	var text := ChatLines.pick(event, rng, {
		"leader": leader.character_name,
		"ally": speaker_name,
		"enemy": context.get("enemy", ""),
		"item": context.get("item", ""),
		"zone": context.get("zone", zone_name),
		"level": context.get("level", ""),
	})
	if text == "":
		return
	last_global_ms = game_time_ms
	last_spoke_ms[speaker_name] = game_time_ms
	GameState.emit_signal("chat_message", _channel_for(event, speaker), speaker_name, text)

## The ally who says the line, or null if nobody can.
func _pick_speaker(event: String, context: Dictionary, leader: Node2D) -> Node:
	match event:
		"ally_joined", "ally_level_up", "ally_died":
			var ally = context.get("ally", null)
			if ally != null and is_instance_valid(ally):
				return ally
			return null
		"ambient":
			var candidates: Array = []
			for sp in get_tree().get_nodes_in_group("simulated_players"):
				if is_instance_valid(sp) and sp.group_leader == null and not sp.is_dead \
						and sp.home_zone_id == leader.current_zone_id:
					candidates.append(sp)
			return _random_of(candidates)
		_:
			var living: Array = []
			for member in leader.party:
				if is_instance_valid(member) and not member.is_dead:
					living.append(member)
			return _random_of(living)

func _random_of(nodes: Array) -> Node:
	if nodes.is_empty():
		return null
	return nodes[rng.randi_range(0, nodes.size() - 1)]

func _channel_for(event: String, speaker: Node) -> String:
	if event == "ambient":
		return "zone"
	if event in ["ally_level_up", "ally_died"] and speaker.group_leader == null:
		return "zone"
	return "party"
