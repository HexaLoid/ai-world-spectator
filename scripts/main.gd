extends Node2D

const FLOATING_TEXT_SCENE: PackedScene = preload("res://scenes/ui/FloatingText.tscn")

func _ready() -> void:
	GameState.damage_dealt.connect(_on_damage_dealt)

func _on_damage_dealt(damage_position: Vector2, amount: int, is_heal: bool) -> void:
	var floating_text := FLOATING_TEXT_SCENE.instantiate()
	floating_text.global_position = damage_position
	floating_text.amount = amount
	floating_text.is_heal = is_heal
	add_child.call_deferred(floating_text)
