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
	t.done()
