extends RefCounted

const CONTEXT := {"name": "Aldric", "zone": "Mirewater Swamp", "boss": "the Crypt Lord", "level": 5, "item": "Frostbrand", "killer": "the Crypt Lord", "quest": "Cull the Wolves"}
const ROLLS := [0.0, 0.3, 0.59, 0.6, 0.85, 0.999]

func run(t) -> void:
	t.check_eq(NarratorLines.EVENTS.size(), 10, "ten narrated events")
	for event in NarratorLines.EVENTS:
		for trait_id in TraitTable.ids():
			for roll in ROLLS:
				var line := NarratorLines.line_for(event, trait_id, CONTEXT, roll)
				var label := "%s/%s/%s" % [event, trait_id, str(roll)]
				t.check(line != "", "%s: non-empty" % label)
				t.check(not line.contains("{") and not line.contains("}"), "%s: no unresolved placeholder" % label)
				t.check(not line.contains("[") and not line.contains("%"), "%s: no BBCode or format characters" % label)
	t.check_eq(NarratorLines.line_for("nope", "steady", CONTEXT, 0.1), "", "unknown event: empty")
	t.check_eq(NarratorLines.line_for("level_up", "steady", CONTEXT, 0.4), NarratorLines.line_for("level_up", "steady", CONTEXT, 0.4), "deterministic")

	# placeholders are filled from the context
	t.check(NarratorLines.line_for("zone_arrive", "steady", CONTEXT, 0.1).contains("Mirewater Swamp"), "zone line names the zone")
	t.check(NarratorLines.line_for("boss_engaged", "steady", CONTEXT, 0.1).contains("the Crypt Lord"), "boss line names the boss")
	t.check(NarratorLines.line_for("level_up", "steady", CONTEXT, 0.1).contains("5"), "level line has the level")
	t.check(NarratorLines.line_for("epic_loot", "steady", CONTEXT, 0.1).contains("Frostbrand"), "loot line names the item")
	t.check(NarratorLines.line_for("quest_done", "steady", CONTEXT, 0.1).contains("Cull the Wolves"), "quest line names the quest")

	# missing context falls back instead of leaving holes
	var empty_death := NarratorLines.line_for("death", "steady", {}, 0.1)
	t.check(empty_death != "" and not empty_death.contains("{"), "death with no context still reads")

	# a trait line is used when roll < 0.6, neutral otherwise
	var neutral := NarratorLines.line_for("level_up", "steady", CONTEXT, 0.1)
	var trait_line := NarratorLines.line_for("level_up", "cautious", CONTEXT, 0.1)
	t.check(trait_line != neutral, "cautious low roll gives a trait line")
	t.check_eq(NarratorLines.line_for("level_up", "cautious", CONTEXT, 0.9), NarratorLines.line_for("level_up", "steady", CONTEXT, 0.9), "high roll gives the same neutral line for any trait")
	t.done()
