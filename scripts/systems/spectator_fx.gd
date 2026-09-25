class_name SpectatorFx
extends RefCounted

## Pure decisions for the spectator visual effects (no nodes): how big a damage
## number is, what color it is, how hard the camera shakes, and when a kill
## gets slow motion. Consumed by FloatingText/Main, the camera and BossEvents.

const LARGE_HIT := 40
## A hit worth at least this fraction of the target's max HP shakes the camera.
const HEAVY_FRACTION := 0.15
const SLOW_SCALE := 0.25
const SLOW_DURATION_S := 0.6

const HEAL_COLOR := Color(0.3, 0.9, 0.3, 1.0)
const CRIT_COLOR := Color(1.0, 0.82, 0.2, 1.0)
const CHARACTER_HIT_COLOR := Color(1.0, 0.45, 0.15, 1.0)
const ENEMY_HIT_COLOR := Color(1.0, 0.75, 0.72, 1.0)

static func number_scale(amount: int, is_crit: bool, is_boss_hit: bool) -> float:
	var s := 1.0
	if is_crit and is_boss_hit:
		s = 1.8
	elif is_crit:
		s = 1.5
	elif is_boss_hit:
		s = 1.3
	if amount >= LARGE_HIT:
		s += 0.3
	return s

static func number_color(is_heal: bool, is_crit: bool, on_character: bool) -> Color:
	if is_heal:
		return HEAL_COLOR
	if is_crit:
		return CRIT_COLOR
	if on_character:
		return CHARACTER_HIT_COLOR
	return ENEMY_HIT_COLOR

## 0..1. Zero for ordinary hits; crits, boss hits and hits worth 15%+ of the
## target's max HP shake the camera, more for bigger fractions.
static func shake_strength(amount: int, is_crit: bool, on_character: bool, is_boss_hit: bool, max_hp: int) -> float:
	var fraction := float(maxi(amount, 0)) / float(maxi(max_hp, 1))
	var s := 0.0
	if is_boss_hit:
		s = 0.25
	if is_crit:
		s = maxf(s, 0.35)
	if fraction >= HEAVY_FRACTION:
		s = maxf(s, 0.3 + minf(fraction, 0.6))
	if s > 0.0 and on_character:
		s += 0.1
	return clampf(s, 0.0, 1.0)

static func should_slow_kill(is_boss: bool, time_scale: float) -> bool:
	return is_boss and time_scale > 0.0
