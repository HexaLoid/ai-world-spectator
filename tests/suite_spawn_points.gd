extends RefCounted

## Every `enemy_id = "..."` line in the world scenes must name a real
## EnemyTable entry, and no scene may still use the old per-field overrides.

const OLD_OVERRIDES := ["enemy_name_override", "max_hp_override", "move_speed_override", "attack_damage_min_override",
	"attack_damage_max_override", "xp_reward_override", "aggro_range_override", "sprite_frames_override",
	"sprite_size_override", "sprite_tint_override", "guaranteed_drop_id_override"]

const SCENE_ZONES := {
	"ThornfieldMeadow.tscn": "thornfield_meadow",
	"BlackthornForest.tscn": "blackthorn_forest",
	"SunderedCrypt.tscn": "sundered_crypt",
	"MirewaterSwamp.tscn": "mirewater_swamp",
	"FrostpeakPass.tscn": "frostpeak_pass",
}

func run(t) -> void:
	var regex := RegEx.new()
	regex.compile("enemy_id = \"([a-z_]+)\"")
	var total := 0
	for file_name in DirAccess.get_files_at("res://scenes/world"):
		if not file_name.ends_with(".tscn"):
			continue
		var text := FileAccess.get_file_as_string("res://scenes/world/" + file_name)
		for m in regex.search_all(text):
			total += 1
			var id := m.get_string(1)
			t.check(not EnemyTable.get_def(id).is_empty(), "%s: enemy_id '%s' exists in EnemyTable" % [file_name, id])
			var scene_zone: String = SCENE_ZONES.get(file_name, "")
			t.check(scene_zone != "", "%s is a known zone scene" % file_name)
			t.check_eq(EnemyTable.get_def(id).get("zone", ""), scene_zone, "%s: enemy %s belongs to this scene's zone" % [file_name, id])
		for key in OLD_OVERRIDES:
			t.check(not text.contains(key + " ="), "%s no longer uses %s" % [file_name, key])
	t.check(total >= 18, "all 18 spawn points name an enemy (found %d)" % total)
	# Regression: an enemy with nobody in aggro range walks back to its spawn
	# point instead of standing wherever its last chase ended (a Bandit left in
	# a meadow corner could never be found again, stalling Bandit Trouble).
	var home := Vector2(60, 150)
	var back := CombatSystem.return_home_velocity(Vector2(-356, 280), home, 45.0)
	t.check_near(back.length(), 45.0, "a stray enemy walks home at its move speed")
	t.check(back.dot(home - Vector2(-356, 280)) > 0.0, "a stray enemy walks toward its spawn point")
	t.check_eq(CombatSystem.return_home_velocity(home + Vector2(10, 0), home, 45.0), Vector2.ZERO, "an enemy at home stays put")
	t.done()
