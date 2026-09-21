class_name LootTable
extends RefCounted

## Static item definitions for v1. Each entry's "type" is "weapon", "armor", or
## "consumable"; weapons carry a "damage" stat, armor carries a "max_hp" stat,
## consumables carry a "heal" amount. Callers read these fields directly (see
## Character._pickup_item in Task 7).
const ITEMS := {
	"rusty_sword": {"type": "weapon", "damage": 4},
	"iron_sword": {"type": "weapon", "damage": 7},
	"leather_armor": {"type": "armor", "max_hp": 15},
	"health_potion": {"type": "consumable", "heal": 20},
}

## Picks a random item key from ITEMS using the given rng. Uniform across all items.
static func roll_drop(rng: RandomNumberGenerator) -> String:
	var keys := ITEMS.keys()
	var index := rng.randi_range(0, keys.size() - 1)
	return keys[index]

## Returns true if candidate_item_id should replace whatever is currently in
## equipped_item_id's slot. IMPORTANT: callers must only compare items within the
## SAME equipment slot (weapon vs weapon, armor vs armor) — this function assumes
## that and never mixes slots itself. Consumables never "equip" (always false).
## An empty equipped_item_id (empty slot) always accepts a valid non-consumable
## candidate. Unknown/malformed item ids fail closed (return false) rather than
## erroring — every lookup here goes through Dictionary.get() with a safe default.
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
	var stat_key := "damage" if candidate_type == "weapon" else "max_hp"
	return candidate.get(stat_key, 0) > equipped.get(stat_key, 0)
