#!/usr/bin/env bash
set -euo pipefail

# Checks the ## Regression set table a validator writes into a task's Validation.md against the
# task's history: a repository the task changed that the table leaves out, a ran row without a test
# count or a log, a ran row that a later code commit made stale, a repository carried whole from an
# earlier Validation although it changed since, and a PASSED status without the records the next
# Validation narrows from. Its classes: section, missing, count, log, stale, carried, record.
#
# It works on repositories, never on modules: which module of a repository should have run is the
# module graph, and the reviewer checks that. A repository counts as changed when
# task-ranges.sh ranges --since base holds a commit of it (or cannot tell, state not ok) or
# task-ranges.sh dirty names it. Every question about git goes through task-ranges.sh; a commit that
# touches only the tasks folder is not one (the Validation.md commit itself must not age its own row).
#
# The table format is in skills/task-documents/SKILL.md, in its Validation.md section.
#
# Usage: scripts/lint-validation-scope.sh <task-dir>
# Exit:  0 nothing found, or nothing to measure (no Validation.md);
#        1 one line per finding, "Validation.md: <class>: <what> (<where>)";
#        2 usage, or task-ranges.sh could not answer.

HERE="$(dirname -- "${BASH_SOURCE[0]}")"
usage() {
  echo "usage: $0 <task-dir>" >&2
  exit 2
}
[ "$#" -eq 1 ] || usage
[ -d "$1" ] || { echo "not a directory: $1" >&2; exit 2; }

python3 - "$HERE/task-ranges.sh" "$1" <<'PY'
import json, os, re, subprocess, sys

RANGES, TASK = sys.argv[1], os.path.realpath(sys.argv[2])
HEADER = ['Repository', 'Module', 'Why', 'Run', 'Tests', 'HEAD', 'Log']
SHA = re.compile(r'[0-9a-f]{7,40}')
CARRIED = re.compile(r'carried\s+`?([^\s`]+)`?')
RECORD = re.compile(r'^\[VALIDATED_COMMIT\]\s*=\s*(.*)$')


def ask(*args):
    r = subprocess.run([RANGES] + list(args), capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit(2)
    return r.stdout.strip()


def cells(line):
    # a cell code-formatted in single backticks reads as its plain value
    return [re.sub(r'^`([^`]*)`$', r'\1', c.strip()).strip() for c in line.strip().strip('|').split('|')]


path = os.path.join(TASK, 'Validation.md')
if not os.path.isfile(path):
    sys.exit(0)
with open(path, encoding='utf-8') as fh:
    lines = fh.read().split('\n')

found = []

# The section runs from its heading to the next ## heading; the table is its first run of | lines.
start = next((i for i, l in enumerate(lines) if re.fullmatch(r'##\s+Regression set\s*', l.strip())), None)
table = []
if start is None:
    found.append('section: no ## Regression set (Validation.md)')
else:
    end = next((i for i in range(start + 1, len(lines)) if re.match(r'##\s', lines[i])), len(lines))
    body = [l.strip() for l in lines[start + 1:end]]
    first = next((i for i, l in enumerate(body) if l.startswith('|')), None)
    if first is not None:
        while first < len(body) and body[first].startswith('|'):
            table.append(body[first])
            first += 1
    if not table or cells(table[0]) != HEADER:
        found.append('section: no table with the header %s (## Regression set)' % ' | '.join(HEADER))
        table = []
    elif len(table) < 2 or not all(re.fullmatch(r':?-+:?', c) for c in cells(table[1])):
        found.append('section: the header is not followed by a separator line (## Regression set)')
        table = []

known = json.loads(ask('ranges', TASK, '--since', 'base'))['repos']
rows = []  # (repo, module, run, tests, head, log, where)
for line in table[2:]:
    c = cells(line)
    where = 'row ' + (c[0] if c else '?')
    if len(c) != len(HEADER):
        found.append('section: a row with %d cells, not %d (%s)' % (len(c), len(HEADER), where))
        continue
    if c[1] not in ('', '—', '-'):
        where += ', ' + c[1]
    if c[0] not in known:
        found.append('section: %s is not a repository of the task (%s)' % (c[0], where))
        continue
    rows.append(tuple(c) + (where,))

listed = {r[0] for r in rows}
changed = {rel for rel, v in known.items() if v['state'] != 'ok' or v['commits'] > 0}
changed |= set(ask('dirty', TASK).split())
if table:
    found += ['missing: %s has changes and no row (## Regression set)' % rel for rel in sorted(changed - listed)]

ran = {r[0] for r in rows if r[3] == 'ran'}
for repo, module, why, run, tests, head, log, where in rows:
    if run == 'ran':
        if not re.fullmatch(r'\d+', tests):
            found.append('count: Tests is "%s", not a number (%s)' % (tests, where))
        target = os.path.realpath(os.path.join(TASK, log))
        if os.path.isabs(log) or not target.startswith(TASK + os.sep) or not os.path.isfile(target):
            found.append('log: "%s" is not a file of the task folder (%s)' % (log, where))
        if not SHA.fullmatch(head):
            found.append('stale: HEAD "%s" is not a sha (%s)' % (head, where))
        else:
            n = ask('count', TASK, repo, head)
            if n == 'rewritten':
                found.append('stale: HEAD %s is not in the history of %s (%s)' % (head, repo, where))
            elif n != '0':
                found.append('stale: %s commits after %s (%s)' % (n, head, where))
        continue
    m = CARRIED.fullmatch(run)
    if not m or not SHA.fullmatch(m.group(1)):
        found.append('section: Run is "%s", not ran or carried <sha> (%s)' % (run, where))
        continue
    n = ask('count', TASK, repo, m.group(1))
    if n == 'rewritten':
        found.append('carried: %s is not in the history of %s (%s)' % (m.group(1), repo, where))
    elif n != '0' and repo not in ran:
        found.append('carried: %s commits after %s and no ran row for the repository (%s)' % (n, m.group(1), where))

# A PASSED Validation leaves the records the next one narrows from, one per repository it covered.
if lines and re.match(r'\[VALIDATION_STATUS\]\s*=\s*PASSED\b', lines[0].strip()):
    recorded = set()
    for line in lines:
        m = RECORD.match(line.strip())
        v = m and re.fullmatch(r'(?:(.+?):\s+)?([0-9a-f]{7,40})', m.group(1).strip())
        if v:
            recorded.add(v.group(1) or '.')
    found += ['record: no [VALIDATED_COMMIT] line for %s (closing block)' % repo for repo in sorted(listed - recorded)]

if found:
    print('\n'.join('Validation.md: ' + f for f in found))
    sys.exit(1)
PY
