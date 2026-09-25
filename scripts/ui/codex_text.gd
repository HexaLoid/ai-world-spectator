class_name CodexText
extends RefCounted

## Pure BBCode builders for the codex panel. Every input is a plain value
## (ids, flags, counts), so it is all unit-tested headlessly.

const UNDISCOVERED := "[color=#8a7a65]Not yet discovered.[/color]"

static func list_label(discovered: bool, entry_name: String) -> String:
	return entry_name if discovered else "???"

static func tab_title(tab: String, discovered: int, total: int) -> String:
	return "%s %d/%d" % [tab, discovered, total]

static func enemy_entry(id: String, met: bool, kills: int, zone_visited: bool) -> String:
	var def: Dictionary = EnemyTable.get_def(id)
	if def.is_empty():
		return ""
	var zone_name := String(ZoneTable.ZONES.get(def.get("zone", ""), {}).get("name", "?"))
	if not met:
		var text := UNDISCOVERED
		if zone_visited:
			text += "\nLurks somewhere in %s." % zone_name
		return text
	var lines: Array[String] = []
	var tag := ""
	if def.get("guaranteed_drop", "") != "":
		tag = "  [color=#d9a441]Boss[/color]"
	lines.append("[b]%s[/b]%s" % [def["name"], tag])
	lines.append("Zone: %s" % zone_name)
	lines.append("HP: %d" % int(def["max_hp"]))
	lines.append("Damage: %d - %d" % [int(def["attack_min"]), int(def["attack_max"])])
	if kills >= 1:
		lines.append("XP: %d" % int(def["xp_reward"]))
		lines.append("Gold: %d - %d" % [int(def["gold_min"]), int(def["gold_max"])])
		lines.append("Kills: %d" % kills)
		var drop: String = def.get("guaranteed_drop", "")
		if drop != "":
			lines.append("Drops: %s" % _colored_item_name(drop))
		else:
			lines.append("Drops: possible gear up to level %d" % int(def["loot_level"]))
	return "\n".join(lines)

static func item_entry(id: String, found: bool) -> String:
	var item: Dictionary = LootTable.ITEMS.get(id, {})
	if item.is_empty():
		return ""
	var slot_label := "Consumable" if item.get("type", "") == "consumable" else String(LootTable.SLOT_LABELS.get(item.get("slot", ""), ""))
	if not found:
		var hint := UNDISCOVERED
		if slot_label != "":
			hint += "\n%s" % slot_label
		return hint
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % _colored_item_name(id))
	lines.append("%s - %s - Level %d" % [slot_label, String(item.get("rarity", "")).capitalize(), int(item.get("level_req", 1))])
	if item.get("type", "") == "consumable":
		lines.append("Heals %d HP" % int(item.get("heal", 0)))
	else:
		var stats := ItemScoring.describe_stats(id)
		if stats != "":
			lines.append(stats)
	var sources := CodexData.item_sources(id)
	for enemy_name in sources["guaranteed"]:
		lines.append("Guaranteed drop: %s" % enemy_name)
	for quest_name in sources["quests"]:
		lines.append("Quest reward: %s" % quest_name)
	if int(sources["random_from_loot_level"]) >= 0:
		lines.append("Random drops from level %d enemies" % int(sources["random_from_loot_level"]))
	return "\n".join(lines)

## `enemies_met_in_zone`: ids of the zone's enemies the character has met.
static func zone_entry(id: String, visited: bool, enemies_met_in_zone: Array) -> String:
	var zone: Dictionary = ZoneTable.ZONES.get(id, {})
	if zone.is_empty():
		return ""
	if not visited:
		return UNDISCOVERED
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % zone["name"])
	var range := CodexData.zone_level_range(id)
	lines.append("Levels %d - %d" % [range[0], range[1]])
	var roster := CodexData.zone_enemy_ids(id)
	var met_count := 0
	lines.append("Enemies:")
	for enemy_id in roster:
		if enemies_met_in_zone.has(enemy_id):
			met_count += 1
			lines.append("  - %s" % EnemyTable.name_of(enemy_id))
		else:
			lines.append("  - ???")
	var boss_id := CodexData.zone_boss_id(id)
	if boss_id != "":
		lines.append("Boss: %s" % (EnemyTable.name_of(boss_id) if enemies_met_in_zone.has(boss_id) else "???"))
	lines.append("Discovered: %d/%d" % [met_count, roster.size()])
	return "\n".join(lines)

static func _colored_item_name(item_id: String) -> String:
	var rarity: String = LootTable.ITEMS.get(item_id, {}).get("rarity", "")
	var color: Color = LootTable.RARITY_COLORS.get(rarity, Color.WHITE)
	return "[color=#%s]%s[/color]" % [color.to_html(false), LootTable.display_name(item_id)]
