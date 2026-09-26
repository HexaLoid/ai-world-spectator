class_name NarratorLines
extends RefCounted

## Story lines for key moments, chosen per event and personality trait. Pure:
## `line_for` returns text, `NarratorDirector` decides when to speak.
## Placeholders: {name} {zone} {boss} {level} {item} {killer} {quest} {job} {dungeon}.
## Lines are plain text (no BBCode, no % characters).

## Below this roll a trait-specific line is used (when the event has one).
const TRAIT_CHANCE := 0.6

const EVENTS := ["zone_arrive", "boss_engaged", "boss_victory", "boss_fled", "boss_defeated",
	"level_up", "epic_loot", "low_hp", "death", "quest_done", "job_change",
	"dungeon_enter", "dungeon_clear", "dungeon_fail"]

const FALLBACKS := {
	"name": "The hero", "zone": "the wilds", "boss": "the beast", "level": "?",
	"item": "a relic", "killer": "an unseen foe", "quest": "a task", "job": "a new calling", "dungeon": "the dungeon",
}

const TEMPLATES := {
	"job_change": {
		"neutral": ["{name} takes up the {job}'s path, level {level}.", "A new calling: {name} becomes a {job}, level {level}."],
		"cautious": ["{name} studies the crystal, then chooses the {job}."],
		"reckless": ["{name} grabs the crystal and becomes a {job} without a second thought."],
		"greedy": ["The crystal hums. {name} sees profit in being a {job}."],
		"explorer": ["Another road, another calling: {name} is a {job} now."],
	},
	"zone_arrive": {
		"neutral": ["{name} arrives in {zone}.", "New ground: {name} enters {zone}."],
		"cautious": ["{name} steps into {zone}, watching every shadow."],
		"reckless": ["{name} storms into {zone} without a second thought."],
		"greedy": ["{name} reaches {zone}, already eyeing the ground for treasure."],
		"explorer": ["{zone} at last. {name} smiles and keeps walking."],
	},
	"boss_engaged": {
		"neutral": ["A shape rises ahead: {boss}.", "{boss} bars the way."],
		"cautious": ["{boss} looms. {name} grips the hilt and measures the distance."],
		"reckless": ["{boss}! {name} charges before anyone can speak."],
		"greedy": ["{boss} guards something worth having. {name} licks dry lips."],
		"explorer": ["So this is what lives here: {boss}."],
	},
	"boss_victory": {
		"neutral": ["{boss} falls.", "It is over. {boss} is no more."],
		"cautious": ["{boss} falls. {name} lets out a long breath."],
		"reckless": ["{boss} falls, and {name} laughs through the blood."],
		"greedy": ["{boss} falls. Now, what did it drop?"],
		"explorer": ["{boss} falls. One more story for the road."],
	},
	"boss_fled": {
		"neutral": ["{name} breaks away from {boss}.", "Not today: {name} retreats from {boss}."],
		"cautious": ["Discretion wins. {name} backs away from {boss}."],
		"reckless": ["Even {name} knows when to run from {boss}."],
		"greedy": ["{name} abandons the prize and flees {boss}."],
		"explorer": ["{name} leaves {boss} for another day."],
	},
	"boss_defeated": {
		"neutral": ["{boss} proves too much. {name} falls.", "{name} is cut down by {boss}."],
		"cautious": ["{name} hesitated a moment too long, and {boss} did not."],
		"reckless": ["{name} charged {boss} one time too many."],
		"greedy": ["{boss} takes {name}, and the treasure stays unclaimed."],
		"explorer": ["The road ends here, at the hands of {boss}."],
	},
	"level_up": {
		"neutral": ["{name} grows stronger: level {level}.", "Level {level}. {name} feels it in every bone."],
		"cautious": ["Level {level}. {name} nods, quietly satisfied."],
		"reckless": ["Level {level}! {name} wants a bigger fight."],
		"greedy": ["Level {level}. Stronger arms carry more loot."],
		"explorer": ["Level {level}. Further roads open up."],
	},
	"epic_loot": {
		"neutral": ["Something gleams: {item}.", "{name} finds {item}, a piece of legend."],
		"cautious": ["{name} turns {item} over twice before trusting it."],
		"reckless": ["{name} snatches up {item} and swings it at once."],
		"greedy": ["{item}! {name} has never been happier."],
		"explorer": ["{item}: proof that the road pays."],
	},
	"low_hp": {
		"neutral": ["{name} is hurt and knows it.", "Blood in the dust. {name} is badly wounded."],
		"cautious": ["{name} feels the edge of danger and looks for a way out."],
		"reckless": ["{name} is bleeding, and fighting anyway."],
		"greedy": ["{name} clutches the loot and the wound alike."],
		"explorer": ["A rough stretch of road for {name}."],
	},
	"death": {
		"neutral": ["Felled by {killer}. The story does not end here.", "{name} falls to {killer}."],
		"cautious": ["Felled by {killer}. {name} was careful, and it was not enough."],
		"reckless": ["Felled by {killer}, exactly as {name} lived."],
		"greedy": ["Felled by {killer}, with empty hands."],
		"explorer": ["Felled by {killer}, far from any road."],
	},
	"quest_done": {
		"neutral": ["The job is done: {quest}.", "{name} finishes {quest}."],
		"cautious": ["{quest} is finished. {name} checks the work once more."],
		"reckless": ["{quest}: done, and quickly."],
		"greedy": ["{quest} is done. Payment, please."],
		"explorer": ["{quest} is done. On to the next horizon."],
	},
	"dungeon_enter": {
		"neutral": ["The party gathers and steps through the gate into {dungeon}.", "{name} leads four companions into {dungeon}."],
		"cautious": ["{name} counts the party twice before entering {dungeon}."],
		"reckless": ["{name} is through the gate into {dungeon} before the others can speak."],
		"greedy": ["{dungeon} must be full of treasure. {name} goes in first."],
		"explorer": ["A place no map shows: {name} enters {dungeon}."],
	},
	"dungeon_clear": {
		"neutral": ["{dungeon} is cleared. The party walks out victorious.", "Silence falls in {dungeon}. It is done."],
		"cautious": ["{dungeon} is cleared, and everyone is still standing. {name} exhales."],
		"reckless": ["{dungeon} is cleared. {name} wants to do it again."],
		"greedy": ["{dungeon} is cleared, and the loot is even better than hoped."],
		"explorer": ["{dungeon} is cleared. {name} is already thinking about the next one."],
	},
	"dungeon_fail": {
		"neutral": ["{dungeon} was too much. The party retreats.", "The run in {dungeon} ends in defeat."],
		"cautious": ["{name} should have known better than to trust the odds in {dungeon}."],
		"reckless": ["{name} pushed too far in {dungeon}."],
		"greedy": ["{dungeon} keeps its treasure, this time."],
		"explorer": ["{dungeon} was a road too far, for now."],
	},
}

## One story line for `event` and `trait_id`, or "" for an unknown event.
## `roll` (0..1) makes the choice deterministic: below TRAIT_CHANCE the trait's
## line is used when it has one, otherwise a neutral line.
static func line_for(event: String, trait_id: String, context: Dictionary, roll: float) -> String:
	var pool_set: Dictionary = TEMPLATES.get(event, {})
	if pool_set.is_empty():
		return ""
	var r := clampf(roll, 0.0, 0.999999)
	var pool: Array = pool_set["neutral"]
	var index := 0
	var trait_pool: Array = pool_set.get(trait_id, [])
	if r < TRAIT_CHANCE and not trait_pool.is_empty():
		pool = trait_pool
		index = mini(int(r / TRAIT_CHANCE * float(pool.size())), pool.size() - 1)
	else:
		index = mini(int(r * float(pool.size())), pool.size() - 1)
	return _fill(String(pool[index]), context)

static func _fill(template: String, context: Dictionary) -> String:
	var text := template
	for key in FALLBACKS.keys():
		var value := str(context.get(key, ""))
		if value == "":
			value = String(FALLBACKS[key])
		text = text.replace("{%s}" % key, value)
	return text
