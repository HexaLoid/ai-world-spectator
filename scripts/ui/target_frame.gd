extends Panel

## Shows the enemy the spectated character is fighting: name (with an Elite
## tag for guaranteed-drop enemies), HP bar with numbers, and damage range.
## Driven by GameState.combat_target_changed; HP is read from the enemy each
## frame so no enemy-side changes are needed.

const BAR_SIZE := Vector2(264, 16)

@onready var name_label: Label = $NameLabel
@onready var hp_bar: ProgressBar = $HPBar
@onready var hp_text: Label = $HPText
@onready var damage_label: Label = $DamageLabel

var target: Node2D = null

func _ready() -> void:
	# Godot resets a ProgressBar's scene-declared size during its internal
	# setup — reassign it here (same workaround as the unit frame).
	hp_bar.size = BAR_SIZE
	visible = false
	GameState.combat_target_changed.connect(_on_combat_target_changed)

func _on_combat_target_changed(new_target: Node2D) -> void:
	target = new_target
	visible = target != null
	if target == null:
		return
	var elite_tag := " (Elite)" if target.guaranteed_drop_id != "" else ""
	name_label.text = "%s%s" % [target.enemy_name, elite_tag]
	damage_label.text = "%d - %d damage" % [target.attack_damage_min, target.attack_damage_max]
	_update_hp()

func _process(_delta: float) -> void:
	# A freed enemy compares equal to null, so test is_instance_valid first
	# (a plain null check would return early and leave the frame showing).
	if not is_instance_valid(target):
		target = null
		visible = false
		return
	_update_hp()

func _update_hp() -> void:
	hp_bar.max_value = target.max_hp
	hp_bar.value = target.hp
	hp_text.text = "%d / %d" % [target.hp, target.max_hp]
