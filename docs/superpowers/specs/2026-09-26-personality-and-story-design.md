# Character Personality and Story - Design

Date: 2026-09-26

## Context

The spectator-experience pass made fights and bosses watchable. What is still
missing is a reason to care about *this* character: every run is the same
nameless fighter with the same decisions, and nothing is told or remembered.
This pass adds a **personality trait** that changes how the character plays,
a **narrator** that tells the story as it happens, a **death recap** card and
a **journal** of milestones.

## Goals

- Each run rolls one trait that changes real decisions and the narration, so
  runs feel different and the character has an identity.
- A narrator gives short story lines for key moments, in its own chat channel.
- Each death shows a recap card (who, where, level, what the run looked like).
- A journal panel lists the run's milestones with timestamps.
- Trait numbers, narrator line choice and the journal are pure and unit-tested;
  balance is measured with the sim before merging.

## Non-goals

- Saving the journal or character between launches (save/load is a later pass).
- New classes, player input, dialogue.
- Changing the balance of a Steady (no-trait) character in any way.

## Traits: `TraitTable` (`scripts/systems/trait_table.gd`, pure, static)

Five traits, one per character, rolled with the character's own `rng`:

| Trait id | Title | Effect |
|---|---|---|
| `steady` | the Steady | none (exactly today's behavior) |
| `cautious` | the Cautious | flee below 25% HP (default 10%), rest below 45% (default 30%) |
| `reckless` | the Reckless | flee below 5% HP, rest below 20% |
| `greedy` | the Greedy | notices loot from 1.6x the usual distance |
| `explorer` | the Explorer | zone stays are 30% shorter |

Each entry: `{"title": String, "flee_hp": float, "rest_hp": float,
"item_range_mult": float, "stay_mult": float, "blurb": String}`. Steady's
values are the current constants (`AIDecision.FLEE_HP_THRESHOLD`,
`REST_HP_THRESHOLD`, 1.0, 1.0). API: `TraitTable.ids()`, `get_def(id)`,
`title_of(id)`, `pick(rng) -> String` (uniform over ids).

`AIDecision.resolve_state` reads optional context keys `flee_hp` and `rest_hp`
(defaulting to the existing constants), so existing tests and behavior are
unchanged when the keys are absent.

`Character` gains `var character_trait: String` (an `@export`, empty = roll
one in `_ready` with its `rng`; the sim harness can force it), and applies it:

- `_build_context` adds `flee_hp` and `rest_hp` from the trait;
- item noticing uses `AGGRO_RANGE * item_range_mult`;
- `ready_to_travel` compares the stay against `stay_duration_ms * stay_mult`.

The unit frame stays unchanged. The character sheet header becomes
`Aldric the Cautious - Level 7 Warrior` (via `SheetText`, keeping the class and
level text), and the snapshot gains `trait_id` and `trait_title`.

## Narrator: `NarratorLines` (`scripts/systems/narrator_lines.gd`, pure, static)

`NarratorLines.line_for(event, trait_id, context, roll) -> String` returns one
story line (or `""` when there is nothing to say). Events and context:

| Event | Context | Example (Cautious) |
|---|---|---|
| `zone_arrive` | `zone` | "Aldric steps into Mirewater Swamp, watching every shadow." |
| `boss_engaged` | `boss` | "A shape rises ahead: the Crypt Lord. Aldric grips the hilt." |
| `boss_victory` | `boss` | "The Crypt Lord falls. Aldric lets out a long breath." |
| `boss_fled` | `boss` | "Discretion wins. Aldric backs away from the Crypt Lord." |
| `boss_defeated` | `boss` | "The Crypt Lord proves too much. Aldric falls." |
| `level_up` | `level` | "Aldric grows stronger: level 5." |
| `epic_loot` | `item` | "Something gleams: Frostbrand. Aldric takes it." |
| `low_hp` | none | "Aldric is hurt and knows it." |
| `death` | `killer` | "Killed by X. The story does not end here." |
| `quest_done` | `quest` | "The Cull the Wolves job is done." |

- Each event has 2-3 neutral lines plus 1-2 lines per trait; the trait line is
  chosen when `roll < 0.6` and one exists, otherwise a neutral line
  (`roll` picks the variant deterministically). All lines are templates using
  `{name}`, `{zone}`, `{boss}`, `{level}`, `{item}`, `{killer}`, `{quest}`; the
  character name is passed in `context["name"]`.
- Every string is plain text without BBCode or `%` formatting problems (tested
  by formatting every template with sample context).
- A `NarratorDirector` node (`scripts/ui/narrator_director.gd`, added by
  `main.gd` like the other directors) listens to the existing signals
  (`chat_event` for zone arrival, low HP, death, level up and loot; `boss_event`,
  `combat_target_changed` for boss engaged; `quest_changed` for quest done),
  applies a global cooldown of 4 s (game-time clock, like `ChatDirector`) so a
  burst of events never spams, and emits
  `GameState.chat_message("story", "Narrator", text)`.
- `ChatLines.CHANNELS` gains `"story"` (label `Story`, a distinct parchment
  gold color); the chat panel already renders any channel from that table.

## Death recap

- `Character.take_damage(amount, is_crit = false, attacker = null)`; `Enemy._attack`
  passes `self`. `Character` remembers `last_attacker_name` (enemy name, else "").
- On death `Character` emits `GameState.death_recap(info: Dictionary)` with
  `{name, trait_title, level, zone, killer, time_alive_s, kills, gold}` where
  `time_alive_s` is the game time since the last respawn (or start).
- `DeathRecap` (`scripts/ui/death_recap.gd`, a `Control` built in code and added
  to the UI by `main.gd`) shows a centered card for `HOLD_S = 2.5` s (the
  respawn delay is 2 s, so the card fades over the first seconds of the new
  life) with `RecapText.build(info) -> String` (pure, `scripts/ui/recap_text.gd`):
  title "Fallen", killer/zone/level line, time alive and kills line, and a
  one-line trait remark. Uses the same style as `BossEvents`.

## Journal

- `Journal` (`scripts/systems/journal.gd`, pure, no nodes): entries
  `{"t_ms": float, "kind": String, "text": String}`; `add(t_ms, kind, text)`,
  `entries()`, `count()`, `has_kind_text(kind, text)` (to make "first X"
  entries unique), and `Journal.format_time(t_ms) -> String` (`m:ss`).
  `GameState` gains `var journal := Journal.new()` and
  `signal journal_changed()`.
- `JournalRecorder` logic lives in `Character` and `Enemy` at the same places
  that already emit events (no new gameplay hooks): first arrival in each zone,
  a boss first sighted, boss victory / fled / defeated, epic item found, level
  up, death, quest completed. Texts are plain sentences (`"Reached level 5"`).
- `JournalPanel` (`scripts/ui/journal_panel.gd`, built in code, added by
  `main.gd`): toggled by the `J` key or a **Journal (J)** button appended to the
  speed row; a dark panel about 420x360 centered like the codex, `RichTextLabel`
  with entries newest first (`m:ss  text`) and the trait blurb at the top; it
  refreshes on `journal_changed` while visible. Does not pause the game.

## Safety and balance

- Steady must behave exactly like today: same `flee_hp`/`rest_hp`, `item_range_mult`
  1.0, `stay_mult` 1.0. A sim regression on a forced `trait=steady` run must
  match the pre-change logs for the same seeds (as in the last pass).
- The sim harness gains `trait=<id>` (forces `character_trait`); the default (no
  arg) rolls from the seeded rng. All narration/recap/journal work is UI-side
  and runs regardless of `fx_enabled`, but touches no gameplay state; the
  `rng` draw for the trait happens once in `_ready`.
- Because the trait draw consumes one value from the character's `rng`, seeded
  runs without `trait=` differ from older logs; the regression uses
  `trait=steady`.
- Balance measurement: 16 seeds x 2 classes x each of the four non-steady
  traits, 45 minutes. Acceptance: mean deaths per run within 0.3 - 3.0, level 5
  by 13 min and level 10 by 45 min in at least 12 of 16 runs, no trait more than
  20% off the Steady pace. Tune the numbers in `TraitTable` if a trait fails
  (recorded in the balance report).

## Files

- New: `scripts/systems/trait_table.gd`, `narrator_lines.gd`, `journal.gd`;
  `scripts/ui/narrator_director.gd`, `death_recap.gd`, `recap_text.gd`,
  `journal_panel.gd`; tests `suite_trait_table.gd`, `suite_narrator_lines.gd`,
  `suite_journal.gd`, `suite_recap_text.gd`.
- Modified: `scripts/ai/ai_decision.gd`, `scripts/entities/character.gd`,
  `scripts/entities/enemy.gd`, `scripts/autoload/game_state.gd`,
  `scripts/systems/chat_lines.gd`, `scripts/ui/sheet_text.gd`,
  `scripts/ui/speed_control.gd`, `scripts/main.gd`, `tests/sim/sim_run.gd`,
  `tests/suite_ai_decision.gd`, `tests/suite_sheet_text.gd`,
  `tests/suite_chat_lines.gd`, `tests/run_tests.gd`, `README.md`,
  `docs/superpowers/balance/2026-09-25-balance-report.md`.

## Testing

Headless suites (each ends with `t.done()`):

- `suite_trait_table`: every id has all keys; Steady equals the current
  constants; `flee_hp < rest_hp` for all; `pick` is deterministic for a seeded
  rng and covers all ids over many draws; `title_of`.
- `suite_ai_decision` (extended): a Cautious threshold flees at 20% HP where
  the default would fight; a Reckless one fights at 8% where the default would
  flee; missing keys behave as before.
- `suite_narrator_lines`: every event x trait returns non-empty text for a
  sample context; no unresolved `{...}` placeholders; unknown events give `""`;
  the same roll gives the same line; a trait line appears for `roll < 0.6`.
- `suite_journal`: add/entries ordering, `count`, `has_kind_text`, `format_time`.
- `suite_recap_text`: recap text contains the killer, zone, level and trait
  title; handles an empty killer.
- `suite_sheet_text` / `suite_chat_lines` (extended): header includes the trait
  title; `story` channel formats.

Live check: a Cautious run flees earlier than a Reckless one; narrator lines
appear in the Story channel with a sensible cadence; a death shows the recap
card and a journal entry; the journal panel opens with `J` and the button and
lists milestones newest first; no errors.
