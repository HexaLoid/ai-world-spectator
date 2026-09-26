class_name RecapText
extends RefCounted

## BBCode for the death recap card. `info` keys: name, trait_title,
## trait_remark, level, zone, killer, time_alive_s, kills, gold (all optional).
static func build(info: Dictionary) -> String:
	var character_name := String(info.get("name", ""))
	var trait_title := String(info.get("trait_title", ""))
	var who := ("%s %s" % [character_name, trait_title]).strip_edges()
	if who == "":
		who = "The hero"
	var killer := String(info.get("killer", ""))
	if killer == "":
		killer = "an unseen foe"
	var zone := String(info.get("zone", ""))
	var kills := int(info.get("kills", 0))
	var lines: Array[String] = []
	lines.append("[center][b]Fallen[/b][/center]")
	lines.append("[center]%s, level %d[/center]" % [who, int(info.get("level", 1))])
	var slain := "Slain by %s" % killer
	if zone != "":
		slain += " in %s" % zone
	lines.append("[center]%s[/center]" % slain)
	lines.append("[center]Survived %s  -  %d %s, %d gold[/center]" % [
		Journal.format_time(float(info.get("time_alive_s", 0.0)) * 1000.0),
		kills, "kill" if kills == 1 else "kills", int(info.get("gold", 0))])
	var remark := String(info.get("trait_remark", ""))
	if remark != "":
		lines.append("[center][i]%s[/i][/center]" % remark)
	return "\n".join(lines)
