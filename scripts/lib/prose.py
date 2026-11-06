"""Prose extraction shared by the artifact lints (lint-artifact-lang.sh, lint-walkthrough.sh).

Import with sys.path.insert(0, <scripts>/lib). Which lines are prose and which are not is
decided here once, so every lint measures the same text.
"""
import re

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
DROPPED_LINE = re.compile(r'^\s*(\||>|\[[A-Z_]+\]\s*=|\*\*Run:\*\*)')
LIST_ITEM = re.compile(r'^\s*[-*+]\s')

# A sentence longer than this many words is a style finding. Release 3 replaces the constant
# with the words-per-sentence budget key.
MAX_WORDS = 30

# After these a full stop does not end the sentence. The Russian ones are \u escapes: the toolkit
# keeps Cyrillic out of scripts (scripts/lint-i18n.sh).
ABBREVIATIONS = (
    'e.g.', 'i.e.', 'etc.',
    '\u0442.\u0435.', '\u0442.\u0434.', '\u043d\u0430\u043f\u0440.', '\u0441\u043c.', '\u0440\u0438\u0441.',
)
# A terminator run followed by whitespace. A decimal point or comma has no whitespace after it,
# so 0.8 and 0,8 never match here.
BOUNDARY = re.compile('[.!?…]+\\s+')
WORD = re.compile(r'`[^`\n]*`|[^\W_]+(?:-[^\W_]+)*')


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


def sentences(text):
    """The sentences of text, split on . ! ? or an ellipsis followed by whitespace, except after
    an abbreviation. A decimal is never split: nothing follows its point or comma but a digit."""
    out, start = [], 0
    for m in BOUNDARY.finditer(text):
        if _abbreviation(text[start:m.start() + len(m.group().rstrip())]):
            continue
        out.append(text[start:m.start() + len(m.group().rstrip())])
        start = m.end()
    out.append(text[start:])
    return [s.strip() for s in out if s.strip()]


def words(sentence):
    """Runs of letters and digits, a hyphenated compound as one; an inline code span is one word."""
    return len(WORD.findall(sentence))
