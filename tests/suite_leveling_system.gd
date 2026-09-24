extends RefCounted

func run(t) -> void:
	t.check_eq(LevelingSystem.MAX_LEVEL, 10, "level cap is 10")
	t.check_eq(LevelingSystem.XP_THRESHOLDS.size(), LevelingSystem.MAX_LEVEL - 1, "one threshold per level above 1")
	var previous := 0
	for threshold in LevelingSystem.XP_THRESHOLDS:
		t.check(int(threshold) > previous, "thresholds strictly increase (%d after %d)" % [threshold, previous])
		previous = int(threshold)

	var below := LevelingSystem.apply_xp(1, 0, 99)
	t.check_eq(below["level"], 1, "99 xp is still level 1")
	t.check(not below["leveled_up"], "no level-up below the first threshold")

	var first := LevelingSystem.apply_xp(1, 0, 100)
	t.check_eq(first["level"], 2, "100 xp reaches level 2")
	t.check(first["leveled_up"], "level-up flagged")
	t.check_eq(first["hp_bonus"], LevelingSystem.HP_PER_LEVEL, "one level of hp bonus")
	t.check_eq(first["damage_bonus"], LevelingSystem.DAMAGE_PER_LEVEL, "one level of damage bonus")

	var top := LevelingSystem.apply_xp(1, 0, 3200)
	t.check_eq(top["level"], 10, "3200 xp reaches level 10")
	t.check_eq(top["hp_bonus"], 9 * LevelingSystem.HP_PER_LEVEL, "nine levels of hp bonus")
	t.check_eq(top["damage_bonus"], 9 * LevelingSystem.DAMAGE_PER_LEVEL, "nine levels of damage bonus")

	var capped := LevelingSystem.apply_xp(10, 3200, 5000)
	t.check_eq(capped["level"], 10, "cannot exceed the cap")
	t.check(not capped["leveled_up"], "no level-up at the cap")

	t.check_eq(LevelingSystem.get_next_threshold(1), 100, "next threshold from level 1")
	t.check_eq(LevelingSystem.get_next_threshold(9), 3200, "next threshold from level 9")
	t.check_eq(LevelingSystem.get_next_threshold(10), -1, "no threshold at the cap")
	t.check_eq(LevelingSystem.get_next_threshold(0), -1, "invalid level has no threshold")
