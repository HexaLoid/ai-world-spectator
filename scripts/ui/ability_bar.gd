extends HBoxContainer

## Builds one AbilitySlot per ability in the active character's class,
## instead of a fixed warrior-shaped set of slots — otherwise a second class
## with a different-sized kit (the mage has no gap-closer) would show empty
## or stale slots. Same "build children in code" pattern decoration_scatter.gd
## already uses for a similar reason (data-driven child count).
const ABILITY_SLOT_SCENE: PackedScene = preload("res://scenes/ui/AbilitySlot.tscn")

func _ready() -> void:
	if GameState.character == null:
		return
	_rebuild()
	GameState.job_changed.connect(func(_o, _n, _l): _rebuild())

func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var class_def: Dictionary = GameState.character.class_def
	for ability_id in class_def.get("abilities", []):
		var slot := ABILITY_SLOT_SCENE.instantiate()
		slot.ability_id = ability_id
		add_child(slot)
