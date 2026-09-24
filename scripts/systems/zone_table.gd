class_name ZoneTable
extends RefCounted

## Each zone's world-space bounds (same 20px inset from its background rect
## convention Thornfield Meadow already used) and its center, which is what
## the "travel" AI state walks toward. `center` doubles as the arrival point
## and the initial spawn/respawn point for its own zone.
const ZONES := {
	"thornfield_meadow": {
		"name": "Thornfield Meadow",
		"center": Vector2(0, 0),
		"bounds_min": Vector2(-380, -280),
		"bounds_max": Vector2(380, 280),
	},
	"blackthorn_forest": {
		"name": "Blackthorn Forest",
		"center": Vector2(2200, 0),
		"bounds_min": Vector2(1820, -280),
		"bounds_max": Vector2(2580, 280),
	},
}

## Visited in a fixed back-and-forth loop by the "travel" AI state — with
## only two zones, "the other one" and "next in TRAVEL_ORDER" are the same
## thing, but this makes a third zone a data change, not a logic change.
const TRAVEL_ORDER := ["thornfield_meadow", "blackthorn_forest"]

## Encompasses every zone's bounds plus the corridor between them, so the
## character isn't clamped back into its origin zone mid-"travel".
const WORLD_BOUNDS_MIN := Vector2(-380, -280)
const WORLD_BOUNDS_MAX := Vector2(2580, 280)

static func next_zone_id(current_zone_id: String) -> String:
	var index := TRAVEL_ORDER.find(current_zone_id)
	return TRAVEL_ORDER[(index + 1) % TRAVEL_ORDER.size()] if index >= 0 else TRAVEL_ORDER[0]
