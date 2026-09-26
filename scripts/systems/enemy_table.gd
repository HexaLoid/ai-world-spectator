class_name EnemyTable
extends RefCounted

## Central enemy definitions. SpawnPoint reads an entry by id; quests match
## kills by `name`; the (future) codex lists these. Sprites are recolored /
## rescaled versions of the two existing sheets ("wolf", "bandit").
## `zone`: the enemy's home zone id (ZoneTable), shown by the codex.
## `loot_level`: random drops only pick items with level_req <= this.
## `guaranteed_drop` (bosses/elites): always dropped, and gold is x5.

const SPRITE_FRAMES := {
	"wolf": "res://assets/sprites/wolf/wolf_frames.tres",
	"bandit": "res://assets/sprites/bandit/bandit_frames.tres",
}

const ENEMIES := {
	# --- Thornfield Meadow / Blackthorn Forest / Sundered Crypt (unchanged stats) ---
	"wolf": {
		"name": "Wolf", "zone": "thornfield_meadow", "sprite": "wolf", "tint": Color(1, 1, 1, 1), "sprite_size": 40.0,
		"max_hp": 18, "move_speed": 70.0, "attack_min": 2, "attack_max": 4, "aggro_range": 120.0,
		"xp_reward": 20, "gold_min": 1, "gold_max": 3, "loot_level": 2, "guaranteed_drop": "",
	},
	"dire_wolf": {
		"name": "Dire Wolf", "zone": "blackthorn_forest", "sprite": "wolf", "tint": Color(1, 1, 1, 1), "sprite_size": 40.0,
		"max_hp": 30, "move_speed": 75.0, "attack_min": 4, "attack_max": 7, "aggro_range": 120.0,
		"xp_reward": 35, "gold_min": 1, "gold_max": 3, "loot_level": 3, "guaranteed_drop": "",
	},
	"bandit": {
		"name": "Bandit", "zone": "thornfield_meadow", "sprite": "bandit", "tint": Color(1, 1, 1, 1), "sprite_size": 40.0,
		"max_hp": 35, "move_speed": 45.0, "attack_min": 4, "attack_max": 8, "aggro_range": 120.0,
		"xp_reward": 35, "gold_min": 1, "gold_max": 3, "loot_level": 2, "guaranteed_drop": "",
	},
	"bandit_captain": {
		"name": "Bandit Captain", "zone": "blackthorn_forest", "sprite": "bandit", "tint": Color(0.65, 0.3, 0.85, 1.0), "sprite_size": 56.0,
		"max_hp": 70, "move_speed": 50.0, "attack_min": 8, "attack_max": 14, "aggro_range": 120.0,
		"xp_reward": 90, "gold_min": 1, "gold_max": 3, "loot_level": 3, "guaranteed_drop": "iron_sword",
	},
	# A small, enclosed dungeon room (360x360): this aggro range exceeds the
	# worst-case corner-to-center distance (~255), so the boss reliably notices
	# the character on every visit instead of possibly never coming into range
	# during a short wander before the zone's dwell timer expires.
	"crypt_lord": {
		"name": "Crypt Lord", "zone": "sundered_crypt", "sprite": "bandit", "tint": Color(0.2, 0.06, 0.1, 1.0), "sprite_size": 64.0,
		"max_hp": 380, "move_speed": 78.0, "attack_min": 17, "attack_max": 27, "aggro_range": 280.0,
		"xp_reward": 300, "gold_min": 1, "gold_max": 3, "loot_level": 4, "guaranteed_drop": "warlords_greatsword",
	},
	# --- Mirewater Swamp (levels 4+) ---
	"mire_wolf": {
		"name": "Mire Wolf", "zone": "mirewater_swamp", "sprite": "wolf", "tint": Color(0.55, 0.85, 0.6, 1.0), "sprite_size": 40.0,
		"max_hp": 45, "move_speed": 72.0, "attack_min": 6, "attack_max": 11, "aggro_range": 120.0,
		"xp_reward": 55, "gold_min": 3, "gold_max": 6, "loot_level": 6, "guaranteed_drop": "",
	},
	"bog_bandit": {
		"name": "Bog Bandit", "zone": "mirewater_swamp", "sprite": "bandit", "tint": Color(0.5, 0.85, 0.55, 1.0), "sprite_size": 40.0,
		"max_hp": 55, "move_speed": 46.0, "attack_min": 7, "attack_max": 13, "aggro_range": 120.0,
		"xp_reward": 65, "gold_min": 4, "gold_max": 7, "loot_level": 6, "guaranteed_drop": "",
	},
	"mire_tyrant": {
		"name": "Mire Tyrant", "zone": "mirewater_swamp", "sprite": "bandit", "tint": Color(0.25, 0.5, 0.3, 1.0), "sprite_size": 64.0,
		"max_hp": 900, "move_speed": 80.0, "attack_min": 32, "attack_max": 52, "aggro_range": 200.0,
		"xp_reward": 600, "gold_min": 6, "gold_max": 10, "loot_level": 6, "guaranteed_drop": "tyrants_maul",
	},
	# --- Frostpeak Pass (levels 7+) ---
	"frost_wolf": {
		"name": "Frost Wolf", "zone": "frostpeak_pass", "sprite": "wolf", "tint": Color(0.7, 0.88, 1.0, 1.0), "sprite_size": 42.0,
		"max_hp": 70, "move_speed": 78.0, "attack_min": 9, "attack_max": 15, "aggro_range": 130.0,
		"xp_reward": 90, "gold_min": 5, "gold_max": 9, "loot_level": 9, "guaranteed_drop": "",
	},
	"frost_raider": {
		"name": "Frost Raider", "zone": "frostpeak_pass", "sprite": "bandit", "tint": Color(0.6, 0.8, 1.0, 1.0), "sprite_size": 42.0,
		"max_hp": 85, "move_speed": 50.0, "attack_min": 10, "attack_max": 17, "aggro_range": 130.0,
		"xp_reward": 105, "gold_min": 6, "gold_max": 10, "loot_level": 9, "guaranteed_drop": "",
	},
	"raider_captain": {
		"name": "Raider Captain", "zone": "frostpeak_pass", "sprite": "bandit", "tint": Color(0.35, 0.55, 0.95, 1.0), "sprite_size": 58.0,
		"max_hp": 560, "move_speed": 80.0, "attack_min": 28, "attack_max": 42, "aggro_range": 160.0,
		"xp_reward": 260, "gold_min": 10, "gold_max": 16, "loot_level": 9, "guaranteed_drop": "rimewatch_helm",
	},
	"frostpeak_warlord": {
		"name": "Frostpeak Warlord", "zone": "frostpeak_pass", "sprite": "bandit", "tint": Color(0.9, 0.95, 1.0, 1.0), "sprite_size": 72.0,
		"max_hp": 1300, "move_speed": 84.0, "attack_min": 34, "attack_max": 50, "aggro_range": 220.0,
		"xp_reward": 1200, "gold_min": 20, "gold_max": 30, "loot_level": 9, "guaranteed_drop": "glacier_plate",
	},
	# --- Hollowed Vault (dungeon, level 8+) ---
	"vault_skeleton": {
		"name": "Vault Skeleton", "zone": "hollowed_vault", "sprite": "bandit", "tint": Color(0.78, 0.78, 0.86, 1.0), "sprite_size": 42.0,
		"max_hp": 90, "move_speed": 52.0, "attack_min": 10, "attack_max": 16, "aggro_range": 140.0,
		"xp_reward": 120, "gold_min": 6, "gold_max": 11, "loot_level": 10, "guaranteed_drop": "",
	},
	"vault_wraith": {
		"name": "Vault Wraith", "zone": "hollowed_vault", "sprite": "wolf", "tint": Color(0.6, 0.5, 0.95, 1.0), "sprite_size": 42.0,
		"max_hp": 60, "move_speed": 84.0, "attack_min": 12, "attack_max": 18, "aggro_range": 200.0,
		"xp_reward": 60, "gold_min": 4, "gold_max": 8, "loot_level": 10, "guaranteed_drop": "",
	},
	"bone_warden": {
		"name": "Bone Warden", "zone": "hollowed_vault", "sprite": "bandit", "tint": Color(0.9, 0.88, 0.7, 1.0), "sprite_size": 64.0,
		"max_hp": 700, "move_speed": 60.0, "attack_min": 30, "attack_max": 45, "aggro_range": 200.0,
		"xp_reward": 700, "gold_min": 20, "gold_max": 30, "loot_level": 10, "guaranteed_drop": "wardens_plate",
	},
	"hollow_king": {
		"name": "Hollow King", "zone": "hollowed_vault", "sprite": "bandit", "tint": Color(0.5, 0.3, 0.65, 1.0), "sprite_size": 80.0,
		"max_hp": 1800, "move_speed": 66.0, "attack_min": 38, "attack_max": 55, "aggro_range": 260.0,
		"xp_reward": 1600, "gold_min": 40, "gold_max": 60, "loot_level": 10, "guaranteed_drop": "hollow_crown",
		"mechanics": "hollow_king",
	},
}

static func get_def(id: String) -> Dictionary:
	return ENEMIES.get(id, {})

## Bosses and elites are the enemies with a guaranteed drop.
static func is_boss(id: String) -> bool:
	return String(get_def(id).get("guaranteed_drop", "")) != ""

static func name_of(id: String) -> String:
	return String(ENEMIES.get(id, {}).get("name", ""))

## Ids of every enemy with this display name (quests match kills by name).
static func ids_named(enemy_name: String) -> Array:
	var ids: Array = []
	for id in ENEMIES:
		if ENEMIES[id]["name"] == enemy_name:
			ids.append(id)
	return ids
