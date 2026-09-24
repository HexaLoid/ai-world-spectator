# Day/Night Cycle — Design

## Summary

A slow, continuous ambient lighting cycle (dawn → day → dusk → night → dawn,
6 minutes per full loop) driven by a single `CanvasModulate` node under
`Main`. Pure ambiance — no gameplay, AI, or system changes — the next step
after the terrain upgrade toward a world that feels alive to watch rather
than a static diorama.

## Goals

- A continuous, looping lighting cycle with distinct dawn/day/dusk/night
  moods, each recognizable at a glance.
- The HUD stays fully readable at all times — only the world (terrain,
  character, enemies) is tinted, never the UI.
- Respects the existing pause/1x/2x/4x speed controls, consistent with
  every other timer in this project.

## Non-Goals

- No directional/point lighting, no shadows, no per-zone light sources —
  a single global multiplicative tint is enough for the "time is passing"
  effect this is going for.
- No gameplay effect (no reduced vision range, no night-only spawns) —
  purely cosmetic, matching the terrain upgrade's scope discipline.

## Architecture

### New files

```
/scripts/world
  day_night_cycle.gd   CanvasModulate script: accumulates delta (already
                        time_scale-scaled, same pattern as every other
                        timer here) into elapsed_ms, wraps it into a
                        0-1 fraction of CYCLE_DURATION_MS, and lerps
                        between ordered [time_fraction, Color] keyframes
```

### Modified files

- `scenes/Main.tscn` — a `DayNightCycle` `CanvasModulate` node added as a
  child of `Main` (the default 2D canvas), before `World`. `CanvasModulate`
  multiplicatively tints everything else in that same canvas — it does
  *not* affect `UI`, which is its own `CanvasLayer` and therefore a
  separate rendering layer entirely, so the HUD is unaffected by design,
  not by coincidence.

### Why a flat multiplicative tint instead of a TileMap-lighting approach

A single `CanvasModulate` is the simplest tool that achieves "the whole
scene visibly brightens/dims/tints over time" — no per-object light nodes,
no shadow casting to configure, nothing that could interact unpredictably
with the terrain/decoration sprites added in the previous pass. It's also
trivially not a source of new bugs: it only ever *reads* elapsed time and
*writes* its own `color` property, touching nothing else in the scene.

## Error Handling / Edge Cases

- `_tint_at()` falls back to the first keyframe's color if `t` somehow
  lands outside every keyframe span (shouldn't happen given the keyframes
  span the full `[0, 1]` range inclusive, but avoids an unhandled case
  either way).
- The night tint (`Color(0.45, 0.45, 0.68, 1.0)`) was chosen to be
  noticeably dimmer/cooler than day without ever making the scene hard to
  read — verified visually, not just by color math.

## Testing / Validation

Live headless runs (Godot 4.7 under Xvfb):

- Temporarily shortened `CYCLE_DURATION_MS` to 8s to observe several full
  cycles within a short test run; confirmed the tint correctly progresses
  through night → dawn → day → dusk → night and wraps cleanly, with
  screenshots confirming both the dusk (warm orange) and night (cool blue,
  still clearly legible) extremes look good over the new terrain, and the
  HUD stays crisp and unaffected throughout.
- Reverted to the real 360000ms (6 minute) duration and ran a further
  ~2.5 minute unattended session: zero `SCRIPT ERROR` lines, no
  regressions in combat/quest/travel behavior.

## How We'll Know This Is Done

The world visibly brightens and dims over time on its own, giving the
spectator experience an actual rhythm instead of a fixed lighting state,
without touching how the AI behaves or how any other system works.
