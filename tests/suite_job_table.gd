extends RefCounted

const ROLES := ["tank", "healer", "melee", "magic"]
const KINDS := ["gap_closer", "melee_hit", "bleed", "self_heal", "ally_heal"]
const KEYS := ["name", "role", "blurb", "resource_name", "resource_color", "max_resource", "primary_stat", "stat_weights", "sprite_tint", "abilities", "ally_hp_mult", "ally_damage_mult"]

func run(t) -> void:
	t.check_eq(AbilityTable.JOB_ORDER.size(), 7, "seven jobs")
	t.check_eq(AbilityTable.job_ids(), AbilityTable.JOB_ORDER, "job_ids returns the order")
	t.check_eq(AbilityTable.CLASSES.size(), 7, "CLASSES has exactly the seven jobs")
	for id in AbilityTable.CLASSES.keys():
		t.check(AbilityTable.JOB_ORDER.has(id), "%s is in JOB_ORDER" % id)
	for id in AbilityTable.JOB_ORDER:
		var def: Dictionary = AbilityTable.CLASSES[id]
		for key in KEYS:
			t.check(def.has(key), "%s has %s" % [id, key])
		t.check(ROLES.has(def["role"]), "%s: valid role" % id)
		t.check(["strength", "intellect"].has(def["primary_stat"]), "%s: known primary stat" % id)
		t.check(float(def["ally_hp_mult"]) > 0.0 and float(def["ally_damage_mult"]) > 0.0, "%s: positive ally multipliers" % id)
		for stat in def["stat_weights"].keys():
			t.check(float(def["stat_weights"][stat]) > 0.0, "%s: weight %s positive" % [id, stat])
		var damaging := false
		for ability_id in def["abilities"]:
			t.check(AbilityTable.ABILITIES.has(ability_id), "%s: ability %s exists" % [id, ability_id])
			var ability: Dictionary = AbilityTable.ABILITIES.get(ability_id, {})
			t.check(KINDS.has(ability.get("kind", "")), "%s/%s: known kind" % [id, ability_id])
			t.check(int(ability.get("cooldown_ms", 0)) > 0, "%s/%s: positive cooldown" % [id, ability_id])
			t.check(ResourceLoader.exists(String(ability.get("icon", ""))), "%s/%s: icon exists" % [id, ability_id])
			if ability.get("kind", "") in ["melee_hit", "bleed"]:
				damaging = true
		t.check(damaging, "%s has a damaging ability" % id)

	# names and helpers
	t.check_eq(AbilityTable.job_name("mage"), "Black Mage", "mage is displayed as Black Mage")
	t.check_eq(AbilityTable.job_name("white_mage"), "White Mage", "job_name")
	t.check_eq(AbilityTable.job_name("nope"), "Nope", "unknown id falls back to a capitalized id")
	t.check_eq(AbilityTable.job_name(""), "Adventurer", "empty id falls back to Adventurer")

	# roles and the special abilities
	t.check_eq(AbilityTable.CLASSES["warrior"]["role"], "tank", "warrior is the tank")
	t.check_eq(AbilityTable.CLASSES["white_mage"]["role"], "healer", "white mage is the healer")
	var healer_kinds: Array = []
	for ability_id in AbilityTable.CLASSES["white_mage"]["abilities"]:
		healer_kinds.append(AbilityTable.ABILITIES[ability_id]["kind"])
	t.check(healer_kinds.has("ally_heal"), "white mage can heal allies")
	t.check(float(AbilityTable.CLASSES["thief"].get("gold_bonus_mult", 1.0)) > 1.0, "thief steals extra gold")
	t.check(float(AbilityTable.CLASSES["thief"].get("bonus_crit_chance", 0.0)) > 0.0, "thief has innate crit")
	t.check(int(AbilityTable.ABILITIES["combo"].get("hit_count", 1)) > 1, "black belt combo hits several times")
	t.check(AbilityMath.jump_multiplier(AbilityTable.ABILITIES["jump"]) > 0.0, "dragoon jump lands a hit")

	# the two original jobs keep their numbers
	t.check_eq(AbilityTable.CLASSES["warrior"]["abilities"], ["charge", "rend", "heroic_strike", "second_wind"], "warrior abilities unchanged")
	t.check_eq(AbilityTable.CLASSES["mage"]["abilities"], ["frost_nova", "arcane_bolt", "mana_ward"], "mage abilities unchanged")
	t.check_eq(int(AbilityTable.CLASSES["mage"]["bonus_max_hp"]), 25, "mage bonus HP unchanged")
	t.check_eq(int(AbilityTable.CLASSES["mage"]["bonus_armor"]), 5, "mage bonus armor unchanged")
	t.done()
