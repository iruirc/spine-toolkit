#!/usr/bin/env bash
set -euo pipefail

# Measures the prose of a task folder's artifacts against the project's [LANG].
# Which files, what counts as prose and where a finding starts: conventions/artifact-language.md.
#
# Usage: scripts/lint-artifact-lang.sh <task-dir> [<task-dir> ...]
# Exit:  0 nothing written in the wrong language, 1 something is, 2 usage or an unresolvable config.
#
# The language comes from scripts/resolve-settings.sh, the one reader of CLAUDE-spine-toolkit.md.

[ "$#" -ge 1 ] || { echo "usage: $0 <task-dir> [<task-dir> ...]" >&2; exit 2; }

RESOLVE="$(dirname -- "${BASH_SOURCE[0]}")/resolve-settings.sh"
python3 - "$RESOLVE" "$@" <<'PY'
import json, os, re, subprocess, sys

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
# The types of conventions/commit-messages.md: a quoted subject stays English at any [LANG].
SUBJECT = re.compile(r'\b(?:feat|fix|refactor|test|docs|chore|perf|style)(?:\([^)\n]*\))?!?: .*$', re.M)
INLINE = [
    re.compile(r'`[^`\n]*`'),
    re.compile(r'\*\*[^*\n]{1,40}:\*\*'),
    re.compile(r'https?://\S+'),
    re.compile(r'\S*[/\\]\S*'),
    re.compile(r'\b\w+\.[A-Za-z][A-Za-z0-9]{0,5}\b'),
]
HEADING = re.compile(r'^ {0,3}(#{1,6})\s+(.*?)\s*#*\s*$')
FENCE = re.compile(r'^\s*(`{3,}|~{3,})')
DROPPED_LINE = re.compile(r'^\s*(\||\[[A-Z_]+\]\s*=)')


def chunks(text):
    """(heading, prose) pairs: the text before the first heading, then the text under each
    heading up to the next one of any level. A fence may be indented under a list item, and
    what it holds is code whatever the indentation."""
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    out, title, buf, fence = [], '(preamble)', [], None
    for line in text.split('\n'):
        m = FENCE.match(line)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence):
                fence = None
            continue
        if m:
            fence = m.group(1)
            continue
        h = HEADING.match(line)
        if h:
            out.append((title, '\n'.join(buf)))
            title, buf = h.group(0).strip(), []
            continue
        if DROPPED_LINE.match(line):
            continue
        buf.append(line)
    out.append((title, '\n'.join(buf)))
    return out


def prose(text):
    text = SUBJECT.sub('', text)
    for pattern in INLINE:
        text = pattern.sub(' ', text)
    return text


def count(text, lang):
    own = foreign = 0
    for code, (_, pattern) in SCRIPTS.items():
        n = len(pattern.findall(text))
        if code == lang:
            own += n
        else:
            foreign += n
    return own, foreign


def settings(task_dir, resolve):
    out = subprocess.run([resolve, 'json', task_dir], capture_output=True, text=True)
    for line in out.stderr.splitlines():
        if line.split(": '", 1)[0].endswith('[LANG]'):
            print(line, file=sys.stderr)
    if out.returncode != 0:
        print(out.stderr, end='', file=sys.stderr)
        print('lint-artifact-lang.sh: resolve-settings.sh failed for %s' % task_dir, file=sys.stderr)
        sys.exit(2)
    return json.loads(out.stdout)


resolve, dirs = sys.argv[1], sys.argv[2:]
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
    name = SCRIPTS[lang][0]
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
        parts = [(title, prose(body)) for title, body in chunks(text)]
        whole = '\n'.join(body for _, body in parts)
        for title, body in parts + [('(file)', whole)]:
            own, foreign = count(body, lang)
            total = own + foreign
            if total >= MIN_LETTERS and own * 100 < FLOOR_PERCENT * total:
                findings.append('%s § %s: %d%% %s in %d letters of prose (lang %s)'
                                % (path, title, own * 100 // total, name, total, lang))

for f in findings:
    print(f)

if findings:
    print()
    print('artifact language failed: %d finding(s)' % len(findings))
    sys.exit(1)

print('artifact language passed')
PY
