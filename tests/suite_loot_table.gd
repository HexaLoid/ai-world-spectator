extends RefCounted

func run(t) -> void:
	t.check(LootTable.SLOTS.size() == 6, "six equipment slots")
	var items_per_slot := {}
	var has_level_one_common := {}
	for item_id in LootTable.ITEMS:
		var item: Dictionary = LootTable.ITEMS[item_id]
		t.check(LootTable.RARITY_WEIGHTS.has(item.get("rarity", "")), "%s has a valid rarity" % item_id)
		var icon: String = item.get("icon", "")
		t.check(icon != "" and FileAccess.file_exists(icon), "%s icon exists (%s)" % [item_id, icon])
		if item.get("type", "") == "consumable":
			t.check(int(item.get("heal", 0)) > 0, "%s heals" % item_id)
			t.check(not item.has("slot"), "%s (consumable) has no slot" % item_id)
			continue
		var slot: String = item.get("slot", "")
		t.check(LootTable.SLOTS.has(slot), "%s has a valid slot (%s)" % [item_id, slot])
		var stats: Dictionary = item.get("stats", {})
		t.check(not stats.is_empty(), "%s has stats" % item_id)
		for stat in stats:
			t.check(LootTable.STAT_LABELS.has(stat), "%s stat %s is known" % [item_id, stat])
		var level_req := int(item.get("level_req", 0))
		t.check(level_req >= 1 and level_req <= LevelingSystem.MAX_LEVEL, "%s level_req in range" % item_id)
		items_per_slot[slot] = int(items_per_slot.get(slot, 0)) + 1
		if item.get("rarity", "") == "common" and level_req == 1:
			has_level_one_common[slot] = true
	for slot in LootTable.SLOTS:
		t.check(int(items_per_slot.get(slot, 0)) >= 3, "slot %s has at least three items" % slot)
		t.check(has_level_one_common.has(slot), "slot %s has a common level-1 item" % slot)
	for quest in QuestTable.QUESTS:
		var reward: String = quest.get("item_reward", "")
		if reward != "":
			t.check(LootTable.ITEMS.has(reward), "quest %s reward %s exists" % [quest["id"], reward])
			if LootTable.ITEMS.has(reward):
				t.check(int(LootTable.ITEMS[reward].get("level_req", 1)) <= int(quest["min_level"]), "quest %s reward %s is equippable at the quest's min_level" % [quest["id"], reward])
	for boss_drop in ["iron_sword", "warlords_greatsword"]:
		t.check(LootTable.ITEMS.has(boss_drop), "guaranteed drop %s exists" % boss_drop)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 300:
		var rolled := LootTable.roll_drop(rng)
		t.check(LootTable.ITEMS.has(rolled), "rolled item exists")
		t.check(LootTable.ITEMS[rolled]["rarity"] != "epic", "epic items never roll randomly")
	t.check_eq(LootTable.STAT_ORDER.size(), LootTable.STAT_LABELS.size(), "STAT_ORDER and STAT_LABELS have the same number of stats")
	for stat in LootTable.STAT_ORDER:
		t.check(LootTable.STAT_LABELS.has(stat), "STAT_ORDER key %s has a label" % stat)
	t.check_eq(LootTable.display_name("iron_helm"), "Iron Helm", "display_name capitalizes")
	# level-aware drops
	var drop_rng := RandomNumberGenerator.new()
	drop_rng.seed = 99
	for loot_level in [1, 2, 3, 5, 6, 9, 10]:
		for i in 300:
			var rolled := LootTable.roll_drop(drop_rng, loot_level)
			t.check(LootTable.ITEMS.has(rolled), "level-%d roll returns a real item" % loot_level)
			var rolled_def: Dictionary = LootTable.ITEMS[rolled]
			t.check(int(rolled_def.get("level_req", 1)) <= loot_level, "level-%d roll never returns %s (level_req %d)" % [loot_level, rolled, int(rolled_def.get("level_req", 1))])
			t.check(rolled_def["rarity"] != "epic", "level-%d roll never returns an epic" % loot_level)
	t.check(LootTable.roll_drop(drop_rng, 1) != "", "a level-1 roll always finds something")
	# new content sanity
	for item_id in ["tempered_sword", "mirewood_staff", "tyrants_maul", "frostbrand", "glacier_staff", "bog_bulwark",
			"frostguard_shield", "marsh_helm", "rimewatch_helm", "reinforced_mail", "glacier_plate", "swamp_charm",
			"rimewatch_amulet", "ring_of_the_mire", "frozen_band"]:
		t.check(LootTable.ITEMS.has(item_id), "new item %s exists" % item_id)
	# boss bonus epic
	var epic_ids := LootTable.epic_ids_up_to(99)
	var real_epics: Array = []
	for item_id in LootTable.ITEMS:
		if LootTable.ITEMS[item_id].get("rarity", "") == "epic":
			real_epics.append(item_id)
	real_epics.sort()
	t.check_eq(epic_ids, real_epics, "epic_ids_up_to(99) is every epic, sorted")
	t.check_eq(LootTable.epic_ids_up_to(2), [], "no epic is available at level 2")
	t.check_eq(LootTable.epic_ids_up_to(3), ["amulet_of_wrath", "champions_plate", "crown_of_thornfield", "warlords_greatsword"], "level-3 epics")
	t.check(LootTable.epic_ids_up_to(9).has("glacier_plate") and LootTable.epic_ids_up_to(9).has("frostbrand"), "level-9 epics include the frost set")
	t.check(not LootTable.epic_ids_up_to(7).has("frostbrand"), "frostbrand needs level 8")
	t.check_eq(LootTable.BOSS_BONUS_EPIC_CHANCE, 0.35, "boss bonus chance is 35%")
	var bonus_rng := RandomNumberGenerator.new()
	bonus_rng.seed = 4242
	for i in 500:
		t.check_eq(LootTable.roll_boss_bonus(bonus_rng, 2), "", "level-2 bonus roll never finds an epic")
	var hits := 0
	var seen := {}
	for i in 2000:
		var bonus := LootTable.roll_boss_bonus(bonus_rng, 9)
		if bonus == "":
			continue
		hits += 1
		seen[bonus] = true
		t.check(LootTable.ITEMS.has(bonus) and LootTable.ITEMS[bonus]["rarity"] == "epic", "bonus roll returns an epic")
		t.check(int(LootTable.ITEMS[bonus]["level_req"]) <= 9, "bonus roll respects loot_level")
	t.check(hits >= 500 and hits <= 900, "about 35%% of level-9 bonus rolls succeed (got %d/2000)" % hits)
	t.check_eq(seen.size(), LootTable.epic_ids_up_to(9).size(), "every eligible epic can be rolled")
	var lvl5_rng := RandomNumberGenerator.new()
	lvl5_rng.seed = 7
	for i in 500:
		var low_bonus := LootTable.roll_boss_bonus(lvl5_rng, 5)
		t.check(low_bonus == "" or int(LootTable.ITEMS[low_bonus]["level_req"]) <= 5, "level-5 bonus never above level 5")
	var ex_rng := RandomNumberGenerator.new()
	ex_rng.seed = 11
	for i in 500:
		t.check(LootTable.roll_boss_bonus(ex_rng, 9, "glacier_plate") != "glacier_plate", "bonus never returns the excluded id")
	t.done()
