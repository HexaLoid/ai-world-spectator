extends Camera2D

const ZOOM_STEP := 0.1
const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.5
## Exponential smoothing rates (per second) for the directed camera.
const POS_SMOOTH := 6.0
const ZOOM_SMOOTH := 3.0
## Trauma lost per second; the shake offset is trauma^2 * SHAKE_MAX_PX.
const SHAKE_DECAY := 2.5
const SHAKE_MAX_PX := 14.0

var following := true
var dragging := false
var drag_start_mouse := Vector2.ZERO
var drag_start_camera := Vector2.ZERO
## The Director button toggles this; off = the camera behaves as it always did.
var director_enabled := true
## True once the human dragged or scrolled; pauses the director until Recenter.
var manual := false
var trauma := 0.0
var _last_ticks_ms := -1
var _zoom_reset_done := false
## Directed camera snaps instead of lerping beyond this distance (respawn/startup).
const SNAP_DISTANCE := 600.0

func _ready() -> void:
	GameState.camera = self
	GameState.hit_landed.connect(_on_hit_landed)

func _process(delta: float) -> void:
	var character = GameState.character
	var have_character: bool = character != null and is_instance_valid(character)
	var boss = null
	if have_character:
		boss = character.current_boss()
	var plan := CameraDirector.decide({
		"enabled": director_enabled,
		"manual": manual,
		"in_boss_fight": boss != null,
		"travelling": have_character and character.current_state == "travel",
		"boss_distance": character.global_position.distance_to(boss.global_position) if boss != null else 0.0,
	})
	var directed: bool = plan["active"] and GameState.fx_enabled
	if following and have_character:
		var target_position: Vector2 = character.global_position
		if directed:
			if boss != null:
				target_position = target_position.lerp(boss.global_position, plan["focus_weight"])
			global_position = global_position.lerp(target_position, 1.0 - exp(-POS_SMOOTH * delta))
		else:
			global_position = target_position
	if directed:
		var wanted: Vector2 = (Vector2.ONE * float(plan["zoom"])).clamp(Vector2.ONE * MIN_ZOOM, Vector2.ONE * MAX_ZOOM)
		zoom = zoom.lerp(wanted, 1.0 - exp(-ZOOM_SMOOTH * delta))
	if not director_enabled:
		# Director off behaves exactly as before the feature: snap zoom once, no shake.
		if not _zoom_reset_done:
			_zoom_reset_done = true
			zoom = Vector2.ONE
		trauma = 0.0
		offset = Vector2.ZERO
		return
	_zoom_reset_done = false
	# Shake decays in real time so pause / slow-mo neither freezes nor jitters it.
	var now := Time.get_ticks_msec()
	var real_dt := 0.0 if _last_ticks_ms < 0 else float(now - _last_ticks_ms) / 1000.0
	_last_ticks_ms = now
	trauma = maxf(0.0, trauma - SHAKE_DECAY * real_dt)
	if Engine.time_scale > 0.0:
		if GameState.fx_enabled and trauma > 0.0:
			offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * trauma * trauma * SHAKE_MAX_PX
		else:
			offset = Vector2.ZERO

func add_shake(strength: float) -> void:
	trauma = minf(1.0, trauma + strength)

func _on_hit_landed(target: Node2D, amount: int, is_crit: bool, on_character: bool) -> void:
	if not GameState.fx_enabled or not is_instance_valid(target):
		return
	var strength := SpectatorFx.shake_strength(amount, is_crit, on_character, HitFeedback.is_boss_hit(target, on_character), int(target.get("max_hp")))
	if strength > 0.0:
		add_shake(strength)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				following = false
				manual = true
				drag_start_mouse = event.position
				drag_start_camera = global_position
			else:
				dragging = false
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			manual = true
			zoom = (zoom + Vector2.ONE * ZOOM_STEP).clamp(Vector2.ONE * MIN_ZOOM, Vector2.ONE * MAX_ZOOM)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			manual = true
			zoom = (zoom - Vector2.ONE * ZOOM_STEP).clamp(Vector2.ONE * MIN_ZOOM, Vector2.ONE * MAX_ZOOM)
	elif event is InputEventMouseMotion and dragging:
		var mouse_motion := event as InputEventMouseMotion
		var delta_mouse := mouse_motion.position - drag_start_mouse
		global_position = drag_start_camera - delta_mouse / zoom

func recenter() -> void:
	following = true
	manual = false

## Returns the new state (true = director on).
func toggle_director() -> bool:
	director_enabled = not director_enabled
	if director_enabled:
		manual = false
		following = true
	return director_enabled
