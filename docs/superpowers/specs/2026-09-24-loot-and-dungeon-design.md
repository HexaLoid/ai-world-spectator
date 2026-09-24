# Loot & Dungeons — Design

## Summary

The fourth and final originally-scoped v2 milestone: rarity tiers on items
(color-coded in the HUD), a new Trinket gear slot with a crit-chance stat,
and **Sundered Crypt** — a small, level-gated dungeon room with a single
powerful boss (the Crypt Lord) that guarantees an epic weapon drop. This is
the "bigger power-fantasy loot moment" the other three zones/systems have
been building toward: a genuinely dangerous fight (the AI fled it mid-fight
before winning, in testing) that ends in a dramatic, guaranteed reward
rather than another random roll.

## Goals

- Rarity tiers (common/uncommon/rare/epic) on every item, shown as
  color-coded text in the HUD equipment slots.
- Epic items are never a random drop — only a guaranteed elite/boss kill
  or a quest reward, so finding one is always a specific, legible moment.
- A third gear slot (Trinket) with its own stat (crit_chance), reusing the
  existing equip-comparison system rather than inventing a parallel one.
- A compact, level-3-gated dungeon zone with one boss enemy, folded into
  the existing zone-travel rotation and quest system rather than needing
  new mechanics of their own.

## Non-Goals

- No inventory UI, no stacking/multiple trinkets, no new stat dimensions
  beyond crit_chance (no armor penetration, haste, etc.).
- No multi-boss dungeon, no dungeon-specific mechanics (phases, adds) —
  one enemy, one guaranteed drop, matching this project's consistent
  "small, legible vertical slice" scoping.
- No new creature art — the Crypt Lord is a tinted/scaled Bandit, same
  reskin technique as the Bandit Captain elite.

## Architecture

### New files

```
/scenes/world
  SunderedCrypt.tscn      a small (400x400 background, 360x360 playable
                          bounds) dark room with one SpawnPoint (Crypt
                          Lord: max_hp 150, guaranteed warlords_greatsword
                          drop, 90s respawn)
/assets/icons
  steel_sword_icon.png, warlords_greatsword_icon.png,
  chainmail_armor_icon.png, champions_plate_icon.png,
  lucky_charm_icon.png, ring_of_fortune_icon.png,
  amulet_of_wrath_icon.png   7 new pixel-art icons, same style/size as the
                          existing item icons
```

### Modified files

- `scripts/systems/loot_table.gd` — every item gains a `"rarity"` field;
  7 new items (rare/epic weapon+armor tiers, 3 trinkets). New
  `RARITY_WEIGHTS` (epic = weight 0, so `roll_drop()` — a weighted pick,
  not the old uniform one — never randomly rolls an epic) and
  `RARITY_COLORS`. `should_equip()`'s stat-key lookup extracted into
  `_stat_key_for_type()` and extended for `"trinket"` → `"crit_chance"`.
- `scripts/systems/zone_table.gd` — `sundered_crypt` zone entry
  (`min_level: 3`, a shorter `stay_duration_ms`, and its own small
  bounds); `next_zone_id()` now takes the character's `level` and skips
  zones it doesn't qualify for yet; `WORLD_BOUNDS_MAX` extended; new
  `stay_duration_ms(zone_id)` helper.
- `scripts/systems/quest_table.gd` — `"the_crypt_lord"` quest
  (min_level 3, rewards the epic `amulet_of_wrath` trinket), tying the
  dungeon into the existing quest rotation for free.
- `scripts/autoload/game_state.gd` — `character_equipment_changed` gains
  a third `trinket_id` parameter.
- `scripts/entities/character.gd`:
  - New state: `equipped_trinket_id`, `crit_chance`.
  - `_acquire_item()` gains a `"trinket"` branch (mirrors weapon/armor).
  - New `_roll_damage(min, max, multiplier)`: rolls base damage, then an
    independent crit check against `crit_chance`; a crit doubles the
    result. Both the plain auto-attack and Heroic Strike route through
    it instead of each rolling separately, so a trinket's crit chance
    applies identically everywhere character damage is rolled.
  - `_build_context()`/`_do_travel()` now pass `level` into
    `ZoneTable.next_zone_id()`, and `ready_to_travel` reads the current
    zone's own `stay_duration_ms` instead of one fixed constant.
- `scripts/ui/unit_frame.gd` — the weapon/armor/trinket update logic is
  unified into one `_update_equipment_slot()` helper (was two near-
  identical blocks, now three ways to reuse the same one) that also
  colors each label by `LootTable.RARITY_COLORS`.
- `scenes/ui/SpectatorUI.tscn` — a `TrinketIcon`/`TrinketLabel` row added
  to `UnitFrame`.
- `scenes/world/World.tscn` — `SunderedCrypt` instanced past Blackthorn
  Forest, joined by a second corridor.

### A bug found and fixed during live testing

The first version of `SunderedCrypt.tscn` reused the other zones' full
800x600 size with the boss's `aggro_range` at the same 180 default those
zones' regular enemies use. In testing, the character would cross into the
zone's *bounds* (which is what `_sync_current_zone()` treats as "arrival")
while still ~380 units from the boss at the exact center — well outside
aggro range — drop into `"wander"` (slow, random-direction movement), and
often burn through the zone's entire dwell timer without ever coming close
enough to fight it at all. Two live 5+ minute runs showed zero Crypt Lord
encounters before this was caught and fixed.

Fixed by shrinking the room to a 360x360 play area (worst-case corner-to-
center distance ~255) and raising the boss's own `aggro_range_override` to
280 — comfortably past that worst case, so the boss reliably notices the
character on every visit regardless of exactly where it crosses in.
Verified with a follow-up run: the Crypt Lord aggroed and engaged on both
zone visits.

### Data flow summary

```
enemy.gd _drop_loot() -> guaranteed_drop_id (if set) else LootTable.roll_drop()
  (roll_drop is now weighted by RARITY_WEIGHTS; epic weight 0 => never random)

character.gd _acquire_item(item_id) "trinket" branch
  -> crit_chance += new_bonus - old_bonus
  -> GameState.character_equipment_changed(weapon_id, armor_id, trinket_id)
     -> unit_frame.gd _update_equipment_slot() colors each label by rarity

character.gd _roll_damage(min, max, multiplier)
  -> base roll * multiplier, then independent crit check vs crit_chance
  -> used identically by _attack_nearest_hostile() and _use_heroic_strike()

character.gd _build_context() / _do_travel()
  -> ZoneTable.next_zone_id(current_zone_id, level) skips sundered_crypt
     until level >= 3
  -> ready_to_travel uses ZoneTable.stay_duration_ms(current_zone_id)
     (20s for the crypt, 45s default elsewhere)
```

## Error Handling / Edge Cases

- `roll_drop()` falls back to `max(total_weight, 1)` before rolling, so it
  can never divide by/roll against zero even if every item's weight were
  somehow zeroed out.
- Re-killing the Crypt Lord after already having its guaranteed drop
  correctly logs "current gear is better" rather than re-equipping —
  `should_equip()`'s `>` comparison (not `>=`) means an identical item
  never displaces itself.
- `ZoneTable.next_zone_id()`'s fallback (nothing eligible) still returns a
  valid zone id rather than erroring, same defensive shape as before this
  milestone.
- `_stat_key_for_type()` defaults to `"max_hp"` for any unrecognized type,
  so a malformed item degrades to an armor-shaped comparison rather than
  crashing on a missing key.

## Testing / Validation

Live headless runs (Godot 4.7 under Xvfb), same method as every prior
milestone — two ~5-minute runs, the first of which caught the aggro-range
bug above:

- Confirmed rarity-tiered items drop and equip correctly, with HUD labels
  colored grey/green/blue/purple matching common/uncommon/rare/epic.
- Confirmed the Trinket slot equips (`lucky_charm`) and `crit_chance`
  updates accordingly, read directly off the character's own state.
- Confirmed the character only travels to Sundered Crypt once it reaches
  level 3, correctly skipping it before then.
- Confirmed (after the fix) the Crypt Lord reliably aggros on arrival,
  fights a genuinely dangerous multi-phase battle (the character fled at
  low HP and re-engaged before winning), drops `warlords_greatsword` on
  first kill, and correctly declines to re-equip it as "already the best"
  on a second kill.
- No `SCRIPT ERROR` lines in either run.

## How We'll Know This Is Done

The AI's loot progression now has real texture instead of a flat item
list — a spectator can tell at a glance whether a drop is junk or
significant just from its color, a new equipment slot adds its own kind of
upgrade to chase, and reaching level 3 unlocks a genuinely tense, higher-
stakes fight against a named boss that always pays off with a guaranteed,
visibly special reward.
