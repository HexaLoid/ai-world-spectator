extends Node2D

const FLOATING_TEXT_SCENE: PackedScene = preload("res://scenes/ui/FloatingText.tscn")

func _ready() -> void:
	GameState.damage_dealt.connect(_on_damage_dealt)
	GameState.hit_landed.connect(_on_hit_landed)
	add_child(HitFeedback.new())

# Heals still arrive through damage_dealt; damage numbers come from
# hit_landed, which knows about crits and boss fights.
func _on_damage_dealt(damage_position: Vector2, amount: int, is_heal: bool) -> void:
	if is_heal:
		_spawn_number(damage_position, amount, true, false, false, false)

func _on_hit_landed(target: Node2D, amount: int, is_crit: bool, on_character: bool) -> void:
	if not is_instance_valid(target):
		return
	_spawn_number(target.global_position, amount, false, is_crit, on_character, HitFeedback.is_boss_hit(target, on_character))

func _spawn_number(at: Vector2, amount: int, is_heal: bool, is_crit: bool, on_character: bool, is_boss_hit: bool) -> void:
	var floating_text := FLOATING_TEXT_SCENE.instantiate()
	floating_text.global_position = at
	floating_text.amount = amount
	floating_text.is_heal = is_heal
	floating_text.is_crit = is_crit
	floating_text.text_scale = SpectatorFx.number_scale(amount, is_crit, is_boss_hit)
	floating_text.text_color = SpectatorFx.number_color(is_heal, is_crit, on_character)
	add_child.call_deferred(floating_text)
