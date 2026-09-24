class_name NameTable
extends RefCounted

## Names for the spectated character, so allies can address it in chat. None
## of these may collide with the simulated players' names (Kaelen, Elowen,
## Brynhild, Gorrim) — enforced by tests/suite_name_table.gd.
const NAMES := [
	"Aldric", "Seraphine", "Thorne", "Marisol", "Dunstan", "Isolde",
	"Corwin", "Lyra", "Bram", "Petra", "Osric", "Nyla",
]

static func pick(rng: RandomNumberGenerator) -> String:
	return NAMES[rng.randi_range(0, NAMES.size() - 1)]
