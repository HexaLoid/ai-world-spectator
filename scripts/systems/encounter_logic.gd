class_name EncounterLogic
extends RefCounted

## Timing and numbers for the dungeon boss mechanics (see BossMechanics).
const HEAVY_INTERVAL_MS := 9000.0
const HEAVY_WINDUP_MS := 1500.0
const HEAVY_MULT := 2.5
const ADD_PHASE_HP := 0.5
const ADD_COUNT := 2

static func heavy_due(now_ms: float, next_ms: float) -> bool:
	return now_ms >= next_ms

static func heavy_damage(attack_max: int, mult: float = HEAVY_MULT) -> int:
	return roundi(float(attack_max) * mult)

static func add_phase_due(hp: int, max_hp: int, done: bool) -> bool:
	return not done and hp > 0 and float(hp) <= float(max_hp) * ADD_PHASE_HP
