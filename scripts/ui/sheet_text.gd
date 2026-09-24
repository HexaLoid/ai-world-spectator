class_name SheetText
extends RefCounted

## Pure formatting for the character sheet: a snapshot dictionary (see
## Character.get_sheet_snapshot) in, a BBCode string out. Every key is
## optional so a partial or empty snapshot never errors.

const HEADER_COLOR := "d9a441"
const EMPTY_COLOR := "8a7a65"
const TOP_KILLS_SHOWN := 3

## "mm:ss"; hours roll into minutes (62:05), negatives clamp to 00:00.
static func format_time(ms: float) -> String:
	var total_seconds := int(maxf(ms, 0.0) / 1000.0)
	return "%02d:%02d" % [floori(total_seconds / 60.0), total_seconds % 60]

static func build(snap: Dictionary) -> String:
	var lines: Array[String] = []

	var class_text := String(snap.get("class_name", "")).capitalize()
	if class_text == "":
		class_text = "Adventurer"
	lines.append("[b]Level %d %s[/b] - %s" % [int(snap.get("level", 1)), class_text, String(snap.get("zone_name", "?"))])
	var xp_next := int(snap.get("xp_next", 0))
	lines.append("XP: MAX" if xp_next <= 0 else "XP: %d / %d" % [int(snap.get("xp", 0)), xp_next])
	lines.append("")

	lines.append(_header("Stats"))
	lines.append("HP: %d / %d" % [int(snap.get("hp", 0)), int(snap.get("max_hp", 0))])
	lines.append("Damage: %d - %d" % [int(snap.get("damage_min", 0)), int(snap.get("damage_max", 0))])
	lines.append("Armor: %d" % int(snap.get("armor", 0)))
	lines.append("Crit chance: %d%%" % roundi(float(snap.get("crit_chance", 0.0)) * 100.0))
	var primary := String(snap.get("primary_stat", ""))
	if primary != "":
		lines.append("%s: %d (+%d%% damage)" % [primary.capitalize(), roundi(float(snap.get("primary_value", 0.0))), roundi(float(snap.get("primary_bonus_percent", 0.0)))])
	lines.append("")

	lines.append(_header("Equipment"))
	var equipment: Dictionary = snap.get("equipment", {})
	for slot in LootTable.SLOTS:
		lines.append(_equipment_line(slot, String(equipment.get(slot, ""))))
	lines.append("")

	lines.append(_header("Progress"))
	lines.append("Gold: %d" % int(snap.get("gold", 0)))
	lines.append("Quest: %s" % String(snap.get("quest_text", "none active")))
	lines.append("Quests completed: %d" % int(snap.get("quests_completed", 0)))
	lines.append("")

	lines.append(_header("Session"))
	var kills: Dictionary = snap.get("kills_by_name", {})
	var kills_total := 0
	for enemy_name in kills:
		kills_total += int(kills[enemy_name])
	lines.append("Kills: %d" % kills_total)
	var top := _top_kills(kills)
	if not top.is_empty():
		lines.append("Top: %s" % ", ".join(top))
	lines.append("Deaths: %d" % int(snap.get("deaths", 0)))
	lines.append("Damage dealt: %d" % int(snap.get("damage_dealt", 0)))
	lines.append("Damage taken: %d" % int(snap.get("damage_taken", 0)))
	lines.append("Gold earned: %d" % int(snap.get("gold_earned", 0)))
	lines.append("Time played: %s" % format_time(float(snap.get("time_played_ms", 0.0))))

	return "\n".join(lines)

static func _header(title: String) -> String:
	return "[b][color=#%s]%s[/color][/b]" % [HEADER_COLOR, title]

static func _equipment_line(slot: String, item_id: String) -> String:
	var slot_label: String = LootTable.SLOT_LABELS.get(slot, slot)
	if item_id == "":
		return "%s: [color=#%s]empty[/color]" % [slot_label, EMPTY_COLOR]
	var rarity: String = LootTable.ITEMS.get(item_id, {}).get("rarity", "")
	var color: Color = LootTable.RARITY_COLORS.get(rarity, Color.WHITE)
	var line := "%s: [color=#%s]%s[/color]" % [slot_label, color.to_html(false), LootTable.display_name(item_id)]
	var stats := ItemScoring.describe_stats(item_id)
	if stats != "":
		line += " (%s)" % stats
	return line

## "Wolf x12" entries for the most-killed enemy types, highest first, ties
## broken alphabetically so the order is deterministic.
static func _top_kills(kills: Dictionary) -> Array[String]:
	var names: Array = kills.keys()
	names.sort_custom(func(a, b): return _kills_before(kills, a, b))
	var top: Array[String] = []
	for i in mini(names.size(), TOP_KILLS_SHOWN):
		top.append("%s x%d" % [names[i], int(kills[names[i]])])
	return top

static func _kills_before(kills: Dictionary, a, b) -> bool:
	var count_a := int(kills[a])
	var count_b := int(kills[b])
	if count_a != count_b:
		return count_a > count_b
	return String(a) < String(b)
