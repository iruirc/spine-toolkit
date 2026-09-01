#!/usr/bin/env bash
set -euo pipefail

# Measures a task folder's artifacts against the ceilings a lite task's artifacts carry.
# The axis, and why this is a script rather than a sentence in a brief: conventions/task-scale.md.
#
# Usage: scripts/lint-artifact-budget.sh <task-dir> [<task-dir> ...]
# Exit:  0 nothing over budget (or nothing measured), 1 something over, 2 usage.
#
# Scale per task dir: Task.md [SCALE] -> the nearest CLAUDE-spine-toolkit.md ## Scale -> full.
# REVIEW and RESEARCH are never measured: neither has an implementing stage, and the artifact
# their run produces IS the deliverable.

# First draft, taken from the shape of existing artifacts rather than from a measurement; the
# design's Rollout §1 revises them. workflows/profile-*.js carries the same table as its prelude
# CAP map, and tests/foundation/lib/artifact-budget.test.bats fails when the two disagree.
CAPS="Reproduce.md:120 Plan.md:200 Validation.md:100 Review.md:120 Done.md:80"

[ "$#" -ge 1 ] || { echo "usage: $0 <task-dir> [<task-dir> ...]" >&2; exit 2; }

python3 - "$CAPS" "$@" <<'PY'
import os, re, sys

caps = dict((n, int(v)) for n, v in (p.split(':') for p in sys.argv[1].split()))
UNMEASURED = {'REVIEW', 'RESEARCH'}
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


def project_scale(start):
    """First non-empty, non-parenthetical line under ## Scale in the nearest config above."""
    d = os.path.abspath(start)
    while True:
        cfg = os.path.join(d, 'CLAUDE-spine-toolkit.md')
        if os.path.isfile(cfg):
            with open(cfg, encoding='utf-8') as fh:
                inside = False
                for line in fh:
                    if line.startswith('## '):
                        if inside:
                            return None
                        inside = line.strip() == '## Scale'
                        continue
                    if inside and line.strip() and not line.lstrip().startswith('('):
                        return line.strip().lower()
            return None
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


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
    for name, cap in sorted(caps.items()):
        path = os.path.join(task_dir, name)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, 'rb') as fh:
                n = sum(1 for _ in fh)
        except OSError:
            print('%s: unreadable, skipping' % path, file=sys.stderr)
            continue
        if n > cap:
            violations.append('%s: %d lines, lite ceiling %d' % (path, n, cap))


def walk(root):
    measure(root)
    for entry in sorted(os.listdir(root)):
        # _archive/ holds the copies the orchestrator took before overwriting an artifact:
        # measuring them would report a violation nobody can act on.
        if entry == '_archive':
            continue
        sub = os.path.join(root, entry)
        if os.path.isdir(sub) and entry.endswith('.step'):
            walk(sub)


for arg in sys.argv[2:]:
    if not os.path.isdir(arg):
        print('not a directory: %s' % arg, file=sys.stderr)
        sys.exit(2)
    walk(arg)

for v in violations:
    print(v)

if violations:
    print()
    print('artifact budget failed: %d artifact(s) over a lite ceiling' % len(violations))
    sys.exit(1)

print('artifact budget passed')
PY
