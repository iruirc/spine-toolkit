#!/usr/bin/env bash
set -euo pipefail

# Routes a change set to the documentation components a project declares.
# The vocabulary and the doctrine: conventions/docs-components.md.
# Why a script and not a sentence in a brief: matching a diff against a dozen glob patterns by
# eye is how a router names the wrong document with full confidence.
#
# Usage:
#   scripts/docs-route.sh registry <project-root>
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


def parse_map(path, prefix):
    """One DocsMap.md, in declaration order. A package map is written relative to the package
    root and prefixed here, because everything downstream matches project-relative paths."""
    comps, cur, key = [], None, None
    for raw in open(path, encoding='utf-8'):
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
        item = re.match(r'^\s+-\s+(.+?)\s*$', line)
        if item and key in LIST_KEYS:
            cur[key].append(under(prefix, item.group(1)))
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
    comps = []
    top = os.path.join(ROOT, config('Docs', 'map', 'DocsMap.md'))
    if os.path.isfile(top):
        comps += parse_map(top, '')
    for pkg in package_roots():
        pm = os.path.join(ROOT, pkg, 'DocsMap.md')
        if os.path.isfile(pm):
            comps += parse_map(pm, pkg)

    default_level = config('Docs', 'strictness', 'advisory')
    errors, seen = [], {}
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
            errors.append('name "%s" is declared twice: %s and %s' % (c['name'], seen[c['name']], c['source']))
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


if CMD == 'registry':
    comps, errors = load_registry()
    if errors:
        die(errors)
    for c in comps:
        print('\t'.join([c['name'], c['genre'], c['strictness'], c['source']]))
    sys.exit(0)

print('unknown command "%s"' % CMD)
sys.exit(2)
PY
)
python3 -c "$SRC" "$@"
