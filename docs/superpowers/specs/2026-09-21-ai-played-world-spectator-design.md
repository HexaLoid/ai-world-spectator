# AI-Played World Spectator — v1 Design

## Summary

A single-player, spectator-only game: one AI-controlled character autonomously
explores a small fantasy zone, fights enemies, loots items, and levels up.
The player never controls the character directly — they watch, pan/zoom the
camera, control simulation speed, and read a log explaining what the AI is
doing and why. No multiplayer, no networked/LLM reasoning in v1 — the "AI" is
local, rule-based game AI (a finite state machine), in the tradition of
classic NPC/bot AI.

This is the first vertical slice of a larger "watch an AI live its life in a
fantasy world" idea. It intentionally covers one small zone and a handful of
systems, enough to prove the core loop is watchable and legible before any
larger world is built.

## Goals

- Prove the core spectator loop is fun to watch unattended for several
  minutes: explore → fight → loot/level → repeat, with visible cause and
  effect (the log explains every decision).
- Keep the AI entirely local and deterministic-ish (no network/LLM calls) —
  fast, free, and easy to debug.
- Keep scope small enough to actually finish: one zone, two enemy types, no
  quests, no classes/spells, one AI character.

## Non-Goals (deferred, not forgotten)

- Quests or any narrative/objective system beyond "survive and grow."
- Multiple zones or an overworld map.
- Character classes, spells, or any ability beyond basic melee.
- Inventory management UI (equipment is auto-equipped by simple stat
  comparison, no player interaction).
- Multiple simultaneous AI characters.
- LLM-driven decision-making. The AI is a local finite state machine.

## Tech Stack

- **Engine:** Godot 4.x, GDScript.
- **Perspective:** 2D top-down.
- **Art:** Free/CC0 sprite packs (sourced from OpenGameArt/itch.io) for
  character, enemies, terrain tiles, and items. No custom art pipeline in v1.

## Architecture

### Project structure

```
/scenes
  /world       Thornfield Meadow zone scene (tilemap + spawn points)
  /entities    Character, Wolf, Bandit, Item pickup scenes
  /ui          Spectator UI scene (unit frame, log panel, camera/speed controls)
/scripts
  /ai          FiniteStateMachine, individual state scripts (Wander, Chase, Combat, Flee, Loot, Rest)
  /entities    Character.gd, Enemy.gd (shared base for Wolf/Bandit), Item.gd
  /systems     CombatSystem.gd, LevelingSystem.gd, LootTable.gd
  /ui          UnitFrame.gd, ActivityLog.gd, CameraController.gd, SpeedControl.gd
/assets
  /sprites, /tiles   CC0 art assets
```

- `GameState` (autoload singleton): holds references to the AI character,
  broadcasts events (state changes, damage, level-ups, loot) that the UI
  layer subscribes to. Decouples AI/combat logic from UI — the UI never
  reaches into game logic directly, it only listens to `GameState` signals.

### AI decision system (finite state machine)

The AI character has one active state at a time. Each state's `_process`
function checks whether a higher-priority transition condition is met and,
if so, switches state. Every transition emits a short reason string used
for the activity log.

States, in priority order (higher priority checked first each tick):

1. **Flee** — HP below 30% and a hostile is nearby → run away from the
   nearest hostile toward open ground.
2. **Rest** — HP below 30% and no hostile nearby → stand still, regen HP
   over time.
3. **Combat** — a hostile is within attack range → face it, attack on
   cooldown.
4. **Chase** — a hostile is within aggro range but out of attack range →
   move toward it.
5. **Loot** — an item is on the ground within pickup range and no hostile
   is nearby → move to it and pick it up.
6. **Wander** — none of the above apply → pick a random nearby point and
   walk toward it, pausing occasionally.

Transition example log lines: `"HP low (18/60) — fleeing from Bandit"`,
`"Wolf in range — engaging"`, `"Picked up Rusty Sword — equipping (higher
damage than current)"`.

### Combat

Real-time, not turn-based. Character and enemies have HP, a flat attack
damage range, and an attack cooldown. On attack: face target, roll damage
within a small random range, apply after a short wind-up. No spells or
abilities in v1 — melee only, both for the AI character and enemies.

### Leveling

Killing an enemy grants XP. Crossing an XP threshold levels the character
up (levels 1–5 for v1), increasing max HP and attack damage by a fixed
amount per level. No skill points or player choice involved — leveling is
fully automatic, consistent with "no direct player control."

### Loot

Enemies drop from a small loot table on death (3–4 total item definitions:
at least one weapon with a damage stat, one armor piece with an HP/defense
stat, and one consumable-style HP potion). When the AI character picks up
gear, it auto-equips if the new item's relevant stat beats the currently
equipped item; otherwise it's ignored (no inventory storage in v1 — keeps
scope down).

### World content — "Thornfield Meadow"

One zone: open meadow blending into a forest edge, built on a Godot
TileMap. Enemy spawn points scattered around the zone; each spawn point
respawns its enemy after a fixed delay once it's killed, so the AI always
has something to do. Two enemy types:

- **Wolf** — low HP, fast movement, low damage.
- **Bandit** — higher HP, slower, higher damage.

Both enemies use a minimal mirror of the player's Chase/Combat logic
(approach the character if it enters their aggro range, attack when in
range) — they don't need their own FSM, just the same two states.

### Spectator UI

- **Unit frame:** HP bar, level, XP bar, icons for currently equipped
  weapon/armor. Updates via `GameState` signals.
- **Activity log:** scrolling panel showing the FSM's transition reason
  strings, most recent at the bottom, capped to a reasonable scrollback
  (e.g. last 100 entries) to avoid unbounded memory growth.
- **Camera:** follows the AI character by default; click-drag pans, scroll
  wheel zooms. A "recenter" control returns to follow mode.
- **Speed controls:** buttons for pause / 1x / 2x / 4x, implemented via
  Godot's `Engine.time_scale`.

## Error Handling / Edge Cases

- **State deadlock:** if the FSM's conditions are ever simultaneously
  false for every state (shouldn't happen given `Wander` is the catch-all),
  default to `Wander` rather than freezing.
- **Character death:** if HP reaches 0, character respawns at a fixed
  point after a short delay, with a log entry, rather than the simulation
  ending. Keeps the spectator experience continuous.
- **No hostiles/items ever spawning:** not expected given respawn timers,
  but if a spawn point fails to respawn, `Wander` still gives the character
  something to do rather than the game going idle/broken.

## Testing / Validation

Primarily manual/observational for v1, given this is a simulation-feel
prototype rather than a system with strict correctness requirements:

- Run the zone unattended for 10+ minutes and confirm the character cycles
  through Wander/Chase/Combat/Flee/Loot/Rest without getting stuck in any
  one state indefinitely.
- Confirm the activity log's stated reasons always match what's actually
  visible on screen (no "fleeing" log line while the character is
  standing still, etc.) — this is the main way we catch FSM logic bugs.
- Confirm leveling, equipping, and respawn-after-death all trigger
  correctly at their respective boundaries (XP threshold, stat comparison,
  HP <= 0).

## How We'll Know V1 Is Done

The AI character can run unattended in Thornfield Meadow for several
minutes, autonomously fighting, fleeing/resting when hurt, looting and
auto-equipping better gear, and leveling up from 1 to 5 — with the
activity log narrating each decision clearly enough that a spectator with
no game knowledge can follow what's happening and why.
