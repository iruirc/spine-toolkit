#!/usr/bin/env bash
# Collects the open items of a research-style artifact's question sections, each one whole.
# How the orchestrator uses it: skills/orchestrator/SKILL.md → Open-questions inline.
#
# Usage: scripts/open-questions.sh <artifact>…
# Prints a JSON array of {artifact, section, id, text, recommended}. Exit 0; 2: usage, missing file.
# What looks like an open question the gate cannot read goes to stderr, one line per place:
# open-questions: <artifact>:<line>: <message>.
set -uo pipefail

[ $# -ge 1 ] || { echo "usage: open-questions.sh <artifact>…" >&2; exit 2; }
exec python3 - "$@" <<'PY'
import json, re, sys

SECTIONS = {"designer questions", "backend questions", "known unknowns", "open questions"}
HEADING = re.compile(r"^#{1,6}\s+(.*?)\s*#*\s*$")
ITEM = re.compile(r"^(\s*)(?:[-*]|\d+[.)])\s+(.*)$")
ID = re.compile(r"^(\[?[A-Za-z]{1,3}\d+\]?)(?=[\s:.,)]|$)")
CLOSED = re.compile(r"^\[(RESOLVED|DEFERRED)\]")
MARK = re.compile(r"\s*\(recommended\)", re.I)
BOLD_ID = re.compile(r"^\*\*\[?[A-Za-z]{1,3}\d+\]?\.")
LOG = "open questions log"
OUTSIDE = 'an open question outside a section the gate reads — expected a heading beginning "Open Questions"'
PARAGRAPH = 'a question written as a paragraph — expected a list item "- <ID>. …"'
FENCE = re.compile(r"^\s*(```|~~~)")


def indent(line):
    return len(line) - len(line.lstrip(" "))


def done(cur):
    while not cur["lines"][-1].strip():
        cur["lines"].pop()
    return cur


def read_section(title):
    """The heading's title when the gate reads that section, else None."""
    t = title.lower()
    if t.startswith(LOG):
        return None
    for s in SECTIONS:
        if t == s or (t.startswith(s) and not t[len(s)].isalpha()):
            return title
    return None


def items(path, lines, warns):
    section, base, cur, fence = None, None, None, None
    # Where the section outside the gate starts, whether it was reported, and whether it is the log.
    head_at, warned, log = None, False, False
    for n, line in enumerate(lines, 1):
        line = line.rstrip("\n").expandtabs(4)
        if fence:
            if cur:
                cur["lines"].append(line)
            if line.strip().startswith(fence):
                fence = None
            continue
        f = FENCE.match(line)
        h = None if f else HEADING.match(line)
        m = None if f else ITEM.match(line)
        if cur and (h or (line.strip() and indent(line) <= base)):
            yield done(cur)
            cur = None
        if h:
            section = read_section(h.group(1))
            base, head_at, warned = None, n, False
            log = h.group(1).lower().startswith(LOG)
            continue
        if f:
            fence = f.group(1)
        else:
            bold = BOLD_ID.match(line.strip())
            if section is None and not log and not warned and (bold or MARK.search(line)):
                warns.append((head_at or n, OUTSIDE))
                warned = True
            elif section is not None and bold and not m:
                warns.append((n, PARAGRAPH))
        if section is None:
            continue
        if m and (base is None or len(m.group(1)) <= base):
            base = len(m.group(1))
            cur = {"artifact": path, "section": section, "head": m.group(2), "lines": [line]}
        elif cur:
            cur["lines"].append(line)
    if cur:
        yield done(cur)


def record(it):
    head = it["head"]
    token = ID.match(head[2:] if head.startswith("**") else head)
    subs = [m.group(2) for m in map(ITEM.match, it["lines"][1:]) if m and MARK.search(m.group(2))]
    base = indent(it["lines"][0])
    return {
        "artifact": it["artifact"],
        "section": it["section"],
        "id": token.group(1) if token else head[:80],
        "text": "\n".join(l[base:] for l in it["lines"]),
        "recommended": " ".join(MARK.sub("", subs[0]).split()) if len(subs) == 1 else None,
    }


out, warnings = [], []
for path in sys.argv[1:]:
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()
    except FileNotFoundError:
        print("open-questions: no such file: " + path, file=sys.stderr)
        sys.exit(2)
    warns = []
    out += [record(it) for it in items(path, lines, warns) if not CLOSED.match(it["head"])]
    warnings += ["open-questions: %s:%d: %s" % (path, n, msg) for n, msg in sorted(warns)]
print(json.dumps(out, ensure_ascii=False))
for w in warnings:
    print(w, file=sys.stderr)
PY
