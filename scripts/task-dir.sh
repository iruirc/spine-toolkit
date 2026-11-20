#!/usr/bin/env bash
# Resolution step 1 of the orchestrator: find a task folder and spell it through the session's Tasks.
#
# A task repository reached through a Tasks link has no project config above its physical path, and
# resolve-settings.sh walks the path as given: handed the physical path, it finds nothing and stops.
# This script turns every way of naming a task — its id, a path through the link, the physical path
# — into the one spelling through Tasks, so the contract and every stage carry that. It never reads
# the project config: finding the folder and reading the settings stay apart.
#
# The Tasks folder is the nearest entry named Tasks (a folder, or a link to one) at or above --from,
# the current directory by default. An argument with a "/" is a path, relative to the current
# directory; any other is a task id, matched as <id>-* at the top of Tasks and in a status folder,
# and as <id>.step or <id>-*.step at any depth below.
#
# Usage: scripts/task-dir.sh <task_id | path> [--from <dir>]
# Exit:  0 the task folder on stdout, absolute, through Tasks;
#        2 usage, no Tasks at or above --from, or a path that is not a folder;
#        3 no folder for the id;
#        4 more than one folder for the id — every one on stdout, a line each;
#        5 a path under neither the Tasks folder nor the folder it links to.
set -euo pipefail

usage() { echo "usage: $0 <task_id | path> [--from <dir>]" >&2; exit 2; }

arg="" from="$PWD"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --from) [ "$#" -ge 2 ] || usage; from="$2"; shift 2 ;;
    -*) usage ;;
    *) [ -z "$arg" ] || usage; arg="$1"; shift ;;
  esac
done
[ -n "$arg" ] || usage

exec python3 - "$arg" "$from" <<'PY'
import os, sys

ARG, FROM = sys.argv[1], sys.argv[2]


def fail(code, msg):
    print(msg, file=sys.stderr)
    sys.exit(code)


def under(path, folder):
    return path == folder or path.startswith(folder.rstrip(os.sep) + os.sep)


def tasks_root(start):
    """The nearest Tasks at or above start, written lexically: the link is kept, not followed."""
    d = os.path.normpath(os.path.abspath(start))
    while True:
        if os.path.isdir(os.path.join(d, 'Tasks')):
            return os.path.join(d, 'Tasks')
        parent = os.path.dirname(d)
        if parent == d:
            fail(2, 'no Tasks folder at or above %s' % os.path.abspath(start))
        d = parent


TASKS = tasks_root(FROM)

if '/' in ARG:
    if not os.path.isdir(ARG):
        fail(2, 'not a directory: %s' % ARG)
    lexical = os.path.normpath(os.path.abspath(ARG))
    # A `..` after a link names the folder the filesystem reaches, not the one normpath leaves: the
    # lexical spelling stands only where it names the same folder.
    if under(lexical, TASKS) and os.path.isdir(lexical) and os.path.samefile(lexical, ARG):
        print(lexical)
        sys.exit(0)
    real, real_tasks = os.path.realpath(ARG), os.path.realpath(TASKS)
    if under(real, real_tasks):
        rest = os.path.relpath(real, real_tasks)
        print(TASKS if rest == '.' else os.path.join(TASKS, rest))
        sys.exit(0)
    fail(5, '%s is not under %s' % (ARG, TASKS))

found = {}


def keep(path):
    found.setdefault(os.path.realpath(path), path)


for depth in (TASKS, *(os.path.join(TASKS, s) for s in sorted(os.listdir(TASKS)))):
    if not os.path.isdir(depth):
        continue
    for name in sorted(os.listdir(depth)):
        if name.startswith(ARG + '-') and not name.endswith('.step') and os.path.isdir(os.path.join(depth, name)):
            keep(os.path.join(depth, name))
# Links below Tasks are not followed: a loop there must not hang the search.
for top, dirs, _ in os.walk(TASKS, followlinks=False):
    dirs.sort()
    for name in dirs:
        if name.endswith('.step') and (name == ARG + '.step' or name.startswith(ARG + '-')):
            keep(os.path.join(top, name))

matches = sorted(found.values())
if not matches:
    fail(3, 'not found: %s under %s' % (ARG, TASKS))
if len(matches) > 1:
    print('\n'.join(matches))
    fail(4, 'ambiguous: %s' % ARG)
print(matches[0])
PY
