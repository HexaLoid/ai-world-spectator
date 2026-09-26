class_name AIDecision
extends RefCounted

## Below this HP fraction the character runs from a hostile in aggro range.
## Kept well under REST_HP_THRESHOLD on purpose: a burst (a boss hit) can still
## kill a character that has already dropped this low, so deaths are rare but real.
const FLEE_HP_THRESHOLD := 0.1
## Below this HP fraction the character rests, but only when nothing hostile is
## in aggro range (with a hostile near, it keeps fighting until FLEE_HP_THRESHOLD).
const REST_HP_THRESHOLD := 0.3

## Resolves the AI character's next state from its current situation.
## Expected context keys: hp_percent (float, 0.0-1.0), hostile_in_attack_range (bool),
## hostile_in_aggro_range (bool), hostile_name (String), item_nearby (bool),
## ready_to_travel (bool), next_zone_name (String), quest_giver_in_zone (bool),
## quest_ready (bool). Optional: job_change_ready (bool, default false), flee_hp / rest_hp (floats, default FLEE_HP_THRESHOLD /
## REST_HP_THRESHOLD) for per-character personality thresholds.
## Returns {"state": <one of "flee"/"rest"/"combat"/"chase"/"loot"/"quest"/"job_change"/"travel"/"wander">, "reason": <String>}.
static func resolve_state(context: Dictionary) -> Dictionary:
	var hp_percent: float = clampf(float(context.get("hp_percent", 1.0)), 0.0, 1.0)
	var hostile_in_attack_range: bool = bool(context.get("hostile_in_attack_range", false))
	var hostile_in_aggro_range: bool = bool(context.get("hostile_in_aggro_range", false))
	var hostile_name: String = String(context.get("hostile_name", ""))
	if hostile_name == "":
		hostile_name = "an enemy"
	var item_nearby: bool = bool(context.get("item_nearby", false))
	var ready_to_travel: bool = bool(context.get("ready_to_travel", false))
	var next_zone_name: String = String(context.get("next_zone_name", "the next zone"))
	var quest_giver_in_zone: bool = bool(context.get("quest_giver_in_zone", false))
	var quest_ready: bool = bool(context.get("quest_ready", false))
	var job_change_ready: bool = bool(context.get("job_change_ready", false))
	var flee_hp: float = float(context.get("flee_hp", FLEE_HP_THRESHOLD))
	var rest_hp: float = float(context.get("rest_hp", REST_HP_THRESHOLD))

	if hp_percent < flee_hp and hostile_in_aggro_range:
		return {"state": "flee", "reason": "HP low (%d%%) - fleeing from %s" % [round(hp_percent * 100), hostile_name]}
	if hp_percent < rest_hp and not hostile_in_aggro_range:
		return {"state": "rest", "reason": "HP low (%d%%) - resting to recover" % round(hp_percent * 100)}
	if hostile_in_attack_range:
		return {"state": "combat", "reason": "%s in range - engaging" % hostile_name}
	# Ranked above "chase" (but still below finishing a fight already in
	# attack range) so a completed/acceptable quest doesn't get stranded
	# forever behind an endless string of freshly-respawned wolves near
	# their spawn point — found live: without this, the character kept
	# re-engaging new Wolves in Thornfield well past "ready to turn in" and
	# never actually walked back to the board.
	if quest_giver_in_zone and quest_ready:
		return {"state": "quest", "reason": "Heading to the quest board"}
	if job_change_ready:
		return {"state": "job_change", "reason": "Heading to the job crystal"}
	if hostile_in_aggro_range:
		return {"state": "chase", "reason": "%s spotted - closing in" % hostile_name}
	if item_nearby:
		return {"state": "loot", "reason": "Item nearby - moving to pick it up"}
	if ready_to_travel:
		return {"state": "travel", "reason": "Time to move on - heading to %s" % next_zone_name}
	return {"state": "wander", "reason": "Nothing pressing - wandering"}
