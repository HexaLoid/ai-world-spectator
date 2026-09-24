# Second Class: Mage — Design

## Summary

A second class, the Mage, with a genuinely different kit and resource
mechanic from the Warrior: no gap-closer, a Mana pool that regenerates
over downtime instead of draining from combat, and three new abilities
(Frost Nova, Arcane Bolt, Mana Ward) themed as a ranged/burst caster
against the Warrior's sustained melee brawler. Since this is a single
always-on spectator character with no class-select UI, which class the
session watches is decided once, randomly, at spawn — turning "which class
will it be this time?" into part of the spectator appeal, the same way a
fresh Erenshor/WoW alt run would.

This was flagged as future work in the very first Class & Abilities design
doc (`AbilityTable`'s own doc comment: "the CLASSES/ABILITIES split exists
so a second class can be added later without restructuring Character or
the HUD") — the data shape was already right; what hadn't actually been
built was the dispatch code to use it generically instead of hardcoding
warrior-specific ability ids.

## Goals

- A second class that plays differently, not just re-skinned numbers:
  Mana regenerates passively during downtime (rest/loot/wander) rather
  than being built by fighting or being hit, and the mage has no
  Charge-equivalent, so "chase" simply walks for it — a deliberate
  mobility/sustain tradeoff against the warrior.
- `Character`'s ability-triggering code becomes genuinely class-agnostic:
  it dispatches by each ability's declared `kind` and only ever considers
  ability ids in the active class's own `abilities` list — no per-class
  branching anywhere in `character.gd`.
- The HUD's ability bar shows exactly the active class's abilities (3 for
  the mage, 4 for the warrior) instead of a fixed warrior-shaped set of
  slots.
- A lightweight, low-risk visual identity for the mage (a cool blue sprite
  tint, a blue Mana-colored resource bar, a "Level N Mage"/"Level N
  Warrior" HUD label) rather than a whole new spritesheet/animation set.
- Random class selection at spawn, so replaying the game (or just letting
  a long session run) shows real variety without needing a character-select
  screen this single-character spectator game has no other use for.

## Non-Goals

- No class-select UI — out of scope for a single always-on character; a
  random roll is the natural fit here, not a limitation to work around.
- No new spritesheet/animation work — the mage reuses the exact same
  walk/run/slash frames as the warrior, reskinned only by tint. A real
  spellcast animation is a reasonable future pass, not this one.
- No ranged/projectile mechanics — "Arcane Bolt" still resolves as an
  instant hit once the target is in the same `ATTACK_RANGE` every class
  uses; there's no projectile travel time or distance-based targeting
  differences yet.
- No third class, no talent trees, no per-ability upgrades.

## Architecture

### Modified files

- `scripts/systems/ability_table.gd` — new `"mage"` entry in `CLASSES`
  (`resource_name: "Mana"`, `resource_regen_per_second: 6.0` instead of a
  decay rate, `sprite_tint`, `resource_color`, and its own `abilities`
  list); three new entries in `ABILITIES` (`frost_nova` — kind `"bleed"`,
  `arcane_bolt` — kind `"melee_hit"`, `mana_ward` — kind `"self_heal"`).
  `"warrior"` also gained explicit `sprite_tint`/`resource_color` fields
  (previously implicit via hardcoded defaults elsewhere) so both classes
  are defined the same way.
- `scripts/entities/character.gd` — the real work of this milestone:
  - `character_class`'s default changed from `"warrior"` to `""`;
    `_ready()` now rolls a random class from `AbilityTable.CLASSES.keys()`
    when it's empty (a scene can still force a specific class by
    overriding the export directly, which is how this milestone's own
    tests picked a class deterministically).
  - New `_find_class_ability_id(kind)` — the only place that scans a
    class's own `abilities` list for one matching a `kind`; every
    ability-triggering function now goes through it instead of a hardcoded
    ability id.
  - `_try_charge` → `_try_gap_closer`: looks up the class's `"gap_closer"`
    ability (if any) instead of hardcoding `"charge"`; returns `false`
    immediately for a class with none, so `"chase"` falls back to walking
    exactly as it already did when Charge was simply on cooldown.
  - `_try_combat_abilities`: now iterates the class's own `abilities` list
    in order, dispatching to `_use_bleed`/`_use_melee_hit` by `kind`
    instead of hardcoding `"rend"`/`"heroic_strike"` — this is what makes
    Frost Nova/Arcane Bolt fire for the mage with no new call sites.
  - `_try_second_wind` → `_try_self_heal`: same pattern, looks up the
    class's `"self_heal"` ability (Second Wind for the warrior, Mana Ward
    for the mage) instead of hardcoding `"second_wind"`. Also now actually
    calls `_spend_resource()` on cast — the original never needed to,
    since Second Wind's cost was 0, but Mana Ward's isn't.
  - `_use_rend`/`_use_heroic_strike` → `_use_bleed`/`_use_melee_hit`:
    same logic, just parameterized by `ability_id` instead of a hardcoded
    cooldown-tracking key, and their log lines now read the ability's own
    `name` (`"%s afflicts %s..."`/`"%s hits %s for %d!"`) instead of a
    hardcoded "Rend"/"Heroic Strike" string, so the same functions produce
    correct flavor text for either class's abilities.
  - `_decay_resource` → `_tick_resource`: now applies
    `resource_regen_per_second - resource_decay_per_second` together —
    both default to `0.0`, so the warrior (which only sets decay) behaves
    identically to before, and the mage (which only sets regen) gets
    passive Mana recovery for free from the same three call sites
    (rest/loot/wander) that already drove Rage's decay.
  - `_ready()` also sets `sprite.modulate` from `class_def.sprite_tint`.
- `scripts/ui/unit_frame.gd` — the resource bar's fill color is now read
  from `class_def.resource_color` (duplicating the shared `StyleBoxFlat` so
  this doesn't mutate anyone else's copy), and the level label now reads
  `"Level %d %s"` with the class name appended (`character_class.capitalize()`).
- `scenes/ui/SpectatorUI.tscn` — the `AbilityBar` no longer contains four
  hardcoded `AbilitySlot` children; it's now an empty `HBoxContainer` with
  `ability_bar.gd` attached, which builds the right number of slots at
  runtime from the active character's `class_def.abilities`.

### New files

- `scripts/ui/ability_bar.gd` — reads `GameState.character.class_def.abilities`
  once in `_ready()` and instantiates one `AbilitySlot.tscn` per entry, in
  order. Same "build children in code from data" pattern
  `decoration_scatter.gd` already established, applied here because the
  child *count* itself is now data-driven (3 for mage, 4 for warrior)
  where it previously never needed to be.
- `scenes/ui/AbilitySlot.tscn` — the `Panel`/`Icon`/`CooldownBar` structure
  that used to be hand-duplicated four times directly in `SpectatorUI.tscn`,
  extracted into its own instantiable scene.
- `assets/icons/arcane_bolt_icon.png`, `frost_nova_icon.png`,
  `mana_ward_icon.png` — new 32x32 pixel-art icons (PIL-generated, same
  flat-shape/black-outline style as the warrior's four existing ability
  icons): a blue lightning bolt, a six-point ice-blue snowflake, and a
  blue shield-in-badge (mirroring Second Wind's cross-in-badge look).

### Why `kind`-based dispatch instead of one big per-class `match`

The alternative — a `match character_class:` block inside every
ability-triggering function — would mean every future class change touches
`character.gd` itself. Dispatching by each ability's own `kind` (already
present in the data, just unused before this milestone) means
`character.gd` never needs to know a class by name; adding a third class
later is purely a data change in `ability_table.gd`, exactly the promise
the original v1 doc comment made.

## Error Handling / Edge Cases

- `_find_class_ability_id` returns `""` (not an error) when a class has no
  ability of that `kind` — `_try_gap_closer` treats that as "nothing to do,
  fall back to walking," never a crash or a stuck state.
- `_try_combat_abilities`'s loop naturally does nothing if every candidate
  ability is on cooldown or unaffordable that tick — identical to the
  original hardcoded rend-then-heroic-strike fallback-to-plain-auto-attack
  behavior, just generalized.
- A class with `resource_regen_per_second` unset defaults to `0.0` via
  `Dictionary.get()`, so `_tick_resource` never divides or branches on a
  missing key — same fail-closed style as every other data lookup in this
  project.

## Testing / Validation

Live headless runs (Godot 4.7 under Xvfb), same method as every prior
milestone:

- A direct test instantiated a real `Character` node for each class in
  turn (forcing `character_class` before it entered the tree, bypassing
  the random roll for determinism) with a minimal fake enemy stand-in, and
  called `_try_gap_closer`/`_try_combat_abilities`/`_try_self_heal`
  directly: confirmed the warrior's Charge fires and repositions correctly
  while the mage's gap-closer check correctly reports absent and does
  nothing; confirmed Rend/Frost Nova (bleed) and Heroic Strike/Arcane Bolt
  (melee_hit) both fire and apply the right effect; confirmed Second
  Wind/Mana Ward both heal, and that Mana Ward correctly spends 30 Mana
  where Second Wind (cost 0) doesn't touch the warrior's Rage.
- Ran the random-class roll six times in a row via separate process
  launches — got both `warrior` and `mage`, confirming it's genuinely
  randomized rather than silently defaulting to one class.
- A screenshot with the class forced to mage confirmed visually: the
  "Level 1 Mage" HUD label, the blue sprite tint, and exactly 3 ability
  bar slots (Frost Nova, Arcane Bolt, Mana Ward — no leftover Charge slot).
- A full live mage playthrough (60 real seconds at 6x speed) through two
  zones and a level-up showed Frost Nova and Arcane Bolt firing correctly
  in every fight, Mana draining while fighting and climbing back to
  100/100 during downtime, and zero `SCRIPT ERROR` lines.

## How We'll Know This Is Done

Launching the game now shows either a Warrior or a Mage, decided fresh
each time, each with a distinct resource rhythm, ability kit, and look —
and nothing about `Character`'s core loop had to learn a second class's
name to make that happen.
