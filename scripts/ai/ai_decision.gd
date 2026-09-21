class_name AIDecision
extends RefCounted

const FLEE_HP_THRESHOLD := 0.3

static func resolve_state(context: Dictionary) -> Dictionary:
	var hp_percent: float = context.get("hp_percent", 1.0)
	var hostile_in_attack_range: bool = context.get("hostile_in_attack_range", false)
	var hostile_in_aggro_range: bool = context.get("hostile_in_aggro_range", false)
	var hostile_name: String = context.get("hostile_name", "")
	var item_nearby: bool = context.get("item_nearby", false)

	if hp_percent < FLEE_HP_THRESHOLD and hostile_in_aggro_range:
		return {"state": "flee", "reason": "HP low (%d%%) - fleeing from %s" % [round(hp_percent * 100), hostile_name]}
	if hp_percent < FLEE_HP_THRESHOLD:
		return {"state": "rest", "reason": "HP low (%d%%) - resting to recover" % round(hp_percent * 100)}
	if hostile_in_attack_range:
		return {"state": "combat", "reason": "%s in range - engaging" % hostile_name}
	if hostile_in_aggro_range:
		return {"state": "chase", "reason": "%s spotted - closing in" % hostile_name}
	if item_nearby:
		return {"state": "loot", "reason": "Item nearby - moving to pick it up"}
	return {"state": "wander", "reason": "Nothing pressing - wandering"}
