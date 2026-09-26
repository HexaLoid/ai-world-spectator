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
	var cautious_def := TraitTable.get_def("cautious")
	var reckless_def := TraitTable.get_def("reckless")
	var c_flee: float = cautious_def["flee_hp"]
	var c_rest: float = cautious_def["rest_hp"]
	var r_flee: float = reckless_def["flee_hp"]
	var r_rest: float = reckless_def["rest_hp"]
	t.check(c_flee > flee_hp and c_rest > rest_hp, "cautious thresholds are above the defaults")
	t.check(r_flee < flee_hp and r_rest < rest_hp, "reckless thresholds are below the defaults")
	var near_flee := c_flee - 0.01
	var cautious := _ctx(near_flee, true, true)
	t.check_eq(AIDecision.resolve_state(cautious)["state"], "combat", "just below cautious flee HP, default thresholds: keeps fighting")
	cautious["flee_hp"] = c_flee
	cautious["rest_hp"] = c_rest
	t.check_eq(AIDecision.resolve_state(cautious)["state"], "flee", "just below cautious flee HP, cautious: flees")
	var mid_rest := (rest_hp + c_rest) / 2.0
	var cautious_rest := _ctx(mid_rest, false)
	cautious_rest["flee_hp"] = c_flee
	cautious_rest["rest_hp"] = c_rest
	t.check_eq(AIDecision.resolve_state(cautious_rest)["state"], "rest", "above default rest HP but below cautious rest HP, nothing near: cautious rests")
	t.check_eq(AIDecision.resolve_state(_ctx(mid_rest, false))["state"], "wander", "same HP, default: wanders")
	var mid_flee := (r_flee + flee_hp) / 2.0
	var reckless := _ctx(mid_flee, true, true)
	t.check_eq(AIDecision.resolve_state(reckless)["state"], "flee", "between reckless and default flee HP, default: flees")
	reckless["flee_hp"] = r_flee
	reckless["rest_hp"] = r_rest
	t.check_eq(AIDecision.resolve_state(reckless)["state"], "combat", "same HP, reckless: keeps fighting")
	var reckless_low := _ctx(r_flee - 0.01, true, true)
	reckless_low["flee_hp"] = r_flee
	reckless_low["rest_hp"] = r_rest
	t.check_eq(AIDecision.resolve_state(reckless_low)["state"], "flee", "below reckless flee HP: finally flees")
	t.done()
