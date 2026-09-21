class_name CombatSystem
extends RefCounted

static func roll_damage(min_damage: int, max_damage: int, rng: RandomNumberGenerator) -> int:
	return rng.randi_range(min_damage, max_damage)

static func is_off_cooldown(last_attack_time_ms: int, cooldown_ms: int, now_ms: int) -> bool:
	return now_ms - last_attack_time_ms >= cooldown_ms
