# Simulated Players — Design

## Summary

Populates Thornfield Meadow and Blackthorn Forest with a handful of
independent, AI-controlled "other adventurers" — Erenshor's actual core
trick, which this project's premise had only borrowed the name from until
now. Each `SimulatedPlayer` wanders its home zone, fights real enemies on
its own initiative, takes real damage, dies, and respawns — all fully
independent of the spectated `Character`, which keeps its own quest/XP/loot
systems completely untouched. Enemies now fight whichever adventurer
(spectated or simulated) is nearest, so the world actually feels shared
rather than the spectated character being the only thing monsters ever
notice.

## Goals

- Multiple named, visually distinct companions per outdoor zone, each
  wandering, fighting, fleeing/resting, and respawning entirely on their
  own — the same illusion of "a world you're not alone in" that Erenshor's
  Simulated Players create.
- Enemies pick their nearest valid target from *everyone* adventuring
  (the spectated character and every simulated player), not just the
  spectated character — so a simulated player can pull aggro, get
  attacked, and get killed, exactly like a real other player would.
- A flavor log line ("Kaelen defeats Bandit!") when a simulated player
  lands a kill, so the activity feed actually shows the world being shared
  — without ever touching the spectated character's own quest/XP/kill
  tracking.
- Reuse `AIDecision.resolve_state()` — the same pure function the
  spectated `Character` already uses — for simulated players too, rather
  than writing a second state-selection algorithm.

## Non-Goals

- No progression for simulated players — no XP, no leveling, no loot
  pickup, no quests, no class abilities (they only ever plain-auto-attack).
  They're atmosphere, not a second character to balance or track.
- No inter-zone travel — each simulated player stays in its home zone
  forever, wandering within that zone's own bounds. No Sundered Crypt
  population either — a solo boss room stays solo.
- No direct interaction with the spectated character (no grouping,
  whispers, or dialogue) — they share the same monsters, nothing else, for
  this first slice.
- No new combat mechanics — a simulated player's attack is exactly
  `CombatSystem.roll_damage()`, the same primitive Enemy already uses.

## Architecture

### New files

```
/scripts/entities
  simulated_player.gd   CharacterBody2D. Builds a context dict (hp_percent,
                         hostile_in_*_range, hostile_name, and every
                         quest/travel/loot field hardcoded false) and
                         passes it straight to AIDecision.resolve_state() —
                         since those fields are always false, the pure
                         function naturally only ever returns flee/rest/
                         combat/chase/wander for it, no branching needed
                         here to exclude quest/travel/loot behavior.
/scenes/entities
  SimulatedPlayer.tscn   CharacterBody2D + AnimatedSprite2D (reuses
                         character_frames.tres, tinted per instance) +
                         NameLabel (outlined text above the sprite)
```

### Modified files

- `scripts/entities/enemy.gd`:
  - `_find_nearest_target()` (new) replaces the old hardcoded
    `GameState.character` lookup — scans the new `"combat_targets"` group
    (which both `Character` and every `SimulatedPlayer` register into) for
    the nearest living entity, same `_find_nearest_in_group` pattern
    already used everywhere else in this project.
  - `take_damage(amount, attacker = null)` now records `last_attacker`;
    `apply_bleed(..., source = null)` records `bleed_source`, used the same
    way when a bleed tick's own `take_damage()` call lands the kill — so a
    DoT kill still attributes correctly.
  - `_die()` only calls `take_kill_credit()` (XP, quest progress) when
    `last_attacker == GameState.character` — a simulated player's kill
    never touches quest/XP state, it only logs the flavor line via
    `last_attacker.player_name` (checked with `"player_name" in
    last_attacker` rather than a type check, since the only two possible
    attacker types in this closed system are `Character` and
    `SimulatedPlayer`).
- `scripts/entities/character.gd`:
  - Joins the new `"combat_targets"` group in `_ready()`.
  - Its three damage-dealing call sites (`_attack_nearest_hostile`,
    `_use_melee_hit`, `_use_bleed`) now explicitly pass `self` as the
    attacker/bleed source, instead of relying on `_die()`'s old assumption
    that the only possible attacker was ever `GameState.character`.
- `scenes/world/ThornfieldMeadow.tscn` / `BlackthornForest.tscn` — two
  `SimulatedPlayer` instances each (Kaelen/Elowen; Brynhild/Gorrim),
  distinct tints, placed in open ground away from spawn points and
  landmarks. Sundered Crypt intentionally gets none.

### Why reuse AIDecision instead of a simplified copy

`AIDecision.resolve_state()` was already a pure function of a context
dictionary with sensible defaults for every key — passing a context that
simply never sets `quest_giver_in_zone`/`quest_ready`/`ready_to_travel`/
`item_nearby` to true means the priority chain (flee > rest > combat >
chase > ... > wander) naturally collapses to exactly the subset a
zone-bound companion needs, with zero new branching logic and zero risk of
the two state machines drifting apart over time.

### Why a shared `"combat_targets"` group instead of Enemy tracking two separate lists

A single group scanned by the same `_find_nearest_in_group`-style helper
already used throughout this project is the simplest way to make "anyone
adventuring" a single concept Enemy doesn't need to special-case — adding a
third kind of combat-target later (say, a future companion pet) would need
zero changes to `enemy.gd`.

## Error Handling / Edge Cases

- `_find_nearest_target()` skips any group member with `is_dead == true`,
  so a respawning (hidden, physics-disabled) `Character` or
  `SimulatedPlayer` is correctly invisible to enemy targeting during its
  respawn window, not just visually but functionally.
- `_die()`'s `"player_name" in last_attacker` check fails closed (no log
  line, no crash) if `last_attacker` is ever something unexpected — guarded
  by `is_instance_valid()` first in case the attacker was freed between
  dealing the killing blow and this check running (not possible in the
  current direct-hit path, but bleed's delayed-tick path makes it worth
  guarding).
- A `SimulatedPlayer`'s own death/respawn cycle (hide, wait
  `RESPAWN_DELAY_S`, restore at `spawn_position`) mirrors `Character`'s
  exactly, so the same "no orphaned bleed timers, no lingering combat
  target reference" reasoning already validated for the spectated
  character's respawn applies here too.

## Testing / Validation

Live headless runs (Godot 4.7 under Xvfb), same method as every prior
milestone:

- A 45-second live run (5x speed) across both populated zones showed
  simulated players independently engaging and defeating Wolves, Dire
  Wolves, and Bandits ("Kaelen defeats Bandit!", "Brynhild defeats Dire
  Wolf!"), dying and respawning on their own ("Gorrim has fallen -
  respawning"), all while the spectated character's own quest ("Accepted
  quest: Cull the Wolves"), leveling, and equipment logic ran completely
  normally and unaffected — confirming kill-credit separation works
  correctly in real, not just isolated, play.
- Zero `SCRIPT ERROR` lines across the run.
- A screenshot of Thornfield Meadow confirmed visually: multiple
  differently-tinted adventurers on screen simultaneously, a visible name
  tag over a simulated player, alongside the spectated character, wolves,
  and the zone's existing landmarks — the actual "populated world" effect
  this milestone is for.

## How We'll Know This Is Done

Watching any outdoor zone now shows more than one adventurer doing their
own thing — fighting, dying, respawning, occasionally logging their own
kill — while the spectated character's own systems (quests, XP, loot)
stay exactly as they were, because nothing about them had to change to
make the world feel shared.
