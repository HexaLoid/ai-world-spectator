extends Panel

## Which AbilityTable.ABILITIES entry this slot displays; set per-instance
## in SpectatorUI.tscn (one slot per warrior ability, in rotation order).
@export var ability_id: String = ""

@onready var icon: TextureRect = $Icon
@onready var cooldown_bar: ProgressBar = $CooldownBar

var resource_cost: float = 0.0
const READY_COLOR := Color(1, 1, 1, 1)
const UNAVAILABLE_COLOR := Color(0.4, 0.4, 0.4, 1)

func _ready() -> void:
	var def: Dictionary = AbilityTable.ABILITIES.get(ability_id, {})
	var icon_path: String = def.get("icon", "")
	if icon_path != "":
		icon.texture = load(icon_path)
	resource_cost = float(def.get("resource_cost", 0.0))
	cooldown_bar.min_value = 0.0
	cooldown_bar.max_value = float(def.get("cooldown_ms", 1000)) / 1000.0
	cooldown_bar.show_percentage = false

func _process(_delta: float) -> void:
	var character := GameState.character
	if character == null or not is_instance_valid(character):
		return
	var remaining: float = character.get_ability_cooldown_remaining(ability_id)
	cooldown_bar.value = remaining
	cooldown_bar.visible = remaining > 0.0
	var affordable: bool = character.resource_amount >= resource_cost
	icon.modulate = READY_COLOR if (remaining <= 0.0 and affordable) else UNAVAILABLE_COLOR
