class_name LootTable
extends RefCounted

## Static item definitions. Each entry's "type" is "weapon", "armor",
## "trinket", or "consumable"; weapons carry a "damage" stat, armor carries
## a "max_hp" stat, trinkets carry a "crit_chance" stat (0.0-1.0, chance an
## attack doubles its damage), consumables carry a "heal" amount. "rarity"
## (common/uncommon/rare/epic) drives RARITY_COLORS for HUD display and
## RARITY_WEIGHTS for how often roll_drop() picks it. Callers read these
## fields directly (see Character._acquire_item).
const ITEMS := {
	"rusty_sword": {"type": "weapon", "damage": 4, "rarity": "common", "icon": "res://assets/icons/sword_rusty_icon.png"},
	"iron_sword": {"type": "weapon", "damage": 7, "rarity": "uncommon", "icon": "res://assets/icons/sword_iron_icon.png"},
	"steel_sword": {"type": "weapon", "damage": 11, "rarity": "rare", "icon": "res://assets/icons/steel_sword_icon.png"},
	"warlords_greatsword": {"type": "weapon", "damage": 18, "rarity": "epic", "icon": "res://assets/icons/warlords_greatsword_icon.png"},
	"leather_armor": {"type": "armor", "max_hp": 15, "rarity": "common", "icon": "res://assets/icons/armor_icon.png"},
	"chainmail_armor": {"type": "armor", "max_hp": 25, "rarity": "rare", "icon": "res://assets/icons/chainmail_armor_icon.png"},
	"champions_plate": {"type": "armor", "max_hp": 40, "rarity": "epic", "icon": "res://assets/icons/champions_plate_icon.png"},
	"lucky_charm": {"type": "trinket", "crit_chance": 0.05, "rarity": "common", "icon": "res://assets/icons/lucky_charm_icon.png"},
	"ring_of_fortune": {"type": "trinket", "crit_chance": 0.12, "rarity": "rare", "icon": "res://assets/icons/ring_of_fortune_icon.png"},
	"amulet_of_wrath": {"type": "trinket", "crit_chance": 0.20, "rarity": "epic", "icon": "res://assets/icons/amulet_of_wrath_icon.png"},
	"health_potion": {"type": "consumable", "heal": 20, "rarity": "common", "icon": "res://assets/icons/potion_icon.png"},
}

## Relative weight of each rarity tier in roll_drop()'s random pool. Epic
## items have weight 0 — they never drop randomly, only as a guaranteed
## elite/boss drop (Enemy.guaranteed_drop_id) or a quest reward, so finding
## one is always a specific, deliberate moment rather than a lucky roll.
const RARITY_WEIGHTS := {
	"common": 10,
	"uncommon": 4,
	"rare": 1,
	"epic": 0,
}

## Display color for each rarity tier, used by the HUD's equipment labels.
const RARITY_COLORS := {
	"common": Color(0.82, 0.82, 0.82, 1.0),
	"uncommon": Color(0.25, 0.78, 0.25, 1.0),
	"rare": Color(0.25, 0.55, 0.95, 1.0),
	"epic": Color(0.68, 0.32, 0.95, 1.0),
}

## Picks a random item key from ITEMS using the given rng, weighted by
## RARITY_WEIGHTS (so epic items, at weight 0, are never picked here).
static func roll_drop(rng: RandomNumberGenerator) -> String:
	var total_weight := 0
	for item_id in ITEMS:
		total_weight += int(RARITY_WEIGHTS.get(ITEMS[item_id].get("rarity", "common"), 0))
	var roll := rng.randi_range(1, max(total_weight, 1))
	var cumulative := 0
	for item_id in ITEMS:
		cumulative += int(RARITY_WEIGHTS.get(ITEMS[item_id].get("rarity", "common"), 0))
		if roll <= cumulative:
			return item_id
	return ITEMS.keys()[0]

## Returns true if candidate_item_id should replace whatever is currently in
## equipped_item_id's slot. IMPORTANT: callers must only compare items within the
## SAME equipment slot (weapon vs weapon, armor vs armor, trinket vs trinket) —
## this function assumes that and never mixes slots itself. Consumables never
## "equip" (always false). An empty equipped_item_id (empty slot) always accepts
## a valid non-consumable candidate. Unknown/malformed item ids fail closed
## (return false) rather than erroring — every lookup here goes through
## Dictionary.get() with a safe default.
static func should_equip(equipped_item_id: String, candidate_item_id: String) -> bool:
	var candidate: Dictionary = ITEMS.get(candidate_item_id, {})
	if candidate.is_empty():
		return false
	var candidate_type: String = candidate.get("type", "")
	if candidate_type == "consumable":
		return false
	if equipped_item_id == "":
		return true
	var equipped: Dictionary = ITEMS.get(equipped_item_id, {})
	if equipped.get("type", "") != candidate_type:
		return false
	var stat_key := _stat_key_for_type(candidate_type)
	return candidate.get(stat_key, 0) > equipped.get(stat_key, 0)

static func _stat_key_for_type(item_type: String) -> String:
	match item_type:
		"weapon":
			return "damage"
		"trinket":
			return "crit_chance"
		_:
			return "max_hp"
