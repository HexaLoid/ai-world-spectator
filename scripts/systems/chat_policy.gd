class_name ChatPolicy
extends RefCounted

## Pure rate-limiting rules for ally chat. Times are game milliseconds.

const GLOBAL_COOLDOWN_MS := 6000.0
const SPEAKER_COOLDOWN_MS := 20000.0
const AMBIENT_MIN_MS := 30000.0
const AMBIENT_SPAN_MS := 30000.0

## Probability (0.0-1.0) that a given event produces a line at all.
const EVENT_CHANCE := {
	"ally_joined": 1.0,
	"leader_level_up": 0.9,
	"elite_kill": 0.9,
	"zone_arrive": 0.8,
	"leader_died": 0.8,
	"ally_level_up": 0.8,
	"leader_loot": 0.7,
	"leader_low_hp": 0.6,
	"ally_died": 0.5,
	"ambient": 1.0,
}

## Events that ignore the cooldowns (two allies join at the start and both greet).
const BYPASS_COOLDOWN_EVENTS := ["ally_joined"]

## True if a roll in [0, 1) should let `event` produce a line. Unknown events never fire.
static func should_fire(event: String, roll: float) -> bool:
	return roll < float(EVENT_CHANCE.get(event, 0.0))

## True if enough game time has passed since the last line overall and since
## this speaker last spoke (both are checked; the bypass events skip both).
static func can_speak(event: String, now_ms: float, last_global_ms: float, last_speaker_ms: float) -> bool:
	if BYPASS_COOLDOWN_EVENTS.has(event):
		return true
	return now_ms - last_global_ms >= GLOBAL_COOLDOWN_MS and now_ms - last_speaker_ms >= SPEAKER_COOLDOWN_MS

## Delay until the next ambient line for a roll in [0, 1]: 30-60 s.
static func next_ambient_delay_ms(roll: float) -> float:
	return AMBIENT_MIN_MS + roll * AMBIENT_SPAN_MS
