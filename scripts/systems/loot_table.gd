class_name LootTable
extends RefCounted

## Equipment slots, in HUD display order.
const SLOTS := ["weapon", "offhand", "head", "chest", "neck", "ring"]

## Display names for each slot (HUD tooltips).
const SLOT_LABELS := {
	"weapon": "Weapon", "offhand": "Off-hand", "head": "Head",
	"chest": "Chest", "neck": "Neck", "ring": "Ring",
}

## Stat keys an item's "stats" dictionary may use, in the order they are
## listed in text ("+7 damage, +2 STR"), with their short display labels.
const STAT_ORDER := ["damage", "armor", "max_hp", "crit_chance", "strength", "intellect"]
const STAT_LABELS := {
	"damage": "damage", "armor": "armor", "max_hp": "HP",
	"crit_chance": "crit", "strength": "STR", "intellect": "INT",
}

## Static item definitions. Gear entries have "slot" (one of SLOTS), "rarity"
## (common/uncommon/rare/epic — drives RARITY_COLORS and RARITY_WEIGHTS),
## "level_req", "icon", and a "stats" dictionary using STAT_LABELS keys
## ("crit_chance" is a 0.0-1.0 fraction). Consumables have "type":
## "consumable" and a "heal" amount, and no slot. Equip decisions live in
## ItemScoring; derived-stat math lives in StatCalculator.
const ITEMS := {
	# Weapons
	"rusty_sword": {"slot": "weapon", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/sword_rusty_icon.png", "stats": {"damage": 4}},
	"iron_sword": {"slot": "weapon", "rarity": "uncommon", "level_req": 1, "icon": "res://assets/icons/sword_iron_icon.png", "stats": {"damage": 7}},
	"steel_sword": {"slot": "weapon", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/steel_sword_icon.png", "stats": {"damage": 11, "strength": 2}},
	"warlords_greatsword": {"slot": "weapon", "rarity": "epic", "level_req": 3, "icon": "res://assets/icons/warlords_greatsword_icon.png", "stats": {"damage": 18, "strength": 4}},
	"apprentice_staff": {"slot": "weapon", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/apprentice_staff_icon.png", "stats": {"damage": 3, "intellect": 2}},
	"oak_staff": {"slot": "weapon", "rarity": "uncommon", "level_req": 2, "icon": "res://assets/icons/oak_staff_icon.png", "stats": {"damage": 5, "intellect": 4}},
	"arcane_staff": {"slot": "weapon", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/arcane_staff_icon.png", "stats": {"damage": 8, "intellect": 7}},
	"tempered_sword": {"slot": "weapon", "rarity": "rare", "level_req": 5, "icon": "res://assets/icons/tempered_sword_icon.png", "stats": {"damage": 15, "strength": 3}},
	"mirewood_staff": {"slot": "weapon", "rarity": "rare", "level_req": 5, "icon": "res://assets/icons/mirewood_staff_icon.png", "stats": {"damage": 11, "intellect": 9}},
	"tyrants_maul": {"slot": "weapon", "rarity": "epic", "level_req": 6, "icon": "res://assets/icons/tyrants_maul_icon.png", "stats": {"damage": 20, "strength": 5, "intellect": 3}},
	"frostbrand": {"slot": "weapon", "rarity": "epic", "level_req": 8, "icon": "res://assets/icons/frostbrand_icon.png", "stats": {"damage": 24, "strength": 6}},
	"glacier_staff": {"slot": "weapon", "rarity": "epic", "level_req": 8, "icon": "res://assets/icons/glacier_staff_icon.png", "stats": {"damage": 18, "intellect": 12}},
	# Off-hand
	"wooden_shield": {"slot": "offhand", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/wooden_shield_icon.png", "stats": {"armor": 3}},
	"iron_shield": {"slot": "offhand", "rarity": "uncommon", "level_req": 2, "icon": "res://assets/icons/iron_shield_icon.png", "stats": {"armor": 5, "max_hp": 8}},
	"tower_shield": {"slot": "offhand", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/tower_shield_icon.png", "stats": {"armor": 8, "max_hp": 15, "strength": 1}},
	"bog_bulwark": {"slot": "offhand", "rarity": "rare", "level_req": 6, "icon": "res://assets/icons/bog_bulwark_icon.png", "stats": {"armor": 11, "max_hp": 20}},
	"frostguard_shield": {"slot": "offhand", "rarity": "epic", "level_req": 8, "icon": "res://assets/icons/frostguard_shield_icon.png", "stats": {"armor": 15, "max_hp": 30, "strength": 2}},
	# Head
	"leather_cap": {"slot": "head", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/leather_cap_icon.png", "stats": {"armor": 1, "max_hp": 5}},
	"iron_helm": {"slot": "head", "rarity": "uncommon", "level_req": 2, "icon": "res://assets/icons/iron_helm_icon.png", "stats": {"armor": 2, "max_hp": 10}},
	"steel_helm": {"slot": "head", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/steel_helm_icon.png", "stats": {"armor": 4, "max_hp": 15, "strength": 2}},
	"crown_of_thornfield": {"slot": "head", "rarity": "epic", "level_req": 3, "icon": "res://assets/icons/crown_of_thornfield_icon.png", "stats": {"armor": 3, "max_hp": 15, "crit_chance": 0.10, "strength": 3, "intellect": 3}},
	"marsh_helm": {"slot": "head", "rarity": "rare", "level_req": 5, "icon": "res://assets/icons/marsh_helm_icon.png", "stats": {"armor": 5, "max_hp": 20, "strength": 1}},
	"rimewatch_helm": {"slot": "head", "rarity": "rare", "level_req": 7, "icon": "res://assets/icons/rimewatch_helm_icon.png", "stats": {"armor": 7, "max_hp": 25, "strength": 3, "intellect": 3}},
	# Chest
	"leather_armor": {"slot": "chest", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/armor_icon.png", "stats": {"armor": 2, "max_hp": 15}},
	"chainmail_armor": {"slot": "chest", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/chainmail_armor_icon.png", "stats": {"armor": 5, "max_hp": 25}},
	"champions_plate": {"slot": "chest", "rarity": "epic", "level_req": 3, "icon": "res://assets/icons/champions_plate_icon.png", "stats": {"armor": 9, "max_hp": 40, "strength": 3}},
	"reinforced_mail": {"slot": "chest", "rarity": "rare", "level_req": 5, "icon": "res://assets/icons/chainmail_armor_icon.png", "stats": {"armor": 8, "max_hp": 35}},
	"glacier_plate": {"slot": "chest", "rarity": "epic", "level_req": 9, "icon": "res://assets/icons/champions_plate_icon.png", "stats": {"armor": 13, "max_hp": 55, "strength": 4, "intellect": 4}},
	# Neck
	"lucky_charm": {"slot": "neck", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/lucky_charm_icon.png", "stats": {"crit_chance": 0.05}},
	"silver_necklace": {"slot": "neck", "rarity": "uncommon", "level_req": 2, "icon": "res://assets/icons/silver_necklace_icon.png", "stats": {"max_hp": 10, "crit_chance": 0.06}},
	"sage_pendant": {"slot": "neck", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/sage_pendant_icon.png", "stats": {"intellect": 5, "crit_chance": 0.08}},
	"amulet_of_wrath": {"slot": "neck", "rarity": "epic", "level_req": 3, "icon": "res://assets/icons/amulet_of_wrath_icon.png", "stats": {"damage": 2, "strength": 3, "crit_chance": 0.20}},
	"swamp_charm": {"slot": "neck", "rarity": "uncommon", "level_req": 5, "icon": "res://assets/icons/swamp_charm_icon.png", "stats": {"crit_chance": 0.08, "max_hp": 15}},
	"rimewatch_amulet": {"slot": "neck", "rarity": "epic", "level_req": 8, "icon": "res://assets/icons/rimewatch_amulet_icon.png", "stats": {"damage": 4, "strength": 4, "intellect": 4, "crit_chance": 0.16}},
	# Ring
	"copper_ring": {"slot": "ring", "rarity": "common", "level_req": 1, "icon": "res://assets/icons/copper_ring_icon.png", "stats": {"crit_chance": 0.03, "max_hp": 5}},
	"ring_of_vigor": {"slot": "ring", "rarity": "uncommon", "level_req": 2, "icon": "res://assets/icons/ring_of_vigor_icon.png", "stats": {"max_hp": 20}},
	"ring_of_fortune": {"slot": "ring", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/ring_of_fortune_icon.png", "stats": {"crit_chance": 0.12}},
	"signet_of_power": {"slot": "ring", "rarity": "rare", "level_req": 3, "icon": "res://assets/icons/signet_of_power_icon.png", "stats": {"damage": 3, "strength": 2, "intellect": 2}},
	"ring_of_the_mire": {"slot": "ring", "rarity": "rare", "level_req": 6, "icon": "res://assets/icons/ring_of_the_mire_icon.png", "stats": {"max_hp": 30, "crit_chance": 0.06}},
	"frozen_band": {"slot": "ring", "rarity": "epic", "level_req": 8, "icon": "res://assets/icons/frozen_band_icon.png", "stats": {"damage": 5, "crit_chance": 0.12}},
	# Consumables
	"health_potion": {"type": "consumable", "heal": 20, "rarity": "common", "icon": "res://assets/icons/potion_icon.png"},
	"greater_health_potion": {"type": "consumable", "heal": 45, "rarity": "uncommon", "icon": "res://assets/icons/greater_health_potion_icon.png"},
}

## Human-readable item name for the HUD and activity log ("iron_sword" ->
## "Iron Sword"); the raw id is what code keys on.
static func display_name(item_id: String) -> String:
	return item_id.replace("_", " ").capitalize()

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
## RARITY_WEIGHTS (so epic items, at weight 0, are never picked here) and
## limited to items whose level_req is at most `loot_level` (consumables count
## as level 1), so early enemies never drop gear a character of their zone
## cannot use.
static func roll_drop(rng: RandomNumberGenerator, loot_level: int = LevelingSystem.MAX_LEVEL) -> String:
	var eligible: Array = []
	var total_weight := 0
	for item_id in ITEMS:
		var item: Dictionary = ITEMS[item_id]
		if int(item.get("level_req", 1)) > loot_level:
			continue
		var weight := int(RARITY_WEIGHTS.get(item.get("rarity", "common"), 0))
		if weight <= 0:
			continue
		eligible.append([item_id, weight])
		total_weight += weight
	if eligible.is_empty():
		return "health_potion"
	var roll := rng.randi_range(1, total_weight)
	var cumulative := 0
	for entry in eligible:
		cumulative += int(entry[1])
		if roll <= cumulative:
			return String(entry[0])
	return String(eligible[0][0])
