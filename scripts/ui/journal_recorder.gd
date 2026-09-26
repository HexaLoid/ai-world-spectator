class_name JournalRecorder
extends Node

## Turns game signals into journal milestones. Pure bookkeeping: touches no
## gameplay state.

func _ready() -> void:
	var c = GameState.character
	if c != null and is_instance_valid(c):
		_add("start", "Set out from %s" % ZoneTable.ZONES[c.current_zone_id]["name"])
		_add("zone", "First visit to %s" % ZoneTable.ZONES[c.current_zone_id]["name"])
	GameState.zone_changed.connect(_on_zone_changed)
	GameState.boss_event.connect(_on_boss_event)
	GameState.character_leveled_up.connect(func(level: int): _add("level", "Reached level %d" % level))
	GameState.item_acquired.connect(_on_item_acquired)
	GameState.quest_completed.connect(func(quest_name: String): _add("quest", "Completed %s" % quest_name))
	GameState.death_recap.connect(_on_death)

func _add(kind: String, text: String) -> void:
	var c = GameState.character
	var t_ms: float = c.game_time_ms if c != null and is_instance_valid(c) else 0.0
	GameState.record_journal(t_ms, kind, text)

func _on_zone_changed(zone_id: String) -> void:
	var text := "First visit to %s" % ZoneTable.ZONES[zone_id]["name"]
	if not GameState.journal.has_kind_text("zone", text):
		_add("zone", text)

func _on_boss_event(kind: String, boss_name: String) -> void:
	match kind:
		"engaged":
			var text := "Faced %s" % boss_name
			if not GameState.journal.has_kind_text("boss", text):
				_add("boss", text)
		"victory":
			_add("boss", "Defeated %s" % boss_name)
		"fled":
			_add("boss", "Fled from %s" % boss_name)

func _on_item_acquired(item_name: String, rarity: String) -> void:
	if rarity == "epic":
		_add("loot", "Found the epic %s" % item_name)

func _on_death(info: Dictionary) -> void:
	var killer := String(info.get("killer", ""))
	if killer == "":
		killer = "an unseen foe"
	_add("death", "Died to %s at level %d" % [killer, int(info.get("level", 1))])
