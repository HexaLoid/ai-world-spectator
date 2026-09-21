class_name LevelingSystem
extends RefCounted

const XP_THRESHOLDS := [100, 250, 450, 700]
const MAX_LEVEL := 5
const HP_PER_LEVEL := 10
const DAMAGE_PER_LEVEL := 2

static func apply_xp(current_level: int, current_xp: int, xp_gained: int) -> Dictionary:
	var xp: int = current_xp + xp_gained
	var level: int = current_level
	while level < MAX_LEVEL and xp >= XP_THRESHOLDS[level - 1]:
		level += 1
	var levels_gained: int = level - current_level
	return {
		"level": level,
		"xp": xp,
		"leveled_up": levels_gained > 0,
		"hp_bonus": levels_gained * HP_PER_LEVEL,
		"damage_bonus": levels_gained * DAMAGE_PER_LEVEL,
	}
