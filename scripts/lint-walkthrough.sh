#!/usr/bin/env bash
set -euo pipefail

# Checks a task's Walkthrough.md against the task's history and against its own header: a commit
# ## Commits names that a reset or a squash dropped, a section the skill requires for the file's
# depth, a deep section that holds more than one commit, and a commit of a declared range that the
# body never names — what a patch that cut the file short leaves behind.
#
# Usage: scripts/lint-walkthrough.sh <task-dir>
# Exit:  0 nothing found, or nothing to measure (no Walkthrough.md, no Base.md, an EPIC);
#        1 one line per finding, "Walkthrough.md: <class>: <what> (<where>)";
#        2 usage, or task-ranges.sh could not answer.

[ "$#" -eq 1 ] || { echo "usage: $0 <task-dir>" >&2; exit 2; }
[ -d "$1" ] || { echo "not a directory: $1" >&2; exit 2; }

python3 - "$(dirname -- "${BASH_SOURCE[0]}")/task-ranges.sh" "$1" <<'PY'
import os, re, subprocess, sys

RANGES, TASK = sys.argv[1], sys.argv[2]
SHA = r'[0-9a-f]{7,40}'
# Every backticked sha or sha range on a line, wherever it sits: a heading may put a word or bold
# markup before one.
TOKEN = re.compile(r'`(%s)(?:\.\.(%s))?`' % (SHA, SHA))
NUMBER = re.compile(r'^###\s+([\d\u2013-]+)')
FENCE = re.compile(r'^\s*(`{3,}|~{3,})')
# task-walkthrough, ## Structure: the sections each depth carries.
SECTIONS = {
    'deep': ['What changed', 'Glossary', 'Summary', 'Commit order', 'Plan vs. outcome', 'Commits',
             'How it works', 'Out of scope', 'Follow-ups'],
    'brief': ['What changed', 'Summary', 'Plan vs. outcome', 'Commits', 'How it works', 'Follow-ups'],
}


def task_type():
    try:
        with open(os.path.join(TASK, 'Task.md'), encoding='utf-8') as fh:
            m = re.search(r'^\[TASK_TYPE\]\s*=\s*\[?([A-Za-z_]+)', fh.read(), re.M)
            return m.group(1).upper() if m else None
    except OSError:
        return None


def ranges(*args):
    r = subprocess.run([RANGES] + list(args), capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit(2)
    return r.stdout.split()


def cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]


path = os.path.join(TASK, 'Walkthrough.md')
# An epic's ## Commits holds a section per step, not per commit.
if not os.path.isfile(path) or not os.path.isfile(os.path.join(TASK, 'Base.md')) or task_type() == 'EPIC':
    sys.exit(0)

headings, named, headers, perimeter, columns = [], [], [], [], None
where, fence, part = None, None, 'header'
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
        part, where = line[3:].strip(), None
        headings.append(part)
        continue
    if part == 'header' and line.startswith('|'):
        row = cells(line)
        if columns is None and 'Range' in row and 'Commits' in row:
            columns = (row.index('Range'), row.index('Commits'))
        elif columns and not set(''.join(row)) <= set('-: '):
            perimeter.append(row)
        continue
    if part != 'Commits':
        continue
    if line.startswith('### '):
        if line.strip() == '### Bookkeeping':
            where = 'Bookkeeping'
            continue
        m = NUMBER.match(line)
        where = '### ' + m.group(1) if m else '###'
        found = [t.groups() for t in TOKEN.finditer(line)]
        headers.append((where, len(found)))
        named += [(t, where) for t in found]
    elif where in (None, 'Bookkeeping') and line.startswith('- '):
        # Bullets inside a commit's own section are its prose, not the log.
        named += [(t.groups(), where or 'brief') for t in TOKEN.finditer(line)]

deep = 'Glossary' in headings or any(n for _, n in headers)
declared = []
for row in perimeter:
    m = TOKEN.search(row[columns[0]]) if len(row) > max(columns) else None
    if m:
        declared.append((row[0].strip('`'), m.group(1), m.group(2) or m.group(1), row[columns[1]]))

ends = sorted({s for (a, b), _ in named for s in (a, b) if s} | {s for _, a, b, _ in declared for s in (a, b)})
gone = set(ranges('unreachable', TASK, *ends)) if ends else set()

found = []
for (a, b), w in named:
    found += ['unreachable: %s is not in the task\'s history (%s)' % (s, w) for s in (a, b) if s in gone]
for repo, a, b, _ in declared:
    found += ['unreachable: %s is not in the task\'s history (header %s)' % (s, repo) for s in dict.fromkeys((a, b)) if s in gone]
if columns is None:
    found.append('section: no perimeter table with Range and Commits (header)')
found += ['section: missing (## %s)' % s for s in SECTIONS['deep' if deep else 'brief'] if s not in headings]
if deep:
    found += ['heading: %d commits in one section (%s)' % (n, w) for w, n in headers if n > 1]

covered = set()
for (a, b), _ in named:
    if a in gone or b in gone:
        continue
    covered.update(ranges('commits', TASK, '%s..%s' % (a, b)) if b else [a])
for repo, a, b, count in declared:
    if a in gone or b in gone:
        continue
    listed = ranges('commits', TASK, '%s..%s' % (a, b))
    found += ['missing: %s is not named in ## Commits (%s)' % (c[:7], repo)
              for c in listed if not any(c.startswith(s) for s in covered)]
    if count.strip() != str(len(listed)):
        found.append('count: the header says %s, the range holds %d (%s)' % (count.strip(), len(listed), repo))

if found:
    print('\n'.join('Walkthrough.md: ' + f for f in found))
    sys.exit(1)
PY
