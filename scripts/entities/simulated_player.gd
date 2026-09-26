extends CharacterBody2D

## A background "other adventurer" populating a zone — the Erenshor-style
## illusion of a live world, without being the spectated character. Reuses
## AIDecision.resolve_state() directly (the same pure function Character
## uses): passing a context with quest/travel/loot fields always false
## naturally limits it to flee/rest/combat/chase/wander, exactly the subset
## that makes sense for a companion with no quests or loot of its own.
##
## `group_leader` (set by Character when it recruits this companion — see
## Character._recruit_companions_in_zone) switches two behaviors: the
## "wander" fallback becomes "follow the leader" instead of random zone-
## bound wandering, and the position clamp switches from the home zone's
## own bounds to the whole world's, so a grouped companion can actually
## follow the leader between zones (including into Sundered Crypt, which
## has no simulated players of its own). Ungrouped companions behave
## exactly as before — zone-locked wandering, no leader to follow.
## Recruitment is permanent for this slice: once grouped, always grouped.
##
## Still no quests or loot pickup (non-goals), but companions DO gain XP
## and level up from their own kills now (LevelingSystem, same as
## Character) — Erenshor's simulated players "get stronger" over time, and
## that's cheap to support once EnemyDeath already tracks who landed the
## kill.

const MOVE_SPEED := 75.0
const ATTACK_RANGE := 28.0
const AGGRO_RANGE := 150.0
const ATTACK_COOLDOWN_MS := 1000
const RESPAWN_DELAY_S := 3.0
const HP_REGEN_PER_SECOND := 2.5
const TARGET_SPRITE_SIZE := 40.0
const ATTACK_ANIM_DURATION_MS := 400.0

const FOLLOW_DISTANCE := 45.0

@export var player_name: String = "Adventurer"
@export var max_hp: int = 45
@export var attack_damage_min: int = 5
@export var attack_damage_max: int = 9
@export var sprite_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var home_zone_id: String = "thornfield_meadow"

var hp: int
var level: int = 1
var xp: int = 0
var current_state: String = "wander"
var last_attack_time_ms: int = 0
var wander_target: Vector2 = Vector2.ZERO
var rng := RandomNumberGenerator.new()
var is_dead: bool = false
var game_time_ms: float = 0.0
var hp_regen_accumulator: float = 0.0
var spawn_position: Vector2 = Vector2.ZERO
var attack_anim_until_ms: float = 0.0
var group_leader: Node2D = null

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var name_label: Label = $NameLabel

func _ready() -> void:
	rng.randomize()
	spawn_position = global_position
	wander_target = global_position
	hp = max_hp
	sprite.modulate = sprite_tint
	name_label.text = player_name
	# Stagger label height per player so two allies standing together don't
	# draw their names on top of each other.
	name_label.position.y -= 12.0 * float(hash(player_name) % 2)
	add_to_group("combat_targets")
	add_to_group("simulated_players")

func _physics_process(delta: float) -> void:
	game_time_ms += delta * 1000.0
	if hp <= 0:
		return
	# Resolved once per tick and reused by both the state decision AND the
	# actual combat/chase actions in _act() below, so what gets fought is
	# always exactly what the decision was based on — not two independent
	# lookups that could disagree.
	var preferred_hostile := _preferred_hostile()
	var context := _build_context(preferred_hostile)
	current_state = AIDecision.resolve_state(context)["state"]
	_act(delta, context, preferred_hostile)

## Prefer fighting alongside the leader's own target when one exists and is
## still alive — this is what makes a grouped fight visibly "shared" rather
## than just several individuals coincidentally near each other. Falls back
## to the closest enemy otherwise (leader not in combat, or ungrouped).
func _preferred_hostile() -> Node2D:
	if group_leader != null and is_instance_valid(group_leader):
		# Untyped on purpose: last_combat_target can be a stale reference to
		# an Enemy that's since been freed (Character only updates it when
		# ITS OWN combat_hostile changes, which can lag a frame behind the
		# target actually dying). Assigning a freed instance straight into a
		# Node2D-typed var throws "invalid previously freed instance" —
		# is_instance_valid() is the only safe way to check it first.
		var leader_target = group_leader.last_combat_target
		if leader_target != null and is_instance_valid(leader_target):
			return leader_target
	return _find_nearest_in_group("enemies")

func _build_context(nearest_hostile: Node2D) -> Dictionary:
	var context := {
		"hp_percent": float(hp) / float(max_hp),
		"hostile_in_attack_range": false,
		"hostile_in_aggro_range": false,
		"hostile_name": "",
		"item_nearby": false,
		"ready_to_travel": false,
		"quest_giver_in_zone": false,
		"quest_ready": false,
	}
	if nearest_hostile:
		var dist := global_position.distance_to(nearest_hostile.global_position)
		context["hostile_in_attack_range"] = dist <= ATTACK_RANGE
		context["hostile_in_aggro_range"] = dist <= AGGRO_RANGE
		context["hostile_name"] = nearest_hostile.enemy_name
	return context

func _find_nearest_in_group(group_name: String) -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := INF
	for node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node):
			continue
		var d := global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = node
	return nearest

func _act(delta: float, _context: Dictionary, preferred_hostile: Node2D) -> void:
	var base_anim := "idle"
	var combat_hostile: Node2D = null
	match current_state:
		"flee":
			# Flees from whatever's actually nearest to itself, not
			# necessarily the leader's target — self-preservation, same as
			# Character's own flee logic.
			var hostile := _find_nearest_in_group("enemies")
			if hostile:
				_move_toward(global_position - hostile.global_position)
			base_anim = "run"
		"rest":
			velocity = Vector2.ZERO
			_regen_hp(delta)
		"combat":
			velocity = Vector2.ZERO
			combat_hostile = preferred_hostile
			_attack_nearest_hostile(combat_hostile)
		"chase":
			if preferred_hostile:
				_move_toward(preferred_hostile.global_position - global_position)
			base_anim = "run"
		"wander":
			if group_leader != null and is_instance_valid(group_leader):
				var to_leader: Vector2 = group_leader.global_position - global_position
				if to_leader.length() > FOLLOW_DISTANCE:
					_move_toward(to_leader)
					base_anim = "run" if to_leader.length() > 150.0 else "walk"
				else:
					velocity = Vector2.ZERO
			else:
				var zone: Dictionary = ZoneTable.ZONES[home_zone_id]
				if global_position.distance_to(wander_target) < 8.0:
					wander_target = (global_position + Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))).clamp(zone["bounds_min"], zone["bounds_max"])
				_move_toward((wander_target - global_position) * 0.5)
				base_anim = "walk"
	var facing := _facing_from_velocity(velocity)
	if combat_hostile:
		facing = _facing_from_velocity(combat_hostile.global_position - global_position)
	if game_time_ms < attack_anim_until_ms:
		base_anim = "slash"
	_play_animation(base_anim, facing)
	# Grouped companions roam the whole world following their leader (e.g.
	# into Sundered Crypt); ungrouped ones stay clamped to their own zone,
	# same as before.
	if group_leader != null and is_instance_valid(group_leader):
		global_position = global_position.clamp(ZoneTable.WORLD_BOUNDS_MIN, ZoneTable.WORLD_BOUNDS_MAX)
	else:
		var zone: Dictionary = ZoneTable.ZONES[home_zone_id]
		global_position = global_position.clamp(zone["bounds_min"], zone["bounds_max"])

func _move_toward(direction: Vector2) -> void:
	velocity = direction.normalized() * MOVE_SPEED
	move_and_slide()

func _regen_hp(delta: float) -> void:
	hp_regen_accumulator += HP_REGEN_PER_SECOND * delta
	while hp_regen_accumulator >= 1.0 and hp < max_hp:
		hp += 1
		hp_regen_accumulator -= 1.0

func _attack_nearest_hostile(hostile: Node2D) -> void:
	var now := int(game_time_ms)
	if hostile == null or not CombatSystem.is_off_cooldown(last_attack_time_ms, ATTACK_COOLDOWN_MS, now):
		return
	last_attack_time_ms = now
	var damage := CombatSystem.roll_damage(attack_damage_min, attack_damage_max, rng)
	hostile.take_damage(damage, self)
	attack_anim_until_ms = game_time_ms + ATTACK_ANIM_DURATION_MS

func take_damage(amount: int) -> void:
	if is_dead:
		return
	hp = max(0, hp - amount)
	GameState.emit_signal("damage_dealt", global_position, amount, false)
	GameState.emit_signal("hit_landed", self, amount, false, false)
	if hp <= 0:
		_die()

func _die() -> void:
	is_dead = true
	GameState.emit_signal("chat_event", "ally_died", {"ally": self})
	GameState.log_event("[Ally] %s has fallen - respawning" % player_name)
	visible = false
	set_physics_process(false)
	await get_tree().create_timer(RESPAWN_DELAY_S).timeout
	hp = max_hp
	# A grouped companion respawns back at the leader's side rather than its
	# original home spot — otherwise dying mid-journey (e.g. in Sundered
	# Crypt) would strand it far from the party it's supposed to follow.
	var respawn_position := spawn_position
	if group_leader != null and is_instance_valid(group_leader):
		respawn_position = group_leader.global_position
	global_position = respawn_position
	wander_target = respawn_position
	visible = true
	set_physics_process(true)
	is_dead = false

## Mirrors Character.gain_xp/take_kill_credit — companions "get stronger"
## from their own kills too (same LevelingSystem, same hp/damage bonuses).
func take_kill_credit(_enemy_name: String, xp_reward: int) -> void:
	var result := LevelingSystem.apply_xp(level, xp, xp_reward)
	level = result["level"]
	xp = result["xp"]
	if result["leveled_up"]:
		max_hp += result["hp_bonus"]
		hp += result["hp_bonus"]
		attack_damage_min += result["damage_bonus"]
		attack_damage_max += result["damage_bonus"]
		GameState.log_event("[Ally] %s levels up to %d!" % [player_name, level])
		GameState.emit_signal("chat_event", "ally_level_up", {"ally": self, "level": level})

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
