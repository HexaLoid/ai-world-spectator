#!/usr/bin/env bash
# Runs a batch of balance simulations in parallel and summarizes them.
#
#   tests/sim/run_batch.sh OUT_DIR MINUTES "warrior mage" "1 2 3 4" [JOBS] [EXTRA_USER_ARGS...]
#
# Writes OUT_DIR/<class>_s<seed>.log per run, then prints
# `python tests/sim/summarize.py OUT_DIR/*.log`. GODOT must point at the
# Godot 4.7 executable (console build on Windows). Runs use --fixed-fps 60,
# so each run is frame-rate independent and, for a given seed, reproducible.
set -euo pipefail
OUT_DIR="$1"; MINUTES="$2"; CLASSES="$3"; SEEDS="$4"; JOBS="${5:-4}"
shift 5 || shift $#
EXTRA="$*"
: "${GODOT:?set GODOT to the Godot executable}"
mkdir -p "$OUT_DIR"
cd "$(dirname "$0")/../.."
for c in $CLASSES; do for s in $SEEDS; do echo "$c $s"; done; done |
  xargs -P "$JOBS" -L 1 bash -c '
    timeout 900 "$GODOT" --headless --path . --fixed-fps 60 res://tests/sim/SimRun.tscn -- \
      class="$0" seed="$1" minutes='"$MINUTES"' '"$EXTRA"' > "'"$OUT_DIR"'/$0_s$1.log" 2>&1 || true'
python tests/sim/summarize.py "$OUT_DIR"/*.log
