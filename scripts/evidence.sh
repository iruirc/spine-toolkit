#!/usr/bin/env bash
# Keeps tool output in a task folder without committing what it printed: the raw log goes to a raw/
# folder git never sees, and a scrubbed excerpt of it — the lines the caller asks for and the tail —
# is what the task commits. The redaction rules live here, in one place.
#
# Usage: scripts/evidence.sh keep <log> <evidence dir> [--name <name>] [--match <regex>]…
#          <evidence dir> lies inside a task folder (one holding Task.md). Writes <evidence dir>/raw/<name>.log,
#          a byte copy of <log>, raw/.gitignore holding `*` when it is missing, and the excerpt
#          <evidence dir>/<name>.log: the header line, the lines a --match finds (above the tail), `# tail`
#          and the last 20 lines, all after redaction. <name> defaults to <log>'s base name; a trailing .log
#          is dropped from either.
#          Prints `kept <excerpt path relative to the task folder> redacted=<n>`.
#          Project patterns: the `## Redact` block of the project config, one ``- `<regex>` `` per line.
#        scripts/evidence.sh raw <evidence dir>
#          <evidence dir> lies inside a task folder. Makes <evidence dir>/raw/ and raw/.gitignore holding `*`
#          when they are missing, and prints the absolute path of raw/: a screenshot is saved there, never
#          into a raw/ made by hand, which git sees until a .gitignore is in it.
#        scripts/evidence.sh keep-image <image> <evidence dir>
#          <image> is a .png, .jpg, .jpeg, .gif or .webp file in <evidence dir>/raw/ that was viewed and holds
#          no secret. Moves it to <evidence dir>/ and lists it in <evidence dir>/kept.txt as
#          `<sha1>  <file name>`, in place of an older line for the same name. Prints
#          `kept <image path relative to the task folder> sha1=<sha1>`.
#        scripts/evidence.sh check <task dir>
#          Walks phase-evidence/ and validation-evidence/ of <task dir> and of its *.step/ folders at any
#          depth, raw/ folders skipped, and prints `evidence path=<path relative to task dir> reason=<reason>`
#          for each file that must not be committed, in path order. unmarked: a .log without the excerpt
#          header. secret: an excerpt the rules still find a value in. unlisted: an image not in its folder's
#          kept.txt. changed: an image whose sha1 is not the listed one. other: any file but kept.txt and .md.
# Exit: 0: done; for check, nothing found. 1: check found a file. 2: usage, no task folder above
#       <evidence dir>, an image not in its raw/, no project config, a `## Redact` line that does not parse,
#       a file that cannot be read or moved, or any other error.
set -uo pipefail

exec python3 - "$(cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")" "$@" <<'PY'
import hashlib, json, os, re, subprocess, sys

SCRIPT = sys.argv[1]
HERE = os.path.dirname(SCRIPT)
ARGS = sys.argv[2:]
HEADER = "# evidence excerpt v1 — raw: raw/%s.log"
TAIL = 20
TAIL_LINE = "# tail"
MASK = "***"

# The key names a key=value, key: value or JSON pair is redacted under; the key may be part of a
# longer name (access_token, clientSecret). The name around the key is bounded, so a line of
# 100 000 word characters costs a bounded scan per position, not a quadratic one.
KEYS = r"(?:token|secret|passw(?:or)?d|api[_-]?key|auth|credential|private[_-]?key|session|cookie)"
# The line keep writes under a key's BEGIN line when the excerpt holds neither its body nor its END line:
# in an excerpt it closes the block, so the lines after it are read as the excerpt's own, not as key body.
# In a raw log it is a line like any other: a log that prints it inside a key block does not end the block.
CUT = "# private key cut: its body and END line are not in this excerpt"
BEGIN = re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----")
END = re.compile(r"-----END [A-Z0-9 ]*PRIVATE KEY-----")
PEM_RAW = re.compile(r"(%s)(.*?)(%s|\Z)" % (BEGIN.pattern, END.pattern), re.S)
PEM_EXCERPT = re.compile(r"(%s)(.*?)(%s|(?<=\n)%s(?=\r?\n|\Z)|\Z)" % (BEGIN.pattern, END.pattern, re.escape(CUT)),
                         re.S)
# (pattern, the group that holds the value): the value alone becomes ***, the rest of the match stays.
# An Authorization header keeps its scheme word when it is a known one and loses the rest of its value up
# to the end of the line or a quote that closes a string around it; a ="…" parameter (Digest) is taken
# whole. A first word that is no known scheme may be the credential itself: everything after the colon goes.
# A key=value, key: value or key => value pair takes its key in double quotes, single quotes or none; an
# unquoted value that is a known scheme word followed by a token keeps the word and loses the token.
SCHEMES = (r"(?:Bearer|Basic|Digest|Negotiate|NTLM|Token|AWS4-HMAC-SHA256|HOBA|Mutual|SCRAM-SHA-1|"
           r"SCRAM-SHA-256|DPoP|GNAP)")
RULES = [
    (re.compile(r"(?i)\bAuthorization:[ \t]*(?:" + SCHEMES + r"[ \t]+)?((?:=\"[^\"\r\n]*\"|[^\s\"'])(?:=\"[^\"\r\n]*\"|[^\"'\r\n])*)"), 1),
    (re.compile(r"(?i)\bX-Api-Key:[ \t]*([^\s\"',]+)"), 1),
    (re.compile(r"(?i)\b(?:Set-)?Cookie:[ \t]*([^\"'\r\n]+)"), 1),
    (re.compile(r"://[^\s/:@]+:([^\s/@]+)@"), 1),
    (re.compile(r"(?i)[\"']?[\w.-]{0,64}?" + KEYS + r"[\w.-]{0,64}[\"']?[ \t]*(?:=>|[:=])[ \t]*"
                r"(?:\"((?:[^\"\\\r\n]|\\.)*)\"|'((?:[^'\\\r\n]|\\.)*)'|(?:" + SCHEMES + r"[ \t]+)?([^\s\"'&;,]+))"),
     (1, 2, 3)),
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
# The scheme word of an Authorization header whose credential the first rule already made ***: a key=value
# read of the same header must leave it.
SCHEME = re.compile(SCHEMES, re.I)
AFTER_SCHEME = re.compile(r"[ \t]+\*\*\*")
# Every rule and token above needs one of these, lowercased, on its line: a line with none skips them all.
# A superset is fine; a cue missing here is a secret form that is never redacted.
CUES = ("token", "secret", "passw", "api", "auth", "credential", "private", "session", "cookie", "://",
        "eyj", "akia", "gh", "github_pat_", "sk-", "xox", "aiza")
IMAGES = (".png", ".jpg", ".jpeg", ".gif", ".webp")
EVIDENCE = ("phase-evidence", "validation-evidence")
MARK = re.compile(r"# evidence excerpt v1 — raw: raw/.+\.log")
KEPT = "kept.txt"
KEPT_LINE = re.compile(r"([0-9a-f]{40})  (.+)")


def usage_text():
    """The header's usage: from the `# Usage:` line to the end of the `# Exit:` block, without the `#`."""
    out, exit_seen = [], False
    with open(SCRIPT, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not out and not line.startswith("# Usage:"):
                continue
            if exit_seen and not line.startswith("#  "):
                break
            exit_seen = exit_seen or line.startswith("# Exit:")
            out.append(line[2:])
    return "\n".join(out)


def usage(msg, full=False):
    print("evidence: " + msg, file=sys.stderr)
    if full:
        print(usage_text(), file=sys.stderr)
    sys.exit(2)


def redact(text, extra, excerpt=False):
    """The whole text with every secret value replaced by ***, and how many values were replaced.
    A private key block keeps its BEGIN and END lines and each of its body lines becomes ***. excerpt:
    text is an excerpt keep wrote, where the CUT line closes a key block; in a raw log it does not."""
    count = 0

    def pem(m):
        nonlocal count
        # The excerpt's own `# tail` line can fall inside a block the tail cut: it is no body line.
        body = re.sub(r"[^\r\n]+", lambda l: l.group(0) if l.group(0) in (MASK, TAIL_LINE) else MASK,
                      m.group(2))
        if body != m.group(2):
            count += 1
        return m.group(1) + body + m.group(3)
    text = (PEM_EXCERPT if excerpt else PEM_RAW).sub(pem, text)

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
            s, e = m.start(g) - m.start(0), m.end(g) - m.start(0)
            if not v or v == MASK:
                return m.group(0)
            if (SCHEME.fullmatch(v) and AFTER_SCHEME.match(m.string, m.end())
                    and "authorization" in m.group(0)[:s].lower()):
                return m.group(0)
            count += 1
            return m.group(0)[:s] + MASK + m.group(0)[e:]
        return sub
    rules = [(p, value(g if isinstance(g, tuple) else (g,))) for p, g in RULES]
    # Every rule and token stops at the end of a line, so they run line by line, and only on a line
    # holding a cue: in a long build log most lines hold none, and the cue test is far cheaper.
    lines = text.split("\n")
    for i, line in enumerate(lines):
        low = line.lower()
        if not any(c in low for c in CUES):
            continue
        for p, sub in rules:
            line = p.sub(sub, line)
        for p in TOKENS:
            line = p.sub(whole, line)
        lines[i] = line
    return "\n".join(lines), count


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
        cause = ("no project config (SPINE.md) at or above it" if "no project config" in run.stderr
                 else "resolve-settings.sh raw exited %d" % run.returncode)
        usage("cannot read ## Redact for %s: %s" % (task_dir, cause))
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
        usage("keep takes <log> and <evidence dir>", full=True)
    log, evidence = pos
    if not os.path.isfile(log):
        usage("no log at " + log)
    if name is None:
        name = os.path.basename(log)
    name = name[:-4] if name.endswith(".log") else name
    if not name or name in (".", "..") or "/" in name:
        usage("not a name: " + name)
    evidence, task = evidence_dir(evidence)
    extra = project_patterns(task)

    with open(log, "rb") as fh:
        data = fh.read()
    raw = os.path.join(raw_folder(evidence), name + ".log")
    if not (os.path.exists(raw) and os.path.samefile(log, raw)):
        with open(raw, "wb") as fh:
            fh.write(data)

    text, count = redact(data.decode("utf-8", errors="surrogateescape"), extra)
    lines = [l[:-1] if l.endswith("\r") else l for l in text.split("\n")]
    if lines and lines[-1] == "":
        lines.pop()
    cut = max(len(lines) - TAIL, 0)
    matched = [i for i, l in enumerate(lines) if any(p.search(l) for p in matches)]
    if matches and not matched:
        print("evidence: no line matched --match in " + log, file=sys.stderr)
    above = []
    for i in matched:
        if i >= cut:
            continue
        above.append(lines[i])
        if BEGIN.search(lines[i]) and not END.search(lines[i]):
            # The block's END, if the log has one, decides where its body stops. When the excerpt
            # leaves the END out, the lines after BEGIN would read as body: close the block here.
            j = next((k for k in range(i + 1, len(lines)) if END.search(lines[k])), None)
            if j is not None and j < cut and j not in matched:
                above.append(CUT)
    body = [HEADER % name] + above + [TAIL_LINE] + lines[cut:]
    excerpt = os.path.join(evidence, name + ".log")
    with open(excerpt, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write("\n".join(body) + "\n")
    print("kept %s redacted=%d" % (os.path.relpath(excerpt, task), count))


def evidence_dir(path):
    """(absolute evidence dir, its task folder); the evidence dir lies strictly below the task folder."""
    evidence = os.path.abspath(path)
    task = task_dir_of(evidence)
    if task is None or task == evidence:
        usage("%s is not inside a task folder (no Task.md above it)" % path)
    return evidence, task


def raw_folder(evidence):
    """evidence's raw/, made with a .gitignore holding `*` when either is missing: git never sees a file
    put there. An existing .gitignore is left as it is."""
    raw_dir = os.path.join(evidence, "raw")
    os.makedirs(raw_dir, exist_ok=True)
    ignore = os.path.join(raw_dir, ".gitignore")
    if not os.path.exists(ignore):
        with open(ignore, "w", encoding="utf-8") as fh:
            fh.write("*\n")
    return raw_dir


def raw(args):
    if len(args) != 1 or args[0].startswith("--"):
        usage("raw takes <evidence dir>", full=True)
    evidence, _task = evidence_dir(args[0])
    print(raw_folder(evidence))


def sha1(path):
    h = hashlib.sha1()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def is_image(name):
    return name.lower().endswith(IMAGES)


def kept_list(folder):
    """{file name: sha1} from the folder's kept.txt; a line of another shape lists nothing."""
    out = {}
    try:
        with open(os.path.join(folder, KEPT), encoding="utf-8", errors="surrogateescape") as fh:
            for line in fh:
                m = KEPT_LINE.fullmatch(line.rstrip("\r\n"))
                if m:
                    out[m.group(2)] = m.group(1)
    except FileNotFoundError:
        pass
    return out


def keep_image(args):
    if len(args) != 2 or any(a.startswith("--") for a in args):
        usage("keep-image takes <image> and <evidence dir>", full=True)
    image, evidence = args
    if not os.path.isfile(image):
        usage("no image at " + image)
    name = os.path.basename(image)
    if not is_image(name):
        usage("not an image (%s): %s" % (", ".join(IMAGES), image))
    if "\n" in name or "\r" in name:
        usage("an image name with a line break cannot be listed: %r" % name)
    evidence, task = evidence_dir(evidence)
    raw_dir = os.path.join(evidence, "raw")
    if not (os.path.isdir(raw_dir) and os.path.samefile(os.path.dirname(os.path.abspath(image)), raw_dir)):
        usage("%s is not in %s: a screenshot is saved first into the folder `evidence.sh raw <evidence dir>` prints"
              % (image, raw_dir))
    digest = sha1(image)
    dest = os.path.join(evidence, name)
    os.replace(image, dest)
    kept = os.path.join(evidence, KEPT)
    lines = []
    if os.path.exists(kept):
        with open(kept, encoding="utf-8", errors="surrogateescape") as fh:
            for line in fh:
                line = line.rstrip("\r\n")
                m = KEPT_LINE.fullmatch(line)
                if line and not (m and m.group(2) == name):
                    lines.append(line)
    lines.append("%s  %s" % (digest, name))
    with open(kept, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write("\n".join(lines) + "\n")
    print("kept %s sha1=%s" % (os.path.relpath(dest, task), digest))


def evidence_roots(folder):
    """The phase-evidence/ and validation-evidence/ folders of folder and of its *.step/ folders, any depth."""
    for entry in sorted(os.scandir(folder), key=lambda e: e.name):
        if not entry.is_dir(follow_symlinks=False):
            continue
        if entry.name in EVIDENCE:
            yield entry.path
        elif entry.name.endswith(".step"):
            yield from evidence_roots(entry.path)


def reason_of(path, extra):
    """Why the file at path must not be committed, or None."""
    name = os.path.basename(path)
    if name in (KEPT, ".DS_Store") or name.lower().endswith(".md"):
        return None
    if is_image(name):
        listed = kept_list(os.path.dirname(path)).get(name)
        if listed is None:
            return "unlisted"
        return "changed" if sha1(path) != listed else None
    if name.endswith(".log"):
        with open(path, "rb") as fh:
            text = fh.read().decode("utf-8", errors="surrogateescape")
        first = text.split("\n", 1)[0].rstrip("\r")
        if not MARK.fullmatch(first):
            return "unmarked"
        return "secret" if redact(text, extra, excerpt=True)[1] else None
    return "other"


def check_findings(task_dir):
    """[(path relative to task_dir, reason)] for each evidence file that must not be committed, in path
    order. raw/ folders are never read: git ignores them."""
    extra = project_patterns(task_dir)
    found = []
    for root in evidence_roots(task_dir):
        for folder, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d != "raw"]
            for f in files:
                path = os.path.join(folder, f)
                why = reason_of(path, extra)
                if why:
                    found.append((os.path.relpath(path, task_dir), why))
    return sorted(found)


def check(args):
    if len(args) != 1 or args[0].startswith("--"):
        usage("check takes <task dir>", full=True)
    task = os.path.abspath(args[0])
    if not os.path.isfile(os.path.join(task, "Task.md")):
        usage("%s is not a task folder (no Task.md in it)" % args[0])
    found = check_findings(task)
    for path, why in found:
        print("evidence path=%s reason=%s" % (path, why))
    sys.exit(1 if found else 0)


if not ARGS:
    usage("a subcommand is needed", full=True)
cmd = ARGS.pop(0)
COMMANDS = {"keep": keep, "raw": raw, "keep-image": keep_image, "check": check}
if cmd not in COMMANDS:
    usage("unknown subcommand " + cmd, full=True)
try:
    COMMANDS[cmd](ARGS)
except OSError as e:
    # A file that cannot be read or moved is no finding: exit 1 belongs to check's findings.
    usage("%s: %s" % (cmd, e))
except Exception as e:
    # Nor is an error nobody expected: Python's own exit 1 would read as a finding.
    usage("%s: unexpected %s: %s" % (cmd, type(e).__name__, e))
PY
