extends RefCounted

func run(t) -> void:
	var fresh := JobState.new()
	t.check_eq(fresh.level, 1, "default level")
	t.check_eq(fresh.xp, 0, "default xp")
	t.check_eq(fresh.equipment, {}, "default equipment is empty")

	var made := JobState.create(5, 900, {"weapon": "rusty_sword"})
	t.check_eq(made.level, 5, "create sets level")
	t.check_eq(made.xp, 900, "create sets xp")
	t.check_eq(made.equipment, {"weapon": "rusty_sword"}, "create sets equipment")

	var copy := made.duplicate()
	copy.equipment["head"] = "iron_helm"
	copy.level = 6
	t.check_eq(made.equipment, {"weapon": "rusty_sword"}, "duplicate does not share the equipment dictionary")
	t.check_eq(made.level, 5, "duplicate does not share level")
	var input := {"weapon": "rusty_sword"}
	var stored := JobState.create(1, 0, input)
	input["chest"] = "leather_armor"
	t.check_eq(stored.equipment, {"weapon": "rusty_sword"}, "create copies the equipment it is given")
	t.done()
