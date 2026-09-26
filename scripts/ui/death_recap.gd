class_name DeathRecap
extends Control

const HOLD_S := 2.5
const FADE_S := 0.6

var card: Panel
var text: RichTextLabel
var tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card = Panel.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -190.0
	card.offset_right = 190.0
	card.offset_top = -80.0
	card.offset_bottom = 80.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.05, 0.05, 0.94)
	style.border_color = Color(0.7, 0.2, 0.18, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", style)
	card.modulate.a = 0.0
	add_child(card)
	text = RichTextLabel.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.bbcode_enabled = true
	text.scroll_active = false
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.offset_left = 12.0
	text.offset_top = 10.0
	text.offset_right = -12.0
	text.offset_bottom = -10.0
	card.add_child(text)
	GameState.death_recap.connect(_on_death_recap)

func _on_death_recap(info: Dictionary) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	text.text = RecapText.build(info)
	card.modulate.a = 1.0
	tween = create_tween()
	tween.tween_interval(HOLD_S)
	tween.tween_property(card, "modulate:a", 0.0, FADE_S)
