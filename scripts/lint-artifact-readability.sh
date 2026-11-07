#!/usr/bin/env bash
set -euo pipefail

# Measures the prose of the artifacts a task leaves against the reader who did not follow the task:
# Done.md, Plan.md, Review.md, Research.md, Questions.md, OpsChecklist.md. Its classes:
#   sentence     a sentence over words-per-sentence words (the budget key of the task's directory,
#                30 unless a Task.md, an epic or the project sets it), in any section
#   identifiers  backtick spans piled into the first section (at least IDENT_MIN_SPANS of them and
#                more than IDENT_SHARE of its words), or more than CELL_MAX_SPANS in one cell of a
#                table column headed What, Note or Evidence
#   label        a label (M1, u3, P5) outside brackets and parentheses that starts a sentence, or
#                stands in a sentence of fewer than LABEL_MIN_WORDS words: a name with no gloss
#   question     Questions.md only: an entry of the log without a **Question:** of three words
#   format       OpsChecklist.md only: a table, where the checklist is a list
# What counts as prose is scripts/lib/prose.py, the same text lint-artifact-lang.sh and
# lint-walkthrough.sh measure: fences, tables, quotes, headings and the machine lines of the closing
# block ([DONE_COMMIT], [REVIEW_FIXES], [REVIEWED_COMMIT], **Run:**, **Device:**) are not prose,
# wherever those lines stand, so a file in the old layout (markers on top) reads like a new one.
# It runs at both scales and reads no setting but words-per-sentence. The thresholds named below are
# starting values, to be calibrated against real artifacts.
#
# Usage: scripts/lint-artifact-readability.sh <task-dir|file>
#        A directory checks those of the artifacts above that exist in it (none: nothing to say);
#        a file is chosen by its basename and read against its own directory's settings.
# Exit:  0 nothing found, or nothing to check;
#        1 one line per finding, "<Artifact>.md: <class>: <what> (<where>)", <where> being the nearest
#          heading text;
#        2 usage, a path that does not exist, a basename that is not one of the artifacts, or a
#          resolver that could not answer.

HERE="$(dirname -- "${BASH_SOURCE[0]}")"
ARTIFACTS="Done.md Plan.md Review.md Research.md Questions.md OpsChecklist.md"

usage() { echo "usage: $0 <task-dir|file>  (artifacts: $ARTIFACTS)" >&2; exit 2; }
[ "$#" -eq 1 ] || usage
if [ -d "$1" ]; then
  dir="$1"
  files=()
  for a in $ARTIFACTS; do [ -f "$dir/$a" ] && files+=("$dir/$a"); done
  [ "${#files[@]}" -gt 0 ] || exit 0
elif [ -f "$1" ]; then
  case " $ARTIFACTS " in
    *" $(basename -- "$1") "*) ;;
    *) echo "not an artifact this lint reads: $(basename -- "$1")" >&2; usage ;;
  esac
  dir="$(dirname -- "$1")"
  files=("$1")
else
  echo "no such directory or file: $1" >&2
  exit 2
fi

python3 - "$HERE/lib" "$dir" "${files[@]}" <<'PY'
import os, re, sys

# chunks() and the sentence helpers are shared with the other artifact lints. No bytecode: a python
# without a cache prefix would otherwise leave scripts/lib/__pycache__ in the plugin.
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
from prose import chunks, sentences, words, units, words_per_sentence, LEAD, SUBJECT, INLINE, HEADING, FENCE, LIST_START

DIR, FILES = sys.argv[2], sys.argv[3:]

# Starting values, guessed before data: they are calibrated against the Tasks/DONE corpus.
IDENT_MIN_SPANS = 3          # the first section needs at least this many backtick spans ...
IDENT_SHARE = 0.10           # ... and they must be more than this share of its words
CELL_MAX_SPANS = 2           # a cell may hold this many spans, one more is a finding
CELL_HEADERS = ('what', 'note', 'evidence')   # English column headers, compared case-insensitively
LABEL_MIN_WORDS = 4          # a label outside brackets needs a sentence of this many words around it
LOG_HEADING = 'Questions Log'
QUESTION_MIN_WORDS = 3

SPAN = re.compile(r'`[^`\n]*`')
# u3, M1, P5, MA12: one or two letters and one to three digits, alone (not inside a longer word),
# in backticks or not.
LABEL = r'(?:[A-Z]{1,2}|[a-z])\d{1,3}'
LABEL_FREE = re.compile(r'(?<![\w`])(`?)%s\1(?![\w`])' % LABEL)
LABEL_SPAN = re.compile(r'^`%s`$' % LABEL)
BRACKETED = re.compile(r'\([^()]*\)|\[[^\[\]]*\]')
LABEL_BOLD = re.compile(r'\*\*[^*\n]{1,40}:\*\*')
QUESTION = re.compile(r'\*\*Question:\*\*\s*(.*)', re.S)
# A Questions.md entry starts on its key, "[plan] q1 — ": the id names the entry and the question
# that follows is its gloss, so the key is not a label to be glossed.
ENTRY_KEY = re.compile('^(?:\\[[^\\]\\n]*\\]\\s+)+\\S+\\s+\u2014\\s+')
SEPARATOR = re.compile(r'^:?-{1,}:?$')


def place(title):
    m = HEADING.match(title)
    return m.group(2) if m else title


def level(title):
    m = HEADING.match(title)
    return len(m.group(1)) if m else 0


def lines_by_heading(text):
    """(heading text, line) for every line outside comments and fences."""
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    where, fence = '(preamble)', None
    for line in text.split('\n'):
        m = FENCE.match(line)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
                fence = None
            continue
        if m and not (m.group(1)[0] == '`' and '`' in m.group(2)):
            fence = m.group(1)
            continue
        h = HEADING.match(line)
        if h:
            where = h.group(2)
            continue
        yield where, line


def cells(line):
    row = line.strip()[1:]
    if row.endswith('|') and not row.endswith('\\|'):
        row = row[:-1]
    return [c.strip() for c in re.split(r'(?<!\\)\|', row)]


def mask(text):
    """Every backtick span as `X`, except one that is a label alone: that stays what it is."""
    return SPAN.sub(lambda m: m.group() if LABEL_SPAN.match(m.group()) else '`X`', text)


def unlabelled(sentence):
    """True when sentence holds a label that has no gloss next to it."""
    t = sentence
    while True:
        u = BRACKETED.sub(' ', t)
        if u == t:
            break
        t = u
    for pattern in INLINE[1:]:
        t = pattern.sub(' ', t)
    found = LABEL_FREE.search(t)
    if not found:
        return False
    if not t[:found.start()].strip(' \t*_>"\'“«-'):
        return True
    return words(LABEL_FREE.sub(' ', t)) < LABEL_MIN_WORDS


def prose_pass(text, limit, entries_keyed):
    out = []
    for title, body in chunks(text):
        where = place(title)
        for unit in units(body):
            lines = []
            for line in unit:
                cut = SUBJECT.sub('', line)
                # A subject quoted in backticks loses its closing backtick with the rest of the line.
                if cut != line and cut.count('`') % 2:
                    i = cut.rindex('`')
                    cut = cut[:i] + cut[i + 1:]
                lines.append(cut.strip())
            joined = ' '.join(lines).strip()
            if entries_keyed:
                joined = ENTRY_KEY.sub('', joined, 1)
            masked = mask(LEAD.sub('', joined, 1))
            for sentence in sentences(masked):
                plain = sentence
                for pattern in INLINE[1:]:
                    plain = pattern.sub(' ', plain)
                count = words(plain)
                if count > limit:
                    out.append('sentence: sentence of %d words (%s)' % (count, where))
                if unlabelled(sentence):
                    out.append('label: label without a gloss (%s)' % where)
    return out


def first_section(text):
    """(heading text, prose) of the first ## section, its sub-headings included."""
    where, parts = None, []
    for title, body in chunks(text):
        lvl = level(title)
        if where is None:
            if lvl == 2:
                where = place(title)
                parts.append(body)
        elif 0 < lvl <= 2:
            break
        else:
            parts.append(body)
    return where, '\n'.join(parts)


def identifier_pass(text):
    out = []
    where, body = first_section(text)
    if where is not None:
        n = len(SPAN.findall(body))
        plain = SPAN.sub('`X`', body)
        for pattern in INLINE[1:]:
            plain = pattern.sub(' ', plain)
        total = words(plain)
        if n >= IDENT_MIN_SPANS and n > IDENT_SHARE * total:
            out.append('identifiers: %d of %d words are identifiers in the first section (%s)' % (n, total, where))
    # A table is dropped from chunks(): its cells are read here, under the column headers.
    header = columns = None
    for where, line in lines_by_heading(text):
        if not line.lstrip().startswith('|'):
            header = columns = None
            continue
        row = cells(line)
        if header is None:
            header = row
        elif columns is None:
            if all(SEPARATOR.match(c) for c in row if c):
                columns = [i for i, c in enumerate(header) if c.replace('*', '').replace('`', '').strip().lower() in CELL_HEADERS]
            else:
                header = row
        else:
            for i in columns:
                if i < len(row) and len(SPAN.findall(row[i])) > CELL_MAX_SPANS:
                    out.append('identifiers: %d identifiers in one cell (%s)' % (len(SPAN.findall(row[i])), where))
    return out


def entries(body):
    """The list items of body, each with the lines that continue it."""
    item, blank = None, False
    for line in body.split('\n'):
        if not line.strip():
            blank = True
        elif LIST_START.match(line):
            if item is not None:
                yield ' '.join(item)
            item, blank = [LIST_START.sub('', line, 1).strip()], False
        elif item is not None and (not blank or line[0] in ' \t'):
            item.append(line.strip())
            blank = False
        else:
            if item is not None:
                yield ' '.join(item)
            item, blank = None, False
    if item is not None:
        yield ' '.join(item)


def question_pass(text):
    out, log = [], None
    for title, body in chunks(text):
        lvl = level(title)
        if lvl:
            if LOG_HEADING in place(title):
                log = lvl
            elif log is not None and lvl <= log:
                log = None
        if log is None or not lvl:
            continue
        for entry in entries(body):
            m = QUESTION.search(entry)
            asked = LABEL_BOLD.split(m.group(1), 1)[0] if m else ''
            if words(asked) < QUESTION_MIN_WORDS:
                out.append('question: entry without a question (%s)' % place(title))
    return out


def format_pass(text):
    out, inside = [], False
    for where, line in lines_by_heading(text):
        table = line.lstrip().startswith('|')
        if table and not inside:
            out.append('format: table row; the checklist is a list (%s)' % where)
        inside = table
    return out


limit = words_per_sentence(os.path.abspath(DIR), 'lint-artifact-readability.sh')
found = []
for path in FILES:
    name = os.path.basename(path)
    with open(path, encoding='utf-8', errors='replace') as fh:
        text = fh.read()
    lines = prose_pass(text, limit, name == 'Questions.md') + identifier_pass(text)
    if name == 'Questions.md':
        lines += question_pass(text)
    if name == 'OpsChecklist.md':
        lines += format_pass(text)
    found += ['%s: %s' % (name, line) for line in lines]

if found:
    print('\n'.join(found))
    sys.exit(1)
PY
