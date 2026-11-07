"""Prose extraction shared by the artifact lints (lint-artifact-lang.sh, lint-walkthrough.sh).

Import with sys.path.insert(0, <scripts>/lib). Which lines are prose and which are not is
decided here once, so every lint measures the same text.

Known limit: a full stop after an abbreviation never ends a sentence, so a sentence that ends on one
("... and so on, etc. Next one.") is counted together with the sentence after it. Telling that full
stop apart needs more than the text around it; the split leans toward one long count over a false
short one.
"""
import json
import os
import re
import subprocess
import sys

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
FENCE = re.compile(r'^\s*(`{3,}|~{3,})(.*)$')
DROPPED_LINE = re.compile(r'^\s*(\||>|\[[A-Z_]+\]\s*=|\*\*Run:\*\*|\*\*Device:\*\*)')
LIST_ITEM = re.compile(r'^\s*[-*+]\s')

# The default threshold: a sentence longer than this many words is a style finding. The threshold a
# lint applies is the budget key words-per-sentence of the task (words_per_sentence() below);
# this constant is the key's default and what the resolver falls back to.
MAX_WORDS = 30

# After these a full stop does not end the sentence; a spaced form (t. e.) holds inside it too. The
# Russian ones are \u escapes: the toolkit keeps Cyrillic out of scripts (scripts/lint-i18n.sh).
ABBREVIATIONS = (
    'e.g.', 'i.e.', 'etc.',
    '\u0442.\u0435.', '\u0442.\u0434.', '\u043d\u0430\u043f\u0440.', '\u0441\u043c.', '\u0440\u0438\u0441.',
    '\u0442. \u0435.', '\u0442. \u0434.',
)
# A terminator run followed by whitespace. A decimal point or comma has no whitespace after it,
# so 0.8 and 0,8 never match here.
BOUNDARY = re.compile('[.!?…]+\\s+')
WORD = re.compile(r'`[^`\n]*`|[^\W_]+(?:-[^\W_]+)*')

# A label line (**Files:** and its kin) is a list of names, not prose, and so is its wrapped tail.
LABEL_LINE = re.compile(r'^\s*(?:[-*+]\s+)?\*\*(?:Files|Changes|Commits|Steps):\*\*')
LIST_START = re.compile(r'^\s*(?:[-*+]|\d+[.)])\s+')
LEAD = re.compile(r'^\*\*[^*\n]{1,40}[.:]\*\*\s*')

_RESOLVE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'resolve-settings.sh')
_BUDGETS = {}
_WARNED = set()


def chunks(text, checklist=False):
    """(heading, prose) pairs: the text before the first heading, then the text under each
    heading up to the next one of any level. A fence may be indented under a list item, and
    what it holds is code whatever the indentation."""
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    out, title, buf, fence = [], '(preamble)', [], None
    for line in text.split('\n'):
        m = FENCE.match(line)
        if fence:
            # CommonMark: only the run alone, at least as long as the opening one, closes a fence.
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
                fence = None
            continue
        # CommonMark: a backtick fence's info string holds no backtick, or the line opens nothing.
        if m and not (m.group(1)[0] == '`' and '`' in m.group(2)):
            fence = m.group(1)
            continue
        h = HEADING.match(line)
        if h:
            out.append((title, '\n'.join(buf)))
            title, buf = h.group(0).strip(), []
            continue
        if DROPPED_LINE.match(line):
            continue
        if checklist and LIST_ITEM.match(line):
            # A checklist item's own text is the catalog's, English at any [LANG]: prose is what
            # follows its first dash, and an item with no dash has none.
            if ' — ' not in line:
                continue
            line = line.split(' — ', 1)[1]
        buf.append(line)
    out.append((title, '\n'.join(buf)))
    return out


def prose(text):
    text = SUBJECT.sub('', text)
    for pattern in INLINE:
        text = pattern.sub(' ', text)
    return text


def _abbreviation(head):
    """True when head, the text up to and including a terminator, ends in an abbreviation."""
    low = head.lower()
    for abbr in ABBREVIATIONS:
        if low.endswith(abbr) and (len(low) == len(abbr) or not low[-len(abbr) - 1].isalnum()):
            return True
    return False


def _inside_abbreviation(head, rest):
    """True when head ends on the first part of a spaced abbreviation (t. e.) and rest, the text
    after the whitespace, carries the remainder of it."""
    low, tail = head.lower(), rest.lower()
    for abbr in ABBREVIATIONS:
        if ' ' not in abbr:
            continue
        first, remainder = abbr.split(' ', 1)
        if low.endswith(first) and (len(low) == len(first) or not low[-len(first) - 1].isalnum()) \
                and tail.startswith(remainder):
            return True
    return False


def sentences(text):
    """The sentences of text, split on . ! ? or an ellipsis followed by whitespace, except after
    an abbreviation. A decimal is never split: nothing follows its point or comma but a digit."""
    out, start = [], 0
    for m in BOUNDARY.finditer(text):
        head = text[start:m.start() + len(m.group().rstrip())]
        if _abbreviation(head) or _inside_abbreviation(head, text[m.end():]):
            continue
        out.append(text[start:m.start() + len(m.group().rstrip())])
        start = m.end()
    out.append(text[start:])
    return [s.strip() for s in out if s.strip()]


def words(sentence):
    """Runs of letters and digits, a hyphenated compound as one; an inline code span is one word."""
    return len(WORD.findall(sentence))


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


def words_per_sentence(directory, lint=None):
    """The words-per-sentence budget of directory, from scripts/resolve-settings.sh (run, Task.md,
    epic, project, default 30). Only the resolver's lines about [BUDGETS] are forwarded to stderr,
    each at most once per process; the rest are other settings' business. A resolver failure
    prints "<lint>: resolve-settings.sh failed for <directory>" and exits 2, the code every
    lint keeps for input it cannot read."""
    if directory in _BUDGETS:
        return _BUDGETS[directory]
    lint = lint or os.path.basename(sys.argv[0] if sys.argv and sys.argv[0] not in ('', '-', '-c') else 'lint')
    def fail():
        print('%s: resolve-settings.sh failed for %s' % (lint, directory), file=sys.stderr)
        sys.exit(2)

    try:
        out = subprocess.run([_RESOLVE, 'json', directory], capture_output=True, text=True)
    except OSError:
        fail()
    failed = out.returncode != 0
    for line in out.stderr.splitlines():
        if not line or line in _WARNED:
            continue
        if not failed and not line.split(": '", 1)[0].endswith('[BUDGETS]'):
            continue
        _WARNED.add(line)
        print(line, file=sys.stderr)
    if failed:
        fail()
    # An answer that is not the settings json is a failed resolver too, whatever its exit code said.
    try:
        budgets = json.loads(out.stdout).get('budgets', {})
        value = budgets.get('words-per-sentence', MAX_WORDS)
    except (ValueError, AttributeError):
        fail()
    _BUDGETS[directory] = value if isinstance(value, int) and value > 0 else MAX_WORDS
    return _BUDGETS[directory]
