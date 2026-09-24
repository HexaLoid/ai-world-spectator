# Quests — Design

## Summary

The third v2 milestone: a Quest Giver (a signpost/quest board in Thornfield
Meadow) offering simple "kill N of \<enemy\>" quests, accepted and turned in
automatically by the AI with no player input, giving the activity log a
narrative arc — accept, hunt, turn in, repeat — instead of just
survive-and-grind. Quest progress is tracked passively: the character
already fights whatever it encounters (per the v1 design), so a quest just
watches kills go by rather than steering combat toward its target.

## Goals

- A stationary Quest Giver in the home zone (Thornfield Meadow) the AI
  visits automatically once it has nothing more urgent to do.
- A small rotating set of kill quests spanning both zones and the elite,
  each with an XP reward and sometimes an item reward.
- A HUD quest tracker showing the active quest and progress, plus a
  WoW-style "!" marker on the quest board that's visible exactly when
  there's something to do there (accept or turn in) and hidden while a
  quest is in progress.
- Zero new combat/targeting logic — quests ride entirely on the existing
  fight-whatever's-nearby AI and the existing `take_kill_credit` hook.

## Non-Goals

- No quest types beyond "kill N of X" (no fetch/escort/explore quests).
- No quest *chains* with prerequisites beyond `min_level` gating — `QUESTS`
  is a flat rotation, recycled once every entry has been completed.
- No pathing changes — reaching the quest giver reuses the same
  move-toward-then-interact pattern `"loot"` already uses for items.
- No changes to `AIDecision`'s combat/flee/rest/chase/loot priority order
  above `"quest"`, or to how `LootTable`/`AbilityTable`/`ZoneTable` work.

## Architecture

### New files

```
/scripts/systems
  quest_table.gd        class_name QuestTable; QUESTS — id/name/target_name/
                         count/xp_reward/item_reward/min_level, same static-
                         table pattern as LootTable/AbilityTable/ZoneTable
/scripts/entities
  quest_giver.gd         adds itself to the "quest_givers" group; listens to
                         GameState.quest_changed to show/hide its own "!"
                         marker — never told directly by Character
/scripts/ui
  quest_tracker.gd       HUD label; listens to the same quest_changed signal
/scenes/entities
  QuestGiver.tscn         Sprite2D (quest_board.png) + MarkerLabel ("!")
/assets/icons
  quest_board.png         new 16x20 pixel-art signpost icon, same chunky
                         style as the existing item/ability icons
```

### Modified files

- `scripts/autoload/game_state.gd` — new signal
  `quest_changed(quest_name, progress, count)`; `("", 0, 0)` means "no
  active quest." Same one-way gameplay-emits/UI-listens rule as every other
  signal here — `QuestGiver`'s marker and the HUD tracker both just listen,
  neither is told anything directly by `Character`.
- `scenes/world/ThornfieldMeadow.tscn` — one `QuestGiver` instance placed
  away from the existing spawn points.
- `scenes/ui/SpectatorUI.tscn` — a `QuestTracker` panel next to the speed
  controls.
- `scripts/ai/ai_decision.gd` — one new priority tier, `"quest"`, checked
  after `item_nearby` and before `ready_to_travel`: fires when
  `quest_giver_in_zone and quest_ready`. Pure function, same style as every
  other check.
- `scripts/entities/character.gd`:
  - New state: `active_quest_id`, `quest_progress`, `completed_quest_ids`,
    `last_offered_quest_index`.
  - `_build_context()` adds `quest_giver_in_zone` (found via
    `_find_nearest_in_group("quest_givers")`, checked against the giver's
    own zone via the same `_zone_id_for_position()` helper `_sync_current_zone()`
    uses — refactored out of it for this reuse) and `quest_ready`
    (`_quest_has_something_to_do()`).
  - `"quest"` state in `_act()`: walks to the nearest quest giver like
    `"loot"` walks to an item; within `PICKUP_RANGE`, calls
    `_interact_with_quest_giver()`, which turns in a completed quest and/or
    accepts the next eligible one in the same visit.
  - `take_kill_credit()` now also calls `_advance_quest_progress(enemy_name)`,
    which increments progress only if there's an active quest whose
    `target_name` matches — no combat/targeting change needed.
  - `_pickup_item()`'s equip-or-discard logic is extracted into
    `_acquire_item(item_id)`, shared with quest item-reward turn-in instead
    of duplicating it.

### Data flow summary

```
enemy.gd _die() -> character.take_kill_credit(enemy_name, xp_reward)
  -> gain_xp(...)
  -> _advance_quest_progress(enemy_name)
     -> if matches active quest's target_name: quest_progress += 1
        -> GameState.quest_changed(name, progress, count)
           -> quest_tracker.gd updates its label
           -> quest_giver.gd shows "!" once progress >= count

character.gd _build_context()
  -> quest_giver_in_zone, quest_ready

AIDecision.resolve_state()
  -> {"state": "quest", ...} when quest_giver_in_zone and quest_ready

character.gd _act() "quest" case -> _interact_with_quest_giver()
  -> _turn_in_quest(): gain_xp, _acquire_item(reward) if any,
     completed_quest_ids.append(...), quest_changed("", 0, 0)
  -> _accept_next_quest(): quest_changed(name, 0, count)
```

## Error Handling / Edge Cases

- `_find_next_eligible_quest_index()` recycles `completed_quest_ids` once
  every quest has been done, so the rotation never runs dry; it's a
  read-only "peek" otherwise (`_accept_next_quest()` is the only thing that
  actually commits to an index), and the recycle is idempotent under
  repeated per-frame peeking from `_quest_has_something_to_do()`.
- `min_level`-gated quests (`Dire Wolf Hunt`, `The Captain's Head`, both
  requiring level 2) simply aren't offered until the character levels up —
  `_find_next_eligible_quest_index()` skips them, no error, no stall (the
  two level-1 quests are always available as a fallback).
- A quest's `item_reward` going through `_acquire_item()` means the normal
  "current gear is better" outcome applies here too — turning in a reward
  the character already has an equal-or-better version of just logs that,
  it doesn't crash or silently do nothing unexplained.
- The Quest Giver's marker is driven purely by the signal, never touched
  directly — if `Character` doesn't exist yet or hasn't emitted anything,
  `quest_giver.gd` defaults its marker to visible in `_ready()` (matching
  the true starting condition: no active quest).

## Testing / Validation

Live headless run (Godot 4.7 under Xvfb), same method as every prior
milestone:

- Confirmed the AI walks to the quest board unprompted at game start
  ("Heading to the quest board"), accepts "Cull the Wolves", and the HUD
  tracker updates to "Quest: Cull the Wolves (0/3)".
- Confirmed progress increments correctly as matching kills land (no
  progress from non-matching kills), the tracker updates live (e.g.
  "(2/3)"), and "Quest ready to turn in" logs once complete.
- Confirmed a full turn-in cycle: character returns to the board, logs
  "Turned in quest: Cull the Wolves", gains XP (leveled up from it in this
  run), and immediately accepts the next quest in rotation in the same
  visit.
- Confirmed the quest board's "!" marker is visible with no active quest,
  hidden while a quest is in progress, and (by code path, same as turn-in)
  visible again once complete.
- Confirmed zone travel continues to function normally with quests active
  — the character still heads off to Blackthorn Forest on schedule.
- No `SCRIPT ERROR` lines in the run.

## How We'll Know This Is Done

The AI character's activity log now reads like it's actually doing
something with a purpose beyond survival — accepting a quest, hunting the
right target across whichever zone it's in, returning to turn it in for a
reward, and picking up the next one — all without any player input, and
without changing how combat, looting, or zone travel already work.
