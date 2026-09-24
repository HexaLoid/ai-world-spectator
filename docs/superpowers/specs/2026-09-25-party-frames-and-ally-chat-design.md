# Party Frames & Ally Chat — Design (Phase 3 of 4)

Date: 2026-09-25

## Context

Phase 3 of the Erenshor-style roadmap (1: loot & gear depth and 2: character
sheet & target frame are done; 4: world & content follows). Today the four
simulated players ("allies": Kaelen, Elowen in Thornfield Meadow; Brynhild,
Gorrim in Blackthorn Forest) fight and level up but are silent. The spectated
character recruits up to two of them permanently (`Character.party`, max 2) and
the only trace is log lines like "[Ally] Brynhild defeats Dire Wolf!". There is
no party HUD and no social layer, which is the core of the "other players in a
shared world" feel.

## Goals

- **Party frames:** compact HUD frames for the character's grouped allies.
- **Ally chat:** a separate chat panel where allies talk in-character, driven by
  game events, with two channels (`[Party]`, `[Zone]`) and sane rate limiting.
- **A name for the spectated character**, so allies can address it.

## Non-goals

- Ally classes, abilities and gear (a later phase).
- Groups that form and dissolve dynamically (recruitment stays permanent).
- Any typed input; every chat line comes from templates.
- Persisting chat across launches.

## Character name

`Character.character_name` is picked from `NameTable.NAMES` at spawn (a small
pool that does not collide with ally names: Aldric, Seraphine, Thorne, Marisol,
Dunstan, Isolde, Corwin, Lyra, Bram, Petra, Osric, Nyla). It is shown as the first
line of the character sheet (`SheetText.build` prepends `[b]<name>[/b]` when the
snapshot has a non-empty `character_name`) and used as `{leader}` in chat.

## Signals (added to `GameState`)

- `chat_event(event: String, context: Dictionary)`: emitted by gameplay code at
  trigger sites; the `ChatDirector` decides whether anyone speaks.
- `chat_message(channel: String, speaker: String, text: String)`: emitted by the
  director; the chat panel listens.
- `party_changed()`: emitted when the character's party membership changes.

## Chat events

| Event | Emitted by | Channel | Speaker |
|---|---|---|---|
| `ally_joined` | `Character._recruit_companions_in_zone`, per recruit | party | the recruit |
| `ally_level_up` | `SimulatedPlayer.take_kill_credit` on level-up | party if grouped, else zone | that ally |
| `ally_died` | `SimulatedPlayer._die` | party if grouped, else zone | that ally |
| `elite_kill` | `Enemy._die` when `guaranteed_drop_id != ""` | party | random living party member |
| `leader_level_up` | `Character.gain_xp` on level-up | party | random living party member |
| `leader_loot` | `Character._acquire_item` when a rare/epic item is equipped | party | random living party member |
| `zone_arrive` | `Character._sync_current_zone` | party | random living party member |
| `leader_low_hp` | `Character.take_damage`, edge-triggered: fires when HP first falls below 30% and re-arms once HP is above 60% | party | random living party member |
| `leader_died` | `Character._die` | party | random living party member |
| `ambient` | `ChatDirector` timer | zone | random ungrouped ally whose `home_zone_id` equals the character's current zone |

Context dictionaries carry what the templates need: `ally` (the node),
`enemy`, `item`, `zone`, `level`. If a party event has no living party member
to speak (empty or all down), nothing is said.

## Templates: `ChatLines` (pure, `scripts/systems/chat_lines.gd`)

- `TEMPLATES: Dictionary` maps each event name above to an array of at least
  three line templates with placeholders `{leader}`, `{ally}`, `{enemy}`,
  `{item}`, `{zone}`, `{level}`.
- `pick(event, rng, vars) -> String` picks a template with the given
  `RandomNumberGenerator` and fills the placeholders. Unknown events return `""`.
  Missing vars are replaced by an empty string; no `{...}` may remain in the result.
- `format(channel, speaker, text) -> String` returns the BBCode line:
  `[color=#6fa8dc][Party][/color] [b]Kaelen[/b]: text` (party) or
  `[color=#d9b382][Zone][/color] [b]Kaelen[/b]: text` (zone).

## Rate limiting: `ChatPolicy` (pure, `scripts/systems/chat_policy.gd`)

- `GLOBAL_COOLDOWN_MS = 6000`, `SPEAKER_COOLDOWN_MS = 20000`.
- `EVENT_CHANCE`: `ally_joined` 1.0, `leader_level_up` 0.9, `elite_kill` 0.9,
  `zone_arrive` 0.8, `leader_died` 0.8, `ally_level_up` 0.8, `leader_loot` 0.7,
  `leader_low_hp` 0.6, `ally_died` 0.5, `ambient` 1.0.
- `should_fire(event, roll) -> bool`: `roll < EVENT_CHANCE[event]` (unknown
  events never fire).
- `can_speak(event, now_ms, last_global_ms, last_speaker_ms) -> bool`: `ally_joined`
  bypasses both cooldowns (two allies join at the start and both should greet);
  every other event needs both cooldowns elapsed.
- `next_ambient_delay_ms(roll) -> float`: 30000 + roll * 30000 (roll in 0..1).

## ChatDirector (`scripts/ui/chat_director.gd`, a Node in `SpectatorUI.tscn`)

- Keeps its own `game_time_ms` (accumulated from `_process` delta, so it follows
  the speed control) and per-speaker last-spoke times.
- On `GameState.chat_event(event, context)`: roll `ChatPolicy.should_fire`, pick a
  speaker (see the table), check `ChatPolicy.can_speak`, build the text with
  `ChatLines.pick`, then emit `chat_message(channel, speaker_name, text)` and
  record the times.
- Ambient timer: when `game_time_ms` passes `next_ambient_ms`, run the `ambient`
  event and schedule the next one with `next_ambient_delay_ms`.
- Tolerates a null `GameState.character` and freed/invalid ally nodes.

## Chat panel (`scripts/ui/chat_panel.gd`)

A themed `Panel` at position (16, 270), size 320x124, holding a `RichTextLabel`
(BBCode, auto-scroll, dark text-friendly styling consistent with the character
sheet). It appends `ChatLines.format(...)` for each `chat_message` and trims to
the last 60 lines.

## Party frames (`scripts/ui/party_frames.gd`)

A `VBoxContainer` at (16, 176) holding one compact panel (224x40) per member of
`GameState.character.party`: name, `Lv N`, and an HP bar with numbers. It
rebuilds on `GameState.party_changed` (also once in `_ready` for the current
party), reads each member's `hp`/`max_hp`/`level`/`is_dead` every frame, and
shows an ally that is down as dimmed with `Down` instead of HP. The bars use the
same ProgressBar sizing workaround as the unit and target frames (theme with
zero-minimum styleboxes, `custom_minimum_size`, reassign `size` in `_ready`).
Nodes are built in code; freed members are skipped.

Left-side layout at 1152x648 (no overlaps): unit frame y 16-170, party frames
y 176-262, chat y 270-394, activity log y 400-560.

## Files

- New: `scripts/systems/name_table.gd`, `scripts/systems/chat_lines.gd`,
  `scripts/systems/chat_policy.gd`, `scripts/ui/chat_director.gd`,
  `scripts/ui/chat_panel.gd`, `scripts/ui/party_frames.gd`.
- Modified: `scripts/autoload/game_state.gd` (three signals),
  `scripts/entities/character.gd` (name, event emission, `party_changed`),
  `scripts/entities/simulated_player.gd` (event emission),
  `scripts/entities/enemy.gd` (`elite_kill`), `scripts/ui/sheet_text.gd` (name
  line), `scenes/ui/SpectatorUI.tscn` (director, chat panel, party frames),
  `README.md`.

## Error handling

- Unknown events, missing context keys and freed nodes never raise: templates
  return `""`, the director skips the event.
- No living party member means party events are dropped silently.
- A null `GameState.character` disables ambient chat and party frames until it
  exists.

## Testing

New headless suites in the existing runner:

- `suite_chat_lines.gd`: every event in the table above has at least three
  templates; `pick` fills every placeholder and leaves no `{` or `}`; unknown
  event returns `""`; missing vars become empty; `format` output contains the
  channel tag, the bold speaker name and the text.
- `suite_chat_policy.gd`: `should_fire` boundaries (0, chance, just below/above);
  `can_speak` with cooldowns elapsed/not elapsed, and the `ally_joined` bypass;
  `next_ambient_delay_ms` bounds (0 -> 30000, 1 -> 60000); every event in
  `ChatLines.TEMPLATES` has a chance entry.
- `suite_name_table.gd`: names are unique, non-empty, and do not collide with the
  four ally names.
- `suite_sheet_text.gd`: the new name line.

Live check: allies greet when recruited; party frames appear under the unit frame
with names and HP bars that update and show `Down` when an ally dies; chat lines
appear on zone arrival, level-ups, elite kills and low HP, and ambient `[Zone]`
lines show up now and then without flooding; the sheet shows the character's
name; nothing overlaps the existing HUD; no errors in the log.
