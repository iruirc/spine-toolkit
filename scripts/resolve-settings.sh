#!/usr/bin/env bash
set -euo pipefail

# Resolves every setting a task runs with: one chain, one reader of CLAUDE-spine-toolkit.md.
# The fields, their values and their defaults: conventions/task-settings.md.
#
# Usage: scripts/resolve-settings.sh json <task-dir>           # every field as one JSON object,
#                                                                # plus plugin_root, the core root it runs from,
#                                                                # and roots, the folders a stage may search
#        scripts/resolve-settings.sh show <task-dir> [--all]   # Task.md lines, with sources
#                                                                # --all: every field, defaults included
#        scripts/resolve-settings.sh raw  <dir> <block>        # the value lines of one config block
# Exit:  0, or 2 on a usage error. One stderr line per entry it could not take at face value.
#
# Key by key: Task.md [FIELD] -> for a .step/ folder, the epic's Task.md above it -> the nearest
# CLAUDE-spine-toolkit.md -> the defaults below. walkthrough has one more step: off when the
# resolved scale is lite, which beats the project and loses to the task's own [WALKTHROUGH].
# walkthrough_check then follows it: auto is on at deep and off at brief, and off where no file is written.
ROLES="architect developer tester reviewer refactorer validator security diagnostics"
MODELS="opus sonnet haiku fable session"
# A `platform` left by 1.11.0 reads as if its line were absent, not as `session`,
# so the validator keeps its `sonnet` default.
UNSET_MODELS="platform"
EFFORTS="low medium high xhigh max session"
# The per-artifact line ceilings. workflows/profile-*.js carries the same table as its prelude
# CAP map, and tests/foundation/lib/artifact-budget.test.bats fails when the two disagree.
CAPS="Reproduce.md:120 Plan.md:200 Validation.md:100 Review.md:120 Done.md:80 Task.md:100"

[ "$#" -ge 2 ] || { echo "usage: $0 json|show <task-dir> [--all] | raw <dir> <block>" >&2; exit 2; }
[ -d "$2" ] || { echo "not a directory: $2" >&2; exit 2; }
[ "$1" != raw ] || [ "$#" -ge 3 ] || { echo "usage: $0 raw <dir> <block>" >&2; exit 2; }
[ "$1" != show ] || [ "$#" -eq 2 ] || [ "$3" = --all ] || { echo "usage: $0 show <task-dir> [--all]" >&2; exit 2; }

# Not a setting: where this installation lives, which a Method A script cannot find for itself.
export SPINE_CORE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROLES" "$MODELS" "$EFFORTS" "$UNSET_MODELS" "$CAPS" "$@" <<'PY'
import glob, json, os, re, sys

ROLES, MODEL_VALUES, EFFORT_VALUES, UNSET_MODELS = (s.split() for s in sys.argv[1:5])

# The value kind of a map whose values are whole minutes rather than words.
MINUTES = 'minutes'


# The value one map entry contributes, or None when the entry is not one of the map's values.
def map_value(values, raw):
    if values == MINUTES:
        return int(raw) if re.fullmatch(r'[1-9][0-9]*', raw) else None
    return raw if raw in values else None


CAPS = dict((n, int(v)) for n, v in (p.split(':') for p in sys.argv[5].split()))
CMD, TARGET = sys.argv[6], sys.argv[7]
EXTRA = sys.argv[8] if len(sys.argv) > 8 else None
BLOCK = EXTRA if CMD == 'raw' else None
SHOW_ALL = CMD == 'show' and EXTRA == '--all'

# field, config/Task.md field name, values (None = open), default
SCALARS = (
    ('lang', 'LANG', ['en', 'ru'], 'en'),
    ('mode', 'WORKFLOW_MODE', ['manual', 'auto'], 'manual'),
    ('progress', 'PROGRESS', ['quiet', 'normal', 'live'], 'normal'),
    ('settings_report', 'SETTINGS_REPORT', ['diff', 'full', 'off'], 'diff'),
    ('scale', 'SCALE', ['lite', 'full'], 'full'),
    ('walkthrough', 'WALKTHROUGH', ['brief', 'deep', 'off'], 'deep'),
    ('walkthrough_check', 'WALKTHROUGH_CHECK', ['auto', 'on', 'off'], 'auto'),
    ('drive_app', 'DRIVE_APP', ['auto', 'off'], 'auto'),
    ('manual_checks', 'MANUAL_CHECKS', ['auto', 'always'], 'auto'),
    ('driver', 'DRIVER', None, 'auto'),
    ('phase_verification', 'PHASE_VERIFICATION', ['proportional', 'full'], 'proportional'),
    ('security', 'SECURITY', ['auto', 'on', 'off'], 'auto'),
    ('docs_lever', 'DOCS', ['on', 'off'], 'on'),
    ('docs_map', 'DOCS_MAP', None, 'DocsMap.md'),
    ('docs_strictness', 'DOCS_STRICTNESS', ['blocking', 'advisory', 'off'], 'advisory'),
    ('docs_freshness', 'DOCS_FRESHNESS', ['on', 'off'], 'on'),
)
# A field the config alone answers: no Task.md is read for it, which is what ## Project settings means.
PROJECT_ONLY = {'lang', 'progress', 'settings_report', 'docs_map', 'docs_strictness',
                'docs_freshness', 'budgets'}
# A map's field is one bracketed, comma-separated list, in the config exactly as in a Task.md.
MAPS = (
    ('models', 'MODELS', ['light', 'walkthrough', 'done'] + ROLES, MODEL_VALUES, UNSET_MODELS,
     dict({r: 'session' for r in ROLES}, light='sonnet', walkthrough='session', done='session',
          validator='sonnet')),
    ('effort', 'EFFORT', ['walkthrough', 'done'] + ROLES, EFFORT_VALUES, [],
     dict({r: 'session' for r in ROLES}, walkthrough='session', done='session')),
    ('long_run', 'LONG_RUN', ['stall', 'max'], MINUTES, [], {'stall': 5, 'max': 30}),
)
# A spelling an older release wrote, still applied. Reported in words a caller can tell apart from
# a typo's, so the two get different announcements.
ALIASES = {'walkthrough': {'on': 'deep'}}


def warn(label, entry):
    print("%s: '%s' not recognized, skipped" % (label, entry), file=sys.stderr)


def accept(name, values, raw, label):
    """What this entry contributes, or None when it contributes nothing and the chain goes on."""
    if values is None:
        return raw
    low = raw.lower()
    if low in values:
        return low
    alias = ALIASES.get(name, {}).get(low)
    if alias:
        print("%s: '%s' is the pre-depth spelling, read as '%s'" % (label, raw, alias), file=sys.stderr)
        return alias
    # progress is the one field a bad value does not get reported for: the opening block prints
    # what it resolved to, so the mismatch with the file is visible.
    if name != 'progress':
        warn(label, raw)
    return None


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
    template block carries, which may run over several lines. `raw` is the only caller —
    a setting is a [FIELD] line now, and what is left is the blocks a skill reads itself."""
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


def config_fields(cfg):
    """Every [FIELD] = [value] line of the config, in file order, one list per field. Anchored at
    column 0 — a commented-out line is documentation, exactly as it is in a Task.md. A field named
    twice folds as a task file's does, which is what config_value and config_entries below apply."""
    out = {}
    if not cfg:
        return out
    with open(cfg, encoding='utf-8') as fh:
        for line in fh:
            m = re.match(r'^\[([A-Z_]+)\]\s*=\s*\[([^\]]*)\]', line)
            if m:
                out.setdefault(m.group(1), []).append(m.group(2).strip())
    return out


MOVED = ('Language', 'Mode', 'Progress', 'Scale', 'Reporting', 'Validation', 'Docs', 'Budgets',
         'Models', 'Effort')


def refuse_old_format(cfg):
    """A config in the 1.x shape is an error, not a file to guess at: every field would silently
    fall to its default and a project would run on settings nobody chose."""
    if not cfg:
        return
    with open(cfg, encoding='utf-8') as fh:
        for line in fh:
            if line.startswith('## ') and line.strip()[3:] in MOVED:
                print('%s: the %s format is 2.0-incompatible, run /setup to migrate'
                      % (cfg, line.strip()), file=sys.stderr)
                sys.exit(2)


def field_entries(raw):
    """The entries of one bracketed, comma-separated field value."""
    return [e.strip() for e in (raw or '').split(',') if e.strip()]


def config_value(field):
    """A config scalar: the first [FIELD] line, as task_value takes a Task.md's first."""
    lines = CFG_FIELDS.get(field, ())
    return lines[0] if lines else None


def config_entries(field):
    """A config map's entries: every [FIELD] line folded in file order, as task_map_entries
    folds a Task.md's."""
    return [e for raw in CFG_FIELDS.get(field, ()) for e in field_entries(raw)]


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
                    out.extend(field_entries(m.group(1)))
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
refuse_old_format(CFG)

if CMD == 'raw':
    for line in block(CFG, BLOCK):
        print(line)
    sys.exit(0)
if CMD not in ('json', 'show'):
    print('unknown command "%s"' % CMD, file=sys.stderr)
    sys.exit(2)

CFG_FIELDS = config_fields(CFG)
resolved, sources, defaults = {}, {}, {}

for name, field, values, default in SCALARS:
    value, source = None, 'default'
    for label, path in ([] if name in PROJECT_ONLY else task_files()):
        raw = task_value(path, field)
        if not raw:
            continue
        value = accept(name, values, raw, 'Task.md [%s]' % field)
        if value is None:
            continue
        source = label
        break
    if value is None:
        raw = config_value(field)
        if raw:
            value = accept(name, values, raw, '%s [%s]' % (CFG, field))
            if value is not None:
                source = 'project'
    resolved[name], sources[name], defaults[name] = (default if value is None else value), source, default

# walkthrough: off on a lite task, above the project and below the task's own field.
# show_source holds what the column says where that is more than the source's bare name.
show_source = {}
if resolved['scale'] == 'lite' and sources['walkthrough'] in ('default', 'project'):
    displaced = resolved['walkthrough'] if sources['walkthrough'] == 'project' else None
    resolved['walkthrough'], sources['walkthrough'] = 'off', 'scale'
    show_source['walkthrough'] = 'scale: lite' + (' (project: %s)' % displaced if displaced else '')

# walkthrough_check follows the depth it checks. CHOSEN keeps what the chain picked, so show can
# tell a value derived from auto from one somebody wrote down.
CHOSEN = {'walkthrough_check': resolved['walkthrough_check']}
chosen, depth = CHOSEN['walkthrough_check'], resolved['walkthrough']
check = 'off' if depth == 'off' else ('on' if depth == 'deep' else 'off') if chosen == 'auto' else chosen
if check != chosen:
    show_source['walkthrough_check'] = ('walkthrough: %s' % depth if chosen == 'auto' else
                                        'walkthrough: off (%s: %s)' % (sources['walkthrough_check'], chosen))
    resolved['walkthrough_check'], sources['walkthrough_check'] = check, 'walkthrough'

for name, field, keys, values, unset, map_defaults in MAPS:
    out, decided = dict(map_defaults), set()
    found = [(('Task.md [%s]' % field), label, task_map_entries(path, field))
             for label, path in task_files()]
    found.append((('%s [%s]' % (CFG, field)), 'project', config_entries(field)))
    key_source = {}
    for label, source, entries in found:
        seen = {}
        for entry in entries:
            m = re.fullmatch(r'([A-Za-z]+)\s*:\s*(\S+)', entry)
            k, raw = (m.group(1).lower(), m.group(2).lower()) if m else (None, None)
            if k in keys and raw in unset:
                continue
            v = map_value(values, raw) if k in keys else None
            if v is None:
                warn(label, entry)
                continue
            seen[k] = v
        for k, v in seen.items():
            if k not in decided:
                out[k], decided = v, decided | {k}
                key_source[k] = source
                sources.setdefault('%s.%s' % (name, k), source)
    resolved[name], defaults[name] = out, dict(map_defaults)
    # The map's own source is the nearest label among the keys that were actually decided:
    # task beats epic beats project, so a task-chosen key is never reported as the project's.
    order = ['task', 'epic', 'project']
    sources[name] = min((key_source.values()), key=order.index, default='default')

lr = resolved['long_run']
if lr['stall'] >= lr['max']:
    print('long_run: stall %d is not below max %d, the budget fires first' % (lr['stall'], lr['max']),
          file=sys.stderr)

caps, budget_source = dict(CAPS), 'default'
for entry in config_entries('BUDGETS'):
    m = re.match(r'^(\S+)\s*:\s*(\S+)$', entry)
    name, value = (m.group(1), m.group(2)) if m else (entry, '')
    if name in caps and re.fullmatch(r'[0-9]+', value) and int(value) > 0:
        caps[name], budget_source = int(value), 'project'
        # Recorded even when the value matches the default: the entry was still an override, and
        # 'budgets.<name>' is how a caller asks which ceilings this project wrote down at all.
        sources['budgets.%s' % name] = 'project'
    else:
        warn('%s [BUDGETS]' % CFG, entry)
resolved['budgets'], defaults['budgets'] = caps, dict(CAPS)
sources['budgets'] = budget_source



def search_roots():
    """Not a setting either: where a stage may look for a file, the core root aside
    (conventions/agent-tooling.md → Finding files). The project root, then every folder
    ## Paths names under External packages or Roots; one inside a listed root adds nothing."""
    if not CFG:
        return []
    home = os.path.dirname(CFG)
    roots = [home]
    for line in block(CFG, 'Paths'):
        m = re.match(r'^-\s*(External packages|Roots):\s*(.+?)\s*$', line)
        if not m:
            continue
        key, pat = m.groups()
        # External packages is written from the project root, as docs-route.sh reads it; Roots
        # names folders outside it, so an absolute path there means what it says.
        rel = pat.lstrip('/') if key == 'External packages' else os.path.expanduser(pat)
        hits = [os.path.normpath(p) for p in sorted(glob.glob(os.path.join(home, rel))) if os.path.isdir(p)]
        if not hits and key == 'Roots':
            print("%s ## Paths: Roots '%s' names no folder, skipped" % (CFG, pat), file=sys.stderr)
        for p in hits:
            if not any(p == r or p.startswith(r + os.sep) for r in roots):
                roots.append(p)
    return roots


if CMD == 'json':
    print(json.dumps(dict(resolved, sources=sources, plugin_root=os.environ['SPINE_CORE_ROOT'],
                          roots=search_roots()),
                     ensure_ascii=False, sort_keys=True))
    sys.exit(0)

# show: the column a human reads. Task.md spells a map as one bracketed list, so that is how
# the column spells it too. A field is in the column when somebody chose it AND the value they
# chose differs from the built-in default: the shipped config template writes every field down at
# its default, and a column repeating those is one nobody reads. --all names every field and every
# map key — defaults included — and never prints the "more" line.
FIELD_OF = dict((s[0], s[1]) for s in SCALARS)
rows, rest = [], 0
for name in [s[0] for s in SCALARS] + ['models', 'effort', 'long_run', 'budgets']:
    value = resolved[name]
    if isinstance(value, dict):
        chosen = [k for k in value
                  if sources.get('%s.%s' % (name, k)) and value[k] != defaults[name][k]]
        keys = list(value) if SHOW_ALL else chosen
        if not keys:
            rest += 1
            continue
        text = ', '.join('%s: %s' % (k, value[k]) for k in keys)
    else:
        # A value derived from the default (walkthrough_check's auto) is nobody's choice either.
        if not SHOW_ALL and (sources[name] == 'default' or value == defaults[name]
                             or CHOSEN.get(name) == defaults[name]):
            rest += 1
            continue
        text = value
    rows.append(('[%s]' % FIELD_OF.get(name, name.upper()), text,
                 show_source.get(name, sources[name])))
width = max(len(r[0]) for r in rows) if rows else 0
for label, text, source in rows:
    print('%-*s = [%s]  # %s' % (width, label, text, source))
if rest:
    print('# %d more at their default' % rest)
PY
