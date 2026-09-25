class_name CameraDirector
extends RefCounted

## Pure camera framing decision. `state` keys (all optional): enabled (bool,
## default true), manual (bool: the human took over), in_boss_fight (bool),
## travelling (bool), boss_distance (float px between character and boss).
## Returns {"active": bool, "zoom": float, "focus_weight": float}; the camera
## focuses on lerp(character, boss, focus_weight) and only applies `zoom`
## while `active`.

const DEFAULT_ZOOM := 1.0
const BOSS_ZOOM := 1.5
const TRAVEL_ZOOM := 0.8
## The character never sits further than this (world px) from the focus.
const MAX_OFFSET_PX := 120.0

static func decide(state: Dictionary) -> Dictionary:
	var active: bool = bool(state.get("enabled", true)) and not bool(state.get("manual", false))
	var zoom := DEFAULT_ZOOM
	var weight := 0.0
	if bool(state.get("in_boss_fight", false)):
		zoom = BOSS_ZOOM
		var dist := float(state.get("boss_distance", 0.0))
		weight = 0.5 if dist <= 0.0 else minf(0.5, MAX_OFFSET_PX / dist)
	elif bool(state.get("travelling", false)):
		zoom = TRAVEL_ZOOM
	return {"active": active, "zoom": zoom, "focus_weight": weight}
