extends RefCounted

func run(t) -> void:
	# catch_up_level
	t.check_eq(JobSwitch.catch_up_level({}), 1, "no jobs taken: level 1")
	t.check_eq(JobSwitch.catch_up_level({"warrior": 10}), 8, "best minus 2")
	t.check_eq(JobSwitch.catch_up_level({"warrior": 2}), 1, "never below 1")
	t.check_eq(JobSwitch.catch_up_level({"warrior": 3, "thief": 6}), 4, "uses the best job")

	# starting_xp
	t.check_eq(JobSwitch.starting_xp(1), 0, "level 1 starts at 0 XP")
	t.check_eq(JobSwitch.starting_xp(2), LevelingSystem.XP_THRESHOLDS[0], "level 2 threshold")
	t.check_eq(JobSwitch.starting_xp(8), LevelingSystem.XP_THRESHOLDS[6], "level 8 threshold")

	# inherit_equipment
	# fixed items from different slots: a level-1 weapon and a level-9 chest
	t.check_eq(int(LootTable.ITEMS["rusty_sword"]["level_req"]), 1, "test data: rusty_sword is level 1")
	t.check_eq(int(LootTable.ITEMS["glacier_plate"]["level_req"]), 9, "test data: glacier_plate is level 9")
	var gear := {"weapon": "rusty_sword", "chest": "glacier_plate"}
	var inherited := JobSwitch.inherit_equipment(gear, 8)
	t.check_eq(inherited.get("weapon", ""), "rusty_sword", "a usable item is kept")
	t.check(not inherited.has("chest"), "an item above the level is dropped")
	t.check_eq(JobSwitch.inherit_equipment(gear, 9).size(), 2, "everything usable at level 9 is kept")
	t.check_eq(gear.size(), 2, "the input dictionary is not modified")
	t.check_eq(JobSwitch.inherit_equipment({}, 5), {}, "empty gear stays empty")

	# switch_due
	t.check(JobSwitch.switch_due(10, [10, 4, 1], "cap"), "cap: due when another job is below the cap")
	t.check(not JobSwitch.switch_due(10, [10, 10], "cap"), "cap: not due when every other job is capped")
	t.check(not JobSwitch.switch_due(9, [1], "cap"), "cap: not due below the cap")
	t.check(JobSwitch.switch_due(10, [8], "loop"), "loop: gap of exactly 2 is due")
	t.check(not JobSwitch.switch_due(10, [9], "loop"), "loop: gap of 1 is not due")
	t.check(not JobSwitch.switch_due(5, [], "loop"), "loop: no other jobs")
	t.check(not JobSwitch.switch_due(9, [1], "loop"), "loop: the active job is below the cap")
	t.check(JobSwitch.switch_due(10, [1], "loop"), "loop: the active job is at the cap")
	t.check(JobSwitch.switch_due(10, [8, 10], "loop"), "loop at the cap with a job 2 below")
	t.check(not JobSwitch.switch_due(5, [1], "nope"), "unknown reason is never due")

	# pick_next_job
	var order := AbilityTable.job_ids()
	var others: Array = []
	for id in order:
		if id != "warrior":
			others.append(id)
	t.check_eq(JobSwitch.pick_next_job("warrior", {"warrior": 10}, "steady", 0.0), others[0], "untaken jobs count as level 1: first in order at roll 0")
	t.check_eq(JobSwitch.pick_next_job("warrior", {"warrior": 10}, "steady", 0.999), others[others.size() - 1], "last in order at roll 0.999")
	t.check_eq(JobSwitch.pick_next_job("warrior", {"warrior": 10, "dragoon": 3}, "steady", 0.0), others[0], "a taken job above level 1 is not the lowest")

	var capped := {}
	for id in order:
		capped[id] = 10
	t.check_eq(JobSwitch.pick_next_job("warrior", capped, "steady", 0.5), "", "everything capped: no pick")
	capped["thief"] = 4
	t.check_eq(JobSwitch.pick_next_job("warrior", capped, "steady", 0.5), "thief", "capped jobs are excluded")
	t.check_eq(JobSwitch.pick_next_job("thief", capped, "steady", 0.5), "", "the active job is excluded")

	# trait nudges (within 2 levels of the lowest)
	var levels := {"warrior": 10, "black_belt": 1, "thief": 1, "dragoon": 1, "white_mage": 2, "mage": 1, "red_mage": 1}
	t.check_eq(JobSwitch.pick_next_job("warrior", levels, "steady", 0.0), "black_belt", "steady: lowest level pool")
	t.check_eq(JobSwitch.pick_next_job("warrior", levels, "cautious", 0.0), "white_mage", "cautious prefers the healer within 2 levels")
	levels["white_mage"] = 5
	t.check_eq(JobSwitch.pick_next_job("warrior", levels, "cautious", 0.0), "black_belt", "cautious: healer too far above the lowest, base pick")

	var rlevels := {"warrior": 10, "white_mage": 1, "black_belt": 2, "thief": 10, "dragoon": 10, "mage": 10, "red_mage": 10}
	t.check_eq(JobSwitch.pick_next_job("warrior", rlevels, "steady", 0.0), "white_mage", "steady picks the lowest")
	t.check_eq(JobSwitch.pick_next_job("warrior", rlevels, "reckless", 0.0), "black_belt", "reckless prefers melee or magic")

	var glevels := {"warrior": 10, "thief": 3, "black_belt": 1, "dragoon": 10, "white_mage": 10, "mage": 10, "red_mage": 10}
	t.check_eq(JobSwitch.pick_next_job("warrior", glevels, "greedy", 0.0), "thief", "greedy prefers the thief within 2 levels")
	glevels["thief"] = 4
	t.check_eq(JobSwitch.pick_next_job("warrior", glevels, "greedy", 0.0), "black_belt", "greedy: thief too far above the lowest")

	t.check_eq(JobSwitch.pick_next_job("warrior", {"warrior": 10, "thief": 9}, "explorer", 0.0), others[0], "explorer: any candidate, first at roll 0")
	t.check_eq(JobSwitch.pick_next_job("warrior", {"warrior": 10}, "explorer", 0.999), others[others.size() - 1], "explorer: last at roll 0.999")
	t.check_eq(JobSwitch.pick_next_job("warrior", levels, "steady", 0.3), JobSwitch.pick_next_job("warrior", levels, "steady", 0.3), "deterministic for a given roll")
	t.done()
