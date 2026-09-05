#!/usr/bin/env bash
set -euo pipefail

# Routes a change set to the documentation components a project declares.
# The vocabulary and the doctrine: conventions/docs-components.md.
# Why a script and not a sentence in a brief: matching a diff against a dozen glob patterns by
# eye is how a router names the wrong document with full confidence.
#
# Usage:
#   scripts/docs-route.sh registry <project-root> [--paths]
#   scripts/docs-route.sh route    <project-root> --task-dir <dir> --phase <id>   < change set
#   scripts/docs-route.sh reorigin <prefix>                                        < change set
#
# The change set is `git diff --name-status` on stdin. A line with no tab is read as a modified
# path, so a plan can pipe the paths it intends to touch before any of them exists. Every command
# that takes one reads stdin unconditionally: feed it `</dev/null` when there is nothing to say.
#
# Paths in a change set are relative to the project root, and the registry is written the same
# way. A diff taken inside a checkout is not: git prints paths relative to that checkout. Pipe it
# through `reorigin <path-of-the-checkout>` first — that is what lets one phase touch code in one
# repository and its documentation in another, which is the case this mechanism exists for.
#
# Exit: 0 clean, 1 something the caller must act on, 2 usage or a malformed registry.
#
# The source goes into a variable and reaches python as -c rather than on stdin the way the other
# scripts here do it: a heredoc fed to `python3 -` IS stdin, and this script reads the change set
# from there. lint-artifact-budget.sh never reads stdin, which is why the shape looks safe.

[ "$#" -ge 2 ] || { echo "usage: $0 <command> <project-root> [options]" >&2; exit 2; }

SRC=$(cat <<'PY'
import glob as globlib
import os
import re
import sys

ARGV = sys.argv[1:]
CMD = ARGV[0]
ROOT = os.path.abspath(ARGV[1])

GENRES = ('state', 'tracker')
LEVELS = ('blocking', 'advisory', 'off')
LIST_KEYS = ('places', 'covers', 'fed_by')


def opt(name, default=None):
    if name in ARGV:
        i = ARGV.index(name)
        if i + 1 < len(ARGV):
            return ARGV[i + 1]
    return default


def block(path, name):
    """Body of a `## <name>` section, up to the next H2. Absent is not an error."""
    try:
        text = open(path, encoding='utf-8').read()
    except OSError:
        return None
    m = re.search(r'^## %s\s*$(.*?)(?=^## |\Z)' % re.escape(name), text, flags=re.M | re.S)
    return m.group(1) if m else None


def config(name, key, default=None):
    body = block(os.path.join(ROOT, 'CLAUDE-spine-toolkit.md'), name)
    if body is None:
        return default
    m = re.search(r'^\s*%s:\s*(.+?)\s*$' % re.escape(key), body, flags=re.M)
    return m.group(1).strip() if m else default


def under(prefix, path):
    p = path.strip().lstrip('/')
    return '%s/%s' % (prefix.rstrip('/'), p) if prefix else p


def parse_map(path, prefix, errors):
    """One DocsMap.md, in declaration order. A package map is written relative to the package
    root and prefixed here, because everything downstream matches project-relative paths."""
    comps, cur, key = [], None, None
    for lineno, raw in enumerate(open(path, encoding='utf-8'), 1):
        line = raw.rstrip('\n')
        head = re.match(r'^## (.+?)\s*$', line)
        if head:
            cur = {'name': head.group(1).strip(), 'source': os.path.relpath(path, ROOT),
                   'genre': None, 'strictness': None, 'places': [], 'covers': [], 'fed_by': []}
            comps.append(cur)
            key = None
            continue
        if cur is None:
            continue
        item = re.match(r'^(\s*)-\s+(.+?)\s*$', line)
        if item and key in LIST_KEYS:
            if not item.group(1):
                # A value that lost its indentation reads as prose and would leave the component
                # quietly short of what it declares, which is the divergence this whole mechanism
                # exists to catch.
                errors.append('%s:%d: "- %s" is not indented — a value under "%s:" takes two '
                              'spaces, and a dash at column zero is prose'
                              % (os.path.relpath(path, ROOT), lineno, item.group(2), key))
                continue
            cur[key].append(under(prefix, item.group(2)))
            continue
        field = re.match(r'^([a-z_]+):\s*(.*?)\s*$', line)
        if field:
            key, val = field.group(1), field.group(2)
            if key in ('genre', 'strictness') and val:
                cur[key] = val
            elif key in LIST_KEYS and val:
                cur[key].append(under(prefix, val))
        elif line.strip():
            key = None
    return comps


def package_roots():
    body = block(os.path.join(ROOT, 'CLAUDE-spine-toolkit.md'), 'Paths') or ''
    roots = []
    for pat in re.findall(r'^\s*-\s*External packages:\s*(.+?)\s*$', body, flags=re.M):
        for p in sorted(globlib.glob(os.path.join(ROOT, pat.strip().lstrip('/')))):
            if os.path.isdir(p):
                roots.append(os.path.relpath(p, ROOT))
    return roots


def load_registry():
    """Every declared component, project map first, packages after in path order.
    The order is load-bearing: fed_by resolves to the first component that matched."""
    comps, errors = [], []
    top = os.path.join(ROOT, config('Docs', 'map', 'DocsMap.md'))
    if os.path.isfile(top):
        comps += parse_map(top, '', errors)
    for pkg in package_roots():
        pm = os.path.join(ROOT, pkg, 'DocsMap.md')
        if os.path.isfile(pm):
            comps += parse_map(pm, pkg, errors)

    default_level = config('Docs', 'strictness', 'advisory')
    seen = {}
    for c in comps:
        where = '%s: component "%s"' % (c['source'], c['name'])
        if c['genre'] not in GENRES:
            errors.append('%s declares genre "%s" — one of %s' % (where, c['genre'], '/'.join(GENRES)))
        if c['strictness'] is None:
            c['strictness'] = default_level
        elif c['strictness'] not in LEVELS:
            errors.append('%s declares strictness "%s" — one of %s' % (where, c['strictness'], '/'.join(LEVELS)))
        if not c['places']:
            errors.append('%s declares no places' % where)
        if c['genre'] == 'state' and not c['covers']:
            errors.append('%s is a state component and declares no covers' % where)
        if c['genre'] == 'tracker' and not c['fed_by']:
            errors.append('%s is a tracker and declares no fed_by' % where)
        if c['name'] in seen:
            errors.append('name "%s" is declared twice: %s and %s — a registry that merges them '
                          'silently produces the divergence this mechanism exists to catch'
                          % (c['name'], seen[c['name']], c['source']))
        else:
            seen[c['name']] = c['source']
    return comps, errors


def matcher(pattern):
    """A pattern with no glob character matches the path itself and everything under it, so a
    bare directory does not have to remember its trailing slash. `**` crosses separators, `*`
    does not."""
    p = pattern.strip().lstrip('/').rstrip('/')
    if '*' not in p and '?' not in p:
        return lambda path: path == p or path.startswith(p + '/')
    out, i = [], 0
    while i < len(p):
        if p.startswith('**', i):
            out.append('.*')
            i += 2
        elif p[i] == '*':
            out.append('[^/]*')
            i += 1
        elif p[i] == '?':
            out.append('[^/]')
            i += 1
        else:
            out.append(re.escape(p[i]))
            i += 1
    rx = re.compile('^%s$' % ''.join(out))
    return lambda path: bool(rx.match(path))


def die(errors):
    for e in errors:
        print(e)
    sys.exit(2)


HEADER = ('# Docs\n\n'
          '> Routed by spine-toolkit:docs-route. One row per phase and component. Fill Verdict\n'
          '> with Applicable, N/A or Pending; N/A requires a reason in Note.\n\n'
          '| Phase | Component | Genre | Strictness | Verdict | Note |\n'
          '|---|---|---|---|---|---|\n')


def read_change_set():
    changed, created = [], []
    for line in sys.stdin:
        parts = line.rstrip('\n').split('\t')
        if not parts or not parts[-1].strip():
            continue
        path = parts[-1].strip().lstrip('/')
        status = parts[0].strip() if len(parts) > 1 else 'M'
        changed.append(path)
        if status.startswith('A'):
            created.append(path)
    return changed, created


def task_field(task_dir, name):
    """A bracketed Task.md field, anchored at column 0. Every task file ships the optional
    fields commented out as documentation, and reading one of those as a value would switch
    the mechanism off for every task in every project."""
    if not task_dir:
        return None
    try:
        fh = open(os.path.join(task_dir, 'Task.md'), encoding='utf-8')
    except OSError:
        return None
    with fh:
        for line in fh:
            m = re.match(r'^\[%s\]\s*=\s*\[(.*?)\]' % re.escape(name), line)
            if m:
                return m.group(1).strip()
    return None


def docs_enabled(task_dir):
    return (task_field(task_dir, 'DOCS') or 'on').lower() != 'off'


def declared_new(task_dir):
    """[DOCS_NEW] = [Name:genre, Other:tracker] — the one thing routing cannot derive, since a
    subsystem being born has no covers to match against yet."""
    raw = task_field(task_dir, 'DOCS_NEW') or ''
    out = []
    for item in raw.split(','):
        item = item.strip()
        if not item:
            continue
        name, _, genre = item.partition(':')
        out.append((name.strip(), (genre.strip() or 'state')))
    return out


def affected(comps, changed):
    """State components only. A tracker is fed by task folders and generated; whether a rule
    moved is a question only a state component can be asked."""
    hits = []
    for c in comps:
        if c['genre'] != 'state':
            continue
        ms = [matcher(pat) for pat in c['covers']]
        if any(m(p) for p in changed for m in ms):
            hits.append(c)
    return hits


def append_rows(task_dir, phase, rows):
    path = os.path.join(task_dir, 'Docs.md')
    text = open(path, encoding='utf-8').read() if os.path.isfile(path) else HEADER
    for name, genre, level in rows:
        row = '| %s | %s | %s | %s |  |  |\n' % (phase, name, genre, level)
        if re.search(r'^\| %s \| %s \|' % (re.escape(phase), re.escape(name)), text, flags=re.M):
            continue
        text += row
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(text)


if CMD == 'reorigin':
    # A change set speaks the language of the checkout it was taken in; the registry speaks the
    # language of the project root, which in a multi-repository project is a container and not a
    # repository at all. Without this the two never meet.
    prefix = ARGV[1].strip().strip('/')
    for line in sys.stdin:
        parts = line.rstrip('\n').split('\t')
        if len(parts) < 2:
            if parts and parts[0].strip():
                print('%s/%s' % (prefix, parts[0].strip().lstrip('/')))
            continue
        print('\t'.join([parts[0]] + ['%s/%s' % (prefix, c.strip().lstrip('/')) for c in parts[1:]]))
    sys.exit(0)

if CMD == 'registry':
    comps, errors = load_registry()
    if errors:
        die(errors)
    paths = '--paths' in ARGV
    for c in comps:
        print('\t'.join([c['name'], c['genre'], c['strictness'], c['source']]))
        if paths:
            for kind in LIST_KEYS:
                for p in c[kind]:
                    print('\t'.join(['', kind, p]))
    sys.exit(0)

if CMD == 'route':
    task_dir = opt('--task-dir')
    phase = opt('--phase', '1')
    if not task_dir:
        print('route needs --task-dir')
        sys.exit(2)
    if not docs_enabled(task_dir):
        sys.exit(0)
    comps, errors = load_registry()
    if errors:
        die(errors)
    changed, _created = read_change_set()
    default_level = config('Docs', 'strictness', 'advisory')
    rows = [(c['name'], c['genre'], c['strictness']) for c in affected(comps, changed)]
    known = {c['name'] for c in comps}
    for n, g in declared_new(task_dir):
        if n in known:
            continue
        if g == 'state':
            rows.append((n, g, default_level))
        else:
            print('%s: declared as a new %s — add its record to the registry; a tracker is '
                  'generated and never asked' % (n, g))
    if rows:
        append_rows(task_dir, phase, rows)
        for name, _g, level in rows:
            print('%s (%s): does this change alter what the component asserts?' % (name, level))
    sys.exit(0)

print('unknown command "%s"' % CMD)
sys.exit(2)
PY
)
python3 -c "$SRC" "$@"
