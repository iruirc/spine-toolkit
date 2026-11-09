#!/usr/bin/env bash
set -euo pipefail

# Checks the report of a task and the links to it. A task whose results spread over several artifacts
# leaves one topic document, the report, in a documentation place; the artifacts link to it. The
# fields come from Plan.md, else from Research.md (a RESEARCH task has no Plan.md, and the Plan.md of
# an epic may carry none), written as in Task.md: "[REPORT_DECISION] = needed" and "[REPORT_PATH] =
# <path from the project root>", the brackets around a value optional, a list marker ("- ") before the
# name, "**" around it and backticks around the value tolerated. Its checks, for a decision of needed or update:
#
#   report    the file <root>/<REPORT_PATH> is there;
#   link      Done.md is there, and Done.md, Plan.md and Research.md (the last two when they exist)
#             link to the report: a Markdown link target ("](target)") or a reference definition
#             ("[x]: target"), stripped of "#anchor", URL-decoded, resolved against the folder of
#             the artifact itself, equals <root>/<REPORT_PATH> after normalising the path;
#   name      the report names the task folder, by its name;
#   section   the report has a heading "Where sources disagree" (any level, any case, a number
#             prefix is fine), or its Russian form.
#
# A decision of not-needed, or no fields, is nothing to check. A decision of unplaced prints a
# reminder and passes. The root is the folder of the project config that resolve-settings.sh finds
# for the task, unless --root names it.
#
# Usage: scripts/lint-report-links.sh <task-dir> [--root <project-root>]
# Exit:  0 nothing found, or nothing to check;
#        1 one line per finding, "report: <what>";
#        2 usage, an unknown decision, a decision with no path, or no root.

usage() { echo "usage: $0 <task-dir> [--root <project-root>]" >&2; exit 2; }

task="" root=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) [ "$#" -ge 2 ] || usage; root="$2"; shift 2 ;;
    -*) usage ;;
    *) [ -z "$task" ] || usage; task="$1"; shift ;;
  esac
done
[ -n "$task" ] && [ -d "$task" ] || usage

exec python3 - "$task" "$root" "$(cd "$(dirname "$0")" && pwd)" <<'PY'
import json, os, re, subprocess, sys
from urllib.parse import unquote

task, root, scripts = sys.argv[1], sys.argv[2], sys.argv[3]
task = os.path.realpath(task)
DECISIONS = ('needed', 'update', 'not-needed', 'unplaced')

# The Russian heading is \u escapes: the toolkit keeps Cyrillic out of scripts (scripts/lint-i18n.sh);
# "where sources disagree" in Russian.
SECTION = re.compile(r'^#{1,6}\s+.*(?:where sources disagree|\u0433\u0434\u0435 \u0438\u0441\u0442\u043e\u0447\u043d\u0438\u043a\u0438 \u0440\u0430\u0441\u0445\u043e\u0434\u044f\u0442\u0441\u044f)',
                     re.I | re.M)
INLINE = re.compile(r'\]\(\s*(<[^>\n]*>|[^)\s]*)')
REFDEF = re.compile(r'^ {0,3}\[[^\]\n]+\]:\s*(<[^>\n]*>|\S+)', re.M)


def read(path):
    with open(path, encoding='utf-8', errors='replace') as fh:
        return fh.read()


def field(text, name):
    """The value of a "[NAME] = value" line, brackets optional, a trailing "# comment" dropped.

    The line may be a list item ("- " or "* ") and the name may be bold ("**[NAME]**"); a value in
    backticks is read without them."""
    m = re.search(r'^[ \t]*(?:[-*][ \t]+)?(?:\*\*)?\[%s\](?:\*\*)?[ \t]*=[ \t]*(.*)$' % name, text, re.M)
    if not m:
        return None
    rest = m.group(1).strip()
    b = re.match(r'\[(.*?)\]', rest)
    value = b.group(1) if b else re.split(r'\s+#', rest, 1)[0]
    return value.strip().strip('`').strip()


def fail(message):
    print(message)
    sys.exit(2)


# The first of Plan.md, Research.md that carries a field: an epic on the pure-research branch has a
# Plan.md with none and its fields in Research.md.
decision = path = None
for n in ('Plan.md', 'Research.md'):
    full = os.path.join(task, n)
    if os.path.isfile(full):
        text = read(full)
        decision, path = field(text, 'REPORT_DECISION'), field(text, 'REPORT_PATH')
        if decision is not None or path is not None:
            break

if decision is None or decision == 'not-needed':
    sys.exit(0)
if decision not in DECISIONS:
    fail('report: [REPORT_DECISION] = %s is not one of %s' % (decision, ', '.join(DECISIONS)))
if decision == 'unplaced':
    print('report: unplaced — Done writes no report until Questions.md answers where it goes')
    sys.exit(0)
if not path:
    fail('report: [REPORT_DECISION] = %s without [REPORT_PATH]' % decision)

if not root:
    run = subprocess.run([os.path.join(scripts, 'resolve-settings.sh'), 'json', task],
                         capture_output=True, text=True)
    try:
        config = json.loads(run.stdout).get('project_config')
    except ValueError:
        config = None
    if not config:
        fail('report: no project config above %s; pass --root' % sys.argv[1])
    root = os.path.dirname(config)
root = os.path.realpath(root)
report = os.path.normpath(os.path.join(root, path))
name = os.path.basename(task)


def links(artifact):
    """True when a link in the artifact resolves to the report."""
    base = os.path.dirname(artifact)
    for target in INLINE.findall(read(artifact)) + REFDEF.findall(read(artifact)):
        target = target.strip()
        if target.startswith('<') and target.endswith('>'):
            target = target[1:-1]
        target = unquote(target.split('#', 1)[0])
        if target and os.path.normpath(os.path.join(base, target)) == report:
            return True
    return False


found = []
have = os.path.isfile(report)
if not have:
    found.append('report: %s: missing' % path)

done = os.path.join(task, 'Done.md')
if not os.path.isfile(done):
    found.append('report: Done.md: missing')
for artifact in ('Done.md', 'Plan.md', 'Research.md'):
    full = os.path.join(task, artifact)
    if os.path.isfile(full) and not links(full):
        found.append('report: %s: no link to %s' % (artifact, path))

if have:
    body = read(report)
    if name not in body:
        found.append('report: %s: does not name the task %s' % (path, name))
    if not SECTION.search(body):
        found.append('report: %s: no "Where sources disagree" section' % path)

if found:
    print('\n'.join(found))
    sys.exit(1)
PY
