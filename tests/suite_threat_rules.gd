extends RefCounted

func _c(dist: float, is_tank: bool) -> Dictionary:
	return {"dist": dist, "is_tank": is_tank}

func run(t) -> void:
	t.check_eq(ThreatRules.pick_target([], 120.0), -1, "no candidates")
	t.check_eq(ThreatRules.pick_target([_c(80.0, false), _c(50.0, false)], 120.0), 1, "no tank: nearest wins")
	t.check_eq(ThreatRules.pick_target([_c(40.0, false), _c(100.0, true)], 120.0), 1, "a tank in range beats a nearer non-tank")
	t.check_eq(ThreatRules.pick_target([_c(40.0, false), _c(150.0, true)], 120.0), 1, "the pull range is 1.3x the aggro range (156)")
	t.check_eq(ThreatRules.pick_target([_c(40.0, false), _c(200.0, true)], 120.0), 0, "a tank beyond the pull range loses")
	t.check_eq(ThreatRules.pick_target([_c(100.0, true), _c(60.0, true)], 120.0), 1, "two tanks: the nearer one")
	t.check_eq(ThreatRules.pick_target([_c(50.0, false), _c(50.0, false)], 120.0), 0, "a tie goes to the first")
	t.check_near(ThreatRules.TANK_PULL_MULT, 1.3, "pull multiplier")
	t.done()
