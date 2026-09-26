extends RefCounted

const EVENTS := [
	"ally_joined", "ally_level_up", "ally_died", "elite_kill", "leader_level_up",
	"leader_loot", "zone_arrive", "leader_low_hp", "leader_died", "ambient",
]

func run(t) -> void:
	t.check_eq(ChatLines.TEMPLATES.size(), EVENTS.size(), "template table covers exactly the ten events")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var vars := {"leader": "Aldric", "ally": "Kaelen", "enemy": "Bandit Captain",
		"item": "Iron Helm", "zone": "Blackthorn Forest", "level": 4}
	for event in EVENTS:
		var templates: Array = ChatLines.TEMPLATES.get(event, [])
		t.check(templates.size() >= 3, "%s has at least three templates" % event)
		for template in templates:
			t.check(String(template) != "", "%s template is non-empty" % event)
		# Every template must resolve fully with a complete var set.
		for i in 40:
			var text := ChatLines.pick(event, rng, vars)
			t.check(text != "", "%s picks a non-empty line" % event)
			t.check(not text.contains("{") and not text.contains("}"), "%s line has no leftover placeholder: %s" % [event, text])

	# placeholder filling
	var joined := ChatLines.TEMPLATES["ally_joined"] as Array
	var found_leader := false
	for template in joined:
		if String(template).contains("{leader}"):
			found_leader = true
	t.check(found_leader, "ally_joined uses the {leader} placeholder somewhere")
	rng.seed = 1
	var levelup := ChatLines.pick("ally_level_up", rng, {"level": 7})
	t.check(levelup.contains("7"), "level is filled in (every ally_level_up template uses {level})")

	# missing vars become empty strings, never leftovers
	for i in 40:
		var partial := ChatLines.pick("elite_kill", rng, {})
		t.check(not partial.contains("{"), "missing vars leave no braces: %s" % partial)

	# unknown event
	t.check_eq(ChatLines.pick("no_such_event", rng, vars), "", "unknown event returns an empty string")

	# format()
	var party_line := ChatLines.format("party", "Kaelen", "Hello there")
	t.check(party_line.contains("[lb]Party[rb]"), "party tag")
	t.check(party_line.contains("[b]Kaelen[/b]: Hello there"), "bold speaker then text")
	t.check(party_line.contains("6fa8dc"), "party color")
	var zone_line := ChatLines.format("zone", "Gorrim", "Hi")
	t.check(zone_line.contains("[lb]Zone[rb]") and zone_line.contains("d9b382"), "zone tag and color")
	t.check(ChatLines.format("weird", "X", "y").contains("[lb]Zone[rb]"), "unknown channel falls back to the zone style")
	t.check(ChatLines.format("story", "Narrator", "It begins.").contains("[lb]Story[rb]"), "story channel has its own label")
	t.check(not ChatLines.format("story", "Narrator", "It begins.").contains("[lb]Zone[rb]"), "story is not the zone style")
	t.done()
