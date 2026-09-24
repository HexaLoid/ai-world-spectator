extends CharacterBody2D

const MOVE_SPEED := 80.0
const ATTACK_RANGE := 28.0
const AGGRO_RANGE := 160.0
const PICKUP_RANGE := 20.0
const ATTACK_COOLDOWN_MS := 900
const RESPAWN_DELAY_S := 2.0
const RESPAWN_POSITION := Vector2(0, 0)
const HP_REGEN_PER_SECOND := 3.0
const TARGET_SPRITE_SIZE := 40.0
const ATTACK_ANIM_DURATION_MS := 400.0
const RESPAWN_ZONE_ID := "thornfield_meadow"
const MAX_PARTY_SIZE := 2

const STATE_DISPLAY_NAMES := {
	"wander": "Wandering",
	"chase": "Chasing",
	"combat": "Fighting",
	"flee": "Fleeing",
	"loot": "Looting",
	"rest": "Resting",
	"travel": "Traveling",
	"quest": "Questing",
}

@export var max_hp: int = 60
@export var hp: int = 60
@export var level: int = 1
@export var xp: int = 0
@export var attack_damage_min: int = 4
@export var attack_damage_max: int = 8
## "" means "roll a random class at spawn" (see _ready()) — the normal way
## this ends up populated, since this is a single always-on spectator
## character with no class-select UI. A scene can still force a specific
## class by overriding this export directly, e.g. for testing.
@export var character_class: String = ""

## Slot name -> equipped item id (see LootTable.SLOTS); a missing key means
## the slot is empty. max_hp, attack_damage_min/max, crit_chance and armor are
## DERIVED from the base_* values plus equipment by _recompute_stats() —
## never adjust them directly for gear or level-ups, change the base and recompute.
var equipment: Dictionary = {}
var gold: int = 0
var character_name: String = ""
# True once the "low HP" chat line fired; re-armed when HP climbs back above 60%.
var low_hp_announced: bool = false
# Session statistics (shown on the character sheet); reset only by relaunching.
var kills_by_name: Dictionary = {}
var deaths: int = 0
var damage_dealt_total: int = 0
var damage_taken_total: int = 0
var gold_earned: int = 0
var armor: int = 0
var base_max_hp: int = 0
var base_damage_min: int = 0
var base_damage_max: int = 0
var crit_chance: float = 0.0
var current_state: String = "wander"
var last_attack_time_ms: int = 0
var wander_target: Vector2 = Vector2.ZERO
var rng := RandomNumberGenerator.new()
var is_dead: bool = false
var game_time_ms: float = 0.0
var hp_regen_accumulator: float = 0.0
var last_combat_target: Node2D = null
var current_zone_id: String = RESPAWN_ZONE_ID
var zone_entered_time_ms: float = 0.0
var party: Array = []

# Quest state. Progress is tracked passively (see take_kill_credit) rather
# than by directing combat toward the quest target — the character already
# fights whatever it encounters, so this just watches kills go by.
var active_quest_id: String = ""
var quest_progress: int = 0
var completed_quest_ids: Array = []
var last_offered_quest_index: int = -1
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var action_label: Label = $ActionLabel
var attack_anim_until_ms: float = 0.0

# Class resource (Rage for the warrior) and per-ability cooldown tracking.
# `class_def`/`ABILITIES` come from AbilityTable, keyed by `character_class`,
# so a second class can be added there later without touching this script's
# structure.
var class_def: Dictionary = {}
var resource_amount: float = 0.0
var max_resource: float = 0.0
var ability_cooldowns: Dictionary = {}

func _ready() -> void:
	rng.randomize()
	wander_target = global_position
	GameState.character = self
	add_to_group("combat_targets")
	if character_class == "":
		var class_ids := AbilityTable.CLASSES.keys()
		character_class = class_ids[rng.randi_range(0, class_ids.size() - 1)]
	class_def = AbilityTable.CLASSES.get(character_class, {})
	character_name = NameTable.pick(rng)
	max_resource = float(class_def.get("max_resource", 0.0))
	sprite.modulate = class_def.get("sprite_tint", Color(1.0, 1.0, 1.0, 1.0))
	base_max_hp = max_hp
	base_damage_min = attack_damage_min
	base_damage_max = attack_damage_max
	_recompute_stats()
	GameState.emit_signal("character_resource_changed", resource_amount, max_resource)
	# _sync_current_zone() only recruits on a zone TRANSITION, but the
	# character starts already inside its home zone rather than "arriving"
	# there — so that zone's companions need recruiting once, up front, or
	# they'd never get picked up unless the character later left and came
	# back.
	_recruit_companions_in_zone(current_zone_id)

func _physics_process(delta: float) -> void:
	game_time_ms += delta * 1000.0
	if low_hp_announced and hp * 10 > max_hp * 6:
		low_hp_announced = false
	if hp <= 0:
		return
	var context := _build_context()
	var decision := AIDecision.resolve_state(context)
	var new_state: String = decision["state"]
	if new_state != current_state:
		current_state = new_state
		GameState.log_event(decision["reason"])
		GameState.emit_signal("character_state_changed", current_state)
		action_label.text = STATE_DISPLAY_NAMES.get(current_state, current_state.capitalize())
	_act(delta, context)

func _facing_from_velocity(vel: Vector2) -> String:
	if vel.length() < 1.0:
		return "down"
	if abs(vel.x) > abs(vel.y):
		return "right" if vel.x > 0.0 else "left"
	return "down" if vel.y > 0.0 else "up"

func _play_animation(base_anim: String, facing: String) -> void:
	if sprite.sprite_frames == null:
		return
	var anim_name := base_anim + "_" + facing
	var mirrored := false
	if not sprite.sprite_frames.has_animation(anim_name):
		# Sheets without a dedicated up/down pose (e.g. the Wolf) only have a
		# "_right" animation; mirror it via flip_h for left, but up/down just
		# reuse the right-facing pose unmirrored since there's no better option.
		var fallback := base_anim + "_right"
		if not sprite.sprite_frames.has_animation(fallback):
			return
		anim_name = fallback
		mirrored = facing == "left"
	sprite.flip_h = mirrored
	if sprite.animation != anim_name or not sprite.is_playing():
		sprite.play(anim_name)
	var first_frame := sprite.sprite_frames.get_frame_texture(anim_name, 0)
	if first_frame:
		var native_size: Vector2 = first_frame.get_size()
		if native_size.x > 0.0 and native_size.y > 0.0:
			var s: float = TARGET_SPRITE_SIZE / max(native_size.x, native_size.y)
			sprite.scale = Vector2(s, s)

func _build_context() -> Dictionary:
	var nearest_hostile := _find_nearest_in_group("enemies")
	var nearest_item := _find_nearest_wanted_item()
	var quest_giver := _find_nearest_in_group("quest_givers")
	var next_zone_id := ZoneTable.next_zone_id(current_zone_id, level)
	var context := {
		"hp_percent": float(hp) / float(max_hp),
		"hostile_in_attack_range": false,
		"hostile_in_aggro_range": false,
		"hostile_name": "",
		"item_nearby": false,
		"ready_to_travel": (game_time_ms - zone_entered_time_ms) >= ZoneTable.stay_duration_ms(current_zone_id),
		"next_zone_name": String(ZoneTable.ZONES[next_zone_id]["name"]),
		"quest_giver_in_zone": quest_giver != null and _zone_id_for_position(quest_giver.global_position) == current_zone_id,
		"quest_ready": _quest_has_something_to_do(),
	}
	if nearest_hostile:
		var dist := global_position.distance_to(nearest_hostile.global_position)
		context["hostile_in_attack_range"] = dist <= ATTACK_RANGE
		context["hostile_in_aggro_range"] = dist <= AGGRO_RANGE
		context["hostile_name"] = nearest_hostile.enemy_name
	if nearest_item:
		var item_dist := global_position.distance_to(nearest_item.global_position)
		context["item_nearby"] = item_dist <= AGGRO_RANGE
	return context

func _find_nearest_in_group(group_name: String) -> Node2D:
	var nodes := get_tree().get_nodes_in_group(group_name)
	var nearest: Node2D = null
	var nearest_dist := INF
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var d := global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = node
	return nearest

## True if this ground pickup is worth walking to right now: gold, a potion
## while hurt, or gear ItemScoring says would actually be equipped. Junk
## (non-upgrades, gear above the character's level) is ignored entirely.
func _wants_item(item: Node2D) -> bool:
	if item.gold_amount > 0:
		return true
	var item_def: Dictionary = LootTable.ITEMS.get(item.item_id, {})
	if item_def.get("type", "") == "consumable":
		return hp < max_hp
	var slot: String = item_def.get("slot", "")
	return ItemScoring.is_upgrade(equipment.get(slot, ""), item.item_id, class_def, level)

func _find_nearest_wanted_item() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for node in get_tree().get_nodes_in_group("items"):
		if not is_instance_valid(node) or not _wants_item(node):
			continue
		var d := global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = node
	return nearest

func _act(delta: float, _context: Dictionary) -> void:
	var base_anim := "idle"
	var combat_hostile: Node2D = null
	match current_state:
		"flee":
			_try_self_heal()
			var hostile := _find_nearest_in_group("enemies")
			if hostile:
				_move_toward(global_position - hostile.global_position, MOVE_SPEED)
			base_anim = "run"
		"rest":
			_try_self_heal()
			velocity = Vector2.ZERO
			_regen_hp(delta)
			_tick_resource(delta)
		"combat":
			velocity = Vector2.ZERO
			combat_hostile = _find_nearest_in_group("enemies")
			_attack_nearest_hostile()
			if combat_hostile:
				_try_combat_abilities(combat_hostile)
		"chase":
			var hostile := _find_nearest_in_group("enemies")
			if hostile:
				if not _try_gap_closer(hostile):
					_move_toward(hostile.global_position - global_position, MOVE_SPEED)
			base_anim = "run"
		"loot":
			var item := _find_nearest_wanted_item()
			if item:
				var to_item := item.global_position - global_position
				if to_item.length() <= PICKUP_RANGE:
					_pickup_item(item)
				else:
					_move_toward(to_item, MOVE_SPEED)
			base_anim = "walk"
			_tick_resource(delta)
		"wander":
			var zone: Dictionary = ZoneTable.ZONES[current_zone_id]
			if global_position.distance_to(wander_target) < 8.0:
				wander_target = (global_position + Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))).clamp(zone["bounds_min"], zone["bounds_max"])
			_move_toward(wander_target - global_position, MOVE_SPEED * 0.5)
			base_anim = "walk"
			_tick_resource(delta)
		"quest":
			var quest_giver := _find_nearest_in_group("quest_givers")
			if quest_giver:
				var to_giver := quest_giver.global_position - global_position
				if to_giver.length() <= PICKUP_RANGE:
					_interact_with_quest_giver()
				else:
					_move_toward(to_giver, MOVE_SPEED)
			base_anim = "walk"
		"travel":
			_do_travel()
			base_anim = "run"
	var facing := _facing_from_velocity(velocity)
	if combat_hostile:
		facing = _facing_from_velocity(combat_hostile.global_position - global_position)
	_update_combat_target(combat_hostile)
	if game_time_ms < attack_anim_until_ms:
		base_anim = "slash"
	_play_animation(base_anim, facing)
	# A hard safety clamp against the WHOLE traversable world, not just the
	# current zone: any state (a mid-corridor Charge onto a border enemy,
	# a Flee shoved past a zone edge, ...) can legitimately put the
	# character outside its "home" zone's own bounds without that meaning
	# it left the world. Clamping to current_zone_id's bounds here instead
	# would snap it straight back across the map the instant that happens.
	global_position = global_position.clamp(ZoneTable.WORLD_BOUNDS_MIN, ZoneTable.WORLD_BOUNDS_MAX)
	_sync_current_zone()

func _move_toward(direction: Vector2, speed: float) -> void:
	velocity = direction.normalized() * speed
	move_and_slide()

func _do_travel() -> void:
	var dest_center: Vector2 = ZoneTable.ZONES[ZoneTable.next_zone_id(current_zone_id, level)]["center"]
	_move_toward(dest_center - global_position, MOVE_SPEED)

## Which zone's bounds rectangle contains `pos`, or `current_zone_id` if
## `pos` isn't inside any zone (e.g. the corridor) — used both to detect the
## character's own arrival and to check which zone a stationary landmark
## (the Quest Giver) belongs to.
func _zone_id_for_position(pos: Vector2) -> String:
	for zone_id in ZoneTable.ZONES:
		var zone: Dictionary = ZoneTable.ZONES[zone_id]
		var bounds_min: Vector2 = zone["bounds_min"]
		var bounds_max: Vector2 = zone["bounds_max"]
		if pos.x < bounds_min.x or pos.x > bounds_max.x:
			continue
		if pos.y < bounds_min.y or pos.y > bounds_max.y:
			continue
		return zone_id
	return current_zone_id

## Detects "arrival" as actually crossing into a zone's bounds rectangle
## (checked every frame, regardless of state) rather than the "travel" state
## reaching that zone's exact center — so wandering/fighting across a border
## (e.g. a Charge that lands inside the next zone) also correctly updates
## which zone the character calls home, not just a deliberate full trip.
func _sync_current_zone() -> void:
	var zone_id := _zone_id_for_position(global_position)
	if zone_id == current_zone_id:
		return
	current_zone_id = zone_id
	zone_entered_time_ms = game_time_ms
	# Otherwise the next "wander" tick chases whatever stale target was
	# picked back in the old zone — clamped to THAT zone's bounds — and
	# walks the character straight back out across the corridor instead
	# of actually exploring the one it just arrived in.
	wander_target = global_position
	GameState.log_event("Arrives in %s" % ZoneTable.ZONES[zone_id]["name"])
	GameState.emit_signal("zone_changed", zone_id)
	GameState.emit_signal("chat_event", "zone_arrive", {"zone": String(ZoneTable.ZONES[zone_id]["name"])})
	_recruit_companions_in_zone(zone_id)

## Recruits up to MAX_PARTY_SIZE ungrouped SimulatedPlayers whose home zone
## is the one just entered — permanent for this slice (no leave condition),
## which is why this only ever needs to run on arrival, not continuously.
## A recruited companion switches its own behavior (following instead of
## zone-bound wandering, world bounds instead of zone bounds — see
## SimulatedPlayer) entirely on its own once `group_leader` is set; nothing
## else here needs to manage that.
func _recruit_companions_in_zone(zone_id: String) -> void:
	if party.size() >= MAX_PARTY_SIZE:
		return
	for sp in get_tree().get_nodes_in_group("simulated_players"):
		if party.size() >= MAX_PARTY_SIZE:
			return
		if not is_instance_valid(sp) or sp.group_leader != null:
			continue
		if sp.home_zone_id != zone_id:
			continue
		sp.group_leader = self
		party.append(sp)
		GameState.log_event("%s joins the group!" % sp.player_name)
		GameState.emit_signal("party_changed")
		GameState.emit_signal("chat_event", "ally_joined", {"ally": sp})

func _regen_hp(delta: float) -> void:
	hp_regen_accumulator += HP_REGEN_PER_SECOND * delta
	while hp_regen_accumulator >= 1.0 and hp < max_hp:
		hp += 1
		hp_regen_accumulator -= 1.0

func _update_combat_target(combat_hostile: Node2D) -> void:
	if combat_hostile != last_combat_target:
		last_combat_target = combat_hostile
		GameState.emit_signal("combat_target_changed", combat_hostile)

func _attack_nearest_hostile() -> void:
	var now := int(game_time_ms)
	if not CombatSystem.is_off_cooldown(last_attack_time_ms, ATTACK_COOLDOWN_MS, now):
		return
	var hostile := _find_nearest_in_group("enemies")
	if hostile == null:
		return
	last_attack_time_ms = now
	var roll := _roll_damage(attack_damage_min, attack_damage_max)
	# Logged before the hit lands so a killing blow reads "hit ... Defeated ...".
	if roll["is_crit"]:
		GameState.log_event("Critical hit on %s for %d!" % [hostile.enemy_name, roll["damage"]])
	hostile.take_damage(roll["damage"], self)
	attack_anim_until_ms = game_time_ms + ATTACK_ANIM_DURATION_MS
	_gain_resource(float(class_def.get("rage_per_swing", 0.0)))

## Rolls base weapon damage (optionally scaled by `multiplier`, e.g.
## Heroic Strike's bonus) and then an independent crit roll against
## crit_chance (from equipped gear); a crit doubles the final damage.
## Centralizes the crit check so both the plain auto-attack and Heroic
## Strike apply it the same way instead of each rolling it separately.
func _roll_damage(min_damage: int, max_damage: int, multiplier: float = 1.0) -> Dictionary:
	var damage := int(round(CombatSystem.roll_damage(min_damage, max_damage, rng) * multiplier))
	var is_crit := rng.randf() < crit_chance
	if is_crit:
		damage *= 2
	return {"damage": damage, "is_crit": is_crit}

func take_damage(amount: int) -> void:
	if is_dead:
		return
	amount = StatCalculator.mitigate(amount, armor)
	damage_taken_total += mini(amount, hp)
	hp = max(0, hp - amount)
	GameState.emit_signal("character_hp_changed", hp, max_hp)
	GameState.emit_signal("damage_dealt", global_position, amount, false)
	var hp_fraction := float(hp) / float(max_hp)
	if hp > 0 and hp_fraction < 0.3 and not low_hp_announced:
		low_hp_announced = true
		GameState.emit_signal("chat_event", "leader_low_hp", {})
	elif hp_fraction > 0.6:
		low_hp_announced = false
	_gain_resource(float(class_def.get("rage_per_hit_taken", 0.0)))
	if hp <= 0:
		_die()

func _die() -> void:
	is_dead = true
	deaths += 1
	GameState.emit_signal("chat_event", "leader_died", {})
	_update_combat_target(null)
	GameState.log_event("Character died - respawning")
	visible = false
	set_physics_process(false)
	await get_tree().create_timer(RESPAWN_DELAY_S).timeout
	hp = max_hp
	low_hp_announced = false
	global_position = RESPAWN_POSITION
	wander_target = RESPAWN_POSITION
	current_zone_id = RESPAWN_ZONE_ID
	zone_entered_time_ms = game_time_ms
	visible = true
	set_physics_process(true)
	is_dead = false
	ability_cooldowns.clear()
	resource_amount = 0.0
	GameState.emit_signal("character_hp_changed", hp, max_hp)
	GameState.emit_signal("character_resource_changed", resource_amount, max_resource)

## Returns seconds remaining before `ability_id` is off cooldown (0 if ready).
## Polled directly by the HUD's ability bar each frame, the same way
## CameraController polls GameState.character's position — cooldown sweeps
## need continuous updates, not a discrete signal per tick.
func get_ability_cooldown_remaining(ability_id: String) -> float:
	var ready_at: float = ability_cooldowns.get(ability_id, 0.0)
	return max(0.0, (ready_at - game_time_ms) / 1000.0)

func _ability_ready(ability_id: String, cost: float) -> bool:
	return get_ability_cooldown_remaining(ability_id) <= 0.0 and resource_amount >= cost

func _start_cooldown(ability_id: String, cooldown_ms: int) -> void:
	ability_cooldowns[ability_id] = game_time_ms + cooldown_ms

func _gain_resource(amount: float) -> void:
	if amount == 0.0 or max_resource <= 0.0:
		return
	resource_amount = clampf(resource_amount + amount, 0.0, max_resource)
	GameState.emit_signal("character_resource_changed", resource_amount, max_resource)

func _spend_resource(amount: float) -> void:
	_gain_resource(-amount)

## Passive resource change over time — decay for an aggressive resource like
## Rage (warrior), regen for a patient one like Mana (mage). Both fields
## default to 0.0 so a class only needs to set whichever one applies to it;
## called from the same "downtime" states (rest/loot/wander) that always
## drove Rage's decay, so warrior's balance is unchanged and mage's Mana
## simply regenerates during those same states instead.
func _tick_resource(delta: float) -> void:
	var regen := float(class_def.get("resource_regen_per_second", 0.0))
	var decay := float(class_def.get("resource_decay_per_second", 0.0))
	_gain_resource((regen - decay) * delta)

## Finds the id of the current class's ability (from class_def's own
## "abilities" list, never the full global AbilityTable.ABILITIES) whose
## "kind" matches, or "" if the class has none of that kind — e.g. the mage
## has no "gap_closer", so _try_gap_closer() below just no-ops for it.
func _find_class_ability_id(kind: String) -> String:
	for ability_id in class_def.get("abilities", []):
		if AbilityTable.ABILITIES.get(ability_id, {}).get("kind", "") == kind:
			return ability_id
	return ""

## Gap closer used from the "chase" state instead of walking, when off
## cooldown. Returns true if it fired (caller skips its normal move step).
## Not every class has one (the mage doesn't), in which case this just
## returns false immediately and the caller falls back to walking.
func _try_gap_closer(hostile: Node2D) -> bool:
	var ability_id := _find_class_ability_id("gap_closer")
	if ability_id == "":
		return false
	var def: Dictionary = AbilityTable.ABILITIES.get(ability_id, {})
	if not _ability_ready(ability_id, float(def.get("resource_cost", 0.0))):
		return false
	_start_cooldown(ability_id, int(def.get("cooldown_ms", 0)))
	var to_hostile := hostile.global_position - global_position
	# Land just outside melee range rather than exactly on top of the target.
	global_position = hostile.global_position - to_hostile.normalized() * (ATTACK_RANGE * 0.9)
	_gain_resource(float(def.get("resource_gain", 0.0)))
	GameState.log_event("Uses %s on %s!" % [def.get("name", "an ability"), hostile.enemy_name])
	return true

## Layers the class's non-gap-closer/self-heal abilities (a bonus-damage hit
## and a damage-over-time effect, for both classes so far) on top of the
## normal auto-attack, one at a time in class ability-list order, while in
## the "combat" state.
func _try_combat_abilities(hostile: Node2D) -> void:
	for ability_id in class_def.get("abilities", []):
		var def: Dictionary = AbilityTable.ABILITIES.get(ability_id, {})
		var kind: String = def.get("kind", "")
		if kind != "bleed" and kind != "melee_hit":
			continue
		if not _ability_ready(ability_id, float(def.get("resource_cost", 0.0))):
			continue
		if kind == "bleed":
			_use_bleed(hostile, ability_id, def)
		else:
			_use_melee_hit(hostile, ability_id, def)
		return

func _use_bleed(hostile: Node2D, ability_id: String, def: Dictionary) -> void:
	_spend_resource(float(def.get("resource_cost", 0.0)))
	_start_cooldown(ability_id, int(def.get("cooldown_ms", 0)))
	hostile.apply_bleed(
		int(def.get("tick_damage_min", 0)),
		int(def.get("tick_damage_max", 0)),
		int(def.get("tick_count", 0)),
		int(def.get("tick_interval_ms", 0)),
		self
	)
	attack_anim_until_ms = game_time_ms + ATTACK_ANIM_DURATION_MS
	GameState.log_event("%s afflicts %s - taking damage over time!" % [def.get("name", "An ability"), hostile.enemy_name])

func _use_melee_hit(hostile: Node2D, ability_id: String, def: Dictionary) -> void:
	_spend_resource(float(def.get("resource_cost", 0.0)))
	_start_cooldown(ability_id, int(def.get("cooldown_ms", 0)))
	var roll := _roll_damage(attack_damage_min, attack_damage_max, float(def.get("damage_multiplier", 1.0)))
	var crit_suffix := " (Critical!)" if roll["is_crit"] else ""
	GameState.log_event("%s hits %s for %d!%s" % [def.get("name", "An ability"), hostile.enemy_name, roll["damage"], crit_suffix])
	hostile.take_damage(roll["damage"], self)
	attack_anim_until_ms = game_time_ms + ATTACK_ANIM_DURATION_MS

## Checked at the start of the "flee"/"rest" states rather than folded into
## AIDecision, so the FSM's pure state-selection logic stays untouched — this
## only changes how much HP the character has by the time flee/rest run.
func _try_self_heal() -> void:
	var ability_id := _find_class_ability_id("self_heal")
	if ability_id == "":
		return
	var def: Dictionary = AbilityTable.ABILITIES.get(ability_id, {})
	if not _ability_ready(ability_id, float(def.get("resource_cost", 0.0))):
		return
	_spend_resource(float(def.get("resource_cost", 0.0)))
	_start_cooldown(ability_id, int(def.get("cooldown_ms", 0)))
	var old_hp := hp
	hp = min(max_hp, hp + int(max_hp * float(def.get("heal_percent", 0.0))))
	var healed := hp - old_hp
	if healed <= 0:
		return
	GameState.emit_signal("character_hp_changed", hp, max_hp)
	GameState.emit_signal("damage_dealt", global_position, healed, true)
	GameState.log_event("Uses %s - recovers %d HP!" % [def.get("name", "an ability"), healed])

## Recomputes every gear-dependent stat from the base_* values and the
## current equipment. Current HP is only ever clamped down to the new max
## (equipping HP gear raises the ceiling, it does not heal).
func _recompute_stats() -> void:
	var derived := StatCalculator.derive(
		{"max_hp": base_max_hp, "damage_min": base_damage_min, "damage_max": base_damage_max, "crit_chance": 0.0},
		equipment, class_def)
	max_hp = derived["max_hp"]
	attack_damage_min = derived["damage_min"]
	attack_damage_max = derived["damage_max"]
	crit_chance = derived["crit_chance"]
	armor = derived["armor"]
	hp = mini(hp, max_hp)

func _gain_gold(amount: int) -> void:
	gold += amount
	gold_earned += amount
	GameState.emit_signal("gold_changed", gold)

## Everything the character sheet displays, as a plain dictionary (see
## SheetText.build). `xp` is XP earned within the current level and `xp_next`
## the XP span of this level (0 at max level), matching the unit frame's bar.
func get_sheet_snapshot() -> Dictionary:
	var primary: String = class_def.get("primary_stat", "")
	var gear := StatCalculator.gear_totals(equipment)
	var primary_value := float(gear.get(primary, 0.0)) if primary != "" else 0.0
	var next_threshold := LevelingSystem.get_next_threshold(level)
	var prev_threshold: int = LevelingSystem.XP_THRESHOLDS[level - 2] if level > 1 else 0
	var quest: Dictionary = _find_quest(active_quest_id) if active_quest_id != "" else {}
	var quest_text := "none active"
	if not quest.is_empty():
		quest_text = "%s %d/%d" % [quest.get("name", ""), quest_progress, int(quest.get("count", 0))]
	return {
		"character_name": character_name,
		"level": level,
		"class_name": character_class,
		"zone_name": String(ZoneTable.ZONES[current_zone_id]["name"]),
		"xp": xp - prev_threshold,
		"xp_next": 0 if next_threshold <= 0 else next_threshold - prev_threshold,
		"hp": hp,
		"max_hp": max_hp,
		"damage_min": attack_damage_min,
		"damage_max": attack_damage_max,
		"armor": armor,
		"crit_chance": crit_chance,
		"primary_stat": primary,
		"primary_value": primary_value,
		"primary_bonus_percent": primary_value * StatCalculator.PRIMARY_STAT_DAMAGE_PER_POINT * 100.0,
		"equipment": equipment.duplicate(),
		"gold": gold,
		"quest_text": quest_text,
		"quests_completed": completed_quest_ids.size(),
		"kills_by_name": kills_by_name.duplicate(),
		"deaths": deaths,
		"damage_dealt": damage_dealt_total,
		"damage_taken": damage_taken_total,
		"gold_earned": gold_earned,
		"time_played_ms": game_time_ms,
	}

func gain_xp(amount: int) -> void:
	var result := LevelingSystem.apply_xp(level, xp, amount)
	level = result["level"]
	xp = result["xp"]
	if result["leveled_up"]:
		base_max_hp += result["hp_bonus"]
		base_damage_min += result["damage_bonus"]
		base_damage_max += result["damage_bonus"]
		_recompute_stats()
		hp += result["hp_bonus"]
		GameState.log_event("Leveled up to %d!" % level)
		GameState.emit_signal("character_leveled_up", level)
		GameState.emit_signal("chat_event", "leader_level_up", {"level": level})
		GameState.emit_signal("character_hp_changed", hp, max_hp)
	GameState.emit_signal("character_xp_changed", xp)

func take_kill_credit(enemy_name: String, xp_reward: int) -> void:
	kills_by_name[enemy_name] = int(kills_by_name.get(enemy_name, 0)) + 1
	GameState.log_event("Defeated %s" % enemy_name)
	gain_xp(xp_reward)
	_advance_quest_progress(enemy_name)

func _pickup_item(item: Node2D) -> void:
	if item.gold_amount > 0:
		_gain_gold(item.gold_amount)
	else:
		_acquire_item(item.item_id)
	item.queue_free()

## Shared by picking an item up off the ground and turning in a quest's
## item reward — both are "the character now owns this item". Consumables
## are used immediately; gear is equipped only if ItemScoring says it is an
## upgrade for this class and level, and the log says why either way.
func _acquire_item(item_id: String) -> void:
	var item_def: Dictionary = LootTable.ITEMS.get(item_id, {})
	if item_def.is_empty():
		return
	var display_name := LootTable.display_name(item_id)
	if item_def.get("type", "") == "consumable":
		var old_hp := hp
		hp = min(max_hp, hp + int(item_def.get("heal", 0)))
		var healed := hp - old_hp
		GameState.log_event("Used %s" % display_name)
		GameState.emit_signal("character_hp_changed", hp, max_hp)
		if healed > 0:
			GameState.emit_signal("damage_dealt", global_position, healed, true)
		return
	var slot: String = item_def.get("slot", "")
	if not LootTable.SLOTS.has(slot):
		push_warning("Item %s has no valid slot" % item_id)
		return
	if not ItemScoring.meets_level(item_id, level):
		GameState.log_event("Received %s - needs level %d" % [display_name, int(item_def.get("level_req", 1))])
		return
	if not ItemScoring.is_upgrade(equipment.get(slot, ""), item_id, class_def, level):
		GameState.log_event("Found %s - current gear is better" % display_name)
		return
	equipment[slot] = item_id
	_recompute_stats()
	GameState.log_event("Equipped %s (%s)" % [display_name, ItemScoring.describe_stats(item_id)])
	GameState.emit_signal("character_equipment_changed", equipment.duplicate())
	if item_def.get("rarity", "") in ["rare", "epic"]:
		GameState.emit_signal("chat_event", "leader_loot", {"item": display_name})
	GameState.emit_signal("character_hp_changed", hp, max_hp)

func _find_quest(quest_id: String) -> Dictionary:
	for quest in QuestTable.QUESTS:
		if quest.get("id", "") == quest_id:
			return quest
	return {}

func _advance_quest_progress(enemy_name: String) -> void:
	if active_quest_id == "":
		return
	var quest := _find_quest(active_quest_id)
	if quest.is_empty() or quest.get("target_name", "") != enemy_name:
		return
	quest_progress += 1
	var count: int = int(quest.get("count", 0))
	GameState.emit_signal("quest_changed", quest.get("name", ""), quest_progress, count)
	if quest_progress >= count:
		GameState.log_event("Quest ready to turn in: %s" % quest.get("name", ""))

## Finds the next QUESTS entry (in rotation order from the last one offered)
## that isn't already completed, meets its min_level, and has every quest id
## in its `requires` already in completed_quest_ids — this is what turns the
## flat rotation into chains (e.g. dire_wolf_hunt requires cull_the_wolves).
## Recycles completed_quest_ids once every quest has been done, so there's
## always something to offer rather than the rotation running dry — the whole
## chain then replays from its two unlocked intro quests. Read-only aside
## from that recycle — accepting is a separate step (_accept_next_quest).
func _find_next_eligible_quest_index() -> int:
	var quests: Array = QuestTable.QUESTS
	if quests.is_empty():
		return -1
	if completed_quest_ids.size() >= quests.size():
		completed_quest_ids.clear()
	for i in range(quests.size()):
		var idx: int = (last_offered_quest_index + 1 + i) % quests.size()
		var quest: Dictionary = quests[idx]
		if completed_quest_ids.has(quest.get("id", "")):
			continue
		if level < int(quest.get("min_level", 1)):
			continue
		if not _quest_requirements_met(quest):
			continue
		return idx
	return -1

## True if every prerequisite quest id in `quest`'s `requires` array is
## already in completed_quest_ids (vacuously true for an empty array).
func _quest_requirements_met(quest: Dictionary) -> bool:
	var requires: Array = quest.get("requires", [])
	for prereq_id in requires:
		if not completed_quest_ids.has(prereq_id):
			return false
	return true

func _quest_has_something_to_do() -> bool:
	if active_quest_id != "":
		var quest := _find_quest(active_quest_id)
		return not quest.is_empty() and quest_progress >= int(quest.get("count", 0))
	return _find_next_eligible_quest_index() >= 0

func _interact_with_quest_giver() -> void:
	if active_quest_id != "":
		var quest := _find_quest(active_quest_id)
		if not quest.is_empty() and quest_progress >= int(quest.get("count", 0)):
			_turn_in_quest(quest)
	if active_quest_id == "":
		_accept_next_quest()

func _turn_in_quest(quest: Dictionary) -> void:
	GameState.log_event("Turned in quest: %s" % quest.get("name", ""))
	gain_xp(int(quest.get("xp_reward", 0)))
	var item_reward: String = quest.get("item_reward", "")
	if item_reward != "":
		_acquire_item(item_reward)
	completed_quest_ids.append(active_quest_id)
	active_quest_id = ""
	quest_progress = 0
	GameState.emit_signal("quest_changed", "", 0, 0)

func _accept_next_quest() -> void:
	var idx := _find_next_eligible_quest_index()
	if idx < 0:
		return
	var quest: Dictionary = QuestTable.QUESTS[idx]
	last_offered_quest_index = idx
	active_quest_id = quest.get("id", "")
	quest_progress = 0
	GameState.log_event("Accepted quest: %s (0/%d %s)" % [quest.get("name", ""), quest.get("count", 0), quest.get("target_name", "")])
	GameState.emit_signal("quest_changed", quest.get("name", ""), 0, int(quest.get("count", 0)))
