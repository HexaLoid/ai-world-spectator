extends RefCounted

func run(t) -> void:
	var warrior: Dictionary = AbilityTable.CLASSES["warrior"]
	var mage: Dictionary = AbilityTable.CLASSES["mage"]
	var base := {"max_hp": 60, "damage_min": 4, "damage_max": 8, "crit_chance": 0.0}

	# gear_totals()
	var totals := StatCalculator.gear_totals({"weapon": "steel_sword", "head": "iron_helm"})
	t.check_near(float(totals.get("damage", 0.0)), 11.0, "totals sum damage")
	t.check_near(float(totals.get("armor", 0.0)), 2.0, "totals sum armor")
	t.check_near(float(totals.get("max_hp", 0.0)), 10.0, "totals sum max_hp")
	t.check_eq(StatCalculator.gear_totals({}).size(), 0, "no gear, no totals")
	t.check_eq(StatCalculator.gear_totals({"weapon": "no_such_item", "head": ""}).size(), 0, "unknown/empty ids contribute nothing")

	# derive(): no gear leaves base stats untouched
	var bare := StatCalculator.derive(base, {}, warrior)
	t.check_eq(bare["max_hp"], 60, "bare max_hp")
	t.check_eq(bare["damage_min"], 4, "bare damage_min")
	t.check_eq(bare["damage_max"], 8, "bare damage_max")
	t.check_near(float(bare["crit_chance"]), 0.0, "bare crit")
	t.check_eq(bare["armor"], 0, "bare armor")

	# derive(): warrior with steel_sword (+11 dmg, +2 STR -> x1.02) and iron_helm (+2 armor, +10 HP)
	var geared := StatCalculator.derive(base, {"weapon": "steel_sword", "head": "iron_helm"}, warrior)
	t.check_eq(geared["damage_min"], 15, "(4+11) x 1.02 = 15.3 -> 15")
	t.check_eq(geared["damage_max"], 19, "(8+11) x 1.02 = 19.38 -> 19")
	t.check_eq(geared["max_hp"], 70, "max_hp includes helm")
	t.check_eq(geared["armor"], 2, "armor from helm")

	# derive(): a mage's strength is not its primary stat, so it does not boost damage
	var mage_geared := StatCalculator.derive(base, {"weapon": "steel_sword"}, mage)
	t.check_eq(mage_geared["damage_min"], 15, "mage: (4+11) x 1.0 = 15")
	# ...but its intellect is
	var mage_staff := StatCalculator.derive(base, {"weapon": "arcane_staff"}, mage)
	t.check_eq(mage_staff["damage_min"], 13, "(4+8) x 1.07 = 12.84 -> 13")

	# derive(): crit adds up
	var crit := StatCalculator.derive(base, {"neck": "lucky_charm", "ring": "ring_of_fortune"}, warrior)
	t.check_near(float(crit["crit_chance"]), 0.17, "crit from neck + ring")

	# class bonuses: flat HP and armor, none for a class without them
	var mage_base := StatCalculator.derive(base, {}, mage)
	t.check_eq(mage_base["max_hp"], int(base["max_hp"]) + int(mage.get("bonus_max_hp", 0)), "mage bonus HP applies")
	t.check_eq(mage_base["armor"], int(mage.get("bonus_armor", 0)), "mage bonus armor applies")
	t.check(int(mage.get("bonus_max_hp", 0)) > 0 and int(mage.get("bonus_armor", 0)) > 0, "mage has class bonuses")
	t.check_eq(StatCalculator.derive(base, {}, warrior)["armor"], 0, "warrior has no bonus armor")

	# mitigate()
	t.check_eq(StatCalculator.mitigate(10, 0), 10, "no armor, no reduction")
	t.check_eq(StatCalculator.mitigate(10, 25), 5, "25 armor halves damage (100 / (100 + 25x4))")
	t.check_eq(StatCalculator.mitigate(1, 100), 1, "damage never mitigated below 1")
	t.check_eq(StatCalculator.mitigate(0, 50), 0, "zero damage stays zero")
	# bonus_crit_chance is a flat class bonus on top of gear
	var crit_class := {"bonus_crit_chance": 0.10}
	t.check_near(float(StatCalculator.derive(base, {}, crit_class)["crit_chance"]), 0.10, "class crit bonus")
	t.check_near(float(StatCalculator.derive(base, {"neck": "lucky_charm"}, crit_class)["crit_chance"]), 0.10 + float(StatCalculator.derive(base, {"neck": "lucky_charm"}, {})["crit_chance"]), "class crit stacks with gear")
	t.check_near(float(StatCalculator.derive(base, {}, warrior)["crit_chance"]), 0.0, "no class crit bonus by default")
	t.done()
