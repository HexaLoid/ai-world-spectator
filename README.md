# AI World Spectator

A single-player fantasy game where you don't play — you **watch**. An AI character
autonomously explores a small meadow, fights wolves and bandits, loots gear,
rests when hurt, and levels up, while a spectator HUD narrates every decision.

There is no player-controlled character and no multiplayer. The "AI" is a local,
rule-based state machine (no network or LLM calls), so it runs fast, free, and
offline.

Built with **Godot 4.7** (GDScript, 2D top-down).

## What you'll see

- **Thornfield Meadow** — one small zone ringed by pine trees, with two wolves
  and a bandit that respawn after being defeated.
- **An autonomous character** that cycles through wandering, chasing, fighting,
  fleeing, resting, and looting, choosing each action from simple priority rules
  (for example: flee or rest when HP is low, fight when an enemy is in range).
- **Loot, gear and leveling** — enemies drop gear across six slots (weapon,
  off-hand, head, chest, neck, ring) with multiple stats each, plus gold and
  potions. The character equips only real upgrades for its class and level and
  ignores the rest; armor reduces damage taken. Kills grant XP and level-ups
  increase HP and damage.
- **A spectator HUD**
  - HP bar, XP bar, level, six equipment slots with rarity-colored icons and hover tooltips, and a gold counter
  - An activity log explaining what the AI is doing and why
  - A floating label above the character showing its current action
  - Floating damage and heal numbers
  - A health bar over whichever enemy is currently being fought
  - A character sheet (stats, gear, quest, kills/deaths/damage/gold statistics)
  - A target frame showing the enemy being fought
  - Pause / 1x / 2x / 4x speed controls

## Running it

1. Install [Godot 4.7](https://godotengine.org/download) (the .NET edition was
   used for development; the game itself is pure GDScript).
2. Clone this repository:
   ```bash
   git clone https://github.com/HexaLoid/ai-world-spectator.git
   ```
3. Open Godot, choose **Import**, and select the `project.godot` file.
4. Press **F5** (Play). The main scene is `scenes/Main.tscn`.

The first time the project opens, Godot imports the art assets, which takes a few
seconds. If sprites or icons look missing on first launch, close and reopen the
project once so the import finishes.

## Controls

You can't control the character, but you can control how you watch:

| Input | Action |
|---|---|
| Left-click + drag | Pan the camera (stops following the character) |
| Mouse wheel | Zoom in / out |
| **Recenter** button | Snap the camera back to following the character |
| **Pause / 1x / 2x / 4x** buttons | Change simulation speed |
| **C** key / **Sheet (C)** button | Open or close the character sheet |

## Project layout

```
scenes/
  Main.tscn                 Root scene: world, character, camera, HUD
  world/ThornfieldMeadow.tscn   The zone, spawn points, and tree border
  entities/                 Character, Enemy, SpawnPoint, item pickup
  ui/                       Spectator HUD and floating damage text
scripts/
  ai/ai_decision.gd         Picks the character's next state from context
  entities/                 Character, enemy, spawn point, item pickup logic
  systems/                  Combat, leveling, loot, item scoring, and stat rules
  ui/                       HUD, camera controller, health bar, floating text
  autoload/game_state.gd    Signal hub between gameplay and UI
tests/                      Headless test suites (run with: godot --headless --path . --script res://tests/run_tests.gd)
assets/
  sprites/, tiles/, icons/  Third-party art (see Credits)
  theme/spectator_theme.tres  Parchment-style HUD theme
docs/superpowers/           Design specs and implementation plans
```

Gameplay code never talks to the UI directly. It emits signals on the `GameState`
autoload (HP changes, damage dealt, combat target changes, log events), and the
HUD listens.

## Design docs

The project was built in three phases, each with a written design spec and a
task-by-task implementation plan under `docs/superpowers/`:

1. **Core game** — AI state machine, combat, leveling, loot, zone, spectator UI
   (`2026-09-21-ai-played-world-spectator-design.md`)
2. **Visual art upgrade** — replaced placeholder squares with animated sprites and
   a tree-line border (`2026-09-22-visual-art-upgrade-design.md`)
3. **HUD/UI upgrade** — themed HUD, equipment icons, floating damage numbers,
   enemy health bar, action label (`2026-09-23-hud-ui-upgrade-design.md`)

## Credits

All third-party art is credited in [`assets/CREDITS.txt`](assets/CREDITS.txt),
including per-author attribution files kept next to the assets.

- Character, bandit, and terrain art: [Liberated Pixel Cup](https://lpc.opengameart.org)
  (CC-BY-SA 3.0 and compatible licenses)
- Wolf: [LPC Wolf Animation](https://opengameart.org/content/lpc-wolf-animation)
  by William.Thompsonj and Stephen "Redshrike" Challener
- HUD icons: [Kyrise's Free 16x16 RPG Icon Pack](https://opengameart.org/content/kyrises-free-16x16-rpg-icon-pack)
  (CC-BY 4.0)

The CC-BY-SA terms apply to the art itself. No license has been chosen for the
game's own source code yet.
