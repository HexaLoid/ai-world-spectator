# Loot & Gear Depth — Design (Phase 1 of 4)

Date: 2026-09-25

## Context

The game is moving toward an Erenshor-style single-player MMO simulation. That
goal splits into four phases, each with its own spec, plan and build:

1. **Loot & gear depth** (this document)
2. Richer HUD & stats (character sheet, tooltips, target/party frames, combat log)
3. Simulated players / social (allies with classes and gear, party frames, chat lines)
4. World & content (more zones, enemies, quests, bosses, in-game bestiary)

Today the character has three equipment slots (weapon, armor, trinket), each
item carries a single stat, and there are 12 hand-written items. The AI walks
to every drop and logs "current gear is better" for most of them.

## Goals

- Six equipment slots (weapon, offhand, head, chest, neck, ring) with multi-stat items (about 27 items to start).
- The AI equips items by a class-weighted score, and explains each decision.
- The AI ignores ground items that cannot be upgrades.
- Enemies drop gold; the HUD shows a gold counter.
- Derived stats are recomputed from base + level + equipment, replacing the
  delta arithmetic in `Character._acquire_item`.

## Non-goals

- Inventory, bags or vendors (non-upgrades are simply not picked up).
- Procedural affixes / random stat rolls.
- Gear for simulated players (phase 3).
- Item tooltips and the character sheet (phase 2).

## Data model

**Slots:** `weapon`, `offhand`, `head`, `chest`, `neck`, `ring`. (Amended during planning: the project's icon pack has no leg or boot icons, so `legs`/`boots` became `offhand` (shields) and `neck`, and `trinket` became `ring`.)

**Item definition** (in `LootTable.ITEMS`, keyed by item id):

```
"iron_helm": {
    "slot": "head", "rarity": "uncommon", "level_req": 2,
    "icon": "res://assets/icons/...",
    "stats": {"armor": 2, "max_hp": 10}
}
```

Supported stat keys: `damage`, `armor`, `max_hp`, `crit_chance`, `strength`,
`intellect`. Consumables (e.g. `health_potion`) keep `"type": "consumable"` and
a `heal` value; they have no slot.

**Rarity rules are unchanged:** common / uncommon / rare / epic, with epic items
never rolling randomly (boss drops and quest rewards only, via
`guaranteed_drop_id` and quest reward ids).

**Character state:** `equipment: Dictionary` maps slot name to item id
(`""` when empty). It replaces `equipped_weapon_id`, `equipped_armor_id` and
`equipped_trinket_id`. Base stats (`base_max_hp`, `base_damage_min/max`) come
from class and level; everything else is derived.

Existing item ids are migrated: `rusty_sword`, `iron_sword`, `steel_sword`,
`warlords_greatsword` (weapon); `leather_armor`, `chainmail_armor`,
`champions_plate` (chest); `lucky_charm`, `amulet_of_wrath` (neck); `ring_of_fortune` (ring);
`crown_of_thornfield` (head). New offhand/head/neck/ring items are added, reusing
existing icon art where suitable and adding icons where needed (credited in
`assets/CREDITS.txt`).

## Decisions and loot behavior

**Scoring** — new `scripts/systems/item_scoring.gd`:
`score(item_def, class_def) = sum(stat_value * weight[stat])`, where per-class
weights live in `AbilityTable.CLASSES[class]["stat_weights"]`. A Warrior weights
damage, strength, armor and HP; a Mage weights damage, intellect and crit.

**Upgrade rule:** equip candidate C into slot S if the character's level is at
least `level_req` and `score(C) > score(current in S)` (an empty slot scores 0).

**Log lines explain the decision:**
- "Equipped Iron Helm (+2 armor, +10 HP)"
- "Received Steel Sword - needs level 5" (only possible for quest-reward items,
  which are handed over directly; ground drops that fail the level check are
  never walked to, see below)

**Ground-item targeting:** `_build_context()` sets `item_nearby` only for items
that are upgrades right now, potions when HP is below full, or gold. Items that
are not upgrades are ignored entirely, so the character stops walking to junk.
Items that fail only on level requirement are also ignored (no revisit logic).

**Gold:** enemies drop gold on death, scaled by enemy tier (small fixed ranges
in the enemy definition, with a boss multiplier). Gold is auto-collected like
other pickups, tracked as `gold: int` on the character, and emitted via a new
`GameState.gold_changed(amount)` signal.

## Stats in combat

- **Damage:** weapon `damage` adds to base damage; `strength` (Warrior) or
  `intellect` (Mage) adds 1% per point on top.
- **Armor:** incoming damage is `max(1, round(damage * 100 / (100 + armor * 4)))`.
  Applied only to damage the character receives; enemies are unchanged.
- **Max HP and crit:** as today, but read from the recomputed totals.
- **Level requirement:** enforced at equip time only.

## Architecture

- `scripts/systems/item_scoring.gd` (new): pure functions for scoring and
  upgrade decisions. No node access.
- `scripts/systems/stat_calculator.gd` (new): pure function computing derived
  stats from base stats, level and an equipment dictionary.
- `scripts/systems/loot_table.gd`: item list, rarity tables, drop rolling,
  `display_name()`. Loses `should_equip()` and `_stat_key_for_type()`.
- `scripts/entities/character.gd`: holds `equipment` and `gold`; `_acquire_item`
  reduces to "decide (via ItemScoring) → set slot → recompute stats → log →
  emit signal". Damage-taken path applies armor.
- `scripts/autoload/game_state.gd`: `character_equipment_changed(equipment: Dictionary)`
  and `gold_changed(amount: int)`.
- Enemy drop code: adds gold drops; guaranteed drops unchanged.
- `scenes/ui/SpectatorUI.tscn` + `scripts/ui/unit_frame.gd`: the three equipment
  rows become six slot icons with rarity-colored borders and a gold counter.

Call sites of the old `equipped_*_id` variables and the three-argument
`character_equipment_changed` signal (unit frame, quest rewards, respawn/reset
paths) are updated in the same change.

## Error handling

- Unknown item ids and malformed item definitions fail closed (never equipped,
  score 0), matching the current `should_equip` behavior.
- An item whose slot is missing or not one of the six slots is ignored with a
  `push_warning`.
- Armor mitigation never reduces damage below 1.

## Testing

The project has no test setup, so this phase adds a small headless runner
(`tests/run_tests.gd`, run with `godot --headless --script`) covering:

- `ItemScoring`: per-class scores, tie behavior, empty slot, unknown item.
- `StatCalculator`: derived stats for known equipment sets and levels.
- Armor mitigation formula, including the floor of 1.
- Level-requirement rule in the upgrade decision.
- Item-table validation: every item has a valid slot, rarity and icon path that
  exists.

Then a live check in the running game: gear fills all six slots over a run, no
"current gear is better" lines for ignored items, gold accrues, and the HUD
shows six slots and the gold counter with no errors in the log.

## Open items for later phases

- Phase 2 consumes `equipment` and item stats for tooltips and the character sheet.
- Phase 3 gives simulated players their own `equipment` and reuses `ItemScoring`.
- Phase 4 may add vendors that spend the gold tracked here.
