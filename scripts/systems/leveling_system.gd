class_name LevelingSystem
extends RefCounted

## Cumulative XP required to REACH levels 2-10 (index 0 = threshold for level 2, etc).
const XP_THRESHOLDS := [100, 250, 450, 700, 1000, 1400, 1900, 2500, 3200]
const MAX_LEVEL := 10
const HP_PER_LEVEL := 10
const DAMAGE_PER_LEVEL := 2

## Applies xp_gained (expected >= 0) to a character currently at current_level/current_xp.
## current_level is clamped to [1, MAX_LEVEL] defensively. Returns a Dictionary with keys:
## level (int), xp (int), leveled_up (bool), hp_bonus (int), damage_bonus (int) — the last
## two are the TOTAL bonus earned by however many levels were gained in this single call.
static func apply_xp(current_level: int, current_xp: int, xp_gained: int) -> Dictionary:
	var starting_level: int = clampi(current_level, 1, MAX_LEVEL)
	var level: int = starting_level
	var xp: int = maxi(0, current_xp + xp_gained)
	while level < MAX_LEVEL and xp >= XP_THRESHOLDS[level - 1]:
		level += 1
	var levels_gained: int = level - starting_level
	return {
		"level": level,
		"xp": xp,
		"leveled_up": levels_gained > 0,
		"hp_bonus": levels_gained * HP_PER_LEVEL,
		"damage_bonus": levels_gained * DAMAGE_PER_LEVEL,
	}

## Returns the cumulative XP required to reach the NEXT level after `level`, or -1 if
## `level` is already at or above MAX_LEVEL (or invalid). Use this instead of indexing
## XP_THRESHOLDS directly to avoid off-by-one/out-of-bounds mistakes.
static func get_next_threshold(level: int) -> int:
	if level < 1 or level >= MAX_LEVEL:
		return -1
	return XP_THRESHOLDS[level - 1]
