extends Node

## Balance-simulation observer (test tooling only). Added under Main by
## sim_run.gd; listens to GameState signals and polls GameState.character,
## printing one `SIM|t=<game seconds>|<kind>|key=value|...` line per event.
## It never changes game state. tests/sim/summarize.py parses the output.

var duration_s: float = 1500.0
var snap_interval_s: float = 30.0
var run_info: String = ""
var trace_damage: bool = false
var watch_enemy: String = ""

var t: float = 0.0
var next_snap_s: float = 0.0
var finished: bool = false
var boss_names: Dictionary = {}
var last_target_name: String = ""
var last_equipment: Dictionary = {}
var zone_time: Dictionary = {}
var state_time: Dictionary = {}
var last_xp_t: float = 0.0
var max_xp_gap_s: float = 0.0
var max_xp_gap_end_t: float = 0.0
var kills: int = 0
var ally_kills: int = 0
var boss_kills: Array = []
var quests_done: int = 0
var zones_seen: Array = []
var boss_deaths: Dictionary = {}
# Open fights, keyed by enemy instance id: a fight begins the first time the
# character targets that enemy instance (switching targets back and forth does
# not restart it) and ends when the character kills it ("win"), the character
# dies while it is the last target ("death"), or it disappears some other way,
# e.g. an ally's kill ("other"). Emitted as
# `fight|enemy=..|result=..|dur=..|level=..|hp_start=..|min_hp=..|max_hp=..`.
var fights: Dictionary = {}
var last_target_id: int = 0
var seed_base: int = 0
var seeded_count: int = 0

func _ready() -> void:
	process_priority = 1000
	process_physics_priority = 1000
	for id in EnemyTable.ENEMIES:
		var def: Dictionary = EnemyTable.ENEMIES[id]
		if String(def.get("guaranteed_drop", "")) != "":
			boss_names[String(def["name"])] = id
	GameState.character_leveled_up.connect(_on_level_up)
	GameState.zone_changed.connect(_on_zone_changed)
	GameState.activity_logged.connect(_on_activity)
	GameState.character_equipment_changed.connect(_on_equipment_changed)
	GameState.character_xp_changed.connect(_on_xp_changed)
	GameState.combat_target_changed.connect(_on_target_changed)
	if trace_damage:
		GameState.damage_dealt.connect(func(pos: Vector2, amount: int, is_heal: bool) -> void:
			_emit("dmg", {"amount": amount, "heal": int(is_heal), "x": roundi(pos.x), "y": roundi(pos.y),
				"char_hp": _ch().hp if _ch() else -1}))
	_emit("start", {"info": run_info})

func _ch() -> Node:
	return GameState.character

func _physics_process(delta: float) -> void:
	if finished:
		return
	t += delta
	var ch := _ch()
	if ch == null:
		return
	if zones_seen.is_empty():
		zones_seen.append(ch.current_zone_id)
		_emit("zone_arrive", {"zone": ch.current_zone_id, "level": ch.level})
	var zone: String = ch.current_zone_id
	zone_time[zone] = float(zone_time.get(zone, 0.0)) + delta
	if not ch.is_dead:
		var fleeing: bool = ch.current_state == "flee"
		for id in fights.keys():
			var f: Dictionary = fights[id]
			f["min_hp"] = mini(int(f["min_hp"]), ch.hp)
			if fleeing and not f["fleeing"]:
				f["flees"] = int(f["flees"]) + 1
			f["fleeing"] = fleeing
			if not is_instance_id_valid(id):
				_end_fight(id, "other")
	var state: String = "dead" if ch.is_dead else ch.current_state
	state_time[state] = float(state_time.get(state, 0.0)) + delta
	if t - last_xp_t > max_xp_gap_s:
		max_xp_gap_s = t - last_xp_t
		max_xp_gap_end_t = t
	if t >= next_snap_s:
		next_snap_s += snap_interval_s
		_snap()
	if t >= duration_s:
		finished = true
		_snap()
		_summary()
		get_tree().quit(0)

func _emit(kind: String, fields: Dictionary) -> void:
	var parts := PackedStringArray(["SIM", "t=%.1f" % t, kind])
	for key in fields:
		parts.append("%s=%s" % [key, str(fields[key])])
	print("|".join(parts))

func _snap() -> void:
	var ch := _ch()
	if ch == null:
		return
	var allies := PackedStringArray()
	for sp in ch.party:
		if is_instance_valid(sp):
			allies.append("%s:%d" % [sp.player_name, sp.level])
	_emit("snap", {
		"level": ch.level, "xp": ch.xp, "hp": ch.hp, "max_hp": ch.max_hp,
		"dmg": "%d-%d" % [ch.attack_damage_min, ch.attack_damage_max],
		"armor": ch.armor, "crit": "%.2f" % ch.crit_chance,
		"zone": ch.current_zone_id, "state": ch.current_state,
		"gold": ch.gold, "deaths": ch.deaths, "kills": kills,
		"quest": ch.active_quest_id, "qprog": ch.quest_progress,
		"allies": ",".join(allies),
	})
	if watch_enemy != "":
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e) and e.enemy_name == watch_enemy:
				_emit("watch", {"enemy": watch_enemy, "x": roundi(e.global_position.x), "y": roundi(e.global_position.y),
					"hp": e.hp, "max_hp": e.max_hp})

func _summary() -> void:
	var ch := _ch()
	var zt := PackedStringArray()
	for z in zone_time:
		zt.append("%s:%d" % [z, roundi(zone_time[z])])
	var st := PackedStringArray()
	for s in state_time:
		st.append("%s:%d" % [s, roundi(state_time[s])])
	var gear := PackedStringArray()
	for slot in ch.equipment:
		gear.append("%s:%s" % [slot, ch.equipment[slot]])
	var bd := PackedStringArray()
	for b in boss_deaths:
		bd.append("%s:%d" % [b, boss_deaths[b]])
	_emit("summary", {
		"class": ch.character_class, "level": ch.level, "xp": ch.xp,
		"deaths": ch.deaths, "kills": kills, "ally_kills": ally_kills,
		"gold": ch.gold, "quests_done": quests_done,
		"bosses": ",".join(PackedStringArray(boss_kills)),
		"deaths_to_bosses": ",".join(bd),
		"zones_seen": ",".join(PackedStringArray(zones_seen)),
		"zone_time": ",".join(zt), "state_time": ",".join(st),
		"max_xp_gap": "%.0f@%.0f" % [max_xp_gap_s, max_xp_gap_end_t],
		"gear": ",".join(gear),
	})

func _on_level_up(level: int) -> void:
	var ch := _ch()
	_emit("level_up", {"level": level, "zone": ch.current_zone_id, "deaths": ch.deaths})

func _on_zone_changed(zone_id: String) -> void:
	var ch := _ch()
	if not zones_seen.has(zone_id):
		zones_seen.append(zone_id)
	_emit("zone_arrive", {"zone": zone_id, "level": ch.level})

func _on_xp_changed(_xp: int) -> void:
	last_xp_t = t

func _on_target_changed(target: Node2D) -> void:
	if target == null or not is_instance_valid(target) or target.is_dead:
		return
	last_target_name = String(target.enemy_name)
	last_target_id = target.get_instance_id()
	if fights.has(last_target_id):
		return
	var ch := _ch()
	fights[last_target_id] = {"node": target, "enemy": String(target.enemy_name), "t0": t,
		"hp0": ch.hp, "min_hp": ch.hp, "max_hp": ch.max_hp, "level": ch.level,
		"enemy_hp0": target.hp, "dealt0": ch.damage_dealt_total, "flees": 0, "fleeing": false}

func _end_fight(id: int, result: String) -> void:
	if not fights.has(id):
		return
	var f: Dictionary = fights[id]
	fights.erase(id)
	var enemy_id: String = ""
	var ids := EnemyTable.ids_named(f["enemy"])
	if not ids.is_empty():
		enemy_id = ids[0]
	_emit("fight", {"enemy": enemy_id, "result": result, "dur": "%.1f" % (t - float(f["t0"])),
		"level": f["level"], "hp_start": f["hp0"], "min_hp": f["min_hp"] if result != "death" else 0,
		"max_hp": f["max_hp"], "enemy_hp_start": f["enemy_hp0"],
		"char_dmg": _ch().damage_dealt_total - int(f["dealt0"]), "flees": f["flees"]})

func _on_equipment_changed(equipment: Dictionary) -> void:
	for slot in equipment:
		if last_equipment.get(slot, "") != equipment[slot]:
			_emit("equip", {"slot": slot, "item": equipment[slot], "level": _ch().level})
	last_equipment = equipment.duplicate()

func _on_activity(message: String) -> void:
	var ch := _ch()
	if message.begins_with("Defeated "):
		var enemy_name := message.substr(9)
		kills += 1
		# The killed enemy is mid-_die(): same name, is_dead already set.
		var closed := false
		for id in fights.keys():
			if fights[id]["enemy"] == enemy_name and is_instance_id_valid(id) and fights[id]["node"].is_dead:
				_end_fight(id, "win")
				closed = true
				break
		if not closed:
			# Killed in the same frame it was first engaged (Character only
			# reports its combat target after that frame's attacks land).
			fights[-1] = {"node": null, "enemy": enemy_name, "t0": t, "hp0": ch.hp, "min_hp": ch.hp,
				"max_hp": ch.max_hp, "level": ch.level, "enemy_hp0": -1, "dealt0": ch.damage_dealt_total,
				"flees": 0, "fleeing": false}
			_end_fight(-1, "win")
		if boss_names.has(enemy_name):
			boss_kills.append(boss_names[enemy_name])
			_emit("boss_kill", {"name": boss_names[enemy_name], "by": "character", "level": ch.level})
	elif message.begins_with("[Ally] ") and message.contains(" defeats "):
		var ally := message.substr(7, message.find(" defeats ") - 7)
		var enemy_name := message.substr(message.find(" defeats ") + 9).trim_suffix("!")
		var grouped := false
		for sp in ch.party:
			if is_instance_valid(sp) and sp.player_name == ally:
				grouped = true
		if grouped:
			ally_kills += 1
			if boss_names.has(enemy_name):
				boss_kills.append(boss_names[enemy_name] + "(ally)")
				_emit("boss_kill", {"name": boss_names[enemy_name], "by": ally, "level": ch.level})
	elif message.begins_with("Character died"):
		var killer := last_target_name
		if boss_names.has(killer):
			var bid: String = boss_names[killer]
			boss_deaths[bid] = int(boss_deaths.get(bid, 0)) + 1
		_end_fight(last_target_id, "death")
		for id in fights.keys():
			_end_fight(id, "other")
		_emit("death", {"zone": ch.current_zone_id, "level": ch.level, "last_target": killer, "deaths": ch.deaths})
	elif message.begins_with("Turned in quest: "):
		quests_done += 1
		_emit("quest_done", {"id": ch.active_quest_id, "level": ch.level})
	elif message.begins_with("Accepted quest: "):
		_emit("quest_accept", {"id": ch.active_quest_id, "level": ch.level})

## Every gameplay entity owns an `rng` it randomize()s in _ready(); re-seed it
## right after that (the `ready` signal fires after _ready()) so a whole run
## is reproducible for a given seed. Tree insertion order is deterministic
## under --fixed-fps, so the running counter gives each entity a stable seed.
func on_node_added(node: Node) -> void:
	if not ("rng" in node):
		return
	if not (node.get("rng") is RandomNumberGenerator):
		return
	node.ready.connect(_seed_node.bind(node), CONNECT_ONE_SHOT)

func _seed_node(node: Node) -> void:
	seeded_count += 1
	var rng: RandomNumberGenerator = node.get("rng")
	rng.seed = hash([seed_base, seeded_count])
