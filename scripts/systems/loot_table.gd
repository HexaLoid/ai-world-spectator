class_name LootTable
extends RefCounted

const ITEMS := {
	"rusty_sword": {"type": "weapon", "damage": 4},
	"iron_sword": {"type": "weapon", "damage": 7},
	"leather_armor": {"type": "armor", "max_hp": 15},
	"health_potion": {"type": "consumable", "heal": 20},
}

static func roll_drop(rng: RandomNumberGenerator) -> String:
	var keys := ITEMS.keys()
	var index := rng.randi_range(0, keys.size() - 1)
	return keys[index]

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
