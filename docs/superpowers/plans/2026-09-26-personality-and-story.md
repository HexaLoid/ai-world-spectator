# Personality and Story Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the character a rolled personality trait that changes its decisions, a narrator that tells the story in a Story chat channel, a death recap card, and a journal panel of milestones.

**Architecture:** Pure static/data helpers (`TraitTable`, `NarratorLines`, `Journal`, `RecapText`) hold all decisions and are unit-tested headless. `AIDecision` takes optional trait thresholds through its existing context dictionary. `Character` gains the trait, a few new `GameState` signals, and small emissions at places that already fire events. Four small scene-side nodes (`JournalRecorder`, `NarratorDirector`, `DeathRecap`, `JournalPanel`) consume the signals and are attached from `main.gd` in code (no `.tscn` edits).

**Tech Stack:** Godot 4.7 (mono) GDScript, headless test runner `tests/run_tests.gd`, `tests/sim` balance harness.

Spec: `docs/superpowers/specs/2026-09-26-personality-and-story-design.md`.

**Deviations from the spec (decided while planning, all small)**

- The trait title is appended to the *name line* of the character sheet (`Aldric the Cautious`); the `Level N Class - Zone` line is unchanged.
- One new pure key `remark` per trait (a one-line death remark) lives in `TraitTable`.
- Boss-first-sight uses a new `boss_event` kind `"engaged"` (emitted once per boss instance by `Character`); `BossEvents` already ignores unknown kinds. Journal/narrator use `boss_event`, `zone_changed`, `character_leveled_up` plus three new signals (`item_acquired`, `quest_completed`, `death_recap`) instead of hooks inside `Enemy`.
- The sim harness defaults to `trait=steady` (not a random trait) because the game seeds the character's `rng` after `_ready`; a forced Steady keeps old seeded logs comparable.

**Conventions for every task**

- Run in a worktree: from `main`, `git worktree add .claude/worktrees/personality-story -b personality-story`. In the fresh worktree run the headless editor import twice: `"$GODOT" --headless --path . --editor --quit` (twice), and once more after creating new `class_name` scripts (the test runner needs the class cache; commit the generated `.gd.uid` files for new scripts, the repo tracks them).
- `GODOT="C:/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"`.
- "Run the tests" means: `"$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1 | grep -E "FAIL|SCRIPT ERROR|checks"`. Baseline: `12198 checks, 0 failures`.
- Every suite's `run(t)` ends with `t.done()`. Register new suites in `SUITES` in `tests/run_tests.gd`.
- Working tree is CRLF, commits are LF: use the Edit tool for existing files (or Python with `newline=''`).
- Never stage `assets/**/*.import`, `docs/screenshots/*.import` or `project.godot` (editor noise).
- Commit messages end with `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- GDScript typing quirk: calling members that are not on the declared type (`Node2D`) is a parse error; use untyped `var x = ...`, `.call("m")`, `.get("prop")`. Guard `get_meta` with `has_meta`. Do not use integer `/` division (warning); use `floori(float(a) / float(b))`.

---

### Task 1: `TraitTable`

**Files:**
- Create: `scripts/systems/trait_table.gd`
- Create: `tests/suite_trait_table.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/suite_trait_table.gd`:

```gdscript
extends RefCounted

const KEYS := ["title", "flee_hp", "rest_hp", "item_range_mult", "stay_mult", "blurb", "remark"]

func run(t) -> void:
	t.check_eq(TraitTable.ORDER, ["steady", "cautious", "reckless", "greedy", "explorer"], "trait order")
	t.check_eq(TraitTable.ids().size(), 5, "five traits")
	for id in TraitTable.ids():
		var def := TraitTable.get_def(id)
		for key in KEYS:
			t.check(def.has(key), "%s has %s" % [id, key])
		t.check(float(def["flee_hp"]) < float(def["rest_hp"]), "%s: flee below rest" % id)
		t.check(float(def["flee_hp"]) > 0.0 and float(def["rest_hp"]) < 1.0, "%s: thresholds in (0, 1)" % id)
		t.check(float(def["item_range_mult"]) >= 1.0, "%s: item range never shrinks" % id)
		t.check(float(def["stay_mult"]) > 0.0 and float(def["stay_mult"]) <= 1.0, "%s: stay multiplier in (0, 1]" % id)
		t.check(String(def["title"]).begins_with("the "), "%s: title reads 'the X'" % id)
		t.check_eq(TraitTable.title_of(id), def["title"], "%s: title_of" % id)

	# Steady is exactly today's behavior
	var steady := TraitTable.get_def("steady")
	t.check_near(float(steady["flee_hp"]), AIDecision.FLEE_HP_THRESHOLD, "steady flee threshold is the default")
	t.check_near(float(steady["rest_hp"]), AIDecision.REST_HP_THRESHOLD, "steady rest threshold is the default")
	t.check_near(float(steady["item_range_mult"]), 1.0, "steady item range")
	t.check_near(float(steady["stay_mult"]), 1.0, "steady stay")

	# the spec's numbers
	t.check_near(float(TraitTable.get_def("cautious")["flee_hp"]), 0.25, "cautious flees at 25%")
	t.check_near(float(TraitTable.get_def("cautious")["rest_hp"]), 0.45, "cautious rests below 45%")
	t.check_near(float(TraitTable.get_def("reckless")["flee_hp"]), 0.05, "reckless flees at 5%")
	t.check_near(float(TraitTable.get_def("reckless")["rest_hp"]), 0.20, "reckless rests below 20%")
	t.check_near(float(TraitTable.get_def("greedy")["item_range_mult"]), 1.6, "greedy notices loot from 1.6x")
	t.check_near(float(TraitTable.get_def("explorer")["stay_mult"]), 0.7, "explorer stays 30% shorter")

	# unknown ids
	t.check(TraitTable.get_def("nope").is_empty(), "unknown trait: empty def")
	t.check_eq(TraitTable.title_of("nope"), "", "unknown trait: empty title")

	# pick(): deterministic for a seeded rng, covers every trait
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 42
	b.seed = 42
	var seen := {}
	var same := true
	for i in range(300):
		var pa := TraitTable.pick(a)
		if pa != TraitTable.pick(b):
			same = false
		seen[pa] = true
	t.check(same, "pick is deterministic for the same seed")
	t.check_eq(seen.size(), 5, "300 draws cover every trait")
	t.done()
```

Register `"res://tests/suite_trait_table.gd",` in `tests/run_tests.gd` after the `suite_spectator_fx.gd`/`suite_camera_director.gd` lines (end of `SUITES`).

- [ ] **Step 2: Run the tests to verify they fail**

Run the tests. Expected: SCRIPT ERROR / suite failed to load for `TraitTable`.

- [ ] **Step 3: Implement**

Create `scripts/systems/trait_table.gd`:

```gdscript
class_name TraitTable
extends RefCounted

## Personality traits: one is rolled per character and changes real decisions
## (via AIDecision's optional thresholds and two Character multipliers) and
## the narration. Steady is exactly the pre-trait behavior.
##   flee_hp / rest_hp   HP fractions for AIDecision (flee < rest)
##   item_range_mult     multiplier on the distance at which loot is noticed
##   stay_mult           multiplier on how long the character stays in a zone
const ORDER := ["steady", "cautious", "reckless", "greedy", "explorer"]

const TRAITS := {
	"steady": {
		"title": "the Steady", "flee_hp": AIDecision.FLEE_HP_THRESHOLD, "rest_hp": AIDecision.REST_HP_THRESHOLD,
		"item_range_mult": 1.0, "stay_mult": 1.0,
		"blurb": "Even-tempered. Fights, rests and travels by the book.",
		"remark": "Steady on. Try again.",
	},
	"cautious": {
		"title": "the Cautious", "flee_hp": 0.25, "rest_hp": 0.45,
		"item_range_mult": 1.0, "stay_mult": 1.0,
		"blurb": "Retreats early and rests often. Rarely dies, but loses time.",
		"remark": "Perhaps a little more caution next time.",
	},
	"reckless": {
		"title": "the Reckless", "flee_hp": 0.05, "rest_hp": 0.20,
		"item_range_mult": 1.0, "stay_mult": 1.0,
		"blurb": "Fights to the last breath. Fast, and often fatal.",
		"remark": "Bold to the very end.",
	},
	"greedy": {
		"title": "the Greedy", "flee_hp": AIDecision.FLEE_HP_THRESHOLD, "rest_hp": AIDecision.REST_HP_THRESHOLD,
		"item_range_mult": 1.6, "stay_mult": 1.0,
		"blurb": "Spots loot from far away and never leaves a drop behind.",
		"remark": "The loot was not worth it.",
	},
	"explorer": {
		"title": "the Explorer", "flee_hp": AIDecision.FLEE_HP_THRESHOLD, "rest_hp": AIDecision.REST_HP_THRESHOLD,
		"item_range_mult": 1.0, "stay_mult": 0.7,
		"blurb": "Restless. Moves on to the next zone sooner.",
		"remark": "There is always another road.",
	},
}

static func ids() -> Array:
	return ORDER.duplicate()

static func get_def(id: String) -> Dictionary:
	return TRAITS.get(id, {})

static func title_of(id: String) -> String:
	return String(get_def(id).get("title", ""))

static func pick(rng: RandomNumberGenerator) -> String:
	return ORDER[rng.randi_range(0, ORDER.size() - 1)]
```

- [ ] **Step 4: Import and run the tests**

Run the headless editor import once (new `class_name`), then run the tests. Expected `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/trait_table.gd scripts/systems/trait_table.gd.uid tests/suite_trait_table.gd tests/suite_trait_table.gd.uid tests/run_tests.gd
git commit -m "Add TraitTable personality traits

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `AIDecision` optional trait thresholds

**Files:**
- Modify: `scripts/ai/ai_decision.gd`
- Modify: `tests/suite_ai_decision.gd`

- [ ] **Step 1: Write the failing test**

In `tests/suite_ai_decision.gd`, before the final `t.done()` add:

```gdscript
	# trait thresholds (optional context keys flee_hp / rest_hp)
	var cautious := _ctx(0.2, true, true)
	t.check_eq(AIDecision.resolve_state(cautious)["state"], "combat", "20% HP, default thresholds: keeps fighting")
	cautious["flee_hp"] = 0.25
	cautious["rest_hp"] = 0.45
	t.check_eq(AIDecision.resolve_state(cautious)["state"], "flee", "20% HP, cautious: flees")
	var cautious_rest := _ctx(0.4, false)
	cautious_rest["flee_hp"] = 0.25
	cautious_rest["rest_hp"] = 0.45
	t.check_eq(AIDecision.resolve_state(cautious_rest)["state"], "rest", "40% HP, cautious, nothing near: rests")
	t.check_eq(AIDecision.resolve_state(_ctx(0.4, false))["state"], "wander", "40% HP, default: wanders")
	var reckless := _ctx(0.08, true, true)
	t.check_eq(AIDecision.resolve_state(reckless)["state"], "flee", "8% HP, default: flees")
	reckless["flee_hp"] = 0.05
	reckless["rest_hp"] = 0.20
	t.check_eq(AIDecision.resolve_state(reckless)["state"], "combat", "8% HP, reckless: keeps fighting")
	var reckless_low := _ctx(0.04, true, true)
	reckless_low["flee_hp"] = 0.05
	reckless_low["rest_hp"] = 0.20
	t.check_eq(AIDecision.resolve_state(reckless_low)["state"], "flee", "4% HP, reckless: finally flees")
```

- [ ] **Step 2: Run the tests to verify they fail**

Expected: FAIL on "20% HP, cautious: flees" (thresholds ignored).

- [ ] **Step 3: Implement**

In `scripts/ai/ai_decision.gd`, extend the header comment of `resolve_state` to add `flee_hp` and `rest_hp` (optional floats, default the constants above) to the expected keys, then near the other `context.get` lines add:

```gdscript
	var flee_hp: float = float(context.get("flee_hp", FLEE_HP_THRESHOLD))
	var rest_hp: float = float(context.get("rest_hp", REST_HP_THRESHOLD))
```

and change the two threshold conditions to use them:

```gdscript
	if hp_percent < flee_hp and hostile_in_aggro_range:
		return {"state": "flee", "reason": "HP low (%d%%) - fleeing from %s" % [round(hp_percent * 100), hostile_name]}
	if hp_percent < rest_hp and not hostile_in_aggro_range:
		return {"state": "rest", "reason": "HP low (%d%%) - resting to recover" % round(hp_percent * 100)}
```

- [ ] **Step 4: Run the tests to verify they pass**

Expected `0 failures` (existing AI tests unchanged).

- [ ] **Step 5: Commit**

```bash
git add scripts/ai/ai_decision.gd tests/suite_ai_decision.gd
git commit -m "AIDecision: optional per-character flee and rest thresholds

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: `Journal`

**Files:**
- Create: `scripts/systems/journal.gd`
- Create: `tests/suite_journal.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/suite_journal.gd`:

```gdscript
extends RefCounted

func run(t) -> void:
	var j := Journal.new()
	t.check_eq(j.count(), 0, "new journal is empty")
	t.check_eq(j.entries(), [], "no entries")
	j.add(0.0, "start", "Set out from Thornfield Meadow")
	j.add(65000.0, "level", "Reached level 2")
	t.check_eq(j.count(), 2, "two entries")
	var entries := j.entries()
	t.check_eq(entries[0]["text"], "Set out from Thornfield Meadow", "insertion order")
	t.check_eq(entries[1]["kind"], "level", "kind kept")
	t.check_near(float(entries[1]["t_ms"]), 65000.0, "time kept")
	entries.clear()
	t.check_eq(j.count(), 2, "entries() returns a copy")
	t.check(j.has_kind_text("level", "Reached level 2"), "has_kind_text finds a match")
	t.check(not j.has_kind_text("level", "Reached level 3"), "has_kind_text: different text")
	t.check(not j.has_kind_text("zone", "Reached level 2"), "has_kind_text: different kind")

	t.check_eq(Journal.format_time(0.0), "0:00", "zero")
	t.check_eq(Journal.format_time(65000.0), "1:05", "65 seconds")
	t.check_eq(Journal.format_time(3725000.0), "62:05", "hours roll into minutes")
	t.check_eq(Journal.format_time(-5.0), "0:00", "negative clamps")
	t.done()
```

Register `"res://tests/suite_journal.gd",` in `tests/run_tests.gd`.

- [ ] **Step 2: Run the tests to verify they fail**

Expected: SCRIPT ERROR for `Journal`.

- [ ] **Step 3: Implement**

Create `scripts/systems/journal.gd`:

```gdscript
class_name Journal
extends RefCounted

## The run's milestones, oldest first. Pure data (no nodes): the recorder adds
## entries, the journal panel displays them newest first.

var _entries: Array = []

func add(t_ms: float, kind: String, text: String) -> void:
	_entries.append({"t_ms": t_ms, "kind": kind, "text": text})

func entries() -> Array:
	return _entries.duplicate()

func count() -> int:
	return _entries.size()

## True when an entry with exactly this kind and text exists (used to keep
## "first visit" style entries unique).
func has_kind_text(kind: String, text: String) -> bool:
	for entry in _entries:
		if entry["kind"] == kind and entry["text"] == text:
			return true
	return false

## Minutes:seconds ("1:05") for a time in milliseconds; negatives clamp to 0.
static func format_time(t_ms: float) -> String:
	var total_seconds: int = maxi(0, floori(t_ms / 1000.0))
	return "%d:%02d" % [floori(float(total_seconds) / 60.0), total_seconds % 60]
```

- [ ] **Step 4: Import and run the tests**

Import once, then run the tests. Expected `0 failures`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/journal.gd scripts/systems/journal.gd.uid tests/suite_journal.gd tests/suite_journal.gd.uid tests/run_tests.gd
git commit -m "Add Journal milestone list

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: `NarratorLines` and the Story chat channel

**Files:**
- Create: `scripts/systems/narrator_lines.gd`
- Create: `tests/suite_narrator_lines.gd`
- Modify: `scripts/systems/chat_lines.gd` (`CHANNELS`)
- Modify: `tests/suite_chat_lines.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/suite_narrator_lines.gd`:

```gdscript
extends RefCounted

const CONTEXT := {"name": "Aldric", "zone": "Mirewater Swamp", "boss": "the Crypt Lord", "level": 5, "item": "Frostbrand", "killer": "the Crypt Lord", "quest": "Cull the Wolves"}
const ROLLS := [0.0, 0.3, 0.59, 0.6, 0.85, 0.999]

func run(t) -> void:
	t.check_eq(NarratorLines.EVENTS.size(), 10, "ten narrated events")
	for event in NarratorLines.EVENTS:
		for trait_id in TraitTable.ids():
			for roll in ROLLS:
				var line := NarratorLines.line_for(event, trait_id, CONTEXT, roll)
				var label := "%s/%s/%s" % [event, trait_id, str(roll)]
				t.check(line != "", "%s: non-empty" % label)
				t.check(not line.contains("{") and not line.contains("}"), "%s: no unresolved placeholder" % label)
				t.check(not line.contains("[") and not line.contains("%"), "%s: no BBCode or format characters" % label)
	t.check_eq(NarratorLines.line_for("nope", "steady", CONTEXT, 0.1), "", "unknown event: empty")
	t.check_eq(NarratorLines.line_for("level_up", "steady", CONTEXT, 0.4), NarratorLines.line_for("level_up", "steady", CONTEXT, 0.4), "deterministic")

	# placeholders are filled from the context
	t.check(NarratorLines.line_for("zone_arrive", "steady", CONTEXT, 0.1).contains("Mirewater Swamp"), "zone line names the zone")
	t.check(NarratorLines.line_for("boss_engaged", "steady", CONTEXT, 0.1).contains("the Crypt Lord"), "boss line names the boss")
	t.check(NarratorLines.line_for("level_up", "steady", CONTEXT, 0.1).contains("5"), "level line has the level")
	t.check(NarratorLines.line_for("epic_loot", "steady", CONTEXT, 0.1).contains("Frostbrand"), "loot line names the item")
	t.check(NarratorLines.line_for("quest_done", "steady", CONTEXT, 0.1).contains("Cull the Wolves"), "quest line names the quest")

	# missing context falls back instead of leaving holes
	var empty_death := NarratorLines.line_for("death", "steady", {}, 0.1)
	t.check(empty_death != "" and not empty_death.contains("{"), "death with no context still reads")

	# a trait line is used when roll < 0.6, neutral otherwise
	var neutral := NarratorLines.line_for("level_up", "steady", CONTEXT, 0.1)
	var trait_line := NarratorLines.line_for("level_up", "cautious", CONTEXT, 0.1)
	t.check(trait_line != neutral, "cautious low roll gives a trait line")
	t.check_eq(NarratorLines.line_for("level_up", "cautious", CONTEXT, 0.9), NarratorLines.line_for("level_up", "steady", CONTEXT, 0.9), "high roll gives the same neutral line for any trait")
	t.done()
```

In `tests/suite_chat_lines.gd`, before the final `t.done()` add:

```gdscript
	t.check(ChatLines.format("story", "Narrator", "It begins.").contains("[lb]Story[rb]"), "story channel has its own label")
	t.check(not ChatLines.format("story", "Narrator", "It begins.").contains("[lb]Zone[rb]"), "story is not the zone style")
```

Register `"res://tests/suite_narrator_lines.gd",` in `tests/run_tests.gd`.

- [ ] **Step 2: Run the tests to verify they fail**

Expected: SCRIPT ERROR for `NarratorLines`; the story-channel checks fail.

- [ ] **Step 3: Add the channel**

In `scripts/systems/chat_lines.gd`, in `CHANNELS` add after `"zone"`:

```gdscript
	"story": ["Story", "e6c25a"],
```

- [ ] **Step 4: Implement `NarratorLines`**

Create `scripts/systems/narrator_lines.gd`:

```gdscript
class_name NarratorLines
extends RefCounted

## Story lines for key moments, chosen per event and personality trait. Pure:
## `line_for` returns text, `NarratorDirector` decides when to speak.
## Placeholders: {name} {zone} {boss} {level} {item} {killer} {quest}.
## Lines are plain text (no BBCode, no % characters).

## Below this roll a trait-specific line is used (when the event has one).
const TRAIT_CHANCE := 0.6

const EVENTS := ["zone_arrive", "boss_engaged", "boss_victory", "boss_fled", "boss_defeated",
	"level_up", "epic_loot", "low_hp", "death", "quest_done"]

const FALLBACKS := {
	"name": "The hero", "zone": "the wilds", "boss": "the beast", "level": "?",
	"item": "a relic", "killer": "an unseen foe", "quest": "a task",
}

const TEMPLATES := {
	"zone_arrive": {
		"neutral": ["{name} arrives in {zone}.", "New ground: {name} enters {zone}."],
		"cautious": ["{name} steps into {zone}, watching every shadow."],
		"reckless": ["{name} storms into {zone} without a second thought."],
		"greedy": ["{name} reaches {zone}, already eyeing the ground for treasure."],
		"explorer": ["{zone} at last. {name} smiles and keeps walking."],
	},
	"boss_engaged": {
		"neutral": ["A shape rises ahead: {boss}.", "{boss} bars the way."],
		"cautious": ["{boss} looms. {name} grips the hilt and measures the distance."],
		"reckless": ["{boss}! {name} charges before anyone can speak."],
		"greedy": ["{boss} guards something worth having. {name} licks dry lips."],
		"explorer": ["So this is what lives here: {boss}."],
	},
	"boss_victory": {
		"neutral": ["{boss} falls.", "It is over. {boss} is no more."],
		"cautious": ["{boss} falls. {name} lets out a long breath."],
		"reckless": ["{boss} falls, and {name} laughs through the blood."],
		"greedy": ["{boss} falls. Now, what did it drop?"],
		"explorer": ["{boss} falls. One more story for the road."],
	},
	"boss_fled": {
		"neutral": ["{name} breaks away from {boss}.", "Not today: {name} retreats from {boss}."],
		"cautious": ["Discretion wins. {name} backs away from {boss}."],
		"reckless": ["Even {name} knows when to run from {boss}."],
		"greedy": ["{name} abandons the prize and flees {boss}."],
		"explorer": ["{name} leaves {boss} for another day."],
	},
	"boss_defeated": {
		"neutral": ["{boss} proves too much. {name} falls.", "{name} is cut down by {boss}."],
		"cautious": ["{name} hesitated a moment too long, and {boss} did not."],
		"reckless": ["{name} charged {boss} one time too many."],
		"greedy": ["{boss} takes {name}, and the treasure stays unclaimed."],
		"explorer": ["The road ends here, at the hands of {boss}."],
	},
	"level_up": {
		"neutral": ["{name} grows stronger: level {level}.", "Level {level}. {name} feels it in every bone."],
		"cautious": ["Level {level}. {name} nods, quietly satisfied."],
		"reckless": ["Level {level}! {name} wants a bigger fight."],
		"greedy": ["Level {level}. Stronger arms carry more loot."],
		"explorer": ["Level {level}. Further roads open up."],
	},
	"epic_loot": {
		"neutral": ["Something gleams: {item}.", "{name} finds {item}, a piece of legend."],
		"cautious": ["{name} turns {item} over twice before trusting it."],
		"reckless": ["{name} snatches up {item} and swings it at once."],
		"greedy": ["{item}! {name} has never been happier."],
		"explorer": ["{item}: proof that the road pays."],
	},
	"low_hp": {
		"neutral": ["{name} is hurt and knows it.", "Blood in the dust. {name} is badly wounded."],
		"cautious": ["{name} feels the edge of danger and looks for a way out."],
		"reckless": ["{name} is bleeding, and fighting anyway."],
		"greedy": ["{name} clutches the loot and the wound alike."],
		"explorer": ["A rough stretch of road for {name}."],
	},
	"death": {
		"neutral": ["Felled by {killer}. The story does not end here.", "{name} falls to {killer}."],
		"cautious": ["Felled by {killer}. {name} was careful, and it was not enough."],
		"reckless": ["Felled by {killer}, exactly as {name} lived."],
		"greedy": ["Felled by {killer}, with empty hands."],
		"explorer": ["Felled by {killer}, far from any road."],
	},
	"quest_done": {
		"neutral": ["The job is done: {quest}.", "{name} finishes {quest}."],
		"cautious": ["{quest} is finished. {name} checks the work once more."],
		"reckless": ["{quest}: done, and quickly."],
		"greedy": ["{quest} is done. Payment, please."],
		"explorer": ["{quest} is done. On to the next horizon."],
	},
}

## One story line for `event` and `trait_id`, or "" for an unknown event.
## `roll` (0..1) makes the choice deterministic: below TRAIT_CHANCE the trait's
## line is used when it has one, otherwise a neutral line.
static func line_for(event: String, trait_id: String, context: Dictionary, roll: float) -> String:
	var set: Dictionary = TEMPLATES.get(event, {})
	if set.is_empty():
		return ""
	var r := clampf(roll, 0.0, 0.999999)
	var pool: Array = set["neutral"]
	var index := 0
	var trait_pool: Array = set.get(trait_id, [])
	if r < TRAIT_CHANCE and not trait_pool.is_empty():
		pool = trait_pool
		index = mini(int(r / TRAIT_CHANCE * float(pool.size())), pool.size() - 1)
	else:
		index = mini(int(r * float(pool.size())), pool.size() - 1)
	return _fill(String(pool[index]), context)

static func _fill(template: String, context: Dictionary) -> String:
	var text := template
	for key in FALLBACKS.keys():
		var value := str(context.get(key, ""))
		if value == "":
			value = String(FALLBACKS[key])
		text = text.replace("{%s}" % key, value)
	return text
```

- [ ] **Step 5: Import and run the tests**

Import once, then run the tests. Expected `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/narrator_lines.gd scripts/systems/narrator_lines.gd.uid scripts/systems/chat_lines.gd tests/suite_narrator_lines.gd tests/suite_narrator_lines.gd.uid tests/suite_chat_lines.gd tests/run_tests.gd
git commit -m "Add NarratorLines and the Story chat channel

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: `RecapText` and the sheet's trait title

**Files:**
- Create: `scripts/ui/recap_text.gd`
- Create: `tests/suite_recap_text.gd`
- Modify: `scripts/ui/sheet_text.gd` (name line)
- Modify: `tests/suite_sheet_text.gd`
- Modify: `tests/run_tests.gd`

- [ ] **Step 1: Write the failing tests**

Create `tests/suite_recap_text.gd`:

```gdscript
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
```

In `tests/suite_sheet_text.gd`, before the final `t.done()` add:

```gdscript
	# trait title on the name line
	var titled := _full_snapshot()
	titled["trait_title"] = "the Cautious"
	t.check(SheetText.build(titled).contains("the Cautious"), "trait title appears on the sheet")
	var plain := _full_snapshot()
	t.check(not SheetText.build(plain).contains("the Cautious"), "no trait title without the key")
```

Register `"res://tests/suite_recap_text.gd",` in `tests/run_tests.gd`.

- [ ] **Step 2: Run the tests to verify they fail**

Expected: SCRIPT ERROR for `RecapText`; the sheet check fails.

- [ ] **Step 3: Implement `RecapText`**

Create `scripts/ui/recap_text.gd`:

```gdscript
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
```


- [ ] **Step 4: Sheet trait title**

In `scripts/ui/sheet_text.gd` `build()`, replace the name line block:

```gdscript
	var character_name := String(snap.get("character_name", ""))
	if character_name != "":
		lines.append("[b]%s[/b]" % character_name)
```

with:

```gdscript
	var character_name := String(snap.get("character_name", ""))
	if character_name != "":
		var trait_title := String(snap.get("trait_title", ""))
		lines.append("[b]%s[/b]" % (character_name if trait_title == "" else "%s %s" % [character_name, trait_title]))
```

- [ ] **Step 5: Import and run the tests**

Import once, then run the tests. Expected `0 failures`.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/recap_text.gd scripts/ui/recap_text.gd.uid scripts/ui/sheet_text.gd tests/suite_recap_text.gd tests/suite_recap_text.gd.uid tests/suite_sheet_text.gd tests/run_tests.gd
git commit -m "Add RecapText and show the trait title on the sheet

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Signals, trait in `Character`, and emissions

**Files:**
- Modify: `scripts/autoload/game_state.gd`
- Modify: `scripts/entities/character.gd`
- Modify: `scripts/entities/enemy.gd` (`_attack`)
- Modify: `tests/sim/sim_run.gd`

This task is node wiring; it is verified by the tests staying green, the Steady sim regression (Task 9) and the live check.

- [ ] **Step 1: `GameState` additions**

After the `boss_event`/`fx_enabled` block in `scripts/autoload/game_state.gd`, add:

```gdscript
## An item was picked up (equipped or not). `rarity` is the LootTable rarity.
signal item_acquired(item_name: String, rarity: String)

## The character turned in a quest.
signal quest_completed(quest_name: String)

## The character died. `info` feeds RecapText.build (see Character._die).
signal death_recap(info: Dictionary)

## The journal gained an entry / the Journal button asked to toggle the panel.
signal journal_changed()
signal journal_toggle_requested()

## The run's milestones (see Journal); filled by JournalRecorder.
var journal := Journal.new()

func record_journal(t_ms: float, kind: String, text: String) -> void:
	journal.add(t_ms, kind, text)
	journal_changed.emit()
```

Also extend the `boss_event` doc comment: `kind` is `"engaged"`, `"victory"`, `"defeated"` or `"fled"`.

- [ ] **Step 2: Trait in `Character`**

In `scripts/entities/character.gd`:

1. Add exports/vars next to `character_class`/`character_name`:

```gdscript
## Personality trait id (see TraitTable). Empty = rolled in _ready with `rng`;
## the sim harness can force one.
@export var character_trait: String = ""
var trait_def: Dictionary = {}
## Enemy name of the last thing that hit the character (for the death recap).
var last_attacker_name: String = ""
## game_time_ms when the current life began (0 at start, reset on respawn).
var life_started_ms: float = 0.0
var _engaged_id: int = 0
```

2. In `_ready`, immediately after `character_name = NameTable.pick(rng)`:

```gdscript
	if character_trait == "" or not TraitTable.TRAITS.has(character_trait):
		character_trait = TraitTable.pick(rng)
	trait_def = TraitTable.get_def(character_trait)
```

3. In `_build_context`: add to the context dictionary literal
`"flee_hp": float(trait_def.get("flee_hp", AIDecision.FLEE_HP_THRESHOLD)),` and
`"rest_hp": float(trait_def.get("rest_hp", AIDecision.REST_HP_THRESHOLD)),`;
change `ready_to_travel` to
`travel_destination_id != "" or (game_time_ms - zone_entered_time_ms) >= ZoneTable.stay_duration_ms(current_zone_id) * float(trait_def.get("stay_mult", 1.0))`;
change `context["item_nearby"] = item_dist <= AGGRO_RANGE` to
`context["item_nearby"] = item_dist <= AGGRO_RANGE * float(trait_def.get("item_range_mult", 1.0))`.

4. `get_sheet_snapshot()`: add `"trait_id": character_trait, "trait_title": TraitTable.title_of(character_trait),`.

- [ ] **Step 3: Boss "engaged" event**

In `_update_combat_target`, where the new target is a boss (the code that sets `boss_foe`), add once per boss instance:

```gdscript
	if is_instance_valid(combat_hostile) and combat_hostile.is_boss() and combat_hostile.get_instance_id() != _engaged_id:
		_engaged_id = combat_hostile.get_instance_id()
		GameState.emit_signal("boss_event", "engaged", combat_hostile.enemy_name)
```

(`combat_hostile` is typed `Node2D` in the signature: read the existing function and use the same untyped `var`/`.call("is_boss")` pattern it already uses for `boss_foe`.)

- [ ] **Step 4: Item, quest and death signals; last attacker**

1. `_acquire_item`: right after the `slot` validity check (before the `meets_level` check) add
   `GameState.emit_signal("item_acquired", display_name, String(item_def.get("rarity", "")))`.
2. `_turn_in_quest`: after the `log_event("Turned in quest: ...")` line add
   `GameState.emit_signal("quest_completed", String(quest.get("name", "")))`.
3. `take_damage` becomes `func take_damage(amount: int, is_crit: bool = false, attacker: Node2D = null) -> void:` and, after the `is_dead` guard, records the attacker:
   ```gdscript
   	if attacker != null and is_instance_valid(attacker):
   		last_attacker_name = String(attacker.get("enemy_name"))
   ```
4. `_die()`: right after `deaths += 1` (before `_update_combat_target(null)`) emit the recap, keeping the existing boss "defeated" emission where it is:
   ```gdscript
   	var total_kills := 0
   	for k in kills_by_name.values():
   		total_kills += int(k)
   	GameState.emit_signal("death_recap", {
   		"name": character_name, "trait_title": TraitTable.title_of(character_trait),
   		"trait_remark": String(trait_def.get("remark", "")), "level": level,
   		"zone": String(ZoneTable.ZONES[current_zone_id]["name"]), "killer": last_attacker_name,
   		"time_alive_s": (game_time_ms - life_started_ms) / 1000.0, "kills": total_kills, "gold": gold,
   	})
   ```
   and in the respawn section (where `is_dead = false` is set) add `life_started_ms = game_time_ms` and `last_attacker_name = ""`.

- [ ] **Step 5: `Enemy._attack` passes itself to the character**

In `scripts/entities/enemy.gd` `_attack`, replace `target.take_damage(damage)` with:

```gdscript
	if target == GameState.character:
		target.take_damage(damage, false, self)
	else:
		target.take_damage(damage)
```

(`SimulatedPlayer.take_damage(amount)` keeps its signature.)

- [ ] **Step 6: Sim harness**

In `tests/sim/sim_run.gd`: add to the doc comment `trait=steady|cautious|reckless|greedy|explorer   forced trait (default: steady)`, and after `main.get_node("Character").character_class = character_class` add:

```gdscript
	main.get_node("Character").character_trait = args.get("trait", "steady")
```

and include `trait=%s` in `monitor.run_info` (append `|trait=%s` with the value) so the logs record it.

- [ ] **Step 7: Run the tests**

Run the tests. Expected `0 failures`, no SCRIPT ERROR. Also `"$GODOT" --headless --path . --quit 2>&1 | grep -iE "error|parse"` prints nothing about the changed files.

- [ ] **Step 8: Commit**

```bash
git add scripts/autoload/game_state.gd scripts/entities/character.gd scripts/entities/enemy.gd tests/sim/sim_run.gd
git commit -m "Character traits, death recap and story signals

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Story nodes and UI

**Files:**
- Create: `scripts/ui/journal_recorder.gd`
- Create: `scripts/ui/narrator_director.gd`
- Create: `scripts/ui/death_recap.gd`
- Create: `scripts/ui/journal_panel.gd`
- Modify: `scripts/ui/speed_control.gd`
- Modify: `scripts/main.gd`

- [ ] **Step 1: `journal_recorder.gd`**

```gdscript
class_name JournalRecorder
extends Node

## Turns game signals into journal milestones. Pure bookkeeping: touches no
## gameplay state.

func _ready() -> void:
	var c = GameState.character
	if c != null and is_instance_valid(c):
		_add("start", "Set out from %s" % ZoneTable.ZONES[c.current_zone_id]["name"])
	GameState.zone_changed.connect(_on_zone_changed)
	GameState.boss_event.connect(_on_boss_event)
	GameState.character_leveled_up.connect(func(level: int): _add("level", "Reached level %d" % level))
	GameState.item_acquired.connect(_on_item_acquired)
	GameState.quest_completed.connect(func(quest_name: String): _add("quest", "Completed %s" % quest_name))
	GameState.death_recap.connect(_on_death)

func _add(kind: String, text: String) -> void:
	var c = GameState.character
	var t_ms: float = c.game_time_ms if c != null and is_instance_valid(c) else 0.0
	GameState.record_journal(t_ms, kind, text)

func _on_zone_changed(zone_id: String) -> void:
	var text := "First visit to %s" % ZoneTable.ZONES[zone_id]["name"]
	if not GameState.journal.has_kind_text("zone", text):
		_add("zone", text)

func _on_boss_event(kind: String, boss_name: String) -> void:
	match kind:
		"engaged":
			var text := "Faced %s" % boss_name
			if not GameState.journal.has_kind_text("boss", text):
				_add("boss", text)
		"victory":
			_add("boss", "Defeated %s" % boss_name)
		"fled":
			_add("boss", "Fled from %s" % boss_name)
		"defeated":
			_add("boss", "Fell to %s" % boss_name)

func _on_item_acquired(item_name: String, rarity: String) -> void:
	if rarity == "epic":
		_add("loot", "Found the epic %s" % item_name)

func _on_death(info: Dictionary) -> void:
	var killer := String(info.get("killer", ""))
	if killer == "":
		killer = "an unseen foe"
	_add("death", "Died to %s at level %d" % [killer, int(info.get("level", 1))])
```

- [ ] **Step 2: `narrator_director.gd`**

```gdscript
class_name NarratorDirector
extends Node

## Speaks story lines (NarratorLines) into the Story chat channel for key
## moments. Global cooldown on its own game clock (follows the speed control).

const COOLDOWN_MS := 4000.0
const NEVER_MS := -1000000000.0

var game_time_ms: float = 0.0
var last_line_ms: float = NEVER_MS
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	GameState.zone_changed.connect(func(zone_id: String): _say("zone_arrive", {"zone": String(ZoneTable.ZONES[zone_id]["name"])}))
	GameState.boss_event.connect(_on_boss_event)
	GameState.character_leveled_up.connect(func(level: int): _say("level_up", {"level": level}))
	GameState.item_acquired.connect(func(item_name: String, rarity: String):
		if rarity == "epic":
			_say("epic_loot", {"item": item_name}))
	GameState.chat_event.connect(func(event: String, _context: Dictionary):
		if event == "leader_low_hp":
			_say("low_hp", {}))
	GameState.death_recap.connect(func(info: Dictionary): _say("death", {"killer": String(info.get("killer", ""))}))
	GameState.quest_completed.connect(func(quest_name: String): _say("quest_done", {"quest": quest_name}))

func _process(delta: float) -> void:
	game_time_ms += delta * 1000.0

func _on_boss_event(kind: String, boss_name: String) -> void:
	var event := ""
	match kind:
		"engaged": event = "boss_engaged"
		"victory": event = "boss_victory"
		"fled": event = "boss_fled"
		"defeated": event = "boss_defeated"
	if event != "":
		_say(event, {"boss": boss_name})

func _say(event: String, context: Dictionary) -> void:
	var leader = GameState.character
	if leader == null or not is_instance_valid(leader):
		return
	if game_time_ms - last_line_ms < COOLDOWN_MS:
		return
	var ctx := context.duplicate()
	ctx["name"] = leader.character_name
	var line := NarratorLines.line_for(event, leader.character_trait, ctx, rng.randf())
	if line == "":
		return
	last_line_ms = game_time_ms
	GameState.emit_signal("chat_message", "story", "Narrator", line)
```

- [ ] **Step 3: `death_recap.gd`**

Model it on `scripts/ui/boss_events.gd` (built in code, `mouse_filter = IGNORE`, full-rect anchors). A centered card:

```gdscript
class_name DeathRecap
extends Control

const HOLD_S := 2.5
const FADE_S := 0.6

var card: Panel
var text: RichTextLabel
var tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card = Panel.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -190.0
	card.offset_right = 190.0
	card.offset_top = -80.0
	card.offset_bottom = 80.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.05, 0.05, 0.94)
	style.border_color = Color(0.7, 0.2, 0.18, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", style)
	card.modulate.a = 0.0
	add_child(card)
	text = RichTextLabel.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.bbcode_enabled = true
	text.scroll_active = false
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.offset_left = 12.0
	text.offset_top = 10.0
	text.offset_right = -12.0
	text.offset_bottom = -10.0
	card.add_child(text)
	GameState.death_recap.connect(_on_death_recap)

func _on_death_recap(info: Dictionary) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
	text.text = RecapText.build(info)
	card.modulate.a = 1.0
	tween = create_tween()
	tween.tween_interval(HOLD_S)
	tween.tween_property(card, "modulate:a", 0.0, FADE_S)
```

- [ ] **Step 4: `journal_panel.gd`**

```gdscript
class_name JournalPanel
extends Panel

## The run's milestones, newest first. J key or the Journal button toggles it;
## it does not pause the game.

var text: RichTextLabel

func _ready() -> void:
	visible = false
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -210.0
	offset_right = 210.0
	offset_top = 110.0
	offset_bottom = 470.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.07, 0.05, 0.96)
	style.border_color = Color(0.55, 0.42, 0.2, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", style)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.offset_left = 12.0
	text.offset_top = 10.0
	text.offset_right = -12.0
	text.offset_bottom = -10.0
	add_child(text)
	GameState.journal_changed.connect(func(): if visible: _refresh())
	GameState.journal_toggle_requested.connect(toggle)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J:
		toggle()

func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()

func _refresh() -> void:
	var lines: Array[String] = ["[b]Journal[/b]"]
	var c = GameState.character
	if c != null and is_instance_valid(c):
		var trait_def := TraitTable.get_def(c.character_trait)
		lines.append("[i]%s %s - %s[/i]" % [c.character_name, String(trait_def.get("title", "")), String(trait_def.get("blurb", ""))])
	lines.append("")
	var entries := GameState.journal.entries()
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		lines.append("[color=#9a8f7a]%s[/color]  %s" % [Journal.format_time(float(entry["t_ms"])), String(entry["text"])])
	text.text = "\n".join(lines)
```

- [ ] **Step 5: Journal button and wiring**

In `scripts/ui/speed_control.gd` `_ready()`, after the Director button is added, append:

```gdscript
	var journal_button := Button.new()
	journal_button.text = "Journal (J)"
	journal_button.pressed.connect(func(): GameState.journal_toggle_requested.emit())
	add_child(journal_button)
```

In `scripts/main.gd` `_ready()`, inside the existing `if ui != null:` block after `ui.add_child(BossEvents.new())` add `ui.add_child(DeathRecap.new())` and `ui.add_child(JournalPanel.new())`, and after that block:

```gdscript
	add_child(JournalRecorder.new())
	add_child(NarratorDirector.new())
```

- [ ] **Step 6: Import, test, boot check**

Import once (new class names), run the tests (`0 failures`). Boot with Godot MCP `run_project` (worktree path; the connection takes ~15 s, retry `game_eval`; do not probe port 9090 with other clients). `get_debug_output` shows no ERROR from the new scripts. `game_eval`: `GameState.journal.count()` is at least 1 (the "Set out from" entry) and `GameState.character.character_trait` is one of the five ids. Screenshot: the speed row shows `Journal (J)` and fits within 1152 px; if it does not, shorten the Director label to `Director`. Stop the project.

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/journal_recorder.gd scripts/ui/journal_recorder.gd.uid scripts/ui/narrator_director.gd scripts/ui/narrator_director.gd.uid scripts/ui/death_recap.gd scripts/ui/death_recap.gd.uid scripts/ui/journal_panel.gd scripts/ui/journal_panel.gd.uid scripts/ui/speed_control.gd scripts/main.gd
git commit -m "Add narrator, death recap card, journal recorder and panel

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Live behavior check

- [ ] **Step 1: Boot and force scenarios** (Godot MCP `run_project`, worktree path)

Using `game_eval` and `game_screenshot`:

1. Story channel: `GameState.emit_signal("character_leveled_up", 5)`; within a frame or two a `[Story] Narrator:` line appears in the chat panel (screenshot). Emit again within 4 game-seconds: no second line (cooldown).
2. Death: set `GameState.character.last_attacker_name = "Crypt Lord"` then `GameState.character.take_damage(999999)`. The red "Fallen" card appears for about 2.5 s with the killer, zone, time alive and the trait remark; after respawn the journal has `Died to Crypt Lord at level 1`.
3. Journal: press `J` (`game_key_press`) and screenshot: the panel lists `Set out from Thornfield Meadow` at the bottom and newer entries above; the Journal button toggles it too.
4. Traits: force `GameState.character.character_trait = "cautious"; GameState.character.trait_def = TraitTable.get_def("cautious")`, set `hp` to 20% with an enemy in aggro range and check `current_state` becomes `flee`; for `reckless` at 8% HP it stays `combat`.
5. Sheet: press `C`: the name line shows the trait title.
6. No ERROR lines in `get_debug_output` (ignore `mcp_interaction_server.gd` warnings).

- [ ] **Step 2: Fix anything found** in the relevant script, re-run the tests, commit as `Fix: <what>`.

---

### Task 9: Balance measurement and Steady regression

**Files:**
- Modify: `docs/superpowers/balance/2026-09-25-balance-report.md` (new section 8)
- Modify: `scripts/systems/trait_table.gd` only if a trait fails acceptance

- [ ] **Step 1: Steady regression**

```bash
export GODOT="C:/Users/n1njaz/Desktop/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
rm -rf "$TEMP/simS" && tests/sim/run_batch.sh "$TEMP/simS" 45 "warrior mage" "1 2 3 4" 8 trait=steady > /dev/null 2>&1
for f in "$TEMP"/simS/*.log; do b=$(basename $f); a=$(python tests/sim/summarize.py "$TEMP/simC/$b" | head -2 | tail -1 | tr -s ' '); c=$(python tests/sim/summarize.py "$f" | head -2 | tail -1 | tr -s ' '); [ "$a" == "$c" ] && echo "SAME $b" || { echo "DIFF $b"; echo "$a"; echo "$c"; }; done
```

(`$TEMP/simC` holds the 2026-09-26 logs; if gone, run the same batch on `main` first.) Expected: all eight `SAME`. A `DIFF` means Steady changed behavior; fix before continuing.

- [ ] **Step 2: Trait batches**

```bash
for t in cautious reckless greedy explorer; do
  echo "== $t"; tests/sim/run_batch.sh "$TEMP/simT_$t" 45 "warrior mage" "$(seq -s ' ' 1 16)" 10 trait=$t 2>&1 | grep -E "^\s*(mage|warrior)\s+[0-9]+\s+(min to L5|min to L10|deaths |worst)"
done
```

Also run the baseline for comparison: `tests/sim/run_batch.sh "$TEMP/simT_steady" 45 "warrior mage" "$(seq -s ' ' 1 16)" 10 trait=steady`, same grep.

- [ ] **Step 3: Check acceptance** (from the spec), per class and trait: mean deaths per run within 0.3 to 3.0; L5 reached by about 13 min mean; L10 reached in at least 12 of 16 runs; mean L10 time within 20% of the Steady batch. If a trait fails, adjust its numbers in `TraitTable` (small steps, e.g. Cautious rest 0.45 to 0.40, Reckless flee 0.05 to 0.07, Explorer stay_mult 0.7 to 0.8), update the pinned numbers in `tests/suite_trait_table.gd` in the same commit, and re-run only the failing trait until it passes.

- [ ] **Step 4: Report**

Append section 8 to the balance report: a table of Steady and the four traits per class (deaths, L5, L10, L10 reached) and any tuning applied with the reason. Commit:

```bash
git add scripts/systems/trait_table.gd tests/suite_trait_table.gd docs/superpowers/balance/2026-09-25-balance-report.md
git commit -m "Balance: measure and tune personality traits

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

(If nothing was tuned, only the report changes.)

---

### Task 10: README, final review and merge

- [ ] **Step 1: README**

In `README.md`: add a feature bullet under the features list (`Personality and story: each run rolls a trait (Steady, Cautious, Reckless, Greedy, Explorer) that changes its decisions, a narrator in the Story chat channel, a death recap card and a journal of milestones`); add `| **J** key / **Journal (J)** button | Open or close the journal (run milestones) |` to the Controls table next to the Codex row; add `Story` to the chat description if channels are listed. If the live check produced a good screenshot of the journal or recap card, save it to `docs/screenshots/` and add it to the Screenshots section.

- [ ] **Step 2: Final tests and review**

Run the tests (`0 failures`). Dispatch a final code-review subagent over `git diff main...personality-story` focused on: Steady exactness (context keys, multipliers), signal handler lifetimes, `Character.take_damage` signature change (callers: `Enemy._attack`, `SimulatedPlayer` is a different class), journal duplicate entries, narrator cooldown/spam, UI overlap at 1152x648 (speed row width, journal panel vs codex panel, recap card vs boss bar). Fix real findings.

- [ ] **Step 3: Commit and merge**

```bash
git add README.md docs
git commit -m "Docs: personality and story pass

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

Fast-forward merge `personality-story` into `main` locally (`git merge --ff-only personality-story` from the main checkout), re-run the tests on `main`, remove the worktree (`git worktree remove --force .claude/worktrees/personality-story`) and delete the branch. Push only when the user asks.
