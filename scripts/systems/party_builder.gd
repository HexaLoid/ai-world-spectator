class_name PartyBuilder
extends RefCounted

## Which pool members to add so a dungeon party has `size` people (hero
## included): a tank first when there is none, then a healer, then damage
## dealers, then anyone. `party` and `pool` are arrays of dictionaries with a
## "role" (tank/healer/melee/magic) and any other keys (the same dictionaries
## are returned). Deterministic: pool order breaks ties.
static func missing_members(hero_role: String, party: Array, pool: Array, size: int = 5) -> Array:
	var free := size - 1 - party.size()
	var picks: Array = []
	if free <= 0:
		return picks
	var has_tank := hero_role == "tank"
	var has_healer := hero_role == "healer"
	var in_party := {}
	for member in party:
		in_party[member.get("id", member.get("name", ""))] = true
		var role := String(member.get("role", ""))
		has_tank = has_tank or role == "tank"
		has_healer = has_healer or role == "healer"
	var remaining: Array = []
	for candidate in pool:
		if not in_party.has(candidate.get("id", candidate.get("name", ""))):
			remaining.append(candidate)
	if not has_tank:
		_take_first(remaining, picks, ["tank"], free)
	if not has_healer:
		_take_first(remaining, picks, ["healer"], free)
	while picks.size() < free:
		var before := picks.size()
		_take_first(remaining, picks, ["melee", "magic"], free)
		if picks.size() == before:
			break
	while picks.size() < free and not remaining.is_empty():
		picks.append(remaining.pop_front())
	return picks

static func _take_first(remaining: Array, picks: Array, roles: Array, free: int) -> void:
	if picks.size() >= free:
		return
	for i in range(remaining.size()):
		if roles.has(String(remaining[i].get("role", ""))):
			picks.append(remaining[i])
			remaining.remove_at(i)
			return
