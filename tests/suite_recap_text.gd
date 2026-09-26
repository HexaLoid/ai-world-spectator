extends RefCounted

func _info() -> Dictionary:
	return {"name": "Aldric", "trait_title": "the Cautious", "trait_remark": "Perhaps a little more caution next time.",
		"level": 3, "zone": "Sundered Crypt", "killer": "Crypt Lord", "time_alive_s": 754.0, "kills": 21, "gold": 88}

func run(t) -> void:
	var text := RecapText.build(_info())
	t.check(text.contains("Fallen"), "title")
	t.check(text.contains("Aldric the Cautious"), "name and trait title")
	t.check(text.contains("level 3"), "level")
	t.check(text.contains("Crypt Lord"), "killer")
	t.check(text.contains("Sundered Crypt"), "zone")
	t.check(text.contains("12:34"), "time alive as m:ss")
	t.check(text.contains("21 kills"), "kills")
	t.check(text.contains("88 gold"), "gold")
	t.check(text.contains("Perhaps a little more caution next time."), "trait remark")

	var unknown := _info()
	unknown["killer"] = ""
	t.check(RecapText.build(unknown).contains("an unseen foe"), "empty killer reads as an unseen foe")

	var bare := RecapText.build({})
	t.check(bare.contains("Fallen") and not bare.contains("null"), "empty info still renders")
	var one := _info()
	one["kills"] = 1
	t.check(RecapText.build(one).contains("1 kill,") or RecapText.build(one).contains("1 kill "), "singular kill")
	t.done()
