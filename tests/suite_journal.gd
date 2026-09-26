extends RefCounted

func run(t) -> void:
	var j := Journal.new()
	t.check_eq(j.count(), 0, "new journal is empty")
	t.check_eq(j.entries(), [], "no entries")
	j.add(0.0, "start", "Set out from Thornfield Meadow")
	j.add(65000.0, "level", "Reached level 2")
	t.check_eq(j.count(), 2, "two entries")
	var entries := j.entries()
	t.check_eq(entries[0]["text"], "Set out from Thornfield Meadow", "insertion order")
	t.check_eq(entries[1]["kind"], "level", "kind kept")
	t.check_near(float(entries[1]["t_ms"]), 65000.0, "time kept")
	entries.clear()
	t.check_eq(j.count(), 2, "entries() returns a copy")
	t.check(j.has_kind_text("level", "Reached level 2"), "has_kind_text finds a match")
	t.check(not j.has_kind_text("level", "Reached level 3"), "has_kind_text: different text")
	t.check(not j.has_kind_text("zone", "Reached level 2"), "has_kind_text: different kind")

	t.check_eq(Journal.format_time(0.0), "0:00", "zero")
	t.check_eq(Journal.format_time(65000.0), "1:05", "65 seconds")
	t.check_eq(Journal.format_time(3725000.0), "62:05", "hours roll into minutes")
	t.check_eq(Journal.format_time(-5.0), "0:00", "negative clamps")
	t.done()
