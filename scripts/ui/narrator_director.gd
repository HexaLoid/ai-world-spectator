class_name NarratorDirector
extends Node

## Speaks story lines (NarratorLines) into the Story chat channel for key
## moments. Global cooldown on its own game clock (follows the speed control).

const COOLDOWN_MS := 4000.0
const NEVER_MS := -1000000000.0

var game_time_ms: float = 0.0
var last_line_ms: float = NEVER_MS
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	GameState.zone_changed.connect(func(zone_id: String): _say("zone_arrive", {"zone": String(ZoneTable.ZONES[zone_id]["name"])}))
	GameState.boss_event.connect(_on_boss_event)
	GameState.character_leveled_up.connect(func(level: int): _say("level_up", {"level": level}))
	GameState.item_acquired.connect(func(item_name: String, rarity: String):
		if rarity == "epic":
			_say("epic_loot", {"item": item_name}))
	GameState.chat_event.connect(func(event: String, _context: Dictionary):
		if event == "leader_low_hp":
			_say("low_hp", {}))
	GameState.death_recap.connect(func(info: Dictionary): _say("death", {"killer": String(info.get("killer", ""))}))
	GameState.quest_completed.connect(func(quest_name: String): _say("quest_done", {"quest": quest_name}))

func _process(delta: float) -> void:
	game_time_ms += delta * 1000.0

func _on_boss_event(kind: String, boss_name: String) -> void:
	var event := ""
	match kind:
		"engaged": event = "boss_engaged"
		"victory": event = "boss_victory"
		"fled": event = "boss_fled"
		"defeated": event = "boss_defeated"
	if event != "":
		_say(event, {"boss": boss_name})

func _say(event: String, context: Dictionary) -> void:
	var leader = GameState.character
	if leader == null or not is_instance_valid(leader):
		return
	if game_time_ms - last_line_ms < COOLDOWN_MS:
		return
	var ctx := context.duplicate()
	ctx["name"] = leader.character_name
	var line := NarratorLines.line_for(event, leader.character_trait, ctx, rng.randf())
	if line == "":
		return
	last_line_ms = game_time_ms
	GameState.emit_signal("chat_message", "story", "Narrator", line)
