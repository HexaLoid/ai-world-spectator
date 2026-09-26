extends RefCounted

func _m(name: String, role: String) -> Dictionary:
	return {"id": name, "name": name, "role": role}

func _names(members: Array) -> Array:
	var out: Array = []
	for m in members:
		out.append(m["name"])
	return out

func run(t) -> void:
	var pool := [_m("Kaelen", "tank"), _m("Elowen", "healer"), _m("Brynhild", "melee"), _m("Gorrim", "melee"), _m("Vesper", "magic"), _m("Hrolf", "melee")]

	# a melee hero with an empty party: tank, healer, then two damage dealers
	var picks := PartyBuilder.missing_members("melee", [], pool, 5)
	t.check_eq(_names(picks), ["Kaelen", "Elowen", "Brynhild", "Gorrim"], "tank, healer, then damage in pool order")

	# a tank hero needs no second tank
	picks = PartyBuilder.missing_members("tank", [], pool, 5)
	t.check_eq(_names(picks), ["Elowen", "Brynhild", "Gorrim", "Vesper"], "a tank hero adds a healer and damage")

	# a healer hero needs no healer
	picks = PartyBuilder.missing_members("healer", [], pool, 5)
	t.check_eq(_names(picks), ["Kaelen", "Brynhild", "Gorrim", "Vesper"], "a healer hero adds a tank and damage")

	# existing members stay and count
	var party := [_m("Kaelen", "tank"), _m("Elowen", "healer")]
	picks = PartyBuilder.missing_members("magic", party, pool, 5)
	t.check_eq(_names(picks), ["Brynhild", "Gorrim"], "party already has tank and healer: two damage dealers join")
	for p in picks:
		t.check(p["name"] != "Kaelen" and p["name"] != "Elowen", "never re-adds a member already in the party")

	# missing roles come first even when the party has damage dealers
	picks = PartyBuilder.missing_members("magic", [_m("Brynhild", "melee"), _m("Gorrim", "melee")], pool, 5)
	t.check_eq(_names(picks), ["Kaelen", "Elowen"], "tank and healer first")

	# a role missing from the pool is skipped
	var no_healer := [_m("Kaelen", "tank"), _m("Brynhild", "melee"), _m("Gorrim", "melee")]
	picks = PartyBuilder.missing_members("melee", [], no_healer, 5)
	t.check_eq(_names(picks), ["Kaelen", "Brynhild", "Gorrim"], "no healer available: fill with what exists")

	# never more than the free slots
	picks = PartyBuilder.missing_members("melee", [_m("A", "melee"), _m("B", "melee"), _m("C", "melee")], pool, 5)
	t.check_eq(picks.size(), 1, "one free slot: one member")
	picks = PartyBuilder.missing_members("melee", [_m("A", "melee"), _m("B", "melee"), _m("C", "melee"), _m("D", "melee")], pool, 5)
	t.check_eq(picks.size(), 0, "full party: nobody joins")
	t.check_eq(PartyBuilder.missing_members("melee", [], [], 5).size(), 0, "empty pool")
	t.check_eq(PartyBuilder.missing_members("melee", [], pool, 3).size(), 2, "size 3 party: two joiners")
	t.check_eq(_names(PartyBuilder.missing_members("melee", [], pool, 5)), _names(PartyBuilder.missing_members("melee", [], pool, 5)), "deterministic")
	t.done()
