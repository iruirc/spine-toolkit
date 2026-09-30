#!/usr/bin/env bash
set -euo pipefail

# Names each case of a ManualChecks.md that carries no code reference, which ## Grounding of the
# manual-checks skill requires of every case. The cold reader never sees code, so it cannot tell.
#
# Usage: scripts/lint-manual-checks.sh <ManualChecks.md>
# Exit:  0 every case carries a reference, or nothing to measure (no file, no case);
#        1 one line per case, "ManualChecks.md: case <N>: no code reference (## Grounding)";
#        2 usage.

[ "$#" -eq 1 ] || { echo "usage: $0 <ManualChecks.md>" >&2; exit 2; }
[ -f "$1" ] || exit 0

python3 - "$1" <<'PY'
import re, sys

text = open(sys.argv[1], encoding='utf-8').read()
# A gloss is a parenthesis holding name:line, as in (snap_resolver:88) or (greeting, probe.src:9).
REF = re.compile(r'\([^()]*[A-Za-z_][\w./-]*:\d+[^()]*\)')
cases = re.findall(r'^### (\d+)\.(.*?)(?=^##)', text + '\n##', re.M | re.S)
missing = [n for n, body in cases if not REF.search(body)]
for n in missing:
    print(f'ManualChecks.md: case {n}: no code reference (## Grounding)')
sys.exit(1 if missing else 0)
PY
