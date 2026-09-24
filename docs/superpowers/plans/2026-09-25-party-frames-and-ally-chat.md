# Party Frames & Ally Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Party frames for the character's grouped allies, an in-character ally chat panel (`[Party]` / `[Zone]` channels) driven by game events with rate limiting, and a name for the spectated character.

**Architecture:** Pure, headless-tested rule classes (`NameTable`, `ChatLines`, `ChatPolicy`) plus thin nodes. Gameplay code emits a generic `GameState.chat_event(event, context)`; a `ChatDirector` node decides who speaks (using `ChatPolicy`/`ChatLines`) and emits `chat_message`, which a `ChatPanel` renders. `PartyFrames` rebuilds on `party_changed` and polls member HP each frame.

**Tech Stack:** Godot 4.7 (mono build, GDScript only), headless `--script` test runner.

**Spec:** `docs/superpowers/specs/2026-09-25-party-frames-and-ally-chat-design.md`

---

## Conventions used in every task

- Work in a dedicated git worktree/branch (e.g. `party-chat`). A fresh checkout needs **two** headless editor passes before scripts and textures resolve.
- Shell variable (bash on Windows):

```bash
GODOT="/c/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
```

- **Import pass** (registers new `class_name` scripts, writes `.gd.uid` sidecars). Run from the project root whenever a task adds a script, *before* running tests:

```bash
"$GODOT" --headless --path . --editor --quit
```

- **Run tests** (from the project root; `timeout` guards against a hung console exe):

```bash
timeout 90 "$GODOT" --headless --path . --script res://tests/run_tests.gd
```

  Exit code 0 = all pass; failures print lines starting `FAIL:`. A suite that fails to parse is reported as `FAIL: suite failed to load: ...`. The baseline before this plan is `919 checks, 0 failures`.
- Commit `.gd.uid` sidecars next to new scripts (repo convention). Do **not** commit Godot's line-ending-only rewrites of `.import` files, the `mcp_interaction_server` autoload line in `project.godot`, or `mcp_interaction_server.gd*`.
- Commit messages end with: `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`
- **Line endings:** many files are CRLF in the working tree (git normalizes to LF in commits). Preserve each file's existing line endings when editing (use Python with `newline=''`, inserting text with the file's own ending), and check `git diff --stat` shows only the lines you meant to change. New files may be LF.
- If an edit tool fails to match multi-line text, match on a single line without leading tabs, or use a small Python script.
- **Live checks** use the Godot MCP tools (`mcp__godot__run_project` with `projectPath` = the worktree, then `game_screenshot`, `game_get_errors`, `get_debug_output`, `game_click`, `game_key_press`, `game_eval`, `game_get_property`, `stop_project`). They may be deferred: load with ToolSearch `select:`. The `game_*` tools need several seconds after `run_project` to connect; retry. Window is 1152x648. Click the HUD `4x` button (~x=613,y=28) to speed up. `game_wait` returns immediately, so pace with repeated screenshots. `Engine.time_scale` can be set through `game_eval` (`Engine.time_scale = 0.3`) to catch short-lived UI. Only the MCP plugin's own warnings from `mcp_interaction_server.gd` are acceptable in `game_get_errors`. Never call `game_get_property` with an unknown property name (a bad name halts the game).

## File structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/systems/name_table.gd` | create | Name pool for the spectated character |
| `scripts/systems/chat_lines.gd` | create | Pure: event -> line templates, placeholder filling, BBCode formatting |
| `scripts/systems/chat_policy.gd` | create | Pure: cooldown / probability rules |
| `tests/suite_name_table.gd`, `tests/suite_chat_lines.gd`, `tests/suite_chat_policy.gd` | create | Unit tests |
| `tests/suite_sheet_text.gd`, `scripts/ui/sheet_text.gd` | modify | Character name line on the sheet |
| `tests/run_tests.gd` | modify | Register the new suites |
| `scripts/autoload/game_state.gd` | modify | `chat_event`, `chat_message`, `party_changed` signals |
| `scripts/entities/character.gd` | modify | Name, event emission, `party_changed` |
| `scripts/entities/simulated_player.gd` | modify | `ally_level_up`, `ally_died` events |
| `scripts/entities/enemy.gd` | modify | `elite_kill` event |
| `scripts/ui/chat_director.gd` | create | Decides who speaks and when |
| `scripts/ui/chat_panel.gd` | create | Renders chat lines |
| `scripts/ui/party_frames.gd` | create | Party frames |
| `scenes/ui/SpectatorUI.tscn` | modify | `ChatDirector`, `ChatPanel`, `PartyFrames` nodes |
| `README.md` | modify | HUD list |

---

### Task 1: `NameTable` and the sheet's name line

**Files:**
- Create: `scripts/systems/name_table.gd`, `tests/suite_name_table.gd`
- Modify: `tests/run_tests.gd`, `scripts/ui/sheet_text.gd`, `tests/suite_sheet_text.gd`

- [ ] **Step 1: Write the failing tests**

`tests/suite_name_table.gd`:

```gdscript
extends RefCounted

## The four simulated-player names placed in the world scenes.
const ALLY_NAMES := ["Kaelen", "Elowen", "Brynhild", "Gorrim"]

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
```

Add `"res://tests/suite_name_table.gd"` to `SUITES` in `tests/run_tests.gd`.

Append to the end of `run()` in `tests/suite_sheet_text.gd`:

```gdscript
	# character name line
	var named := _full_snapshot()
	named["character_name"] = "Aldric"
	t.check(SheetText.build(named).begins_with("[b]Aldric[/b]"), "sheet starts with the character's name")
	t.check(not SheetText.build(_full_snapshot()).contains("[b]Aldric[/b]"), "no name line without a name")
	t.check(SheetText.build({}).begins_with("[b]Level 1 Adventurer[/b]"), "empty snapshot still starts with the level line")
```

- [ ] **Step 2: Run tests to verify they fail**

Import pass, then tests. Expected: `FAIL: suite failed to load: res://tests/suite_name_table.gd` and a failing name-line check.

- [ ] **Step 3: Implement**

`scripts/systems/name_table.gd`:

```gdscript
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
```

In `scripts/ui/sheet_text.gd`, in `build()`, insert this directly after `var lines: Array[String] = []`:

```gdscript
	var character_name := String(snap.get("character_name", ""))
	if character_name != "":
		lines.append("[b]%s[/b]" % character_name)
```

- [ ] **Step 4: Run tests to verify they pass**

Import pass (new class + sidecars), then tests. Expected: `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/name_table.gd scripts/systems/name_table.gd.uid tests/suite_name_table.gd tests/suite_name_table.gd.uid tests/run_tests.gd tests/suite_sheet_text.gd scripts/ui/sheet_text.gd
git commit -m "Add NameTable and show the character's name on the sheet

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `ChatLines` and `ChatPolicy` (pure rules) with tests

**Files:**
- Create: `scripts/systems/chat_lines.gd`, `scripts/systems/chat_policy.gd`, `tests/suite_chat_lines.gd`, `tests/suite_chat_policy.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing suites**

`tests/suite_chat_lines.gd`:

```gdscript
extends RefCounted

const EVENTS := [
	"ally_joined", "ally_level_up", "ally_died", "elite_kill", "leader_level_up",
	"leader_loot", "zone_arrive", "leader_low_hp", "leader_died", "ambient",
]

func run(t) -> void:
	t.check_eq(ChatLines.TEMPLATES.size(), EVENTS.size(), "template table covers exactly the ten events")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var vars := {"leader": "Aldric", "ally": "Kaelen", "enemy": "Bandit Captain",
		"item": "Iron Helm", "zone": "Blackthorn Forest", "level": 4}
	for event in EVENTS:
		var templates: Array = ChatLines.TEMPLATES.get(event, [])
		t.check(templates.size() >= 3, "%s has at least three templates" % event)
		for template in templates:
			t.check(String(template) != "", "%s template is non-empty" % event)
		# Every template must resolve fully with a complete var set.
		for i in 40:
			var text := ChatLines.pick(event, rng, vars)
			t.check(text != "", "%s picks a non-empty line" % event)
			t.check(not text.contains("{") and not text.contains("}"), "%s line has no leftover placeholder: %s" % [event, text])

	# placeholder filling
	var joined := ChatLines.TEMPLATES["ally_joined"] as Array
	var found_leader := false
	for template in joined:
		if String(template).contains("{leader}"):
			found_leader = true
	t.check(found_leader, "ally_joined uses the {leader} placeholder somewhere")
	rng.seed = 1
	var levelup := ChatLines.pick("ally_level_up", rng, {"level": 7})
	t.check(levelup.contains("7"), "level is filled in (every ally_level_up template uses {level})")

	# missing vars become empty strings, never leftovers
	for i in 40:
		var partial := ChatLines.pick("elite_kill", rng, {})
		t.check(not partial.contains("{"), "missing vars leave no braces: %s" % partial)

	# unknown event
	t.check_eq(ChatLines.pick("no_such_event", rng, vars), "", "unknown event returns an empty string")

	# format()
	var party_line := ChatLines.format("party", "Kaelen", "Hello there")
	t.check(party_line.contains("[lb]Party[rb]"), "party tag")
	t.check(party_line.contains("[b]Kaelen[/b]: Hello there"), "bold speaker then text")
	t.check(party_line.contains("6fa8dc"), "party color")
	var zone_line := ChatLines.format("zone", "Gorrim", "Hi")
	t.check(zone_line.contains("[lb]Zone[rb]") and zone_line.contains("d9b382"), "zone tag and color")
	t.check(ChatLines.format("weird", "X", "y").contains("[lb]Zone[rb]"), "unknown channel falls back to the zone style")
```

`tests/suite_chat_policy.gd`:

```gdscript
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
```

Add `"res://tests/suite_chat_lines.gd"` and `"res://tests/suite_chat_policy.gd"` to `SUITES` in `tests/run_tests.gd`.

- [ ] **Step 2: Run tests to verify they fail**

Import pass, then tests. Expected: both suites report `FAIL: suite failed to load` (`ChatLines`/`ChatPolicy` not declared).

- [ ] **Step 3: Implement `ChatLines`**

`scripts/systems/chat_lines.gd`:

```gdscript
class_name ChatLines
extends RefCounted

## Pure chat text rules: which lines each game event can produce, how the
## placeholders are filled, and how a line is formatted for the chat panel.
## Placeholders: {leader} (the spectated character), {ally} (the speaker),
## {enemy}, {item}, {zone}, {level}.

const PLACEHOLDERS := ["leader", "ally", "enemy", "item", "zone", "level"]

const TEMPLATES := {
	"ally_joined": [
		"Hey {leader}, mind if I tag along?",
		"{leader}! Room in the party for one more?",
		"Well met, {leader}. Let's go hunting.",
		"Count me in, {leader}.",
	],
	"ally_level_up": [
		"Ding! Level {level}!",
		"Finally, level {level}.",
		"Level {level} at last, that took a while.",
		"Feeling stronger already. Level {level}!",
	],
	"ally_died": [
		"Ow. That one hurt.",
		"Back in a moment, I'm down!",
		"I did not see that coming...",
		"Ugh, respawning.",
	],
	"elite_kill": [
		"Nice kill on the {enemy}, {leader}!",
		"The {enemy} is down!",
		"Did you see that {enemy} go down?",
		"{enemy} defeated. Loot time!",
	],
	"leader_level_up": [
		"Grats on level {level}, {leader}!",
		"Level {level}, {leader}, well earned.",
		"Look at you, level {level}!",
		"Nice, {leader}. Level {level}!",
	],
	"leader_loot": [
		"Ooh, {item}! Nice find, {leader}.",
		"That {item} looks great on you.",
		"Lucky drop, {leader}. {item}!",
		"Envious of that {item}.",
	],
	"zone_arrive": [
		"{zone}. Stay sharp, everyone.",
		"So this is {zone}. Let's see what lives here.",
		"Welcome to {zone}, {leader}. Lead the way.",
		"New zone, new loot. {zone} it is.",
	],
	"leader_low_hp": [
		"{leader}, watch your health!",
		"You're hurting, {leader}. Back off a bit!",
		"Careful, {leader}, HP is low!",
		"{leader}, maybe rest before the next pull?",
	],
	"leader_died": [
		"Ouch, {leader} is down!",
		"Rough one, {leader}. Shake it off.",
		"We'll get them next time, {leader}.",
		"{leader}! Up you get.",
	],
	"ambient": [
		"Anyone seen the good loot around {zone}?",
		"Looking for a group in {zone}, anyone?",
		"{zone} is quiet today.",
		"I could really use a better weapon.",
		"Wolves everywhere in {zone}, watch out.",
		"Anyone else having trouble with the bandits?",
	],
}

## channel -> [tag text, hex color]
const CHANNELS := {
	"party": ["Party", "6fa8dc"],
	"zone": ["Zone", "d9b382"],
}

## Picks a template for `event` with `rng` and fills its placeholders from
## `vars` (missing vars become empty strings). Unknown events return "".
static func pick(event: String, rng: RandomNumberGenerator, vars: Dictionary) -> String:
	var templates: Array = TEMPLATES.get(event, [])
	if templates.is_empty():
		return ""
	var text: String = templates[rng.randi_range(0, templates.size() - 1)]
	for key in PLACEHOLDERS:
		text = text.replace("{%s}" % key, str(vars.get(key, "")))
	return text

## BBCode for one chat line. The tag brackets use [lb]/[rb] so a RichTextLabel
## shows them literally instead of parsing "[Party]" as a BBCode tag.
static func format(channel: String, speaker: String, text: String) -> String:
	var info: Array = CHANNELS.get(channel, CHANNELS["zone"])
	return "[color=#%s][lb]%s[rb][/color] [b]%s[/b]: %s" % [info[1], info[0], speaker, text]
```

- [ ] **Step 4: Implement `ChatPolicy`**

`scripts/systems/chat_policy.gd`:

```gdscript
class_name ChatPolicy
extends RefCounted

## Pure rate-limiting rules for ally chat. Times are game milliseconds.

const GLOBAL_COOLDOWN_MS := 6000.0
const SPEAKER_COOLDOWN_MS := 20000.0
const AMBIENT_MIN_MS := 30000.0
const AMBIENT_SPAN_MS := 30000.0

## Probability (0.0-1.0) that a given event produces a line at all.
const EVENT_CHANCE := {
	"ally_joined": 1.0,
	"leader_level_up": 0.9,
	"elite_kill": 0.9,
	"zone_arrive": 0.8,
	"leader_died": 0.8,
	"ally_level_up": 0.8,
	"leader_loot": 0.7,
	"leader_low_hp": 0.6,
	"ally_died": 0.5,
	"ambient": 1.0,
}

## Events that ignore the cooldowns (two allies join at the start and both greet).
const BYPASS_COOLDOWN_EVENTS := ["ally_joined"]

## True if a roll in [0, 1) should let `event` produce a line. Unknown events never fire.
static func should_fire(event: String, roll: float) -> bool:
	return roll < float(EVENT_CHANCE.get(event, 0.0))

## True if enough game time has passed since the last line overall and since
## this speaker last spoke (both are checked; the bypass events skip both).
static func can_speak(event: String, now_ms: float, last_global_ms: float, last_speaker_ms: float) -> bool:
	if BYPASS_COOLDOWN_EVENTS.has(event):
		return true
	return now_ms - last_global_ms >= GLOBAL_COOLDOWN_MS and now_ms - last_speaker_ms >= SPEAKER_COOLDOWN_MS

## Delay until the next ambient line for a roll in [0, 1]: 30-60 s.
static func next_ambient_delay_ms(roll: float) -> float:
	return AMBIENT_MIN_MS + roll * AMBIENT_SPAN_MS
```

- [ ] **Step 5: Run tests to verify they pass**

Import pass (two new classes + sidecars), then tests. Expected: `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/chat_lines.gd scripts/systems/chat_lines.gd.uid scripts/systems/chat_policy.gd scripts/systems/chat_policy.gd.uid tests/suite_chat_lines.gd tests/suite_chat_lines.gd.uid tests/suite_chat_policy.gd tests/suite_chat_policy.gd.uid tests/run_tests.gd
git commit -m "Add ChatLines and ChatPolicy: pure ally chat rules with tests

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Signals and event emission

**Files:**
- Modify: `scripts/autoload/game_state.gd`, `scripts/entities/character.gd`, `scripts/entities/simulated_player.gd`, `scripts/entities/enemy.gd`

Nothing consumes the new signals yet, so the game stays runnable; verify with tests, a smoke run and a short live check.

- [ ] **Step 1: Signals**

In `scripts/autoload/game_state.gd`, directly under the `signal zone_changed(zone_id: String)` line, add:

```gdscript
## Emitted by gameplay code at chat-worthy moments (an ally joins or levels up,
## the character levels up, an elite dies, ...). `event` is a key of
## ChatLines.TEMPLATES; `context` carries what the templates need (`ally`
## node, `enemy`, `item`, `zone`, `level`). The ChatDirector decides whether
## anyone actually speaks.
signal chat_event(event: String, context: Dictionary)
## Emitted by the ChatDirector when an ally says something; the chat panel
## renders it. `channel` is "party" or "zone".
signal chat_message(channel: String, speaker: String, text: String)
## Emitted when the character's party membership changes.
signal party_changed()
```

- [ ] **Step 2: Character**

Apply these edits to `scripts/entities/character.gd` (each anchor is a unique line; use Python with `newline=''` preserving CRLF):

1. Add fields directly under `var gold: int = 0`:
```gdscript
var character_name: String = ""
# True once the "low HP" chat line fired; re-armed when HP climbs back above 60%.
var low_hp_announced: bool = false
```
2. In `_ready()`, directly after the line `class_def = AbilityTable.CLASSES.get(character_class, {})`, add:
```gdscript
	character_name = NameTable.pick(rng)
```
3. In `_recruit_companions_in_zone`, replace the line `GameState.log_event("%s joins the group!" % sp.player_name)` with:
```gdscript
		GameState.log_event("%s joins the group!" % sp.player_name)
		GameState.emit_signal("party_changed")
		GameState.emit_signal("chat_event", "ally_joined", {"ally": sp})
```
   (indented with two tabs, same as the surrounding lines).
4. In `_sync_current_zone`, directly after `GameState.emit_signal("zone_changed", zone_id)`, add:
```gdscript
	GameState.emit_signal("chat_event", "zone_arrive", {"zone": String(ZoneTable.ZONES[zone_id]["name"])})
```
5. In `take_damage`, directly after the line `GameState.emit_signal("damage_dealt", global_position, amount, false)` add:
```gdscript
	var hp_fraction := float(hp) / float(max_hp)
	if hp > 0 and hp_fraction < 0.3 and not low_hp_announced:
		low_hp_announced = true
		GameState.emit_signal("chat_event", "leader_low_hp", {})
	elif hp_fraction > 0.6:
		low_hp_announced = false
```
6. In `_die`, directly after `deaths += 1`, add:
```gdscript
	GameState.emit_signal("chat_event", "leader_died", {})
```
7. In `gain_xp`, inside the `if result["leveled_up"]:` block, directly after the line `GameState.emit_signal("character_leveled_up", level)`, add:
```gdscript
		GameState.emit_signal("chat_event", "leader_level_up", {"level": level})
```
8. In `_acquire_item`, directly after the line `GameState.emit_signal("character_equipment_changed", equipment.duplicate())` add:
```gdscript
	if item_def.get("rarity", "") in ["rare", "epic"]:
		GameState.emit_signal("chat_event", "leader_loot", {"item": display_name})
```
9. In `get_sheet_snapshot()`, add `"character_name": character_name,` as the first entry of the returned dictionary (before `"level": level,`).

- [ ] **Step 3: SimulatedPlayer**

In `scripts/entities/simulated_player.gd`:
1. In `_die`, directly after `is_dead = true`, add:
```gdscript
	GameState.emit_signal("chat_event", "ally_died", {"ally": self})
```
2. In `take_kill_credit`, directly after the line `GameState.log_event("[Ally] %s levels up to %d!" % [player_name, level])` add:
```gdscript
		GameState.emit_signal("chat_event", "ally_level_up", {"ally": self, "level": level})
```

- [ ] **Step 4: Enemy**

In `scripts/entities/enemy.gd`, in `_die`, directly after `is_dead = true` (the first line), add:
```gdscript
	if guaranteed_drop_id != "":
		GameState.emit_signal("chat_event", "elite_kill", {"enemy": enemy_name})
```

- [ ] **Step 5: Verify**

Run the tests (expect `0 failures`), then the smoke run:

```bash
timeout 90 "$GODOT" --headless --path . --quit-after 1200 2>&1 | grep -i "SCRIPT ERROR\|Parse Error" ; echo "grep-exit=$?"
```

Expected: no matches (`grep-exit=1`). Then a short live check (Godot MCP): launch, 4x for ~1 minute, no errors in `game_get_errors`, and confirm `character_name` is set by reading it from the Character node (`/root/Main/Character`, property `character_name`; expect one of `NameTable.NAMES`) and that `get_sheet_snapshot` includes it. To prove the events fire, connect a listener through `game_eval`, for example:
```gdscript
var log := []
GameState.chat_event.connect(func(e, c): log.append(e))
get_node("/root/Main/Character").gain_xp(500)
return log
```
Expected: `log` contains `leader_level_up`. Stop the game.

- [ ] **Step 6: Commit**

```bash
git add scripts/autoload/game_state.gd scripts/entities/character.gd scripts/entities/simulated_player.gd scripts/entities/enemy.gd
git commit -m "Emit chat and party events; give the character a name

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: ChatDirector and chat panel

**Files:**
- Create: `scripts/ui/chat_director.gd`, `scripts/ui/chat_panel.gd`
- Modify: `scenes/ui/SpectatorUI.tscn`

- [ ] **Step 1: `ChatDirector`**

`scripts/ui/chat_director.gd`:

```gdscript
extends Node

## Decides who speaks and when. Gameplay code emits GameState.chat_event;
## this picks a speaker, applies ChatPolicy's probability and cooldowns, builds
## the text with ChatLines and emits GameState.chat_message. It also fires an
## occasional "ambient" zone line. All timing uses its own game clock, so it
## follows the speed control.

const NEVER_MS := -1000000000.0

var game_time_ms: float = 0.0
var last_global_ms: float = NEVER_MS
var last_spoke_ms: Dictionary = {}
var next_ambient_ms: float = 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	next_ambient_ms = ChatPolicy.next_ambient_delay_ms(rng.randf())
	GameState.chat_event.connect(_on_chat_event)
	# The character recruits its starting party in its own _ready, before this
	# node exists, so those greetings are replayed once everything is ready.
	_greet_existing_party.call_deferred()

func _process(delta: float) -> void:
	game_time_ms += delta * 1000.0
	if game_time_ms >= next_ambient_ms:
		next_ambient_ms = game_time_ms + ChatPolicy.next_ambient_delay_ms(rng.randf())
		_on_chat_event("ambient", {})

func _greet_existing_party() -> void:
	var leader = GameState.character
	if leader == null or not is_instance_valid(leader):
		return
	for member in leader.party:
		_on_chat_event("ally_joined", {"ally": member})

func _on_chat_event(event: String, context: Dictionary) -> void:
	if not ChatPolicy.should_fire(event, rng.randf()):
		return
	var leader = GameState.character
	if leader == null or not is_instance_valid(leader):
		return
	var speaker = _pick_speaker(event, context, leader)
	if speaker == null:
		return
	var speaker_name: String = speaker.player_name
	var last_speaker_ms := float(last_spoke_ms.get(speaker_name, NEVER_MS))
	if not ChatPolicy.can_speak(event, game_time_ms, last_global_ms, last_speaker_ms):
		return
	var zone_name := String(ZoneTable.ZONES[leader.current_zone_id]["name"])
	var text := ChatLines.pick(event, rng, {
		"leader": leader.character_name,
		"ally": speaker_name,
		"enemy": context.get("enemy", ""),
		"item": context.get("item", ""),
		"zone": context.get("zone", zone_name),
		"level": context.get("level", ""),
	})
	if text == "":
		return
	last_global_ms = game_time_ms
	last_spoke_ms[speaker_name] = game_time_ms
	GameState.emit_signal("chat_message", _channel_for(event, speaker), speaker_name, text)

## The ally who says the line, or null if nobody can.
func _pick_speaker(event: String, context: Dictionary, leader: Node2D) -> Node:
	match event:
		"ally_joined", "ally_level_up", "ally_died":
			var ally = context.get("ally", null)
			if ally != null and is_instance_valid(ally):
				return ally
			return null
		"ambient":
			var candidates: Array = []
			for sp in get_tree().get_nodes_in_group("simulated_players"):
				if is_instance_valid(sp) and sp.group_leader == null and not sp.is_dead \
						and sp.home_zone_id == leader.current_zone_id:
					candidates.append(sp)
			return _random_of(candidates)
		_:
			var living: Array = []
			for member in leader.party:
				if is_instance_valid(member) and not member.is_dead:
					living.append(member)
			return _random_of(living)

func _random_of(nodes: Array) -> Node:
	if nodes.is_empty():
		return null
	return nodes[rng.randi_range(0, nodes.size() - 1)]

func _channel_for(event: String, speaker: Node) -> String:
	if event == "ambient":
		return "zone"
	if event in ["ally_level_up", "ally_died"] and speaker.group_leader == null:
		return "zone"
	return "party"
```

- [ ] **Step 2: `ChatPanel`**

`scripts/ui/chat_panel.gd`:

```gdscript
extends Panel

## Renders GameState.chat_message lines (see ChatLines.format), newest at the
## bottom, trimmed to the last MAX_LINES.

const MAX_LINES := 60
const BODY_COLOR := Color(0.93, 0.88, 0.75, 1.0)

@onready var body: RichTextLabel = $Body

var line_count := 0

func _ready() -> void:
	# Dark panel (like the character sheet) so the channel colors stay readable.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.09, 0.05, 0.9)
	style.set_border_width_all(2)
	style.border_color = Color(0.55, 0.4, 0.15, 1.0)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	body.add_theme_color_override("default_color", BODY_COLOR)
	GameState.chat_message.connect(_on_chat_message)

func _on_chat_message(channel: String, speaker: String, text: String) -> void:
	if line_count >= MAX_LINES:
		body.remove_paragraph(0)
	else:
		line_count += 1
	body.append_text(ChatLines.format(channel, speaker, text) + "\n")
```

- [ ] **Step 3: Scene nodes**

In `scenes/ui/SpectatorUI.tscn` (Python with `newline=''`, using the file's line ending): read the current file, add two ext_resource lines after the existing ones (and bump `load_steps` by 2):

```
[ext_resource type="Script" path="res://scripts/ui/chat_director.gd" id="10_chatdirector"]
[ext_resource type="Script" path="res://scripts/ui/chat_panel.gd" id="11_chatpanel"]
```

and append at the end of the file:

```
[node name="ChatDirector" type="Node" parent="."]
script = ExtResource("10_chatdirector")

[node name="ChatPanel" type="Panel" parent="."]
theme = ExtResource("4_theme")
script = ExtResource("11_chatpanel")
position = Vector2(16, 270)
size = Vector2(320, 124)

[node name="Body" type="RichTextLabel" parent="ChatPanel"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = 8.0
offset_top = 6.0
offset_right = -8.0
offset_bottom = -6.0
theme_override_font_sizes/normal_font_size = 12
theme_override_font_sizes/bold_font_size = 12
bbcode_enabled = true
scroll_following = true
```

- [ ] **Step 4: Verify**

Import pass, tests (`0 failures`), then a live check via the Godot MCP tools: launch, wait until connected.
- At start the chat panel appears at the left between the unit frame and the activity log (x 16-336, y 270-394) with a dark background, and shortly after launch shows greeting lines such as `[Party] Kaelen: Hey <name>, mind if I tag along?` for each recruited ally (two lines).
- Line format: colored `[Party]` tag (blue), bold speaker name, text; no raw BBCode visible; the tag brackets show literally.
- At 4x for ~2 minutes: further lines appear (zone arrival, level-ups, ally level-ups/deaths, ambient `[Zone]` lines); it does not flood (no more than a line every few seconds); the panel auto-scrolls to the newest line; nothing overlaps the unit frame, log, quest tracker or ability bar.
- Force a couple of events with `game_eval` to check speakers/channels, for example `get_node("/root/Main/Character").gain_xp(300)` (expect a `[Party]` congratulation) and `GameState.emit_signal("chat_event", "elite_kill", {"enemy": "Bandit Captain"})` (may be skipped by probability/cooldowns; try again after a few seconds).
- `game_get_errors`: only the MCP plugin's warnings. Stop the game.

If something looks wrong (unreadable text, overlap, `remove_paragraph`/`scroll_following` not available in this build), fix within the plan's intent and report exactly what you changed.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/chat_director.gd scripts/ui/chat_director.gd.uid scripts/ui/chat_panel.gd scripts/ui/chat_panel.gd.uid scenes/ui/SpectatorUI.tscn
git commit -m "Add ally chat: director, policy-driven lines and a chat panel

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Party frames

**Files:**
- Create: `scripts/ui/party_frames.gd`
- Modify: `scenes/ui/SpectatorUI.tscn`

- [ ] **Step 1: Script**

`scripts/ui/party_frames.gd`:

```gdscript
extends VBoxContainer

## One compact frame per member of the character's party: name, level, HP bar
## with numbers; an ally that is down shows "Down" and is dimmed. Rebuilds on
## GameState.party_changed and polls each member every frame (like the target
## frame), so it needs no per-member signals.

const FRAME_SIZE := Vector2(224, 40)
const BAR_SIZE := Vector2(208, 12)
const DOWN_MODULATE := Color(1.0, 1.0, 1.0, 0.5)

# Each row: {"member": Node, "panel": Panel, "name": Label, "bar": ProgressBar, "text": Label}
var rows: Array = []

func _ready() -> void:
	add_theme_constant_override("separation", 6)
	GameState.party_changed.connect(_rebuild)
	_rebuild()

func _rebuild() -> void:
	for row in rows:
		row["panel"].queue_free()
	rows.clear()
	var leader = GameState.character
	if leader == null or not is_instance_valid(leader):
		return
	for member in leader.party:
		if is_instance_valid(member):
			rows.append(_make_row(member))

func _make_row(member: Node) -> Dictionary:
	var panel := Panel.new()
	panel.custom_minimum_size = FRAME_SIZE
	var name_label := Label.new()
	name_label.position = Vector2(8, 1)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = BAR_SIZE
	bar.position = Vector2(8, 22)
	bar.show_percentage = false
	var text := Label.new()
	text.position = Vector2(8, 22)
	text.size = BAR_SIZE
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_font_size_override("font_size", 10)
	text.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	text.add_theme_constant_override("outline_size", 4)
	panel.add_child(name_label)
	panel.add_child(bar)
	panel.add_child(text)
	add_child(panel)
	# Godot resets a ProgressBar's size during its setup, so reassign it once
	# it is in the tree (same workaround as the unit and target frames).
	bar.size = BAR_SIZE
	return {"member": member, "panel": panel, "name": name_label, "bar": bar, "text": text}

func _process(_delta: float) -> void:
	for row in rows:
		var member = row["member"]
		if not is_instance_valid(member):
			row["panel"].visible = false
			continue
		row["name"].text = "%s  Lv %d" % [member.player_name, member.level]
		var bar: ProgressBar = row["bar"]
		bar.max_value = member.max_hp
		bar.value = member.hp
		if member.is_dead:
			row["text"].text = "Down"
			row["panel"].modulate = DOWN_MODULATE
		else:
			row["text"].text = "%d / %d" % [member.hp, member.max_hp]
			row["panel"].modulate = Color(1, 1, 1, 1)
```

- [ ] **Step 2: Scene node**

In `scenes/ui/SpectatorUI.tscn` (Python with `newline=''`): add `[ext_resource type="Script" path="res://scripts/ui/party_frames.gd" id="12_partyframes"]` and bump `load_steps` by 1, then append at the end:

```
[node name="PartyFrames" type="VBoxContainer" parent="."]
theme = ExtResource("4_theme")
script = ExtResource("12_partyframes")
offset_left = 16.0
offset_top = 176.0
offset_right = 240.0
offset_bottom = 262.0
```

- [ ] **Step 3: Live check**

Import pass, tests, then launch via the Godot MCP tools:
- Under the unit frame (x 16-240, y 176-262) one frame appears per recruited ally (at start: two, e.g. Kaelen and Elowen) with name, `Lv 1`, a red HP bar 12 px tall with `hp / max` text centered on it; nothing overlaps the unit frame (ends y 170), the chat panel (starts y 270) or the activity log.
- At 4x the HP bars and `Lv` update during fights; when an ally dies, its frame dims and reads `Down`, then recovers on respawn (force with `game_eval`: call `_die()` on one of the members, found via `GameState.character.party[0]`; only if you do not catch a natural death).
- After the character travels to a new zone the party frames still match the party (members follow the character).
- `game_get_errors`: only the MCP plugin's warnings; no errors when an ally node is freed or respawns. Stop the game.

If the bar is inflated (taller than 12 px), the theme/size workaround needs adjusting; fix within the plan's intent and report exactly what you changed.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/party_frames.gd scripts/ui/party_frames.gd.uid scenes/ui/SpectatorUI.tscn
git commit -m "Add party frames for the character's grouped allies

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Final verification and docs

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README**

In the HUD bullet list (alongside the character sheet / target frame bullets) add, matching the existing style:

```markdown
  - Party frames for the character's grouped allies (name, level, HP)
  - An ally chat panel: allies greet, congratulate, warn and chat in `[Party]` and `[Zone]` channels
```

Also add a short sentence to the "What you'll see" section (or the equivalent) noting that the character has a name and that simulated players talk to it. Preserve line endings.

- [ ] **Step 2: Full run**

Run the tests (`0 failures`, count above 919). Then a ~3-minute live run at 4x with the Godot MCP tools. Check off with evidence: greeting lines at start; party frames present and updating; at least three distinct chat event types appear over the run (e.g. `zone_arrive`, `leader_level_up`, `ally_level_up`, `ambient`); lines never appear faster than the cooldowns allow (note timestamps/order); `[Zone]` ambient lines come only from allies who are not in the party; the character sheet's first line shows the character's name and chat lines use it (`{leader}`); the layout at 1152x648 shows unit frame, party frames, chat, activity log stacked on the left with no overlap, and the character sheet (`C`) still opens on the right without overlapping the new panels; no errors other than the MCP plugin's warnings. Report any real bug precisely (file, line, symptom); fix only if the fix is small and obviously correct.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Document party frames and ally chat

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Self-review notes (completed by the plan author)

- **Spec coverage:** character name + sheet line -> Task 1 (+ snapshot key in Task 3); `ChatLines`/`ChatPolicy` -> Task 2; the three signals and every event site in the spec's table (`ally_joined`, `ally_level_up`, `ally_died`, `elite_kill`, `leader_level_up`, `leader_loot` for rare/epic, `zone_arrive`, `leader_low_hp` edge-triggered at <30% re-armed >60%, `leader_died`) -> Task 3; `ambient` via the director's timer, speaker picking, channels, replay of the starting party's greetings -> Task 4; chat panel with 60-line trim -> Task 4; party frames with `Down` state and rebuild on `party_changed` -> Task 5; README + full run -> Task 6; tests for names, lines, policy and the sheet name line -> Tasks 1-2.
- **Deliberate implementation detail:** channel tags are formatted as `[lb]Party[rb]` (BBCode escapes) so a `RichTextLabel` shows literal `[Party]`; the spec's visual `[Party]` is unchanged.
- **Timing subtlety handled:** `Character._ready` recruits the starting party before the HUD nodes exist, so the director replays `ally_joined` for the existing party on a deferred call, and `PartyFrames` builds its rows from the current party in `_ready`.
- **Type/name consistency:** event names are identical in `ChatLines.TEMPLATES`, `ChatPolicy.EVENT_CHANCE`, the emit sites and `ChatDirector`; snapshot key `character_name`; signals `chat_event`, `chat_message`, `party_changed`.
