extends RefCounted

func run(t) -> void:
	# item sources
	var maul := CodexData.item_sources("tyrants_maul")
	t.check_eq(maul["guaranteed"], ["Mire Tyrant"], "tyrants_maul is a guaranteed Mire Tyrant drop")
	t.check_eq(maul["random_from_loot_level"], -1, "an epic never drops randomly")
	var mail := CodexData.item_sources("reinforced_mail")
	t.check_eq(mail["quests"], ["The Mire Tyrant"], "reinforced_mail is a quest reward")
	var rusty := CodexData.item_sources("rusty_sword")
	t.check_eq(rusty["random_from_loot_level"], 2, "rusty_sword first drops from loot level 2 enemies (lowest loot_level in the table)")
	t.check(rusty["guaranteed"].is_empty() and rusty["quests"].is_empty(), "rusty_sword has no fixed sources")
	var potion := CodexData.item_sources("health_potion")
	t.check_eq(potion["random_from_loot_level"], 2, "potions drop randomly like gear")
	var iron_sword := CodexData.item_sources("iron_sword")
	t.check(iron_sword["guaranteed"].has("Bandit Captain"), "iron_sword is guaranteed from the Bandit Captain")
	t.check(iron_sword["quests"].has("The Captain's Head"), "iron_sword is also a quest reward")
	var none := CodexData.item_sources("no_such_item")
	t.check(none["guaranteed"].is_empty() and none["quests"].is_empty() and int(none["random_from_loot_level"]) == -1, "unknown item has empty sources")

	# boss bonus sources (extra epic drop from bosses)
	t.check_eq(CodexData.item_sources("frostbrand")["boss_bonus"], ["Raider Captain", "Frostpeak Warlord"], "frostbrand can bonus-drop from the L9 bosses")
	t.check_eq(CodexData.item_sources("champions_plate")["boss_bonus"], ["Bandit Captain", "Crypt Lord", "Mire Tyrant", "Raider Captain", "Frostpeak Warlord"], "champions_plate can bonus-drop from every boss")
	t.check(not CodexData.item_sources("tyrants_maul")["boss_bonus"].has("Mire Tyrant"), "a boss's own guaranteed epic is not a bonus drop")
	t.check(CodexData.item_sources("tyrants_maul")["boss_bonus"].has("Frostpeak Warlord"), "tyrants_maul can bonus-drop from other bosses")
	t.check(CodexData.item_sources("rusty_sword")["boss_bonus"].is_empty(), "non-epics have no boss bonus source")
	t.check(CodexData.item_sources("no_such_item")["boss_bonus"].is_empty(), "unknown item has no boss bonus source")

	# every item can be found somewhere
	for item_id in LootTable.ITEMS:
		var src := CodexData.item_sources(item_id)
		var has_source: bool = not src["guaranteed"].is_empty() or not src["quests"].is_empty() or not src["boss_bonus"].is_empty() or int(src["random_from_loot_level"]) >= 0
		t.check(has_source, "%s has at least one source" % item_id)

	# zones
	t.check_eq(CodexData.zone_order(), ZoneTable.TRAVEL_ORDER, "zone_order follows the travel order")
	for zone_id in ZoneTable.ZONES:
		t.check(not CodexData.zone_enemy_ids(zone_id).is_empty(), "%s has enemies" % zone_id)
	t.check_eq(CodexData.zone_enemy_ids("mirewater_swamp"), ["mire_wolf", "bog_bandit", "mire_tyrant"], "swamp roster is ordered by hp")
	t.check_eq(CodexData.zone_boss_id("mirewater_swamp"), "mire_tyrant", "swamp boss")
	t.check_eq(CodexData.zone_boss_id("frostpeak_pass"), "frostpeak_warlord", "the pass boss is the strongest guaranteed-drop enemy")
	t.check_eq(CodexData.zone_boss_id("thornfield_meadow"), "", "the meadow has no boss")
	t.check_eq(CodexData.zone_boss_id("no_such_zone"), "", "unknown zone has no boss")
	t.check_eq(CodexData.zone_level_range("thornfield_meadow"), [1, 1], "meadow level range (the forest has no gate, so the range is one level)")
	t.check_eq(CodexData.zone_level_range("sundered_crypt"), [3, 3], "crypt level range")
	t.check_eq(CodexData.zone_level_range("frostpeak_pass"), [7, LevelingSystem.MAX_LEVEL], "the last zone runs to the level cap")

	# orderings contain every id exactly once
	var enemies := CodexData.enemy_order()
	t.check_eq(enemies.size(), EnemyTable.ENEMIES.size(), "enemy_order has every enemy")
	t.check_eq(enemies.duplicate().size(), _unique(enemies).size(), "enemy_order has no duplicates")
	t.check_eq(enemies[0], "wolf", "the weakest meadow enemy is first")
	t.check_eq(enemies[enemies.size() - 1], "frostpeak_warlord", "the final boss is last")
	var items := CodexData.item_order()
	t.check_eq(items.size(), LootTable.ITEMS.size(), "item_order has every item")
	t.check_eq(items.size(), _unique(items).size(), "item_order has no duplicates")
	t.check_eq(LootTable.ITEMS[items[0]].get("slot", ""), "weapon", "weapons come first")
	t.check_eq(LootTable.ITEMS[items[items.size() - 1]].get("type", ""), "consumable", "consumables come last")
	t.done()

func _unique(values: Array) -> Dictionary:
	var seen := {}
	for v in values:
		seen[v] = true
	return seen
