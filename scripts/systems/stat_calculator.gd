class_name StatCalculator
extends RefCounted

## Pure derived-stat math. `Character` keeps base stats and an equipment
## dictionary (slot -> item id) and calls derive() whenever either changes,
## instead of applying per-item deltas.

## Each armor point shrinks incoming damage: damage * 100 / (100 + armor * ARMOR_FACTOR).
const ARMOR_FACTOR := 4.0
## Each point of the class's primary stat (strength/intellect) adds this
## fraction to weapon damage.
const PRIMARY_STAT_DAMAGE_PER_POINT := 0.01

## Sums every equipped item's stats: {stat_key: total}. Unknown ids and
## empty ("") slots contribute nothing.
static func gear_totals(equipment: Dictionary) -> Dictionary:
	var totals := {}
	for slot in equipment:
		var stats: Dictionary = LootTable.ITEMS.get(equipment[slot], {}).get("stats", {})
		for stat in stats:
			totals[stat] = float(totals.get(stat, 0.0)) + float(stats[stat])
	return totals

## `base` has max_hp, damage_min, damage_max, crit_chance (the character's
## own stats before gear). Returns {max_hp, damage_min, damage_max,
## crit_chance, armor} with equipment and the class's primary stat applied.
static func derive(base: Dictionary, equipment: Dictionary, class_def: Dictionary) -> Dictionary:
	var gear := gear_totals(equipment)
	var primary: String = class_def.get("primary_stat", "")
	var damage_multiplier := 1.0
	if primary != "":
		damage_multiplier += float(gear.get(primary, 0.0)) * PRIMARY_STAT_DAMAGE_PER_POINT
	var gear_damage := float(gear.get("damage", 0.0))
	return {
		"max_hp": int(base["max_hp"]) + int(class_def.get("bonus_max_hp", 0)) + roundi(float(gear.get("max_hp", 0.0))),
		"damage_min": roundi((float(base["damage_min"]) + gear_damage) * damage_multiplier),
		"damage_max": roundi((float(base["damage_max"]) + gear_damage) * damage_multiplier),
		"crit_chance": float(base["crit_chance"]) + float(class_def.get("bonus_crit_chance", 0.0)) + float(gear.get("crit_chance", 0.0)),
		"armor": int(class_def.get("bonus_armor", 0)) + roundi(float(gear.get("armor", 0.0))),
	}

## Damage actually taken after armor. Zero stays zero; any positive damage
## deals at least 1 so enemies can always hurt the character.
static func mitigate(damage: int, armor: int) -> int:
	if damage <= 0:
		return 0
	return maxi(1, roundi(float(damage) * 100.0 / (100.0 + float(armor) * ARMOR_FACTOR)))
