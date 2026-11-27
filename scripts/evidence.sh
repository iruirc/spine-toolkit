#!/usr/bin/env bash
# Keeps tool output in a task folder without committing what it printed: the raw log goes to a raw/
# folder git never sees, and a scrubbed excerpt of it — the lines the caller asks for and the tail —
# is what the task commits. The redaction rules live here, in one place.
#
# Usage: scripts/evidence.sh keep <log> <evidence dir> [--name <name>] [--match <regex>]…
#          <evidence dir> lies inside a task folder (one holding Task.md). Writes <evidence dir>/raw/<name>.log,
#          a byte copy of <log>, raw/.gitignore holding `*` when it is missing, and the excerpt
#          <evidence dir>/<name>.log: the header line, the lines a --match finds (above the tail), `# tail`
#          and the last 20 lines, all after redaction. <name> defaults to <log>'s base name without .log.
#          Prints `kept <excerpt path relative to the task folder> redacted=<n>`.
#          Project patterns: the `## Redact` block of the project config, one ``- `<regex>` `` per line.
# Exit: 0, a line matched or not (none matched: one stderr line says so). 2: usage, no task folder above
#       <evidence dir>, no project config above it, or a `## Redact` line that does not parse.
set -uo pipefail

[ $# -ge 1 ] || { sed -n '5,14p' "$0" >&2; exit 2; }
exec python3 - "$(cd -- "$(dirname -- "$0")" && pwd)" "$@" <<'PY'
import json, os, re, subprocess, sys

HERE = sys.argv[1]
ARGS = sys.argv[2:]
HEADER = "# evidence excerpt v1 — raw: raw/%s.log"
TAIL = 20
MASK = "***"

# The key names a key=value, key: value or JSON pair is redacted under; the key may be part of a
# longer name (access_token, clientSecret). The name around the key is bounded, so a line of
# 100 000 word characters costs a bounded scan per position, not a quadratic one.
KEYS = r"(?:token|secret|passw(?:or)?d|api[_-]?key|auth|credential|private[_-]?key|session|cookie)"
PEM = re.compile(r"(-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----)(.*?)(-----END [A-Z0-9 ]*PRIVATE KEY-----|\Z)", re.S)
# (pattern, the group that holds the value): the value alone becomes ***, the rest of the match stays.
RULES = [
    (re.compile(r"(?i)\bAuthorization:[ \t]*(?:(?:Bearer|Basic)[ \t]+)?([^\s\"',]+)"), 1),
    (re.compile(r"(?i)\bX-Api-Key:[ \t]*([^\s\"',]+)"), 1),
    (re.compile(r"(?i)\b(?:Set-)?Cookie:[ \t]*([^\"'\r\n]+)"), 1),
    (re.compile(r"://[^\s/:@]+:([^\s/@]+)@"), 1),
    (re.compile(r"(?i)\"?[\w.-]{0,64}?" + KEYS + r"[\w.-]{0,64}\"?[ \t]*[:=][ \t]*"
                r"(?:\"([^\"\r\n]*)\"|'([^'\r\n]*)'|([^\s\"'&;,]+))"), (1, 2, 3)),
]
# Whole tokens: the match itself becomes ***.
TOKENS = [
    re.compile(r"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"(?<![A-Za-z0-9_-])(?:ghp_|gho_|ghs_|github_pat_)[A-Za-z0-9_]+"),
    re.compile(r"(?<![A-Za-z0-9_-])sk-[A-Za-z0-9_-]{8,}"),
    re.compile(r"(?<![A-Za-z0-9_-])xox[bpas]-[A-Za-z0-9-]+"),
    re.compile(r"(?<![A-Za-z0-9_-])AIza[0-9A-Za-z_-]{8,}"),
]
# An unquoted value that is only the scheme word of an Authorization header the rule above already redacted.
SCHEMES = ("bearer", "basic")


def usage(msg):
    print("evidence: " + msg, file=sys.stderr)
    sys.exit(2)


def redact(text, extra):
    """The whole text with every secret value replaced by ***, and how many values were replaced.
    A private key block keeps its BEGIN and END lines and each of its body lines becomes ***."""
    count = 0

    def pem(m):
        nonlocal count
        count += 1
        body = re.sub(r"[^\r\n]+", MASK, m.group(2))
        return m.group(1) + body + m.group(3)
    text = PEM.sub(pem, text)

    def whole(m):
        nonlocal count
        if m.group(0) == MASK:
            return m.group(0)
        count += 1
        return MASK
    for p in extra:
        text = p.sub(whole, text)

    def value(groups):
        def sub(m):
            nonlocal count
            g = next((g for g in groups if m.group(g) is not None), None)
            v = m.group(g) if g is not None else ""
            if not v or v == MASK or v.lower() in SCHEMES:
                return m.group(0)
            count += 1
            s, e = m.start(g) - m.start(0), m.end(g) - m.start(0)
            return m.group(0)[:s] + MASK + m.group(0)[e:]
        return sub
    for p, g in RULES:
        text = p.sub(value(g if isinstance(g, tuple) else (g,)), text)
    for p in TOKENS:
        text = p.sub(whole, text)
    return text, count


def task_dir_of(path):
    """The nearest directory at or above path holding Task.md, or None."""
    d = os.path.abspath(path)
    while True:
        if os.path.isfile(os.path.join(d, "Task.md")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def where(task_dir, entry):
    """`<config> line <n>` for the ## Redact line holding entry, for the message that stops on it. The
    config's path is resolve-settings.sh's answer: the lookup lives there alone."""
    run = subprocess.run([os.path.join(HERE, "resolve-settings.sh"), "json", task_dir],
                         capture_output=True, text=True)
    try:
        cfg = json.loads(run.stdout)["project_config"]
        inside = False
        with open(cfg, encoding="utf-8") as fh:
            for n, line in enumerate(fh, 1):
                if line.startswith("## "):
                    inside = line.strip() == "## Redact"
                elif inside and line.strip() == entry:
                    return "%s line %d" % (cfg, n)
    except (OSError, ValueError, KeyError, TypeError):
        pass
    return "## Redact"


def project_patterns(task_dir):
    """The project's own patterns from the ## Redact block. A line that is not ``- `<regex>` ``, a regex
    that does not compile, or one that matches the empty string stops the run with its line."""
    run = subprocess.run([os.path.join(HERE, "resolve-settings.sh"), "raw", task_dir, "Redact"],
                         capture_output=True, text=True)
    sys.stderr.write(run.stderr)
    if run.returncode != 0:
        sys.exit(2)
    out = []
    for entry in run.stdout.splitlines():
        m = re.fullmatch(r"- `(.+)`", entry.strip())
        why = None if m else "not a - `<regex>` line"
        if m:
            try:
                p = re.compile(m.group(1))
                if p.fullmatch(""):
                    why = "matches the empty string"
                out.append(p)
            except re.error as e:
                why = str(e)
        if why:
            usage("%s: %s (%s)" % (where(task_dir, entry.strip()), entry.strip(), why))
    return out


def keep(args):
    pos, name, matches = [], None, []
    while args:
        a = args.pop(0)
        if a in ("--name", "--match"):
            if not args:
                usage(a + " needs a value")
            v = args.pop(0)
            if a == "--name":
                name = v
            else:
                try:
                    matches.append(re.compile(v))
                except re.error as e:
                    usage("--match %s: %s" % (v, e))
        elif a.startswith("--"):
            usage("unknown option " + a)
        else:
            pos.append(a)
    if len(pos) != 2:
        usage("keep <log> <evidence dir> [--name <name>] [--match <regex>]...")
    log, evidence = pos
    if not os.path.isfile(log):
        usage("no log at " + log)
    if name is None:
        name = os.path.basename(log)
        name = name[:-4] if name.endswith(".log") else name
    if not name or name in (".", "..") or "/" in name:
        usage("not a name: " + name)
    evidence = os.path.abspath(evidence)
    task = task_dir_of(evidence)
    if task is None or task == evidence:
        usage("%s is not inside a task folder (no Task.md above it)" % pos[1])
    extra = project_patterns(task)

    with open(log, "rb") as fh:
        data = fh.read()
    raw_dir = os.path.join(evidence, "raw")
    os.makedirs(raw_dir, exist_ok=True)
    raw = os.path.join(raw_dir, name + ".log")
    if not (os.path.exists(raw) and os.path.samefile(log, raw)):
        with open(raw, "wb") as fh:
            fh.write(data)
    ignore = os.path.join(raw_dir, ".gitignore")
    if not os.path.exists(ignore):
        with open(ignore, "w", encoding="utf-8") as fh:
            fh.write("*\n")

    text, count = redact(data.decode("utf-8", errors="surrogateescape"), extra)
    lines = [l[:-1] if l.endswith("\r") else l for l in text.split("\n")]
    if lines and lines[-1] == "":
        lines.pop()
    cut = max(len(lines) - TAIL, 0)
    matched = [i for i, l in enumerate(lines) if any(p.search(l) for p in matches)]
    if not matched:
        print("evidence: no line matched --match in " + log, file=sys.stderr)
    body = [HEADER % name] + [lines[i] for i in matched if i < cut] + ["# tail"] + lines[cut:]
    excerpt = os.path.join(evidence, name + ".log")
    with open(excerpt, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write("\n".join(body) + "\n")
    print("kept %s redacted=%d" % (os.path.relpath(excerpt, task), count))


if not ARGS:
    usage("keep <log> <evidence dir> [--name <name>] [--match <regex>]...")
cmd = ARGS.pop(0)
if cmd == "keep":
    keep(ARGS)
else:
    usage("unknown subcommand " + cmd)
PY
