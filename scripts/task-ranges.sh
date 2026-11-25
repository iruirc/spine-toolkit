#!/usr/bin/env bash
# Where a task's repositories stood, and what changed since: conventions/task-ranges.md.
#
# Usage: scripts/task-ranges.sh record <task-dir>                                 # Base.md, once
#        scripts/task-ranges.sh tips   <task-dir> --kind reviewed|done|validated  # record lines
#        scripts/task-ranges.sh ranges <task-dir> --since base|reviewed|done|validated [--fallback base]  # JSON
#        scripts/task-ranges.sh since  <task-dir> --action run|continue|redo|restart|restart-full|catch-up|fix-review  # base Review reads from
#        scripts/task-ranges.sh dirty  <task-dir>                                 # uncommitted work the base did not hold
#        scripts/task-ranges.sh count  <task-dir> <repo> <sha>                    # commits after sha, or rewritten
#        scripts/task-ranges.sh unreachable <task-dir> <sha>...                   # shas not the task's
#        scripts/task-ranges.sh commits <task-dir> <a>..<b>                       # a and what follows
#        scripts/task-ranges.sh last <task-dir>                                   # newest own commit
#        scripts/task-ranges.sh names <task-dir>                                  # repositories by folder
#        scripts/task-ranges.sh owners <task-dir> <sha>...                        # which hold each sha
# Exit:  0, or 2 on a usage error, a record it cannot read, or a recorded repository gone.
set -euo pipefail

[ "$#" -ge 2 ] || { echo "usage: $0 record|tips|ranges|since|dirty|count|unreachable|commits|last|names|owners <task-dir> [--kind k | --since s [--fallback base] | --action a | <repo> <sha> | <sha>... | <a>..<b>]" >&2; exit 2; }
[ -d "$2" ] || { echo "not a directory: $2" >&2; exit 2; }
resolver="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/resolve-settings.sh"
paths="$("$resolver" raw "$2" Paths)" || exit 2
# roots[0] is the config's own directory (resolve-settings.sh: search_roots) — empty when
# no config was found; task-ranges.sh never reads for the file itself (settings-resolver.test.bats
# — "no script but the resolver parses the config file").
home="$("$resolver" json "$2" | python3 -c 'import json,sys; r=json.load(sys.stdin)["roots"]; print(r[0] if r else "")')" || exit 2

python3 - "$paths" "$home" "$@" <<'PY'
import glob, hashlib, json, os, re, subprocess, sys

PATHS, HOME_ARG, CMD, TASK, OPTS = sys.argv[1], sys.argv[2], sys.argv[3], os.path.realpath(sys.argv[4]), sys.argv[5:]
KINDS = {'base': ('BASE', 'Base.md'), 'reviewed': ('REVIEWED', 'Review.md'), 'done': ('DONE', 'Done.md'),
         'validated': ('VALIDATED', 'Validation.md')}
RECORD = re.compile(r'^\[(BASE|REVIEWED|DONE|VALIDATED)_COMMIT\]\s*=\s*(.*)$')


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
    die('no project config (SPINE.md) at or above %s' % TASK)
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


def fingerprint(top):
    # One sha over the path and content of every uncommitted path outside the tasks folder: None when
    # the checkout is clean, False when git cannot tell. What is staged and what is not reads the same.
    tasks = os.path.relpath(TASKS, top)
    spec = ['--', '.', ':(exclude)' + tasks] if not tasks.startswith('..') else []
    r = subprocess.run(['git', '-C', top, 'status', '--porcelain', '-z', '--untracked-files=all', '--no-renames']
                       + spec, capture_output=True)
    if r.returncode != 0:
        return False
    paths = sorted({e[3:] for e in r.stdout.split(b'\0') if len(e) > 3})
    if not paths:
        return None
    h = hashlib.sha1()
    for p in paths:
        full = os.path.join(top.encode(), p)
        if os.path.islink(full):
            digest = b'link:' + os.readlink(full)
        elif os.path.isdir(full):
            digest = b'dir'  # a nested checkout: its own state is its own repository's
        elif os.path.isfile(full):
            with open(full, 'rb') as fh:
                digest = hashlib.sha1(fh.read()).hexdigest().encode()
        else:
            digest = b'-'
        h.update(p + b'\0' + digest + b'\0')
    return h.hexdigest()


def base_dirty():
    path, out = os.path.join(TASK, 'Base.md'), {}
    if os.path.isfile(path):
        with open(path, encoding='utf-8') as fh:
            for line in fh:
                m = re.fullmatch(r'\[BASE_DIRTY\]\s*=\s*(.+?):\s+([0-9a-f]{40})', line.strip())
                if m:
                    out.setdefault(m.group(1), m.group(2))
    return out


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


def fallback_base(top):
    # The nearest merge-base over the local and the remote main branch: either may run ahead of
    # the other with commits that are not the task's. None when HEAD sits on one of them.
    head, best = git(top, 'rev-parse', 'HEAD'), None
    for ref in (git(top, 'symbolic-ref', '-q', '--short', 'refs/remotes/origin/HEAD'), 'main', 'master'):
        sha = ref and git(top, 'rev-parse', '-q', '--verify', ref + '^{commit}') and git(top, 'merge-base', 'HEAD', ref)
        if sha == head:
            return None
        if sha and (best is None or count(top, sha) < count(top, best)):
            best = sha
    return best


def count(top, sha):
    rel = os.path.relpath(TASKS, top)
    spec = ['--', '.', ':(exclude)' + rel] if not rel.startswith('..') else []
    return int(git(top, 'rev-list', '--count', sha + '..HEAD', *spec))


def elsewhere(top, sha):
    # A commit touching only another task's folder: the tasks folder is shared by every task.
    paths = [os.path.join(top, f) for f in (git(top, 'diff-tree', '--no-commit-id', '--name-only', '-r', '--root', sha) or '').splitlines()]
    return bool(paths) and all(inside(p, TASKS) and not inside(p, TASK) for p in paths)


def with_own():
    # The tasks repository is never a range to review, but its phase-closing commits are the task's.
    own, out = git(TASK, 'rev-parse', '--show-toplevel'), dict(REPOS)
    if own and inside(os.path.realpath(own), TASKS):
        out[None] = os.path.realpath(own)
    return out


_base = None


def ours(rel, top, sha):
    # A base the history no longer holds bounds nothing: reachable from HEAD is all that is left.
    global _base
    if _base is None:
        _base = recorded('BASE', 'Base.md')
    full, base = git(top, 'rev-parse', '-q', '--verify', sha + '^{commit}'), _base.get(rel)
    if not full:
        return False
    if git(top, 'merge-base', '--is-ancestor', full, 'HEAD') is None:
        # A checkout switched to another branch, here or by another session, still holds it.
        return bool(git(top, 'for-each-ref', '--contains', full, 'refs/heads'))
    bounded = base and git(top, 'merge-base', '--is-ancestor', base, 'HEAD') is not None
    return not bounded or git(top, 'merge-base', '--is-ancestor', full, base) is None


def names():
    # The name a commit reference in Walkthrough.md carries: the checkout's folder, or its path from
    # the project root where two checkouts of the task share a folder name. The tasks repository last.
    found = sorted(with_own().items(), key=lambda kv: (kv[0] is None, kv[0] or ''))
    rels = {key: os.path.relpath(top, HOME) for key, top in found}
    base = {key: os.path.basename(top) for key, top in found}
    return {key: (rels[key] if list(base.values()).count(base[key]) > 1 else base[key], rels[key])
            for key, _ in found}


if CMD == 'record':
    if OPTS:
        die('usage: task-ranges.sh record <task-dir>')
    base = os.path.join(TASK, 'Base.md')
    if not os.path.exists(base):
        # What was uncommitted before the task, an environment switch the project never commits, is
        # not the task's work: dirty leaves it out while it stays as it was. A status git cannot
        # answer gets no line, so dirty counts that repository's every change, and stops on it.
        dirty = ['[BASE_DIRTY] = %s: %s' % (rel, fp) for rel, fp in
                 ((rel, fingerprint(top)) for rel, top in sorted(REPOS.items())) if fp]
        with open(base, 'w', encoding='utf-8') as fh:
            fh.write('# Base\n\n' + '\n'.join(heads('BASE') + dirty) + '\n')
elif CMD == 'tips':
    kind = opt('--kind', ['reviewed', 'done', 'validated'])
    lines = heads(KINDS[kind][0])
    if kind == 'done':
        # Where Done left the fix rounds: a later catch-up counts its own from here.
        plan = os.path.join(TASK, 'Plan.md')
        text = open(plan, encoding='utf-8').read() if os.path.isfile(plan) else ''
        # A round is a progress row, a status in it, whose id is R<n>; the title is the fallback for a Plan.md that predates the id.
        rounds = re.findall(r'^\|\s*R(\d+)\s*\|.*(?:⬜|🔄|✅|⏸|🚫|⊘)', text, re.M) + re.findall(r'Review fixes (\d+)', text)
        lines.append('[REVIEW_FIXES] = %d' % max([int(n) for n in rounds] or [0]))
    print('\n'.join(lines))
elif CMD == 'ranges':
    SINCES = ['base', 'reviewed', 'done', 'validated']
    fallback = OPTS[2:] == ['--fallback', 'base']
    if not (len(OPTS) in (2, 4) and OPTS[0] == '--since' and OPTS[1] in SINCES and (len(OPTS) == 2 or fallback)) \
            or (fallback and OPTS[1] not in ('reviewed', 'done')):
        die('usage: task-ranges.sh ranges <task-dir> --since %s [--fallback base, with reviewed|done]' % '|'.join(SINCES))
    since = OPTS[1]

    def measure(since):
        kind, name = KINDS[since]
        rec = recorded(kind, name)
        gone = sorted(set(rec) - set(REPOS))
        if gone:
            die('%s names %s, which is not a repository of this task on disk' % (name, ', '.join(gone)))
        out = {}
        for rel, top in sorted(REPOS.items()):
            sha = rec.get(rel)
            if not sha and since == 'base':
                sha = fallback_base(top)
            if not sha:
                out[rel] = {'range': None, 'commits': None, 'state': 'unknown'}
            elif git(top, 'merge-base', '--is-ancestor', sha, 'HEAD') is None:
                out[rel] = {'range': None, 'commits': None, 'state': 'rewritten'}
            else:
                out[rel] = {'range': sha + '..HEAD', 'commits': count(top, sha), 'state': 'ok'}
        return out

    repos = measure(since)
    # Per repository: a record the previous review or Done cannot give is measured from the base;
    # the others keep theirs (conventions/task-ranges.md -> Ranges).
    lost = [rel for rel, r in repos.items() if r['state'] != 'ok'] if fallback else []
    if lost:
        base = measure('base')
        for rel in lost:
            repos[rel] = dict(base[rel], since='base', fallback=repos[rel]['state'])
    print(json.dumps({'since': since, 'repos': repos}, sort_keys=True))
elif CMD == 'since':
    ACTIONS = ['run', 'continue', 'redo', 'restart', 'restart-full', 'catch-up', 'fix-review']
    action = opt('--action', ACTIONS)
    # The base Review reads from, by the rules of conventions/task-ranges.md -> Ranges.
    if action == 'catch-up':
        print('done')
    elif action == 'fix-review':
        print('reviewed')
    elif action in ('restart', 'restart-full') or not os.path.isfile(os.path.join(TASK, 'Review.md')):
        print('base')
    else:
        print('reviewed')
elif CMD == 'dirty':
    if OPTS:
        die('usage: task-ranges.sh dirty <task-dir>')
    recorded_dirty = base_dirty()
    for rel, top in sorted(REPOS.items()):
        fp = fingerprint(top)
        # A status git cannot answer is not a clean one: the lint that reads this must not pass it.
        if fp is False:
            die('git status failed in %s' % rel)
        if fp and fp != recorded_dirty.get(rel):
            print(rel)
elif CMD == 'count':
    if len(OPTS) != 2:
        die('usage: task-ranges.sh count <task-dir> <repo> <sha>')
    name, sha = OPTS
    if name not in REPOS:
        die('%s is not a repository of this task' % name)
    top = REPOS[name]
    full = git(top, 'rev-parse', '-q', '--verify', sha + '^{commit}')
    if full and git(top, 'merge-base', '--is-ancestor', full, 'HEAD') is not None:
        print(count(top, full))
    else:
        print('rewritten')
elif CMD == 'last':
    if OPTS:
        die('usage: task-ranges.sh last <task-dir>')
    rec = recorded('BASE', 'Base.md')
    for rel, top in sorted(REPOS.items()):
        sha = rec.get(rel) or fallback_base(top)
        if not sha or git(top, 'merge-base', '--is-ancestor', sha, 'HEAD') is None:
            print('%s unknown' % rel)
            continue
        tasks = os.path.relpath(TASKS, top)
        spec = ['--', '.', ':(exclude)' + tasks] if not tasks.startswith('..') else []
        last = git(top, 'rev-list', '-1', '--first-parent', sha + '..HEAD', *spec)
        if last:
            print('%s %s' % (rel, last))
elif CMD == 'unreachable':
    if not OPTS:
        die('usage: task-ranges.sh unreachable <task-dir> <sha>...')
    checked = with_own()
    for sha in OPTS:
        if not any(ours(rel, top, sha) for rel, top in checked.items()):
            print(sha)
elif CMD == 'names':
    if OPTS:
        die('usage: task-ranges.sh names <task-dir>')
    for name, rel in names().values():
        print('%s %s' % (name, rel))
elif CMD == 'owners':
    if not OPTS:
        die('usage: task-ranges.sh owners <task-dir> <sha>...')
    checked, named = with_own(), names()
    for sha in OPTS:
        print(' '.join([sha] + [named[rel][0] for rel, top in checked.items() if ours(rel, top, sha)]))
elif CMD == 'commits':
    m = re.fullmatch(r'([0-9a-f]{7,40})\.\.([0-9a-f]{7,40})', OPTS[0]) if len(OPTS) == 1 else None
    if not m:
        die('usage: task-ranges.sh commits <task-dir> <a>..<b>')
    for top in with_own().values():
        a, b = (git(top, 'rev-parse', '-q', '--verify', s + '^{commit}') for s in m.groups())
        if a and b and git(top, 'merge-base', '--is-ancestor', a, b) is not None:
            # First parent only: a merge brings upstream commits into a..b that are not the task's.
            listed = [a] + git(top, 'rev-list', '--first-parent', '--reverse', a + '..' + b).split()
            print('\n'.join(c for c in listed if not elsewhere(top, c)))
            sys.exit(0)
    die('no repository of the task holds %s' % OPTS[0])
else:
    die('unknown command "%s"' % CMD)
PY
