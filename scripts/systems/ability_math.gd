class_name AbilityMath
extends RefCounted

## Pure numbers behind the job abilities (no nodes), so they are unit-tested.

## How many times a `melee_hit` ability strikes (default 1, never below 1).
static func hit_count(def: Dictionary) -> int:
	return maxi(1, int(def.get("hit_count", 1)))

## Damage multiplier of the hit that lands after a `gap_closer` jump; 0 = no hit.
static func jump_multiplier(def: Dictionary) -> float:
	return float(def.get("damage_multiplier", 0.0))

## Index of the member with the lowest HP fraction that is below `below`, or -1.
## Members with 0 HP (dead) or a max HP of 0 are skipped.
static func pick_heal_target(hps: Array, max_hps: Array, below: float) -> int:
	var best := -1
	var best_fraction := below
	for i in range(mini(hps.size(), max_hps.size())):
		var hp := int(hps[i])
		var max_hp := int(max_hps[i])
		if hp <= 0 or max_hp <= 0:
			continue
		var fraction := float(hp) / float(max_hp)
		if fraction < best_fraction:
			best_fraction = fraction
			best = i
	return best

## HP restored by a heal worth `percent` of `max_hp` (at least 1).
static func heal_amount(max_hp: int, percent: float) -> int:
	return maxi(1, roundi(float(max_hp) * percent))
