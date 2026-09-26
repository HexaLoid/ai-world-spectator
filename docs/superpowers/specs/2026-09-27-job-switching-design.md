# Job Switching (Phase 2) - Design

Date: 2026-09-27

## Context

Phase 1 gave every character a job. The hero keeps that one job for the whole
run and stops progressing at level 10, so after about 35 minutes there is
little left to watch. Phase 2 follows FFXIV: one character can level every job.
The hero keeps a **level, XP and gear set per job** and changes job by itself at
a **Job Crystal** in Thornfield Meadow. The spectator stays fully passive.

## Goals

- Per-job level, XP and equipment for the hero; the hero's level, XP and gear
  are always the active job's.
- Automatic, visible job changes at a crystal, chosen so all seven jobs get
  trained, with personality traits nudging the choice.
- The UI, narrator and journal reflect each change.
- The decision logic is pure and unit-tested; balance is measured with the sim.

## Non-goals

- Allies changing jobs (they keep their scene job).
- Job-locked gear, a manual job-change UI, or a higher level cap.
- Save/load.

## Per-job state: `JobState` (`scripts/systems/job_state.gd`, pure)

`JobState` is a small `RefCounted` with `level: int`, `xp: int` (cumulative, as
`Character.xp` is) and `equipment: Dictionary` (slot -> item id). Pure helpers
in `JobSwitch` (below) create and choose states; `Character` stores
`job_states: Dictionary` (job id -> `JobState`) for jobs the hero has taken.
The active job's fields live in the existing `Character.level`, `xp` and
`equipment`; on a switch the outgoing job is written back into `job_states`.

Base stats for a level are derived, not stored: `base_max_hp = 60 + 10 *
(level - 1)`, `base_damage_min/max = 4/8 + 2 * (level - 1)` (identical to
what `gain_xp` accumulates today; `LevelingSystem` constants are reused).

## Switch logic: `JobSwitch` (`scripts/systems/job_switch.gd`, pure, static)

- `catch_up_level(levels: Dictionary) -> int`: the level a job starts at the
  first time it is taken: `max(1, best_level - 2)` where `best_level` is the
  highest level among `levels` (job id -> level for taken jobs; empty -> 1).
- `starting_xp(level) -> int`: `LevelingSystem.XP_THRESHOLDS[level - 2]`, or 0
  at level 1.
- `inherit_equipment(equipment, level) -> Dictionary`: the outgoing gear set
  filtered to items with `level_req <= level` (via `ItemScoring.meets_level`),
  so a job first taken never starts naked.
- `switch_due(active_level, other_levels, reason) -> bool`: `reason` is
  `"cap"` (active job is at `LevelingSystem.MAX_LEVEL`; due when any other job
  is below the cap, counting jobs never taken as level 1) or `"loop"` (arrived
  in the meadow on the zone loop; due when some other job is at least 2 levels
  below the active one). False when there are no other jobs below the cap.
- `pick_next_job(active_id, levels, trait_id, roll) -> String`: candidates are
  all jobs except the active one and any at the cap, with untaken jobs at level
  1. The base pick is uniformly among the candidates with the lowest level, by
  `roll` (0..1, deterministic). Trait nudges (only when a matching candidate is
  no more than 2 levels above that lowest level, else the base pick):
  `explorer` picks uniformly among all candidates; `cautious` prefers `tank` /
  `healer` roles; `reckless` prefers `melee` / `magic`; `greedy` prefers
  `thief`; `steady` has no nudge. Returns `""` when there is no candidate.

## Character behaviour

- **Fields:** `job_states`, `wants_job_change: bool`, `job_change_reason:
  String`, `jobs_mastered: Array` (ids that reached the cap).
- **`_change_job(new_id)`** (see `JobSwitch`): save the outgoing `JobState`;
  load or create the new one (`catch_up_level`, `starting_xp`,
  `inherit_equipment`); set `character_class`, `class_def`, `max_resource`,
  sprite tint; set `level`, `xp`, `equipment`; recompute base stats from the
  level and `_recompute_stats()`; restore full HP; reset resource to 0 and
  clear ability cooldowns; clear `wants_job_change`; then emit
  `GameState.job_changed(old_id, new_id, level)` plus the existing
  `character_equipment_changed`, `character_hp_changed`,
  `character_resource_changed` and `character_xp_changed` signals; log
  `Changed job: <Old> -> <New> (level N)`.
- **Triggers:** in `gain_xp`, when the active job first reaches the cap add it to
  `jobs_mastered` (journal/narrator) and, if `switch_due(..., "cap")`, set
  `wants_job_change = true, job_change_reason = "cap"`. On arrival in Thornfield
  Meadow after having left it since the last switch (the existing
  travel-arrival hook `_sync_current_zone`), if `switch_due(..., "loop")` set
  `wants_job_change = true, job_change_reason = "loop"`.
- **Going to the crystal:** a new AI state `job_change` ("Heading to the job
  crystal"): `AIDecision` gets a context key `job_change_ready` (true when
  `wants_job_change` and a crystal exists in the current zone) resolved right
  after the quest-board state and above `chase`, like the quest state. When
  `wants_job_change` is set outside the meadow, the next travel leg's destination
  is forced to `thornfield_meadow` (the crystal's zone) instead of the usual next
  zone. `_act` for the state walks to the nearest node in the `job_crystals`
  group; within 30 px it calls `_change_job(pick_next_job(...))` (if the pick is
  `""`, it clears the flag and does nothing).
- **Everything shared:** quests (state and completed list), gold, kills,
  statistics, party, codex and journal are not per job. Quest `min_level` and
  zone gating (`ZoneTable.next_zone_id`) use the active job's level.
- **Mastery:** when every job is at the cap the character stops switching; the
  journal records `Mastered every job` once.

## Job Crystal

`JobCrystal` (`scenes/world/JobCrystal.tscn` + `scripts/world/job_crystal.gd`): a
`Node2D` in group `job_crystals`, drawn in code (a cyan `Polygon2D` diamond with a
slow scale/alpha pulse and a small "Job Crystal" `Label`), no new art. One
instance is placed in `ThornfieldMeadow.tscn` near the quest board.

## UI, narrator, journal

- **Ability bar:** `AbilityBar` rebuilds its slots on `job_changed`.
- **Unit frame:** level label (`Level N <Job>`) and the resource bar color and
  name refresh on `job_changed`.
- **Sheet:** the snapshot gains `jobs` (an array of `{id, name, level}` for every
  job, level 0 = not taken yet); `SheetText` adds a "Jobs" section, e.g.
  `Warrior 10, White Mage 8, Thief -`. The name/level line already uses the active
  job.
- **Narrator:** `NarratorLines` gets a `job_change` event (context `job`, `level`)
  with neutral and per-trait lines (the event count assertion in its test becomes
  11); `NarratorDirector` speaks it on `job_changed`.
- **Journal:** `JournalRecorder` adds `Took up <Job> (level N)` on each change,
  `Mastered <Job>` when a job first reaches the cap and `Mastered every job`.
- **Death recap / unit frame** already read the active job.

## Sim harness and safety

- `GameState.job_switching_enabled` (default true). When false, `wants_job_change`
  is never set, so behavior is exactly phase 1. The sim gets `switching=0|1`
  (default `0`, so existing balance commands and logs stay comparable; use
  `switching=1` to measure this feature) and the monitor logs each change as
  `SIM|job|<t_s>|<from>|<to>|<level>`; `summarize.py` counts them and reports jobs
  taken and switch count.
- **Regression:** with `switching=0` and `trait=steady`, seeded runs of all seven
  jobs must match the phase-1 logs in `$TEMP/simJC_<job>` (the reference for this
  phase; regenerate on `main` if missing).
- **Measurement:** 120-minute runs, 12 seeds, starting from Warrior, White Mage and
  Thief with `switching=1`. Acceptance: at least 3 job changes per run, mean deaths
  per 10 minutes at most 1.0, and in at least 75% of changes the new job reaches
  level 10 within 25 minutes. Tune catch-up (`best - 2`), the `loop` gap (2),
  and inherited gear as needed; record in the balance report (section 10).

## Files

- New: `scripts/systems/job_state.gd`, `scripts/systems/job_switch.gd`,
  `scenes/world/JobCrystal.tscn`, `scripts/world/job_crystal.gd`,
  `tests/suite_job_switch.gd`, `tests/suite_job_state.gd`.
- Modified: `scripts/entities/character.gd`, `scripts/ai/ai_decision.gd`,
  `scripts/autoload/game_state.gd`, `scripts/systems/narrator_lines.gd`,
  `scripts/ui/narrator_director.gd`, `scripts/ui/journal_recorder.gd`,
  `scripts/ui/ability_bar.gd`, `scripts/ui/unit_frame.gd`, `scripts/ui/sheet_text.gd`,
  `scenes/world/ThornfieldMeadow.tscn`, `tests/sim/sim_run.gd`,
  `tests/sim/sim_monitor.gd`, `tests/sim/summarize.py`, `tests/run_tests.gd`,
  `tests/suite_ai_decision.gd`, `tests/suite_narrator_lines.gd`,
  `tests/suite_sheet_text.gd`, `README.md`, the balance report.

## Testing

Headless suites (each ends with `t.done()`):

- `suite_job_switch`: `catch_up_level` (empty, one job, best minus 2, minimum 1);
  `starting_xp` at levels 1, 2 and 8; `inherit_equipment` drops items above the
  level and keeps the rest; `switch_due` for cap and loop, including "no job below
  the cap", "gap of exactly 2" and "gap of 1"; `pick_next_job`: lowest level wins,
  untaken jobs count as level 1, the active and capped jobs are excluded, each
  trait nudge applies only within 2 levels, determinism for a given roll, `""`
  when everything is capped.
- `suite_job_state`: defaults and a round trip of level, xp and equipment copies.
- `suite_ai_decision` (extended): `job_change_ready` resolves to `job_change`
  below flee/rest/combat and above chase; absent key behaves as before.
- `suite_narrator_lines` (extended): the `job_change` event; `suite_sheet_text`
  (extended): the Jobs section.

Live check: the crystal is visible in the meadow; forcing `wants_job_change`
makes the character walk to it and change job with the log line, journal entry
and narrator line; the ability bar, unit frame and sheet update; the new job's
level is best minus 2 with inherited gear; no errors.
