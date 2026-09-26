# Five-Man Dungeon: the Hollowed Vault - Design

Date: 2026-09-27

## Context

The Sundered Crypt is a small room with one boss, the open-world party holds at
most 2 allies (`MAX_PARTY_SIZE := 2`) and no encounter needs a role. Jobs now
have roles (tank, healer, melee, magic) and allies have jobs. This phase adds an
**instanced five-man dungeon** so those roles matter: a party of five, three
rooms, a mini-boss, and a final boss with mechanics. Raids (8+ members) are a
later phase that will reuse this party and encounter system.

## Goals

- A five-person run (hero + 4 allies) with one tank, one healer and three damage
  dealers, formed like a Duty Finder at a portal.
- A separate instanced map: trash packs, a mini-boss, a final boss with a
  telegraphed heavy strike and an add phase; a clear or fail result.
- Threat: enemies prefer the tank while in the dungeon, so a tank ally holds them.
- Dungeon-only epic loot, story beats (banners, narrator, journal, codex).
- Party formation, threat targeting and encounter timing are pure and unit-tested;
  balance is measured with the sim and the open-world balance is untouched.

## Non-goals

- Raids, difficulty tiers, manual queueing or a spectator control.
- Changing the open-world party size (it stays 2).
- New sprites: dungeon enemies reuse the bandit and wolf frames with tints.

## Party formation: `PartyBuilder` (`scripts/systems/party_builder.gd`, pure)

`PartyBuilder.missing_members(hero_role, party, pool, size = 5) -> Array` returns
the members of `pool` to add so the group has `size` people (hero included).
`party` and `pool` are arrays of `{"id": String, "name": String, "role": String}`
(`role` is a job role: `tank`, `healer`, `melee`, `magic`). Rules:

1. Members already in `party` stay.
2. If the group (hero role plus `party` roles) has no tank, add a tank from `pool`
   first; then, if it has no healer, add a healer; a role missing from `pool` is skipped.
3. Fill the remaining slots with damage roles (`melee`, `magic`), then, if still
   short, any remaining `pool` members, in `pool` order (deterministic).
4. Never return more than `size - 1 - party.size()` members or a member already in
   `party`.

The pool is the six named allies (Kaelen Warrior/tank, Elowen White Mage/healer,
Brynhild Dragoon/melee, Gorrim Black Belt/melee, Vesper Red Mage/magic, Hrolf
Thief/melee) that are not already grouped.

## Entering: the Vault Gate and a new AI state

- `VaultGate` (`scenes/world/VaultGate.tscn` + `scripts/world/vault_gate.gd`): a
  code-drawn portal (purple ring and glow, group `vault_gates`) placed in the
  Sundered Crypt.
- `AIDecision` gets context key `dungeon_ready` and a state `dungeon_enter`
  ("Heading to the Vault Gate"), resolved after the quest and job-change states
  and above chase. `Character` computes `dungeon_ready` as: switching/dungeon flag
  on, not already in a dungeon, level >= `DUNGEON_MIN_LEVEL` (8), HP >= 70%, the
  dungeon cooldown elapsed (`DUNGEON_COOLDOWN_MS` = 15 minutes of game time, also
  after a fail) and a `vault_gates` node in the current zone.
- Within 30 px of the gate the hero starts the run through `DungeonRun`.

## The run: `DungeonRun` (`scripts/world/dungeon_run.gd`, a node added by `Main`)

States: `idle`, `running`. Start (`start(hero)`):

1. Build the party: `PartyBuilder.missing_members(...)`; each added ally gets
   `group_leader = hero` and is appended to `hero.party` (recorded as "pulled" so it
   is released afterwards); `party_changed` is emitted.
2. Instantiate `scenes/world/HollowedVault.tscn` at world position `(12000, 0)`,
   set `GameState.in_dungeon = true`, teleport the hero and the party to the
   entrance, emit `GameState.dungeon_event("enter", "Hollowed Vault")`.
3. `_physics_process` watches the run: **cleared** when the final boss is dead
   (all `dungeon_enemies` of the final room gone); **failed** when the hero dies
   or after `RUN_TIMEOUT_S` (12 minutes of game time).

End (`_end_run(success)`): free the vault instance and every remaining node in group
`dungeon_enemies`; teleport the hero (if alive) and the party back to the gate; release
every "pulled" ally (`group_leader = null`, removed from `party`, teleported to its
spawn position); `GameState.in_dungeon = false`; set the cooldown; emit
`dungeon_event("clear" | "fail", ...)`. A cleared run also gives the hero a bonus
(`CLEAR_BONUS_XP` via `gain_xp`, gold) and records `dungeons_cleared`.

## The map: `HollowedVault.tscn` and a new zone

- `ZoneTable.ZONES` gains `hollowed_vault` with `"instanced": true`, `min_level` 8,
  bounds around `(12000, 0)` (about 1500 x 400: three connected rooms in a row) and
  is **not** in `TRAVEL_ORDER`. `WORLD_BOUNDS_MAX.x` grows to cover it, and
  `ZoneTable` gets `ALL_ZONE_ORDER` (`TRAVEL_ORDER` plus instanced zones) for the
  codex. Tests that assume "every zone is in `TRAVEL_ORDER`" or "bounds inside the
  world" are updated to skip or include instanced zones as appropriate.
- The scene (dark stone floor drawn with `ColorRect`s, pillars from existing tiles,
  no new art) holds `SpawnPoint` nodes with `dungeon = true` (a new export: the enemy
  joins group `dungeon_enemies` and the spawn point never respawns it):
  - Room 1: 3 packs of 2 `vault_skeleton`.
  - Room 2: the mini-boss `bone_warden` with 2 `vault_skeleton`.
  - Room 3: the final boss `hollow_king`.

## Enemies and loot

`EnemyTable` gains `zone: "hollowed_vault"` enemies (bandit/wolf frames, dark tints):

| id | HP | damage | notes |
|---|---|---|---|
| `vault_skeleton` | 90 | 10-16 | trash, loot_level 10 |
| `vault_wraith` | 60 | 12-18 | the boss's adds |
| `bone_warden` | 700 | 30-45 | mini-boss, guaranteed epic |
| `hollow_king` | 1800 | 38-55 | final boss, guaranteed epic, `mechanics` set |

(Starting numbers, tuned with the sim.) `LootTable` gains four dungeon epics with
`level_req` 8 to 9 (a chest, a strength weapon, an intellect staff and a ring), icons
reused; the bosses' `guaranteed_drop` ids point at them, so `CodexData` shows their
sources. Tests that enumerate epics and boss drops are updated.

## Roles that matter

- **Threat:** while `GameState.in_dungeon`, `Enemy._find_nearest_target` uses
  `ThreatRules.pick_target(candidates, aggro_range)`: a target with role `tank`
  within `aggro_range * TANK_PULL_MULT` (1.3) wins over a nearer non-tank; otherwise
  the nearest wins. Outside a dungeon the existing nearest-target rule is used
  unchanged. `ThreatRules` (`scripts/systems/threat_rules.gd`) is pure: it takes an
  array of `{"dist": float, "is_tank": bool}` and returns an index (or -1).
  Combat targets expose `job_role` (Character: from its class def; SimulatedPlayer:
  from `job_role`).
- **Boss mechanics:** an enemy def can set `"mechanics": "hollow_king"`. `Enemy`
  adds a `BossMechanics` child (`scripts/entities/boss_mechanics.gd`) driven by the
  pure `EncounterLogic`:
  - a **heavy strike** every `HEAVY_INTERVAL_MS` (9000): a 1.5 s wind-up with a
    warning (`dungeon_event("warning", "<boss> winds up!")` banner and a red flash
    on the boss), then `heavy_damage(attack_max, HEAVY_MULT = 2.5)` to the current
    tank (or the current target when none);
  - an **add phase** once at 50% HP: 2 `vault_wraith` spawn beside the boss.
  `EncounterLogic` functions (`heavy_due(now_ms, next_ms)`, `heavy_damage`,
  `add_phase_due(hp, max_hp, done)`) are pure and unit-tested.
- The healer ally (`SimulatedPlayer._tick_healer`) and White Mage Cure already heal;
  the pull-in party makes a healer always present when one exists in the pool.

## AI inside the dungeon

- A state `dungeon_advance` ("Pressing on") for the hero while `GameState.in_dungeon`
  and no hostile is in aggro range: walk toward the nearest node in `dungeon_enemies`
  (below chase, loot and quest; above wander/travel). While in a dungeon,
  `ready_to_travel` is false and job-change trips are ignored.
- Allies already follow the leader and fight the leader's target.
- Everything else (flee/rest/combat/chase/loot) is unchanged.

## UI, story, codex

- `GameState.dungeon_event(kind, name)` (`enter`, `warning`, `clear`, `fail`);
  `BossEvents` shows banners for it (entering, warning, cleared, failed).
- `NarratorLines` gains `dungeon_enter`, `dungeon_clear`, `dungeon_fail` (events count
  14) and `NarratorDirector` speaks them; `JournalRecorder` adds `Entered the Hollowed
  Vault`, `Cleared the Hollowed Vault` (and `Fell in the Hollowed Vault`).
- The codex zones tab lists the vault (via `ZoneTable.ALL_ZONE_ORDER`), the bestiary its
  enemies; `PartyFrames` shows up to four allies (check the layout at 1152x648).

## Sim harness and safety

- `GameState.dungeon_enabled` (default true in the game). The sim gets
  `dungeon=0|1` (default 0) and logs `SIM|dungeon|result=cleared|failed|timeout|dur=<s>`;
  `summarize.py` counts clears/fails and mean duration.
- **Regression:** with `dungeon=0` (and `switching=0`, `trait=steady`) seeded runs of
  all seven jobs must match the phase-2 logs in `$TEMP/simJC_<job>`. (Threat rules and
  the extra states are inert when no dungeon is running.)
- **Measurement:** 120-minute runs, 12 seeds, `dungeon=1 switching=1`, starting from
  Warrior, White Mage and Thief. Acceptance: at least one dungeon attempt per run, a
  clear rate of 60% to 90%, a mean run time of 3 to 8 minutes, hero deaths per 10
  minutes at most 1.0 over the whole run and no stuck run (a run that times out
  counts as a fail, and more than 15% timeouts fails the check). Tune enemy HP and
  damage, `HEAVY_MULT` and the interval; record in the balance report (section 11).

## Files

- New: `scripts/systems/party_builder.gd`, `threat_rules.gd`, `encounter_logic.gd`,
  `scripts/entities/boss_mechanics.gd`, `scripts/world/dungeon_run.gd`,
  `scripts/world/vault_gate.gd`, `scenes/world/VaultGate.tscn`,
  `scenes/world/HollowedVault.tscn`, tests `suite_party_builder.gd`,
  `suite_threat_rules.gd`, `suite_encounter_logic.gd`.
- Modified: `scripts/systems/zone_table.gd`, `enemy_table.gd`, `loot_table.gd`,
  `codex_data.gd`, `narrator_lines.gd`; `scripts/entities/character.gd`, `enemy.gd`,
  `spawn_point.gd`, `simulated_player.gd`; `scripts/ai/ai_decision.gd`;
  `scripts/autoload/game_state.gd`; `scripts/ui/boss_events.gd`,
  `narrator_director.gd`, `journal_recorder.gd`, `party_frames.gd`; `scripts/main.gd`;
  `scenes/world/SunderedCrypt.tscn`, `World.tscn` (bounds only if needed);
  `tests/sim/*`; the zone, enemy, loot, codex, AI, narrator suites; `README.md`; the
  balance report.

## Testing

Headless suites (each ends with `t.done()`):

- `suite_party_builder`: tank first, then healer, then damage; existing members stay;
  a role missing from the pool is skipped; the hero's role counts (a tank hero adds no
  tank); never exceeds five people; deterministic; empty pool.
- `suite_threat_rules`: tank within the pull range beats a nearer non-tank; a tank
  beyond the pull range loses; nearest wins with no tank; empty list; ties.
- `suite_encounter_logic`: heavy strike timing (due / not due), heavy damage scaling,
  the add phase fires once at 50% and not before, not twice.
- Extended: `suite_zone_table`, `suite_enemy_table`, `suite_loot_table`,
  `suite_codex_data`, `suite_ai_decision` (`dungeon_enter` priority: below flee/rest/
  combat/quest/job change, above chase; absent key unchanged), `suite_narrator_lines`.

Live check: entering through the gate builds a five-person party and teleports it to the
vault; the hero pushes through the rooms with the tank holding aggro; the boss warning
banner appears before the heavy strike; the add phase spawns wraiths; a clear returns the
party with loot and a banner; a forced hero death fails the run and restores everyone;
allies are released; no errors.
