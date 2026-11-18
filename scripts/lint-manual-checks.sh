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
#   field     the optional marks of a case, written after **What it checks:** and read by a collective
#             pass: **Runner:** is "agent", **Device:** is not empty, **Order:** reads "first — <why>"
#             or "last — <why>"; a mark is judged by its shape, never by the mode of the run, and a
#             label in another case (**runner:**) is no mark;
#   steps     **Steps:** is a table headed "| # | Action | Data | Expected | Actual |", and no row
#             leaves Action or Expected empty ("—" is a value);
#   compound  an Action that holds two steps: then, and then, afterwards, repeat steps, a semicolon,
#             and their Russian forms;
#   code      code in Action, Expected, **Preconditions:** or **What it checks:** — a CamelCase word of
#             two or more humps, a source file, a dotted name of three or more parts (a version or a
#             decimal is not one), a (file:line) gloss;
#   codeslot  a case with no row in ## Code references (a table "| Case | Code |", one "| MC-<n> | ... |"
#             row per case), a row with no file:line, a row for an id that is no case under ## Cases;
#             a scene of ## Preparation from P2 on ("### P<n>.") with no "| P<n> | ... |" row or with
#             no file:line in it, and a row for a scene that is not there; P0, P1 and a scene whose
#             body opens with **dev-only:** need no row, and the scene is named by its heading (### P2.);
#   chain     a case that starts from another case's end state, or a file that keeps its edit history;
#   instrument **By instrument:** in a case, a ## Reading the verdict section in the file, a screen
#             recording asked of the tester in a step or in any field of a case ("record the screen",
#             "screen recording", "start recording" and their Russian forms): nothing a person walks is
#             settled by an instrument, a measurement is Validation.md's or a line of ## Not covered;
#             the same recording asked in a ## Preparation scene (S1 in brief, P2 in full) is named by
#             the scene's id;
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
#             and no field of the full case is (once per case); the marks of `field` are not such
#             a field;
#   steps     at least one numbered step "1. <action>" carries its expectation after "→", on its own
#             line or on the line under it; a table, a conditions table in **Test data:**
#             included, is never a step;
#   file      [COVERS] and a **Result:** line are there, ## Code references when there is a case, and
#             no section of the full file is: ## Run record, ## On failure, ## Troubleshooting,
#             ## Charter, ### Screen map;
#   field, compound, code, codeslot, chain, instrument and scriptable read the brief case as they
#             read a full one: the Action is the text of a numbered step before "→", the Expected the text
#             after it, and **Start:** is read where a full case's **Preconditions:** is. The scenes
#             codeslot reads are "### S<n>.", every one of them, with "| S<n> | ... |" rows.
#
# A collective pass file, <epic>/ManualChecks.md of an epic that walks its cases at the end, is a file
# with a line "[PASS] = <step>, <step>, ..." after [STYLE], in either style. Its cases sit under
# "### Session <n>. <device>" as "#### <step>/MC-<n>. <behaviour>", and every check above reads such a
# case as an ordinary one, naming it by its heading as written (#### 01/MC-1.). On top of them:
#
#   pass      a case outside a session (no session heading above it, or a ### heading under ## Cases
#             that is no session), a case id that is not <step>/MC-<n>, **Order:** first after a case
#             of its session that does not carry it, **Order:** last before a case that does not carry
#             it (once per session and kind), a case with no "<step>/MC-<n> <mark>" token in
#             **Result:**; the rows of ## Code references and the Result tokens are keyed by
#             <step>/MC-<n>, and **Result:** is required in full too (the script reads it); its
#             scenes are "### S<n>." in either style, their rows "| S<n> | ... |" with no step prefix;
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
ORDER = re.compile(r'^(first|last) \u2014 \S')
STYLE = re.compile(r'^\s*\[STYLE\]\s*=\s*\[?\s*(brief|full)\s*\]?\s*$', re.I)
NUMBERED = re.compile(r'^(\d+)\.\s+(.*)$')
PASS_LINE = re.compile(r'^\s*\[PASS\]\s*=')
SESSION = re.compile(r'^### Session (\d+)\.')
PASS_HEAD = re.compile(r'^#### (\S+?)\.(?:\s+(.*))?$')
PASS_ID = re.compile(r'^[^\s/]+/MC-\d+$')
PASS_REF = re.compile(r'^\S*MC-\S*$')

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
SCENE_REF = re.compile(r'^[SP]\d+$')
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
style = next((STYLE.match(line).group(1).lower() for line, h in rows if h is None and STYLE.match(line)), 'full')
brief = style == 'brief'
# A pass file is one with a [PASS] line; its cases are #### <step>/MC-<n>. under a ### Session heading.
is_pass = any(PASS_LINE.match(line) for line, h in rows if h is None)

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
    if is_pass and not any(line.lstrip().startswith('**Result:**') for line, h in rows if h is None):
        found.append('file: missing **Result:** (file)')

# instrument, in ## Preparation: a person walks its scenes (S-scenes in brief, P-tables in full) too.
prep = next((i for i, h in headings if h == (2, '## Preparation')), None)
if prep is not None:
    scene, hit = '## Preparation', []
    for line, h in rows[prep + 1:]:
        if h:
            if h[0] <= 2:
                break
            m = re.match(r'^#+\s+([A-Z]\d+)\b', h[1])
            scene = m.group(1) if m else re.sub(r'^#+\s*', '', h[1])
            continue
        if any(p.search(line) for p in RECORD) and scene not in hit:
            hit.append(scene)
            found.append('instrument: a screen recording in ## Preparation (%s)' % scene)

# instrument, at file level: the section an instrument's commands lived in.
if any(t.startswith('## Reading the verdict') for t in titles):
    found.append('instrument: ## Reading the verdict in the file (## Reading the verdict)')

# The cases of the file as (heading index, label, where, text after the id, session). A label is
# "MC-<n>", or "<step>/MC-<n>" in a pass file, where a case is any #### heading under ## Cases and the
# session is the ### Session heading above it (None when there is none).
recs = []
if is_pass:
    in_cases, session = False, None
    for i, h in headings:
        if h[0] <= 2:
            in_cases, session = h[1] == '## Cases', None
        elif in_cases and h[0] == 3:
            s = SESSION.match(h[1])
            session = '### Session %s.' % s.group(1) if s else None
        elif in_cases and h[0] == 4:
            m = PASS_HEAD.match(h[1])
            label = m.group(1) if m else h[1]
            recs.append((i, label, '#### %s.' % label if m else h[1], (m.group(2) or '') if m else '', session))
else:
    for i, h in headings:
        m = MC.match(h[1])
        if m:
            recs.append((i, 'MC-' + m.group(1), '### MC-%s.' % m.group(1), m.group(2), None))
where_of = {i: where for i, _, where, _, _ in recs}
old = [(i, h) for i, h in headings if OLD.match(h[1])]

# ## Code references: the table's rows, "MC-<n>" to the text of the Code cell, and a scene's "S<n>"
# or "P<n>" to its own.
refs, scene_refs, has_refs = {}, {}, False
for i, h in headings:
    if h == (2, '## Code references'):
        has_refs = True
        for line in section(i, 2):
            if not line.lstrip().startswith('|') or set(line.strip()) <= set('|-: '):
                continue
            c = cells(line)
            r = (PASS_REF if is_pass else re.compile(r'^MC-\d+$')).match(c[0])
            if r and len(c) > 1 and c[0] not in refs:
                refs[c[0]] = c[1]
            elif SCENE_REF.match(c[0]) and len(c) > 1 and c[0] not in scene_refs:
                scene_refs[c[0]] = c[1]

# The old format keeps the references in the case, as a **Code:** field.
old_code = next((i for i, _, _, _, _ in recs
                 if any('**Code:**' in line for line in section(i, 4 if is_pass else 3) if not line.lstrip().startswith('|'))), None)

if recs and not has_refs and old_code is None:
    found.append('file: missing ## Code references (file)')

if not recs and old:
    found.append('case: old format, ### <n>. headings instead of ### MC-<n>. (### %s.)' % OLD.match(old[0][1][1]).group(1))
else:
    in_cases, under_cases = False, None
    for i, h in headings:
        if h[0] <= 2:
            in_cases = h[1] == '## Cases'
            if in_cases and under_cases is None:
                under_cases = 0
        elif is_pass and h[0] == 3 and in_cases and not SESSION.match(h[1]):
            found.append('pass: a heading under ## Cases is not ### Session <n>. (%s)' % h[1])
        elif is_pass and h[0] == 4 and in_cases:
            under_cases += 1
        elif is_pass:
            continue
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
orders = []
for i, cid, where, behaviour, session in recs:
    body = section(i, 4 if is_pass else 3)
    if cid in seen:
        found.append('case: id %s is used twice (%s)' % (cid, where))
    seen.add(cid)
    if is_pass and session is None:
        found.append('pass: a case outside a session (%s)' % where)
    if is_pass and not PASS_ID.match(cid):
        found.append('pass: a case id is not <step>/MC-<n> (%s)' % where)
    if not behaviour.strip():
        found.append('case: no observable behaviour after the id (%s)' % where)
    plain = [line for line in body if not line.lstrip().startswith('|')]
    for label in (BRIEF_LABELS if brief else LABELS):
        if not any('**%s:**' % label in line for line in plain):
            found.append('case: missing **%s:** (%s)' % (label, where))
    if brief and any('**%s:**' % label in line for label in BRIEF_NOT for line in plain):
        found.append('case: a field brief does not carry (%s)' % where)
    # field: the optional marks. A missing mark is no finding; a present one has a shape.
    runner, device, order = (field(plain, label) for label in ('Runner', 'Device', 'Order'))
    if runner is not None and runner.strip() != 'agent':
        found.append('field: **Runner:** is not agent (%s)' % where)
    if device is not None and not device.strip():
        found.append('field: **Device:** is empty (%s)' % where)
    if order is not None and not ORDER.match(order.strip()):
        found.append('field: **Order:** is not first or last with a reason (%s)' % where)
    orders.append((session, order.strip().split(' ')[0] if order is not None and ORDER.match(order.strip()) else None))
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
        if cid not in refs:
            found.append('codeslot: no row in ## Code references (%s)' % where)
        elif not FILE_LINE.search(refs[cid]):
            found.append('codeslot: no file:line in ## Code references (%s)' % where)

for label in refs:
    if label not in seen:
        found.append('codeslot: row for a case not in ## Cases (%s)' % label)

# codeslot, for the scenes of ## Preparation: the starting state of a scene is grounded like a case.
# A scene is "### S<n>." in brief and in a pass file, "### P<n>." from P2 on in full; P0 and P1, the
# build and the device, and a scene whose body opens with **dev-only:** need no row.
if recs and has_refs and old_code is None:
    scene_kind = 'S' if brief or is_pass else 'P'
    scenes, present = [], set()
    if prep is not None:
        for i, h in headings:
            if i <= prep:
                continue
            if h[0] <= 2:
                break
            m = re.match(r'^###\s+(([SP])(\d+))\.', h[1])
            if h[0] != 3 or not m or m.group(2) != scene_kind:
                continue
            present.add(m.group(1))
            if scene_kind == 'P' and int(m.group(3)) < 2:
                continue
            body = trimmed(section(i, 3))
            if body and body[0].lstrip().startswith('**dev-only:**'):
                continue
            scenes.append(m.group(1))
    for sid in scenes:
        where = '### %s.' % sid
        if sid not in scene_refs:
            found.append('codeslot: no row in ## Code references (%s)' % where)
        elif not FILE_LINE.search(scene_refs[sid]):
            found.append('codeslot: no file:line in ## Code references (%s)' % where)
    for sid in scene_refs:
        if sid not in present and not (scene_kind == 'P' and sid in ('P0', 'P1')):
            found.append('codeslot: row for a scene not in ## Preparation (%s)' % sid)

if is_pass:
    # pass: inside a session the cases that need an untouched state come first, the ones that end it last.
    sessions = []
    for session, mark in orders:
        if session is not None:
            if not sessions or sessions[-1][0] != session:
                sessions.append((session, []))
            sessions[-1][1].append(mark)
    for session, marks in sessions:
        if any(m == 'first' and any(x != 'first' for x in marks[:j]) for j, m in enumerate(marks)):
            found.append('pass: Order first after a case without it (%s)' % session)
        if any(m != 'last' and 'last' in marks[:j] for j, m in enumerate(marks)):
            found.append('pass: Order last before a case without it (%s)' % session)
    # pass: the Result line carries a token for every case, keyed by <step>/MC-<n>.
    result = ' '.join(line for line, h in rows if h is None and line.lstrip().startswith('**Result:**'))
    if result:
        for _, label, where, _, _ in recs:
            if not re.search(r'(?<![\w/])' + re.escape(label) + r' (?:PASS|FAIL|BLOCKED|DROPPED|__)(?!\w)', result):
                found.append('pass: no mark for a case in **Result:** (%s)' % where)

# chain, over the whole file: a line names the heading it sits under.
where = 'file'
for n, (line, h) in enumerate(rows):
    if h:
        where = where_of.get(n, h[1])
    for p in CHAIN:
        for m in p.finditer(line):
            found.append('chain: "%s" (%s)' % (m.group(), where))

if found:
    print('\n'.join('ManualChecks.md: ' + f for f in found))
    sys.exit(1)
PY
