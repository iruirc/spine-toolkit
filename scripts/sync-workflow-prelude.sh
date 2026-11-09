#!/usr/bin/env bash
set -euo pipefail

# Copies the shared prelude from workflow-src/prelude.js into every workflows/profile-*.js.
#
# A workflow script runs in a sandbox that loads no modules, so every profile script carries its own
# copy of the prelude. The copy is generated: it is edited in workflow-src/prelude.js and written into
# each script between the `// ── prelude ─` and `// ── end prelude ─` lines by this script.
# scripts/lint-workflows.sh fails CI on a copy that differs from the source.
#
# Usage: scripts/sync-workflow-prelude.sh [--check]
#   (no flag)  rewrite every script whose prelude differs from the source
#   --check    write nothing; list the scripts that differ
#
# Exit: 0 in sync (or written), 1 --check found a difference, 2 usage or structure error. On 2
# nothing is written: every script is checked before the first one is touched.

cd "$(dirname "$0")/.."

mode=write
case "${1:-}" in
  "") ;;
  --check) mode=check ;;
  *) echo "usage: scripts/sync-workflow-prelude.sh [--check]" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "usage: scripts/sync-workflow-prelude.sh [--check]" >&2; exit 2; }

python3 - "$mode" <<'PY'
import glob, re, sys

mode = sys.argv[1]
SOURCE = 'workflow-src/prelude.js'
BLOCK = re.compile(r'^// ── prelude ─.*?^// ── end prelude ─.*?$', flags=re.M | re.S)
OPEN = re.compile(r'^// ── prelude ─', flags=re.M)
CLOSE = re.compile(r'^// ── end prelude ─', flags=re.M)
HINT = 'run scripts/sync-workflow-prelude.sh'

def fail(lines):
    for line in lines:
        print(f'sync-workflow-prelude: {line}', file=sys.stderr)
    sys.exit(2)

def read(path):
    with open(path, encoding='utf-8', newline='') as f:
        return f.read()

try:
    source = read(SOURCE)
except FileNotFoundError:
    fail([f'{SOURCE}: missing — the source every workflows/profile-*.js prelude is generated from'])
m = BLOCK.search(source)
if not m:
    fail([f'{SOURCE}: no `// ── prelude ─` … `// ── end prelude ─` block'])
block = m.group(0)

scripts = sorted(glob.glob('workflows/profile-*.js'))
if not scripts:
    fail(['no workflows/profile-*.js to sync'])

errors, plan = [], []
for path in scripts:
    text = read(path)
    opens, closes = len(OPEN.findall(text)), len(CLOSE.findall(text))
    if opens != 1 or closes != 1:
        errors.append(f'{path}: expected one opening and one closing prelude marker, found {opens} and {closes}')
        continue
    m = BLOCK.search(text)
    if not m:
        errors.append(f'{path}: the closing prelude marker comes before the opening one')
        continue
    new =text[:m.start()] + block + text[m.end():]
    if new != text:
        plan.append((path, new))
if errors:
    fail(errors)

if mode == 'check':
    for path, _ in plan:
        print(f'{path}: prelude differs from {SOURCE} — {HINT}')
    sys.exit(1 if plan else 0)

for path, new in plan:
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(new)
    print(f'synced {path}')
print(f'synced {len(plan)} of {len(scripts)}')
PY
