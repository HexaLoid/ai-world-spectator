class_name JobSwitch
extends RefCounted

## Pure rules for the hero's job changes: the level a job starts at, the gear
## it inherits, when a change is due and which job comes next.

## A job's level is at most this many levels below the best job when first taken.
const CATCH_UP_GAP := 2
## "loop" trigger: some other job is at least this many levels below the active one.
const LOOP_GAP := 2
## A trait's preferred job is only used within this many levels of the lowest.
const NUDGE_WINDOW := 2

static func catch_up_level(levels: Dictionary) -> int:
	var best := 1
	for id in levels.keys():
		best = maxi(best, int(levels[id]))
	return maxi(1, best - CATCH_UP_GAP)

## Cumulative XP a job has on reaching `level` (0 at level 1).
static func starting_xp(level: int) -> int:
	if level <= 1:
		return 0
	return int(LevelingSystem.XP_THRESHOLDS[mini(level, LevelingSystem.MAX_LEVEL) - 2])

## The outgoing gear set filtered to items usable at `level` (a copy).
static func inherit_equipment(equipment: Dictionary, level: int) -> Dictionary:
	var result := {}
	for slot in equipment.keys():
		var item_id := String(equipment[slot])
		if item_id != "" and ItemScoring.meets_level(item_id, level):
			result[slot] = item_id
	return result

## `reason` is "cap" (the active job is at the level cap) or "loop" (arrived in
## the meadow on the zone loop). `other_levels` are the levels of every other
## job, untaken jobs counted as 1.
static func switch_due(active_level: int, other_levels: Array, reason: String) -> bool:
	if reason == "cap":
		if active_level < LevelingSystem.MAX_LEVEL:
			return false
		for level in other_levels:
			if int(level) < LevelingSystem.MAX_LEVEL:
				return true
		return false
	if reason == "loop":
		for level in other_levels:
			if int(level) <= active_level - LOOP_GAP:
				return true
		return false
	return false

## The next job, or "" when every other job is at the cap. `levels` maps the
## jobs taken so far to their level (missing jobs count as level 1); `roll`
## (0..1) picks deterministically inside the candidate pool.
static func pick_next_job(active_id: String, levels: Dictionary, trait_id: String, roll: float, job_ids: Array = AbilityTable.JOB_ORDER) -> String:
	var candidates: Array = []
	var lowest := LevelingSystem.MAX_LEVEL + 1
	for id in job_ids:
		if id == active_id:
			continue
		var level := int(levels.get(id, 1))
		if level >= LevelingSystem.MAX_LEVEL:
			continue
		candidates.append(id)
		lowest = mini(lowest, level)
	if candidates.is_empty():
		return ""
	var pool: Array = []
	if trait_id == "explorer":
		pool = candidates
	else:
		var preferred: Array = []
		for id in candidates:
			if _prefers(trait_id, id) and int(levels.get(id, 1)) <= lowest + NUDGE_WINDOW:
				preferred.append(id)
		if not preferred.is_empty():
			var preferred_lowest := LevelingSystem.MAX_LEVEL + 1
			for id in preferred:
				preferred_lowest = mini(preferred_lowest, int(levels.get(id, 1)))
			for id in preferred:
				if int(levels.get(id, 1)) == preferred_lowest:
					pool.append(id)
		else:
			for id in candidates:
				if int(levels.get(id, 1)) == lowest:
					pool.append(id)
	var index := mini(int(clampf(roll, 0.0, 0.999999) * float(pool.size())), pool.size() - 1)
	return String(pool[index])

static func _prefers(trait_id: String, job_id: String) -> bool:
	var role := String(AbilityTable.CLASSES.get(job_id, {}).get("role", ""))
	match trait_id:
		"cautious":
			return role == "tank" or role == "healer"
		"reckless":
			return role == "melee" or role == "magic"
		"greedy":
			return job_id == "thief"
	return false
