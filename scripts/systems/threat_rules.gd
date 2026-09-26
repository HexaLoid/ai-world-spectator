class_name ThreatRules
extends RefCounted

## Who an enemy attacks inside a dungeon: a tank within TANK_PULL_MULT x the
## enemy's aggro range beats a nearer non-tank; otherwise the nearest wins.
## `candidates` is an array of {"dist": float, "is_tank": bool}; returns an
## index or -1 for none.
const TANK_PULL_MULT := 1.3

static func pick_target(candidates: Array, aggro_range: float) -> int:
	var nearest := -1
	var nearest_dist := INF
	var tank := -1
	var tank_dist := INF
	for i in range(candidates.size()):
		var dist := float(candidates[i]["dist"])
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = i
		if bool(candidates[i]["is_tank"]) and dist <= aggro_range * TANK_PULL_MULT and dist < tank_dist:
			tank_dist = dist
			tank = i
	return tank if tank >= 0 else nearest
