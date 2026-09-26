class_name JobState
extends RefCounted

## One job's progress for the hero: level, cumulative XP and its own gear set.

var level: int = 1
var xp: int = 0
var equipment: Dictionary = {}

static func create(new_level: int, new_xp: int, new_equipment: Dictionary) -> JobState:
	var state := JobState.new()
	state.level = new_level
	state.xp = new_xp
	state.equipment = new_equipment.duplicate()
	return state

func duplicate() -> JobState:
	return JobState.create(level, xp, equipment)
