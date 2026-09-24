# World & Zones — Design

## Summary

The second v2 milestone (after the Warrior class): a second zone,
**Blackthorn Forest**, connected to Thornfield Meadow by a corridor, plus an
AI "travel" behavior that moves the character between zones on a fixed
dwell timer, and one reskinned/tuned "elite" enemy (Bandit Captain) as a
step toward real enemy variety. The goal is the same "watch an AI live in a
world" pitch the v1 spec set out, now spanning more than one screen's worth
of world — the character explores a zone for a while, then treks somewhere
else, giving a spectator a sense of an ongoing journey rather than one loop
forever.

## Goals

- A second zone, visually and mechanically distinct (darker/tougher forest,
  higher-stat Wolves, one elite).
- An AI "travel" state: after spending `ZONE_STAY_DURATION_MS` (45s) in a
  zone with nothing else pressing, the character walks to the next zone in
  a fixed rotation and explores that one instead.
- One elite enemy (Bandit Captain) — bigger, tinted, much tougher, with a
  guaranteed strong (existing-tier) drop — using only stat/visual overrides
  on the existing Enemy scene, no new sprite art.
- Zone-aware bounds: the character's position is confined to whichever
  zone's content it's actually near, but never hard-clamped back across the
  map by a stale "home zone" flag while fighting near a border.

## Non-Goals

- No new creature sprite art (no spider/skeleton/etc.) — the elite is a
  reskin (tint + scale) of the existing Bandit, consistent with this
  project's no-new-art-pipeline approach elsewhere (ability icons, HUD
  theme).
- No new item tiers — the elite's guaranteed drop is `iron_sword`, already
  in `LootTable.ITEMS`. New rarity tiers/dungeons are a later milestone.
- No quests, no third+ zone (`ZoneTable` supports more, but only two are
  populated).
- No changes to combat/leveling/ability systems — this milestone is purely
  about the world the existing systems play out in.

## Architecture

### New files

```
/scripts/systems
  zone_table.gd          class_name ZoneTable; ZONES (per-zone name/center/
                          bounds), TRAVEL_ORDER, WORLD_BOUNDS_MIN/MAX, and
                          next_zone_id() — same static-table pattern as
                          LootTable/AbilityTable
/scenes/world
  BlackthornForest.tscn   second zone: darker Background, tinted trees
                          (reused tree_pine.png), 2 tougher Wolf spawn
                          points + 1 elite Bandit Captain spawn point
  World.tscn              composes ThornfieldMeadow + BlackthornForest
                          (instanced at (2200,0)) + a corridor ColorRect
                          between them; replaces ThornfieldMeadow.tscn as
                          what Main.tscn instances as "World"
```

### Modified files

- `scenes/Main.tscn` — `World` node now instances `World.tscn` instead of
  `ThornfieldMeadow.tscn` directly. `ThornfieldMeadow.tscn` itself is
  unchanged and still works standalone.
- `scripts/entities/enemy.gd` / `scripts/entities/spawn_point.gd` — three
  new override fields (`sprite_size`/`sprite_tint`/`guaranteed_drop_id` on
  Enemy, with the usual sentinel-value overrides on SpawnPoint) so an elite
  is just spawn-point config, not a new scene or script.
- `scripts/ai/ai_decision.gd` — one new priority tier: `ready_to_travel`
  (from context, computed by Character) is checked after `item_nearby` and
  before the `wander` fallback, returning a new `"travel"` state. Pure
  function, same style as every other check here.
- `scripts/entities/character.gd` — the bulk of the change:
  - `current_zone_id`/`zone_entered_time_ms` track where "home" is and how
    long the character has been there; `_build_context()` derives
    `ready_to_travel` from the dwell timer.
  - `"travel"` state (`_do_travel()`) just walks toward the next zone's
    center — no arrival check of its own (see below).
  - `_sync_current_zone()` runs every `_act()` call, in every state: it
    checks whether `global_position` has actually crossed into a
    *different* zone's bounds rectangle and, if so, updates
    `current_zone_id`, resets the dwell timer, resets `wander_target`, and
    logs "Arrives in \<zone\>". This is what actually detects arrival, not
    the `"travel"` state reaching an exact point.
  - The blanket end-of-`_act()` position clamp now always uses
    `ZoneTable.WORLD_BOUNDS_MIN/MAX` (the whole traversable area), not
    `current_zone_id`'s own bounds. Only the `"wander"` branch's *target
    selection* uses the current zone's bounds, keeping idle wandering
    confined to one zone without hard-clamping every other state.

### Two bugs found during live testing (both fixed before shipping)

Both were caught by actually running the game headless-under-Xvfb for
multiple simulated zone-transition cycles, not by reading the code:

1. **Position snap-back at zone borders.** The first implementation kept
   `current_zone_id` as state updated only by the `"travel"` state's own
   arrival check, and clamped position to *that* zone's bounds in every
   other state. A Charge used mid-chase near Blackthorn's edge (a Dire Wolf
   aggroing from just inside the corridor) teleported the character deep
   into Blackthorn while `current_state` was still `"chase"` — so the
   clamp, still reading `current_zone_id == "thornfield_meadow"`, snapped
   the character straight back to x=380, and it had to re-walk the entire
   corridor. Fixed by clamping to `WORLD_BOUNDS` unconditionally and
   detecting zone entry generically (`_sync_current_zone()`) regardless of
   which state caused the crossing.
2. **Stale wander target after arrival.** Once (1) was fixed, arriving in
   Blackthorn Forest and dropping into `"wander"` immediately sent the
   character walking straight back out — `wander_target` still held its
   last value from Thornfield Meadow (far outside Blackthorn's bounds), so
   the very first `"wander"` tick chased that instead of picking a new,
   correctly-clamped target. Fixed by resetting `wander_target =
   global_position` inside `_sync_current_zone()` on every zone-entry
   transition, so the next `"wander"` tick immediately re-picks within the
   zone it's actually standing in.

### Data flow summary

```
character.gd _build_context()
  -> ready_to_travel = (game_time_ms - zone_entered_time_ms) >= ZONE_STAY_DURATION_MS
  -> next_zone_name = ZoneTable.ZONES[ZoneTable.next_zone_id(current_zone_id)]["name"]

AIDecision.resolve_state(context)
  -> {"state": "travel", "reason": "Time to move on - heading to <zone>"} (if nothing else pressing)

character.gd _act() "travel" case
  -> _do_travel(): walk toward ZoneTable.ZONES[next_id]["center"]

character.gd _act() (every state, every frame)
  -> clamp to ZoneTable.WORLD_BOUNDS_MIN/MAX
  -> _sync_current_zone(): position inside a different zone's bounds?
     -> current_zone_id updated, zone_entered_time_ms reset,
        wander_target reset, GameState.log_event("Arrives in ...")
```

## Error Handling / Edge Cases

- `_sync_current_zone()` skips the zone the character is already flagged as
  being in, so it can't re-log "Arrives in X" every frame while just
  standing in X.
- While in the corridor (inside neither zone's bounds), `current_zone_id`
  simply keeps its last value — "home" persists as "the zone I left" until
  the character actually enters the next one, which is what both the
  wander-target and dwell-timer logic want.
- Death/respawn resets `current_zone_id` to `RESPAWN_ZONE_ID`
  (Thornfield Meadow, matching `RESPAWN_POSITION`) and the dwell timer, so
  a character that died in Blackthorn Forest doesn't respawn still flagged
  as being there.
- `guaranteed_drop_id`/`sprite_size`/`sprite_tint` all default to "don't
  override" sentinels (`""`, `0.0`, transparent black respectively) so
  every existing spawn point (Wolves/Bandit in Thornfield Meadow) is
  unaffected without needing to touch their scene files.

## Testing / Validation

All via live headless runs (Godot 4.7 under Xvfb), the same method used
throughout this project:

- Confirmed the "invisible/never travels" first impression was a test-timing
  artifact (idle framerate uncapped under Xvfb runs faster than the fixed
  60Hz physics tick that drives `game_time_ms`), not a game bug, by logging
  `character.game_time_ms` directly against wall-clock-independent frame
  counts.
- Ran a full multi-cycle session (~130s of simulated game time) confirming:
  Thornfield → 45s dwell → travel → arrive in Blackthorn Forest → fight/loot
  there for the full dwell (including against the tinted, oversized Bandit
  Captain) → travel back → arrive in Thornfield again, with positions
  staying within each zone's actual bounds throughout and no repeat of
  either bug above.
- Screenshots confirm Blackthorn Forest's darker palette, tinted trees, and
  the Bandit Captain's purple tint/larger scale render correctly, and that
  the HUD (HP/XP/Rage bars, equipment icons) keeps working correctly across
  zone transitions.
- No `SCRIPT ERROR` lines across any of the validation runs.

## How We'll Know This Is Done

The AI character doesn't just loop forever in one meadow — it settles into
a zone, fights and loots there for a while, then visibly treks to a second,
tougher zone with its own enemies (including a notably stronger, distinct
elite) and back again, narrated the same way every other decision already
is, with no dead time where it's stuck walking back and forth or dropped
outside the world.
