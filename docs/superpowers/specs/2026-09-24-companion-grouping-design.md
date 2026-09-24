# Companion Grouping — Design

## Summary

Turns Simulated Players from independent zone-locked wanderers into real
party members: the spectated Character automatically recruits up to two
companions from its starting zone, who then follow it everywhere —
including across zones and into Sundered Crypt for a boss fight — fight
whatever the leader is fighting, and level up from their own kills. This
is Erenshor's actual headline feature ("build a group of AI companions to
help you conquer dungeons, quests, and world bosses... they get stronger,
they bleed with you"), which the prior Simulated Players milestone
deliberately deferred as a non-goal.

## Goals

- Automatic recruitment: on entering a zone (or already starting in one),
  the Character recruits any of that zone's ungrouped companions, up to a
  party cap of 2. No player input exists in this game, so "recruit" has to
  be something the AI itself decides, not a menu action.
- A grouped companion follows the leader (not just wanders its home zone)
  and prefers fighting the leader's own current target when it has one —
  so a fight visibly looks shared, not like several individuals who
  happen to be nearby.
- Grouped companions travel with the leader between zones, specifically
  including into Sundered Crypt — a solo boss room becomes a real "bring
  your party" boss room, without Sundered Crypt needing any simulated
  players of its own.
- Companions gain XP and level up from their own kills (reusing
  `LevelingSystem`, unchanged) — Erenshor's "they get stronger" promise —
  regardless of whether they're currently grouped.
- Recruitment is permanent for this slice: once grouped, a companion stays
  in the party for the rest of the session. Simple, and avoids needing any
  "why did they leave" logic this first pass doesn't need yet.

## Non-Goals

- No player-driven recruitment UI — automatic-on-zone-entry is the right
  fit for a spectator game with no input.
- No un-grouping/party management — permanent-once-recruited is
  intentional simplicity, not an oversight.
- No shared/bonus XP for the leader from a companion's kill, or vice versa
  — each still only gains XP from what it personally lands the killing
  blow on, exactly as before this milestone.
- No companion abilities (still plain auto-attack only) or quest/loot
  participation — unchanged non-goals from the original Simulated Players
  milestone; grouping doesn't expand those.
- No HUD party panel — companions' presence is visible in the world itself
  (following, fighting alongside) and in the activity log (join/level-up
  lines), which is enough for this slice.

## Architecture

### Modified files

- `scripts/entities/character.gd`:
  - New `const MAX_PARTY_SIZE := 2` and `var party: Array = []`.
  - New `_recruit_companions_in_zone(zone_id)`: scans the `"simulated_players"`
    group for ungrouped (`group_leader == null`) companions whose
    `home_zone_id` matches, and recruits up to the party cap — setting
    `sp.group_leader = self` is the *entire* handoff; everything else about
    following/targeting/world-bounds-instead-of-zone-bounds is the
    companion's own responsibility once that one field is set (see below).
  - Called from `_sync_current_zone()` (every zone arrival) AND once
    directly in `_ready()` — the latter because the Character starts
    already inside its home zone rather than "arriving" there, so without
    it Thornfield's companions would never get recruited unless the
    Character later left and came back.
- `scripts/entities/simulated_player.gd`:
  - New `_preferred_hostile()`: returns the leader's own
    `last_combat_target` when grouped and that target is still alive,
    otherwise falls back to the companion's own nearest-enemy search
    (ungrouped, or leader not currently fighting anything). Resolved once
    per tick and threaded through to both the `AIDecision` context *and*
    the actual combat/chase actions in `_act()` — an earlier version of
    this only fed it into the context (affecting whether "combat" state
    was chosen) while `_act()` re-derived its own nearest enemy
    independently, meaning "fight what the leader fights" wasn't actually
    happening in combat itself. Caught and fixed via live testing.
  - The `"wander"` fallback becomes "follow the leader" when grouped
    (move toward the leader once further than `FOLLOW_DISTANCE`), instead
    of the original random zone-bound wander target.
  - The end-of-tick position clamp switches from the companion's own home
    zone bounds to `ZoneTable.WORLD_BOUNDS_MIN/MAX` when grouped — this one
    line is what actually lets a companion leave its home zone at all;
    without it a "following" companion would just get clamped back at its
    old zone's border forever.
  - `_die()`'s respawn position is the leader's *current* position when
    grouped, not the companion's original spawn point — otherwise dying
    mid-journey (say, inside Sundered Crypt) would respawn it back home,
    stranded and unable to catch back up.
  - New `take_kill_credit(enemy_name, xp_reward)`, mirroring
    `Character`'s own method name and `LevelingSystem` usage exactly:
    applies XP, and on level-up raises `max_hp`/`attack_damage_min/max`
    and logs `"<name> levels up to <level>!"`.
- `scripts/entities/enemy.gd` — `_die()`'s existing "non-character
  attacker" branch now also calls `last_attacker.take_kill_credit(...)`
  (previously it only logged the flavor line), so a companion's kill
  actually grants it XP, not just a log line.

### The one bug live testing caught

`_preferred_hostile()`'s first draft read
`var leader_target: Node2D = group_leader.last_combat_target` — a *typed*
assignment. `last_combat_target` can be a stale reference to an Enemy that
was `queue_free()`'d after Character's own per-tick `last_combat_target`
update (which only changes when Character's *own* combat_hostile changes,
so it can lag a frame behind the target actually dying). Assigning an
already-freed Object into a typed `Node2D` variable throws `"Trying to
assign invalid previously freed instance"` immediately, before
`is_instance_valid()` ever gets a chance to run. Fixed by fetching it into
an untyped variable first, exactly so `is_instance_valid()` can safely gate
the typed use — the same pattern this project's debug/test scripts have
used all along for `SceneTree`-script `get_node()` results, just needed
here for the first time in real gameplay code because this is the first
place one entity reads another's live object-reference field directly.

## Error Handling / Edge Cases

- `_recruit_companions_in_zone` re-checks `party.size() >= MAX_PARTY_SIZE`
  inside its own loop (not just once at the top), so it can't ever
  over-recruit even if a zone happens to have more ungrouped companions
  than remaining party slots.
- A companion mid-respawn (`is_dead == true`, hidden, physics disabled)
  is still skipped by Enemy's `_find_nearest_target()` exactly as before —
  grouping changes nothing about that.
- `_preferred_hostile()` fails closed to the companion's own nearest-enemy
  search whenever the leader reference itself is invalid, not just when
  the target is — a freed `group_leader` can't happen in this single-
  session game (Character never queue_frees), but the check costs nothing
  and matches this codebase's general "guard every cross-entity reference"
  habit.

## Testing / Validation

Live headless run (Godot 4.7 under Xvfb, 8x speed, ~150 real seconds
covering 120 sim-seconds), same method as every prior milestone:

- Confirmed "Kaelen joins the group!" / "Elowen joins the group!" fire
  immediately at game start (the `_ready()`-time recruitment path, not
  just the zone-transition one).
- Confirmed both companions' tracked positions moved in lockstep with the
  Character's zone transitions across the full loop
  (Thornfield → Blackthorn → Sundered Crypt → Blackthorn → Sundered
  Crypt), landing inside Sundered Crypt at the same time as the Character
  — the actual "companions follow you into the dungeon" scenario this
  milestone exists for — and a companion was confirmed within 400 units
  of the Character while there.
- Confirmed the Character reached level 5 and defeated the Crypt Lord with
  its recruited party present in the room.
- Confirmed companion leveling independent of grouping: Gorrim (Blackthorn
  Forest's *ungrouped* local, since the party filled from Thornfield
  first) leveled up to 4 entirely on its own kills over the run, proving
  leveling doesn't depend on being in a party.
- Confirmed kill-credit stays correctly separated throughout: the
  Character's own "Defeated X"/quest-progress lines never mixed with
  companions' "X defeats Y!"/"X levels up to N!" lines.
- One real bug found and fixed (see above); zero `SCRIPT ERROR` lines in
  the final run.

## How We'll Know This Is Done

Watching the game now shows an actual party: the spectated character
picks up companions at the very start, drags them through both outdoor
zones and into the dungeon, everyone fights the same targets together,
and the companions visibly grow stronger in their own right — matching
what Erenshor's simulated players are actually known for, not just its
name.
