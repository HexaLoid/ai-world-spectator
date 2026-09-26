class_name CodexData
extends RefCounted

## Pure derived facts for the codex, computed from the static tables.

## {"guaranteed": [enemy names], "quests": [quest names],
##  "boss_bonus": [boss names], "random_from_loot_level": int} for an item.
## `boss_bonus` lists (in EnemyTable order) the bosses that can drop an epic
## item as an extra bonus: bosses whose loot_level covers the item's level_req,
## excluding a boss's own guaranteed drop; always empty for non-epics. Dungeon
## epics list only dungeon bosses, open-world epics only open-world bosses. `random_from_loot_level` is the
## lowest enemy loot_level at which the item can drop randomly, or -1 when it
## never drops randomly (epic items, or nothing has a high enough loot level).
static func item_sources(item_id: String) -> Dictionary:
	var result := {"guaranteed": [], "quests": [], "boss_bonus": [], "random_from_loot_level": -1}
	var item: Dictionary = LootTable.ITEMS.get(item_id, {})
	if item.is_empty():
		return result
	for enemy_id in EnemyTable.ENEMIES:
		var def: Dictionary = EnemyTable.ENEMIES[enemy_id]
		if def.get("guaranteed_drop", "") == item_id:
			result["guaranteed"].append(def["name"])
	for quest in QuestTable.QUESTS:
		if quest.get("item_reward", "") == item_id:
			result["quests"].append(quest["name"])
	if item.get("rarity", "") == "epic":
		var level_req := int(item.get("level_req", 1))
		for enemy_id in EnemyTable.ENEMIES:
			var boss: Dictionary = EnemyTable.ENEMIES[enemy_id]
			var own_drop: String = boss.get("guaranteed_drop", "")
			var boss_in_dungeon := bool(ZoneTable.ZONES.get(boss.get("zone", ""), {}).get("instanced", false))
			if boss_in_dungeon != bool(item.get("dungeon", false)):
				continue
			if own_drop != "" and own_drop != item_id and int(boss["loot_level"]) >= level_req:
				result["boss_bonus"].append(boss["name"])
	var weight := int(LootTable.RARITY_WEIGHTS.get(item.get("rarity", "common"), 0))
	if weight > 0:
		var needed := int(item.get("level_req", 1))
		var lowest := -1
		for enemy_id in EnemyTable.ENEMIES:
			var loot_level := int(EnemyTable.ENEMIES[enemy_id]["loot_level"])
			if loot_level >= needed and (lowest == -1 or loot_level < lowest):
				lowest = loot_level
		result["random_from_loot_level"] = lowest
	return result

## Enemy ids whose home zone is `zone_id`, weakest first (by max_hp, then id).
static func zone_enemy_ids(zone_id: String) -> Array:
	var ids: Array = []
	for enemy_id in EnemyTable.ENEMIES:
		if EnemyTable.ENEMIES[enemy_id].get("zone", "") == zone_id:
			ids.append(enemy_id)
	ids.sort_custom(_enemy_before)
	return ids

## The strongest enemy in the zone that has a guaranteed drop, or "".
static func zone_boss_id(zone_id: String) -> String:
	var boss := ""
	for enemy_id in zone_enemy_ids(zone_id):
		if EnemyTable.ENEMIES[enemy_id].get("guaranteed_drop", "") != "":
			boss = enemy_id  # ids are weakest-first, so the last match is the strongest
	return boss

## [first level, last level] the zone is aimed at: its min_level up to one
## below the next zone's min_level (at least the same level), or the level cap
## for the last zone in the travel order.
static func zone_level_range(zone_id: String) -> Array:
	var low := int(ZoneTable.ZONES.get(zone_id, {}).get("min_level", 1))
	var index := ZoneTable.TRAVEL_ORDER.find(zone_id)
	var high := LevelingSystem.MAX_LEVEL
	if index >= 0 and index + 1 < ZoneTable.TRAVEL_ORDER.size():
		var next_min := int(ZoneTable.ZONES[ZoneTable.TRAVEL_ORDER[index + 1]].get("min_level", 1))
		high = maxi(low, next_min - 1)
	return [low, high]

static func zone_order() -> Array:
	return ZoneTable.all_zone_order()

## Every enemy id: by zone in display order (travel loop, then dungeons), then weakest first.
static func enemy_order() -> Array:
	var ids: Array = []
	for zone_id in ZoneTable.all_zone_order():
		ids.append_array(zone_enemy_ids(zone_id))
	return ids

## Every item id: by slot (LootTable.SLOTS order), consumables last, then by
## level requirement, then id.
static func item_order() -> Array:
	var ids: Array = LootTable.ITEMS.keys()
	ids.sort_custom(_item_before)
	return ids

static func _enemy_before(a: String, b: String) -> bool:
	var hp_a := int(EnemyTable.ENEMIES[a]["max_hp"])
	var hp_b := int(EnemyTable.ENEMIES[b]["max_hp"])
	if hp_a != hp_b:
		return hp_a < hp_b
	return a < b

static func _item_before(a: String, b: String) -> bool:
	var slot_a := _slot_rank(a)
	var slot_b := _slot_rank(b)
	if slot_a != slot_b:
		return slot_a < slot_b
	var level_a := int(LootTable.ITEMS[a].get("level_req", 1))
	var level_b := int(LootTable.ITEMS[b].get("level_req", 1))
	if level_a != level_b:
		return level_a < level_b
	return a < b

static func _slot_rank(item_id: String) -> int:
	var slot: String = LootTable.ITEMS[item_id].get("slot", "")
	var rank := LootTable.SLOTS.find(slot)
	return rank if rank >= 0 else LootTable.SLOTS.size()
