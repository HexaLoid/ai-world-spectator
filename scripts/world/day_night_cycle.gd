extends CanvasModulate

## Multiplicatively tints everything drawn under Main's default canvas
## (world terrain, character, enemies) — NOT the HUD, which lives on its
## own CanvasLayer (SpectatorUI) and is unaffected by CanvasModulate, so
## it stays readable at any time of day. Purely cosmetic: nothing here
## reads or affects gameplay state.
##
## Uses accumulated `delta` (already scaled by Engine.time_scale, same as
## every other timer in this project) rather than wall-clock time, so the
## cycle speeds up/pauses with the speed controls like everything else.
const CYCLE_DURATION_MS := 360000.0

## [time_fraction (0-1), tint color] pairs, in order. The cycle lerps
## between consecutive keyframes and wraps from the last back to the first.
const KEYFRAMES: Array = [
	[0.0, Color(0.45, 0.45, 0.68, 1.0)],
	[0.06, Color(0.55, 0.5, 0.62, 1.0)],
	[0.15, Color(0.95, 0.78, 0.6, 1.0)],
	[0.25, Color(1.0, 1.0, 1.0, 1.0)],
	[0.65, Color(1.0, 1.0, 1.0, 1.0)],
	[0.78, Color(0.95, 0.62, 0.42, 1.0)],
	[0.88, Color(0.55, 0.48, 0.6, 1.0)],
	[1.0, Color(0.45, 0.45, 0.68, 1.0)],
]

var elapsed_ms: float = 0.0

func _process(delta: float) -> void:
	elapsed_ms += delta * 1000.0
	var t := fmod(elapsed_ms, CYCLE_DURATION_MS) / CYCLE_DURATION_MS
	color = _tint_at(t)

func _tint_at(t: float) -> Color:
	for i in range(KEYFRAMES.size() - 1):
		var a: Array = KEYFRAMES[i]
		var b: Array = KEYFRAMES[i + 1]
		if t >= a[0] and t <= b[0]:
			var span: float = b[0] - a[0]
			var local_t: float = (t - a[0]) / span if span > 0.0 else 0.0
			return a[1].lerp(b[1], local_t)
	return KEYFRAMES[0][1]
