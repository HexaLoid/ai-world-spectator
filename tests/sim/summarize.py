#!/usr/bin/env python3
"""Summarize balance-simulation logs produced by tests/sim/SimRun.tscn.

Usage:
    python tests/sim/summarize.py LOG [LOG ...] [--cutoff MINUTES] [--markdown]

Each LOG is the captured stdout of one run (only lines starting with "SIM|"
are read; everything else is ignored). Prints one row per run plus a
per-class aggregate (mean / median / min-max) block.

--cutoff MINUTES  only consider events up to that game time, so longer runs
                  can be compared with shorter ones on equal terms.
--markdown        emit Markdown tables instead of plain text.
--fights          also print a per-class, per-enemy fight table (wins,
                  deaths, median duration, median lowest HP %, and for bosses
                  the level and number of deaths before the first kill).
"""
import argparse
import statistics
import sys
from collections import defaultdict

ZONE_ORDER = ["thornfield_meadow", "blackthorn_forest", "sundered_crypt",
              "mirewater_swamp", "frostpeak_pass"]
ZONE_SHORT = {"thornfield_meadow": "meadow", "blackthorn_forest": "forest",
              "sundered_crypt": "crypt", "mirewater_swamp": "swamp",
              "frostpeak_pass": "pass"}
BOSS_SHORT = {"bandit_captain": "BC", "crypt_lord": "CL", "mire_tyrant": "MT",
              "raider_captain": "RC", "frostpeak_warlord": "FW"}
MAX_LEVEL = 10
SPIRAL_WINDOW_S = 300.0   # deaths within this many seconds of each other...
SPIRAL_COUNT = 3          # ...this many times in the same zone = a spiral


def parse_line(line):
    parts = line.rstrip("\r\n").split("|")
    if len(parts) < 3 or parts[0] != "SIM":
        return None
    t = float(parts[1].split("=", 1)[1])
    kind = parts[2]
    fields = {}
    for p in parts[3:]:
        if "=" in p:
            k, v = p.split("=", 1)
            fields[k] = v
    return t, kind, fields


def load_run(path, cutoff_s):
    run = {"path": path, "level_t": {1: 0.0}, "deaths": [], "zone_arrive": [],
           "boss_kills": [], "quests": [], "snaps": [], "summary": None,
           "info": {}, "end_t": 0.0, "level": 1, "gold": 0, "fights": [],
           "jobs": [], "level_events": []}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if not line.startswith("SIM|"):
                continue
            parsed = parse_line(line)
            if parsed is None:
                continue
            t, kind, f = parsed
            if kind == "start":
                # info=class=warrior|seed=.. is split on "|" so the rest of
                # the fields arrive as their own keys.
                run["info"] = dict(f)
                run["info"]["class"] = f.get("info", "").split("=", 1)[-1]
                continue
            if cutoff_s is not None and t > cutoff_s + 1e-6:
                continue
            run["end_t"] = max(run["end_t"], t)
            if kind == "level_up":
                lvl = int(f["level"])
                run["level_t"].setdefault(lvl, t)
                run["level_events"].append((t, lvl))
            elif kind == "job":
                run["jobs"].append((t, f.get("from", ""), f.get("to", ""), int(f.get("level", "1"))))
            elif kind == "death":
                run["deaths"].append((t, f.get("zone", "?"), f.get("last_target", "")))
            elif kind == "zone_arrive":
                run["zone_arrive"].append((t, f["zone"]))
            elif kind == "boss_kill":
                run["boss_kills"].append((t, f["name"], f.get("by", "")))
            elif kind == "quest_done":
                run["quests"].append((t, f.get("id", "")))
            elif kind == "snap":
                run["snaps"].append((t, f))
                run["level"] = int(f["level"])
                run["gold"] = int(f["gold"])
            elif kind == "fight":
                run["fights"].append((t, f))
            elif kind == "summary":
                run["summary"] = f
    return run


def switch_outcomes(run):
    """For each job change: did the new job reach level 10 before the next change (or the end), and when."""
    outcomes = []
    jobs = run["jobs"]
    for i, (t0, _from, to, lvl) in enumerate(jobs):
        t1 = jobs[i + 1][0] if i + 1 < len(jobs) else run["end_t"]
        reached = None
        if lvl >= MAX_LEVEL:
            reached = 0.0
        else:
            for (t, level) in run["level_events"]:
                if t0 < t <= t1 and level >= MAX_LEVEL:
                    reached = t - t0
                    break
        outcomes.append(reached)
    return outcomes


def zone_times(run, cutoff_s=None):
    """Seconds spent per 'home' zone. Exact (from the summary line) for a
    whole run; with --cutoff, reconstructed from the snapshots' zone field
    (sampled every snap interval), which keeps the cutoff honest."""
    out = defaultdict(float)
    if cutoff_s is None and run["summary"] and run["summary"].get("zone_time"):
        for part in run["summary"]["zone_time"].split(","):
            zone, secs = part.rsplit(":", 1)
            out[zone] += float(secs)
        return out
    snaps = run["snaps"]
    for (t0, f0), (t1, _f1) in zip(snaps, snaps[1:]):
        out[f0["zone"]] += t1 - t0
    return out


def spiral_count(run):
    """Largest number of deaths in one zone inside any SPIRAL_WINDOW_S window."""
    best = 0
    by_zone = defaultdict(list)
    for t, zone, _ in run["deaths"]:
        by_zone[zone].append(t)
    for times in by_zone.values():
        j = 0
        for i in range(len(times)):
            while times[i] - times[j] > SPIRAL_WINDOW_S:
                j += 1
            best = max(best, i - j + 1)
    return best


def fmt_min(seconds):
    return "-" if seconds is None else f"{seconds / 60.0:.1f}"


def highest_zone(run):
    best = 0
    for _, z in run["zone_arrive"]:
        if z in ZONE_ORDER:
            best = max(best, ZONE_ORDER.index(z))
    return ZONE_ORDER[best]


def table(headers, rows, markdown):
    if markdown:
        out = ["| " + " | ".join(headers) + " |",
               "|" + "|".join("---" for _ in headers) + "|"]
        out += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
        return "\n".join(out)
    widths = [max(len(str(h)), *(len(str(r[i])) for r in rows)) if rows else len(str(h))
              for i, h in enumerate(headers)]
    line = lambda cells: "  ".join(str(c).rjust(w) for c, w in zip(cells, widths))
    return "\n".join([line(headers)] + [line(r) for r in rows])


def stats(values):
    vals = [v for v in values if v is not None]
    if not vals:
        return "-"
    if len(vals) == 1:
        return f"{vals[0]:.1f}"
    return f"{statistics.mean(vals):.1f} (med {statistics.median(vals):.1f}, {min(vals):.1f}-{max(vals):.1f})"


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("logs", nargs="+")
    ap.add_argument("--cutoff", type=float, default=None, help="game minutes")
    ap.add_argument("--markdown", action="store_true")
    ap.add_argument("--fights", action="store_true")
    args = ap.parse_args(argv)
    cutoff_s = args.cutoff * 60.0 if args.cutoff is not None else None
    runs = [load_run(p, cutoff_s) for p in args.logs]

    headers = ["run", "class", "seed", "min"] + [f"L{l}" for l in range(2, MAX_LEVEL + 1)] + \
              ["lvl", "deaths", "d/10m", "spiral", "deaths by zone", "min per zone",
               "bosses (char/ally)", "top zone", "quests", "gold"]
    rows = []
    per_class = defaultdict(list)
    for r in runs:
        name = r["path"].replace("\\", "/").rsplit("/", 1)[-1].rsplit(".", 1)[0]
        cls = r["info"].get("class", "?")
        seed = r["info"].get("seed", "?")
        minutes = r["end_t"] / 60.0
        lt = [r["level_t"].get(l) for l in range(2, MAX_LEVEL + 1)]
        dz = defaultdict(int)
        for _, z, _ in r["deaths"]:
            dz[ZONE_SHORT.get(z, z)] += 1
        zt = zone_times(r, cutoff_s)
        bosses = defaultdict(lambda: [0, 0])
        for _, b, by in r["boss_kills"]:
            bosses[BOSS_SHORT.get(b, b)][0 if by == "character" else 1] += 1
        d10 = len(r["deaths"]) / minutes * 10.0 if minutes > 0 else 0.0
        rows.append([name, cls, seed, f"{minutes:.0f}"] + [fmt_min(x) for x in lt] + [
            r["level"], len(r["deaths"]), f"{d10:.1f}", spiral_count(r),
            " ".join(f"{k}:{v}" for k, v in dz.items()) or "-",
            " ".join(f"{ZONE_SHORT[z]}:{zt[z] / 60.0:.1f}" for z in ZONE_ORDER if zt.get(z)),
            " ".join(f"{k}:{v[0]}/{v[1]}" for k, v in bosses.items()) or "-",
            ZONE_SHORT[highest_zone(r)], len(r["quests"]), r["gold"]])
        per_class[cls].append({"lt": lt, "deaths": len(r["deaths"]), "d10": d10, "level": r["level"],
                               "zt": zt, "gold": r["gold"], "spiral": spiral_count(r),
                               "top": ZONE_ORDER.index(highest_zone(r)), "dz": dz,
                               "jobs": len(r["jobs"]), "switch": switch_outcomes(r)})
    print(table(headers, rows, args.markdown))
    print()

    agg_headers = ["class", "runs", "metric", "value"]
    agg_rows = []
    for cls, items in sorted(per_class.items()):
        n = len(items)
        for i, l in enumerate(range(2, MAX_LEVEL + 1)):
            vals = [it["lt"][i] / 60.0 for it in items if it["lt"][i] is not None]
            reached = len(vals)
            if reached:
                agg_rows.append([cls, n, f"min to L{l} ({reached}/{n} reached)", stats(vals)])
        agg_rows.append([cls, n, "final level", stats([it["level"] for it in items])])
        agg_rows.append([cls, n, "deaths", stats([it["deaths"] for it in items])])
        agg_rows.append([cls, n, "deaths / 10 min", stats([it["d10"] for it in items])])
        agg_rows.append([cls, n, "worst death cluster (same zone, 5 min)", stats([it["spiral"] for it in items])])
        for z in ZONE_ORDER:
            agg_rows.append([cls, n, f"min in {ZONE_SHORT[z]}", stats([it["zt"].get(z, 0.0) / 60.0 for it in items])])
            agg_rows.append([cls, n, f"deaths in {ZONE_SHORT[z]}", stats([it["dz"].get(ZONE_SHORT[z], 0) for it in items])])
        agg_rows.append([cls, n, "gold", stats([it["gold"] for it in items])])
        tops = defaultdict(int)
        for it in items:
            tops[ZONE_SHORT[ZONE_ORDER[it["top"]]]] += 1
        agg_rows.append([cls, n, "highest zone reached", " ".join(f"{k}:{v}" for k, v in tops.items())])
        agg_rows.append([cls, n, "job switches", stats([it["jobs"] for it in items])])
        outs = [o for it in items for o in it["switch"]]
        ok = sum(1 for o in outs if o is not None and o <= 1500.0)
        agg_rows.append([cls, n, "switches reaching L10 within 25 min", f"{ok}/{len(outs)}"])
    print(table(agg_headers, agg_rows, args.markdown))
    if args.fights:
        print()
        print(fight_table(runs, args.markdown))
    return 0


def fight_table(runs, markdown):
    order = ["wolf", "bandit", "dire_wolf", "bandit_captain", "crypt_lord", "mire_wolf", "bog_bandit",
             "mire_tyrant", "frost_wolf", "frost_raider", "raider_captain", "frostpeak_warlord"]
    agg = defaultdict(lambda: {"win": 0, "death": 0, "other": 0, "dur": [], "minhp": [], "lvl": [],
                               "first": [], "tries": [], "flees": []})
    for r in runs:
        cls = r["info"].get("class", "?")
        seen_win = set()
        deaths_before = defaultdict(int)
        for _t, f in r["fights"]:
            key = (cls, f.get("enemy", "?"))
            a = agg[key]
            res = f.get("result", "other")
            a[res] = a.get(res, 0) + 1
            if res == "win":
                a["dur"].append(float(f["dur"]))
                a["minhp"].append(100.0 * int(f["min_hp"]) / max(1, int(f["max_hp"])))
                a["lvl"].append(int(f["level"]))
                a["flees"].append(int(f.get("flees", 0)))
                if f["enemy"] not in seen_win:
                    seen_win.add(f["enemy"])
                    a["first"].append(int(f["level"]))
                    a["tries"].append(deaths_before[f["enemy"]])
            elif res == "death" and f["enemy"] not in seen_win:
                deaths_before[f["enemy"]] += 1
    med = lambda v: f"{statistics.median(v):.1f}" if v else "-"
    headers = ["class", "enemy", "wins", "deaths", "other", "med dur s", "med lowest HP %",
               "wins with a flee %", "med level", "level at 1st kill", "deaths before 1st kill"]
    rows = []
    for (cls, enemy) in sorted(agg, key=lambda k: (k[0], order.index(k[1]) if k[1] in order else 99)):
        a = agg[(cls, enemy)]
        fled = f"{100.0 * sum(1 for x in a['flees'] if x > 0) / len(a['flees']):.0f}" if a["flees"] else "-"
        rows.append([cls, enemy, a["win"], a["death"], a["other"], med(a["dur"]), med(a["minhp"]), fled,
                     med(a["lvl"]), med(a["first"]), " ".join(str(x) for x in a["tries"]) or "-"])
    return table(headers, rows, markdown)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
