class_name BossEvents
extends Control

## Boss presentation: a name banner and a top-center health bar when the
## character targets a boss, a result banner (Victory / Defeated / Fled), and
## a brief slow-motion on a boss kill. Built in code, added to the UI by Main.

const HOLD_S := 1.6
const FADE_S := 0.6
const ENGAGED_COLOR := Color(1.0, 0.85, 0.3, 1.0)
const VICTORY_COLOR := Color(1.0, 0.9, 0.35, 1.0)
const DEFEATED_COLOR := Color(1.0, 0.35, 0.3, 1.0)
const FLED_COLOR := Color(0.75, 0.85, 1.0, 1.0)

var boss: Node2D = null
var tracking := false
## Boss instances already announced (a respawned boss is a new instance).
var announced := {}

var banner: Label
var bar_panel: Panel
var bar_name: Label
var bar: ProgressBar
var bar_text: Label
var banner_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	banner = Label.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.anchor_right = 1.0
	banner.offset_top = 216.0
	banner.offset_bottom = 266.0
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 34)
	banner.add_theme_constant_override("outline_size", 8)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	banner.modulate.a = 0.0
	add_child(banner)

	bar_panel = Panel.new()
	bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_panel.anchor_left = 0.5
	bar_panel.anchor_right = 0.5
	bar_panel.offset_left = -200.0
	bar_panel.offset_right = 200.0
	bar_panel.offset_top = 178.0
	bar_panel.offset_bottom = 208.0
	bar_panel.visible = false
	add_child(bar_panel)

	# Anchored (not sized) so ProgressBar does not reset its size on setup.
	bar = ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.offset_left = 4.0
	bar.offset_top = 4.0
	bar.offset_right = -4.0
	bar.offset_bottom = -4.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.75, 0.15, 0.12, 1.0)
	bar.add_theme_stylebox_override("fill", fill)
	bar_panel.add_child(bar)

	bar_name = Label.new()
	bar_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_name.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_name.offset_left = 10.0
	bar_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_name.add_theme_font_size_override("font_size", 13)
	bar_panel.add_child(bar_name)

	bar_text = Label.new()
	bar_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_text.offset_right = -10.0
	bar_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_text.add_theme_font_size_override("font_size", 13)
	bar_panel.add_child(bar_text)

	GameState.combat_target_changed.connect(_on_target_changed)
	GameState.boss_event.connect(_on_boss_event)

func _process(_delta: float) -> void:
	var character = GameState.character
	var current = null
	if character != null and is_instance_valid(character):
		current = character.current_boss()
	if current == null:
		if tracking:
			_stop_tracking()
		return
	if current != boss or not tracking:
		boss = current
		tracking = true
		bar.max_value = float(boss.get("max_hp"))
		bar_name.text = String(boss.get("enemy_name"))
		bar_panel.visible = true
	bar.value = float(boss.get("hp"))
	bar_text.text = "%d / %d" % [int(boss.get("hp")), int(boss.get("max_hp"))]

## Announces a boss the first time it is targeted. The bar itself is driven by
## polling in _process so a momentary null target (chase state) cannot flicker it.
func _on_target_changed(target: Node2D) -> void:
	# is_instance_valid first: a freed Object compares equal to null.
	if is_instance_valid(target) and target.has_method("is_boss") and bool(target.call("is_boss")):
		var id := target.get_instance_id()
		if not announced.has(id):
			announced[id] = true
			_show_banner("BOSS - %s" % String(target.get("enemy_name")), ENGAGED_COLOR)

func _stop_tracking() -> void:
	tracking = false
	boss = null
	bar_panel.visible = false

func _on_boss_event(kind: String, boss_name: String) -> void:
	match kind:
		"victory":
			_show_banner("VICTORY - %s" % boss_name, VICTORY_COLOR)
			_slow_motion()
		"defeated":
			_show_banner("DEFEATED by %s" % boss_name, DEFEATED_COLOR)
		"fled":
			_show_banner("Fled from %s" % boss_name, FLED_COLOR)

func _show_banner(text: String, color: Color) -> void:
	if banner_tween != null and banner_tween.is_valid():
		banner_tween.kill()
	banner.text = text
	banner.modulate = color
	banner_tween = create_tween()
	banner_tween.tween_interval(HOLD_S)
	banner_tween.tween_property(banner, "modulate:a", 0.0, FADE_S)

var slow_active := false

func _exit_tree() -> void:
	if slow_active:
		slow_active = false
		Engine.time_scale = GameState.user_time_scale

func _slow_motion() -> void:
	if not GameState.fx_enabled or not SpectatorFx.should_slow_kill(true, Engine.time_scale):
		return
	Engine.time_scale = SpectatorFx.SLOW_SCALE
	slow_active = true
	# process_always = true, process_in_physics = false, ignore_time_scale = true
	await get_tree().create_timer(SpectatorFx.SLOW_DURATION_S, true, false, true).timeout
	if is_instance_valid(self) and slow_active:
		slow_active = false
		Engine.time_scale = GameState.user_time_scale
