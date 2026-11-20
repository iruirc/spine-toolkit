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
# and as <id>.step or <id>-*.step at any depth below. A folder whose whole name is the id — a root task
# by its full name, an epic's 2.step — wins over the folders it only begins. A Tasks that is a dangling
# link is a stop: a Tasks further up belongs to another project.
#
# Usage: scripts/task-dir.sh <task_id | path> [--from <dir>]
# Exit:  0 the task folder on stdout, absolute, through Tasks;
#        2 usage, no Tasks at or above --from, a Tasks that is not a folder, or a path that is not one;
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
        tasks = os.path.join(d, 'Tasks')
        if os.path.isdir(tasks):
            return tasks
        if os.path.lexists(tasks):
            fail(2, '%s is not a folder' % tasks)
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

exact, begun = {}, {}


def keep(path, name):
    (exact if name == ARG else begun).setdefault(os.path.realpath(path), path)


for depth in (TASKS, *(os.path.join(TASKS, s) for s in sorted(os.listdir(TASKS)))):
    if not os.path.isdir(depth):
        continue
    for name in sorted(os.listdir(depth)):
        if not name.endswith('.step') and (name == ARG or name.startswith(ARG + '-')) \
                and os.path.isdir(os.path.join(depth, name)):
            keep(os.path.join(depth, name), name)
# Links below Tasks are followed — a status folder may be one — and each folder is entered once, so a
# loop cannot hang the search.
seen = set()
for top, dirs, _ in os.walk(TASKS, followlinks=True):
    real = os.path.realpath(top)
    if real in seen:
        dirs[:] = []
        continue
    seen.add(real)
    dirs.sort()
    for name in dirs:
        if name.endswith('.step') and (name in (ARG, ARG + '.step') or name.startswith(ARG + '-')):
            keep(os.path.join(top, name), name if name == ARG else name[:-len('.step')])

matches = sorted((exact or begun).values())
if not matches:
    fail(3, 'not found: %s under %s' % (ARG, TASKS))
if len(matches) > 1:
    print('\n'.join(matches))
    fail(4, 'ambiguous: %s' % ARG)
print(matches[0])
PY
