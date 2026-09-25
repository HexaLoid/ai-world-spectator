extends RefCounted

func run(t) -> void:
	var warrior: Dictionary = AbilityTable.CLASSES["warrior"]
	var mage: Dictionary = AbilityTable.CLASSES["mage"]

	# score()
	t.check_near(ItemScoring.score("iron_sword", warrior), 21.0, "warrior scores iron_sword (7 damage x3)")
	t.check_near(ItemScoring.score("steel_sword", warrior), 37.0, "warrior scores steel_sword (11x3 + 2 STR x2)")
	t.check_near(ItemScoring.score("steel_sword", mage), 33.0, "mage ignores strength")
	t.check_near(ItemScoring.score("arcane_staff", mage), 38.0, "mage scores arcane_staff (8x3 + 7 INT x2)")
	t.check_near(ItemScoring.score("arcane_staff", warrior), 24.0, "warrior ignores intellect")
	t.check_near(ItemScoring.score("", warrior), 0.0, "empty slot scores 0")
	t.check_near(ItemScoring.score("no_such_item", warrior), 0.0, "unknown item scores 0")

	# crit is a 0-1 fraction; its weight must make crit gear competitive
	t.check_near(ItemScoring.score("lucky_charm", warrior), 5.0, "lucky_charm (+5% crit) scores 5")
	t.check_near(ItemScoring.score("amulet_of_wrath", warrior), 32.0, "amulet_of_wrath scores 2x3 + 3x2 + 20")
	for cls in [warrior, mage]:
		t.check(ItemScoring.score("ring_of_fortune", cls) > ItemScoring.score("ring_of_vigor", cls), "ring_of_fortune outscores ring_of_vigor")
		t.check(ItemScoring.score("ring_of_fortune", cls) > ItemScoring.score("copper_ring", cls), "ring_of_fortune outscores copper_ring")
	t.check(ItemScoring.is_upgrade("ring_of_vigor", "ring_of_fortune", warrior, 3), "ring_of_fortune is an upgrade over ring_of_vigor")

	# meets_level()
	t.check(ItemScoring.meets_level("steel_sword", 3), "level 3 meets steel_sword's requirement")
	t.check(not ItemScoring.meets_level("steel_sword", 2), "level 2 does not meet steel_sword's requirement")

	# is_upgrade()
	t.check(ItemScoring.is_upgrade("", "rusty_sword", warrior, 1), "anything useful beats an empty slot")
	t.check(ItemScoring.is_upgrade("iron_sword", "steel_sword", warrior, 3), "steel beats iron at level 3")
	t.check(not ItemScoring.is_upgrade("iron_sword", "steel_sword", warrior, 2), "level requirement blocks an upgrade")
	t.check(not ItemScoring.is_upgrade("steel_sword", "iron_sword", warrior, 5), "a downgrade is not an upgrade")
	t.check(not ItemScoring.is_upgrade("iron_sword", "iron_sword", warrior, 5), "an equal item is not an upgrade (strict >)")
	t.check(not ItemScoring.is_upgrade("", "health_potion", warrior, 5), "consumables are never equipped")
	t.check(not ItemScoring.is_upgrade("", "no_such_item", warrior, 5), "unknown items are never equipped")
	t.check(ItemScoring.is_upgrade("", "tower_shield", mage, 5), "a mage still values a shield's armor over nothing")
	t.check(ItemScoring.is_upgrade("rusty_sword", "arcane_staff", mage, 3), "mage prefers the staff")
	t.check(not ItemScoring.is_upgrade("", "champions_plate", {}, 5), "an empty class_def scores everything 0, so nothing is an upgrade")

	# describe_stats()
	t.check_eq(ItemScoring.describe_stats("iron_helm"), "+2 armor, +10 HP", "describe iron_helm")
	t.check_eq(ItemScoring.describe_stats("lucky_charm"), "+5% crit", "describe crit as a percentage")
	t.check_eq(ItemScoring.describe_stats("steel_sword"), "+11 damage, +2 STR", "describe uses STAT_ORDER")
	t.check_eq(ItemScoring.describe_stats("health_potion"), "", "consumables have no stat text")
	t.done()
