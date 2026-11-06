#!/usr/bin/env bash
set -euo pipefail

# Checks a task's Walkthrough.md against the task's history and against its own header: a commit
# ## Commits names that a reset or a squash dropped, a section the skill requires for the file's
# depth, a deep section that holds more than one commit, and a commit of a declared range that the
# body never names — what a patch that cut the file short leaves behind. Its classes: unreachable,
# section, heading, missing, count, range, behind, style.
#
# The style class reads the prose, not the history: a sentence over MAX_WORDS words, an identifier
# in ## What changed, a sentence that starts with an identifier or holds more than two, and, at
# deep, a commit section without **In short:** (or, with sub-headings, without **How verified:**).
# What counts as prose is scripts/lib/prose.py, the same text lint-artifact-lang.sh measures.
#
# With --current it also asks whether the file is up to date: every repository's newest own commit
# named in ## Commits. Nothing to measure is then a finding, since there is nothing up to date.
#
# With --style it runs only the style pass, on one file: no task dir, no git.
#
# Usage: scripts/lint-walkthrough.sh [--current] <task-dir>
#        scripts/lint-walkthrough.sh --style <path-to-Walkthrough.md>
# Exit:  0 nothing found, or nothing to measure (no Walkthrough.md, no Base.md, an EPIC);
#        1 one line per finding, "Walkthrough.md: <class>: <what> (<where>)";
#        2 usage, a --style argument that is not a file, or task-ranges.sh could not answer.

HERE="$(dirname -- "${BASH_SOURCE[0]}")"
current=0
mode=task
if [ "${1:-}" = --style ]; then
  mode=style
  shift
  [ "$#" -eq 1 ] || { echo "usage: $0 --style <path-to-Walkthrough.md>" >&2; exit 2; }
  [ -f "$1" ] || { echo "not a file: $1" >&2; exit 2; }
else
  [ "${1:-}" = --current ] && { current=1; shift; }
  [ "$#" -eq 1 ] || { echo "usage: $0 [--current] <task-dir>" >&2; exit 2; }
  [ -d "$1" ] || { echo "not a directory: $1" >&2; exit 2; }
fi

python3 - "$HERE/task-ranges.sh" "$1" "$current" "$HERE/lib" "$mode" <<'PY'
import os, re, subprocess, sys

RANGES, TASK, CURRENT, MODE = sys.argv[1], sys.argv[2], sys.argv[3] == '1', sys.argv[5]
# chunks() and the sentence helpers are shared with the other artifact lints.
sys.path.insert(0, sys.argv[4])
from prose import chunks, sentences, words, MAX_WORDS, SUBJECT, INLINE, HEADING, FENCE as PROSE_FENCE
SHA = r'[0-9a-f]{7,40}'
# Every backticked sha or sha range on a line, wherever it sits: a heading may put a word or bold
# markup before one.
TOKEN = re.compile(r'`(%s)(?:\.\.(%s))?`' % (SHA, SHA))
NUMBER = re.compile(r'^###\s+([\d\u2013-]+)')
FENCE = re.compile(r'^\s*(`{3,}|~{3,})')
# task-walkthrough, ## Structure: the sections each depth always carries; the glossary and
# ## How it works are left out when nothing earns them.
SECTIONS = {
    'deep': ['What changed', 'Summary', 'Commit order', 'Plan vs. outcome', 'Commits', 'Out of scope', 'Follow-ups'],
    'brief': ['What changed', 'Summary', 'Plan vs. outcome', 'Commits', 'Follow-ups'],
}


def task_type():
    try:
        with open(os.path.join(TASK, 'Task.md'), encoding='utf-8') as fh:
            m = re.search(r'^\[TASK_TYPE\]\s*=\s*\[?([A-Za-z_]+)', fh.read(), re.M)
            return m.group(1).upper() if m else None
    except OSError:
        return None


def ranges(*args):
    r = subprocess.run([RANGES] + list(args), capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit(2)
    return r.stdout.split()


def span(a, b, where):
    # A range the file itself spells wrong is a finding about the file, not a failure of the lint.
    r = subprocess.run([RANGES, 'commits', TASK, '%s..%s' % (a, b)], capture_output=True, text=True)
    if r.returncode != 0 and 'no repository of the task holds' in r.stderr:
        found.append('range: %s..%s is not a range of one repository (%s)' % (a, b, where))
        return None
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit(2)
    return r.stdout.split()


def cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]


# The style pass. Prose is what scripts/lib/prose.py keeps: no code, tables, quotes or headings.
# A label line (**Files:** and its kin) is a list of names, not prose, and so is its wrapped tail.
LABEL_LINE = re.compile(r'^\s*(?:[-*+]\s+)?\*\*(?:Files|Changes|Commits|Steps):\*\*')
LIST_START = re.compile(r'^\s*(?:[-*+]|\d+[.)])\s+')
LEAD = re.compile(r'^\*\*[^*\n]{1,40}[.:]\*\*\s*')
SPAN = re.compile(r'`[^`\n]*`')
# A commit log line (brief ## Commits, ### Bookkeeping) starts on a sha or a range by design.
SHA_SPAN = re.compile(r'^`%s(?:\.\.%s)?`$' % (SHA, SHA))
BARE = re.compile(r'^(?:`[XS]`[\s.,;:!?]*)+$')
LOG_LINE = re.compile(r'^`%s(?:\.\.%s)?`' % (SHA, SHA))


def units(body):
    """The lines of each paragraph, a list item or a numbered item starting a unit of its own, so
    that a list without final dots is not read as one long sentence."""
    cur, tail = [], False
    for line in body.split('\n'):
        if not line.strip():
            if cur:
                yield cur
            cur, tail = [], False
        elif LABEL_LINE.match(line):
            if cur:
                yield cur
            cur, tail = [], True
        elif tail and line[0] in ' \t' and not LIST_START.match(line):
            continue
        else:
            tail = False
            if LIST_START.match(line):
                if cur:
                    yield cur
                cur = [LIST_START.sub('', line, 1)]
            else:
                cur.append(line.strip())
    if cur:
        yield cur


def outline(text):
    """(level, heading line, lines outside fences) per heading, the text before the first one
    under level 0. Fences close as prose.chunks() closes them."""
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    out, fence = [(0, '', [])], None
    for line in text.split('\n'):
        m = PROSE_FENCE.match(line)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
                fence = None
            continue
        if m and not (m.group(1)[0] == '`' and '`' in m.group(2)):
            fence = m.group(1)
            continue
        h = HEADING.match(line)
        if h:
            out.append((len(h.group(1)), h.group(0).strip(), []))
        else:
            out[-1][2].append(line)
    return out


def place(title):
    m = NUMBER.match(title)
    return '### ' + m.group(1) if m else title


def is_deep(entries):
    commits = False
    for level, title, _ in entries:
        if level == 2:
            commits = title[3:].strip() == 'Commits'
            if title[3:].strip() == 'Glossary':
                return True
        elif level == 3 and commits and (NUMBER.match(title) or TOKEN.search(title)) and title != '### Bookkeeping':
            return True
    return False


def style(text, deep):
    out = []
    for title, body in chunks(text):
        where = place(title)
        for unit in units(body):
            joined = ' '.join(unit)
            joined = LEAD.sub('', joined.strip(), 1)
            log_line = bool(LOG_LINE.match(joined))
            lines = []
            for line in unit:
                cut = SUBJECT.sub('', line)
                # A subject quoted in backticks loses its closing backtick with the rest of the line.
                if cut != line and cut.count('`') % 2:
                    i = cut.rindex('`')
                    cut = cut[:i] + cut[i + 1:]
                lines.append(cut.strip())
            # A sha or a range is a reference to a commit, not an identifier: masked as `S`.
            masked = SPAN.sub(lambda m: '`S`' if SHA_SPAN.match(m.group()) else '`X`',
                              LEAD.sub('', ' '.join(lines).strip(), 1))
            for i, sentence in enumerate(sentences(masked)):
                n = sentence.count('`X`')
                plain = sentence
                for pattern in INLINE[1:]:
                    plain = pattern.sub(' ', plain)
                count = words(plain)
                if count > MAX_WORDS:
                    out.append('style: sentence of %d words (%s)' % (count, where))
                # A sentence that is only a reference (a path closing a log line) has no subject to be.
                if BARE.match(sentence):
                    pass
                elif sentence.startswith('`X`') or (sentence.startswith('`S`') and not (i == 0 and log_line)):
                    out.append('style: sentence starts with an identifier (%s)' % where)
                if n > 2:
                    out.append('style: %d identifiers in one sentence (%s)' % (n, where))
    entries = outline(text)
    for k, (level, title, lines) in enumerate(entries):
        if level == 2 and title[3:].strip() == 'What changed':
            # Raw text, tables included, down to the next ## heading.
            raw = list(lines)
            for sub in entries[k + 1:]:
                if sub[0] <= 2:
                    break
                raw += [sub[1]] + sub[2]
            if any(SPAN.search(line) for line in raw):
                out.append('style: identifier in ## What changed (## What changed)')
    if deep:
        commits = False
        for k, (level, title, lines) in enumerate(entries):
            if level == 2:
                commits = title[3:].strip() == 'Commits'
            if not (commits and level == 3 and NUMBER.match(title)):
                continue
            body, subs = list(lines), False
            for sub in entries[k + 1:]:
                if sub[0] <= 3:
                    break
                subs = True
                body += [sub[1]] + sub[2]
            where = place(title)
            if not any('**In short:**' in line for line in body):
                out.append('style: missing **In short:** (%s)' % where)
            if subs and not any('**How verified:**' in line for line in body):
                out.append('style: missing **How verified:** (%s)' % where)
    return out


def report(found):
    if found:
        print('\n'.join('Walkthrough.md: ' + f for f in found))
        sys.exit(1)
    sys.exit(0)


if MODE == 'style':
    with open(TASK, encoding='utf-8') as fh:
        text = fh.read()
    report(style(text, is_deep(outline(text))))

path = os.path.join(TASK, 'Walkthrough.md')
# An epic's ## Commits holds a section per step, not per commit.
if not os.path.isfile(path) or not os.path.isfile(os.path.join(TASK, 'Base.md')) or task_type() == 'EPIC':
    if CURRENT:
        print('Walkthrough.md: behind: no file, no Base.md, or an EPIC (%s)' % TASK)
        sys.exit(1)
    sys.exit(0)

headings, named, headers, perimeter, columns = [], [], [], [], None
where, fence, part, table, bullet = None, None, 'header', False, None
for line in open(path, encoding='utf-8'):
    m = FENCE.match(line)
    if m:
        # Only a run of the same character, at least as long, closes a fence.
        if fence is None:
            fence = m.group(1)
        elif m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not line.strip()[len(m.group(1)):]:
            fence = None
        continue
    if fence:
        continue
    if line.startswith('## '):
        part, where = line[3:].strip(), None
        headings.append(part)
        continue
    if part == 'header':
        # The perimeter ends where its table does; a later table in the header is not its rows.
        row = cells(line) if line.startswith('|') else None
        if row and columns is None and 'Range' in row and 'Commits' in row:
            columns, table = (row.index('Range'), row.index('Commits')), True
        elif row and table and not set(''.join(row)) <= set('-: '):
            perimeter.append(row)
        elif not row:
            table = False
        continue
    if part != 'Commits':
        continue
    if line.startswith('### '):
        if line.strip() == '### Bookkeeping':
            where = 'Bookkeeping'
            continue
        m = NUMBER.match(line)
        where = '### ' + m.group(1) if m else '###'
        found = [t.groups() for t in TOKEN.finditer(line)]
        headers.append((where, len(found), bool(m)))
        named += [(t, where) for t in found]
    elif where in (None, 'Bookkeeping') and (line.startswith('- ') or (bullet and line.startswith('  ') and line.strip())):
        # Bullets inside a commit's own section are its prose, not the log; a wrapped bullet is one.
        bullet = where or 'brief'
        named += [(t.groups(), bullet) for t in TOKEN.finditer(line)]
        continue
    bullet = None

deep = 'Glossary' in headings or any(n or numbered for _, n, numbered in headers)
declared = []
for row in perimeter:
    m = TOKEN.search(row[columns[0]]) if len(row) > max(columns) else None
    if m:
        declared.append((row[0].strip('`'), m.group(1), m.group(2) or m.group(1), row[columns[1]]))

ends = sorted({s for (a, b), _ in named for s in (a, b) if s} | {s for _, a, b, _ in declared for s in (a, b)})
gone = set(ranges('unreachable', TASK, *ends)) if ends else set()

found = []
for (a, b), w in named:
    found += ['unreachable: %s is not in the task\'s history (%s)' % (s, w) for s in (a, b) if s in gone]
for repo, a, b, _ in declared:
    found += ['unreachable: %s is not in the task\'s history (header %s)' % (s, repo) for s in dict.fromkeys((a, b)) if s in gone]
if columns is None:
    found.append('section: no perimeter table with Range and Commits (header)')
found += ['section: missing (## %s)' % s for s in SECTIONS['deep' if deep else 'brief'] if s not in headings]
if deep:
    found += ['heading: %d commits in one section (%s)' % (n, w) for w, n, numbered in headers if n > 1 or (numbered and not n)]

covered = set()
for (a, b), w in named:
    if a in gone or b in gone:
        continue
    covered.update((span(a, b, w) or []) if b else [a])
for repo, a, b, count in declared:
    if a in gone or b in gone:
        continue
    listed = span(a, b, 'header ' + repo)
    if listed is None:
        continue
    found += ['missing: %s is not named in ## Commits (%s)' % (c[:7], repo)
              for c in listed if not any(c.startswith(s) for s in covered)]
    if count.strip() != str(len(listed)):
        found.append('count: the header says %s, the range holds %d (%s)' % (count.strip(), len(listed), repo))

with open(path, encoding='utf-8') as fh:
    found += style(fh.read(), deep)

if CURRENT:
    r = subprocess.run([RANGES, 'last', TASK], capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        sys.exit(2)
    for repo, sha in (line.rsplit(' ', 1) for line in r.stdout.splitlines()):
        if sha == 'unknown':
            found.append('behind: no base to find the newest commit by (%s)' % repo)
        elif not any(sha.startswith(s) for s in covered):
            found.append('behind: %s is not named in ## Commits (%s)' % (sha[:7], repo))

if found:
    print('\n'.join('Walkthrough.md: ' + f for f in found))
    sys.exit(1)
PY
