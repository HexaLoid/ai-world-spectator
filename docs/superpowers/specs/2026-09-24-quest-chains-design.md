# Quest Chains — Design

## Summary

Turns the flat, independently-gated quest rotation from the original Quests
milestone into two short prerequisite chains that converge on a shared
capstone and a new epilogue — giving the AI's questing activity an actual
narrative arc (novice hunts, a boss fight, then recognition as a hero)
instead of five interchangeable "kill N of X" tasks whose only ordering was
`min_level`. Explicitly called out as a non-goal in the original quests
design ("no quest chains with prerequisites beyond `min_level` gating") —
this milestone is that deferred piece, now that the base quest system has
been live-tested and is solid.

## Goals

- A `requires` field on each `QuestTable` entry: an array of prerequisite
  quest ids that must all be in `completed_quest_ids` before it can be
  offered, layered on top of (not replacing) the existing `min_level` gate.
- Two independent early chains (wolves, bandits) that both feed into a
  shared capstone (the Crypt Lord) once both are done, so the two starting
  quests still branch rather than forcing one strict linear order.
- A new epilogue quest, `hero_of_thornfield`, unlocked only after the
  capstone, with its own unique reward (`crown_of_thornfield`, a new epic
  trinket) — a visible "you finished the story" moment.
- The rotation still never stalls: the two intro quests (`cull_the_wolves`,
  `bandit_trouble`) have empty `requires`, so there's always something
  offerable from level 1, exactly as before.
- Zero changes to how quest *progress* is tracked, turned in, or displayed —
  this only changes which quest gets offered next.

## Non-Goals

- No branching *choice* (the AI doesn't pick between mutually exclusive
  quests) — both early chains are always both eventually available, just
  gated by which prerequisite is done.
- No UI change to show the chain structure ahead of time (no quest log
  listing "locked" quests) — the tracker still only shows the one active
  quest, same as before. Discovering the chain happens by watching it play
  out in the activity log.
- No new quest types — still "kill N of X", now just orderable.

## Architecture

### Modified files

- `scripts/systems/quest_table.gd` — every `QUESTS` entry gains a
  `"requires": Array[String]` field (empty for the two intro quests).
  Chain shape:
  ```
  cull_the_wolves ─┐
                    ├─> the_crypt_lord ─> hero_of_thornfield
  bandit_trouble  ─┘        (dire_wolf_hunt +
      │                      captains_head both
      ▼                      required first)
  dire_wolf_hunt        captains_head
  ```
  New entry `hero_of_thornfield`: targets "Crypt Lord" again (count 1),
  `requires: ["the_crypt_lord"]`, `min_level: 3`, rewards
  `crown_of_thornfield`. The Crypt Lord's existing 90s respawn (unrelated to
  this milestone) means a second kill is always eventually reachable on a
  later loop through Sundered Crypt — no new respawn/targeting logic needed.
- `scripts/entities/character.gd` — `_find_next_eligible_quest_index()` gets
  one new check alongside the existing `min_level` check: every id in the
  candidate quest's `requires` must already be in `completed_quest_ids`,
  via a new small helper `_quest_requirements_met(quest)`. Nothing else in
  the quest accept/turn-in/progress flow changes.
- `scripts/systems/loot_table.gd` — new item `crown_of_thornfield` (trinket,
  epic, `crit_chance: 0.25` — the highest of any trinket, since it's the
  chain's final reward), weight-0 like every other epic so it's never a
  random drop, only earned by finishing the chain.
- `assets/icons/crown_of_thornfield_icon.png` — new 32x32 pixel-art icon
  (gold crown, gem, black outline), matching the existing icon set's style
  and generated the same way (PIL, hand-drawn shapes, no atlas extraction).

### Why prerequisites instead of a stricter linear chain

A single straight line (cull_the_wolves -> bandit_trouble -> dire_wolf_hunt
-> ...) would make the early game feel arbitrarily ordered for no reason —
there's no narrative reason wolves must come before bandits. Two independent
branches converging on the capstone keeps both starting quests meaningful
immediately while still gating the capstone behind real preparation (having
handled both threats first).

### Why the recycle behavior needed no changes

`_find_next_eligible_quest_index()` already clears `completed_quest_ids`
once its size reaches `QUESTS.size()`, so once `hero_of_thornfield` (the
last entry) is turned in, the whole chain becomes offerable from scratch
again on the next visit — the two intro quests have no `requires`, so they
re-unlock immediately, and the rest re-unlock in the same order as their
prerequisites are re-completed. This gives the spectator experience
long-run replay value (the AI runs the whole story again) with no new code.

## Error Handling / Edge Cases

- `_quest_requirements_met()` treats a missing/empty `requires` as
  vacuously satisfied (the `for` loop never runs), so the two intro quests
  and any future prerequisite-free quest need no special-casing.
- If a quest's `requires` names an id that doesn't exist in `QUESTS` (typo),
  it simply can never be satisfied and that quest is never offered — fails
  closed, not a crash, consistent with this codebase's existing
  `Dictionary.get()`-with-default error-handling style.
- Being under-leveled with both intro quests already completed (e.g. level 1
  character has done `cull_the_wolves` and `bandit_trouble` but isn't level
  2 yet) correctly yields "nothing to offer right now" rather than looping
  or erroring — same fallback behavior the original min_level gating already
  had, now shared with prerequisite gating.

## Testing / Validation

Live headless run (Godot 4.7 under Xvfb), same method as every prior
milestone, with `Engine.time_scale` temporarily raised well above the UI's
normal 4x cap in the debug driver script (not a game change) to reach
higher levels within a practical test duration:

- Confirmed only `cull_the_wolves` and `bandit_trouble` are ever offered at
  level 1, in rotation, and neither `dire_wolf_hunt`/`captains_head` is
  offered before level 2 even once its prerequisite is completed.
- Confirmed `dire_wolf_hunt` becomes offerable exactly when both conditions
  are met (level 2 AND `cull_the_wolves` completed), and likewise for
  `captains_head`/`bandit_trouble`.
- Confirmed `the_crypt_lord` is withheld until BOTH `dire_wolf_hunt` and
  `captains_head` are completed, even after level 3 is reached — verified by
  reaching level 3 with only one of the two branches done and confirming the
  Quest Giver still offers the other branch's quest, not the capstone.
- Confirmed `hero_of_thornfield` only appears after `the_crypt_lord` is
  turned in, correctly re-targets "Crypt Lord" for a second kill, and its
  turn-in grants `crown_of_thornfield` (equipped automatically over the
  existing `amulet_of_wrath`, since 0.25 > 0.20 crit chance).
- Confirmed the full-chain recycle: after `hero_of_thornfield` turn-in,
  `cull_the_wolves` becomes offerable again on the next Quest Giver visit.
- No `SCRIPT ERROR` lines across the run.

## How We'll Know This Is Done

The AI's questing now visibly tells a small story when watched over a full
session — early skirmishes against wolves and bandits, a dungeon boss fight
that's clearly gated behind having handled both first, and a distinct final
reward marking the story's end — rather than five same-weight tasks handed
out in whatever order `min_level` happened to allow.
