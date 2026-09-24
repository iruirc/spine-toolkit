#!/usr/bin/env bash
# Where a task's repositories stood, and what changed since: conventions/task-ranges.md.
#
# Usage: scripts/task-ranges.sh record <task-dir>                                 # Base.md, once
#        scripts/task-ranges.sh tips   <task-dir> --kind reviewed|done            # record lines
#        scripts/task-ranges.sh ranges <task-dir> --since base|reviewed|done      # JSON
# Exit:  0, or 2 on a usage error, a record it cannot read, or a recorded repository gone.
set -euo pipefail

[ "$#" -ge 2 ] || { echo "usage: $0 record|tips|ranges <task-dir> [--kind k | --since s]" >&2; exit 2; }
[ -d "$2" ] || { echo "not a directory: $2" >&2; exit 2; }
resolver="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/resolve-settings.sh"
paths="$("$resolver" raw "$2" Paths)" || exit 2
# roots[0] is the config's own directory (resolve-settings.sh: search_roots) — empty when
# no config was found; task-ranges.sh never reads for the file itself (settings-resolver.test.bats
# — "no script but the resolver parses the config file").
home="$("$resolver" json "$2" | python3 -c 'import json,sys; r=json.load(sys.stdin)["roots"]; print(r[0] if r else "")')" || exit 2

python3 - "$paths" "$home" "$@" <<'PY'
import glob, json, os, re, subprocess, sys

PATHS, HOME_ARG, CMD, TASK, OPTS = sys.argv[1], sys.argv[2], sys.argv[3], os.path.realpath(sys.argv[4]), sys.argv[5:]
KINDS = {'base': ('BASE', 'Base.md'), 'reviewed': ('REVIEWED', 'Review.md'), 'done': ('DONE', 'Done.md')}
RECORD = re.compile(r'^\[(BASE|REVIEWED|DONE)_COMMIT\]\s*=\s*(.*)$')


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)


def opt(name, values):
    if len(OPTS) != 2 or OPTS[0] != name or OPTS[1] not in values:
        die('usage: task-ranges.sh %s <task-dir> %s %s' % (CMD, name, '|'.join(values)))
    return OPTS[1]


def git(repo, *args):
    r = subprocess.run(['git', '-C', repo] + list(args), capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def ancestors(d):
    while True:
        yield d
        if os.path.dirname(d) == d:
            return
        d = os.path.dirname(d)


def inside(path, folder):
    return path == folder or path.startswith(folder + os.sep)


# resolve-settings.sh found no config above the task dir: HOME_ARG arrived empty.
HOME = os.path.realpath(HOME_ARG) if HOME_ARG else None
if not HOME:
    die('no CLAUDE-spine-toolkit.md at or above %s' % TASK)
TASKS = next((d for d in ancestors(TASK) if os.path.basename(d) == 'Tasks'), TASK)


def repositories():
    found = [HOME]
    for line in PATHS.splitlines():
        m = re.match(r'^-\s*(External packages|Roots):\s*(.+?)\s*$', line)
        if m:
            key, pat = m.groups()
            rel = pat.lstrip('/') if key == 'External packages' else os.path.expanduser(pat)
            found += [p for p in sorted(glob.glob(os.path.join(HOME, rel))) if os.path.isdir(p)]
    out = {}
    for p in found:
        top = git(p, 'rev-parse', '--show-toplevel')
        # A root that holds checkouts rather than being one.
        tops = [top] if top else [os.path.dirname(g) for g in sorted(glob.glob(os.path.join(p, '*', '.git')))]
        for t in tops:
            t = os.path.realpath(t)
            if not inside(t, TASKS):
                out.setdefault(os.path.relpath(t, HOME), t)
    return out


REPOS = repositories()


def heads(kind):
    return ['[%s_COMMIT] = %s: %s' % (kind, rel, git(top, 'rev-parse', 'HEAD'))
            for rel, top in sorted(REPOS.items()) if git(top, 'rev-parse', '-q', '--verify', 'HEAD')]


def recorded(kind, name):
    path, out = os.path.join(TASK, name), {}
    if not os.path.isfile(path):
        return out
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            m = RECORD.match(line.strip())
            if not m or m.group(1) != kind:
                continue
            v = re.fullmatch(r'(?:(.+?):\s+)?([0-9a-f]{7,40})', m.group(2).strip())
            if not v:
                die('%s: cannot read "%s"' % (path, line.strip()))
            # A line written before repositories were named is the project's; the first line wins.
            out.setdefault(v.group(1) or '.', v.group(2))
    return out


def main_branch(top):
    for ref in (git(top, 'symbolic-ref', '-q', '--short', 'refs/remotes/origin/HEAD'), 'main', 'master'):
        if ref and git(top, 'rev-parse', '-q', '--verify', ref + '^{commit}'):
            return ref
    return None


def count(top, sha):
    rel = os.path.relpath(TASKS, top)
    spec = ['--', '.', ':(exclude)' + rel] if not rel.startswith('..') else []
    return int(git(top, 'rev-list', '--count', sha + '..HEAD', *spec))


if CMD == 'record':
    if OPTS:
        die('usage: task-ranges.sh record <task-dir>')
    base = os.path.join(TASK, 'Base.md')
    if not os.path.exists(base):
        with open(base, 'w', encoding='utf-8') as fh:
            fh.write('# Base\n\n' + '\n'.join(heads('BASE')) + '\n')
elif CMD == 'tips':
    print('\n'.join(heads(KINDS[opt('--kind', ['reviewed', 'done'])][0])))
elif CMD == 'ranges':
    since = opt('--since', ['base', 'reviewed', 'done'])
    kind, name = KINDS[since]
    rec = recorded(kind, name)
    gone = sorted(set(rec) - set(REPOS))
    if gone:
        die('%s names %s, which is not a repository of this task on disk' % (name, ', '.join(gone)))
    repos = {}
    for rel, top in sorted(REPOS.items()):
        sha = rec.get(rel)
        if not sha and since == 'base':
            ref = main_branch(top)
            sha = git(top, 'merge-base', 'HEAD', ref) if ref else None
            # Work committed on the main branch itself leaves no base to count from.
            if sha == git(top, 'rev-parse', 'HEAD'):
                sha = None
        if not sha:
            repos[rel] = {'range': None, 'commits': None, 'state': 'unknown'}
        elif git(top, 'merge-base', '--is-ancestor', sha, 'HEAD') is None:
            repos[rel] = {'range': None, 'commits': None, 'state': 'rewritten'}
        else:
            repos[rel] = {'range': sha + '..HEAD', 'commits': count(top, sha), 'state': 'ok'}
    print(json.dumps({'since': since, 'repos': repos}, sort_keys=True))
else:
    die('unknown command "%s"' % CMD)
PY
