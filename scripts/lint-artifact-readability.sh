#!/usr/bin/env bash
set -euo pipefail

# Measures the prose of the artifacts a task leaves against the reader who did not follow the task:
# Done.md, Plan.md, Review.md, Research.md, Questions.md, OpsChecklist.md. Its classes:
#   sentence     a sentence over words-per-sentence words (the budget key of the task's directory,
#                30 unless a Task.md, an epic or the project sets it, or the run's value passed in
#                --words-per-sentence), in any section
#   identifiers  backtick spans piled into the first section (at least IDENT_MIN_SPANS of them and
#                more than IDENT_SHARE of its words), or more than CELL_MAX_SPANS in one cell of a
#                table column headed What, Note or Evidence
#   label        a label (M1, u3, P5, Q1, R1) outside brackets and parentheses that starts a sentence
#                with no gloss right after it (a parenthesised span, or a dash or colon and at least
#                three words), or stands in a sentence of fewer than LABEL_MIN_WORDS words
#   question     Questions.md only: an entry of the log without a **Question:** of three words; an
#                entry already written in the old form (an id, then RESOLVED or DEFERRED, with no
#                **Question:**) stays as it is
#   format       OpsChecklist.md only: a table, where the checklist is a list
# What counts as prose is scripts/lib/prose.py, the same text lint-artifact-lang.sh and
# lint-walkthrough.sh measure: fences, tables, quotes, headings and the machine lines of the closing
# block ([DONE_COMMIT], [REVIEW_FIXES], [REVIEWED_COMMIT], **Run:**, **Device:**) are not prose,
# wherever those lines stand, so a file in the old layout (markers on top) reads like a new one.
# It runs at both scales and reads no setting but words-per-sentence. The thresholds named below are
# starting values, to be calibrated against real artifacts.
#
# A label is one or two capitals, or one small letter, then one or two digits, standing alone: not
# followed by a letter, a digit, a backtick, a hyphen, a slash or a decimal point (v2.0, S3-compatible,
# H264 and H1-style are no labels). A key before a title at the start of a list item or a paragraph
# (M1. Title, **M1. Title**, M1: title, M1 — title) names that title and is not checked, when a
# title follows it: three words, or two when the title is the bold span the key opens. A key with
# less than that after it stays a label ("- M1: fixed." reads as "M1: fixed." in a paragraph does).
# A sentence never ends after a lone label: "M1." joins the sentence after it. Known limit: a short
# code of the same shape (EC2, MP3, Q3, V8) reads as a label; in a sentence of four words or more
# that does not start with it, it passes.
#
# Usage: scripts/lint-artifact-readability.sh [--words-per-sentence <n>] <task-dir|file>
#        A directory checks those of the artifacts above that exist in it (none: nothing to say);
#        a file is chosen by its basename and read against its own directory's settings.
#        --words-per-sentence, a positive integer, replaces the threshold the directory resolves to:
#        the run's own budget, which a directory cannot know.
# Exit:  0 nothing found, or nothing to check;
#        1 one line per finding, "<Artifact>.md: <class>: <what> (<where>)", <where> being the nearest
#          heading text; a sentence or label finding quotes the first five words of its sentence;
#        2 usage, a path that does not exist, a basename that is not one of the artifacts, or a
#          resolver that could not answer.

HERE="$(dirname -- "${BASH_SOURCE[0]}")"
ARTIFACTS="Done.md Plan.md Review.md Research.md Questions.md OpsChecklist.md"

usage() { echo "usage: $0 [--words-per-sentence <n>] <task-dir|file>  (artifacts: $ARTIFACTS)" >&2; exit 2; }
wps=
if [ "${1:-}" = --words-per-sentence ]; then
  [ "$#" -ge 2 ] || usage
  case "$2" in '' | *[!0-9]* | 0*) usage ;; esac
  wps="$2"
  shift 2
fi
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

python3 - "$HERE/lib" "$dir" "$wps" "${files[@]}" <<'PY'
import os, re, sys

# chunks() and the sentence helpers are shared with the other artifact lints. No bytecode: a python
# without a cache prefix would otherwise leave scripts/lib/__pycache__ in the plugin.
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
from prose import chunks, sentences, words, units, words_per_sentence, LEAD, SUBJECT, INLINE, HEADING, FENCE, LIST_START

DIR, WPS, FILES = sys.argv[2], sys.argv[3], sys.argv[4:]

# Starting values, guessed before data: they are calibrated against the Tasks/DONE corpus.
IDENT_MIN_SPANS = 3          # the first section needs at least this many backtick spans ...
IDENT_SHARE = 0.10           # ... and they must be more than this share of its words
CELL_MAX_SPANS = 2           # a cell may hold this many spans, one more is a finding
CELL_HEADERS = ('what', 'note', 'evidence')   # English column headers, compared case-insensitively
LABEL_MIN_WORDS = 4          # a label outside brackets needs a sentence of this many words around it
LOG_HEADING = 'Questions Log'
QUESTION_MIN_WORDS = 3

SPAN = re.compile(r'`[^`\n]*`')
# u3, M1, P5, MA12: one or two letters and one or two digits, alone (not inside a longer word, not
# before a hyphen, a slash or a decimal point), in backticks or not. The header names the limit.
LABEL = r'(?:[A-Z]{1,2}|[a-z])\d{1,2}'
AFTER = r'(?![\w`\-/]|\.\d)'
LABEL_FREE = re.compile(r'(?<![\w`])(`?)(%s)\1%s' % (LABEL, AFTER))
LABEL_SPAN = re.compile(r'^`%s`$' % LABEL)
# A label that starts a sentence, after any opening markup.
LABEL_LEAD = re.compile(r'^[\s*_>"\'\u201c\u00ab-]*(`?)(%s)\1%s' % (LABEL, AFTER))
# A sentence that is a label and nothing else: "M1." cut off the title that follows it.
LABEL_ALONE = re.compile(r'^[\s*_>"\'\u201c\u00ab-]*(`?)%s\1[.:]?(?:\*\*)?$' % LABEL)
# The key before a title at the start of a list item or a paragraph: "M1. Title", "**M1. Title**",
# "M1: title", "M1 \u2014 title". It names the title that follows, as ENTRY_KEY does in Questions.md.
KEY = re.compile(r'^(?:\[[ xX]\]\s+)?(\*\*)?(`?)%s\2(?:[.:]|\s+\u2014)(\*\*)?\s+' % LABEL)
KEY_TITLE_WORDS = 3          # a key is dropped only when a title of this many words follows it
KEY_BOLD_TITLE_WORDS = 2     # ... or of this many, when the title is the bold span the key opens
QUOTE_MARKS = '"\u201c\u201d\''
BRACKETED = re.compile(r'\([^()]*\)|\[[^\[\]]*\]')
LABEL_BOLD = re.compile(r'\*\*[^*\n]{1,40}:\*\*')
QUESTION = re.compile(r'\*\*Question:\*\*\s*(.*)', re.S)
# A Questions.md entry starts on its key, "[plan] q1 — ": the id names the entry and the question
# that follows is its gloss, so the key is not a label to be glossed.
ENTRY_KEY = re.compile('^(?:\\[[^\\]\\n]*\\]\\s+)+\\S+\\s+\u2014\\s+')
# The old form of an entry, "[plan] q2 \u2014 RESOLVED: ...": written before the template, it stays.
OLD_FORM = re.compile('\u2014\\s+(?:RESOLVED:|DEFERRED)')
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


def mask(text, kept):
    """Every backtick span as a numbered placeholder span (one word, no full stop inside it), except
    one that is a label alone: that stays what it is. kept collects the spans, for quote()."""
    def one(m):
        if LABEL_SPAN.match(m.group()):
            return m.group()
        kept.append(m.group())
        return '`\x00%d\x00`' % (len(kept) - 1)
    return SPAN.sub(one, text)


def quote(sentence, kept):
    """The first five words of sentence, its spans as written, and an ellipsis when it goes on."""
    text = re.sub('`\x00(\\d+)\x00`', lambda m: kept[int(m.group(1))], sentence)
    parts = text.strip(QUOTE_MARKS + ' \t').split()
    return '"%s"' % (' '.join(parts[:5]) + (' \u2026' if len(parts) > 5 else ''))


def drop_key(joined):
    """(joined without its leading key, True), or (joined, False) when the key has no title after
    it: the label then stays and is judged like the same text in the middle of a paragraph."""
    m = KEY.match(joined)
    if not m:
        return joined, True
    rest = joined[m.end():]
    if m.group(1) and not m.group(3) and '**' in rest:
        title, need = rest.split('**', 1)[0], KEY_BOLD_TITLE_WORDS
    else:
        title, need = (sentences(mask(rest, []))[:1] or [''])[0], KEY_TITLE_WORDS
    return (rest, True) if words(title) >= need else (joined, False)


def debracket(t):
    while True:
        u = BRACKETED.sub(' ', t)
        if u == t:
            return t
        t = u


def unlabelled(sentence):
    """The label of sentence that has no gloss next to it, or None."""
    t = sentence
    for pattern in INLINE[1:]:
        t = pattern.sub(' ', t)
    lead = LABEL_LEAD.match(t)
    if lead:
        rest = t[lead.end():].lstrip(' \t*_')
        if rest[:1] in (':', '\u2014', '\u2013') or rest[:2] == '- ':
            if words(debracket(rest[1:])) < 3:
                return lead.group(2)
        elif not rest.startswith('('):
            return lead.group(2)
    t = debracket(t)
    found = LABEL_FREE.search(t)
    if found and words(LABEL_FREE.sub(' ', t)) < LABEL_MIN_WORDS:
        return found.group(2)
    return None


def joined_labels(parts):
    """sentences() with a lone label joined to the sentence after it."""
    out, held = [], None
    for s in parts:
        if held is not None:
            s, held = held + ' ' + s, None
        if LABEL_ALONE.match(s):
            held = s
            continue
        out.append(s)
    if held is not None:
        out.append(held)
    return out


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
            joined, keyed = drop_key(joined)
            kept = []
            masked = mask(LEAD.sub('', joined, 1) if keyed else joined, kept)
            for sentence in joined_labels(sentences(masked)):
                plain = sentence
                for pattern in INLINE[1:]:
                    plain = pattern.sub(' ', plain)
                count = words(plain)
                if count > limit:
                    out.append('sentence: sentence of %d words: %s (%s)' % (count, quote(sentence, kept), where))
                token = unlabelled(sentence)
                if token:
                    out.append('label: label without a gloss: %s in %s (%s)' % (token, quote(sentence, kept), where))
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
            if not m and OLD_FORM.search(entry):
                continue
            asked = LABEL_BOLD.split(m.group(1), 1)[0] if m else ''
            if words(asked) < QUESTION_MIN_WORDS:
                out.append('question: entry without a question (%s)' % place(title))
    return out


def format_pass(text):
    out, inside, last = [], False, None
    for where, line in lines_by_heading(text):
        # A heading ends a table: the table under the next heading is a finding of its own.
        if where != last:
            inside, last = False, where
        table = line.lstrip().startswith('|')
        if table and not inside:
            out.append('format: table row; the checklist is a list (%s)' % where)
        inside = table
    return out


limit = int(WPS) if WPS else words_per_sentence(os.path.abspath(DIR), 'lint-artifact-readability.sh')
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
