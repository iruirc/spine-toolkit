#!/usr/bin/env bash
set -euo pipefail

# Checks a ManualChecks.md against the QA test-case format of the manual-checks skill. The reader is
# a tester who knows the product but not the code: every case starts from its own preconditions,
# every step row holds one action, and code lives only in the ## Code references section. Its checks:
#
#   case      every case under ## Cases is "### MC-<n>. <observable behaviour>", ids are unique, and
#             the eleven labels are there; a ## Cases with no such case under it is named (a case
#             at the wrong level, #### MC-1. or ## MC-1., is no case), unless it reads "none — <why>"; a file of "### <n>." headings
#             and no MC- heading is named once as the old format, and its cases are not read further;
#             a case with a **Code:** field inside it is named once as the old format too: the
#             references moved out of the case into ## Code references;
#   steps     **Steps:** is a table headed "| # | Action | Data | Expected | Actual |", and no row
#             leaves Action or Expected empty ("—" is a value);
#   compound  an Action that holds two steps: then, and then, afterwards, repeat steps, a semicolon,
#             and their Russian forms;
#   code      code in Action, Expected, **Preconditions:** or **What it checks:** — a CamelCase word of
#             two or more humps, a source file, a dotted name of three or more parts (a version or a
#             decimal is not one), a (file:line) gloss;
#   codeslot  a case with no row in ## Code references (a table "| Case | Code |", one "| MC-<n> | ... |"
#             row per case), a row with no file:line, a row for an id that is no case under ## Cases;
#   chain     a case that starts from another case's end state, or a file that keeps its edit history;
#   instrument **By instrument:** in a case, a ## Reading the verdict section in the file, a screen
#             recording asked of the tester in a step or in any field of a case ("record the screen",
#             "screen recording", "start recording" and their Russian forms): nothing a person walks is
#             settled by an instrument, a measurement is Validation.md's or a line of ## Not covered;
#   scriptable a case whose every step is a shell command: a backticked command with at most a verb
#             before it, or "run the command ..." and its Russian forms; nothing in it needs a person,
#             so it is a script, not a case; a case with one step a person takes is not named;
#   file      [COVERS], ## Run record and ## On failure are there, and ## Code references when there is
#             a case.
#
# No check counts lines: a case, a section and the file have no line limit.
#
# A file whose [STYLE] line reads brief is read by the skill's ## Brief section instead; a file with no
# such line, or with full, is read as above. In brief:
#
#   case      the three labels **What it checks:**, **Start:** and **Failure looks like:** are there,
#             and no field of the full case is (once per case);
#   steps     at least one numbered step "1. <action>" carries its expectation after "→", on its own
#             line or on the line under it; a table, a conditions table in **Test data:**
#             included, is never a step;
#   file      [COVERS] and a **Result:** line are there, ## Code references when there is a case, and
#             no section of the full file is: ## Run record, ## On failure, ## Troubleshooting,
#             ## Charter, ### Screen map;
#   compound, code, codeslot, chain, instrument and scriptable read the brief case as they read a
#             full one: the Action is the text of a numbered step before "→", the Expected the text
#             after it, and **Start:** is read where a full case's **Preconditions:** is.
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
          'Expected result', 'Failure looks like', 'Cleanup', 'Status', 'Notes / attachments']
STEPS_HEADER = ['#', 'Action', 'Data', 'Expected', 'Actual']
# The brief case: its own three labels, and the fields of the full case it does not carry.
BRIEF_LABELS = ['What it checks', 'Start', 'Failure looks like']
BRIEF_NOT = ['Priority', 'Traces to', 'Preconditions', 'Expected result', 'Cleanup', 'Status',
             'Notes / attachments', 'Steps']
BRIEF_NOT_SECTIONS = ('## Run record', '## On failure', '## Troubleshooting', '## Charter', '### Screen map')
STYLE = re.compile(r'^\s*\[STYLE\]\s*=\s*\[?\s*(brief|full)\s*\]?\s*$')
NUMBERED = re.compile(r'^(\d+)\.\s+(.*)$')

FENCE = re.compile(r'^\s*(`{3,}|~{3,})')
HEADING = re.compile(r'^(#{1,6})\s+(.*?)\s*#*\s*$')
MC = re.compile(r'^### MC-(\d+)\.(.*)$')
OLD = re.compile(r'^### (\d+)\.')
LABEL_LINE = re.compile(r'^\s*\*\*[^*\n]+:\*\*')
CELL_SPLIT = re.compile(r'(?<!\\)\|')

# Russian words are \u escapes: the toolkit keeps Cyrillic out of scripts (scripts/lint-i18n.sh).
COMPOUND = [re.compile(p, re.I) for p in (
    r'\band then\b', r'\bthen\b', r'\bafterwards\b', r'\brepeat\s+(?:the\s+)?steps?\b', r';',
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
# A step that is a shell command: the whole Action a backticked command with at most a verb before it,
# or a verb of running with the word command after it. The Russian stems: execute, launch, command.
RUN_VERB = r'(?:run|execute|\u0432\u044b\u043f\u043e\u043b\u043d\w*|\u0437\u0430\u043f\u0443\u0441\u0442\w*)'
# The backticked text holds a space, a slash, a dot, a dash or an equals sign, so a screen label in
# backticks (`Checkout`) is not one; the word command follows the verb with at most one word between,
# so the Undo command of a menu and the Russian word for team are not one. Russian: script, and read
# the output.
# A recording asked of the tester, in a step or in a field: nobody reads it, so no case asks for one.
RECORD_FIELDS = ('What it checks', 'Preconditions', 'Start', 'Test data', 'Expected result', 'Failure looks like',
                  'Cleanup', 'Notes / attachments')
RECORD = [re.compile(p, re.I) for p in (
    r'\brecord\s+the\s+screen\b', r'\bscreen\s+recording\b', r'\bstart\s+recording\b',
    r'\u0437\u0430\u043f\u0438(?:\u0441|\u0448)\w*\s+\u044d\u043a\u0440\u0430\u043d',   # record the screen
    r'\u0432\u043a\u043b\u044e\u0447(?:\u0438\u0442\u044c|\u0438\u0442\u0435)\s+\u0437\u0430\u043f\u0438\u0441\u044c',  # turn the recording on
)]
CMD_CODE = re.compile(r'^(?:' + RUN_VERB + r'\s+)?(?:the\s+)?(?:script\s+|\u0441\u043a\u0440\u0438\u043f\u0442\s+)?'
                      r'`[^`]*[\s/.=-][^`]*`'
                      r'(?:\s+and\s+read\s+(?:the\s+)?output|\s+\u0438\s+\u043f\u0440\u043e\u0447\u0438\u0442\u0430\u0442\u044c\s+\u0432\u044b\u0432\u043e\u0434)?$', re.I)
CMD_REF = re.compile(r'\b' + RUN_VERB + r'\s+(?:the\s+|\w+\s+)?(?:commands?|\u043a\u043e\u043c\u0430\u043d\u0434\w*)\b', re.I)
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
                # In brief the steps follow a field with no label of their own: a numbered step ends it.
                if LABEL_LINE.match(nxt) or (brief and NUMBERED.match(nxt)):
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


def numbered_steps(body):
    """The brief steps: each "<n>. <action>" line at the margin, with the indented lines under it.
    Returns (n, action, expected) per step; expected is None when no "→" follows the action."""
    out, cur = [], None
    for line in body:
        m = NUMBERED.match(line)
        if m:
            cur = [m.group(1), m.group(2)]
            out.append(cur)
        elif cur is not None and line.strip() and (line[:1].isspace() or line.startswith('\u2192')):
            cur[1] += '\n' + line.strip()
        else:
            cur = None
    steps = []
    for n, text in out:
        action, arrow, expected = text.partition('\u2192')
        steps.append((n, action.strip(), expected.strip() if arrow else None))
    return steps


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

# The style: brief only when the file says so, so a file written before the style existed reads as full.
style = next((STYLE.match(line).group(1) for line, h in rows if h is None and STYLE.match(line)), 'full')
brief = style == 'brief'

# file
if not any(re.match(r'^\s*\[COVERS\]', line) for line, h in rows if h is None):
    found.append('file: missing [COVERS] (file)')
if brief:
    for t in titles:
        if any(t == s or (s == '## On failure' and t.startswith(s)) for s in BRIEF_NOT_SECTIONS):
            found.append('file: a section brief does not carry (%s)' % t)
    if not any(line.lstrip().startswith('**Result:**') for line, h in rows if h is None):
        found.append('file: missing **Result:** (file)')
else:
    if not any(t == '## Run record' for t in titles):
        found.append('file: missing ## Run record (file)')
    if not any(t.startswith('## On failure') for t in titles):
        found.append('file: missing ## On failure (file)')

# instrument, at file level: the section an instrument's commands lived in.
if any(t.startswith('## Reading the verdict') for t in titles):
    found.append('instrument: ## Reading the verdict in the file (## Reading the verdict)')

cases = [(i, h) for i, h in headings if MC.match(h[1])]
old = [(i, h) for i, h in headings if OLD.match(h[1])]

# ## Code references: the table's rows, "MC-<n>" to the text of the Code cell.
refs, has_refs = {}, False
for i, h in headings:
    if h == (2, '## Code references'):
        has_refs = True
        for line in section(i, 2):
            if not line.lstrip().startswith('|') or set(line.strip()) <= set('|-: '):
                continue
            c = cells(line)
            r = re.match(r'^MC-(\d+)$', c[0])
            if r and len(c) > 1 and r.group(1) not in refs:
                refs[r.group(1)] = c[1]

# The old format keeps the references in the case, as a **Code:** field.
old_code = next((i for i, h in cases
                 if any('**Code:**' in line for line in section(i, 3) if not line.lstrip().startswith('|'))), None)

if cases and not has_refs and old_code is None:
    found.append('file: missing ## Code references (file)')

if not cases and old:
    found.append('case: old format, ### <n>. headings instead of ### MC-<n>. (### %s.)' % OLD.match(old[0][1][1]).group(1))
else:
    in_cases, under_cases = False, None
    for i, h in headings:
        if h[0] <= 2:
            in_cases = h[1] == '## Cases'
            if in_cases and under_cases is None:
                under_cases = 0
        elif h[0] == 3 and in_cases and MC.match(h[1]):
            under_cases += 1
        elif h[0] == 3 and in_cases:
            m = OLD.match(h[1])
            found.append('case: heading is not ### MC-<n>. <observable behaviour> (%s)' % ('### %s.' % m.group(1) if m else h[1]))
    # A case one level off (#### MC-1., ## MC-1.) is not a case: the section reads as empty.
    # Under [MANUAL_CHECKS] = always a run may leave no case: ## Cases then reads "none — <why>".
    said_none = any(trimmed(section(i, 2))[:1] and trimmed(section(i, 2))[0].lower().startswith('none')
                    for i, h in headings if h == (2, '## Cases'))
    if under_cases == 0 and not said_none:
        found.append('case: no case under ## Cases (## Cases)')

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
    for label in (BRIEF_LABELS if brief else LABELS):
        if not any('**%s:**' % label in line for line in plain):
            found.append('case: missing **%s:** (%s)' % (label, where))
    if brief and any('**%s:**' % label in line for label in BRIEF_NOT for line in plain):
        found.append('case: a field brief does not carry (%s)' % where)
    if any('**By instrument:**' in line for line in plain):
        found.append('instrument: **By instrument:** in a case (%s)' % where)
    if i == old_code:
        found.append('case: old format, **Code:** inside a case instead of ## Code references (%s)' % where)

    table = [] if brief else steps_table(body)
    actions, expects = [], []
    if brief:
        steps = numbered_steps(body)
        if not any(e is not None for _, _, e in steps):
            found.append('steps: no numbered step with \u2192 (%s)' % where)
        for n, action, expected in steps:
            actions.append((n, action))
            expects.append((n, expected or ''))
    elif not table:
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

    for (step, action), (_, expected) in zip(actions, expects):
        if any(p.search(t) for p in RECORD for t in (action, expected)):
            found.append('instrument: a screen recording in a step (%s, step %s)' % (where, step))
    for label in RECORD_FIELDS:
        text = field(plain, label)
        if text is not None and any(p.search(text) for p in RECORD):
            found.append('instrument: a screen recording in **%s:** (%s)' % (label, where))

    for step, text in actions:
        hit = next((p.search(text) for p in COMPOUND if p.search(text)), None)
        if hit:
            found.append('compound: "%s" in the Action of step %s (%s)' % (hit.group(), step, where))

    if actions and all(CMD_CODE.match(t.strip()) or CMD_REF.search(t) for _, t in actions):
        found.append('scriptable: no step needs a person, run it as a script (%s)' % where)

    places = [('the Action of step %s' % s, t) for s, t in actions] + \
             [('the Expected of step %s' % s, t) for s, t in expects]
    for label in (('Start', 'What it checks') if brief else ('Preconditions', 'What it checks')):
        text = field(plain, label)
        if text is not None:
            places.append(('**%s:**' % label, text))
    places.sort(key=lambda p: 0 if p[0].startswith('the ') else 1)
    for name, text in places:
        for word in code_in(text):
            found.append('code: "%s" in %s (%s)' % (word, name, where))

    if has_refs and old_code is None:
        if m.group(1) not in refs:
            found.append('codeslot: no row in ## Code references (%s)' % where)
        elif not FILE_LINE.search(refs[m.group(1)]):
            found.append('codeslot: no file:line in ## Code references (%s)' % where)

for n in refs:
    if n not in seen:
        found.append('codeslot: row for a case not in ## Cases (MC-%s)' % n)

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
