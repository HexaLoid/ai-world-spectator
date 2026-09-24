# Zone Landmarks — Design

## Summary

Each zone gets one distinctive structural landmark, on top of the terrain,
decorations, and water already in place: a wooden bridge arcing over
Thornfield Meadow's pond, a weathered stone archway standing alone in
Blackthorn Forest, and a dark gatehouse tower flanked by two torches
guarding the Sundered Crypt. All four sprites (bridge, archway, tower,
torch) were extracted from the same already-committed, already-attributed
LPC combined atlas (`assets/tiles/lpc_base_out_atlas.png`) used for this
project's character spritesheets — unlike the terrain atlas used for the
ground tiles, this atlas's individual props already carry real per-sprite
alpha transparency (confirmed by sampling: background pixels read
`(0,0,0,0)`), so no chroma-keying or background-box removal was needed,
just precise `Image.getbbox()`-driven cropping.

## Goals

- One clear, recognizable landmark per zone that reinforces what that zone
  already is: Thornfield's bridge is pastoral and functional-looking,
  Blackthorn's archway is quiet and mysterious (ruins in the woods),
  Sundered Crypt's tower-and-torches reads immediately as "dungeon
  entrance" the moment the character (or the boss) is standing in front of
  it.
- Zero new code — this is purely `.tscn`-level sprite placement (`Sprite2D`
  nodes with a texture, position, scale, and an optional tint), the same
  pattern every prior decoration/terrain milestone already established.
- Reuse the already-attributed atlas rather than introduce a new asset
  source or license to track.

## Non-Goals

- No collision — consistent with this project's "no collision shapes
  anywhere" convention (see the v1 design doc); the character can walk
  through the archway, tower, or bridge railing exactly like it walks
  through trees and rocks today. Purely visual.
- No new decoration_scatter.gd usage for these — each landmark is a single,
  deliberately hand-placed `Sprite2D`, not a randomly-scattered prop (same
  reasoning the pond milestone used: a feature this distinctive reads
  better placed on purpose than scattered).
- No additional atlas mining beyond these four sprites — the atlas has
  much more in it (a full cathedral, castle walls, wells, fences) that's
  out of scope for this pass; nothing stops a future milestone from pulling
  more from the same already-attributed source.

## Architecture

### New files

```
/assets/tiles
  ruin_bridge.png        84x44, wooden arch bridge, cropped from the LPC
                          base_out atlas via Image.getbbox() (no chroma-key
                          needed — real alpha transparency)
  ruin_archway.png        48x54, freestanding classical stone archway,
                          same atlas/method
  ruin_crypt_tower.png     92x121, dark stone gatehouse tower facade with a
                          window and an open doorway (the doorway's
                          transparent gap is part of the original sprite),
                          same atlas/method
  ruin_torch.png            8x74, single torch-on-a-pole, same atlas/method
                          (placed twice, flanking the crypt tower's
                          doorway)
```

### Modified files

- `scenes/world/ThornfieldMeadow.tscn` — new `Bridge` `Sprite2D`
  (`ruin_bridge.png`), positioned at the pond's center so it reads as
  crossing the water, added after `Pond` in the tree so it draws on top.
- `scenes/world/BlackthornForest.tscn` — new `RuinArchway` `Sprite2D`
  (`ruin_archway.png`), tinted slightly darker/desaturated
  (`Color(0.72, 0.78, 0.7, 1.0)`) to match the forest's existing shadowed
  palette, placed in open ground away from spawn points and the pond.
- `scenes/world/SunderedCrypt.tscn` — new `RuinTower` `Sprite2D`
  (`ruin_crypt_tower.png`) backing the north side of the room, plus
  `TorchLeft`/`TorchRight` `Sprite2D`s (`ruin_torch.png`) flanking its
  doorway — together they turn what was just an empty stone room with a
  boss standing in it into an actual "you have arrived at a gate" moment.

### Extraction method

A one-off Python/PIL script per sprite: crop a generous region around the
target sprite, call `Image.getbbox()` on the crop to get the tight alpha
bounding box (re-widening the crop and re-running when the bbox touched an
edge, meaning a neighboring sprite was still bleeding in), and save the
tightly-cropped result. This is the same "verify visually + iterate"
process used for the terrain tile crops in the earlier Visual Terrain
Upgrade milestone, just applied to prop sprites instead of tileable
ground textures.

## Error Handling / Edge Cases

- Every landmark is a plain `Sprite2D` with no script — nothing here can
  throw at runtime; the only failure mode would be a bad texture path,
  which is caught immediately (Godot logs a missing-resource error on
  scene load, and the earlier `--import` pass already confirmed all four
  files import cleanly).
- The crypt tower's silhouette slightly exceeds the room's 400x400
  background rect at its tallest point when scaled — accepted as a minor,
  purely cosmetic edge case (confirmed visually in a screenshot; nothing
  clips or errors, it just extends a few pixels past the inset margin).

## Testing / Validation

Live headless runs (Godot 4.7 under Xvfb), same method as every prior
milestone:

- A dedicated screenshot driver moved the camera directly to each
  landmark's position (bypassing AI movement, since these are static
  placements) and captured three screenshots — confirmed visually that the
  bridge correctly spans the pond, the archway stands cleanly in open
  forest ground with no overlap with existing decorations/spawn points,
  and the tower + both torches are symmetrically placed flanking the
  doorway with the Crypt Lord's spawn point right in front of it.
- A full live AI playthrough (90 real seconds at 4x speed, covering both
  outdoor zones, multiple kills, a level-up, and a full zone round-trip)
  produced zero `SCRIPT ERROR` lines with all three new landmarks in the
  scene tree.

## How We'll Know This Is Done

Each zone now has one unmistakable "this is a place, not just a colored
rectangle with monsters in it" landmark — a bridge, a ruin, a gate — visible
at a glance in a screenshot of that zone, with zero new code and zero
licensing risk beyond what this project already committed to.
