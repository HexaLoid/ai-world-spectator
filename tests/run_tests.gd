extends SceneTree

## Headless test runner. Run with:
##   godot --headless --path . --script res://tests/run_tests.gd
## Each suite is a script with a `run(t)` method that calls `t.check(...)` /
## `t.check_eq(...)`. Exit code is 1 if any check fails. Every suite's
## `run(t)` must end with `t.done()`; a suite that ends early (e.g. a
## runtime script error) records a FAIL.

const SUITES := [
	"res://tests/suite_ability_table.gd",
	"res://tests/suite_loot_table.gd",
	"res://tests/suite_item_scoring.gd",
	"res://tests/suite_stat_calculator.gd",
	"res://tests/suite_sheet_text.gd",
	"res://tests/suite_name_table.gd",
	"res://tests/suite_chat_lines.gd",
	"res://tests/suite_chat_policy.gd",
	"res://tests/suite_leveling_system.gd",
	"res://tests/suite_enemy_table.gd",
	"res://tests/suite_spawn_points.gd",
	"res://tests/suite_zone_table.gd",
	"res://tests/suite_quest_table.gd",
	"res://tests/suite_codex_state.gd",
	"res://tests/suite_codex_data.gd",
	"res://tests/suite_codex_text.gd",
	"res://tests/suite_ai_decision.gd",
	"res://tests/suite_spectator_fx.gd",
	"res://tests/suite_camera_director.gd",
	"res://tests/suite_trait_table.gd",
	"res://tests/suite_journal.gd",
	"res://tests/suite_narrator_lines.gd",
	"res://tests/suite_recap_text.gd",
	"res://tests/suite_ability_math.gd",
	"res://tests/suite_job_table.gd",
	"res://tests/suite_job_state.gd",
	"res://tests/suite_job_switch.gd",
	"res://tests/suite_party_builder.gd",
	"res://tests/suite_threat_rules.gd",
	"res://tests/suite_encounter_logic.gd",
]

var checks := 0
var failures := 0
var suite_finished := false

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func check_eq(actual, expected, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])

func done() -> void:
	suite_finished = true

func check_near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])

func _init() -> void:
	for path in SUITES:
		print("Running ", path.get_file())
		var script = load(path)
		if script == null or not script.can_instantiate():
			check(false, "suite failed to load: " + path)
			continue
		var suite = script.new()
		suite_finished = false
		suite.run(self)
		check(suite_finished, "suite %s ended early (runtime error?)" % path.get_file())
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
