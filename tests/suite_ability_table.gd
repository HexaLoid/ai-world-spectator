extends RefCounted

const VALID_PRIMARY_STATS := ["strength", "intellect"]

func run(t) -> void:
	t.check(AbilityTable.CLASSES.size() >= 2, "at least two classes exist")
	for class_id in AbilityTable.CLASSES:
		var def: Dictionary = AbilityTable.CLASSES[class_id]
		t.check(VALID_PRIMARY_STATS.has(def.get("primary_stat", "")), "%s has a valid primary_stat" % class_id)
		var weights: Dictionary = def.get("stat_weights", {})
		t.check(float(weights.get("damage", 0.0)) > 0.0, "%s weights damage" % class_id)
		t.check(float(weights.get(def.get("primary_stat", ""), 0.0)) > 0.0, "%s weights its primary stat" % class_id)
	t.check_near(float(AbilityTable.CLASSES["warrior"]["stat_weights"]["damage"]), 3.0, "warrior damage weight")
	t.check_near(float(AbilityTable.CLASSES["mage"]["stat_weights"]["intellect"]), 2.0, "mage intellect weight")
	t.done()
