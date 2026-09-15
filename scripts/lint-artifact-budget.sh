#!/usr/bin/env bash
set -euo pipefail

# Measures a task folder's artifacts against their line ceilings.
# The axis, and why this is a script rather than a sentence in a brief: conventions/task-scale.md.
#
# Usage: scripts/lint-artifact-budget.sh [--task-docs] <task-dir> [<task-dir> ...]
#        scripts/lint-artifact-budget.sh --budgets <task-dir>
# Exit:  0 nothing over budget (or nothing measured), 1 something over, 2 usage.
#
# Without a flag: a lite task's own artifacts. --task-docs adds the Task.md of every .step/ folder
# at any scale — its ceiling and its three anchors (skills/task-documents/SKILL.md). --budgets
# prints the ceilings a task resolves to, in the Outbound Contract's brace syntax, and measures
# nothing: the orchestrator ships that line as the contract's budgets field.
#
# Scale per task dir: Task.md [SCALE] -> the nearest CLAUDE-spine-toolkit.md ## Scale -> full.
# Ceilings: CAPS below, overridden per artifact by ## Budgets in that same config.
# REVIEW and RESEARCH are never measured: neither has an implementing stage, and the artifact
# their run produces IS the deliverable. EPIC is never measured either, for a different reason:
# its own Plan.md and Done.md are not gated by this ceiling (workflow-epic/SKILL.md). Its
# .step/ subfolders are unaffected — walk() measures each one against its own Task.md.

# First draft, taken from the shape of existing artifacts rather than from a measurement; the
# design's Rollout §1 revises them. workflows/profile-*.js carries the same table as its prelude
# CAP map, and tests/foundation/lib/artifact-budget.test.bats fails when the two disagree.
CAPS="Reproduce.md:120 Plan.md:200 Validation.md:100 Review.md:120 Done.md:80 Task.md:100"

[ "$#" -ge 1 ] || { echo "usage: $0 [--task-docs] <task-dir> [<task-dir> ...] | --budgets <task-dir>" >&2; exit 2; }

python3 - "$CAPS" "$@" <<'PY'
import os, re, sys

DEFAULTS = dict((n, int(v)) for n, v in (p.split(':') for p in sys.argv[1].split()))
ANCHORS = ['### Expected behaviour', '### Questions for Research', '### Acceptance']
UNMEASURED = {'REVIEW', 'RESEARCH', 'EPIC'}

args = sys.argv[2:]
task_docs = '--task-docs' in args
print_budgets = '--budgets' in args
dirs = [a for a in args if a not in ('--task-docs', '--budgets')]
if any(a.startswith('--') for a in dirs) or not dirs or (print_budgets and (task_docs or len(dirs) != 1)):
    print('usage: lint-artifact-budget.sh [--task-docs] <task-dir> [<task-dir> ...] | --budgets <task-dir>', file=sys.stderr)
    sys.exit(2)

violations = []
reported = set()


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


def config(start):
    """The nearest CLAUDE-spine-toolkit.md at or above start."""
    d = os.path.abspath(start)
    while True:
        cfg = os.path.join(d, 'CLAUDE-spine-toolkit.md')
        if os.path.isfile(cfg):
            return cfg
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def block(cfg, name):
    """The value lines under ## <name>: non-empty, outside the parenthetical guidance a
    template block carries, which may run over several lines."""
    if not cfg:
        return []
    out, inside, paren = [], False, False
    with open(cfg, encoding='utf-8') as fh:
        for line in fh:
            if line.startswith('## '):
                if inside:
                    break
                inside = line.strip() == '## ' + name
                continue
            if not inside or not line.strip():
                continue
            if paren or line.lstrip().startswith('('):
                paren = not line.rstrip().endswith(')')
                continue
            out.append(line.strip())
    return out


def project_scale(start):
    lines = block(config(start), 'Scale')
    return lines[0].lower() if lines else None


def budgets(start):
    """CAPS overridden by ## Budgets. A line that names no artifact CAPS knows, or whose ceiling
    is not a positive whole number, keeps the default and is reported once."""
    cfg = config(start)
    caps = dict(DEFAULTS)
    for line in block(cfg, 'Budgets'):
        m = re.match(r'^(\S+)\s*:\s*(\S+)$', line)
        name, value = (m.group(1), m.group(2)) if m else (line, '')
        if name in caps and value.isdigit() and int(value) > 0:
            caps[name] = int(value)
        elif (cfg, line) not in reported:
            reported.add((cfg, line))
            print("%s: budget '%s' not recognized, keeping the default" % (cfg, line), file=sys.stderr)
    return caps


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
    scale = (field(task_md, 'SCALE') or '').lower() or project_scale(task_dir) or 'full'
    if scale != 'lite':
        # Garbage resolves to full, same as a missing block — that direction is safe (the
        # task runs deeper, not shallower). But full and garbage must not look alike: an
        # unrecognized value is reported, so a typo shows up rather than passing as silence.
        if scale != 'full':
            print(
                "%s: scale '%s' not recognized, treating as full (not measured)"
                % (task_dir, scale),
                file=sys.stderr,
            )
        return
    for name, cap in sorted(budgets(task_dir).items()):
        if name == 'Task.md':
            continue
        path = os.path.join(task_dir, name)
        if not os.path.isfile(path):
            continue
        n = count(path)
        if n is not None and n > cap:
            violations.append('%s: %d lines, lite ceiling %d' % (path, n, cap))


def check_step(step_dir):
    """A step's Task.md at any scale: the what-and-why layer does not depend on the task's size."""
    task_md = os.path.join(step_dir, 'Task.md')
    if not os.path.isfile(task_md):
        return
    cap = budgets(step_dir)['Task.md']
    n = count(task_md)
    if n is None:
        return
    if n > cap:
        violations.append('%s: %d lines, ceiling %d' % (task_md, n, cap))
    with open(task_md, encoding='utf-8') as fh:
        lines = [l.rstrip('\n') for l in fh]
    for anchor in ANCHORS:
        if anchor not in lines:
            violations.append('%s: anchor "%s" missing' % (task_md, anchor))
            continue
        body = []
        for l in lines[lines.index(anchor) + 1:]:
            if l.startswith('## ') or l.startswith('### '):
                break
            if l.strip():
                body.append(l.strip())
        if not body:
            violations.append('%s: anchor "%s" has no text' % (task_md, anchor))
        elif body == ['—']:
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
    caps = budgets(dirs[0])
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
