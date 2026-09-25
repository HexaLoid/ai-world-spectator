extends RefCounted

func run(t) -> void:
	var idle := CameraDirector.decide({"enabled": true, "manual": false, "in_boss_fight": false, "travelling": false, "boss_distance": 0.0})
	t.check(idle["active"], "idle: director active")
	t.check_near(idle["zoom"], 1.0, "idle zoom")
	t.check_near(idle["focus_weight"], 0.0, "idle: focus on the character")

	var boss := CameraDirector.decide({"enabled": true, "manual": false, "in_boss_fight": true, "travelling": false, "boss_distance": 100.0})
	t.check_near(boss["zoom"], 1.5, "boss zoom")
	t.check_near(boss["focus_weight"], 0.5, "close boss: midpoint")
	var far := CameraDirector.decide({"enabled": true, "manual": false, "in_boss_fight": true, "travelling": false, "boss_distance": 400.0})
	t.check_near(far["focus_weight"], 0.3, "far boss: character stays within 120 px of the focus")
	var overlap := CameraDirector.decide({"enabled": true, "manual": false, "in_boss_fight": true, "travelling": false, "boss_distance": 0.0})
	t.check_near(overlap["focus_weight"], 0.5, "boss at distance 0 does not divide by zero")

	var travel := CameraDirector.decide({"enabled": true, "manual": false, "in_boss_fight": false, "travelling": true, "boss_distance": 0.0})
	t.check_near(travel["zoom"], 0.8, "travel pull-out")
	t.check_near(travel["focus_weight"], 0.0, "travel: focus on the character")

	var both := CameraDirector.decide({"enabled": true, "manual": false, "in_boss_fight": true, "travelling": true, "boss_distance": 100.0})
	t.check_near(both["zoom"], 1.5, "boss framing wins over travel")

	var manual := CameraDirector.decide({"enabled": true, "manual": true, "in_boss_fight": true, "travelling": false, "boss_distance": 100.0})
	t.check(not manual["active"], "manual override pauses the director")
	var off := CameraDirector.decide({"enabled": false, "manual": false, "in_boss_fight": true, "travelling": false, "boss_distance": 100.0})
	t.check(not off["active"], "director toggled off")
	var defaults := CameraDirector.decide({})
	t.check(defaults["active"], "empty state: defaults to active")

	var in_range := true
	for dist in [0.0, 1.0, 50.0, 240.0, 500.0, 5000.0]:
		var w: float = CameraDirector.decide({"in_boss_fight": true, "boss_distance": dist})["focus_weight"]
		if w < 0.0 or w > 0.5:
			in_range = false
	t.check(in_range, "focus weight always within 0..0.5")
	t.done()
