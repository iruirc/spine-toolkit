#!/usr/bin/env bash
set -euo pipefail

# Resolves every setting a task runs with: one chain, one reader of CLAUDE-spine-toolkit.md.
# The fields, their values and their defaults: conventions/task-settings.md.
#
# Usage: scripts/resolve-settings.sh json <task-dir> [--set <field>[.<key>]=<value>]...
#                                                  # every field as one JSON object, plus plugin_root,
#                                                  # the core root it runs from, and roots, the folders
#                                                  # a stage may search
#        scripts/resolve-settings.sh show <task-dir> [--all] [--set ...]
#                                                  # Task.md lines, with sources
#                                                  # --all: every field, defaults included
#        scripts/resolve-settings.sh open <task-dir> --method A|B [--why <text>] --range <start>:<end>
#                                         [--progress <value>] [--set ...]
#                                                  # the run's opening block, in the resolved lang
#        scripts/resolve-settings.sh raw  <dir> <block>        # the value lines of one config block
# Exit:  0, or 2 on a usage error. One stderr line per entry it could not take at face value.
#
# Key by key: --set, this run's own word -> Task.md [FIELD] -> for a .step/ folder, the epic's Task.md above it -> the nearest
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

[ "$#" -ge 2 ] || { echo "usage: $0 json|show|open <task-dir> [--all] [--set <field>=<value>]... | raw <dir> <block>" >&2; exit 2; }
[ -d "$2" ] || { echo "not a directory: $2" >&2; exit 2; }
[ "$1" != raw ] || [ "$#" -ge 3 ] || { echo "usage: $0 raw <dir> <block>" >&2; exit 2; }

# Not a setting: where this installation lives, which a Method A script cannot find for itself.
export SPINE_CORE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROLES" "$MODELS" "$EFFORTS" "$UNSET_MODELS" "$CAPS" "$@" <<'PY'
import glob, json, os, re, subprocess, sys

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
BLOCK = sys.argv[8] if CMD == 'raw' else None
SHOW_ALL = False
# open's own flags: --method, --why, --range, --progress.
OPEN = {}
# This run's own word on a field (conventions/task-settings.md → The chain): a scalar, or one key
# of a map, in the order given; a later --set of the same field or key wins.
RUN_SET = []
rest = [] if CMD == 'raw' else sys.argv[8:]
while rest:
    arg = rest.pop(0)
    if arg == '--all' and CMD == 'show':
        SHOW_ALL = True
    elif arg == '--set' and rest and re.fullmatch(r'[a-z_]+(\.[A-Za-z]+)?=\S(.*\S)?', rest[0]):
        RUN_SET.append(rest.pop(0).split('=', 1))
    elif CMD == 'open' and arg in ('--method', '--why', '--range', '--progress') and rest:
        OPEN[arg[2:]] = rest.pop(0)
    else:
        print('usage: resolve-settings.sh json|show|open <task-dir> [--all] [--set <field>[.<key>]=<value>]...',
              file=sys.stderr)
        sys.exit(2)

# field, config/Task.md field name, values (None = open), default
# A SCALARS values slot for a whole number >= 0, taken as an int.
INT = 'int'
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
    ('device', 'DEVICE', None, 'auto'),
    ('phase_verification', 'PHASE_VERIFICATION', ['proportional', 'full'], 'proportional'),
    ('fix_rounds', 'FIX_ROUNDS', INT, 2),
    ('security', 'SECURITY', ['auto', 'on', 'off'], 'auto'),
    ('docs_lever', 'DOCS', ['on', 'off'], 'on'),
    ('docs_map', 'DOCS_MAP', None, 'DocsMap.md'),
    ('docs_strictness', 'DOCS_STRICTNESS', ['blocking', 'advisory', 'off'], 'advisory'),
    ('docs_freshness', 'DOCS_FRESHNESS', ['on', 'off'], 'on'),
    ('device_source', 'DEVICE_SOURCE', None, '—'),
)
# A field the config alone answers: no Task.md is read for it, which is what ## Project settings means.
PROJECT_ONLY = {'lang', 'progress', 'settings_report', 'docs_map', 'docs_strictness',
                'docs_freshness', 'budgets', 'device_source'}
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
        # The open fields' own words: a plugin name is one word, and a sentinel is read in any spelling.
        if name == 'driver' and re.search(r'\s', raw.strip()):
            warn(label, raw)
            return None
        if name == 'device' and raw.strip().lower() == 'auto':
            return 'auto'
        if name == 'device_source' and raw.strip() == '-':
            return '—'
        return raw
    if values == INT:
        if re.fullmatch(r'[0-9]+', raw.strip()):
            return int(raw.strip())
        warn(label, raw)
        return None
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
if CMD not in ('json', 'show', 'open'):
    print('unknown command "%s"' % CMD, file=sys.stderr)
    sys.exit(2)

CFG_FIELDS = config_fields(CFG)
resolved, sources, defaults = {}, {}, {}

# What a run may set is what a task may say about itself: every field with a Task.md line.
RUN_SCALARS, RUN_MAPS = {}, {}
for target, raw in RUN_SET:
    name, _, key = target.partition('.')
    if not key and name in [s[0] for s in SCALARS] and name not in PROJECT_ONLY:
        RUN_SCALARS[name] = raw
    elif key and name in [m[0] for m in MAPS]:
        RUN_MAPS.setdefault(name, {})[key.lower()] = raw
    else:
        print('--set %s: not a field a run can set, skipped' % name, file=sys.stderr)


def task_scale():
    """(label, value) of the nearest task file that names a usable [SCALE], or (None, None)."""
    for label, path in task_files():
        raw = (task_value(path, 'SCALE') or '').lower()
        if raw in ('lite', 'full'):
            return label, raw
    return None, None


for name, field, values, default in SCALARS:
    value, source = None, 'default'
    if name in RUN_SCALARS:
        value = accept(name, values, RUN_SCALARS[name], '--set %s' % name)
        # A run may raise the size of a task, never lower one a task file already raised
        # (conventions/task-scale.md → The ratchet): the file cannot say whose word it was.
        if name == 'scale' and value == 'lite' and task_scale()[1] == 'full':
            print("--set scale: 'lite' does not lower %sTask.md [SCALE] = [full], kept"
                  % ("the epic's " if task_scale()[0] == 'epic' else ''), file=sys.stderr)
            value = None
        if value is not None:
            source = 'run'
    for label, path in ([] if value is not None or name in PROJECT_ONLY else task_files()):
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

# A QUICK task has one shape, and it is lite's (conventions/task-scale.md → QUICK).
if (task_value(os.path.join(TARGET, 'Task.md'), 'TASK_TYPE') or '').upper() == 'QUICK':
    if sources['scale'] in ('task', 'run') and resolved['scale'] != 'lite':
        print("%s: '%s' ignored, a QUICK task is always lite"
              % ('--set scale' if sources['scale'] == 'run' else 'Task.md [SCALE]', resolved['scale']),
              file=sys.stderr)
    resolved['scale'], sources['scale'] = 'lite', 'type'
    show_source['scale'] = 'type: QUICK'

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
    found = [('--set %s' % name, 'run', ['%s: %s' % kv for kv in RUN_MAPS.get(name, {}).items()])]
    found += [(('Task.md [%s]' % field), label, task_map_entries(path, field))
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
    # run beats task beats epic beats project, so a task-chosen key is never reported as the project's.
    order = ['run', 'task', 'epic', 'project']
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
# its default, and a column repeating those is one nobody reads. A value the run set is in it
# whatever it is: the owner said it for this run. --all names every field and every map key —
# defaults included — and never prints the "more" line.
FIELD_OF = dict((s[0], s[1]) for s in SCALARS)


def show_rows(show_all):
    """The column's lines, and how many fields it left out."""
    rows, rest = [], 0
    for name in [s[0] for s in SCALARS] + ['models', 'effort', 'long_run', 'budgets']:
        value = resolved[name]
        if isinstance(value, dict):
            chosen = [k for k in value
                      if sources.get('%s.%s' % (name, k)) == 'run'
                      or (sources.get('%s.%s' % (name, k)) and value[k] != defaults[name][k])]
            keys = list(value) if show_all else chosen
            if not keys:
                rest += 1
                continue
            text = ', '.join('%s: %s' % (k, value[k]) for k in keys)
        else:
            # A value derived from the default (walkthrough_check's auto) is nobody's choice either.
            if not show_all and sources[name] != 'run' and (sources[name] == 'default' or value == defaults[name]
                                                            or CHOSEN.get(name) == defaults[name]):
                rest += 1
                continue
            text = value
        rows.append(('[%s]' % FIELD_OF.get(name, name.upper()), text,
                     show_source.get(name, sources[name])))
    width = max(len(r[0]) for r in rows) if rows else 0
    return ['%-*s = [%s]  # %s' % (width, label, text, source) for label, text, source in rows], rest


if CMD == 'show':
    lines, rest = show_rows(SHOW_ALL)
    for line in lines:
        print(line)
    if rest:
        print('# %d more at their default' % rest)
    sys.exit(0)

# open: the opening block, which the orchestrator shows as it is. One line per fact, in this order:
# profile, task, range, Progress, method (under B, its skill and why); every stage of the range and
# its role, from the profile script's meta; under A, /workflows; every setting this run set, from
# json without --set to what it resolved to; the owner's directive, verbatim, from Run.json; under
# B, the roles whose effort does not travel; at live, the token panel; the settings column, sized
# by settings_report. Nothing at quiet.
CORE = os.environ['SPINE_CORE_ROOT']


def refuse(why):
    print('open: %s' % why, file=sys.stderr)
    sys.exit(2)


method, why, progress = OPEN.get('method'), OPEN.get('why'), OPEN.get('progress', resolved['progress'])
if method not in ('A', 'B'):
    refuse('--method A|B is required')
if (method == 'B') != bool(why):
    refuse('--why goes with --method B, and only with it')
if progress not in ('quiet', 'normal', 'live'):
    refuse("--progress '%s' is not quiet, normal or live" % progress)
if progress == 'quiet':
    sys.exit(0)

profile = (task_value(os.path.join(TARGET, 'Task.md'), 'TASK_TYPE') or '').lower()
script = os.path.join(CORE, 'workflows', 'profile-%s.js' % profile)
if not os.path.isfile(script):
    refuse("no workflow script for [TASK_TYPE] = [%s]" % profile.upper())
with open(script, encoding='utf-8') as fh:
    meta = re.search(r'export const meta\s*=\s*\{(.*?)^\}', fh.read(), flags=re.M | re.S)
# The same reading as scripts/lint-workflows.sh.
phases = re.findall(r"title:\s*'([^']+)'[^}]*?agent:\s*'([^']+)'", meta.group(1) if meta else '')
titles = [t for t, _ in phases]
start, _, end = OPEN.get('range', '').partition(':')
if start not in titles or end not in titles or titles.index(start) > titles.index(end):
    refuse("--range '%s' is not <start>:<end> of %s" % (OPEN.get('range', ''), ', '.join(titles)))

LOCALE = {}
with open(os.path.join(CORE, 'skills', 'orchestrator', 'locales', '%s.md' % resolved['lang']),
          encoding='utf-8') as fh:
    for part in re.split(r'^## ', fh.read(), flags=re.M)[1:]:
        key, _, body = part.partition('\n')
        LOCALE[key.strip()] = body.strip()


def say(key, **values):
    text = LOCALE[key]
    for k, v in values.items():
        text = text.replace('{%s}' % k, str(v))
    return text


def task_label(path):
    """The id a user types: 042 for 042-a-task, 042/02 for its step 02-login.step."""
    path = os.path.normpath(os.path.abspath(path))
    own = re.match(r'[^-.]*', os.path.basename(path)).group(0)
    if not path.endswith('.step'):
        return own
    return '%s/%s' % (re.match(r'[^-.]*', os.path.basename(os.path.dirname(path))).group(0), own)


# from: the chain without this run's word, so a value the run did not change never shows.
plain = subprocess.run([os.path.join(CORE, 'scripts', 'resolve-settings.sh'), 'json', TARGET],
                       capture_output=True, text=True)
if plain.returncode:
    refuse('json without --set failed: %s' % plain.stderr.strip())
before = json.loads(plain.stdout)
changed = [(n, before[n], resolved[n]) for n in [s[0] for s in SCALARS] if sources[n] == 'run']
for name in ('models', 'effort', 'long_run'):
    changed += [('%s.%s' % (name, k), before[name][k], v) for k, v in resolved[name].items()
                if sources.get('%s.%s' % (name, k)) == 'run']

# Run.json is the owner's word only while git does not track it (SKILL.md → The run's own words).
directive, run_file = '', os.path.join(TARGET, 'Run.json')
if os.path.isfile(run_file):
    tracked = subprocess.run(['git', '-C', TARGET, 'ls-files', '--error-unmatch', 'Run.json'],
                             capture_output=True).returncode == 0
    if not tracked:
        try:
            with open(run_file, encoding='utf-8') as fh:
                directive = (json.load(fh).get('user_directive') or '').strip()
        except (OSError, ValueError, AttributeError):
            pass

out = [say('open_header', profile=profile.upper(), task=task_label(TARGET), start=start, end=end,
           progress=progress,
           method=say('open_method_a') if method == 'A' else
           say('open_method_b', skill='spine-toolkit:workflow-%s' % profile, why=why)),
       say('open_stages')]
out += ['  %s — %s' % p for p in phases[titles.index(start):titles.index(end) + 1]]
if method == 'A':
    out.append(say('open_workflows', workflow='profile-%s' % profile))
out += [say('open_run_setting', field=f, **{'from': a, 'to': b}) for f, a, b in changed]
if directive:
    out.append(say('open_directive', directive=directive))
slow = [k for k, v in resolved['effort'].items() if v != 'session']
if method == 'B' and slow:
    out.append(say('warn_effort_method_b', roles=', '.join(slow)))
if progress == 'live':
    session = os.environ.get('CLAUDE_CODE_SESSION_ID')
    if method == 'A' and session:
        out.append(say('open_live_a', script=os.path.join(CORE, 'scripts', 'agent-monitor.sh'), session=session))
    if method == 'B':
        out.append(say('open_live_b'))
if resolved['settings_report'] != 'off':
    lines, rest = show_rows(resolved['settings_report'] == 'full')
    out += [say('open_settings')] + ['  ' + line for line in lines]
    if rest:
        out.append('  ' + say('open_settings_rest', n=rest))
print('\n'.join(out))
PY
