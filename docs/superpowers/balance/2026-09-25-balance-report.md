# Balance pass - 2026-09-25

Measured full headless playthroughs of the real game, fixed two progression
bugs they exposed, and re-tuned the XP curve and the bosses. Every number
below comes from `tests/sim`, not from reading the tables.

## 1. The harness

```
GODOT=".../Godot_v4.7.2-stable_mono_win64_console.exe"
# one run
"$GODOT" --headless --path . --fixed-fps 60 res://tests/sim/SimRun.tscn -- class=warrior seed=3 minutes=45
# a batch (parallel), then the tables
GODOT="$GODOT" tests/sim/run_batch.sh OUT_DIR 45 "warrior mage" "$(seq -s ' ' 1 16)" 10
python tests/sim/summarize.py OUT_DIR/*.log [--fights] [--cutoff 25] [--markdown]
```

- `SimRun.tscn` loads `res://scenes/Main.tscn` unchanged, sets the
  Character node's `character_class` export before it enters the tree, and
  quits after `minutes` of game time. No game script knows about it.
- `--fixed-fps 60` makes every frame exactly 1/60 s of game time with no
  real-time sync, so a run is frame-rate independent and goes as fast as
  the CPU allows (45 game-minutes in ~50-90 s).
- `seed=N` re-seeds every entity's `rng` right after its own `_ready()`
  randomizes it (via the `ready` signal). With `--fixed-fps` a seed is fully
  reproducible: two runs with the same seed produce identical `SIM|` output.
- Other args: `scale=` (Engine.time_scale), `snap=` (snapshot period),
  `trace=1` (every damage number), `watch=<enemy name>` (that enemy's position
  and HP each snapshot).
- Output is `SIM|t=<game s>|<kind>|key=value...` lines: `level_up`,
  `zone_arrive`, `death`, `boss_kill`, `quest_accept`, `quest_done`, `equip`,
  `fight` (per enemy engaged: result, duration, lowest HP, enemy HP when
  engaged, the character's own damage, whether it fled), `snap` every 30 s,
  `summary` at the end.
- `summarize.py` prints per-run rows (minutes to each level, deaths, deaths
  per zone, worst death cluster, minutes per zone, boss kills by the
  character/by allies, highest zone, quests, gold) and a per-class aggregate
  (mean, median, min-max). `--fights` adds a per-enemy fight table.

Time scale: the tables below use `scale=1`. A check batch at `scale=8`
(physics steps of 8/60 s) gave the same results within noise (the last
table row), so a higher scale is usable, but it gains nothing over
`--fixed-fps`, which already runs unthrottled.

**Noise.** Seed-to-seed spread is large (for example, level 5 ranges over
7-16 min within one config), and changing one irrelevant number moved an
8-run median by 2 min. All before/after numbers therefore use 16 seeds per
class. Treat differences below ~1.5 min as noise.

## 2. Results

Median over seeds, 45 game-minutes per run. A level's column is the median
over runs that reached it, so for L10 also read the "reached" count. "Level
@25 min" is the median level at the 25-minute mark.

| config | class | runs | L2 | L3 | L4 | L5 | L6 | L7 | L8 | L9 | L10 (reached) | level @25 min | deaths/run | quests done | boss kills by char | gold | min in meadow/forest/crypt/swamp/pass |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A original (45ed53d) | warrior | 16 | 0.6 | 2.5 | 3.9 | 4.6 | 5.3 | 6.2 | 7.9 | 9.4 | 10.0 (16/16) | 10 | 0.00 | 1 | 19 | 2460 | 2.2/2.3/1.4/20.8/18.6 |
| A original (45ed53d) | mage | 16 | 1.3 | 2.7 | 4.0 | 5.6 | 6.4 | 7.3 | 8.8 | 9.4 | 10.6 (16/16) | 10 | 0.00 | 1 | 16.5 | 2242 | 2.3/2.3/1.4/20.0/18.8 |
| B bug fixes only | warrior | 16 | 0.7 | 1.8 | 2.5 | 3.8 | 4.4 | 6.5 | 8.8 | 9.8 | 12.2 (16/16) | 10 | 0.00 | 8 | 23 | 1464 | 7.9/11.6/7.7/11.1/6.5 |
| B bug fixes only | mage | 16 | 1.0 | 2.3 | 3.3 | 4.6 | 5.7 | 7.6 | 9.7 | 10.9 | 14.0 (16/16) | 10 | 0.00 | 6.5 | 20.5 | 1281 | 8.4/12.1/7.7/10.8/6.5 |
| **C fixes + tuning** | warrior | 16 | 0.7 | 3.5 | 7.5 | 10.2 | 14.4 | 19.0 | 25.0 | 30.1 | 37.9 (14/16) | 7.5 | 0.00 | 9 | 23 | 1143 | 9.9/13.9/7.8/9.0/4.4 |
| **C fixes + tuning** | mage | 16 | 1.0 | 3.8 | 8.2 | 10.6 | 14.8 | 21.1 | 27.5 | 32.9 | 41.0 (12/16) | 7 | 0.00 | 8 | 21 | 1115 | 9.9/13.9/8.1/9.2/4.0 |
| C at time_scale 8 | warrior | 8 | 0.7 | 4.8 | 8.0 | 11.1 | 15.3 | 19.3 | 23.4 | 30.6 | 40.8 (7/8) | 8 | 0.00 | 9 | 21.5 | 1066 | 10.0/13.6/7.7/9.2/4.4 |
| C at time_scale 8 | mage | 8 | 1.0 | 3.9 | 9.1 | 12.2 | 17.1 | 22.8 | 29.1 | 35.7 | 39.4 (5/8) | 7 | 0.00 | 5.5 | 19 | 1090 | 10.1/14.1/8.1/8.8/3.6 |

Zone minutes count corridor time toward the zone the character last
arrived in. In config C at 25 minutes, the pass was reached in 14 of 16
warrior runs and 10 of 16 mage runs; the rest were in the swamp.

**Boss fights** (from `summarize.py --fights`; "lowest HP" is the character's
lowest HP during the fight as a % of max; "fled" is the share of won fights
that included a retreat):

| boss | B: median duration / lowest HP / fled | C: median duration / lowest HP / fled | C: median level |
|---|---|---|---|
| Crypt Lord | 0.9 s / 90-91% / 0-5% | 2.7-3.6 s / 52-58% / 18-21% | 7 |
| Mire Tyrant | 0-0.9 s / 91-94% / 0-3% | 2.7 s / 59-63% / 9-16% | 8-9 |
| Frostpeak Warlord | 1.8 s / 83-89% / 0-4% | 3.8-4.6 s / 48-69% / 8-12% | 8-9 |
| Raider Captain | 0-0.1 s / 97% / 0-14% | 0.9 s / 40-60% / 0% (only 10 fights) | 8 |

The first Crypt Lord encounter is the one real early boss fight:

- **B:** at level 3-5, 1.8-4.9 s, lowest HP 21-73% (median ~44%). Every
  later kill took ~1 s.
- **C:** at level 3 in all 32 runs, typically 5-20 s, lowest HP 12-43%
  (median ~20%). In 11 of 32 first encounters the character retreated and
  its party finished the boss (it gets the kill on a later visit instead).
  Two first encounters turned into ~3.5-minute retreat/rest/re-engage
  cycles before the kill (not a stall; it resolved).

No seed needed a death to kill any boss, in any config.

**Against the brief's targets (config C):**

| target | result |
|---|---|
| L5 in ~8-12 min | met: 10.2 (warrior) / 10.6 (mage) |
| L10 in ~35-60 min | met: 37.9 / 41.0 median. 14 and 12 of 16 runs got there inside 45 min, and the rest were level 9 |
| meaningful swamp/pass progress by 25-30 min | met: level 7-8 at 25 min, the pass reached in 24 of 32 runs |
| every zone reachable in order | met: all five zones in every run, and the loop now really loops (see bug 1) |
| no stalls | met: the largest gap without XP is the wrap-around walk (~2-4 min); quests progress (median 8-9 done, was 1) |
| bosses killable at level within a couple of tries | met: always first try |
| deaths 0-3 per 10 min, more at bosses, no spiral | 0 everywhere, before and after. No spirals, but also no boss deaths; see concern 1 |
| classes within ~25% | met: level 5 within 4%, level 10 within 8% (was 20-25% at level 5 in config B) |
| gold accumulates but isn't the goal | ~1,100-1,150 per 45 min. Nothing spends it |

## 3. Bugs found and fixed

1. **The zone rotation ping-ponged between the last two zones** (commit
   `b8baae3`). The wrap-around leg from Frostpeak Pass back to Thornfield
   Meadow walks through the swamp, and `_sync_current_zone()` treated
   crossing the swamp as arriving there. That restarted the stay timer, and
   the next leg pointed back to the pass. From level 7 on the character
   bounced swamp <-> pass forever. It never saw the meadow's quest board
   again, so the quest chain stalled (median 1 quest per 45 min, table row
   A), and it farmed the swamp and pass bosses nonstop. The same happened
   crypt <-> forest at level 3. Fix: a travel leg now locks its destination
   when it starts. Zones crossed on the way still update `current_zone_id`,
   but only the destination restarts the timer, and death clears the leg.
   Regression test: `ZoneTable.is_travel_arrival` in `suite_zone_table.gd`.
2. **Enemies were stranded wherever a chase ended** (commit `b737cb4`). In
   2 of 8 seeds per class, the meadow's only Bandit chased a fleeing ally
   into the corner at (-356, 280). It stood there at 6 HP for the whole
   45-minute run, out of everyone's reach. It never died, its SpawnPoint
   never respawned it, and "Bandit Trouble" (and every quest after it)
   could never be finished. The `watch=Bandit` harness option found this.
   Fix: an enemy with nobody in aggro range walks back to its spawn point
   (`CombatSystem.return_home_velocity`) and does not heal on the way.
   Regression test in `suite_spawn_points.gd`.

Both are behaviour fixes. On their own (row B) they make progression
faster, because the XP-rich late zones are no longer farmed in a 2-zone
loop but everything else becomes reachable. That is why the tuning had to
follow.

## 4. What changed and why (commit `2bdf6ac`)

| file / entry | old -> new | why |
|---|---|---|
| `LevelingSystem.XP_THRESHOLDS` | `[100,250,450,700,1000,1400,1900,2500,3200]` -> `[100,400,1000,1850,2800,4100,6000,8500,11800]` | Row B reached L5 at ~4 min and L10 at ~12-14 min. I measured XP income per level (roughly 90/min at L1-2, 200-290 at L3-6, 350-550 at L7+ once the pass opens) and set each step to income x target time for that level. Two iterations: `[..,13400]` was slightly slow and `[..,9800]` too fast. |
| Crypt Lord `max_hp` | 150 -> 300 | This is the most-fought boss: the crypt sits on both legs of the loop (~13 kills per 45 min), and it has no zone ally to wear it down. From the second kill on it died in ~1 s with the character above ~80% HP (measured with the new XP curve and the old stats: 0.9 s, 79%). It is a pinned ORIGINAL enemy, so `suite_enemy_table.gd` changed in the same commit, with this reason. |
| Crypt Lord damage | 10-18 -> 14-22 | Same boss: HP alone gave long fights with no threat. Now its first encounter at level 3 takes the character to a median ~20% HP, and about a third of first encounters need a second go. |
| Mire Tyrant | 260 HP, 14-24 -> 520 HP, 16-26 | Died in 0-0.9 s with the character above 90% HP. |
| Raider Captain | 180 HP, 12-20 -> 360 HP, 14-22 | Died in 0-0.1 s with the character above 95% HP. |
| Frostpeak Warlord | 420 HP, 18-30 -> 840 HP, 22-34 | Died in ~1.8 s with the character above ~85% HP. |

Tests changed only because these numbers changed. `suite_enemy_table.gd`
got the new Crypt Lord values and a comment with the reason.
`suite_leveling_system.gd` now derives its "reaches level 10" checks from
`XP_THRESHOLDS` instead of the literal 3200.

**Measured and rejected** (all reverted):

- Swamp/pass trash at 2-3.5x HP: trash still died in 1-2 s, and the zone
  allies Vesper and Hrolf, whose stats match the original trash, died 3-5x
  more.
- Bosses at 3-4x HP or move speed 60-70: same problem. Allies soften these
  bosses between the character's visits anyway (most swamp and pass boss
  fights start with the boss already hurt), so extra boss HP mostly fed the
  allies' die-and-respawn loops.
- Arcane Bolt cooldown 4000 -> 3000: no measurable effect on mage XP (14767
  vs 14819).
- Frostpeak Warlord aggro 220 -> 260: identical encounter counts.
- Frostpeak Pass stay 45 s -> 75 s: +20% endgame boss encounters, no pacing
  change, so not worth it.

Class parity needed no class change once pacing was fixed.

## 5. Remaining concerns

1. **The character never dies** (0 deaths in 32 runs x 45 min, in every
   config including the original). The cause is structural, not a table
   number:
   - the AI flees below 30% HP;
   - every enemy is slower than the character (80 px/s);
   - gear roughly doubles to triples its damage and adds a lot of armor
     (warlord's greatsword +18 damage at level 3, champion's plate, the 35%
     bonus epic from every boss).

   Boss "tries" show up as retreat-and-return (up to ~20% of boss kills),
   not deaths. Getting occasional boss deaths would need a design choice,
   for example bosses at least as fast as the character, a lower flee
   threshold, or softer early epics (`LootTable` weapon damage,
   `BOSS_BONUS_EPIC_CHANCE`). I did not make that choice here.
2. **Zone allies die more.** Falls per 45-minute run, original -> fixes only
   -> final:
   - Hrolf 42 -> 53 -> 77
   - Vesper 24 -> 39 -> 71
   - Brynhild 12 -> 14 -> 19
   - Gorrim 16 -> 20 -> 29

   Much of this is a pre-existing level-design issue: Vesper spawns 128 px
   from the Mire Tyrant (aggro 200), Hrolf 100 px from the Raider Captain
   (aggro 160), so they respawn into the boss. Tougher bosses, and the
   slower XP curve (allies level from the same table), make it worse. Ally
   chat about it is rate-limited by ChatPolicy. Moving those two ally spawns
   away from the bosses is scene data, outside this pass; a test move cut
   their deaths by about a third.
3. **Trash is still trivial for a geared character.** Most trash dies in
   the first 1-2 swings. Fixing that without hurting the allies needs the
   gear curve (loot stats) looked at, not enemy HP.
4. **Kill credit only goes to the last hit.** Allies take 15-18 kills per
   run, including some boss kills, and those give the character no XP or
   quest progress. This is part of why the mage, which has no gap-closer,
   used to lag.
5. **Frostpeak Warlord and Raider Captain are rarely met:** about 0.6 and
   0.3 kills per run by the character. They sit off the pass's centre, the pass is only
   available for the last ~20 min of a 45-minute run, and its stay is 45 s
   per loop. The final quest, "The Frostpeak Warlord", is often still
   pending at 45 min.
6. **Gold has no sink.**

## 6. Danger pass (2026-09-26)

Goal: the character should die rarely but really (about 1-4 times per 45
game-minutes, mostly to bosses or on under-levelled zone visits), with no
death spiral and no pacing regression. Same harness, 32 seeds per class for
the final config (16 for the intermediate steps). `tests/sim` is unchanged:
the `death` line already carries the killer as `last_target`.

### Result

| class | config | deaths/run mean (median, max) | runs with 0 deaths | worst 5-min same-zone cluster | L5 median (min) | L10 median (reached) |
|---|---|---|---|---|---|---|
| warrior | before (2bdf6ac) | 0.00 (0, 0) | 16/16 | 0 | 10.2 | 37.9 (14/16) |
| mage | before | 0.00 (0, 0) | 16/16 | 0 | 10.6 | 41.0 (12/16) |
| warrior | after | 0.91 (1, 4) | 11/32 | max 2, mean 0.7 | 10.0 | 38.1 (30/32) |
| mage | after | 1.34 (1, 4) | 8/32 | max 2, mean 1.0 | 11.5 | 39.6 (26/32) |

Class comparison after: L5 10.0 vs 11.5 (15% gap; was 4%), L10 38.1 vs 39.6
(4%). The mage dies more (1.34 vs 0.91): lower armor and HP, no gap-closer.

Killers over all 64 final runs, by the character's level at death:

| killer | deaths (warrior / mage) | levels |
|---|---|---|
| Crypt Lord | 38 (16 / 22) | 32 at level 3, 5 at level 4, 1 at level 6 |
| Mire Tyrant | 26 (11 / 15) | level 4: 4, 5: 7, 6: 6, 7: 7, 8: 2 |
| Frostpeak Warlord | 7 (2 / 5) | level 8-10 |
| Raider Captain | 1 (0 / 1) | level 7 |

Boss fights (both classes, final config): Crypt Lord 835 fights, 38 deaths
(median lowest HP 41%); Mire Tyrant 174 fights, 26 deaths (median lowest HP
14%); Frostpeak Warlord 25 fights, 7 deaths; Raider Captain 27 fights, 1
death. Before: no boss fight ever ended in a death.

No spiral: the worst same-zone cluster within 5 minutes is 2 deaths. The
worst runs (4 deaths: one warrior and one mage seed of 32) have their deaths
spaced by full loop passes, typically the level-3 Crypt Lord and then Tyrant
deaths at levels 4-7: "under-levelled for the next zone", not a respawn-die
loop at one boss.

### What changed (old -> new) and why

| where | old -> new | why |
|---|---|---|
| `AIDecision.FLEE_HP_THRESHOLD` | 0.30 -> 0.10 | The character ran before a burst could land. Alone, 0.15 gave 0.03 deaths per run (fights end in ~3 s). At 0.10, with the boss changes, ~1 per run. A full-HP character still survives 4+ boss hits (max boss hit is 12-25% of max HP after armor). |
| `AIDecision.REST_HP_THRESHOLD` (new) | (was the same constant, 0.30) -> 0.30 | Split from the flee threshold. Rest still starts below 30% HP but only when nothing hostile is in aggro range; with a hostile near, the character keeps fighting until 10%. `tests/suite_ai_decision.gd` covers the ordering. |
| Crypt Lord | 300 HP, 14-22, speed 45 -> 380 HP, 17-27, speed 78 | Most-fought boss (~13 fights/run). More HP lengthens the mid-game fights; speed 78 (still under the character's 80) makes fleeing less reliable. Damage stayed modest because this is the level-3 first-boss: at 20-32 the mage's L5 slipped ~1 min more. Pinned ORIGINAL in `suite_enemy_table.gd`, updated in the same commit. |
| Mire Tyrant | 520 HP, 16-26, speed 50 -> 900 HP, 32-52, speed 80 | Its fights took 3.6 s with the character at a median 63% lowest HP. Now ~6 s, median lowest HP 14%, 15% of fights fatal. Main source of "under-levelled swamp visit" deaths. |
| Raider Captain | 360 HP, 14-22, speed 55 -> 560 HP, 28-42, speed 80 | Same reasoning; rarely met (~0.4 fights/run) so few deaths. |
| Frostpeak Warlord | 840 HP, 22-34, speed 50 -> 1300 HP, 34-50, speed 84 | 40-60 damage was fatal in 9 of 15 fights and produced a 3-deaths-in-10-min cluster; 34-50 is fatal in ~28%. Speed 84 is above the character's 80: it cannot outrun this boss. |
| `LevelingSystem.XP_THRESHOLDS` | `[100,400,1000,1850,2800,4100,6000,8500,11800]` -> `[100,400,900,1600,2450,3500,5300,7500,10400]` | Deaths plus the walk back from the meadow cost pace: with only the danger changes, L5 was 11.3 (warrior) / 13.3 (mage) and mage reached L10 in 5-11 of 16 runs. Lowering the L5 step ~12% restores L5, lowering the tail ~12% restores L10 (the L10 step is what sets L10 timing). |

### Intermediate measurements (16 seeds per class unless noted)

| step | warrior deaths/run | mage deaths/run | note |
|---|---|---|---|
| baseline | 0.00 | 0.00 | reproduces section 2 config C |
| flee 0.15 | 0.06 | 0.00 | the threshold alone is not enough |
| + Crypt Lord 20-32, Tyrant 22-36, Raider 20-30, Warlord 30-46 | 0.50 | 0.50 | nearly all deaths at the level-3 Crypt Lord |
| + Tyrant 30-48, Raider 28-42, Warlord 40-60 | 0.62 | 0.06 | noise: same boss config moves a class by 0.5 |
| + Tyrant/Raider speed 80, Warlord 84 | 0.44 | 0.38 | speed alone did little, fights are too short for a chase |
| + boss HP x1.3-1.7 | 0.69 | 0.62 | deaths appear at Tyrant/Warlord; Warlord fights last 20 s |
| + flee 0.10, Crypt Lord back to 17-27 | 1.25 | 1.31 | Warlord 60% fatal, 3 deaths in 10 min in one run |
| + Warlord 34-50, XP tail -8% | 0.81 | 1.12 | |
| + Crypt Lord speed 78, Tyrant 32-52 | 0.94 | 1.44 | mage L10 43.5 (5/16) |
| + XP tail -12% (32 seeds) | 1.12 | 1.19 | mage L5 13.3, L10 41.3 (22/32) |
| + XP early levels lower (final, 32 seeds) | 0.91 | 1.34 | L5 10.0 / 11.5, L10 38.1 / 39.6 |

Seed-to-seed spread is large: the same boss stats moved a class between 0.06
and 0.62 deaths per run on 16 seeds. Read a difference under ~0.4 as noise.

### Respawn consequences

`Character._die` respawns in Thornfield Meadow, so a death in a far zone sends
the character back through the loop. From a death to the next arrival in the
zone it died in (73 deaths in the 64-run intermediate batch): median 3.0 min,
max 9.4 min; crypt 2.4, swamp 3.1, pass 4.3 min. Each death costs about 2-4
min of pace, which the XP threshold change offsets. No long stalls, so the
respawn point was left alone (respawning at the current zone's entry would be
a design change).

### Remaining concerns

1. **Median is 1, not 2.** Mean is 0.9-1.3 deaths per run and about a third
   of runs (8-11 of 32 per class) have no death. Configs that reached a
   mean of ~1.3 on both classes also had a 3-deaths-in-10-min cluster or
   boss fights that were 60% fatal.
2. **Class gap at level 5: 15%** (mage 11.5, warrior 10.0). The mage is the
   more fragile class and takes 22 of its 43 deaths at the level-3 Crypt
   Lord. A class-specific early tweak (mage HP/armor at levels 1-4) would
   close it; not done here.
3. **The first Crypt Lord visit is a near coin flip**: 32 of 64 runs (15 of
   32 warrior, 17 of 32 mage) die to it at level 3. That is the "under-levelled
   visit" intent, but half of all runs is a lot for a first boss.
4. **Ally falls were not re-measured** with the tougher Tyrant and Warlord;
   expect the section 5 concern 2 numbers to rise again.
5. **A death is often one hit.** With flee at 10% and boss hits of 12-25% of
   max HP, dying depends on whether a hit lands before the flee. No new
   mechanic (enrage etc.) was added.

## 7. Follow-up: mage gap, swamp/pass pressure, ally spawns

Changes (45-minute sims, 16-32 seeds per class):

| Change | Result |
|---|---|
| Mage class bonus `bonus_max_hp` 25, `bonus_armor` 5 (flat, applied in `StatCalculator.derive`) | Mage L5 11.5 -> 10.4 min (warrior 10.2): gap closed. Mage deaths fell 1.2 -> 0.6. Bonus 15/3 or 25/2 left L5 at 11.3-11.5 (armor is what matters). |
| Mire Wolf 5-9 -> 6-11, Bog Bandit 6-11 -> 7-13, Frost Wolf 8-13 -> 9-15, Frost Raider 9-15 -> 10-17 | Warrior deaths 1.1 -> 1.8 per run (median 2, 0-4). Mage 0.7 (median 1). Levels unchanged (warrior L5 9.9, L10 35.8; mage L5 11.0, L10 38.7). |
| Vesper and Hrolf moved to the zones' NW corner (-330, -230) | Out of aggro range of the Tyrant, Captain and Warlord (>= 500 px). |

Trade-off: the mage's cushion is what closes the level-5 gap, and it also
makes the mage safer (median 1 death, warrior 2). Weakening the bonus
reintroduces the gap, so the classes stay at different danger levels.

## 8. Personality traits

Each trait was measured with 45-minute sims, 16 seeds per class
(`tests/sim/run_batch.sh ... trait=<id>`). A forced `trait=steady` run is
identical to the pre-trait logs for the same seeds (8 of 8 runs compared), so
Steady is unchanged. (The narrator's random generator is named `narrator_rng`
so the sim's per-node seeding does not count it; a node called `rng` would
have shifted every later seed.)

| trait | class | deaths/run | L5 (min) | L10 (min) | L10 reached |
|---|---|---|---|---|---|
| steady | mage / warrior | 0.7 / 2.1 | 11.1 / 10.0 | 38.5 / 36.6 | 13 / 16 |
| cautious (flee 14%, rest 34%) | mage / warrior | 0.4 / 0.9 | 11.2 / 10.0 | 40.0 / 35.7 | 14 / 16 |
| reckless (flee 7%, rest 20%) | mage / warrior | 1.0 / 2.2 | 11.3 / 10.1 | 38.6 / 35.5 | 14 / 15 |
| greedy (loot range 1.6x) | mage / warrior | 0.2 / 1.5 | 9.3 / 8.6 | 38.2 / 33.3 | 14 / 16 |
| explorer (stay x0.8) | mage / warrior | 0.9 / 1.7 | 10.2 / 11.1 | 38.7 / 36.6 | 15 / 16 |

Tuning from the spec's first numbers:

| trait | first try | result | final |
|---|---|---|---|
| cautious | flee 25%, rest 45% | 0.0 / 0.1 deaths: it almost never died, the trait had no risk | 18%/38% still 0.1 / 0.3; 14%/34% gives 0.4 / 0.9 |
| reckless | flee 5% | warrior 3.1 deaths per run, over the 3.0 cap | flee 7% |
| explorer | stay x0.7 | mage reached L10 in only 11 of 16 runs | stay x0.8 |

Greedy stays as designed: it levels fastest (loot upgrades sooner) and its mage
mean of 0.2 deaths is slightly under the 0.3 target, accepted because the
Steady mage is itself only at 0.7. Acceptance used: mean deaths 0.3 to 3.0,
L10 reached in at least 12 of 16 runs, L10 time within 20% of Steady.

## 9. Jobs

Seven jobs, measured with 45-minute sims, 12 seeds each (`class=<job>`,
`trait=steady`). Acceptance: mean deaths 0.3 to 3.0, level 5 mean at most 13
min, level 10 reached in at least 10 of 12 runs, mean level 10 time within 25%
of the Warrior.

### Pass A: original allies (no ally jobs)

| job | deaths/run | L5 (min) | L10 (min) | L10 reached |
|---|---|---|---|---|
| warrior (unchanged) | 2.1 | 9.8 | 36.1 | 12 / 12 |
| black mage (unchanged) | 0.6 | 10.7 | 38.7 | 11 / 12 |
| white mage | 0.4 | 11.5 | 39.6 | 12 / 12 |
| thief | 1.4 | 9.0 | 35.9 | 12 / 12 |
| black belt | 0.9 | 10.6 | 36.9 | 12 / 12 |
| dragoon | 0.9 | 9.6 | 35.4 | 12 / 12 |
| red mage | 0.6 | 11.0 | 39.6 | 10 / 12 |

Tuning: the first White Mage (+20 HP, +4 armor, Cure 30%, Benediction 35% every
25 s) never died (0.0 deaths). Reduced to +10 HP, +2 armor, Cure 20%,
Benediction 25% every 35 s: 0.4 deaths and level 10 in 12 of 12 runs. The other
five jobs passed at their first numbers. Warrior and Black Mage runs are
bit-identical to the pre-job logs (8 of 8 seeded runs compared).
