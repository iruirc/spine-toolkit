#!/usr/bin/env bash
set -euo pipefail

# Reads the agent-run log (Tasks/_calibration/agent-run-log.md) and prints, per coefficient key
# that has data, the observed interquartile range and median in whole minutes. The output is a
# proposal for `## AgentRunCoefficients`; this script never writes a config.

usage() {
  cat <<'USAGE'
usage: run-calibration.sh <log>

  Prints one line per key that has data:
    | <key> | <q1>–<q3> | median <m>, <n> rows |
  Rows used: source = workflow, type other than EPIC. Fewer than three such rows
  proposes nothing. A malformed row is skipped with a warning on stderr. A row
  with 0 phases or 0 modules stays out only of the keys that divide by it.
USAGE
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
if [ "$#" -ne 1 ]; then
  usage >&2
  exit 2
fi

log="$1"
if [ ! -f "$log" ]; then
  echo "run-calibration: no log at $log; nothing proposed"
  exit 0
fi

python3 -I - "$log" <<'PY'
import math
import re
import statistics
import sys

COLUMNS = ("date task_id type mode phases modules driver forecast actual execute validation "
           "review fix_rounds fix_time gates_forecast gates source in_range variance_reason").split()
MINUTES = ("phases", "modules", "execute", "validation", "review", "fix_rounds", "fix_time")
NEED = 3
KEYS = ("execute_per_phase", "validation_per_module", "driver_scenario", "review", "fix_round")


def cells(line):
    # A pipe escaped with a backslash belongs to its cell.
    parts = re.split(r"(?<!\\)\|", line.strip())
    if parts and parts[0].strip() == "":
        parts = parts[1:]
    if parts and parts[-1].strip() == "":
        parts = parts[:-1]
    return [p.strip() for p in parts]


def warn(n, reason):
    print(f"run-calibration: line {n}: {reason}, skipped", file=sys.stderr)


def half_up(x):
    return math.floor(x + 0.5)


def spread(values):
    v = sorted(values)
    if len(v) == 1:
        q1 = m = q3 = v[0]
    else:
        q1, m, q3 = statistics.quantiles(v, n=4, method="inclusive")
    return half_up(q1), half_up(q3), half_up(m)


with open(sys.argv[1], encoding="utf-8") as fh:
    lines = fh.read().splitlines()

rows = []
in_table = False
found_header = False
for n, line in enumerate(lines, 1):
    if not line.lstrip().startswith("|"):
        in_table = False
        continue
    c = cells(line)
    if not in_table:
        if c == COLUMNS:
            in_table = True
            found_header = True
        continue
    if all(re.fullmatch(r":?-{3,}:?", x) for x in c):
        continue
    if len(c) != len(COLUMNS):
        warn(n, f"expected {len(COLUMNS)} cells, got {len(c)}")
        continue
    r = dict(zip(COLUMNS, c))
    if r["source"] not in ("workflow", "git"):
        warn(n, f"source is {r['source']!r}, not workflow or git")
        continue
    if r["source"] != "workflow" or r["type"] == "EPIC":
        continue
    bad = next((k for k in MINUTES if not re.fullmatch(r"\d+", r[k])), None)
    if bad:
        warn(n, f"{bad} is not a whole number: {r[bad]!r}")
        continue
    if r["driver"] not in ("yes", "no"):
        warn(n, f"driver is {r['driver']!r}, not yes or no")
        continue
    for k in MINUTES:
        r[k] = int(r[k])
    # A row with no phases or no modules is still usable: it only stays out of the
    # keys that divide by the count it lacks.
    rows.append(r)

if not found_header:
    print(f"run-calibration: no table with the agent-run-log header in {sys.argv[1]}", file=sys.stderr)

if len(rows) < NEED:
    print(f"run-calibration: {len(rows)} usable rows, need {NEED}; nothing proposed")
    sys.exit(0)

series = {k: [] for k in KEYS}
no_driver = [r for r in rows if r["driver"] == "no" and r["modules"] > 0]
vpm = [r["validation"] / r["modules"] for r in no_driver]
series["validation_per_module"] = vpm
series["execute_per_phase"] = [r["execute"] / r["phases"] for r in rows if r["phases"] > 0]
series["review"] = [r["review"] for r in rows]
series["fix_round"] = [r["fix_time"] / r["fix_rounds"] for r in rows if r["fix_rounds"] > 0]
driver_rows = [r for r in rows if r["driver"] == "yes"]
if vpm:
    base = statistics.median(vpm)
    series["driver_scenario"] = [r["validation"] - r["modules"] * base for r in driver_rows]
elif driver_rows:
    print("run-calibration: driver_scenario: no driver = no rows to subtract", file=sys.stderr)

for key in KEYS:
    # A coefficient is a duration: a sample that is zero or negative says the row
    # is off, not that the step costs nothing, so it never enters a range.
    kept = [v for v in series[key] if v > 0]
    dropped = len(series[key]) - len(kept)
    values = kept
    if not values:
        if dropped:
            print(f"run-calibration: {key}: {dropped} non-positive samples dropped", file=sys.stderr)
        continue
    q1, q3, m = spread(values)
    print(f"| {key} | {q1}–{q3} | median {m}, {len(values)} rows |")
PY
