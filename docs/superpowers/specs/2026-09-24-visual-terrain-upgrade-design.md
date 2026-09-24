# Visual Terrain Upgrade — Design

## Summary

Replaces every zone's flat solid-color `ColorRect` ground with real textured
terrain — grass, a cobbled dirt path, and a dungeon stone floor — plus
scattered decorative flowers/grass tufts/rocks, using the LPC terrain atlas
(`assets/tiles/lpc_terrain_atlas.png`) that has been sitting in the project
unused for terrain since the original visual-art upgrade (it was only used
for `tree_pine.png`). This is a pure visual pass — no gameplay, AI, or
system changes — aimed at making the world actually look like a world
instead of three colored rectangles joined by two more.

## Goals

- Real, tileable grass/dirt-path/stone-floor textures replacing the flat
  background color in all three zones and both corridors.
- Each zone visually distinct: Thornfield Meadow bright and lush,
  Blackthorn Forest darker/mossier, Sundered Crypt cold blue-grey stone.
- Scattered decorative props (flowers, grass tufts, rocks) so the ground
  doesn't read as a mechanically-repeated tile, using no gameplay systems
  (no collision, no interaction) — purely cosmetic.
- Reuse existing licensed art (the LPC atlas) rather than sourcing anything
  new, consistent with this project's art pipeline so far.

## Non-Goals

- No TileMap/TileSet with autotiling — the atlas's terrain art is laid out
  as irregular isometric/prop clusters, not a uniform autotile grid, and
  hand-configuring bitmask rules isn't practical without the editor GUI in
  this headless workflow. Flat, repeated textures via `texture_repeat`
  achieve the same visual goal far more simply.
- No water features, bridges, or structures from the atlas in this pass —
  the atlas has them (ponds, waterfalls, ruins), but extracting irregular
  shapes cleanly requires chroma-keying per-asset background colors, which
  is a separate, riskier effort than flat tileable textures. Left for a
  future pass if wanted.
- No changes to zone bounds, spawn points, or any gameplay-affecting
  geometry — every new node here is a non-colliding `Sprite2D`.

## Architecture

### New files

```
/assets/tiles
  terrain_grass.png    48x48, cropped from the LPC atlas's solid meadow-
                        grass block; tiles with only faint noise-level
                        seams, used (at different tints) for both outdoor
                        zones
  terrain_path.png      96x96, cropped from the atlas's cobbled-dirt
                        block; the visible tile border reads as natural
                        stone edging, used for both corridors
  terrain_stone.png     64x32, cropped from the atlas's flagstone block;
                        tiles perfectly seamlessly, used for the crypt floor
  decor_flowers.png, decor_rock.png, decor_grass_tuft.png
                        new ~12x12 pixel-art decorations (own art, same
                        technique as the ability/quest icons — not from
                        the atlas), scattered for visual variety
/scripts/world
  decoration_scatter.gd  attached to a "Decorations" node per zone;
                        places a random count of the given decoration
                        textures at random positions/scale/rotation within
                        an area — no collision, purely cosmetic
```

### Modified files

- `scenes/world/ThornfieldMeadow.tscn` / `BlackthornForest.tscn` /
  `SunderedCrypt.tscn` — each gains a `Ground` `Sprite2D` (the
  zone-appropriate terrain texture, `region_enabled`/`region_rect` sized to
  the zone and `texture_repeat = 2` (Enabled) so the small source texture
  tiles across the whole area) drawn on top of the existing `Background`
  `ColorRect` (kept as a fallback base color), plus a `Decorations` node
  running `decoration_scatter.gd`. Blackthorn Forest's `Ground` uses a
  darker/desaturated `modulate` on the *same* grass texture rather than a
  second asset — same technique already used for its tinted trees.
- `scenes/world/World.tscn` — both corridors gain a tiled `terrain_path.png`
  sprite layered over their existing `ColorRect`, with a `modulate` tint so
  the two corridors read as distinct (a warm dirt-road tone toward
  Blackthorn, a cooler grey tone toward the crypt).

### Draw order

`Ground` is added right after `Background` in each zone's scene tree, and
`Decorations` right after `Ground` — normal Node2D draw order (later
siblings on top) puts decorations above the ground and both below every
gameplay entity, since those are added dynamically under `Main` (a sibling
of `World`, added *after* it), never under `World` itself.

## Error Handling / Edge Cases

- `decoration_scatter.gd` no-ops immediately if `decoration_textures` is
  empty, so a zone that doesn't set it (there are none currently, but
  future zones might skip decorations) doesn't error.
- All new `Sprite2D`s have no `CollisionShape2D` (matching every other
  visual node in this project — the project has no collision shapes
  anywhere) and no script reading gameplay state, so this pass cannot
  affect movement, combat, or AI decisions even in principle.
- `texture_repeat` is set at the node level (`CanvasItem.texture_repeat`),
  which overrides the source texture's own default sampler setting
  regardless of import defaults — confirmed via live screenshot, not
  assumed.

## Testing / Validation

Live headless runs (Godot 4.7 under Xvfb), same method as every prior
milestone:

- A short smoke-test script teleporting the character/camera to each zone
  in turn confirmed all three terrains render and tile correctly
  (Sundered Crypt's stone floor tiles with zero visible seams; the grass
  and path textures have only faint, acceptable noise-level repetition),
  decorations scatter without overlapping gameplay UI, and Blackthorn
  Forest's darker tint is clearly distinguishable from Thornfield Meadow's
  brighter grass once adjusted (the first tint attempt was too subtle and
  was darkened after a visual check).
- A full ~2-minute unattended run afterward confirmed no regressions —
  zero `SCRIPT ERROR` lines, normal combat/quest/travel behavior
  throughout, matching every prior milestone's baseline.

## How We'll Know This Is Done

Every zone a spectator watches the AI move through has real ground texture
and scattered detail instead of a flat color fill, each zone is
recognizable by its terrain alone (bright meadow vs. dark forest vs. cold
crypt stone) even with the HUD hidden, and none of it changes how the AI
behaves or how combat/quests/loot work.
