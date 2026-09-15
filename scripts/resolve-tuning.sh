#!/usr/bin/env bash
set -euo pipefail

# Resolves the model and effort maps a task dispatches with — conventions/stage-dispatch.md → Model
# and effort. The orchestrator ships the two lines as the contract's models and effort fields.
#
# Usage: scripts/resolve-tuning.sh <task-dir>
# Exit:  0, or 2 on a usage error. One stderr line per entry it could not use.
#
# Key by key: Task.md [MODELS] / [EFFORT] -> for a .step/ folder, the epic's Task.md above it ->
# the nearest CLAUDE-spine-toolkit.md ## Models / ## Effort -> the defaults below.
# workflows/profile-epic.js copies this vocabulary for the steps it pushes, and
# tests/foundation/lib/model-and-effort.test.bats fails when the two disagree.
ROLES="architect developer tester reviewer refactorer validator security diagnostics"
MODELS="opus sonnet haiku fable platform"
EFFORTS="low medium high xhigh max session"

[ "$#" -eq 1 ] || { echo "usage: $0 <task-dir>" >&2; exit 2; }
[ -d "$1" ] || { echo "not a directory: $1" >&2; exit 2; }

python3 - "$ROLES" "$MODELS" "$EFFORTS" "$1" <<'PY'
import os, re, sys

ROLES, MODEL_VALUES, EFFORT_VALUES = (s.split() for s in sys.argv[1:4])
TASK_DIR = sys.argv[4]

AXES = (
    # contract field, Task.md field, config block, keys, values, defaults
    ('models', 'MODELS', 'Models', ['light'] + ROLES, MODEL_VALUES, dict({r: 'platform' for r in ROLES}, light='sonnet')),
    ('effort', 'EFFORT', 'Effort', ROLES, EFFORT_VALUES, {r: 'session' for r in ROLES}),
)


def task_entries(path, name):
    """The entries of [NAME] = [...], anchored at column 0: every template ships the same line
    commented out as documentation, and that one is not a value."""
    try:
        with open(path, encoding='utf-8') as fh:
            for line in fh:
                m = re.match(r'^\[%s\]\s*=\s*\[([^\]]*)\]' % name, line)
                if m:
                    return [e.strip() for e in m.group(1).split(',') if e.strip()]
    except OSError:
        pass
    return []


def config(start):
    """The nearest CLAUDE-spine-toolkit.md at or above start — the lookup lint-artifact-budget.sh does."""
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
    """The value lines under ## <name>, outside the parenthetical guidance a template block carries."""
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


def sources(field, block_name):
    """(label, entries), nearest first."""
    task_md = os.path.join(TASK_DIR, 'Task.md')
    found = [('%s [%s]' % (task_md, field), task_entries(task_md, field))]
    if os.path.basename(os.path.normpath(TASK_DIR)).endswith('.step'):
        epic_md = os.path.join(os.path.dirname(os.path.abspath(TASK_DIR)), 'Task.md')
        if os.path.isfile(epic_md):
            found.append(('%s [%s]' % (epic_md, field), task_entries(epic_md, field)))
    cfg = config(TASK_DIR)
    found.append(('%s ## %s' % (cfg, block_name), block(cfg, block_name)))
    return found


for name, field, block_name, keys, values, defaults in AXES:
    resolved, decided = dict(defaults), set()
    for label, entries in sources(field, block_name):
        for entry in entries:
            m = re.fullmatch(r'([A-Za-z]+)\s*:\s*([A-Za-z]+)', entry)
            key, value = (m.group(1).lower(), m.group(2).lower()) if m else (None, None)
            if key not in keys or value not in values:
                print("%s: '%s' not recognized, skipped" % (label, entry), file=sys.stderr)
                continue
            if key not in decided:
                resolved[key] = value
                decided.add(key)
    print('%s={%s}' % (name, ', '.join('%s: %s' % (k, resolved[k]) for k in keys)))
PY
