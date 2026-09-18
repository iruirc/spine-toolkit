#!/usr/bin/env bash
set -euo pipefail

# Resolves every setting a task runs with: one chain, one reader of CLAUDE-spine-toolkit.md.
# The fields, their values and their defaults: conventions/task-settings.md.
#
# Usage: scripts/resolve-settings.sh json <task-dir>     # every field as one JSON object
#        scripts/resolve-settings.sh show <task-dir>     # the same as Task.md lines, with sources
#        scripts/resolve-settings.sh raw  <dir> <block>  # the value lines of one config block
# Exit:  0, or 2 on a usage error. One stderr line per entry it could not use.
#
# Key by key: Task.md [FIELD] -> for a .step/ folder, the epic's Task.md above it -> the nearest
# CLAUDE-spine-toolkit.md -> the defaults below. walkthrough has one more step: off when the
# resolved scale is lite, which beats the project and loses to the task's own [WALKTHROUGH].
ROLES="architect developer tester reviewer refactorer validator security diagnostics"
MODELS="opus sonnet haiku fable session"
# A `platform` left by 1.11.0 reads as if its line were absent, not as `session`,
# so the validator keeps its `sonnet` default.
UNSET_MODELS="platform"
EFFORTS="low medium high xhigh max session"
# The per-artifact line ceilings. workflows/profile-*.js carries the same table as its prelude
# CAP map, and tests/foundation/lib/artifact-budget.test.bats fails when the two disagree.
CAPS="Reproduce.md:120 Plan.md:200 Validation.md:100 Review.md:120 Done.md:80 Task.md:100"

[ "$#" -ge 2 ] || { echo "usage: $0 json|show <task-dir> | raw <dir> <block>" >&2; exit 2; }
[ -d "$2" ] || { echo "not a directory: $2" >&2; exit 2; }
[ "$1" != raw ] || [ "$#" -ge 3 ] || { echo "usage: $0 raw <dir> <block>" >&2; exit 2; }

python3 - "$ROLES" "$MODELS" "$EFFORTS" "$UNSET_MODELS" "$CAPS" "$@" <<'PY'
import json, os, re, sys

ROLES, MODEL_VALUES, EFFORT_VALUES, UNSET_MODELS = (s.split() for s in sys.argv[1:5])
CAPS = dict((n, int(v)) for n, v in (p.split(':') for p in sys.argv[5].split()))
CMD, TARGET = sys.argv[6], sys.argv[7]
BLOCK = sys.argv[8] if len(sys.argv) > 8 else None

# field, Task.md field, config block, key (None = the block's first value line), values, default
SCALARS = (
    ('lang', None, 'Language', None, ['en', 'ru'], 'en'),
    ('mode', 'WORKFLOW_MODE', 'Mode', None, ['manual', 'auto'], 'manual'),
    ('progress', None, 'Progress', None, ['quiet', 'normal', 'live'], 'normal'),
    ('settings_report', None, 'Progress', 'settings', ['diff', 'full', 'off'], 'diff'),
    ('scale', 'SCALE', 'Scale', None, ['lite', 'full'], 'full'),
    ('walkthrough', 'WALKTHROUGH', 'Reporting', 'walkthrough', ['brief', 'deep', 'off'], 'deep'),
    ('drive_app', 'DRIVE_APP', 'Validation', 'drive_app', ['auto', 'off'], 'auto'),
    ('manual_checks', 'MANUAL_CHECKS', 'Validation', 'manual_checks', ['auto', 'always'], 'auto'),
    ('driver', 'DRIVER', 'Validation', 'driver', None, 'auto'),
    ('phase_verification', 'PHASE_VERIFICATION', 'Validation', 'phase_verification', ['proportional', 'full'], 'proportional'),
    ('docs_lever', 'DOCS', 'Docs', 'enabled', ['on', 'off'], 'on'),
    ('docs_map', None, 'Docs', 'map', None, 'DocsMap.md'),
    ('docs_strictness', None, 'Docs', 'strictness', ['blocking', 'advisory', 'off'], 'advisory'),
    ('docs_freshness', None, 'Docs', 'freshness', ['on', 'off'], 'on'),
)
# The task field of a map is one bracketed list; the config block is one line per key.
MAPS = (
    ('models', 'MODELS', 'Models', ['light'] + ROLES, MODEL_VALUES, UNSET_MODELS,
     dict({r: 'session' for r in ROLES}, light='sonnet', validator='sonnet')),
    ('effort', 'EFFORT', 'Effort', ROLES, EFFORT_VALUES, [], {r: 'session' for r in ROLES}),
)
# A value the resolver reads but never rejects: a free-form value has no closed list.
FREE = ('driver', 'docs_map')


def warn(label, entry):
    print("%s: '%s' not recognized, skipped" % (label, entry), file=sys.stderr)


def config_path(start):
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


def task_value(path, name):
    """A bracketed Task.md field, anchored at column 0: a template ships every optional field
    commented out, and reading one of those would apply a value nobody chose."""
    try:
        with open(path, encoding='utf-8') as fh:
            for line in fh:
                m = re.match(r'^\[%s\]\s*=\s*\[([^\]]*)\]' % name, line)
                if m:
                    return m.group(1).strip()
    except OSError:
        pass
    return None


def task_map_entries(path, name):
    """Every entry of every matching [NAME] = [...] line, in file order: a map field folds every
    line, unlike the scalar path above, which stops at the first."""
    out = []
    try:
        with open(path, encoding='utf-8') as fh:
            for line in fh:
                m = re.match(r'^\[%s\]\s*=\s*\[([^\]]*)\]' % name, line)
                if m:
                    out.extend(e.strip() for e in m.group(1).split(',') if e.strip())
    except OSError:
        pass
    return out


def task_files():
    """(source label, Task.md path), nearest first."""
    out = [('task', os.path.join(TARGET, 'Task.md'))]
    if os.path.basename(os.path.normpath(os.path.abspath(TARGET))).endswith('.step'):
        out.append(('epic', os.path.join(os.path.dirname(os.path.abspath(TARGET)), 'Task.md')))
    return out


CFG = config_path(TARGET)

if CMD == 'raw':
    for line in block(CFG, BLOCK):
        print(line)
    sys.exit(0)
if CMD not in ('json', 'show'):
    print('unknown command "%s"' % CMD, file=sys.stderr)
    sys.exit(2)

resolved, sources = {}, {}

for name, task_field, block_name, key, values, default in SCALARS:
    value, source = None, 'default'
    for label, path in task_files():
        if not task_field:
            break
        raw = task_value(path, task_field)
        if raw is None or not raw:
            continue
        if values is not None and raw.lower() not in values:
            warn('Task.md [%s]' % task_field, raw)
            continue
        value, source = raw if name in FREE else raw.lower(), label
        break
    if value is None:
        lines = block(CFG, block_name)
        raw = None
        if key is None:
            raw = lines[0] if lines else None
        else:
            for line in lines:
                m = re.match(r'^%s\s*:\s*(.+)$' % re.escape(key), line)
                if m:
                    raw = m.group(1).strip()
                    break
        if raw is not None:
            if values is not None and raw.lower() not in values:
                # progress is the one field a bad value does not get reported for: the opening
                # block prints what it resolved to, so the mismatch with the file is visible.
                if name != 'progress':
                    warn('%s ## %s' % (CFG, block_name), raw)
            else:
                value, source = raw if name in FREE else raw.lower(), 'project'
    resolved[name], sources[name] = (default if value is None else value), source

# walkthrough: off on a lite task, above the project and below the task's own field.
if sources['walkthrough'] == 'default' and resolved['scale'] == 'lite':
    resolved['walkthrough'], sources['walkthrough'] = 'off', 'scale'
elif sources['walkthrough'] == 'project' and resolved['scale'] == 'lite':
    resolved['walkthrough'], sources['walkthrough'] = 'off', 'scale'

for name, task_field, block_name, keys, values, unset, defaults in MAPS:
    out, decided = dict(defaults), set()
    found = [(('Task.md [%s]' % task_field), label, task_map_entries(path, task_field))
             for label, path in task_files()]
    found.append((('%s ## %s' % (CFG, block_name)), 'project', block(CFG, block_name)))
    key_source = {}
    for label, source, entries in found:
        seen = {}
        for entry in entries:
            m = re.fullmatch(r'([A-Za-z]+)\s*:\s*([A-Za-z]+)', entry)
            k, v = (m.group(1).lower(), m.group(2).lower()) if m else (None, None)
            if k in keys and v in unset:
                continue
            if k not in keys or v not in values:
                warn(label, entry)
                continue
            seen[k] = v
        for k, v in seen.items():
            if k not in decided:
                out[k], decided = v, decided | {k}
                key_source[k] = source
                sources.setdefault('%s.%s' % (name, k), source)
    resolved[name] = out
    # The map's own source is the nearest label among the keys that were actually decided:
    # task beats epic beats project, so a task-chosen key is never reported as the project's.
    order = ['task', 'epic', 'project']
    sources[name] = min((key_source.values()), key=order.index, default='default')

caps, budget_source = dict(CAPS), 'default'
for line in block(CFG, 'Budgets'):
    m = re.match(r'^(\S+)\s*:\s*(\S+)$', line)
    name, value = (m.group(1), m.group(2)) if m else (line, '')
    if name in caps and re.fullmatch(r'[0-9]+', value) and int(value) > 0:
        caps[name], budget_source = int(value), 'project'
        # Recorded even when the value matches the default: the line was still an override,
        # and 'budgets.<name>' is what show's per-key filter (below) keys off.
        sources['budgets.%s' % name] = 'project'
    else:
        warn('%s ## Budgets' % CFG, line)
resolved['budgets'] = caps
sources['budgets'] = budget_source

if CMD == 'json':
    print(json.dumps(dict(resolved, sources=sources), ensure_ascii=False, sort_keys=True))
    sys.exit(0)

# show: the column a human reads. Task.md spells a map as one bracketed list, so that is how
# the column spells it too, and only the keys somebody chose are named.
FIELD_OF = {'mode': 'WORKFLOW_MODE', 'docs_lever': 'DOCS', 'settings_report': 'SETTINGS_REPORT'}
rows, rest = [], 0
for name in [s[0] for s in SCALARS] + ['models', 'effort', 'budgets']:
    if sources[name] == 'default':
        rest += 1
        continue
    value = resolved[name]
    if isinstance(value, dict):
        chosen = [k for k in value if sources.get('%s.%s' % (name, k))]
        if not chosen:
            rest += 1
            continue
        text = ', '.join('%s: %s' % (k, value[k]) for k in chosen)
    else:
        text = value
    rows.append(('[%s]' % FIELD_OF.get(name, name.upper()), text, sources[name]))
width = max(len(r[0]) for r in rows) if rows else 0
for label, text, source in rows:
    print('%-*s = [%s]  # %s' % (width, label, text, source))
if rest:
    print('# %d more at their default' % rest)
PY
