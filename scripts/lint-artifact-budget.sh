#!/usr/bin/env bash
set -euo pipefail

# Measures a task folder's artifacts against their line ceilings.
# The axis, and why this is a script rather than a sentence in a brief: conventions/task-scale.md.
#
# Usage: scripts/lint-artifact-budget.sh [--task-docs] <task-dir> [<task-dir> ...]
#        scripts/lint-artifact-budget.sh --budgets <task-dir>
# Exit:  0 nothing over budget (or nothing measured), 1 something over, 2 usage.
#
# Without a flag: a lite task's own artifacts. --task-docs covers every .step/ folder not yet
# started, at any scale — its ceiling and its three anchors (skills/task-documents/SKILL.md).
# --budgets prints the ceilings a task resolves to, in the Outbound Contract's brace syntax, and
# measures nothing: the orchestrator ships that line as the contract's budgets field.
#
# Scale and the per-artifact ceilings both come from scripts/resolve-settings.sh, the one reader
# of Task.md and CLAUDE-spine-toolkit.md.
# REVIEW and RESEARCH are never measured: neither has an implementing stage, and the artifact
# their run produces IS the deliverable. EPIC is never measured either, for a different reason:
# its own Plan.md and Done.md are not gated by this ceiling (workflow-epic/SKILL.md). Its
# .step/ subfolders are unaffected — walk() measures each one against its own Task.md.

[ "$#" -ge 1 ] || { echo "usage: $0 [--task-docs] <task-dir> [<task-dir> ...] | --budgets <task-dir>" >&2; exit 2; }

RESOLVE="$(dirname -- "${BASH_SOURCE[0]}")/resolve-settings.sh"
python3 - "$RESOLVE" "$@" <<'PY'
import json, os, re, subprocess, sys

ANCHORS = ['### Expected behaviour', '### Questions for Research', '### Acceptance']
UNMEASURED = {'REVIEW', 'RESEARCH', 'EPIC'}

RESOLVE = sys.argv[1]
_SETTINGS_CACHE = {}
_WARNED = set()
# The resolver reports every field it could not use; this script asked about only some of them,
# and forwarding the rest makes a [MODELS] typo arrive as a budget problem.
_MINE = []


def _emit_stderr(text, everything=False):
    """Print each resolver stderr line at most once per run: two directories under the same
    project would otherwise repeat the same warning once per directory."""
    for line in text.splitlines():
        if not line or line in _WARNED:
            continue
        if not everything and not line.split(": '", 1)[0].endswith(tuple(_MINE)):
            continue
        _WARNED.add(line)
        print(line, file=sys.stderr)


def settings(task_dir):
    """Every setting of this task dir, from the one reader (scripts/resolve-settings.sh).
    Memoized per directory. A resolver failure is an error, not a default — it stops the run
    with exit 2, the usage/malformed code this script already uses for input it cannot read."""
    if task_dir in _SETTINGS_CACHE:
        return _SETTINGS_CACHE[task_dir]
    out = subprocess.run([RESOLVE, 'json', task_dir], capture_output=True, text=True)
    _emit_stderr(out.stderr, everything=out.returncode != 0)
    if out.returncode != 0:
        print('lint-artifact-budget.sh: resolve-settings.sh failed for %s' % task_dir, file=sys.stderr)
        sys.exit(2)
    _SETTINGS_CACHE[task_dir] = json.loads(out.stdout)
    return _SETTINGS_CACHE[task_dir]


args = sys.argv[2:]
task_docs = '--task-docs' in args
print_budgets = '--budgets' in args
# --budgets reads the ceilings and nothing else, which is what lets the orchestrator announce
# every line it forwards as a budget line.
_MINE[:] = ['## Budgets'] if print_budgets else ['## Budgets', '## Scale', 'Task.md [SCALE]']
dirs = [a for a in args if a not in ('--task-docs', '--budgets')]
if any(a.startswith('--') for a in dirs) or not dirs or (print_budgets and (task_docs or len(dirs) != 1)):
    print('usage: lint-artifact-budget.sh [--task-docs] <task-dir> [<task-dir> ...] | --budgets <task-dir>', file=sys.stderr)
    sys.exit(2)

violations = []


def field(path, name):
    """A bracketed Task.md field. Anchored at column 0: every task file ships the same
    fields commented out as documentation, and reading one of those as a value would
    exempt every task in every project from the ceiling."""
    try:
        with open(path, encoding='utf-8') as fh:
            for line in fh:
                m = re.match(r'^\[%s\]\s*=\s*\[?([A-Za-z_]+)' % name, line)
                if m:
                    return m.group(1).strip().upper()
    except OSError:
        pass
    return None


def count(path):
    try:
        with open(path, 'rb') as fh:
            return sum(1 for _ in fh)
    except OSError:
        print('%s: unreadable, skipping' % path, file=sys.stderr)
        return None


def measure(task_dir):
    task_md = os.path.join(task_dir, 'Task.md')
    if not os.path.isfile(task_md):
        return
    if (field(task_md, 'TASK_TYPE') or '') in UNMEASURED:
        return
    s = settings(task_dir)
    if s.get('scale', 'full') != 'lite':
        return
    for name, cap in sorted(s.get('budgets', {}).items()):
        if name == 'Task.md':
            continue
        path = os.path.join(task_dir, name)
        if not os.path.isfile(path):
            continue
        n = count(path)
        if n is not None and n > cap:
            violations.append('%s: %d lines, lite ceiling %d' % (path, n, cap))


def check_step(step_dir):
    """A step's Task.md at any scale, not yet started: [STATUS] other than PENDING or TODO means
    the step already ran, and its Task.md is the record of that rather than a target to fix."""
    task_md = os.path.join(step_dir, 'Task.md')
    if not os.path.isfile(task_md):
        return
    status = field(task_md, 'STATUS')
    if status and status not in ('PENDING', 'TODO'):
        return
    cap = settings(step_dir).get('budgets', {}).get('Task.md', 100)
    n = count(task_md)
    if n is None:
        return
    if n > cap:
        violations.append('%s: %d lines, ceiling %d' % (task_md, n, cap))
    with open(task_md, encoding='utf-8') as fh:
        lines = [l.rstrip('\n') for l in fh]
    # Anchors count only inside ## 3. [Task]: the same heading elsewhere in the file is prose,
    # not the section the anchors belong to.
    section = []
    if '## 3. [Task]' in lines:
        start = lines.index('## 3. [Task]') + 1
        end = next((i for i in range(start, len(lines)) if lines[i].startswith('## ')), len(lines))
        section = lines[start:end]
    for anchor in ANCHORS:
        if anchor not in section:
            violations.append('%s: anchor "%s" missing' % (task_md, anchor))
            continue
        body = []
        for l in section[section.index(anchor) + 1:]:
            if l.startswith('## ') or l.startswith('### '):
                break
            if l.strip():
                body.append(l.strip())
        if not body:
            violations.append('%s: anchor "%s" has no text' % (task_md, anchor))
        elif len(body) == 1 and re.fullmatch(r'[-–—]+', body[0]):
            violations.append('%s: anchor "%s" is a bare dash, give the reason' % (task_md, anchor))


def walk(root):
    measure(root)
    if task_docs and os.path.basename(os.path.normpath(root)).endswith('.step'):
        check_step(root)
    for entry in sorted(os.listdir(root)):
        # _archive/ holds the copies the orchestrator took before overwriting an artifact:
        # measuring them would report a violation nobody can act on.
        if entry == '_archive':
            continue
        sub = os.path.join(root, entry)
        if os.path.isdir(sub) and entry.endswith('.step'):
            walk(sub)


for arg in dirs:
    if not os.path.isdir(arg):
        print('not a directory: %s' % arg, file=sys.stderr)
        sys.exit(2)

if print_budgets:
    caps = settings(dirs[0]).get('budgets', {})
    print('{%s}' % ', '.join('%s: %d' % (k, caps[k]) for k in sorted(caps)))
    sys.exit(0)

for arg in dirs:
    walk(arg)

for v in violations:
    print(v)

if violations:
    print()
    print('artifact budget failed: %d finding(s)' % len(violations))
    sys.exit(1)

print('artifact budget passed')
PY
