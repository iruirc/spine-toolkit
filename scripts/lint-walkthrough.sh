#!/usr/bin/env bash
set -euo pipefail

# Checks every commit ## Commits of a task's Walkthrough.md names against the task's history: a
# section of a commit a reset or a squash dropped describes what the reader will not find in git log.
#
# Usage: scripts/lint-walkthrough.sh <task-dir>
# Exit:  0 every named commit is the task's, or nothing to measure (no Walkthrough.md, no Base.md,
#        an EPIC); 1 one line per commit that is not; 2 usage, or task-ranges.sh could not answer.

[ "$#" -eq 1 ] || { echo "usage: $0 <task-dir>" >&2; exit 2; }
[ -d "$1" ] || { echo "not a directory: $1" >&2; exit 2; }

python3 - "$(dirname -- "${BASH_SOURCE[0]}")/task-ranges.sh" "$1" <<'PY'
import os, re, subprocess, sys

RANGES, TASK = sys.argv[1], sys.argv[2]
SHA = r'[0-9a-f]{7,40}'
# Every backticked sha or sha range on a line, wherever it sits: a heading may group several, or
# put a word or bold markup before one.
TOKEN = re.compile(r'`(%s)(?:\.\.(%s))?`' % (SHA, SHA))
NUMBER = re.compile(r'^###\s+([\d\u2013-]+)')
FENCE = re.compile(r'^\s*(`{3,}|~{3,})')


def task_type():
    try:
        with open(os.path.join(TASK, 'Task.md'), encoding='utf-8') as fh:
            m = re.search(r'^\[TASK_TYPE\]\s*=\s*\[?([A-Za-z_]+)', fh.read(), re.M)
            return m.group(1).upper() if m else None
    except OSError:
        return None


def shas(line):
    return [s for m in TOKEN.finditer(line) for s in m.groups() if s]


path = os.path.join(TASK, 'Walkthrough.md')
# An epic's ## Commits holds a section per step, not per commit.
if not os.path.isfile(path) or not os.path.isfile(os.path.join(TASK, 'Base.md')) or task_type() == 'EPIC':
    sys.exit(0)

named, section, fence, inside = [], None, None, False
for line in open(path, encoding='utf-8'):
    m = FENCE.match(line)
    if m:
        # Only a run of the same character, at least as long, closes a fence.
        if fence is None:
            fence = m.group(1)
        elif m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not line.strip()[len(m.group(1)):]:
            fence = None
        continue
    if fence:
        continue
    if line.startswith('## '):
        inside, section = line.strip() == '## Commits', None
        continue
    if not inside:
        continue
    if line.startswith('### '):
        if line.strip() == '### Bookkeeping':
            section = 'Bookkeeping'
            continue
        m = NUMBER.match(line)
        section = '### ' + m.group(1) if m else '###'
        named += [(s, section) for s in shas(line)]
    elif section in (None, 'Bookkeeping') and line.startswith('- '):
        # Bullets inside a commit's own section are its prose, not the log.
        named += [(s, section or 'brief') for s in shas(line)]

if not named:
    sys.exit(0)
r = subprocess.run([RANGES, 'unreachable', TASK] + sorted({s for s, _ in named}), capture_output=True, text=True)
if r.returncode != 0:
    sys.stderr.write(r.stderr)
    sys.exit(2)
gone = set(r.stdout.split())
found = ["Walkthrough.md: %s (%s) is not in the task's history" % (s, where) for s, where in named if s in gone]
if found:
    print('\n'.join(found))
    sys.exit(1)
PY
