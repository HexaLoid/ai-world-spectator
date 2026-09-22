# Visual Art Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every placeholder `ColorRect` visual (meadow background, Character, Wolf, Bandit) with real, animated LPC 2D sprite art, driven entirely by state/behavior the game already tracks — no gameplay logic changes beyond wiring animation names.

**Architecture:** Each entity gets an `AnimatedSprite2D` + a pre-built `SpriteFrames` `.tres` resource (constructed once via a throwaway `game_eval` script, not a permanent project file) in place of its `ColorRect`. A single shared animation-lookup helper (duplicated into `character.gd` and `enemy.gd`, matching this project's existing small-duplication convention) maps `<base animation>_<facing>` to a real animation name, falling back to a mirrored `_right` variant for entities (the Wolf) that don't have full 4-directional art. `SpawnPoint`'s existing sentinel-override pattern gets a new `sprite_frames_override` replacing the now-obsolete `color_override`.

**Tech Stack:** Godot 4.7 (mono), GDScript, LPC (Liberated Pixel Cup) CC-BY-SA 3.0 sprite/tile assets (already downloaded and committed).

**Spec:** [docs/superpowers/specs/2026-09-22-visual-art-upgrade-design.md](../specs/2026-09-22-visual-art-upgrade-design.md)

---

## Conventions and verified asset data

All of the following was independently verified by directly inspecting the downloaded PNGs (pixel dimensions confirmed via .NET `System.Drawing`, frame content confirmed by reading crops) — not assumed from documentation. Assets are already downloaded, committed, and credited (`assets/CREDITS.txt`); this plan only builds `SpriteFrames`/scene wiring on top of them.

**Character** (`assets/sprites/character/`) — human male, green tunic, sword:
| File | Size | Frame | Cols used | Rows |
|---|---|---|---|---|
| `walk.png` | 832×256 | 64×64 | 9 | 4 |
| `idle.png` | 832×256 | 64×64 | 2 | 4 |
| `run.png` | 832×256 | 64×64 | 8 | 4 |
| `slash.png` | 768×512 | **128×128** | 6 | 4 |

**Bandit** (`assets/sprites/bandit/`) — human male, dark clothes, dagger — identical grid to Character EXCEPT `slash.png` is 64×64 frames (the dagger has no enlarged-canvas variant, unlike the character's sword):
| File | Size | Frame | Cols used | Rows |
|---|---|---|---|---|
| `walk.png` | 832×256 | 64×64 | 9 | 4 |
| `idle.png` | 832×256 | 64×64 | 2 | 4 |
| `run.png` | 832×256 | 64×64 | 8 | 4 |
| `slash.png` | 832×256 | 64×64 | 6 | 4 |

Row order for both (LPC standard): **row 0 = up, row 1 = left, row 2 = down, row 3 = right**.

**Wolf** (`assets/sprites/wolf/wolf.png`, 640×384) — hand-packed, non-uniform sheet, no official frame manifest. Two regions independently confirmed clean by visual crop inspection (both 64×64 frames, single row each, right-facing only — this sheet has no distinct up/down poses):
- **Walk**: region `(320, 0, 256, 64)` → 4 frames of 64×64.
- **Combat** (bipedal rearing/threat pose — used as the attack animation since there's no clean bite-cycle row): region `(0, 0, 320, 64)` → 5 frames of 64×64.
- **Idle**: `assets/sprites/wolf/wolf_howl.png` (64×64, single standalone frame).

**Terrain**: the LPC Tile Atlas (`assets/tiles/lpc_terrain_atlas.png`) turned out to be prop/decoration-oriented (bushes, structures, paths) rather than having a clean seamless "flat grass ground" tile suitable for uniform `TileMap` fill — confirmed by visually scanning the full 1024×1024 atlas. **Decision: keep the meadow's `Background` `ColorRect` exactly as-is** (it already reads as grass-green) and add real tree sprites as scattered border decoration instead of building a `TileMap`/`TileSet`. This still delivers the spec's core visual goal (a real tree-line replacing the hard rectangle edge) without forcing a texture-tiling solution onto assets that aren't shaped for it, and it keeps this fully scriptable (no in-editor `TileSet` work needed, correcting the original spec's assumption that this would require manual editor work).
- **Tree**: `assets/tiles/tree_pine.png` — already cropped from the atlas region `(960, 0, 64, 160)`, confirmed transparent background (alpha-verified), 64×160px, ready to use directly as a standalone texture (no further slicing needed).

**Animation → behavior mapping** (both Character and Enemy):
| Behavior | Base animation |
|---|---|
| Moving slowly / no urgency (Character: `wander`, `loot`) | `walk` |
| Moving with urgency (Character: `chase`, `flee`; Enemy: closing distance) | `run` (Character/Bandit) — Wolf has no `run`, falls back to `walk` (see lookup logic) |
| Attacking (brief, on-hit only) | `slash` (Character/Bandit) / `combat` (Wolf) |
| Standing still, no target (Character: `rest`) | `idle` |

**On-screen size**: LPC frames are natively 64×64 (or 128×128 for the character's enlarged slash canvas). Both are scaled at runtime to a uniform `TARGET_SPRITE_SIZE = 40.0` px so switching between mixed-resolution animations doesn't visibly change the character's size (see Task 4/5's `_play_animation` helper — it computes `scale` from each animation's actual native frame size every time it plays, so this works automatically for any current or future animation regardless of source resolution).

---

### Task 1: Build the Character SpriteFrames resource and wire it into Character.tscn

**Files:**
- Create: `assets/sprites/character/character_frames.tres`
- Modify: `scenes/entities/Character.tscn`

- [ ] **Step 1: Build and save the SpriteFrames resource via game_eval**

Run: `mcp__godot__run_project`.

Run this exact GDScript via `mcp__godot__game_eval` (this is a one-time build step — the resulting `.tres` file is what gets committed, this script itself is never saved to the project):

```gdscript
var directions := ["up", "left", "down", "right"]
var sources := {
	"walk": {"path": "res://assets/sprites/character/walk.png", "frame_w": 64, "frame_h": 64, "cols": 9, "fps": 8.0, "loop": true},
	"idle": {"path": "res://assets/sprites/character/idle.png", "frame_w": 64, "frame_h": 64, "cols": 2, "fps": 2.0, "loop": true},
	"run": {"path": "res://assets/sprites/character/run.png", "frame_w": 64, "frame_h": 64, "cols": 8, "fps": 12.0, "loop": true},
	"slash": {"path": "res://assets/sprites/character/slash.png", "frame_w": 128, "frame_h": 128, "cols": 6, "fps": 12.0, "loop": false},
}
var frames := SpriteFrames.new()
frames.remove_animation("default")
for anim_name in sources.keys():
	var src: Dictionary = sources[anim_name]
	var tex: Texture2D = load(src["path"])
	for row in range(4):
		var full_name := "%s_%s" % [anim_name, directions[row]]
		frames.add_animation(full_name)
		frames.set_animation_loop(full_name, src["loop"])
		frames.set_animation_speed(full_name, src["fps"])
		for col in range(int(src["cols"])):
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(col * src["frame_w"], row * src["frame_h"], src["frame_w"], src["frame_h"])
			frames.add_frame(full_name, atlas)
var err := ResourceSaver.save(frames, "res://assets/sprites/character/character_frames.tres")
return {"save_err": err, "animation_names": frames.get_animation_names()}
```

Expected: `save_err` is `0` (OK), `animation_names` contains 16 entries (`walk_up`, `walk_left`, `walk_down`, `walk_right`, `idle_up`, ..., `run_up`, ..., `slash_up`, ...).

- [ ] **Step 2: Verify the saved resource loads and has correct frame counts**

Run via `game_eval`:

```gdscript
var frames: SpriteFrames = load("res://assets/sprites/character/character_frames.tres")
return {
	"walk_down_count": frames.get_frame_count("walk_down"),
	"idle_down_count": frames.get_frame_count("idle_down"),
	"run_down_count": frames.get_frame_count("run_down"),
	"slash_down_count": frames.get_frame_count("slash_down"),
	"slash_loop": frames.get_animation_loop("slash_down"),
}
```

Expected: `walk_down_count: 9`, `idle_down_count: 2`, `run_down_count: 8`, `slash_down_count: 6`, `slash_loop: false`.

- [ ] **Step 3: Replace Character.tscn's ColorRect with an AnimatedSprite2D**

Read `scenes/entities/Character.tscn` first (current content: `CharacterBody2D` root with script attached, one `ColorRect` child). Hand-edit it via `mcp__godot__write_file` (do NOT use `add_node`/`attach_script`/`save_scene` — this script references the `GameState` autoload, which those tools are confirmed throughout this project to fail on) to:
- Remove the `ColorRect` node block entirely.
- Add an `ext_resource` for `res://assets/sprites/character/character_frames.tres` (type `SpriteFrames`).
- Add a new child node: `[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]` with `sprite_frames = ExtResource("<id>")` and `animation = &"idle_down"`.

Resulting file should look like:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/entities/character.gd" id="1_chscr"]
[ext_resource type="SpriteFrames" path="res://assets/sprites/character/character_frames.tres" id="2_frames"]

[node name="root" type="CharacterBody2D"]
script = ExtResource("1_chscr")

[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]
sprite_frames = ExtResource("2_frames")
animation = &"idle_down"
```

(Root node name may already be `root` or `Character` from prior work — read the actual file first and preserve whatever it currently is; don't rename it. No `unique_id` attribute anywhere, per this project's established convention.)

- [ ] **Step 4: Verify visually and confirm animation playback actually advances frames**

Run: `mcp__godot__run_project` (full `Main.tscn`).
Run via `game_eval`:

```gdscript
var char_sprite: AnimatedSprite2D = GameState.character.get_node("AnimatedSprite2D")
char_sprite.play("walk_down")
var frame1 := char_sprite.frame
await get_tree().create_timer(0.5).timeout
var frame2 := char_sprite.frame
return {"frame1": frame1, "frame2": frame2, "still_playing": char_sprite.is_playing()}
```

Expected: `frame1 != frame2` (confirms calling `.play()` on an already-playing animation does NOT reset it to frame 0 every time — this matters a lot since the actual game code will call `.play()` every physics frame; `still_playing: true`.

Run: `mcp__godot__game_screenshot`. Expected: character now renders as the green-tunic sprite (not a blue square) at roughly the same on-screen size as before.
Run: `mcp__godot__game_get_errors`. Expected: clean or known harness noise only.
Run: `mcp__godot__stop_project`.

- [ ] **Step 5: Commit**

Check `git status`/`git diff` on `project.godot` first and discard any run/stop drift (`git checkout -- project.godot`) — this task doesn't touch that file.

```bash
git add assets/sprites/character/character_frames.tres scenes/entities/Character.tscn
git commit -m "$(cat <<'EOF'
Replace Character's ColorRect with an animated LPC sprite

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Build the Bandit SpriteFrames resource

**Files:**
- Create: `assets/sprites/bandit/bandit_frames.tres`

- [ ] **Step 1: Build and save via game_eval**

Run: `mcp__godot__run_project`. Run via `game_eval` (note: `slash` here is 64×64, not 128×128 like the character's — see the verified table above):

```gdscript
var directions := ["up", "left", "down", "right"]
var sources := {
	"walk": {"path": "res://assets/sprites/bandit/walk.png", "frame_w": 64, "frame_h": 64, "cols": 9, "fps": 8.0, "loop": true},
	"idle": {"path": "res://assets/sprites/bandit/idle.png", "frame_w": 64, "frame_h": 64, "cols": 2, "fps": 2.0, "loop": true},
	"run": {"path": "res://assets/sprites/bandit/run.png", "frame_w": 64, "frame_h": 64, "cols": 8, "fps": 12.0, "loop": true},
	"slash": {"path": "res://assets/sprites/bandit/slash.png", "frame_w": 64, "frame_h": 64, "cols": 6, "fps": 12.0, "loop": false},
}
var frames := SpriteFrames.new()
frames.remove_animation("default")
for anim_name in sources.keys():
	var src: Dictionary = sources[anim_name]
	var tex: Texture2D = load(src["path"])
	for row in range(4):
		var full_name := "%s_%s" % [anim_name, directions[row]]
		frames.add_animation(full_name)
		frames.set_animation_loop(full_name, src["loop"])
		frames.set_animation_speed(full_name, src["fps"])
		for col in range(int(src["cols"])):
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(col * src["frame_w"], row * src["frame_h"], src["frame_w"], src["frame_h"])
			frames.add_frame(full_name, atlas)
var err := ResourceSaver.save(frames, "res://assets/sprites/bandit/bandit_frames.tres")
return {"save_err": err, "animation_names": frames.get_animation_names()}
```

Expected: `save_err: 0`, 16 animation names.

- [ ] **Step 2: Verify frame counts**

```gdscript
var frames: SpriteFrames = load("res://assets/sprites/bandit/bandit_frames.tres")
return {
	"walk_down_count": frames.get_frame_count("walk_down"),
	"slash_down_count": frames.get_frame_count("slash_down"),
}
```

Expected: `walk_down_count: 9`, `slash_down_count: 6`.

Run `game_get_errors` (clean/known-noise), `stop_project`.

- [ ] **Step 3: Commit**

Clean up `project.godot` drift first.

```bash
git add assets/sprites/bandit/bandit_frames.tres
git commit -m "$(cat <<'EOF'
Build Bandit SpriteFrames resource from LPC sprites

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Build the Wolf SpriteFrames resource and wire a default sprite into Enemy.tscn

**Files:**
- Create: `assets/sprites/wolf/wolf_frames.tres`
- Modify: `scenes/entities/Enemy.tscn`

- [ ] **Step 1: Build and save via game_eval**

The wolf sheet has no directional rows — only `_right`-suffixed animations are created; `enemy.gd`'s lookup helper (Task 5) falls back to these (mirrored via `flip_h` for left, unmirrored for up/down) for any facing that isn't `right`.

Run: `mcp__godot__run_project`. Run via `game_eval`:

```gdscript
var frames := SpriteFrames.new()
frames.remove_animation("default")

var walk_tex: Texture2D = load("res://assets/sprites/wolf/wolf.png")
frames.add_animation("walk_right")
frames.set_animation_loop("walk_right", true)
frames.set_animation_speed("walk_right", 8.0)
for col in range(4):
	var atlas := AtlasTexture.new()
	atlas.atlas = walk_tex
	atlas.region = Rect2(320 + col * 64, 0, 64, 64)
	frames.add_frame("walk_right", atlas)

frames.add_animation("combat_right")
frames.set_animation_loop("combat_right", false)
frames.set_animation_speed("combat_right", 10.0)
for col in range(5):
	var atlas2 := AtlasTexture.new()
	atlas2.atlas = walk_tex
	atlas2.region = Rect2(col * 64, 0, 64, 64)
	frames.add_frame("combat_right", atlas2)

var idle_tex: Texture2D = load("res://assets/sprites/wolf/wolf_howl.png")
frames.add_animation("idle_right")
frames.set_animation_loop("idle_right", true)
frames.set_animation_speed("idle_right", 2.0)
var idle_atlas := AtlasTexture.new()
idle_atlas.atlas = idle_tex
idle_atlas.region = Rect2(0, 0, 64, 64)
frames.add_frame("idle_right", idle_atlas)

var err := ResourceSaver.save(frames, "res://assets/sprites/wolf/wolf_frames.tres")
return {"save_err": err, "animation_names": frames.get_animation_names()}
```

Expected: `save_err: 0`, `animation_names` = `["walk_right", "combat_right", "idle_right"]` (order may vary).

- [ ] **Step 2: Verify frame counts and take a screenshot sanity-check of the walk frames specifically**

```gdscript
var frames: SpriteFrames = load("res://assets/sprites/wolf/wolf_frames.tres")
return {
	"walk_count": frames.get_frame_count("walk_right"),
	"combat_count": frames.get_frame_count("combat_right"),
	"idle_count": frames.get_frame_count("idle_right"),
}
```

Expected: `walk_count: 4`, `combat_count: 5`, `idle_count: 1`.

Then spawn a temporary AnimatedSprite2D using this resource to visually confirm the `walk_right` frames actually show a clean running wolf with no visible sliver of an adjacent row bleeding in at the bottom edge (this was flagged as a known risk during asset acquisition — the row-height guess of 64px might clip slightly into the next row):

```gdscript
var probe := AnimatedSprite2D.new()
probe.sprite_frames = load("res://assets/sprites/wolf/wolf_frames.tres")
probe.animation = "walk_right"
probe.frame = 0
probe.position = Vector2(0, -100)
probe.scale = Vector2(4, 4)
get_tree().current_scene.add_child(probe)
return "spawned probe at (0,-100), 4x scale — screenshot next"
```

Run `mcp__godot__game_screenshot`. **Look closely at the cropped frame**: if you see a sliver of another wolf's feet/legs at the very bottom edge of the frame, the row height needs adjusting — redo Step 1 with `region = Rect2(320 + col * 64, 0, 64, 56)` (or another height that visually crops cleanly) for the `walk_right` animation only, re-save, and re-check. If it looks clean, proceed as-is.

Remove the probe: `get_tree().current_scene.remove_child(probe); probe.queue_free()` via `game_eval`, or just `stop_project` (the probe was never added to any scene file, so stopping the project discards it).

Run `game_get_errors` (clean/known-noise), `stop_project`.

- [ ] **Step 3: Add a default AnimatedSprite2D to Enemy.tscn**

Read `scenes/entities/Enemy.tscn` first (current content: `CharacterBody2D` root named `Enemy` with script attached, one `ColorRect` child). Hand-edit via `write_file` (same reasoning as Task 1 Step 3 — `enemy.gd` references `GameState`) to remove the `ColorRect` and add an `AnimatedSprite2D` defaulting to the wolf frames (this is just the scene's static default; `SpawnPoint` will override it to `bandit_frames.tres` for Bandit spawn points in Task 6):

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/entities/enemy.gd" id="1_enemyscr"]
[ext_resource type="SpriteFrames" path="res://assets/sprites/wolf/wolf_frames.tres" id="2_frames"]

[node name="Enemy" type="CharacterBody2D"]
script = ExtResource("1_enemyscr")

[node name="AnimatedSprite2D" type="AnimatedSprite2D" parent="."]
sprite_frames = ExtResource("2_frames")
animation = &"idle_right"
```

(Preserve whatever the root node is actually named if it differs — read first, don't assume.)

- [ ] **Step 4: Verify it loads without error**

Run `mcp__godot__run_project` (full game). Run `game_get_errors` (clean/known-noise — the 3 spawned enemies in Thornfield Meadow will now show the wolf sprite by default since `SpawnPoint`'s override isn't wired up until Task 6, that's expected at this point). Run `mcp__godot__game_screenshot` to confirm no crash/missing-texture pink-and-black checkerboard. Run `stop_project`.

- [ ] **Step 5: Commit**

Clean up `project.godot` drift first.

```bash
git add assets/sprites/wolf/wolf_frames.tres scenes/entities/Enemy.tscn
git commit -m "$(cat <<'EOF'
Build Wolf SpriteFrames resource and default Enemy.tscn to it

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Wire animation state into character.gd

**Files:**
- Modify: `scripts/entities/character.gd`

- [ ] **Step 1: Add the animation fields, helper, and calls**

Read the current full file first (`scripts/entities/character.gd`) to confirm line numbers before editing — it was last touched by the `time_scale` fix (adds `game_time_ms`/`hp_regen_accumulator`) and the weapon/armor/death-reentrancy fixes, so don't assume the exact current content, verify it.

Add these additions (shown as a diff against the current file — apply precisely, don't restate unrelated parts):

1. Add near the top, after the existing `const`s:
```gdscript
const TARGET_SPRITE_SIZE := 40.0
const ATTACK_ANIM_DURATION_MS := 400.0
```

2. Add near the other `var` declarations:
```gdscript
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var attack_anim_until_ms: float = 0.0
```

3. Add these two new functions (anywhere after `_ready()`, e.g. right before `_build_context()`):

```gdscript
func _facing_from_velocity(vel: Vector2) -> String:
	if vel.length() < 1.0:
		return "down"
	if abs(vel.x) > abs(vel.y):
		return "right" if vel.x > 0.0 else "left"
	return "down" if vel.y > 0.0 else "up"

func _play_animation(base: String, facing: String) -> void:
	if sprite.sprite_frames == null:
		return
	var anim_name := base + "_" + facing
	var mirrored := false
	if not sprite.sprite_frames.has_animation(anim_name):
		var fallback := base + "_right"
		if not sprite.sprite_frames.has_animation(fallback):
			return
		anim_name = fallback
		mirrored = facing == "left"
	sprite.flip_h = mirrored
	if sprite.animation != anim_name or not sprite.is_playing():
		sprite.play(anim_name)
	var first_frame := sprite.sprite_frames.get_frame_texture(anim_name, 0)
	if first_frame:
		var native_size: Vector2 = first_frame.get_size()
		if native_size.x > 0.0 and native_size.y > 0.0:
			var s := TARGET_SPRITE_SIZE / max(native_size.x, native_size.y)
			sprite.scale = Vector2(s, s)
```

4. Add a call to update the animation at the end of `_act(delta, context)` (after the existing `match current_state:` block finishes — i.e. as the last lines of that function, still inside `_act`, not inside the `match`):

```gdscript
	var facing := _facing_from_velocity(velocity)
	var base_anim := "idle"
	match current_state:
		"wander", "loot":
			base_anim = "walk"
		"chase", "flee":
			base_anim = "run"
		"combat":
			base_anim = "idle"
		"rest":
			base_anim = "idle"
	if game_time_ms < attack_anim_until_ms:
		base_anim = "slash"
	_play_animation(base_anim, facing)
```

5. In `_attack_nearest_hostile()`, right after the line `hostile.take_damage(damage)`, add:
```gdscript
	attack_anim_until_ms = game_time_ms + ATTACK_ANIM_DURATION_MS
```

- [ ] **Step 2: Verify the file is syntactically valid and the character still functions**

Run `mcp__godot__run_project` (full game). Run `game_eval`:

```gdscript
return {"char_exists": GameState.character != null, "state": GameState.character.current_state, "sprite_anim": GameState.character.sprite.animation}
```

Expected: `char_exists: true`, `sprite_anim` is a real animation name like `"walk_down"` or `"idle_down"` (not empty/null).

- [ ] **Step 3: Verify the animation actually changes across different states and facing directions**

Let the game run for ~10-15 real seconds (combat should occur naturally given 3 enemies exist) using `game_eval` with an `await get_tree().create_timer(...)` or repeated short waits, then read `GameState.character.sprite.animation` a few times across the observation window and confirm it's not stuck on one value — you should see it vary between something like `walk_*`, `run_*`, `idle_*`, and (briefly, right after an attack lands) `slash_*`.

Take a `mcp__godot__game_screenshot` during active combat if possible and visually confirm the character sprite is facing/animating sensibly relative to its movement.

Run `game_get_errors` (clean/known-noise), `stop_project`.

- [ ] **Step 4: Commit**

Clean up `project.godot` drift first.

```bash
git add scripts/entities/character.gd
git commit -m "$(cat <<'EOF'
Drive Character's sprite animation from FSM state and facing

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Wire animation state into enemy.gd

**Files:**
- Modify: `scripts/entities/enemy.gd`

- [ ] **Step 1: Add the same pattern to enemy.gd**

Read the current full file first (`scripts/entities/enemy.gd`) — it was last touched by the reentrancy-guard fix and the `time_scale` fix (`game_time_ms`), confirm exact current content before editing.

1. Add near the top, after the existing `const`s (there likely are none at the top of this file yet beyond what's in the export block — check):
```gdscript
const TARGET_SPRITE_SIZE := 40.0
const ATTACK_ANIM_DURATION_MS := 400.0
```

2. Add near the other `var` declarations:
```gdscript
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var attack_anim_until_ms: float = 0.0
```

3. Add these two functions (same as Character's, unchanged — this is the accepted small duplication consistent with this project's existing pattern for `game_time_ms`):

```gdscript
func _facing_from_velocity(vel: Vector2) -> String:
	if vel.length() < 1.0:
		return "down"
	if abs(vel.x) > abs(vel.y):
		return "right" if vel.x > 0.0 else "left"
	return "down" if vel.y > 0.0 else "up"

func _play_animation(base: String, facing: String) -> void:
	if sprite.sprite_frames == null:
		return
	var anim_name := base + "_" + facing
	var mirrored := false
	if not sprite.sprite_frames.has_animation(anim_name):
		var fallback := base + "_right"
		if not sprite.sprite_frames.has_animation(fallback):
			return
		anim_name = fallback
		mirrored = facing == "left"
	sprite.flip_h = mirrored
	if sprite.animation != anim_name or not sprite.is_playing():
		sprite.play(anim_name)
	var first_frame := sprite.sprite_frames.get_frame_texture(anim_name, 0)
	if first_frame:
		var native_size: Vector2 = first_frame.get_size()
		if native_size.x > 0.0 and native_size.y > 0.0:
			var s := TARGET_SPRITE_SIZE / max(native_size.x, native_size.y)
			sprite.scale = Vector2(s, s)
```

4. In `_physics_process`, add an animation update at the end of the function (after the existing `if/elif/else` distance-branch block, still inside `_physics_process`):

```gdscript
	var facing := _facing_from_velocity(velocity)
	var base_anim := "idle" if velocity.length() < 1.0 else "walk"
	if game_time_ms < attack_anim_until_ms:
		base_anim = "combat"
	_play_animation(base_anim, facing)
```

5. In `_attack(character)`, right after the line `character.take_damage(damage)`, add:
```gdscript
	attack_anim_until_ms = game_time_ms + ATTACK_ANIM_DURATION_MS
```

- [ ] **Step 2: Verify**

Run `mcp__godot__run_project`. Run `game_eval`:

```gdscript
var enemies = get_tree().get_nodes_in_group("enemies")
var result = []
for e in enemies:
	result.append({"name": e.enemy_name, "sprite_anim": e.sprite.animation})
return result
```

Expected: each entry has a non-empty `sprite_anim` (e.g. `"idle_right"` since all enemies default to wolf frames at this point in the plan — Task 6 wires Bandit's real frames in).

Let combat occur naturally (or use `take_damage`/positioning tricks from earlier tasks' verification patterns if needed) and confirm at least one enemy's `sprite_anim` becomes `"combat_right"` briefly during an attack, then reverts.

Run `game_get_errors` (clean/known-noise), `stop_project`.

- [ ] **Step 3: Commit**

Clean up `project.godot` drift first.

```bash
git add scripts/entities/enemy.gd
git commit -m "$(cat <<'EOF'
Drive Enemy's sprite animation from movement/attack state

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Replace SpawnPoint's color_override with sprite_frames_override

**Files:**
- Modify: `scripts/entities/spawn_point.gd`
- Modify: `scenes/world/ThornfieldMeadow.tscn`

- [ ] **Step 1: Update spawn_point.gd**

Read the current full file first (last touched by the `aggro_range_override` addition and `unique_id` cleanup). Replace the `color_override` export and its application branch with a `sprite_frames_override`:

Remove:
```gdscript
@export var color_override: Color = Color.WHITE
```
and remove the branch:
```gdscript
	if color_override != Color.WHITE:
		# Assumes enemy_scene's root has a child literally named "ColorRect"
		# (true of Enemy.tscn today) — a rename there would break this silently.
		current_enemy.get_node("ColorRect").color = color_override
```

Add, in the export block (same position `color_override` was in):
```gdscript
@export var sprite_frames_override: SpriteFrames = null
```

Add, in `_spawn()` (same position the removed branch was in, before the final `get_tree().current_scene.add_child.call_deferred(current_enemy)` line):
```gdscript
	if sprite_frames_override != null:
		current_enemy.get_node("AnimatedSprite2D").sprite_frames = sprite_frames_override
```

- [ ] **Step 2: Verify it loads without error**

Run `mcp__godot__run_project` (full game — note: at this point `ThornfieldMeadow.tscn` still has the OLD `color_override` properties on its `SpawnPoint` nodes, which no longer exist on the script; Godot will just silently drop unknown properties when loading a scene with stale exported values, this is expected and harmless, Step 3 fixes it). Run `game_get_errors` — expect no NEW errors (Godot may log a benign "property not found" info/warning for the stale `color_override` values still in the `.tscn`, which is fine and gets removed in Step 3). Run `stop_project`.

- [ ] **Step 3: Update ThornfieldMeadow.tscn's SpawnPoint instances**

Read `scenes/world/ThornfieldMeadow.tscn`. It has 3 `SpawnPoint` instances (`SpawnPointWolf1`, `SpawnPointWolf2`, `SpawnPointBandit1`), each currently with a `color_override = Color(...)` line. Hand-edit via `write_file`:

- Remove all 3 `color_override = Color(...)` lines.
- Add 2 new `ext_resource` entries at the top (bump `load_steps` accordingly): one for `res://assets/sprites/wolf/wolf_frames.tres`, one for `res://assets/sprites/bandit/bandit_frames.tres`.
- Add `sprite_frames_override = ExtResource("<wolf_frames_id>")` to both `SpawnPointWolf1` and `SpawnPointWolf2`.
- Add `sprite_frames_override = ExtResource("<bandit_frames_id>")` to `SpawnPointBandit1`.

All other properties (positions, `enemy_name_override`, `max_hp_override`, etc.) stay exactly as they are — only the color→sprite_frames swap changes.

- [ ] **Step 4: Verify enemies spawn with the correct distinct sprites**

Run `mcp__godot__run_project`. Run `game_eval`:

```gdscript
var enemies = get_tree().get_nodes_in_group("enemies")
var result = []
for e in enemies:
	var frames: SpriteFrames = e.get_node("AnimatedSprite2D").sprite_frames
	result.append({"name": e.enemy_name, "has_run_anim": frames.has_animation("walk_down")})
result.sort_custom(func(a, b): return a["name"] < b["name"])
return result
```

Expected: the `Bandit` entry has `has_run_anim: true` (bandit frames are 4-directional, `walk_down` exists), both `Wolf` entries have `has_run_anim: false` (wolf frames only have `walk_right`, not `walk_down`) — this confirms each enemy type got its OWN distinct `SpriteFrames` resource, not a shared/default one.

Take a `mcp__godot__game_screenshot` and visually confirm the wolves and the bandit now look like their respective sprites (animal vs. human), not identical.

Run `game_get_errors` (clean/known-noise), `stop_project`.

- [ ] **Step 5: Commit**

Clean up `project.godot` drift first.

```bash
git add scripts/entities/spawn_point.gd scenes/world/ThornfieldMeadow.tscn
git commit -m "$(cat <<'EOF'
Replace SpawnPoint's color_override with sprite_frames_override

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Add a tree-line border to Thornfield Meadow

**Files:**
- Modify: `scenes/world/ThornfieldMeadow.tscn`

- [ ] **Step 1: Add tree Sprite2D decorations around the meadow's perimeter**

The meadow's `Background` `ColorRect` spans `(-400, -300)` to `(400, 300)`. Read `scenes/world/ThornfieldMeadow.tscn` and hand-edit via `write_file` to add one `ext_resource` for `res://assets/tiles/tree_pine.png` (type `Texture2D`), and 14 `Sprite2D` child nodes (named `Tree1` through `Tree14`), each with `texture = ExtResource("<tree_id>")` and a `position`, ringing the perimeter just outside the meadow's visible edge:

```
[node name="Tree1" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(-350, -320)

[node name="Tree2" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(-150, -320)

[node name="Tree3" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(150, -320)

[node name="Tree4" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(350, -320)

[node name="Tree5" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(-350, 320)

[node name="Tree6" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(-150, 320)

[node name="Tree7" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(150, 320)

[node name="Tree8" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(350, 320)

[node name="Tree9" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(-420, -200)

[node name="Tree10" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(-420, 0)

[node name="Tree11" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(-420, 200)

[node name="Tree12" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(420, -200)

[node name="Tree13" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(420, 0)

[node name="Tree14" type="Sprite2D" parent="."]
texture = ExtResource("<tree_id>")
position = Vector2(420, 200)
```

(Y positions on the top/bottom rows are `-320`/`320` — just outside the `-300`/`300` background edge; X positions on the left/right columns are `-420`/`420` — just outside the `-400`/`400` edge. This visually rings the meadow without overlapping the play area where the character/enemies move.) Remember to bump `load_steps` for the one new `ext_resource`, and no `unique_id` anywhere.

- [ ] **Step 2: Verify visually**

Run `mcp__godot__run_project`. Run `game_eval` to confirm all 14 nodes exist:

```gdscript
var world = get_node("/root/Main/World")
var count := 0
for i in range(1, 15):
	if world.has_node("Tree%d" % i):
		count += 1
return count
```

Expected: `14`.

Take a `mcp__godot__game_screenshot`, and also manually pan the camera (via `GameState.camera` — set `following = false` and `global_position` to a few different corner coordinates like `Vector2(-400, -300)`, `Vector2(400, 300)`, screenshotting each) to confirm trees are actually visible ringing the meadow's edges, not just at the default center view. Reset camera with `GameState.camera.recenter()` when done.

Run `game_get_errors` (clean/known-noise), `stop_project`.

- [ ] **Step 3: Commit**

Clean up `project.godot` drift first.

```bash
git add scenes/world/ThornfieldMeadow.tscn
git commit -m "$(cat <<'EOF'
Add tree-line border decoration to Thornfield Meadow

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Full integration verification

**Files:** none (verification only; fix forward in the relevant file if something's broken)

- [ ] **Step 1: Run the complete game and confirm no regressions**

Run `mcp__godot__run_project` (full `Main.tscn`, no scene override). Let it play for at least 60-90 real seconds, polling `game_get_logs` periodically (same pattern as the original plan's Task 17). Confirm via the log and `game_eval` checks:
- The AI still cycles through wander/chase/combat/flee/rest/loot exactly as before (no new errors, no stuck states) — this change should be behaviorally invisible to the FSM.
- Leveling, equipping, and death/respawn still work (reuse the same checks from the original Task 17 if useful: `GameState.character.level`, log lines containing `"Equipped"`, etc.).
- `game_get_errors` stays clean/known-noise-only throughout.

- [ ] **Step 2: Visual confirmation**

Take several `mcp__godot__game_screenshot`s across the play session (during wandering, during combat, during a Bandit encounter specifically to distinguish it from a Wolf) and confirm:
- Character, Wolf, and Bandit are all recognizable animated sprites, not colored squares.
- They face the direction they're moving.
- The Bandit looks visually distinct from the Wolf (human vs. animal) and from the Character (dark vs. green clothing).
- Trees are visible around the meadow's edge.
- No pink-and-black "missing texture" checkerboards anywhere.

- [ ] **Step 3: Fix forward if anything is broken**

If any regression or visual bug is found, diagnose and fix it in the relevant file (same rigor as every other task in this project — read the file fully, understand the root cause, apply a minimal fix, verify live, commit separately with a message describing the actual bug fixed).

- [ ] **Step 4: Stop the project and final check**

Run `mcp__godot__stop_project`. Clean up any `project.godot` drift. Confirm `git status` is clean (or only contains a fix commit from Step 3, already committed).

---

## Self-review notes

- **Spec coverage**: every section of the design spec maps to a task — real character/bandit/wolf sprites → Tasks 1-3, animation state mapping → Tasks 4-5, `color_override` removal (spec explicitly called this out as dead code once sprites exist) → Task 6, tree-line border → Task 7 (implementation mechanism corrected from the spec's `TileMap` assumption to scattered `Sprite2D`s, with the reasoning documented in the Conventions section above — the spec's underlying *goal*, a real tree-line instead of a flat edge, is fully met).
- **Type/signature consistency checked**: `_facing_from_velocity`/`_play_animation` are identical in both `character.gd` and `enemy.gd` (intentional duplication, matches the project's existing `game_time_ms` precedent). `sprite_frames_override: SpriteFrames` in `spawn_point.gd` matches the `AnimatedSprite2D` node name (`"AnimatedSprite2D"`) used in `Enemy.tscn` (Task 3) that it looks up via `get_node()`. Animation names (`walk_*`, `idle_*`, `run_*`, `slash_*`/`combat_*`) are consistent between the builder scripts (Tasks 1-3) and the runtime lookup logic (Tasks 4-5).
- **Known tooling risk flagged, not hidden**: the wolf's `walk_right` row-height guess (64px) might clip a sliver of an adjacent row — Task 3 Step 2 includes an explicit visual check and a documented fallback (try 56px) rather than assuming it's correct.
- **All exact pixel/frame numbers in this plan were independently verified against the actual downloaded files** (not taken from documentation or assumed) before this plan was written — see the Conventions section.
