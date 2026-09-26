class_name ZoneTable
extends RefCounted

const DEFAULT_STAY_DURATION_MS := 45000.0

## Each zone's world-space bounds (same 20px inset from its background rect
## convention Thornfield Meadow established) and its center, which is what
## the "travel" AI state walks toward. `center` doubles as the arrival point
## and the initial spawn/respawn point for its own zone. `min_level`
## (default 1) gates a zone out of the travel rotation until the character
## is strong enough — see next_zone_id(). `stay_duration_ms` overrides
## DEFAULT_STAY_DURATION_MS for zones that should feel shorter/longer to
## dwell in (e.g. a one-boss dungeon room). `instanced: true` marks a dungeon:
## it is not part of the travel rotation (TRAVEL_ORDER) and the dungeon run
## teleports the party there.
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
	"sundered_crypt": {
		"name": "Sundered Crypt",
		"center": Vector2(4400, 0),
		# A small, enclosed 360x360 room (20px inset from a 400x400
		# background) rather than an open field like the other two zones —
		# see SunderedCrypt.tscn's aggro_range_override comment for why.
		"bounds_min": Vector2(4220, -180),
		"bounds_max": Vector2(4580, 180),
		"min_level": 3,
		"stay_duration_ms": 20000.0,
	},
	"mirewater_swamp": {
		"name": "Mirewater Swamp",
		"center": Vector2(6600, 0),
		"bounds_min": Vector2(6220, -280),
		"bounds_max": Vector2(6980, 280),
		"min_level": 4,
	},
	"frostpeak_pass": {
		"name": "Frostpeak Pass",
		"center": Vector2(8800, 0),
		"bounds_min": Vector2(8420, -280),
		"bounds_max": Vector2(9180, 280),
		"min_level": 7,
	},
	"hollowed_vault": {
		"name": "Hollowed Vault",
		"instanced": true,
		"center": Vector2(12000, 0),
		"bounds_min": Vector2(11250, -200),
		"bounds_max": Vector2(12750, 200),
		"min_level": 8,
		"stay_duration_ms": 60000.0,
	},
}

## Visited in a fixed rotation by the "travel" AI state, skipping any zone
## whose min_level the character hasn't reached yet (see next_zone_id()).
const TRAVEL_ORDER := ["thornfield_meadow", "blackthorn_forest", "sundered_crypt", "mirewater_swamp", "frostpeak_pass"]

## Encompasses every zone's bounds plus the corridors between them, so the
## character isn't clamped back into its origin zone mid-"travel". Y range
## is driven by the two larger outdoor zones; Sundered Crypt's smaller room
## fits within it.
const WORLD_BOUNDS_MIN := Vector2(-380, -280)
const WORLD_BOUNDS_MAX := Vector2(12750, 280)

## Every zone in display order: the travel loop, then instanced zones (dungeons).
static func all_zone_order() -> Array:
	var order: Array = TRAVEL_ORDER.duplicate()
	for id in ZONES.keys():
		if bool(ZONES[id].get("instanced", false)) and not order.has(id):
			order.append(id)
	return order

## Next zone in TRAVEL_ORDER after current_zone_id that the character's
## `level` actually qualifies for (min_level defaults to 1, so both
## starting zones are always eligible). Falls back to TRAVEL_ORDER[0] if
## current_zone_id isn't recognized, and to the immediate next zone if
## somehow nothing is eligible (shouldn't happen — Thornfield/Blackthorn
## have no gate).
static func next_zone_id(current_zone_id: String, level: int = 1) -> String:
	var index := TRAVEL_ORDER.find(current_zone_id)
	var start := index + 1 if index >= 0 else 0
	for i in range(TRAVEL_ORDER.size()):
		var candidate: String = TRAVEL_ORDER[(start + i) % TRAVEL_ORDER.size()]
		if level >= int(ZONES[candidate].get("min_level", 1)):
			return candidate
	return TRAVEL_ORDER[(start) % TRAVEL_ORDER.size()]

## Whether entering `entered_zone_id` ends the current travel leg (heading
## for `destination_id`, "" when not traveling). Zones crossed on the way to
## the destination don't count; with no leg in progress (wandering or a
## Charge across a border) any zone entered becomes the new home zone.
static func is_travel_arrival(entered_zone_id: String, destination_id: String) -> bool:
	return destination_id == "" or entered_zone_id == destination_id

static func stay_duration_ms(zone_id: String) -> float:
	return float(ZONES[zone_id].get("stay_duration_ms", DEFAULT_STAY_DURATION_MS))
