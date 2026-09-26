extends Panel

## Shows the enemy the spectated character is fighting: name (with an Elite
## tag for guaranteed-drop enemies), HP bar with numbers, and damage range.
## Driven by GameState.combat_target_changed; HP is read from the enemy each
## frame so no enemy-side changes are needed.

const BAR_SIZE := Vector2(264, 16)
## Seconds the frame stays up (bar at 0) after the target dies or is lost, so
## one-hit kills are readable.
const LINGER_S := 0.8
const LINGER_MODULATE := Color(1, 1, 1, 0.75)

@onready var name_label: Label = $NameLabel
@onready var hp_bar: ProgressBar = $HPBar
@onready var hp_text: Label = $HPText
@onready var damage_label: Label = $DamageLabel

var target: Node2D = null
var linger_left := 0.0
var last_max_hp := 0
# True while a live enemy is being shown. A freed enemy compares equal to null,
# so this flag (not `target != null`) detects that the target has died.
var tracking := false

func _ready() -> void:
	# Godot resets a ProgressBar's scene-declared size during its internal
	# setup — reassign it here (same workaround as the unit frame).
	hp_bar.size = BAR_SIZE
	visible = false
	GameState.combat_target_changed.connect(_on_combat_target_changed)

func _on_combat_target_changed(new_target: Node2D) -> void:
	# Bosses get the big boss bar (BossEvents) instead of this frame.
	if is_instance_valid(new_target) and bool(new_target.call("is_boss")):
		target = null
		tracking = false
		visible = false
		return
	# is_instance_valid first: a freed Object compares equal to null.
	if is_instance_valid(new_target):
		target = new_target
		tracking = true
		linger_left = 0.0
		modulate = Color(1, 1, 1, 1)
		visible = true
		var elite_tag := " (Elite)" if target.guaranteed_drop_id != "" else ""
		name_label.text = "%s%s" % [target.enemy_name, elite_tag]
		damage_label.text = "%d - %d damage" % [target.attack_damage_min, target.attack_damage_max]
		_update_hp()
		return
	if visible:
		_start_linger()
	else:
		target = null
		tracking = false

func _process(delta: float) -> void:
	if is_instance_valid(target):
		_update_hp()
		return
	if tracking:
		# Enemy was freed while still our target (it died).
		_start_linger()
		return
	if linger_left > 0.0:
		linger_left -= delta
		if linger_left <= 0.0:
			linger_left = 0.0
			visible = false
			modulate = Color(1, 1, 1, 1)

func _start_linger() -> void:
	target = null
	tracking = false
	linger_left = LINGER_S
	hp_bar.value = 0
	hp_text.text = "0 / %d" % last_max_hp
	modulate = LINGER_MODULATE
	visible = true

func _update_hp() -> void:
	last_max_hp = int(target.max_hp)
	hp_bar.max_value = target.max_hp
	hp_bar.value = target.hp
	hp_text.text = "%d / %d" % [target.hp, target.max_hp]
