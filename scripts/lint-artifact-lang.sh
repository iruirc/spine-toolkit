#!/usr/bin/env bash
set -euo pipefail

# Measures the prose of a task folder's artifacts against the project's [LANG].
# Which files, what counts as prose and where a finding starts: conventions/artifact-language.md.
#
# Usage: scripts/lint-artifact-lang.sh <task-dir> [<task-dir> ...]
# Exit:  0 nothing written in the wrong language, 1 something is, 2 usage or an unresolvable config.
#
# The language comes from scripts/resolve-settings.sh, the one reader of the project config.

[ "$#" -ge 1 ] || { echo "usage: $0 <task-dir> [<task-dir> ...]" >&2; exit 2; }

HERE="$(dirname -- "${BASH_SOURCE[0]}")"
RESOLVE="$HERE/resolve-settings.sh"
python3 - "$RESOLVE" "$HERE/lib" "$@" <<'PY'
import json, os, re, subprocess, sys

# chunks() and prose() are shared with the other artifact lints. No bytecode: a python without a
# cache prefix would otherwise leave scripts/lib/__pycache__ in the plugin.
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[2])
from prose import chunks, prose

# conventions/artifact-language.md carries the same table. A language that shares its script with
# another row cannot be told apart from it: only a foreign script is caught.
SCRIPTS = {
    'en': ('Latin', re.compile(r'[A-Za-z]')),
    'ru': ('Cyrillic', re.compile('[%s-%s]' % (chr(0x400), chr(0x4FF)))),
}
MIN_LETTERS = 200
FLOOR_PERCENT = 10
ARTIFACTS = ['Research.md', 'Reproduce.md', 'Plan.md', 'Validation.md', 'Review.md',
             'ChangesRequested.md', 'Done.md', 'Walkthrough.md', 'OpsChecklist.md',
             'ManualChecks.md', 'Docs.md']


def count(text, lang):
    own = foreign = 0
    for code, (_, pattern) in SCRIPTS.items():
        n = len(pattern.findall(text))
        if code == lang:
            own += n
        else:
            foreign += n
    return own, foreign


def finding(path, title, body, lang):
    own, foreign = count(body, lang)
    total = own + foreign
    if total >= MIN_LETTERS and own * 100 < FLOOR_PERCENT * total:
        return '%s § %s: %d%% %s in %d letters of prose (lang %s)' % (
            path, title, own * 100 // total, SCRIPTS[lang][0], total, lang)
    return None


_WARNED = set()


def settings(task_dir, resolve):
    """Forwards the resolver's [LANG] lines, or every line when it failed, each once per run:
    task folders under one project share their warnings."""
    out = subprocess.run([resolve, 'json', task_dir], capture_output=True, text=True)
    for line in out.stderr.splitlines():
        if not line or line in _WARNED:
            continue
        if out.returncode == 0 and not line.split(": '", 1)[0].endswith('[LANG]'):
            continue
        _WARNED.add(line)
        print(line, file=sys.stderr)
    if out.returncode != 0:
        print('lint-artifact-lang.sh: resolve-settings.sh failed for %s' % task_dir, file=sys.stderr)
        sys.exit(2)
    return json.loads(out.stdout)


resolve, dirs = sys.argv[1], sys.argv[3:]
if any(d.startswith('--') for d in dirs):
    print('usage: lint-artifact-lang.sh <task-dir> [<task-dir> ...]', file=sys.stderr)
    sys.exit(2)
for d in dirs:
    if not os.path.isdir(d):
        print('not a directory: %s' % d, file=sys.stderr)
        sys.exit(2)

findings = []
for d in dirs:
    lang = settings(d, resolve).get('lang', 'en')
    if lang not in SCRIPTS:
        print('lint-artifact-lang.sh: no script is declared for lang %s' % lang, file=sys.stderr)
        sys.exit(2)
    for artifact in ARTIFACTS:
        path = os.path.join(d, artifact)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding='utf-8') as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError):
            print('%s: unreadable, skipping' % path, file=sys.stderr)
            continue
        parts = [(title, prose(body)) for title, body in chunks(text, artifact == 'OpsChecklist.md')]
        found = [f for f in (finding(path, title, body, lang) for title, body in parts) if f]
        # The whole file is for one made of short parts: a file already named needs no second line.
        if not found:
            whole = finding(path, '(file)', '\n'.join(body for _, body in parts), lang)
            found = [whole] if whole else []
        findings.extend(found)

for f in findings:
    print(f)

if findings:
    print()
    print('artifact language failed: %d finding(s)' % len(findings))
    sys.exit(1)

print('artifact language passed')
PY
