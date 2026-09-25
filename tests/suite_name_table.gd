extends RefCounted

## The four simulated-player names placed in the world scenes.
const ALLY_NAMES := ["Kaelen", "Elowen", "Brynhild", "Gorrim", "Vesper", "Hrolf"]

func run(t) -> void:
	t.check(NameTable.NAMES.size() >= 8, "at least eight names")
	var seen := {}
	for n in NameTable.NAMES:
		t.check(String(n) != "", "name is non-empty")
		t.check(not seen.has(n), "name %s is unique" % n)
		seen[n] = true
		t.check(not ALLY_NAMES.has(n), "name %s does not collide with an ally" % n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 50:
		t.check(NameTable.NAMES.has(NameTable.pick(rng)), "pick returns a pool name")
	t.done()
