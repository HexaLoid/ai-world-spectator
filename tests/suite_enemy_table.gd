extends RefCounted

const ORIGINAL := {
	"wolf": {"name": "Wolf", "max_hp": 18, "move_speed": 70.0, "attack_min": 2, "attack_max": 4, "xp_reward": 20, "sprite": "wolf"},
	"dire_wolf": {"name": "Dire Wolf", "max_hp": 30, "move_speed": 75.0, "attack_min": 4, "attack_max": 7, "xp_reward": 35, "sprite": "wolf"},
	"bandit": {"name": "Bandit", "max_hp": 35, "move_speed": 45.0, "attack_min": 4, "attack_max": 8, "xp_reward": 35, "sprite": "bandit"},
	"bandit_captain": {"name": "Bandit Captain", "max_hp": 70, "move_speed": 50.0, "attack_min": 8, "attack_max": 14, "xp_reward": 90, "sprite": "bandit", "guaranteed_drop": "iron_sword"},
	# Crypt Lord re-tuned by the 2026-09-25 balance pass (was 150 HP, 10-18
	# damage). Measured with tests/sim: it is the boss the character fights
	# most (the crypt lies on both legs of the zone loop, ~13 kills per 45
	# game-minutes, no zone ally to soften it) and from the second kill on it
	# died in ~1 s with the character above ~80% HP. See
	# docs/superpowers/balance/2026-09-25-balance-report.md.
	"crypt_lord": {"name": "Crypt Lord", "max_hp": 300, "move_speed": 45.0, "attack_min": 14, "attack_max": 22, "xp_reward": 300, "sprite": "bandit", "guaranteed_drop": "warlords_greatsword"},
}

const NEW_IDS := ["mire_wolf", "bog_bandit", "mire_tyrant", "frost_wolf", "frost_raider", "raider_captain", "frostpeak_warlord"]

## Zone min_level for each guaranteed-drop enemy's home zone (the drop's
## level_req may be at most 2 above it).
const BOSS_ZONE_MIN_LEVEL := {
	"bandit_captain": 1, "crypt_lord": 3, "mire_tyrant": 4, "raider_captain": 7, "frostpeak_warlord": 7,
}

func run(t) -> void:
	t.check_eq(EnemyTable.ENEMIES.size(), 12, "twelve enemies")
	var names := {}
	for id in EnemyTable.ENEMIES:
		var def: Dictionary = EnemyTable.ENEMIES[id]
		t.check(EnemyTable.SPRITE_FRAMES.has(def.get("sprite", "")), "%s has a known sprite" % id)
		for path in EnemyTable.SPRITE_FRAMES.values():
			t.check(FileAccess.file_exists(path), "sprite frames file exists: %s" % path)
		t.check(String(def.get("name", "")) != "", "%s has a name" % id)
		t.check(ZoneTable.ZONES.has(def.get("zone", "")), "%s has a valid zone (%s)" % [id, def.get("zone", "")])
		t.check(not names.has(def["name"]), "enemy name %s is unique" % def["name"])
		names[def["name"]] = id
		t.check(int(def["max_hp"]) > 0, "%s has hp" % id)
		t.check(float(def["move_speed"]) > 0.0, "%s moves" % id)
		t.check(int(def["attack_min"]) >= 1 and int(def["attack_min"]) <= int(def["attack_max"]), "%s attack range is valid" % id)
		t.check(int(def["xp_reward"]) > 0, "%s gives xp" % id)
		t.check(int(def["gold_min"]) >= 0 and int(def["gold_min"]) <= int(def["gold_max"]), "%s gold range is valid" % id)
		t.check(int(def["loot_level"]) >= 1 and int(def["loot_level"]) <= LevelingSystem.MAX_LEVEL, "%s loot_level in range" % id)
		t.check(float(def["sprite_size"]) >= 32.0 and float(def["sprite_size"]) <= 96.0, "%s sprite size is sane" % id)
		t.check(float(def["aggro_range"]) >= 80.0, "%s aggro range is sane" % id)
		t.check(def["tint"] is Color, "%s tint is a Color" % id)
		var drop: String = def.get("guaranteed_drop", "")
		if drop != "":
			t.check(LootTable.ITEMS.has(drop), "%s guaranteed drop %s exists" % [id, drop])
			t.check(BOSS_ZONE_MIN_LEVEL.has(id), "%s (guaranteed drop) is listed in this suite's zone table" % id)
			if LootTable.ITEMS.has(drop) and BOSS_ZONE_MIN_LEVEL.has(id):
				var level_req := int(LootTable.ITEMS[drop].get("level_req", 1))
				t.check(level_req <= int(BOSS_ZONE_MIN_LEVEL[id]) + 2, "%s drop %s (level_req %d) is reachable from its zone" % [id, drop, level_req])

	# the five original enemies keep their previous stats
	for id in ORIGINAL:
		var expected: Dictionary = ORIGINAL[id]
		var def := EnemyTable.get_def(id)
		t.check(not def.is_empty(), "original enemy %s exists" % id)
		for key in expected:
			var actual = def.get("guaranteed_drop", "") if key == "guaranteed_drop" else def.get(key)
			t.check_eq(actual, expected[key], "%s keeps its original %s" % [id, key])

	# new enemies exist
	for id in NEW_IDS:
		t.check(not EnemyTable.get_def(id).is_empty(), "new enemy %s exists" % id)

	# helpers
	t.check_eq(EnemyTable.name_of("wolf"), "Wolf", "name_of")
	t.check_eq(EnemyTable.name_of("nope"), "", "name_of unknown")
	t.check_eq(EnemyTable.ids_named("Dire Wolf"), ["dire_wolf"], "ids_named")
	t.check_eq(EnemyTable.ids_named("Nobody"), [], "ids_named unknown")
	t.check(EnemyTable.get_def("nope").is_empty(), "get_def unknown is empty")
	t.done()
