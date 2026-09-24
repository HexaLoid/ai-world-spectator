class_name ItemScoring
extends RefCounted

## Pure equip-decision rules. Every function takes item ids and a class
## definition (an AbilityTable.CLASSES entry) and reads LootTable.ITEMS;
## nothing here touches nodes, so it is all unit-tested headlessly.

## Class-weighted value of an item: sum of (stat value * the class's weight
## for that stat). Unknown items and empty ids ("" = empty slot) score 0.
static func score(item_id: String, class_def: Dictionary) -> float:
	var stats: Dictionary = LootTable.ITEMS.get(item_id, {}).get("stats", {})
	var weights: Dictionary = class_def.get("stat_weights", {})
	var total := 0.0
	for stat in stats:
		total += float(stats[stat]) * float(weights.get(stat, 0.0))
	return total

static func meets_level(item_id: String, level: int) -> bool:
	return level >= int(LootTable.ITEMS.get(item_id, {}).get("level_req", 1))

## True if `candidate_id` should replace `current_id` ("" for an empty slot)
## in its slot: it must be a real gear item, the character must meet its
## level requirement, and it must score strictly higher. Callers pass the
## item currently in the CANDIDATE'S slot. Unknown/malformed items and
## consumables (no slot) fail closed.
static func is_upgrade(current_id: String, candidate_id: String, class_def: Dictionary, level: int) -> bool:
	var candidate: Dictionary = LootTable.ITEMS.get(candidate_id, {})
	if not LootTable.SLOTS.has(candidate.get("slot", "")):
		return false
	if not meets_level(candidate_id, level):
		return false
	return score(candidate_id, class_def) > score(current_id, class_def)

## "+2 armor, +10 HP" style text for logs and tooltips; "" if the item has no stats.
static func describe_stats(item_id: String) -> String:
	var stats: Dictionary = LootTable.ITEMS.get(item_id, {}).get("stats", {})
	var parts: Array[String] = []
	for stat in LootTable.STAT_ORDER:
		if not stats.has(stat):
			continue
		var value := float(stats[stat])
		if stat == "crit_chance":
			parts.append("+%d%% %s" % [roundi(value * 100.0), LootTable.STAT_LABELS[stat]])
		else:
			parts.append("+%d %s" % [roundi(value), LootTable.STAT_LABELS[stat]])
	return ", ".join(parts)
