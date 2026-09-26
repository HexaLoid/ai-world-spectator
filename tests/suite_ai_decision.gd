extends RefCounted

func _ctx(hp: float, aggro: bool, attack: bool = false) -> Dictionary:
	return {"hp_percent": hp, "hostile_in_aggro_range": aggro, "hostile_in_attack_range": attack, "hostile_name": "Wolf"}

func run(t) -> void:
	t.check(AIDecision.FLEE_HP_THRESHOLD < AIDecision.REST_HP_THRESHOLD, "flee threshold is below the rest threshold")
	t.check(AIDecision.FLEE_HP_THRESHOLD > 0.0, "flee threshold is positive")
	var flee_hp: float = AIDecision.FLEE_HP_THRESHOLD
	var rest_hp: float = AIDecision.REST_HP_THRESHOLD
	t.check_eq(AIDecision.resolve_state(_ctx(flee_hp - 0.01, true, true))["state"], "flee", "below flee threshold with a hostile near: flee")
	t.check_eq(AIDecision.resolve_state(_ctx(flee_hp - 0.01, false))["state"], "rest", "below flee threshold, nothing near: rest")
	t.check_eq(AIDecision.resolve_state(_ctx(flee_hp + 0.01, true, true))["state"], "combat", "between flee and rest thresholds in melee: keeps fighting")
	t.check_eq(AIDecision.resolve_state(_ctx(flee_hp + 0.01, true))["state"], "chase", "between thresholds, hostile in aggro range: chase")
	t.check_eq(AIDecision.resolve_state(_ctx((flee_hp + rest_hp) / 2.0, false))["state"], "rest", "between thresholds, nothing near: rest")
	t.check_eq(AIDecision.resolve_state(_ctx(rest_hp + 0.01, false))["state"], "wander", "above rest threshold, nothing to do: wander")
	t.check_eq(AIDecision.resolve_state(_ctx(1.0, true, true))["state"], "combat", "full HP in range: combat")
	# trait thresholds (optional context keys flee_hp / rest_hp)
	var cautious := _ctx(0.2, true, true)
	t.check_eq(AIDecision.resolve_state(cautious)["state"], "combat", "20% HP, default thresholds: keeps fighting")
	cautious["flee_hp"] = 0.25
	cautious["rest_hp"] = 0.45
	t.check_eq(AIDecision.resolve_state(cautious)["state"], "flee", "20% HP, cautious: flees")
	var cautious_rest := _ctx(0.4, false)
	cautious_rest["flee_hp"] = 0.25
	cautious_rest["rest_hp"] = 0.45
	t.check_eq(AIDecision.resolve_state(cautious_rest)["state"], "rest", "40% HP, cautious, nothing near: rests")
	t.check_eq(AIDecision.resolve_state(_ctx(0.4, false))["state"], "wander", "40% HP, default: wanders")
	var reckless := _ctx(0.08, true, true)
	t.check_eq(AIDecision.resolve_state(reckless)["state"], "flee", "8% HP, default: flees")
	reckless["flee_hp"] = 0.05
	reckless["rest_hp"] = 0.20
	t.check_eq(AIDecision.resolve_state(reckless)["state"], "combat", "8% HP, reckless: keeps fighting")
	var reckless_low := _ctx(0.04, true, true)
	reckless_low["flee_hp"] = 0.05
	reckless_low["rest_hp"] = 0.20
	t.check_eq(AIDecision.resolve_state(reckless_low)["state"], "flee", "4% HP, reckless: finally flees")
	t.done()
