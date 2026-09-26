extends RefCounted

const KEYS := ["title", "flee_hp", "rest_hp", "item_range_mult", "stay_mult", "blurb", "remark"]

func run(t) -> void:
	t.check_eq(TraitTable.ORDER, ["steady", "cautious", "reckless", "greedy", "explorer"], "trait order")
	t.check_eq(TraitTable.ids().size(), 5, "five traits")
	for id in TraitTable.ids():
		var def := TraitTable.get_def(id)
		for key in KEYS:
			t.check(def.has(key), "%s has %s" % [id, key])
		t.check(float(def["flee_hp"]) < float(def["rest_hp"]), "%s: flee below rest" % id)
		t.check(float(def["flee_hp"]) > 0.0 and float(def["rest_hp"]) < 1.0, "%s: thresholds in (0, 1)" % id)
		t.check(float(def["item_range_mult"]) >= 1.0, "%s: item range never shrinks" % id)
		t.check(float(def["stay_mult"]) > 0.0 and float(def["stay_mult"]) <= 1.0, "%s: stay multiplier in (0, 1]" % id)
		t.check(String(def["title"]).begins_with("the "), "%s: title reads 'the X'" % id)
		t.check_eq(TraitTable.title_of(id), def["title"], "%s: title_of" % id)

	# Steady is exactly today's behavior
	var steady := TraitTable.get_def("steady")
	t.check_near(float(steady["flee_hp"]), AIDecision.FLEE_HP_THRESHOLD, "steady flee threshold is the default")
	t.check_near(float(steady["rest_hp"]), AIDecision.REST_HP_THRESHOLD, "steady rest threshold is the default")
	t.check_near(float(steady["item_range_mult"]), 1.0, "steady item range")
	t.check_near(float(steady["stay_mult"]), 1.0, "steady stay")

	# the spec's numbers
	t.check_near(float(TraitTable.get_def("cautious")["flee_hp"]), 0.14, "cautious flees at 14%")
	t.check_near(float(TraitTable.get_def("cautious")["rest_hp"]), 0.34, "cautious rests below 34%")
	t.check_near(float(TraitTable.get_def("reckless")["flee_hp"]), 0.07, "reckless flees at 7%")
	t.check_near(float(TraitTable.get_def("reckless")["rest_hp"]), 0.20, "reckless rests below 20%")
	t.check_near(float(TraitTable.get_def("greedy")["item_range_mult"]), 1.6, "greedy notices loot from 1.6x")
	t.check_near(float(TraitTable.get_def("explorer")["stay_mult"]), 0.8, "explorer stays 20% shorter")

	# unknown ids
	t.check(TraitTable.get_def("nope").is_empty(), "unknown trait: empty def")
	t.check_eq(TraitTable.title_of("nope"), "", "unknown trait: empty title")

	# pick(): deterministic for a seeded rng, covers every trait
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 42
	b.seed = 42
	var seen := {}
	var same := true
	for i in range(300):
		var pa := TraitTable.pick(a)
		if pa != TraitTable.pick(b):
			same = false
		seen[pa] = true
	t.check(same, "pick is deterministic for the same seed")
	t.check_eq(seen.size(), 5, "300 draws cover every trait")
	t.done()
