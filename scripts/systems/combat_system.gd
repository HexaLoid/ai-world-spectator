class_name CombatSystem
extends RefCounted

## How far from its spawn point an enemy with nobody in aggro range may stand
## before it walks back home (see return_home_velocity()).
const LEASH_SLACK := 24.0

## Rolls a random integer damage value in [min_damage, max_damage] using the given rng.
## Callers pass their own RandomNumberGenerator instance (not a shared/global one) so
## combat rolls stay deterministic per-entity and testable with a fixed seed.
static func roll_damage(min_damage: int, max_damage: int, rng: RandomNumberGenerator) -> int:
	return rng.randi_range(min_damage, max_damage)

## Returns true once cooldown_ms have elapsed since last_attack_time_ms, given the
## current time now_ms. Callers pass a per-entity, Engine.time_scale-aware game-time
## accumulator (see Character/Enemy's game_time_ms) for now_ms/last_attack_time_ms, not
## Time.get_ticks_msec() — that would ignore pause/speed controls.
static func is_off_cooldown(last_attack_time_ms: int, cooldown_ms: int, now_ms: int) -> bool:
	return now_ms - last_attack_time_ms >= cooldown_ms

## Velocity for an enemy with nobody in aggro range: back toward its spawn
## point (`home`) until it is within LEASH_SLACK of it, then zero. Without
## this an enemy that chased someone into a zone corner (e.g. a fleeing ally)
## stood there forever, out of everyone's reach: its SpawnPoint never
## respawned it, and a quest needing it (Bandit Trouble needs the meadow's
## only Bandit) could never be finished. It does not heal on the way back.
static func return_home_velocity(from: Vector2, home: Vector2, speed: float) -> Vector2:
	var to_home := home - from
	if to_home.length() <= LEASH_SLACK:
		return Vector2.ZERO
	return to_home.normalized() * speed
