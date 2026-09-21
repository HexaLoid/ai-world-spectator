class_name CombatSystem
extends RefCounted

## Rolls a random integer damage value in [min_damage, max_damage] using the given rng.
## Callers pass their own RandomNumberGenerator instance (not a shared/global one) so
## combat rolls stay deterministic per-entity and testable with a fixed seed.
static func roll_damage(min_damage: int, max_damage: int, rng: RandomNumberGenerator) -> int:
	return rng.randi_range(min_damage, max_damage)

## Returns true once cooldown_ms have elapsed since last_attack_time_ms, given the
## current time now_ms. Callers pass Time.get_ticks_msec() for now_ms/last_attack_time_ms,
## which is monotonic for the lifetime of the process.
static func is_off_cooldown(last_attack_time_ms: int, cooldown_ms: int, now_ms: int) -> bool:
	return now_ms - last_attack_time_ms >= cooldown_ms
