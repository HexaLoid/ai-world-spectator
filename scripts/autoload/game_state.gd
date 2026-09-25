extends Node

# Signals here are emitted from other scripts via GameState.emit_signal(...), so
# the analyzer cannot see the emits within this class.
@warning_ignore_start("unused_signal")

## Emitted whenever the AI-controlled character transitions to a new behavior
## state (e.g. "idle", "attacking", "fleeing"); new_state is the state name.
signal character_state_changed(new_state: String)
## Emitted whenever the character's HP changes; hp and max_hp are the
## current and maximum health values, for the unit frame to update.
signal character_hp_changed(hp: int, max_hp: int)
## Emitted whenever the character's XP total changes; xp is the new total.
signal character_xp_changed(xp: int)
## Emitted whenever the character's class resource (e.g. Rage) changes;
## resource_amount and max_resource are its current and maximum values.
signal character_resource_changed(resource_amount: float, max_resource: float)
## Emitted when the character gains a level; level is the new level reached.
signal character_leveled_up(level: int)
## Emitted whenever the character's equipment changes; `equipment` maps each
## slot name (see LootTable.SLOTS) to the equipped item id — a slot with no
## item is absent or "". Always a copy, safe for listeners to keep.
signal character_equipment_changed(equipment: Dictionary)
## Emitted whenever the character's gold total changes; amount is the new total.
signal gold_changed(amount: int)
## Emitted for every logged activity event; message is the human-readable
## text describing what happened, for the spectator UI's activity feed.
signal activity_logged(message: String)
## Emitted whenever damage is dealt or healing is applied, so the UI can
## spawn a floating number at the location; position is the world position
## to spawn it at, amount is the value (always positive), is_heal
## distinguishes healing (green) from damage (red).
signal damage_dealt(position: Vector2, amount: int, is_heal: bool)
## Emitted whenever the character's current combat target changes (or
## becomes/stops being null); target is the Enemy node being fought, or
## null if not currently in combat. Enemy health bars listen to this to
## decide whether to show themselves.
signal combat_target_changed(target: Node2D)
## Emitted whenever the character's active quest changes — accepted,
## progressed, or turned in. quest_name is "" when no quest is active;
## progress/count are 0/0 in that case too. The Quest Giver's marker and
## the HUD's quest tracker both listen to this.
signal quest_changed(quest_name: String, progress: int, count: int)
## Emitted whenever the character enters a new zone (see
## Character._sync_current_zone()); zone_id is the zone just entered. Used to
## switch ambient audio, and generally useful for anything else that cares
## which zone the character is currently in.
signal zone_changed(zone_id: String)
## Emitted by gameplay code at chat-worthy moments (an ally joins or levels up,
## the character levels up, an elite dies, ...). `event` is a key of
## ChatLines.TEMPLATES; `context` carries what the templates need (`ally`
## node, `enemy`, `item`, `zone`, `level`). The ChatDirector decides whether
## anyone actually speaks.
signal chat_event(event: String, context: Dictionary)
## Emitted by the ChatDirector when an ally says something; the chat panel
## renders it. `channel` is "party" or "zone".
signal chat_message(channel: String, speaker: String, text: String)
## Emitted when the character's party membership changes.
signal party_changed()
## Emitted when the character discovers a codex entry; `kind` is "enemy",
## "item" or "zone" and `id` the EnemyTable / LootTable / ZoneTable key.
signal codex_changed(kind: String, id: String)

var character: Node2D = null
var camera: Camera2D = null
## What the spectated character has discovered (see CodexState). Session only.
var codex := CodexState.new()

func log_event(message: String) -> void:
	activity_logged.emit(message)
	print(message)

## Records a discovery and, if it is new, announces it. `kind` is "enemy",
## "item" or "zone".
func discover(kind: String, id: String) -> void:
	var is_new := false
	var display := ""
	match kind:
		"enemy":
			is_new = codex.discover_enemy(id)
			display = EnemyTable.name_of(id)
		"item":
			is_new = codex.discover_item(id)
			display = LootTable.display_name(id)
		"zone":
			is_new = codex.visit_zone(id)
			display = String(ZoneTable.ZONES.get(id, {}).get("name", id))
	if not is_new:
		return
	log_event("Codex: new entry - %s" % display)
	codex_changed.emit(kind, id)
