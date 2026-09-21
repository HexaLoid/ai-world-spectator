extends Control

@onready var hp_bar: ProgressBar = $HPBar
@onready var level_label: Label = $LevelLabel
@onready var xp_bar: ProgressBar = $XPBar
@onready var weapon_label: Label = $WeaponLabel
@onready var armor_label: Label = $ArmorLabel

func _ready() -> void:
	GameState.character_hp_changed.connect(_on_hp_changed)
	GameState.character_xp_changed.connect(_on_xp_changed)
	GameState.character_leveled_up.connect(_on_leveled_up)
	GameState.character_equipment_changed.connect(_on_equipment_changed)
	if GameState.character:
		_on_hp_changed(GameState.character.hp, GameState.character.max_hp)
		_on_leveled_up(GameState.character.level)
		_on_xp_changed(GameState.character.xp)
		_on_equipment_changed(GameState.character.equipped_weapon_id, GameState.character.equipped_armor_id)

func _on_hp_changed(hp: int, max_hp: int) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp

func _on_xp_changed(xp: int) -> void:
	var next_threshold: int = LevelingSystem.get_next_threshold(GameState.character.level) if GameState.character else -1
	if next_threshold <= 0:
		next_threshold = LevelingSystem.XP_THRESHOLDS[-1]
	xp_bar.max_value = next_threshold
	xp_bar.value = xp

func _on_leveled_up(level: int) -> void:
	level_label.text = "Level %d" % level

func _on_equipment_changed(weapon_id: String, armor_id: String) -> void:
	weapon_label.text = "Weapon: %s" % (weapon_id if weapon_id != "" else "None")
	armor_label.text = "Armor: %s" % (armor_id if armor_id != "" else "None")
