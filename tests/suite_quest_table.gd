extends RefCounted

func run(t) -> void:
	var ids := {}
	for quest in QuestTable.QUESTS:
		t.check(not ids.has(quest["id"]), "quest id %s is unique" % quest["id"])
		ids[quest["id"]] = quest
	t.check_eq(QuestTable.QUESTS.size(), 13, "thirteen quests")
	for quest in QuestTable.QUESTS:
		var id: String = quest["id"]
		t.check(not EnemyTable.ids_named(quest["target_name"]).is_empty(), "%s targets a real enemy (%s)" % [id, quest["target_name"]])
		t.check(int(quest["count"]) >= 1, "%s has a positive count" % id)
		t.check(int(quest["xp_reward"]) > 0, "%s pays xp" % id)
		t.check(int(quest["min_level"]) >= 1 and int(quest["min_level"]) <= LevelingSystem.MAX_LEVEL, "%s min_level in range" % id)
		var reward: String = quest["item_reward"]
		if reward != "":
			t.check(LootTable.ITEMS.has(reward), "%s reward %s exists" % [id, reward])
			if LootTable.ITEMS.has(reward):
				t.check(int(LootTable.ITEMS[reward].get("level_req", 1)) <= int(quest["min_level"]), "%s reward %s is equippable at the quest's level" % [id, reward])
		for prereq in quest["requires"]:
			t.check(ids.has(prereq), "%s prerequisite %s exists" % [id, prereq])
			if ids.has(prereq):
				t.check(int(ids[prereq]["min_level"]) <= int(quest["min_level"]), "%s does not require a higher-level quest (%s)" % [id, prereq])
	# the chains have no cycles
	for quest in QuestTable.QUESTS:
		t.check(not _has_cycle(ids, quest["id"], []), "%s has no prerequisite cycle" % quest["id"])
	# the two intro quests are always available at level 1
	var intro := 0
	for quest in QuestTable.QUESTS:
		if quest["requires"].is_empty() and int(quest["min_level"]) == 1:
			intro += 1
	t.check(intro >= 2, "at least two level-1 quests without prerequisites")
	# the new chain
	for id in ["drain_the_mire", "bog_bandits", "the_mire_tyrant", "frozen_fangs", "raiders_of_the_pass", "raider_captain_bounty", "the_frostpeak_warlord"]:
		t.check(ids.has(id), "new quest %s exists" % id)

func _has_cycle(ids: Dictionary, id: String, path: Array) -> bool:
	if path.has(id):
		return true
	var next_path := path.duplicate()
	next_path.append(id)
	for prereq in ids[id]["requires"]:
		if ids.has(prereq) and _has_cycle(ids, prereq, next_path):
			return true
	return false
