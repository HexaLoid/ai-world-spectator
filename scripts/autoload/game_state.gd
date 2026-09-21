extends Node

## Emitted whenever the AI-controlled character transitions to a new behavior
## state (e.g. "idle", "attacking", "fleeing"); new_state is the state name.
signal character_state_changed(new_state: String)
## Emitted whenever the character's HP changes; hp and max_hp are the
## current and maximum health values, for the unit frame to update.
signal character_hp_changed(hp: int, max_hp: int)
## Emitted whenever the character's XP total changes; xp is the new total.
signal character_xp_changed(xp: int)
## Emitted when the character gains a level; level is the new level reached.
signal character_leveled_up(level: int)
## Emitted whenever the character's equipped weapon or armor changes;
## weapon_id and armor_id identify the currently equipped items.
signal character_equipment_changed(weapon_id: String, armor_id: String)
## Emitted for every logged activity event; message is the human-readable
## text describing what happened, for the spectator UI's activity feed.
signal activity_logged(message: String)

var character: Node2D = null
var camera: Camera2D = null

func log_event(message: String) -> void:
	activity_logged.emit(message)
	print(message)
