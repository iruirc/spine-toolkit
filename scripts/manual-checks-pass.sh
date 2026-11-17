#!/usr/bin/env bash
set -euo pipefail

# The script side of a collective manual-checks pass: an epic's steps keep their own ManualChecks.md,
# and the pass file at the epic's root, ManualChecks.md, walks the cases no earlier walk marked. Three
# commands, all printing JSON or one line on stdout:
#
#   collect    the cases of the steps that carry no mark yet, in the order of steps and ids:
#              {"cases": [{"step", "dir", "id", "title", "style", "runner", "device", "order"}]}.
#              A step's id is its .step folder's name up to the first "-" (06-editor.step is 06;
#              a folder with no "-" is its name without .step); when two or more folders resolve to
#              the same id (address-form.step and address-list.step are both address), each of them
#              takes its full name without .step (address-form, address-list). A step with no
#              ManualChecks.md is skipped, and so is a step whose own Task.md sets
#              [MANUAL_CHECKS_PASS] = per-step (a bracketed or a bare value, in any letter case,
#              with an optional trailing "# ..." comment): it walks its own cases and is not
#              collected, so marks and writeback never see them either. A brief case is open while its token in **Result:** reads "MC-<n> __" or is
#              missing; a full case is open while its **Status:** line is still the three empty boxes.
#              runner, device and order are the optional marks of a case as written, or null.
#   marks      the marks of the pass: {"pass_file": bool, "marks": [{"case": "<step>/MC-<n>",
#              "mark", "reason", "by"}], "unmarked": ["<step>/MC-<n>"], "missing": ["<step>/MC-<n>"]}.
#              They come from the
#              **Result:** line of <epic>/ManualChecks.md ("<step>/MC-<n> PASS", "... FAIL (<why>)",
#              "... BLOCKED (<why>)", "... DROPPED (<why>)", "... __" for none yet) and from the
#              table "## Agent verdicts" of <epic>/Validation.md ("| Case | Mark | Evidence |"). The
#              Mark cell of a verdict may carry "(<why>)"; without it a FAIL, BLOCKED or DROPPED
#              takes its Evidence as the reason. A mark in the Result line wins over a verdict of
#              the same case. A case of the pass with no mark, or still "__", is unmarked. So is a
#              case `collect` lists now that the pass has neither a token in **Result:** nor a row
#              in the verdicts (a case folded into another one, say, or never written): the pass
#              file holds it nowhere, and it is listed in "missing" as well. A verdict row whose
#              Case cell is no <step>/MC-<n> (a placeholder "—") is ignored. No pass file means
#              pass_file false and the agent verdicts alone as the marks (by "agent"); a collected
#              case with no verdict is unmarked and missing, since nobody walked it.
#   writeback  writes each mark into the file of its step and prints "writeback: <N> mark(s) in
#              <M> file(s)". In a brief step the token "MC-<n> __" becomes "MC-<n> <MARK>" (with
#              " (<why>)" when there is a reason; "(" and ")" in a reason are written as "[" and "]",
#              in a full step too) and the rest of the **Result:** line, the prose
#              after " — " included, stays. In a full step the **Status:** line of the case becomes
#              "**Status:** <MARK> — reason: <why, or —>". It writes nothing and exits 1 when a case
#              of the pass is unmarked ("writeback: unmarked: <ids>") or a mark has no place in any
#              step file ("writeback: no place for: <ids>"). A case already written is left
#              alone, so a second run prints "writeback: 0 mark(s) in 0 file(s)". With no pass file
#              it writes the agent verdicts the same way.
#
# The style of a step file is read from its [STYLE] line as lint-manual-checks.sh reads it: brief
# or full in any letter case, and no line means full.
#
# Usage: scripts/manual-checks-pass.sh collect|marks|writeback <epic_dir>
# Exit:  0 done; 1 writeback refused, with the reason on stderr; 2 usage.

usage() { echo "usage: $0 collect|marks|writeback <epic_dir>" >&2; exit 2; }
[ "$#" -eq 2 ] || usage
case "$1" in
  collect|marks|writeback) ;;
  *) usage ;;
esac
[ -d "$2" ] || { echo "error: not a directory: $2" >&2; exit 2; }

python3 - "$@" <<'PY'
import json, os, re, sys

command, epic = sys.argv[1], sys.argv[2]

OWN_PASS = re.compile(r'^\s*\[MANUAL_CHECKS_PASS\]\s*=\s*\[?\s*per-step\s*\]?\s*(#.*)?$', re.I)
STYLE = re.compile(r'^\s*\[STYLE\]\s*=\s*\[?\s*(brief|full)\s*\]?\s*$', re.I)
FENCE = re.compile(r'^\s*(`{3,}|~{3,})')
HEADING = re.compile(r'^(#{1,6})\s+(.*?)\s*#*\s*$')
MC = re.compile(r'^### MC-(\d+)\.\s*(.*)$')
PASS_CASE = re.compile(r'^#### ([^\s/]+)/MC-(\d+)\.')
MARKS = ('PASS', 'FAIL', 'BLOCKED', 'DROPPED')
# One token of a Result line: an id, then a mark or "__"; a reason in parentheses follows a mark.
TOKEN = re.compile(r'(?:([^\s/·]+)/)?MC-(\d+) (PASS|FAIL|BLOCKED|DROPPED|__)')
EMPTY_STATUS = re.compile(r'^\*\*Status:\*\*\s*☐\s*PASS\s*☐\s*FAIL\s*☐\s*BLOCKED\b')
LABEL = re.compile(r'^\s*\*\*([^*\n]+):\*\*(.*)$')
CELL_SPLIT = re.compile(r'(?<!\\)\|')
DASH = '—'
MIDDOT = '·'


def natural(text):
    return [int(p) if p.isdigit() else p for p in re.split(r'(\d+)', text)]


def read(path):
    with open(path, encoding='utf-8', errors='replace', newline='') as fh:
        return fh.read().split('\n')


def scan(lines):
    """Each line with the heading it is (level, text) or None; a line in a fence is no heading."""
    out, fence = [], None
    for line in lines:
        bare = line.rstrip('\r')
        m = FENCE.match(bare)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not bare.strip()[len(m.group(1)):]:
                fence = None
            out.append((line, None))
            continue
        if m:
            fence = m.group(1)
            out.append((line, None))
            continue
        h = HEADING.match(bare)
        out.append((line, (len(h.group(1)), bare.strip()) if h else None))
    return out


def style_of(rows):
    for line, h in rows:
        if h is None:
            m = STYLE.match(line.rstrip('\r'))
            if m:
                return m.group(1).lower()
    return 'full'


def balanced(text, start):
    """The text in the parentheses that open at start, nested ones kept, and the index after them."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == '(':
            depth += 1
        elif text[i] == ')':
            depth -= 1
            if depth == 0:
                return text[start + 1:i].strip(), i + 1
    return None, start


def result_tokens(line):
    """The tokens of a **Result:** line, left to right, up to the first thing that is no token: the
    prose after " — " is never read. Each is (step, n, mark, reason, start, end) over the line."""
    tag = '**Result:**'
    pos = line.index(tag) + len(tag)
    out = []
    while True:
        while pos < len(line) and line[pos] == ' ':
            pos += 1
        m = TOKEN.match(line, pos)
        if not m:
            break
        end, reason = m.end(), None
        if m.group(3) in MARKS and line.startswith(' (', end):
            reason, after = balanced(line, end + 1)
            if reason is not None:
                end = after
        out.append((m.group(1), m.group(2), m.group(3), reason, m.start(), end))
        pos = end
        if line.startswith(' ' + MIDDOT, pos):
            pos += 2
        else:
            break
    return out


def result_lines(rows):
    return [(i, line) for i, (line, h) in enumerate(rows) if h is None and line.lstrip().startswith('**Result:**')]


def steps_of(epic):
    """The step folders: (step id, folder name), in the order of their names. The id is the short
    prefix of the stem; when two or more folders share a prefix, each of them takes its full stem."""
    found = []
    for name in sorted(os.listdir(epic), key=natural):
        if name.endswith('.step') and os.path.isdir(os.path.join(epic, name)):
            stem = name[:-len('.step')]
            found.append((stem.split('-', 1)[0] if '-' in stem else stem, stem, name))
    count = {}
    for short, _, _ in found:
        count[short] = count.get(short, 0) + 1
    return [(short if count[short] == 1 else stem, name) for short, stem, name in found]


def section(rows, start, level):
    out = []
    for i in range(start + 1, len(rows)):
        h = rows[i][1]
        if h and h[0] <= level:
            break
        out.append(i)
    return out


def case_field(rows, idxs, label):
    for i in idxs:
        line = rows[i][0].rstrip('\r')
        m = LABEL.match(line)
        if m and m.group(1) == label and not line.lstrip().startswith('|') and rows[i][1] is None:
            value = m.group(2).strip()
            return value or None
    return None


def step_cases(rows):
    """The cases of a step file: (n, title, body line indexes, heading index)."""
    out = []
    for i, (line, h) in enumerate(rows):
        m = h and h[0] == 3 and MC.match(h[1])
        if m:
            out.append((int(m.group(1)), m.group(2).strip(), section(rows, i, 3), i))
    return out


def open_state(rows, style, n, body):
    """'open' while the case carries no mark, 'done' when it does; for a brief case the token too."""
    if style == 'brief':
        for i, line in result_lines(rows):
            for step, tn, mark, reason, s, e in result_tokens(line):
                if step is None and int(tn) == n:
                    return mark == '__'
        return True
    for i in body:
        line = rows[i][0].rstrip('\r')
        if line.startswith('**Status:**') and rows[i][1] is None:
            return bool(EMPTY_STATUS.match(line))
    return True


def load_steps(epic):
    """Per step with a ManualChecks.md: id, folder, path, rows, style."""
    steps = []
    for sid, name in steps_of(epic):
        path = os.path.join(epic, name, 'ManualChecks.md')
        if os.path.isfile(path):
            rows = scan(read(path))
            steps.append({'id': sid, 'dir': name, 'path': path, 'rows': rows, 'style': style_of(rows)})
    return steps


def cells(line):
    s = line.strip()
    s = s[1:] if s.startswith('|') else s
    s = s[:-1] if s.endswith('|') and not s.endswith('\\|') else s
    return [c.strip().strip('`').strip() for c in CELL_SPLIT.split(s)]


def agent_verdicts(epic):
    path = os.path.join(epic, 'Validation.md')
    out = []
    if not os.path.isfile(path):
        return out
    rows = scan(read(path))
    for i, (line, h) in enumerate(rows):
        if h == (2, '## Agent verdicts'):
            for j in section(rows, i, 2):
                text = rows[j][0].rstrip('\r')
                if not text.lstrip().startswith('|'):
                    continue
                c = cells(text)
                if len(c) < 2 or not re.match(r'^[^\s/]+/MC-\d+$', c[0]):
                    continue
                m = re.match(r'^(PASS|FAIL|BLOCKED|DROPPED)\b\s*(.*)$', c[1])
                if not m:
                    continue
                reason = None
                if m.group(2).startswith('('):
                    reason, _ = balanced(m.group(2), 0)
                if reason is None and m.group(1) != 'PASS' and len(c) > 2 and c[2] not in ('', DASH, '-'):
                    reason = c[2]
                out.append((c[0], m.group(1), reason))
            break
    return out


def case_order(cid):
    return (natural(cid.split('/')[0]), natural(cid.split('/')[1]))


def pass_marks(epic):
    """(pass_file, marks, unmarked, missing) of the pass file and the agent verdicts. missing is the
    cases `collect` lists that the pass file has no token, no heading and no verdict for; they are
    unmarked too, so a case dropped from the pass cannot pass for done."""
    path = os.path.join(epic, 'ManualChecks.md')
    expected = ['%s/%s' % (c['step'], c['id']) for c in collected(epic)]
    if not os.path.isfile(path):
        # No case was left for a person, so no pass file: the agent's verdicts are the marks, and a
        # collected case with no verdict of the agent is unmarked.
        verdicts = {}
        for cid, mark, reason in agent_verdicts(epic):
            verdicts.setdefault(cid, (mark, reason))
        ids = sorted(verdicts, key=case_order)
        lost = [c for c in expected if c not in verdicts]
        return False, [{'case': c, 'mark': verdicts[c][0], 'reason': verdicts[c][1], 'by': 'agent'} for c in ids], lost, lost
    rows = scan(read(path))
    known, marks, open_ids = {}, {}, []
    for line, h in rows:
        m = h and h[0] == 4 and PASS_CASE.match(h[1])
        if m:
            known['%s/MC-%s' % (m.group(1), m.group(2))] = True
    for i, line in result_lines(rows):
        for step, n, mark, reason, s, e in result_tokens(line):
            if step is None:
                continue
            cid = '%s/MC-%s' % (step, n)
            known[cid] = True
            if mark == '__':
                open_ids.append(cid)
            elif cid not in marks:
                marks[cid] = (mark, reason, 'person')
    for cid, mark, reason in agent_verdicts(epic):
        if cid not in marks:
            marks[cid] = (mark, reason, 'agent')
    missing = [c for c in expected if c not in known and c not in marks]
    ids = sorted(set(known) | set(marks) | set(missing), key=case_order)
    listed = [{'case': c, 'mark': marks[c][0], 'reason': marks[c][1], 'by': marks[c][2]} for c in ids if c in marks]
    unmarked = [c for c in ids if c not in marks]
    return True, listed, unmarked, sorted(missing, key=case_order)


def out(value):
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stdout.write(json.dumps(value, ensure_ascii=False) + '\n')


def walks_itself(task_md):
    """True when the step's own Task.md sets [MANUAL_CHECKS_PASS] = per-step (a bug step Done created):
    it walks its cases inside the step, so the pass does not collect them."""
    if not os.path.isfile(task_md):
        return False
    return any(OWN_PASS.match(line.rstrip('\r')) for line in read(task_md))


def collected(epic):
    """The cases `collect` lists, in the order of steps and ids."""
    cases = []
    for st in load_steps(epic):
        if walks_itself(os.path.join(epic, st['dir'], 'Task.md')):
            continue
        rows = st['rows']
        for n, title, body, _ in sorted(step_cases(rows), key=lambda c: c[0]):
            if not open_state(rows, st['style'], n, body):
                continue
            cases.append({'step': st['id'], 'dir': st['dir'], 'id': 'MC-%d' % n, 'title': title,
                          'style': st['style'], 'runner': case_field(rows, body, 'Runner'),
                          'device': case_field(rows, body, 'Device'), 'order': case_field(rows, body, 'Order')})
    return cases


if command == 'collect':
    out({'cases': collected(epic)})

elif command == 'marks':
    has_pass, marks, unmarked, missing = pass_marks(epic)
    out({'pass_file': has_pass, 'marks': marks, 'unmarked': unmarked, 'missing': missing})

else:
    has_pass, marks, unmarked, _ = pass_marks(epic)
    if unmarked:
        sys.stderr.write('writeback: unmarked: %s\n' % ', '.join(unmarked))
        sys.exit(1)
    steps = {}
    for st in load_steps(epic):
        steps.setdefault(st['id'], st)
    edits, no_place, written = {}, [], 0
    for mk in marks:
        sid, mc = mk['case'].split('/')
        n = int(mc[3:])
        # A reason stands inside "( ... )" in a brief Result line, and an unbalanced parenthesis would
        # cut it short and hide every token after it; both styles get the same text, with square brackets.
        mk['reason'] = mk['reason'].replace('(', '[').replace(')', ']') if mk['reason'] else mk['reason']
        st = steps.get(sid)
        case = next((c for c in step_cases(st['rows']) if c[0] == n), None) if st else None
        if not case:
            no_place.append(mk['case'])
            continue
        rows, body = st['rows'], case[2]
        if st['style'] == 'brief':
            spot = None
            for i, line in result_lines(rows):
                for step, tn, mark, reason, s, e in result_tokens(line):
                    if step is None and int(tn) == n:
                        spot = (i, mark, s, e)
            if spot is None:
                no_place.append(mk['case'])
                continue
            i, mark, s, e = spot
            if mark != '__':
                continue
            text = 'MC-%d %s' % (n, mk['mark']) + (' (%s)' % mk['reason'] if mk['reason'] else '')
            edits.setdefault(st['path'], []).append((i, s, e, text))
        else:
            spot = next((i for i in body if rows[i][1] is None and rows[i][0].startswith('**Status:**')), None)
            if spot is None:
                no_place.append(mk['case'])
                continue
            line = rows[spot][0]
            bare = line.rstrip('\r')
            if not EMPTY_STATUS.match(bare):
                continue
            text = '**Status:** %s %s reason: %s' % (mk['mark'], DASH, mk['reason'] or DASH)
            edits.setdefault(st['path'], []).append((spot, 0, len(bare), text))
    if no_place:
        sys.stderr.write('writeback: no place for: %s\n' % ', '.join(no_place))
        sys.exit(1)
    files = 0
    for path, items in edits.items():
        lines = read(path)
        for i, s, e, text in sorted(items, key=lambda it: (it[0], -it[1])):
            lines[i] = lines[i][:s] + text + lines[i][e:]
        with open(path, 'w', encoding='utf-8', newline='') as fh:
            fh.write('\n'.join(lines))
        files += 1
        written += len(items)
    print('writeback: %d mark(s) in %d file(s)' % (written, files))
PY
