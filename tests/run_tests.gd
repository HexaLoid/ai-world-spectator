extends SceneTree

## Headless test runner. Run with:
##   godot --headless --path . --script res://tests/run_tests.gd
## Each suite is a script with a `run(t)` method that calls `t.check(...)` /
## `t.check_eq(...)`. Exit code is 1 if any check fails.

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
]

var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func check_eq(actual, expected, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])

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
		suite.run(self)
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
