# Warrior Class & Abilities — Design

## Summary

The first "v2" milestone deferred by the original v1 design's Non-Goals
("Character classes, spells, or any ability beyond basic melee"). Gives the
AI character a class (Warrior) with a Rage resource and four abilities
layered on top of the existing plain-melee combat loop: **Charge** (gap
closer), **Rend** (bleed DoT), **Heroic Strike** (bonus-damage hit), and
**Second Wind** (self-heal cooldown used in place of always fleeing). The
goal is a visibly more interesting fight to spectate — the AI opens with a
charge, builds and spends Rage, and claws back from near-death instead of
just running — without touching the FSM's state-selection logic
(`AIDecision`), which stays a pure function.

## Goals

- A Rage resource that builds from dealing and taking melee damage, decays
  when out of combat, and gates ability use — visible in the HUD.
- Four abilities, each on its own cooldown, usable by the AI automatically
  (no player input, consistent with "no direct player control"):
  Charge/Rend/Heroic Strike/Second Wind.
- An ability bar in the HUD showing each ability's icon, a cooldown-sweep
  overlay, and dimming when unaffordable — so a spectator can see *why* the
  AI is or isn't using something, the same legibility goal the activity log
  already serves for state transitions.
- Data-driven ability definitions (`AbilityTable`), keyed by class, so a
  second class can be added later without restructuring `Character`.

## Non-Goals

- No class *selection* — one hardcoded class (`character_class = "warrior"`
  on `Character`) for this slice. `AbilityTable.CLASSES` is structured to
  hold more, but only `"warrior"` has an entry.
- No changes to `AIDecision`'s state-selection logic. Abilities are chosen
  by a separate, simple priority check inside `Character`'s existing
  per-state `_act()` branches, not by the FSM.
- No abilities for enemies — Wolves/Bandits keep their existing plain-melee
  AI. Only `Enemy` gains the ability to *receive* a bleed (`apply_bleed()`),
  not to cast anything itself.
- No new sprite/animation work. Abilities reuse the character's existing
  idle/walk/run/slash animations; ability icons are new 32x32 pixel-art PNGs
  (same size/style as the existing item icons) generated for this feature,
  not sourced from a pack.

## Architecture

### New files

```
/scripts/systems
  ability_table.gd     class_name AbilityTable; CLASSES (per-class resource
                        config) and ABILITIES (per-ability cost/cooldown/
                        effect data), same static-data pattern as LootTable
/scripts/ui
  ability_slot.gd       one HUD ability icon: loads its icon/cooldown from
                        AbilityTable, polls GameState.character each frame
                        for cooldown remaining + affordability
/assets/icons
  charge_icon.png, heroic_strike_icon.png, rend_icon.png,
  second_wind_icon.png  32x32 pixel-art icons matching the existing item
                        icons' style
```

### Modified files

- `scripts/autoload/game_state.gd` — new signal
  `character_resource_changed(resource_amount, max_resource)`, same pattern
  as `character_hp_changed`.
- `scripts/entities/character.gd`:
  - New state: `class_def` (this character's `AbilityTable.CLASSES` entry,
    resolved once in `_ready()`), `resource_amount`/`max_resource`,
    `ability_cooldowns: Dictionary` (ability id → game-time-ms it's next
    ready).
  - `_attack_nearest_hostile()` grants Rage on a landed swing;
    `take_damage()` grants Rage on a hit taken — both read their amount from
    `class_def`, not a hardcoded constant.
  - `_act()`'s `"chase"` branch tries `_try_charge()` before falling back to
    its existing walk-toward movement; `"combat"` calls
    `_try_combat_abilities()` after the normal auto-attack; `"flee"`/`"rest"`
    each call `_try_second_wind()` first. `"wander"`/`"loot"`/`"rest"` decay
    Rage over time (out-of-combat states).
  - `get_ability_cooldown_remaining(id)` is a public getter the HUD polls
    directly each frame — cooldown sweeps need continuous updates, not a
    discrete signal, the same reasoning `CameraController` already polls
    `GameState.character.global_position` directly instead of waiting on a
    signal.
- `scripts/entities/enemy.gd` — `apply_bleed(min, max, ticks, interval_ms)`
  plus the small per-instance bleed-tick state to process it in
  `_physics_process`. Lives on `Enemy` rather than a shared status-effect
  system since it's the only entity type that ever receives one here.
- `scripts/ui/unit_frame.gd` — `_on_resource_changed()` mirrors
  `_on_hp_changed()` for the new Rage bar; hides the bar if
  `max_resource <= 0` (future-proofing for a class with no resource).
- `scenes/ui/SpectatorUI.tscn` — a `ResourceBar` added to `UnitFrame` below
  the XP bar (Weapon/Armor rows shifted down, panel grown to fit); a new
  bottom-center `AbilityBar` (`HBoxContainer`) with four `Panel` slots
  (`Icon` + `CooldownBar` children each), one per ability, each running
  `ability_slot.gd` with its `ability_id` set in the scene.

### Ability resolution (per class)

Each combat-relevant `_act()` branch runs a fixed priority check rather than
a general planner, consistent with `AIDecision`'s own style:

1. **Chase**: Charge if off cooldown (its own state, no Rage cost — it
   *generates* Rage) — teleports to just outside melee range, logs, starts
   its cooldown. Otherwise, walk as before.
2. **Combat**: the existing auto-attack always fires on its own cooldown
   first (unchanged). Then: Rend if off cooldown and affordable (keeps
   uptime on the bleed), else Heroic Strike if off cooldown and affordable.
   Both are independent of the auto-attack's cooldown — layered on top of
   it, the way WoW abilities layer on top of auto-attack.
3. **Flee/Rest**: Second Wind if off cooldown (no Rage cost — a pure
   defensive cooldown), heals a percentage of max HP. Runs *before* the
   state's normal flee-movement/HP-regen, so if it pushes HP back above the
   flee threshold, next frame's `AIDecision` naturally exits flee/rest on
   its own — no direct interaction with the FSM needed.

### Data flow summary

```
character.gd _ready()
  -> class_def = AbilityTable.CLASSES[character_class]
  -> GameState.character_resource_changed(0, max_resource)
     -> unit_frame.gd sizes the Rage bar

character.gd _attack_nearest_hostile() / take_damage()
  -> _gain_resource(...) -> GameState.character_resource_changed(...)
     -> unit_frame.gd updates the Rage bar value

character.gd _try_charge() / _use_rend() / _use_heroic_strike() / _try_second_wind()
  -> GameState.log_event(...) (existing activity-log path, no new signal)
  -> ability_cooldowns[id] = game_time_ms + cooldown_ms

ability_slot.gd _process() (every frame, polling — not signal-driven)
  -> GameState.character.get_ability_cooldown_remaining(id)
  -> updates its own CooldownBar + icon dim state
```

## Error Handling / Edge Cases

- `_gain_resource()`/`_decay_resource()` no-op if `max_resource <= 0`
  (unset/unrecognized `character_class`) rather than dividing or comparing
  against zero.
- Death resets `resource_amount` to 0 and clears `ability_cooldowns` on
  respawn, so the character doesn't come back with abilities still on
  cooldown from the fight that killed it.
- Rend's bleed lives entirely on the `Enemy` instance; when it dies
  (`queue_free()`), the bleed state is destroyed with it — no dangling
  timer, no bleed carrying over to whatever respawns at that spawn point.
- A bleed tick that kills its target routes through the same `take_damage()`
  → `_die()` path as any other damage source (XP/loot drop, spawn-point
  respawn all still fire normally).
- `AbilityTable.ABILITIES.get(id, {})` with `.get(key, default)` throughout
  means a missing/malformed ability entry degrades to a no-cost, no-effect,
  always-off-cooldown no-op rather than erroring.

## Testing / Validation

Same manual/in-engine approach as v1 and the HUD upgrade — run the game
headless-under-Xvfb (as used throughout this project's QA) and confirm via
screenshots + `GameState` signal logging:

- Rage bar starts at 0 and rises as the character trades blows, visibly
  distinct in color from HP (red) and XP (gold).
- Charge fires when a chase begins (if off cooldown), moving the character
  to melee range in one frame and logging `"Charges at <name>!"`.
- Rend and Heroic Strike both fire during sustained combat, each respecting
  its own cooldown and Rage cost; floating damage numbers appear for
  Heroic Strike hits and for each bleed tick.
- Second Wind fires automatically once HP drops below the flee threshold
  (given its cooldown is up), healing a visible chunk of HP and logging
  `"Uses Second Wind - recovers N HP!"`.
- Ability bar icons dim while on cooldown or unaffordable and light back up
  when ready, tracking the same state `Character` reports via
  `get_ability_cooldown_remaining()`.
- A full unattended run still cycles through every FSM state without
  getting stuck, confirming the ability layer didn't regress the base loop.

## How We'll Know This Is Done

The AI character visibly fights like it has a kit, not just an auto-attack:
opening fights with a Charge, weaving Rend/Heroic Strike into its swings,
and using Second Wind instead of purely fleeing when it's a viable save —
all narrated in the activity log and visible on a Rage bar and ability bar
a spectator can actually read, with the underlying FSM state-selection
logic completely unchanged.
