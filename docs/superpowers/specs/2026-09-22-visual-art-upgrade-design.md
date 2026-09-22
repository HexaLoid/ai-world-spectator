# Visual Art Upgrade — Design

## Summary

Replace every placeholder `ColorRect` visual in the shipped v1 game (the
meadow background, the Character, the Wolf, the Bandit) with real 2D sprite
art in a classic "old-school 2D MMO" style — the look the player described
as "like Erenshor and Final Fantasy Online," scoped down to what's actually
achievable in 2D: real terrain instead of a flat green rectangle, and
animated character/enemy sprites instead of colored squares.

This is a **visual-layer-only** change. No gameplay code changes except
wiring each entity's existing `current_state` string to an animation name.
`AIDecision`, `CombatSystem`, `LevelingSystem`, `LootTable`, the FSM, all
`GameState` signals, and the UI logic are untouched.

## Goals

- Real terrain (grass, forest-edge border, paths) instead of one flat
  `ColorRect` background.
- Animated character sprites (idle/walk/attack, minimum) for the Character,
  Wolf, and Bandit instead of static colored squares.
- Sprites face/animate in the direction of movement.
- Correctly attributed, legally clean free art (no scraped/unlicensed
  assets).

## Non-Goals

- Any move to 3D (explicitly ruled out — this stays 2D top-down).
- New gameplay mechanics, animations beyond what's needed to represent the
  existing FSM states, or new enemy/item types.
- Full 8-directional sprite art. LPC sprites are 4-directional (up/down/
  left/right); diagonal movement will just show the nearest cardinal
  direction. Good enough for a top-down camera at this zoom level.
- Sound effects/music (out of scope for this pass; visual only).

## Asset Source

**[Liberated Pixel Cup (LPC)](https://lpc.opengameart.org)** — a mature,
long-maintained, internally-consistent 2D RPG/MMO art ecosystem hosted on
OpenGameArt.org. License: **CC-BY-SA 3.0** (free to use, requires
attribution, derivative art must stay under a compatible license — the
*game's code* is not a derivative work of the art assets, only re-edited
copies of the art itself would be, so this doesn't affect our GDScript).

Two source types:

1. **[Universal LPC Spritesheet
   Generator](https://sanderfrenken.github.io/Universal-LPC-Spritesheet-Character-Generator/)**
   (a browser tool, not a static download) — composes a humanoid character
   from body/clothing/hair/weapon layers and exports a clean, pre-aligned
   spritesheet already split by animation (walk, idle, slash, hurt, run,
   etc.), plus an auto-generated credits file. Used for the **Character**
   (player) and the **Bandit** (a human enemy).
2. **[LPC Tile Atlas](https://opengameart.org/content/lpc-tile-atlas)** for
   terrain, and a standalone **LPC wolf sprite** (found via OpenGameArt
   search, "[LPC] Wolf Animation") for the **Wolf** enemy, since the
   Universal Generator only composes humanoid bodies.

### Concrete asset choices

- **Character (player):** human male base body, simple tunic + pants
  (undyed/neutral color so it reads as "the protagonist," not
  faction-coded), a sword layer for the weapon-bearing animations.
- **Bandit:** human male base body, darker leather/rogue-style clothing, a
  dagger or short sword layer — visually distinct from the Character at a
  glance (darker palette) without needing a second skeleton/rig.
- **Wolf:** the standalone LPC wolf sprite sheet as-is (brown fur), no
  recoloring needed for v1.
- **Terrain:** LPC Tile Atlas's grass tile as the base fill, tree/forest
  tiles from the same atlas ringing the play area as the "forest edge"
  border described in the original design spec (replacing the current
  hard rectangle edge with a visual tree-line).

### Animation → game-state mapping

Both `Character` and `Enemy` already track a `current_state` string. Each
gets an `AnimatedSprite2D` (replacing the `ColorRect` child) whose playing
animation is driven by that state:

| FSM state | Animation played |
|---|---|
| `wander` | `walk` (slow) |
| `chase` | `walk` or `run` (LPC has both; use `run` for visual distinction from wander) |
| `combat` | `slash` (1-handed slash, on attack) / `idle` between swings |
| `flee` | `run` |
| `rest` | `idle` |
| `loot` | `walk` |
| (character/enemy dead, respawn window) | hide sprite, matches existing `visible = false` behavior — no death animation needed since nothing is shown during that window |

Facing direction: derive from `velocity`'s dominant axis (already computed
every frame for movement) and flip/select the corresponding LPC directional
row (LPC sheets are laid out as 4 rows: up/left/down/right).

## Architecture

### New files

```
/assets
  /sprites
    character_walk.png, character_idle.png, character_slash.png, character_run.png   (from LPC generator, split-by-animation export)
    bandit_walk.png, bandit_idle.png, bandit_slash.png, bandit_run.png               (from LPC generator, split-by-animation export)
    wolf_walk.png, wolf_attack.png (or whatever animations the LPC wolf sheet provides)
  /tiles
    lpc_terrain_atlas.png
  CREDITS.txt   (LPC attribution, auto-generated by the generator tool + manual entries for the tile atlas and wolf sprite authors)
```

### Modified files

- `scenes/entities/Character.tscn`, `Enemy.tscn` — swap the `ColorRect`
  child for an `AnimatedSprite2D` with a `SpriteFrames` resource built from
  the exported animation PNGs.
- `scripts/entities/character.gd`, `enemy.gd` — add a small
  `_update_animation()` step (called from `_physics_process`, after state
  resolution) that maps `current_state` + facing direction to the correct
  `AnimatedSprite2D.play(...)` call and `flip_h` where applicable. This is
  the only gameplay-code touch in this whole change.
- `scenes/world/ThornfieldMeadow.tscn` — replace the single `Background`
  `ColorRect` with a `TileMap` node using a `TileSet` built from the LPC
  terrain atlas (grass fill + tree border).
- `scripts/entities/spawn_point.gd` — the existing `color_override`
  mechanism (which recolors an `Enemy`'s `ColorRect`) no longer applies
  once enemies have real sprites. Since the Wolf and Bandit will now be
  *visually* distinct by sprite choice alone (different species/sheet),
  `color_override` becomes dead code and should be removed along with its
  export var and the `get_node("ColorRect")` call — not deprecated in
  place, since nothing will use it going forward and keeping unused
  per-spawn-point coloring logic around would be confusing.

## Risks / Open Questions

- **`TileSet` construction is normally a visual, in-editor task.** Godot's
  TileSet editor (slicing an atlas image into individual tiles, setting up
  the terrain/autotile rules for a clean forest-edge border) doesn't have
  a scripted equivalent in the Godot MCP toolset used throughout this
  project. This part of the work will most likely need to happen with the
  user driving the Godot 4.7 editor GUI directly (with guidance), rather
  than being fully automated the way every previous task in this project
  was. Character/Bandit/Wolf sprite wiring (`AnimatedSprite2D` +
  `SpriteFrames`), by contrast, is scriptable the same way everything else
  in this project has been built.
- **LPC generator is a live web tool, not a file the AI can query
  programmatically** — the exact layer/color selections need to be made by
  clicking through the tool's UI. This will be done via the browser tool,
  same as the research for this spec.

## How We'll Know This Is Done

Running the game shows a textured meadow with a visible tree-line border
instead of a flat green rectangle, and the Character/Wolf/Bandit are
recognizable, animated character sprites (not colored squares) that visibly
change animation and facing direction as they wander, chase, fight, and
flee — with `game_get_errors` clean and no change to any AI/combat
behavior already verified in the base game.
