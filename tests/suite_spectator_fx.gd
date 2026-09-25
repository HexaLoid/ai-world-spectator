extends RefCounted

func run(t) -> void:
	# number_scale
	t.check_near(SpectatorFx.number_scale(5, false, false), 1.0, "normal hit scale")
	t.check_near(SpectatorFx.number_scale(5, true, false), 1.5, "crit scale")
	t.check_near(SpectatorFx.number_scale(5, false, true), 1.3, "boss hit scale")
	t.check_near(SpectatorFx.number_scale(5, true, true), 1.8, "crit boss scale")
	t.check_near(SpectatorFx.number_scale(40, false, false), 1.3, "large hit bonus")
	t.check_near(SpectatorFx.number_scale(60, true, true), 2.1, "everything stacks")

	# number_color
	t.check_eq(SpectatorFx.number_color(true, false, false), SpectatorFx.HEAL_COLOR, "heal is green")
	t.check_eq(SpectatorFx.number_color(false, true, false), SpectatorFx.CRIT_COLOR, "crit is gold")
	t.check_eq(SpectatorFx.number_color(false, false, true), SpectatorFx.CHARACTER_HIT_COLOR, "damage on the character")
	t.check_eq(SpectatorFx.number_color(false, false, false), SpectatorFx.ENEMY_HIT_COLOR, "damage on others")
	t.check_eq(SpectatorFx.number_color(true, true, true), SpectatorFx.HEAL_COLOR, "heal wins")

	# shake_strength
	t.check_near(SpectatorFx.shake_strength(3, false, false, false, 60), 0.0, "small hit: no shake")
	t.check(SpectatorFx.shake_strength(3, true, false, false, 60) > 0.0, "crit shakes")
	t.check(SpectatorFx.shake_strength(3, false, false, true, 60) > 0.0, "boss hit shakes")
	t.check(SpectatorFx.shake_strength(10, false, false, false, 60) > 0.0, "17% of max HP shakes")
	t.check_near(SpectatorFx.shake_strength(8, false, false, false, 60), 0.0, "13% of max HP does not")
	var previous := 0.0
	for amount in range(1, 101):
		var s := SpectatorFx.shake_strength(amount, false, false, false, 60)
		t.check(s >= previous, "shake never decreases with damage (amount %d)" % amount)
		previous = s
	var in_range := true
	for amount in [0, 1, 20, 100, 1000]:
		for max_hp in [0, 1, 60, 1300]:
			for flags in range(8):
				var s := SpectatorFx.shake_strength(amount, flags & 1 != 0, flags & 2 != 0, flags & 4 != 0, max_hp)
				if s < 0.0 or s > 1.0:
					in_range = false
	t.check(in_range, "shake always within 0..1 (including max_hp 0)")

	# should_slow_kill
	t.check(SpectatorFx.should_slow_kill(true, 1.0), "boss kill while running")
	t.check(SpectatorFx.should_slow_kill(true, 4.0), "boss kill at 4x")
	t.check(not SpectatorFx.should_slow_kill(true, 0.0), "no slow-mo while paused")
	t.check(not SpectatorFx.should_slow_kill(false, 1.0), "no slow-mo for non-boss")
	t.done()
