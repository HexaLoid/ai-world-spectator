class_name Journal
extends RefCounted

## The run's milestones, oldest first. Pure data (no nodes): the recorder adds
## entries, the journal panel displays them newest first.

var _entries: Array = []

func add(t_ms: float, kind: String, text: String) -> void:
	_entries.append({"t_ms": t_ms, "kind": kind, "text": text})

func entries() -> Array:
	return _entries.duplicate()

func count() -> int:
	return _entries.size()

## True when an entry with exactly this kind and text exists (used to keep
## "first visit" style entries unique).
func has_kind_text(kind: String, text: String) -> bool:
	for entry in _entries:
		if entry["kind"] == kind and entry["text"] == text:
			return true
	return false

## Minutes:seconds ("1:05") for a time in milliseconds; negatives clamp to 0.
static func format_time(t_ms: float) -> String:
	var total_seconds: int = maxi(0, floori(t_ms / 1000.0))
	return "%d:%02d" % [floori(float(total_seconds) / 60.0), total_seconds % 60]
