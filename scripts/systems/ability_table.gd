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
const CLASSES := {
	"warrior": {
		"resource_name": "Rage",
		"resource_color": Color(0.8, 0.35, 0.05, 1.0),
		"max_resource": 100.0,
		"resource_decay_per_second": 2.0,
		"rage_per_swing": 5.0,
		"rage_per_hit_taken": 3.0,
		"sprite_tint": Color(1.0, 1.0, 1.0, 1.0),
		"abilities": ["charge", "rend", "heroic_strike", "second_wind"],
	},
	"mage": {
		"resource_name": "Mana",
		"resource_color": Color(0.25, 0.45, 0.9, 1.0),
		"max_resource": 100.0,
		"resource_regen_per_second": 6.0,
		"sprite_tint": Color(0.55, 0.65, 1.0, 1.0),
		# No gap-closer — the mage has no Charge equivalent, so "chase" just
		# walks. Mana comes back on its own between fights instead of being
		# built by fighting, the opposite tradeoff from the warrior's Rage.
		"abilities": ["frost_nova", "arcane_bolt", "mana_ward"],
	},
}

## Each entry's "kind" selects which branch of Character's ability-execution
## code runs it: "gap_closer" (Charge), "melee_hit" (a bonus-damage attack),
## "bleed" (a damage-over-time application), "self_heal" (Second Wind).
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
}
