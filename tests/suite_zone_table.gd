extends RefCounted

func run(t) -> void:
	var instanced_count := 0
	for id in ZoneTable.ZONES:
		if bool(ZoneTable.ZONES[id].get("instanced", false)):
			instanced_count += 1
	t.check_eq(ZoneTable.TRAVEL_ORDER.size() + instanced_count, ZoneTable.ZONES.size(), "travel order plus instanced zones cover every zone")
	for id in ZoneTable.TRAVEL_ORDER:
		t.check(ZoneTable.ZONES.has(id), "travel order id %s exists" % id)
	for id in ZoneTable.ZONES:
		if not bool(ZoneTable.ZONES[id].get("instanced", false)):
			t.check(ZoneTable.TRAVEL_ORDER.has(id), "zone %s is in the travel order" % id)
	t.check(ZoneTable.ZONES.has("mirewater_swamp") and ZoneTable.ZONES.has("frostpeak_pass"), "new zones exist")
	t.check_eq(ZoneTable.ZONES["mirewater_swamp"]["min_level"], 4, "swamp min level")
	t.check_eq(ZoneTable.ZONES["frostpeak_pass"]["min_level"], 7, "pass min level")

	var previous_min := 1
	var previous_center_x := -INF
	for id in ZoneTable.TRAVEL_ORDER:
		var zone: Dictionary = ZoneTable.ZONES[id]
		var bmin: Vector2 = zone["bounds_min"]
		var bmax: Vector2 = zone["bounds_max"]
		var center: Vector2 = zone["center"]
		t.check(String(zone["name"]) != "", "%s has a name" % id)
		t.check(bmin.x < bmax.x and bmin.y < bmax.y, "%s bounds are a real rectangle" % id)
		t.check(center.x > bmin.x and center.x < bmax.x and center.y > bmin.y and center.y < bmax.y, "%s center is inside its bounds" % id)
		t.check(center.x > previous_center_x, "%s lies further along the world line than the previous zone" % id)
		previous_center_x = center.x
		var min_level := int(zone.get("min_level", 1))
		t.check(min_level >= previous_min, "%s min_level does not decrease along the travel order" % id)
		t.check(min_level <= LevelingSystem.MAX_LEVEL, "%s min_level is reachable" % id)
		previous_min = min_level
		t.check(bmin.x >= ZoneTable.WORLD_BOUNDS_MIN.x and bmin.y >= ZoneTable.WORLD_BOUNDS_MIN.y, "%s min bounds inside the world" % id)
		var world_max: Vector2 = ZoneTable.world_bounds_max(bool(zone.get("instanced", false)))
		t.check(bmax.x <= world_max.x and bmax.y <= world_max.y, "%s max bounds inside the world" % id)
		t.check(ZoneTable.stay_duration_ms(id) > 0.0, "%s has a stay duration" % id)

	# zones must not overlap each other
	var ids: Array = ZoneTable.ZONES.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Dictionary = ZoneTable.ZONES[ids[i]]
			var b: Dictionary = ZoneTable.ZONES[ids[j]]
			var overlap: bool = a["bounds_min"].x < b["bounds_max"].x and a["bounds_max"].x > b["bounds_min"].x \
				and a["bounds_min"].y < b["bounds_max"].y and a["bounds_max"].y > b["bounds_min"].y
			t.check(not overlap, "%s and %s do not overlap" % [ids[i], ids[j]])

	# the dungeon: instanced, outside the travel loop
	var vault: Dictionary = ZoneTable.ZONES["hollowed_vault"]
	t.check(bool(vault.get("instanced", false)), "the vault is instanced")
	t.check(not ZoneTable.TRAVEL_ORDER.has("hollowed_vault"), "the vault is not in the travel order")
	t.check_eq(int(vault["min_level"]), 8, "vault min level")
	t.check_eq(ZoneTable.all_zone_order().back(), "hollowed_vault", "all_zone_order ends with the vault")
	t.check_eq(ZoneTable.all_zone_order().size(), ZoneTable.ZONES.size(), "all_zone_order lists every zone once")
	for id in ZoneTable.ZONES:
		if not bool(ZoneTable.ZONES[id].get("instanced", false)):
			for level in [1, 8, 12]:
				t.check(ZoneTable.next_zone_id(id, level) != "hollowed_vault", "next_zone_id never returns the vault (%s at %d)" % [id, level])

	# travel loop by level
	t.check_eq(ZoneTable.next_zone_id("sundered_crypt", 4), "mirewater_swamp", "crypt -> swamp at level 4")
	t.check_eq(ZoneTable.next_zone_id("mirewater_swamp", 6), "thornfield_meadow", "swamp -> meadow below the pass's level")
	t.check_eq(ZoneTable.next_zone_id("mirewater_swamp", 7), "frostpeak_pass", "swamp -> pass at level 7")
	t.check_eq(ZoneTable.next_zone_id("frostpeak_pass", 10), "thornfield_meadow", "the loop wraps around")
	# Regression: the wrap-around leg (pass -> meadow) walks through the swamp;
	# that must not count as arriving there, or the rotation ping-pongs
	# swamp <-> pass forever and never reaches the meadow again.
	t.check(not ZoneTable.is_travel_arrival("mirewater_swamp", "thornfield_meadow"), "crossing a zone mid-leg is not an arrival")
	t.check(ZoneTable.is_travel_arrival("thornfield_meadow", "thornfield_meadow"), "reaching the leg's destination is an arrival")
	t.check(ZoneTable.is_travel_arrival("blackthorn_forest", ""), "with no leg in progress any zone entered is an arrival")
	t.done()
