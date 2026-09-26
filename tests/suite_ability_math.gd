extends RefCounted

func run(t) -> void:
	# hit_count
	t.check_eq(AbilityMath.hit_count({}), 1, "no hit_count: one hit")
	t.check_eq(AbilityMath.hit_count({"hit_count": 3}), 3, "hit_count 3")
	t.check_eq(AbilityMath.hit_count({"hit_count": 0}), 1, "hit_count never below 1")
	t.check_eq(AbilityMath.hit_count({"hit_count": -2}), 1, "negative hit_count clamps to 1")

	# jump_multiplier
	t.check_near(AbilityMath.jump_multiplier({}), 0.0, "plain gap closer has no jump hit")
	t.check_near(AbilityMath.jump_multiplier({"damage_multiplier": 1.6}), 1.6, "jump hit multiplier")

	# pick_heal_target: lowest HP fraction below the threshold, or -1
	t.check_eq(AbilityMath.pick_heal_target([10, 50, 30], [100, 100, 100], 0.65), 0, "lowest fraction wins")
	t.check_eq(AbilityMath.pick_heal_target([90, 80], [100, 100], 0.65), -1, "everyone healthy: no target")
	t.check_eq(AbilityMath.pick_heal_target([], [], 0.65), -1, "empty party: no target")
	t.check_eq(AbilityMath.pick_heal_target([20, 30], [40, 100], 0.65), 1, "fractions, not raw HP: 30/100 < 20/40")
	t.check_eq(AbilityMath.pick_heal_target([65], [100], 0.65), -1, "exactly at the threshold is not below it")
	t.check_eq(AbilityMath.pick_heal_target([0, 30], [100, 100], 0.65), 1, "a dead member (0 HP) is skipped")
	t.check_eq(AbilityMath.pick_heal_target([10], [0], 0.65), -1, "max_hp 0 is skipped")

	# heal_amount
	t.check_eq(AbilityMath.heal_amount(100, 0.3), 30, "30% of 100")
	t.check_eq(AbilityMath.heal_amount(45, 0.25), 11, "rounds to nearest")
	t.check_eq(AbilityMath.heal_amount(1, 0.01), 1, "always at least 1")
	t.done()
