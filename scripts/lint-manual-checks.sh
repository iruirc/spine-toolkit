#!/usr/bin/env bash
set -euo pipefail

# Checks a ManualChecks.md against the QA test-case format of the manual-checks skill. The reader is
# a tester who knows the product but not the code: every case starts from its own preconditions,
# every step row holds one action, and code lives only in the **Code:** field. Its checks:
#
#   case      every case under ## Cases is "### MC-<n>. <observable behaviour>", ids are unique, and
#             the twelve labels are there; a file of "### <n>." headings and no MC- heading is named
#             once as the old format, and its cases are not read further;
#   steps     **Steps:** is a table headed "| # | Action | Data | Expected | Actual |", and no row
#             leaves Action or Expected empty ("—" is a value);
#   compound  an Action that holds two steps: then, and then, repeat steps, a semicolon, and their
#             Russian forms;
#   code      code in Action, Expected, **Preconditions:** or **What it checks:** — a CamelCase word of
#             two or more humps, a source file, a dotted name of three or more parts (a version or a
#             decimal is not one), a (file:line) gloss;
#   codeslot  a **Code:** field with no file:line;
#   chain     a case that starts from another case's end state, or a file that keeps its edit history;
#   budget    a case over 40 lines, heading to last line; ## Scope over 8; ## Preparation over 60
#             (blank lines inside count, the ones at either end do not);
#   file      [COVERS], ## Run record and ## On failure are there.
#
# Known limit: a product name in CamelCase (YouTube, PayPal) reads as code. There is no allow-list.
#
# Usage: scripts/lint-manual-checks.sh <ManualChecks.md | task-dir>
#        A directory means its ManualChecks.md.
# Exit:  0 nothing found, or nothing to measure (no such file, a directory without one);
#        1 one line per finding, "ManualChecks.md: <check>: <what> (<where>)";
#        2 usage.

[ "$#" -eq 1 ] || { echo "usage: $0 <ManualChecks.md | task-dir>" >&2; exit 2; }
path="$1"
[ -d "$path" ] && path="$path/ManualChecks.md"
[ -f "$path" ] || exit 0

python3 - "$path" <<'PY'
import re, sys

LABELS = ['Priority', 'Traces to', 'What it checks', 'Preconditions', 'Test data', 'Steps',
          'Expected result', 'Failure looks like', 'Cleanup', 'Code', 'Status', 'Notes / attachments']
STEPS_HEADER = ['#', 'Action', 'Data', 'Expected', 'Actual']
BUDGET_CASE, BUDGET_SCOPE, BUDGET_PREPARATION = 40, 8, 60

FENCE = re.compile(r'^\s*(`{3,}|~{3,})')
HEADING = re.compile(r'^(#{1,6})\s+(.*?)\s*#*\s*$')
MC = re.compile(r'^### MC-(\d+)\.(.*)$')
OLD = re.compile(r'^### (\d+)\.')
LABEL_LINE = re.compile(r'^\s*\*\*[^*\n]+:\*\*')
CELL_SPLIT = re.compile(r'(?<!\\)\|')

# Russian words are \u escapes: the toolkit keeps Cyrillic out of scripts (scripts/lint-i18n.sh).
COMPOUND = [re.compile(p, re.I) for p in (
    r'\band then\b', r'\bthen\b', r'\brepeat\s+(?:the\s+)?steps?\b', r';',
    r'\b\u0437\u0430\u0442\u0435\u043c\b',                               # then
    r'\b\u043f\u043e\u0442\u043e\u043c\b',                               # afterwards
    r'\b\u0438\s+\u0441\u0440\u0430\u0437\u0443\b',                      # and at once
    r'\b\u043f\u043e\u0432\u0442\u043e\u0440\w*\s+\u0448\u0430\u0433\w*',  # repeat steps
)]
CHAIN = [re.compile(p, re.I) for p in (
    r'\bafter\s+(?:case\s+(?:MC-)?\d+|MC-\d+)',
    r'\bstate\s+right\s+after\b',
    r'\bchanges\s+in\s+this\s+revision\b',
    r'\u043f\u043e\u0441\u043b\u0435\s+(?:\u043a\u0435\u0439\u0441\u0430\s+(?:MC-)?\d+|MC-\d+)',  # after case N
    r'\u0441\u043e\u0441\u0442\u043e\u044f\u043d\u0438\w*\s+\u0441\u0440\u0430\u0437\u0443\s+\u043f\u043e\u0441\u043b\u0435',  # state right after
    r'\u0438\u0437\u043c\u0435\u043d\u0435\u043d\u0438\w*\s+(?:\u0432\s+)?\u044d\u0442\u043e\u0439\s+\u0440\u0435\u0434\u0430\u043a\u0446\u0438\w*',  # changes in this revision
)]
# Code a tester cannot know. The CamelCase word starts upper case so that iPhone or eBay is not one;
# a dotted name needs a letter at the start of every part, so 2.1.0 and 0.8 are not one.
GLOSS = re.compile(r'\([^()]*[A-Za-z_][\w./-]*:\d+[^()]*\)')
CODE = [
    re.compile(r'\b[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+\b'),
    re.compile(r'[\w/.-]*\w\.(?:swift|kts?)\b'),
    re.compile(r'\b[A-Za-z_]\w*(?:\.[A-Za-z_]\w*){2,}\b'),
    re.compile(r'\b[\w/-]+\.[A-Za-z]{1,5}:\d+\b'),
]
FILE_LINE = re.compile(r'[A-Za-z_][\w./-]*:\d+')

path = sys.argv[1]
with open(path, encoding='utf-8', errors='replace') as fh:
    lines = fh.read().split('\n')

# Each line with the heading it sits under; a line inside a fence is never a heading.
rows, fence = [], None
for line in lines:
    m = FENCE.match(line)
    if fence:
        if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not line.strip()[len(m.group(1)):]:
            fence = None
        rows.append((line, None))
        continue
    if m:
        fence = m.group(1)
        rows.append((line, None))
        continue
    h = HEADING.match(line)
    rows.append((line, (len(h.group(1)), line.strip()) if h else None))


def section(start, level):
    """Lines after the heading at start, down to the next heading of this level or higher."""
    out = []
    for line, h in rows[start + 1:]:
        if h and h[0] <= level:
            break
        out.append(line)
    return out


def trimmed(body):
    while body and not body[0].strip():
        body = body[1:]
    while body and not body[-1].strip():
        body = body[:-1]
    return body


def cells(line):
    s = line.strip()
    s = s[1:] if s.startswith('|') else s
    s = s[:-1] if s.endswith('|') and not s.endswith('\\|') else s
    return [c.strip() for c in CELL_SPLIT.split(s)]


def field(body, label):
    """The text of a **Label:** field, from the label to the next label line; None when absent."""
    tag = '**%s:**' % label
    for i, line in enumerate(body):
        if tag in line and not line.lstrip().startswith('|'):
            text = [line.split(tag, 1)[1]]
            for nxt in body[i + 1:]:
                if LABEL_LINE.match(nxt):
                    break
                text.append(nxt)
            return '\n'.join(text)
    return None


def steps_table(body):
    """The table that follows **Steps:** (or the first table, with no label): its lines, or []."""
    start = next((i for i, line in enumerate(body) if '**Steps:**' in line), -1)
    table = []
    for line in body[start + 1:]:
        if line.lstrip().startswith('|'):
            table.append(line)
        elif table or (start >= 0 and LABEL_LINE.match(line)):
            break
    return table


def code_in(text):
    hits, rest = [], text
    for g in GLOSS.finditer(text):
        hits.append(g.group())
    rest = GLOSS.sub(' ', rest)
    for pattern in CODE:
        for m in pattern.finditer(rest):
            word = m.group()
            # U.S.A. is an abbreviation, not a name.
            if pattern is CODE[2] and all(len(p) == 1 for p in word.split('.')):
                continue
            if word not in hits:
                hits.append(word)
    return hits


found = []
headings = [(i, h) for i, (_, h) in enumerate(rows) if h]
titles = [h[1] for _, h in headings]

# file
if not any(re.match(r'^\s*\[COVERS\]', line) for line, h in rows if h is None):
    found.append('file: missing [COVERS] (file)')
if not any(t == '## Run record' for t in titles):
    found.append('file: missing ## Run record (file)')
if not any(t.startswith('## On failure') for t in titles):
    found.append('file: missing ## On failure (file)')

cases = [(i, h) for i, h in headings if MC.match(h[1])]
old = [(i, h) for i, h in headings if OLD.match(h[1])]

if not cases and old:
    found.append('case: old format, ### <n>. headings instead of ### MC-<n>. (### %s.)' % OLD.match(old[0][1][1]).group(1))
else:
    in_cases = False
    for i, h in headings:
        if h[0] == 2:
            in_cases = h[1] == '## Cases'
        elif h[0] == 3 and in_cases and not MC.match(h[1]):
            m = OLD.match(h[1])
            found.append('case: heading is not ### MC-<n>. <observable behaviour> (%s)' % ('### %s.' % m.group(1) if m else h[1]))

seen = set()
for i, h in cases:
    m = MC.match(h[1])
    where = '### MC-%s.' % m.group(1)
    body = section(i, 3)
    if m.group(1) in seen:
        found.append('case: id MC-%s is used twice (%s)' % (m.group(1), where))
    seen.add(m.group(1))
    if not m.group(2).strip():
        found.append('case: no observable behaviour after the id (%s)' % where)
    plain = [line for line in body if not line.lstrip().startswith('|')]
    for label in LABELS:
        if not any('**%s:**' % label in line for line in plain):
            found.append('case: missing **%s:** (%s)' % (label, where))

    table = steps_table(body)
    actions, expects = [], []
    if not table:
        found.append('steps: no steps table (%s)' % where)
    elif cells(table[0]) != STEPS_HEADER:
        found.append('steps: header is not | # | Action | Data | Expected | Actual | (%s)' % where)
    else:
        for n, line in enumerate((r for r in table[1:] if not ('-' in r and set(r.strip()) <= set('|-: '))), 1):
            c = cells(line)
            step = c[0] or str(n)
            if len(c) != len(STEPS_HEADER):
                found.append('steps: step %s has %d cells, not %d (%s)' % (step, len(c), len(STEPS_HEADER), where))
                continue
            if not c[1]:
                found.append('steps: step %s has an empty Action (%s)' % (step, where))
            if not c[3]:
                found.append('steps: step %s has an empty Expected (%s)' % (step, where))
            actions.append((step, c[1]))
            expects.append((step, c[3]))

    for step, text in actions:
        hit = next((p.search(text) for p in COMPOUND if p.search(text)), None)
        if hit:
            found.append('compound: "%s" in the Action of step %s (%s)' % (hit.group(), step, where))

    places = [('the Action of step %s' % s, t) for s, t in actions] + \
             [('the Expected of step %s' % s, t) for s, t in expects]
    for label in ('Preconditions', 'What it checks'):
        text = field(plain, label)
        if text is not None:
            places.append(('**%s:**' % label, text))
    places.sort(key=lambda p: 0 if p[0].startswith('the ') else 1)
    for name, text in places:
        for word in code_in(text):
            found.append('code: "%s" in %s (%s)' % (word, name, where))

    code = field(plain, 'Code')
    if code is not None and not FILE_LINE.search(code):
        found.append('codeslot: no file:line in **Code:** (%s)' % where)

    span = trimmed([h[1]] + body)
    if len(span) > BUDGET_CASE:
        found.append('budget: case of %d lines, more than %d (%s)' % (len(span), BUDGET_CASE, where))

for name, limit in (('Scope', BUDGET_SCOPE), ('Preparation', BUDGET_PREPARATION)):
    for i, h in headings:
        if h == (2, '## ' + name):
            n = len(trimmed(section(i, 2)))
            if n > limit:
                found.append('budget: ## %s of %d lines, more than %d (## %s)' % (name, n, limit, name))

# chain, over the whole file: a line names the heading it sits under.
where = 'file'
for line, h in rows:
    if h:
        m = MC.match(h[1])
        where = '### MC-%s.' % m.group(1) if m else h[1]
    for p in CHAIN:
        for m in p.finditer(line):
            found.append('chain: "%s" (%s)' % (m.group(), where))

if found:
    print('\n'.join('ManualChecks.md: ' + f for f in found))
    sys.exit(1)
PY
