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
		if item.get("rarity", "") == "epic":
			t.check(level_req <= 3, "%s (epic) is equippable by the level a boss/quest hands it out" % item_id)
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
				t.check(int(LootTable.ITEMS[reward]["level_req"]) <= int(quest["min_level"]), "quest %s reward %s is equippable at the quest's min_level" % [quest["id"], reward])
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
