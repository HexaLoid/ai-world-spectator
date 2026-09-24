class_name AbilityTable
extends RefCounted

## Per-class resource and ability-loadout definitions. Only "warrior" is
## populated in this slice; the CLASSES/ABILITIES split exists so a second
## class can be added later without restructuring Character or the HUD.
const CLASSES := {
	"warrior": {
		"resource_name": "Rage",
		"max_resource": 100.0,
		"resource_decay_per_second": 2.0,
		"rage_per_swing": 5.0,
		"rage_per_hit_taken": 3.0,
		"abilities": ["charge", "rend", "heroic_strike", "second_wind"],
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
}
