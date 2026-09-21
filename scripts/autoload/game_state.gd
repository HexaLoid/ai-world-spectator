extends Node

signal character_state_changed(new_state: String)
signal character_hp_changed(hp: int, max_hp: int)
signal character_xp_changed(xp: int)
signal character_leveled_up(level: int)
signal character_equipment_changed(weapon_id: String, armor_id: String)
signal activity_logged(message: String)

var character: Node2D = null
var camera: Camera2D = null

func log_event(message: String) -> void:
	emit_signal("activity_logged", message)
	print(message)
