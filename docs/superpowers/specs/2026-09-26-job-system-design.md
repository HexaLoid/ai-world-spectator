# Job System (Phase 1) - Design

Date: 2026-09-26

## Context

The game has two "classes" (Warrior, Mage). The request is to make every
character Final Fantasy style, with **jobs**, using FFXIV's job page as the
model: jobs are grouped by role (tank, healer, melee DPS, magic DPS), each has
its own resource and abilities, and a character can eventually take any job.
This is **phase 1**: every character has a job, new jobs exist, allies have
jobs, and a new character can be started with a chosen job. **Phase 2** (its
own spec) will add per-job levels and hero job switching at a crystal.

## Goals

- Seven jobs with distinct roles, resources, abilities and stat weights.
- Allies have jobs too, so the party reads like an FF party (a healer ally
  actually heals).
- A character select screen at start and a **New Character** button to begin a
  new run as a different job.
- Every job is balanced with the sim before merge.

## Non-goals

- Job switching and per-job levels (phase 2).
- New sprites or animation (jobs differ by tint, icons, name and behavior).
- Job-locked gear (gear stays universal; each job's stat weights already make
  it choose suitable items).
- Save/load, endings, New Game+.

## Terminology

The code's `character_class`, `class_def`, `AbilityTable.CLASSES` and the sim's
`class=` argument stay as they are (renaming would touch many files and logs).
The UI and docs say **job**. Existing ids are unchanged: `warrior`, `mage`
(displayed as **Black Mage**).

## Job data

`AbilityTable.CLASSES` entries gain display and role keys:

- `name` (String), `role` (`tank` / `healer` / `melee` / `magic`), `blurb`
  (one line for the select screen).
- Optional flat bonuses (existing `bonus_max_hp`, `bonus_armor`) plus
  `bonus_crit_chance` (float, added in `StatCalculator.derive`, default 0).
- Optional `gold_bonus_mult` (Thief; default 1.0) applied to gold from kills.
- Ally scaling (used only by `SimulatedPlayer`): `ally_hp_mult`,
  `ally_damage_mult` (default 1.0).
- The existing `resource_*`, `rage_per_*`, `primary_stat`, `stat_weights`,
  `sprite_tint`, `abilities` keys are used unchanged.

`AbilityTable.ABILITIES` extensions (existing entries untouched):

- `melee_hit` accepts `hit_count` (default 1): the hit is rolled that many
  times, each at `damage_multiplier`.
- `gap_closer` accepts `damage_multiplier`: when set, a hit of that multiple
  lands right after the jump (Dragoon's Jump).
- New kind `ally_heal`: heals the lowest-HP-fraction member among the character
  and its party by `heal_percent` of that member's max HP, when that fraction is
  below `heal_below` (default 0.65). Used by White Mage (and by healer allies).

### The seven jobs (starting numbers; tuned with the sim)

| Job (id) | Role | Resource | Abilities | Notes |
|---|---|---|---|---|
| Warrior (`warrior`) | Tank | Rage (unchanged) | Charge, Rend, Heroic Strike, Second Wind | unchanged |
| Black Mage (`mage`) | Magic | Mana (unchanged) | Frost Nova, Arcane Bolt, Mana Ward | unchanged; only gains `name`/`role`/`blurb` |
| White Mage (`white_mage`) | Healer | Mana, regen 6/s | Holy (hit x1.6), Cure (ally_heal 30%), Benediction (self heal 35%, 25 s) | INT; +20 HP, +4 armor |
| Thief (`thief`) | Melee | Focus (rage-like) | Dash (gap closer), Backstab (hit x2.0), Poison (bleed) | STR; +10% crit, gold x1.5 |
| Black Belt (`black_belt`) | Melee | Chakra (rage-like) | Rush (gap closer), Combo (3 hits x0.8), Meditate (self heal 30%) | STR; +20 HP, +2 armor |
| Dragoon (`dragoon`) | Melee | Focus (rage-like) | Jump (gap closer + hit x1.6), Impulse (hit x1.8), Elusive (self heal 20%) | STR; +15 HP, +3 armor |
| Red Mage (`red_mage`) | Magic | Mana, regen 5/s | Verthunder (hit x2.0), Enfeeble (bleed), Vercure (self heal 25%) | INT hybrid; +20 HP, +3 armor |

Ability icons reuse the existing icon set (`assets/icons/`); names differ from
icons where needed. Each job has its own `sprite_tint`.

## Character behaviour changes

- `Character._try_combat_abilities` handles `hit_count`; `_try_gap_closer`
  handles the optional jump hit; a new `_try_ally_heal()` runs each physics
  tick in every state that is not dead or fleeing (it only fires when the
  ability is ready and a party member or the character is below the threshold).
- Kill gold is multiplied by `gold_bonus_mult`.
- The unit frame and sheet show the job's `name` ("Level 4 White Mage").
- The ability bar already lists each job's own abilities.

## Allies with jobs

- `SimulatedPlayer` gains `@export var job_id: String = ""`. Empty = today's
  stats and behavior. With a job: `max_hp` and damage scale by
  `ally_hp_mult` / `ally_damage_mult`, the tint follows the job, and a job with
  role `healer` heals the lowest-HP member among the leader and the party (25%
  of that member's max HP, every 6 s, when any is below 70%, floating heal
  numbers and a log line).
- Assignments in the zone scenes: Kaelen Warrior, Elowen White Mage, Brynhild
  Dragoon, Gorrim Black Belt, Vesper Red Mage, Hrolf Thief.
- Balance impact: the healer in the starting party changes the hero's
  survivability, so all jobs are re-baselined with the sim afterwards.

## New character flow

- `CharacterSelect` (`scenes/CharacterSelect.tscn` + `scripts/ui/character_select.gd`):
  a dark screen with one card per job (name, role tag, blurb, tint swatch) and
  a **Random** card; clicking a card starts a run.
- `GameState` gains `selected_job: String`, `job_chosen: bool` and
  `select_screen_enabled: bool` (true; the sim harness sets it false), plus
  `reset_run()` (clears codex, journal, `character`, user speed and resets
  `Engine.time_scale` to 1).
- `Main._enter_tree` redirects to the select scene (deferred) when
  `select_screen_enabled` is true and `job_chosen` is false, so no
  `project.godot` change is needed. `Character._ready` uses `selected_job` when
  its own `character_class` is empty and a job was chosen (Random picks
  uniformly from all seven).
- A **New Character** button (appended to the speed row) calls
  `GameState.reset_run()`, sets `job_chosen = false` and reloads the select scene.

## Safety and testing

- Warrior and Mage numbers do not change; with `class=warrior|mage` and the old
  ally setup, seeded sim logs must match the pre-change logs (regression, done
  before the ally jobs are applied).
- Unit tests: `suite_job_table` (every job has all keys, role valid, abilities
  exist and are of known kinds, weights positive, primary stat known, `ally_*`
  and bonus values sane; `mage` and `warrior` numbers pinned to the current
  values), ability parameter tests for `hit_count`, `gap_closer` jump and
  `ally_heal` (pure helpers `AbilityMath` in `scripts/systems/ability_math.gd`
  compute the number of hits, jump damage multiplier and the heal target/amount so
  the logic is unit-testable), `StatCalculator.derive` with `bonus_crit_chance`.
- Sim batches for each job (16 seeds, 45 min): acceptance per job: mean deaths
  0.3 to 3.0, level 5 mean at most 13 min, level 10 in at least 12 of 16 runs,
  mean level 10 time within 25% of Warrior. Tuning goes in the balance report
  (section 9).

## Files

- New: `scripts/systems/ability_math.gd`, `scenes/CharacterSelect.tscn`,
  `scripts/ui/character_select.gd`, `tests/suite_job_table.gd`,
  `tests/suite_ability_math.gd`.
- Modified: `scripts/systems/ability_table.gd`, `scripts/systems/stat_calculator.gd`,
  `scripts/entities/character.gd`, `scripts/entities/simulated_player.gd`,
  `scripts/autoload/game_state.gd`, `scripts/main.gd`, `scripts/ui/unit_frame.gd`,
  `scripts/ui/sheet_text.gd`, `scripts/ui/speed_control.gd`, the four zone
  scenes with allies (Thornfield, Blackthorn, Mirewater, Frostpeak; Sundered
  Crypt has none), `tests/sim/sim_run.gd`, `tests/run_tests.gd`,
  `tests/suite_ability_table.gd`, `tests/suite_stat_calculator.gd`, `README.md`,
  the balance report.
