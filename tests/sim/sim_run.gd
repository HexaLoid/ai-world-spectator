extends Node

## Balance-simulation bootstrap (test tooling only; never used by the game).
##
## Loads the real res://scenes/Main.tscn, forces the character's class,
## optionally seeds every entity RNG, attaches a SimMonitor that prints
## machine-readable `SIM|...` lines, and quits after a fixed amount of GAME
## time. Run headless, unthrottled, with a fixed frame step so a run is
## both fast and frame-rate independent:
##
##   godot --headless --path . --fixed-fps 60 res://tests/sim/SimRun.tscn -- class=warrior seed=3 minutes=25
##
## User args (after `--`), all optional:
##   class=warrior|mage   forced class (default: warrior)
##   seed=<int>           seeds every Character/Enemy/SimulatedPlayer RNG
##                        right after its own _ready() randomizes it (0 or
##                        absent = leave them random)
##   minutes=<float>      game minutes to simulate (default 25)
##   scale=<float>        Engine.time_scale (default 1.0; with --fixed-fps
##                        60 every physics step is then scale/60 s long)
##   snap=<float>         seconds of game time between snapshots (default 30)
##   trait=steady|cautious|reckless|greedy|explorer   forced trait (default: steady)
##   switching=0|1        hero changes job at the crystal (default 0 = off)
##   dungeon=0|1          the Hollowed Vault can be entered (default 0 = off)
##   trace=1              also print every damage/heal number (`dmg` lines)
##   watch=<enemy name>   also print that enemy's positions/HP with every snap
##
## Nothing in the game is modified: the class is set on the Character node
## before it enters the tree (exactly like a scene override of its
## `character_class` export), and seeding hooks each node's `ready` signal.

const MAIN_SCENE := "res://scenes/Main.tscn"
const SimMonitor := preload("res://tests/sim/sim_monitor.gd")

func _ready() -> void:
	GameState.fx_enabled = false
	GameState.select_screen_enabled = false
	var args := _parse_args()
	GameState.job_switching_enabled = args.get("switching", "0") == "1"
	GameState.dungeon_enabled = args.get("dungeon", "0") == "1"
	var character_class: String = args.get("class", "warrior")
	var seed_base := int(args.get("seed", "0"))
	var minutes := float(args.get("minutes", "25"))
	var time_scale := float(args.get("scale", "1"))
	var snap_s := float(args.get("snap", "30"))
	Engine.time_scale = time_scale
	# With a large time_scale, allow enough physics steps per frame that the
	# simulation never silently drops game time.
	Engine.max_physics_steps_per_frame = maxi(8, ceili(time_scale) * 2)
	var main: Node = load(MAIN_SCENE).instantiate()
	main.get_node("Character").character_class = character_class
	main.get_node("Character").character_trait = args.get("trait", "steady")
	var monitor: Node = SimMonitor.new()
	# The monitor (not this bootstrap node, which the scene change frees)
	# owns the seeding hook, and must be connected before Main enters the tree.
	if seed_base != 0:
		monitor.seed_base = seed_base
		get_tree().node_added.connect(monitor.on_node_added)
	monitor.name = "SimMonitor"
	monitor.duration_s = minutes * 60.0
	monitor.snap_interval_s = snap_s
	monitor.trace_damage = args.get("trace", "0") == "1"
	monitor.watch_enemy = args.get("watch", "")
	monitor.run_info = "class=%s|seed=%d|minutes=%s|scale=%s|trait=%s" % [character_class, seed_base, str(minutes), str(time_scale), str(args.get("trait", "steady"))]
	main.add_child(monitor)
	# Deferred: the tree is still busy adding this bootstrap scene.
	get_tree().change_scene_to_node.call_deferred(main)

func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		var parts := String(arg).split("=", true, 1)
		if parts.size() == 2:
			out[parts[0].strip_edges()] = parts[1].strip_edges()
	return out
