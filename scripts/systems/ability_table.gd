class_name AbilityTable
extends RefCounted

## Per-class resource and ability-loadout definitions. "abilities" lists the
## ids (into ABILITIES below) that belong to this class, in priority order —
## Character never touches an ability id that isn't in its own class's list,
## and dispatches purely by each ability's "kind" (see ABILITIES), so a
## class needs no other code to plug in. "resource_regen_per_second" and
## "resource_decay_per_second" both default to 0.0 if unset; a class sets
## whichever fits its resource (an aggressive one that drains when idle, like
## Rage, vs. a patient one that recovers over time, like Mana).
## Select-screen order (by role): tank, melee, healer, magic.
const JOB_ORDER := ["warrior", "black_belt", "thief", "dragoon", "white_mage", "mage", "red_mage"]

static func job_ids() -> Array:
	return JOB_ORDER

## Display name of a job; unknown ids fall back to the capitalized id.
static func job_name(id: String) -> String:
	if id == "":
		return "Adventurer"
	return String(CLASSES.get(id, {}).get("name", id.capitalize()))

const CLASSES := {
	"warrior": {
		"name": "Warrior", "role": "tank", "blurb": "Heavy armor and Rage. Charges in and holds the line.", "ally_hp_mult": 1.3, "ally_damage_mult": 0.85,
		"resource_name": "Rage",
		"resource_color": Color(0.8, 0.35, 0.05, 1.0),
		"max_resource": 100.0,
		"resource_decay_per_second": 2.0,
		"rage_per_swing": 5.0,
		"rage_per_hit_taken": 3.0,
		"primary_stat": "strength",
		"stat_weights": {
			"damage": 3.0, "strength": 2.0, "armor": 2.0, "max_hp": 0.5, "crit_chance": 100.0,
		},
		"sprite_tint": Color(1.0, 1.0, 1.0, 1.0),
		"abilities": ["charge", "rend", "heroic_strike", "second_wind"],
	},
	"mage": {
		"name": "Black Mage", "role": "magic", "blurb": "Burns foes from a distance with Mana spells.", "ally_hp_mult": 1.0, "ally_damage_mult": 1.0,
		"resource_name": "Mana",
		"resource_color": Color(0.25, 0.45, 0.9, 1.0),
		"max_resource": 100.0,
		"resource_regen_per_second": 6.0,
		"primary_stat": "intellect",
			# Flat class bonuses (see StatCalculator.derive): the mage is the more
			# fragile class, so it gets a cushion for the level-3 Crypt Lord.
			"bonus_max_hp": 25,
			"bonus_armor": 5,
		"stat_weights": {
			"damage": 3.0, "intellect": 2.0, "armor": 0.5, "max_hp": 0.3, "crit_chance": 100.0,
		},
		"sprite_tint": Color(0.55, 0.65, 1.0, 1.0),
		# No gap-closer — the mage has no Charge equivalent, so "chase" just
		# walks. Mana comes back on its own between fights instead of being
		# built by fighting, the opposite tradeoff from the warrior's Rage.
		"abilities": ["frost_nova", "arcane_bolt", "mana_ward"],
	},
	"white_mage": {
		"name": "White Mage", "role": "healer", "blurb": "Heals the party and herself. Light damage.",
		"resource_name": "Mana", "resource_color": Color(0.85, 0.85, 1.0, 1.0),
		"max_resource": 100.0, "resource_regen_per_second": 6.0,
		"primary_stat": "intellect", "bonus_max_hp": 20, "bonus_armor": 4,
		"stat_weights": {"damage": 2.5, "intellect": 2.0, "armor": 1.0, "max_hp": 0.5, "crit_chance": 100.0},
		"sprite_tint": Color(1.0, 0.92, 0.92, 1.0),
		"abilities": ["holy", "cure", "benediction"],
		"ally_hp_mult": 0.9, "ally_damage_mult": 0.6,
	},
	"thief": {
		"name": "Thief", "role": "melee", "blurb": "Fast and lucky: high crit, and steals extra gold.",
		"resource_name": "Focus", "resource_color": Color(0.9, 0.8, 0.2, 1.0),
		"max_resource": 100.0, "resource_decay_per_second": 2.0,
		"rage_per_swing": 5.0, "rage_per_hit_taken": 3.0,
		"primary_stat": "strength", "bonus_max_hp": 10, "bonus_armor": 2,
		"bonus_crit_chance": 0.10, "gold_bonus_mult": 1.5,
		"stat_weights": {"damage": 3.0, "strength": 1.5, "armor": 1.0, "max_hp": 0.4, "crit_chance": 150.0},
		"sprite_tint": Color(0.5, 0.5, 0.58, 1.0),
		"abilities": ["dash", "backstab", "poison"],
		"ally_hp_mult": 0.9, "ally_damage_mult": 1.15,
	},
	"black_belt": {
		"name": "Black Belt", "role": "melee", "blurb": "An unarmed fighter with rapid multi-hit combos.",
		"resource_name": "Chakra", "resource_color": Color(1.0, 0.6, 0.2, 1.0),
		"max_resource": 100.0, "resource_decay_per_second": 2.0,
		"rage_per_swing": 8.0, "rage_per_hit_taken": 3.0,
		"primary_stat": "strength", "bonus_max_hp": 20, "bonus_armor": 2,
		"stat_weights": {"damage": 3.0, "strength": 2.0, "armor": 1.0, "max_hp": 0.6, "crit_chance": 100.0},
		"sprite_tint": Color(1.0, 0.82, 0.55, 1.0),
		"abilities": ["rush", "combo", "meditate"],
		"ally_hp_mult": 1.1, "ally_damage_mult": 1.0,
	},
	"dragoon": {
		"name": "Dragoon", "role": "melee", "blurb": "Leaps onto foes with a crushing spear strike.",
		"resource_name": "Focus", "resource_color": Color(0.4, 0.7, 0.95, 1.0),
		"max_resource": 100.0, "resource_decay_per_second": 2.0,
		"rage_per_swing": 5.0, "rage_per_hit_taken": 3.0,
		"primary_stat": "strength", "bonus_max_hp": 15, "bonus_armor": 3,
		"stat_weights": {"damage": 3.0, "strength": 2.0, "armor": 1.5, "max_hp": 0.5, "crit_chance": 100.0},
		"sprite_tint": Color(0.7, 0.85, 1.0, 1.0),
		"abilities": ["jump", "impulse", "elusive"],
		"ally_hp_mult": 1.0, "ally_damage_mult": 1.1,
	},
	"red_mage": {
		"name": "Red Mage", "role": "magic", "blurb": "A hybrid: spells, a little healing, and steel.",
		"resource_name": "Mana", "resource_color": Color(0.9, 0.3, 0.4, 1.0),
		"max_resource": 100.0, "resource_regen_per_second": 5.0,
		"primary_stat": "intellect", "bonus_max_hp": 20, "bonus_armor": 3,
		"stat_weights": {"damage": 3.0, "intellect": 1.5, "strength": 1.0, "armor": 1.0, "max_hp": 0.4, "crit_chance": 100.0},
		"sprite_tint": Color(1.0, 0.6, 0.62, 1.0),
		"abilities": ["verthunder", "enfeeble", "vercure"],
		"ally_hp_mult": 1.0, "ally_damage_mult": 1.0,
	},
}

## Each entry's "kind" selects which branch of Character's ability-execution
## code runs it: "gap_closer" (Charge), "melee_hit" (a bonus-damage attack),
## "bleed" (a damage-over-time application), "self_heal" (Second Wind),
## "ally_heal" (Cure: heals the lowest-HP party member below "heal_below").
## Optional parameters: "hit_count" (melee_hit strikes N times) and
## "damage_multiplier" on a gap_closer (a jump hit lands on arrival).
const ABILITIES := {
	"charge": {
		"name": "Charge",
		"icon": "res://assets/icons/charge_icon.png",
		"resource_cost": 0.0,
		"resource_gain": 15.0,
		"cooldown_ms": 6000,
		"kind": "gap_closer",
	},
	"heroic_strike": {
		"name": "Heroic Strike",
		"icon": "res://assets/icons/heroic_strike_icon.png",
		"resource_cost": 15.0,
		"cooldown_ms": 3000,
		"kind": "melee_hit",
		"damage_multiplier": 1.8,
	},
	"rend": {
		"name": "Rend",
		"icon": "res://assets/icons/rend_icon.png",
		"resource_cost": 10.0,
		"cooldown_ms": 9000,
		"kind": "bleed",
		"tick_damage_min": 2,
		"tick_damage_max": 4,
		"tick_count": 4,
		"tick_interval_ms": 1500,
	},
	"second_wind": {
		"name": "Second Wind",
		"icon": "res://assets/icons/second_wind_icon.png",
		"resource_cost": 0.0,
		"cooldown_ms": 20000,
		"kind": "self_heal",
		"heal_percent": 0.25,
	},
	"arcane_bolt": {
		"name": "Arcane Bolt",
		"icon": "res://assets/icons/arcane_bolt_icon.png",
		"resource_cost": 25.0,
		"cooldown_ms": 4000,
		"kind": "melee_hit",
		"damage_multiplier": 2.2,
	},
	"frost_nova": {
		"name": "Frost Nova",
		"icon": "res://assets/icons/frost_nova_icon.png",
		"resource_cost": 20.0,
		"cooldown_ms": 8000,
		"kind": "bleed",
		"tick_damage_min": 3,
		"tick_damage_max": 5,
		"tick_count": 4,
		"tick_interval_ms": 1200,
	},
	"mana_ward": {
		"name": "Mana Ward",
		"icon": "res://assets/icons/mana_ward_icon.png",
		"resource_cost": 30.0,
		"cooldown_ms": 18000,
		"kind": "self_heal",
		"heal_percent": 0.3,
	},
	"holy": {"name": "Holy", "icon": "res://assets/icons/arcane_bolt_icon.png", "resource_cost": 15.0, "cooldown_ms": 3500, "kind": "melee_hit", "damage_multiplier": 1.6},
	"cure": {"name": "Cure", "icon": "res://assets/icons/potion_icon.png", "resource_cost": 20.0, "cooldown_ms": 5000, "kind": "ally_heal", "heal_percent": 0.30, "heal_below": 0.65},
	"benediction": {"name": "Benediction", "icon": "res://assets/icons/mana_ward_icon.png", "resource_cost": 25.0, "cooldown_ms": 25000, "kind": "self_heal", "heal_percent": 0.35},
	"dash": {"name": "Dash", "icon": "res://assets/icons/charge_icon.png", "resource_cost": 0.0, "resource_gain": 10.0, "cooldown_ms": 8000, "kind": "gap_closer"},
	"backstab": {"name": "Backstab", "icon": "res://assets/icons/heroic_strike_icon.png", "resource_cost": 15.0, "cooldown_ms": 3500, "kind": "melee_hit", "damage_multiplier": 2.0},
	"poison": {"name": "Poison", "icon": "res://assets/icons/rend_icon.png", "resource_cost": 10.0, "cooldown_ms": 8000, "kind": "bleed", "tick_damage_min": 2, "tick_damage_max": 4, "tick_count": 5, "tick_interval_ms": 1500},
	"rush": {"name": "Rush", "icon": "res://assets/icons/charge_icon.png", "resource_cost": 0.0, "resource_gain": 15.0, "cooldown_ms": 7000, "kind": "gap_closer"},
	"combo": {"name": "Combo", "icon": "res://assets/icons/heroic_strike_icon.png", "resource_cost": 20.0, "cooldown_ms": 5000, "kind": "melee_hit", "damage_multiplier": 0.8, "hit_count": 3},
	"meditate": {"name": "Meditate", "icon": "res://assets/icons/second_wind_icon.png", "resource_cost": 0.0, "cooldown_ms": 25000, "kind": "self_heal", "heal_percent": 0.30},
	"jump": {"name": "Jump", "icon": "res://assets/icons/charge_icon.png", "resource_cost": 0.0, "resource_gain": 15.0, "cooldown_ms": 8000, "kind": "gap_closer", "damage_multiplier": 1.6},
	"impulse": {"name": "Impulse", "icon": "res://assets/icons/heroic_strike_icon.png", "resource_cost": 15.0, "cooldown_ms": 3000, "kind": "melee_hit", "damage_multiplier": 1.8},
	"elusive": {"name": "Elusive", "icon": "res://assets/icons/second_wind_icon.png", "resource_cost": 0.0, "cooldown_ms": 30000, "kind": "self_heal", "heal_percent": 0.20},
	"verthunder": {"name": "Verthunder", "icon": "res://assets/icons/arcane_bolt_icon.png", "resource_cost": 20.0, "cooldown_ms": 3500, "kind": "melee_hit", "damage_multiplier": 2.0},
	"enfeeble": {"name": "Enfeeble", "icon": "res://assets/icons/frost_nova_icon.png", "resource_cost": 15.0, "cooldown_ms": 9000, "kind": "bleed", "tick_damage_min": 2, "tick_damage_max": 4, "tick_count": 4, "tick_interval_ms": 1500},
	"vercure": {"name": "Vercure", "icon": "res://assets/icons/mana_ward_icon.png", "resource_cost": 25.0, "cooldown_ms": 20000, "kind": "self_heal", "heal_percent": 0.25},
}
