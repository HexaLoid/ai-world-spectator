class_name TraitTable
extends RefCounted

## Personality traits: one is rolled per character and changes real decisions
## (via AIDecision's optional thresholds and two Character multipliers) and
## the narration. Steady is exactly the pre-trait behavior.
##   flee_hp / rest_hp   HP fractions for AIDecision (flee < rest)
##   item_range_mult     multiplier on the distance at which loot is noticed
##   stay_mult           multiplier on how long the character stays in a zone
const ORDER := ["steady", "cautious", "reckless", "greedy", "explorer"]

const TRAITS := {
	"steady": {
		"title": "the Steady", "flee_hp": AIDecision.FLEE_HP_THRESHOLD, "rest_hp": AIDecision.REST_HP_THRESHOLD,
		"item_range_mult": 1.0, "stay_mult": 1.0,
		"blurb": "Even-tempered. Fights, rests and travels by the book.",
		"remark": "Steady on. Try again.",
	},
	"cautious": {
		"title": "the Cautious", "flee_hp": 0.25, "rest_hp": 0.45,
		"item_range_mult": 1.0, "stay_mult": 1.0,
		"blurb": "Retreats early and rests often. Rarely dies, but loses time.",
		"remark": "Perhaps a little more caution next time.",
	},
	"reckless": {
		"title": "the Reckless", "flee_hp": 0.05, "rest_hp": 0.20,
		"item_range_mult": 1.0, "stay_mult": 1.0,
		"blurb": "Fights to the last breath. Fast, and often fatal.",
		"remark": "Bold to the very end.",
	},
	"greedy": {
		"title": "the Greedy", "flee_hp": AIDecision.FLEE_HP_THRESHOLD, "rest_hp": AIDecision.REST_HP_THRESHOLD,
		"item_range_mult": 1.6, "stay_mult": 1.0,
		"blurb": "Spots loot from far away and never leaves a drop behind.",
		"remark": "The loot was not worth it.",
	},
	"explorer": {
		"title": "the Explorer", "flee_hp": AIDecision.FLEE_HP_THRESHOLD, "rest_hp": AIDecision.REST_HP_THRESHOLD,
		"item_range_mult": 1.0, "stay_mult": 0.7,
		"blurb": "Restless. Moves on to the next zone sooner.",
		"remark": "There is always another road.",
	},
}

static func ids() -> Array:
	return ORDER.duplicate()

static func get_def(id: String) -> Dictionary:
	return TRAITS.get(id, {})

static func title_of(id: String) -> String:
	return String(get_def(id).get("title", ""))

static func pick(rng: RandomNumberGenerator) -> String:
	return ORDER[rng.randi_range(0, ORDER.size() - 1)]
