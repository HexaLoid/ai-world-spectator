extends RefCounted

func run(t) -> void:
	t.check(EncounterLogic.heavy_due(9000.0, 9000.0), "due exactly on time")
	t.check(EncounterLogic.heavy_due(9500.0, 9000.0), "due when late")
	t.check(not EncounterLogic.heavy_due(8999.0, 9000.0), "not due early")
	t.check_eq(EncounterLogic.heavy_damage(50), 125, "50 x 2.5")
	t.check_eq(EncounterLogic.heavy_damage(55, 2.0), 110, "custom multiplier")
	t.check_eq(EncounterLogic.heavy_damage(0), 0, "no attack, no heavy damage")
	t.check(not EncounterLogic.add_phase_due(1000, 1800, false), "above 50%: no add phase")
	t.check(EncounterLogic.add_phase_due(900, 1800, false), "exactly 50%: add phase")
	t.check(EncounterLogic.add_phase_due(100, 1800, false), "below 50%: add phase")
	t.check(not EncounterLogic.add_phase_due(100, 1800, true), "the add phase fires only once")
	t.check(not EncounterLogic.add_phase_due(0, 1800, false), "a dead boss does not summon")
	t.check_near(EncounterLogic.HEAVY_INTERVAL_MS, 9000.0, "heavy strike interval")
	t.check_near(EncounterLogic.HEAVY_WINDUP_MS, 1500.0, "wind-up")
	t.check_eq(EncounterLogic.ADD_COUNT, 2, "two adds")
	t.done()
