extends RefCounted

func run(t) -> void:
	# every chat event has a chance entry and every chance entry has templates
	for event in ChatLines.TEMPLATES:
		t.check(ChatPolicy.EVENT_CHANCE.has(event), "%s has a chance entry" % event)
	for event in ChatPolicy.EVENT_CHANCE:
		t.check(ChatLines.TEMPLATES.has(event), "%s (chance entry) has templates" % event)

	# should_fire boundaries
	t.check(ChatPolicy.should_fire("ally_joined", 0.999), "chance 1.0 fires for any roll below 1")
	t.check(ChatPolicy.should_fire("leader_low_hp", 0.0), "roll 0 always fires a known event")
	t.check(ChatPolicy.should_fire("leader_low_hp", 0.59), "roll just below 0.6 fires")
	t.check(not ChatPolicy.should_fire("leader_low_hp", 0.6), "roll equal to the chance does not fire")
	t.check(not ChatPolicy.should_fire("leader_low_hp", 0.95), "high roll does not fire")
	t.check(not ChatPolicy.should_fire("no_such_event", 0.0), "unknown events never fire")

	# can_speak
	var now := 100000.0
	t.check(ChatPolicy.can_speak("zone_arrive", now, now - 7000.0, now - 25000.0), "both cooldowns elapsed")
	t.check(not ChatPolicy.can_speak("zone_arrive", now, now - 3000.0, now - 25000.0), "global cooldown not elapsed")
	t.check(not ChatPolicy.can_speak("zone_arrive", now, now - 7000.0, now - 10000.0), "speaker cooldown not elapsed")
	t.check(ChatPolicy.can_speak("zone_arrive", now, now - ChatPolicy.GLOBAL_COOLDOWN_MS, now - ChatPolicy.SPEAKER_COOLDOWN_MS), "exactly at the cooldown is allowed")
	t.check(ChatPolicy.can_speak("ally_joined", now, now - 100.0, now - 100.0), "ally_joined bypasses both cooldowns")
	t.check(ChatPolicy.can_speak("zone_arrive", now, -1000000000.0, -1000000000.0), "a first-ever line is allowed")

	# ambient delay
	t.check_near(ChatPolicy.next_ambient_delay_ms(0.0), 30000.0, "ambient delay lower bound")
	t.check_near(ChatPolicy.next_ambient_delay_ms(1.0), 60000.0, "ambient delay upper bound")
	t.check_near(ChatPolicy.next_ambient_delay_ms(0.5), 45000.0, "ambient delay midpoint")
