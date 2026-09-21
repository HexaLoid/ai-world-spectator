class_name AIDecision
extends RefCounted

const FLEE_HP_THRESHOLD := 0.3

## Resolves the AI character's next state from its current situation.
## Expected context keys: hp_percent (float, 0.0-1.0), hostile_in_attack_range (bool),
## hostile_in_aggro_range (bool), hostile_name (String), item_nearby (bool).
## Returns {"state": <one of "flee"/"rest"/"combat"/"chase"/"loot"/"wander">, "reason": <String>}.
static func resolve_state(context: Dictionary) -> Dictionary:
	var hp_percent: float = clampf(float(context.get("hp_percent", 1.0)), 0.0, 1.0)
	var hostile_in_attack_range: bool = bool(context.get("hostile_in_attack_range", false))
	var hostile_in_aggro_range: bool = bool(context.get("hostile_in_aggro_range", false))
	var hostile_name: String = String(context.get("hostile_name", ""))
	if hostile_name == "":
		hostile_name = "an enemy"
	var item_nearby: bool = bool(context.get("item_nearby", false))

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
