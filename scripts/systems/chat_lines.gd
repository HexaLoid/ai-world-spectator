class_name ChatLines
extends RefCounted

## Pure chat text rules: which lines each game event can produce, how the
## placeholders are filled, and how a line is formatted for the chat panel.
## Placeholders: {leader} (the spectated character), {ally} (the speaker),
## {enemy}, {item}, {zone}, {level}.

const PLACEHOLDERS := ["leader", "ally", "enemy", "item", "zone", "level"]

const TEMPLATES := {
	"ally_joined": [
		"Hey {leader}, mind if I tag along?",
		"{leader}! Room in the party for one more?",
		"Well met, {leader}. Let's go hunting.",
		"Count me in, {leader}.",
	],
	"ally_level_up": [
		"Ding! Level {level}!",
		"Finally, level {level}.",
		"Level {level} at last, that took a while.",
		"Feeling stronger already. Level {level}!",
	],
	"ally_died": [
		"Ow. That one hurt.",
		"Back in a moment, I'm down!",
		"I did not see that coming...",
		"Ugh, respawning.",
	],
	"elite_kill": [
		"Nice kill on the {enemy}, {leader}!",
		"The {enemy} is down!",
		"Did you see that {enemy} go down?",
		"{enemy} defeated. Loot time!",
	],
	"leader_level_up": [
		"Grats on level {level}, {leader}!",
		"Level {level}, {leader}, well earned.",
		"Look at you, level {level}!",
		"Nice, {leader}. Level {level}!",
	],
	"leader_loot": [
		"Ooh, {item}! Nice find, {leader}.",
		"That {item} looks great on you.",
		"Lucky drop, {leader}. {item}!",
		"Envious of that {item}.",
	],
	"zone_arrive": [
		"{zone}. Stay sharp, everyone.",
		"So this is {zone}. Let's see what lives here.",
		"Welcome to {zone}, {leader}. Lead the way.",
		"New zone, new loot. {zone} it is.",
	],
	"leader_low_hp": [
		"{leader}, watch your health!",
		"You're hurting, {leader}. Back off a bit!",
		"Careful, {leader}, HP is low!",
		"{leader}, maybe rest before the next pull?",
	],
	"leader_died": [
		"Ouch, {leader} is down!",
		"Rough one, {leader}. Shake it off.",
		"We'll get them next time, {leader}.",
		"{leader}! Up you get.",
	],
	"ambient": [
		"Anyone seen the good loot around {zone}?",
		"Looking for a group in {zone}, anyone?",
		"{zone} is quiet today.",
		"I could really use a better weapon.",
		"Wolves everywhere in {zone}, watch out.",
		"Anyone else having trouble with the bandits?",
	],
}

## channel -> [tag text, hex color]
const CHANNELS := {
	"party": ["Party", "6fa8dc"],
	"zone": ["Zone", "d9b382"],
}

## Picks a template for `event` with `rng` and fills its placeholders from
## `vars` (missing vars become empty strings). Unknown events return "".
static func pick(event: String, rng: RandomNumberGenerator, vars: Dictionary) -> String:
	var templates: Array = TEMPLATES.get(event, [])
	if templates.is_empty():
		return ""
	var text: String = templates[rng.randi_range(0, templates.size() - 1)]
	for key in PLACEHOLDERS:
		text = text.replace("{%s}" % key, str(vars.get(key, "")))
	return text

## BBCode for one chat line. The tag brackets use [lb]/[rb] so a RichTextLabel
## shows them literally instead of parsing "[Party]" as a BBCode tag.
static func format(channel: String, speaker: String, text: String) -> String:
	var info: Array = CHANNELS.get(channel, CHANNELS["zone"])
	return "[color=#%s][lb]%s[rb][/color] [b]%s[/b]: %s" % [info[1], info[0], speaker, text]
