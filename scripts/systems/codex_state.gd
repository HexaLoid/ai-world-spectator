class_name CodexState
extends RefCounted

## What the spectated character has discovered so far (session only). Pure
## data: no nodes, no signals; GameState wraps it and emits codex_changed.

var enemies_met: Dictionary = {}
var items_found: Dictionary = {}
var zones_visited: Dictionary = {}

## Each discover/visit call returns true only when the entry was new; unknown
## ids are ignored and return false.
func discover_enemy(id: String) -> bool:
	if not EnemyTable.ENEMIES.has(id) or enemies_met.has(id):
		return false
	enemies_met[id] = true
	return true

func discover_item(id: String) -> bool:
	if not LootTable.ITEMS.has(id) or items_found.has(id):
		return false
	items_found[id] = true
	return true

func visit_zone(id: String) -> bool:
	if not ZoneTable.ZONES.has(id) or zones_visited.has(id):
		return false
	zones_visited[id] = true
	return true

func enemy_met(id: String) -> bool:
	return enemies_met.has(id)

func item_found(id: String) -> bool:
	return items_found.has(id)

func zone_visited(id: String) -> bool:
	return zones_visited.has(id)

func enemies_met_count() -> int:
	return enemies_met.size()

func items_found_count() -> int:
	return items_found.size()

func zones_visited_count() -> int:
	return zones_visited.size()
