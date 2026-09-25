extends RefCounted

func run(t) -> void:
	var state := CodexState.new()
	t.check_eq(state.enemies_met_count(), 0, "starts with no enemies met")
	t.check_eq(state.items_found_count(), 0, "starts with no items found")
	t.check_eq(state.zones_visited_count(), 0, "starts with no zones visited")

	# enemies
	t.check(state.discover_enemy("wolf"), "first meeting is new")
	t.check(not state.discover_enemy("wolf"), "second meeting is not new")
	t.check(state.enemy_met("wolf"), "wolf is met")
	t.check(not state.enemy_met("dire_wolf"), "dire wolf is not met")
	t.check(not state.discover_enemy("no_such_enemy"), "unknown enemy ids are ignored")
	t.check(not state.enemy_met("no_such_enemy"), "unknown enemy is never met")
	t.check_eq(state.enemies_met_count(), 1, "one enemy met")

	# items
	t.check(state.discover_item("iron_sword"), "first find is new")
	t.check(not state.discover_item("iron_sword"), "second find is not new")
	t.check(state.item_found("iron_sword"), "iron sword is found")
	t.check(state.discover_item("health_potion"), "consumables can be discovered")
	t.check(not state.discover_item("no_such_item"), "unknown item ids are ignored")
	t.check_eq(state.items_found_count(), 2, "two items found")

	# zones
	t.check(state.visit_zone("thornfield_meadow"), "first visit is new")
	t.check(not state.visit_zone("thornfield_meadow"), "second visit is not new")
	t.check(state.zone_visited("thornfield_meadow"), "meadow is visited")
	t.check(not state.visit_zone("no_such_zone"), "unknown zone ids are ignored")
	t.check_eq(state.zones_visited_count(), 1, "one zone visited")

	# independence
	t.check(not state.item_found("wolf"), "kinds do not share ids")
	t.check(not state.zone_visited("iron_sword"), "kinds do not share ids (zone)")

	# separate instances are separate
	var other := CodexState.new()
	t.check_eq(other.enemies_met_count(), 0, "a new instance starts empty")
	t.done()
