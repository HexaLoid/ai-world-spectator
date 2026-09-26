extends RefCounted

func _full_snapshot() -> Dictionary:
	return {
		"level": 3, "class_name": "warrior", "zone_name": "Blackthorn Forest",
		"xp": 40, "xp_next": 100,
		"hp": 60, "max_hp": 95, "damage_min": 12, "damage_max": 16, "armor": 4,
		"crit_chance": 0.17,
		"primary_stat": "strength", "primary_value": 5.0, "primary_bonus_percent": 5.0,
		"equipment": {"weapon": "iron_sword", "head": "iron_helm"},
		"gold": 44, "quest_text": "Cull the Wolves 2/3", "quests_completed": 2,
		"kills_by_name": {"Wolf": 12, "Bandit": 3, "Dire Wolf": 3, "Crypt Lord": 1},
		"deaths": 1, "damage_dealt": 950, "damage_taken": 310, "gold_earned": 120,
		"time_played_ms": 65000.0,
	}

func run(t) -> void:
	# format_time()
	t.check_eq(SheetText.format_time(0.0), "00:00", "zero time")
	t.check_eq(SheetText.format_time(65000.0), "01:05", "65 seconds")
	t.check_eq(SheetText.format_time(3725000.0), "62:05", "hours roll into minutes")
	t.check_eq(SheetText.format_time(-500.0), "00:00", "negative time clamps to zero")

	# build() with a full snapshot
	var text := SheetText.build(_full_snapshot())
	t.check(text.contains("Level 3 Warrior"), "header has level and capitalized class")
	t.check(text.contains("Blackthorn Forest"), "header has zone")
	t.check(text.contains("XP: 40 / 100"), "xp line")
	t.check(text.contains("HP: 60 / 95"), "hp line")
	t.check(text.contains("Damage: 12 - 16"), "damage line")
	t.check(text.contains("Armor: 4"), "armor line")
	t.check(text.contains("Crit chance: 17%"), "crit line")
	t.check(text.contains("Strength: 5 (+5% damage)"), "primary stat line")
	var uncommon_hex: String = LootTable.RARITY_COLORS["uncommon"].to_html(false)
	t.check(text.contains("Weapon: [color=#%s]Iron Sword[/color] (+7 damage)" % uncommon_hex),
		"equipment line: slot, rarity-colored name, stats")
	t.check(text.contains("Head: [color=#%s]Iron Helm[/color] (+2 armor, +10 HP)" % uncommon_hex),
		"second equipment line")
	t.check(text.contains("Off-hand: [color=#%s]empty[/color]" % SheetText.EMPTY_COLOR), "empty slot is marked empty")
	t.check(text.contains("Gold: 44"), "gold line")
	t.check(text.contains("Quest: Cull the Wolves 2/3"), "quest line")
	t.check(text.contains("Quests completed: 2"), "completed quests line")
	t.check(text.contains("Kills: 19"), "total kills")
	t.check(text.contains("Wolf x12, Bandit x3, Dire Wolf x3"), "top three kills, ties broken by name")
	t.check(not text.contains("Crypt Lord"), "fourth-place kill type is not listed")
	t.check(text.contains("Deaths: 1"), "deaths line")
	t.check(text.contains("Damage dealt: 950"), "damage dealt line")
	t.check(text.contains("Damage taken: 310"), "damage taken line")
	t.check(text.contains("Gold earned: 120"), "gold earned line")
	t.check(text.contains("Time played: 01:05"), "time played line")

	# max level
	var maxed := _full_snapshot()
	maxed["xp_next"] = 0
	t.check(SheetText.build(maxed).contains("XP: MAX"), "max level shows MAX")

	# no primary stat -> no primary line
	var no_primary := _full_snapshot()
	no_primary["primary_stat"] = ""
	t.check(not SheetText.build(no_primary).contains("(+5% damage)"), "no primary stat, no primary line")

	# an empty snapshot must not error and uses defaults
	var empty_text := SheetText.build({})
	t.check(empty_text.contains("Level 1 Adventurer"), "empty snapshot: default header")
	t.check(empty_text.contains("HP: 0 / 0"), "empty snapshot: default hp")
	t.check(empty_text.contains("Kills: 0"), "empty snapshot: zero kills")
	t.check(empty_text.contains("Quest: none active"), "empty snapshot: default quest")
	t.check(empty_text.contains("Time played: 00:00"), "empty snapshot: zero time")
	for slot_label in LootTable.SLOT_LABELS.values():
		t.check(empty_text.contains("%s: [color=#%s]empty[/color]" % [slot_label, SheetText.EMPTY_COLOR]),
			"empty snapshot: %s slot is empty" % slot_label)
	# character name line
	var named := _full_snapshot()
	named["character_name"] = "Aldric"
	t.check(SheetText.build(named).begins_with("[b]Aldric[/b]"), "sheet starts with the character's name")
	t.check(not SheetText.build(_full_snapshot()).contains("[b]Aldric[/b]"), "no name line without a name")
	t.check(SheetText.build({}).begins_with("[b]Level 1 Adventurer[/b]"), "empty snapshot still starts with the level line")
	# trait title on the name line
	var titled := _full_snapshot()
	titled["character_name"] = "Aldric"
	titled["trait_title"] = "the Cautious"
	t.check(SheetText.build(titled).contains("Aldric the Cautious"), "trait title appears on the sheet")
	var plain := _full_snapshot()
	plain["character_name"] = "Aldric"
	t.check(not SheetText.build(plain).contains("the Cautious"), "no trait title without the key")
	# job name replaces the capitalized class id when present
	var job_snap := _full_snapshot()
	job_snap["class_name"] = "mage"
	job_snap["job_name"] = "Black Mage"
	t.check(SheetText.build(job_snap).contains("Level 3 Black Mage"), "sheet shows the job name")
	var id_snap := _full_snapshot()
	t.check(SheetText.build(id_snap).contains("Level 3 Warrior"), "no job_name: capitalized class id as before")
	t.done()
