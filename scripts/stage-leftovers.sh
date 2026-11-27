#!/usr/bin/env bash
# Shows what a stage left behind — processes it started, files it changed — and a stalled MCP call.
# How the orchestrator uses it: skills/orchestrator/SKILL.md → Stage leftovers.
#
# Usage: scripts/stage-leftovers.sh snap --out <file> [--root <dir>]… [--exclude <dir>]… [--task-dir <glob>]
#        scripts/stage-leftovers.sh diff [--out] <file>
#        scripts/stage-leftovers.sh foreign <task dir>
#        scripts/stage-leftovers.sh kill <pid>:<start>…
#        scripts/stage-leftovers.sh watch --dir <transcript dir> --stall <s> --idle <s> [--since <epoch>]
#        scripts/stage-leftovers.sh origin <pid>…
#        scripts/stage-leftovers.sh restore <snap> <root> <path>…
#        scripts/stage-leftovers.sh leave <snap> <root> <path>…
#        scripts/stage-leftovers.sh held <snap>
# Exit: diff, foreign and held 0 nothing, 1 findings; kill and leave 0; restore 0 or git restore's code;
#       watch 4 stalled call, 5 idle, 6 session gone. 2: usage, any subcommand.
set -uo pipefail

[ $# -ge 1 ] || { sed -n '5,15p' "$0" >&2; exit 2; }
exec python3 - "$@" <<'PY'
import fnmatch, glob, hashlib, json, os, re, signal, subprocess, sys, time
from datetime import datetime

# Test seams: a ps listing, the session's claude pid, this process's pid, the clock, the registry path,
# and "<pid> <origin>" lines read in place of the system's answer (a pid not listed has none).
PS_FILE = os.environ.get("STAGE_LEFTOVERS_PS")
ORIGIN_FILE = os.environ.get("STAGE_LEFTOVERS_ORIGIN")
NOW = float(os.environ.get("STAGE_LEFTOVERS_NOW") or time.time())
POLL = float(os.environ.get("STAGE_LEFTOVERS_POLL") or 15)
SELF = int(os.environ.get("STAGE_LEFTOVERS_SELF") or os.getpid())
SHELL = re.compile(r"^\S*/?(zsh|bash|sh) -\w*c ")
SNAPSHOT = re.compile(r"shell-snapshots/(snapshot-[\w.-]+?\.sh)")
WATCH = re.compile(r"(stage-leftovers\.sh|python\S*\s+-)\s+watch\s")
REGISTRY = os.environ.get("LONG_RUN_REGISTRY") or os.path.join(
    os.environ.get("TMPDIR") or "/tmp", "spine-long-run.registry")


def usage(msg):
    print("stage-leftovers: " + msg, file=sys.stderr)
    sys.exit(2)


def procs():
    # pid -> (ppid, start epoch, cpu, command, pgid, uid); lstart is five words: "Fri Sep 25 14:24:01 2026".
    if PS_FILE:
        text = open(PS_FILE, encoding="utf-8").read()
    else:
        # lstart follows LC_TIME: under ru_RU it is no longer five English words.
        ps = subprocess.run(["ps", "-axww", "-o", "pid=,ppid=,pgid=,uid=,pcpu=,lstart=,command="],
                            capture_output=True, text=True, errors="replace",
                            env=dict(os.environ, LC_ALL="C"))
        if ps.returncode != 0 and not ps.stdout.strip():
            # A sandboxed host (Codex CLI's workspace-write) refuses ps outright.
            usage("ps is not permitted here: " + (ps.stderr.strip() or "exit %d" % ps.returncode))
        text = ps.stdout
    table = {}
    for line in text.splitlines():
        f = line.split(None, 10)
        if len(f) < 11:
            continue
        try:
            start = time.mktime(time.strptime(" ".join(f[5:10]), "%a %b %d %H:%M:%S %Y"))
            table[int(f[0])] = (int(f[1]), start, f[4], f[10], int(f[2]), int(f[3]))
        except ValueError:
            continue
    return table


def session_pid(table):
    if os.environ.get("STAGE_LEFTOVERS_SESSION_PID"):
        return int(os.environ["STAGE_LEFTOVERS_SESSION_PID"])
    pid = table[SELF][0] if SELF in table else os.getppid()
    while pid in table and pid > 1:
        if os.path.basename(table[pid][3].split()[0]) in ("claude", "codex"):
            return pid
        pid = table[pid][0]
    usage("no claude or codex process above this one: run it from the session's shell tool")


# The variables a session sets for the commands it runs; only those this script itself has are compared.
MARKERS = re.compile(r"^(CLAUDE_PID|CLAUDE_CODE_SESSION_ID|CODEX_\w+)$")


def origin(pid):
    # Who a process came from, or None when that cannot be read. On macOS, its responsible process: the
    # app that launched it, inherited across fork and reparenting — a terminal app for everything a
    # session runs, the app itself for its own helpers. Elsewhere, the session markers in its environment.
    if ORIGIN_FILE:
        for line in open(ORIGIN_FILE, encoding="utf-8").read().splitlines():
            f = line.split(None, 1)
            if len(f) == 2 and f[0] == str(pid):
                return f[1]
        return None
    if sys.platform == "darwin":
        try:
            import ctypes
            fn = ctypes.CDLL(None).responsibility_get_pid_responsible_for_pid
            fn.argtypes, fn.restype = [ctypes.c_int], ctypes.c_int
            who = fn(pid)
        except (AttributeError, OSError):
            return None
        return str(who) if who > 0 else None
    names = sorted(n for n in os.environ if MARKERS.match(n))
    if not names:
        return None
    try:
        raw = open("/proc/%d/environ" % pid, "rb").read().split(b"\0")
    except OSError:
        return None
    env = dict(e.decode(errors="replace").split("=", 1) for e in raw if b"=" in e)
    return " ".join("%s=%s" % (n, env.get(n, "")) for n in names)


def session_origin(sess):
    # On macOS the session process answers for itself; elsewhere the markers sit in what it passes down,
    # which this script was given too.
    if ORIGIN_FILE or sys.platform == "darwin":
        return origin(sess)
    names = sorted(n for n in os.environ if MARKERS.match(n))
    return " ".join("%s=%s" % (n, os.environ[n]) for n in names) or None


def descendants(table, root):
    kids = {}
    for pid, (ppid, *_rest) in table.items():
        kids.setdefault(ppid, []).append(pid)
    out, stack = [], list(kids.get(root, []))
    while stack:
        pid = stack.pop()
        out.append(pid)
        stack.extend(kids.get(pid, []))
    return set(out), kids


def own_chain(table, sess):
    # The Bash-tool shell that ran this script and everything under it — a pipe partner too.
    pid = SELF
    while pid in table and table[pid][0] not in (sess, 0, 1):
        pid = table[pid][0]
    return ({pid} | descendants(table, pid)[0]) if pid in table else set()


def literal(pattern):
    # A pattern is a path whose `*` components are wildcards; every other character is itself, so a
    # folder named "044 [x]" is not a character class that matches nothing.
    return os.sep.join(c if c == "*" else glob.escape(c) for c in pattern.split(os.sep))


def quoted(path):
    # One finding is one line: a name with a control character, or bytes that are not UTF-8, is
    # quoted as git quotes it, "a\nb", and the orchestrator shows it without acting on it.
    if not any(c < " " or c == "\x7f" or "\udc80" <= c <= "\udcff" for c in path):
        return path
    esc = {"\n": "\\n", "\t": "\\t", "\r": "\\r", '"': '\\"', "\\": "\\\\"}
    out = []
    for c in path:
        if c in esc:
            out.append(esc[c])
        elif "\udc80" <= c <= "\udcff":
            out.append("\\%03o" % (ord(c) - 0xDC00))
        elif c < " " or c == "\x7f":
            out.append("\\%03o" % ord(c))
        else:
            out.append(c)
    return '"%s"' % "".join(out)


def dirty(root, excludes):
    # Porcelain paths are relative to the repository's top; report them relative to the root.
    top = subprocess.run(["git", "-C", root, "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True).stdout.strip() or root
    out = subprocess.run(["git", "-C", root, "status", "--porcelain", "-z", "--untracked-files=all",
                          "--", "."], capture_output=True, text=True, errors="surrogateescape").stdout
    state, parts, i = {}, out.split("\0"), 0
    while i < len(parts):
        entry = parts[i]
        i += 1
        if len(entry) < 4:
            continue
        xy, path = entry[:2], entry[3:]
        if "R" in xy or "C" in xy:
            i += 1  # a rename carries its source path as the next field
        full = os.path.join(top, path)
        path = os.path.relpath(full, os.path.realpath(root))
        if any(fnmatch.fnmatch(full, literal(os.path.realpath(e))) or
               fnmatch.fnmatch(full, literal(os.path.realpath(e)).rstrip(os.sep) + os.sep + "*")
               for e in excludes):
            continue
        try:
            digest = hashlib.sha1(open(full, "rb").read()).hexdigest()
        except OSError:
            digest = None
        state[path] = [xy, digest]
    return state


# What a task folder may hold (skills/orchestrator/SKILL.md → Stage leftovers): its documents at any
# depth, Run.json, _archive/, and the evidence folders whole except long-run.sh's sidecars. A step
# folder holds the same.
EVIDENCE = ("phase-evidence", "validation-evidence", "experiment")
SIDECARS = (".pid", ".start", ".cwd", ".exit", ".exit.tmp")


def lawful(rel):
    parts = rel.split("/")
    while len(parts) > 1 and parts[0].endswith(".step"):
        parts = parts[1:]
    if len(parts) > 1 and parts[0] in EVIDENCE:
        return not rel.endswith(SIDECARS)
    return rel.endswith(".md") or parts == ["Run.json"] or (len(parts) > 1 and parts[0] == "_archive")


def task_candidates(task_dir):
    # The files a commit of the folder would add: untracked and not ignored. Outside git, or in a
    # repository that ignores the folder whole, every file: nothing commits them, but they still sit
    # beside the documents that cite them.
    git = lambda *a: subprocess.run(["git", "-C", task_dir] + list(a), capture_output=True)
    if git("rev-parse").returncode == 0 and git("check-ignore", "-q", ".").returncode != 0:
        out = subprocess.run(["git", "-C", task_dir, "ls-files", "--others", "--exclude-standard", "-z"],
                             capture_output=True, text=True, errors="surrogateescape").stdout
        return sorted(p for p in out.split("\0") if p)
    # A nested repository is one entry, "clone/", as git lists it.
    found = []
    for d, dirs, files in os.walk(task_dir):
        if d != task_dir and ".git" in dirs + files:
            found.append(os.path.relpath(d, task_dir) + "/")
            dirs[:] = []
            continue
        dirs[:] = [x for x in dirs if x != ".git"]
        found += [os.path.relpath(os.path.join(d, f), task_dir) for f in files if f != ".DS_Store"]
    return sorted(found)


def resolve_task_dirs(pattern):
    # Every folder the glob matches: a failed move can leave the task under two status directories.
    return sorted(h for h in glob.glob(literal(pattern)) if os.path.isdir(h))


def foreign(args):
    if len(args) != 1 or not os.path.isdir(args[0]):
        usage("foreign <task dir>")
    hits = [p for p in task_candidates(args[0]) if not lawful(p)]
    if hits:
        print("\n".join("foreign path=%s" % quoted(p) for p in hits))
    sys.exit(1 if hits else 0)


def age(seconds):
    m = int(seconds) // 60
    return "%dh%02dm" % (m // 60, m % 60) if m >= 60 else "%dm" % m


def snap(args):
    out, roots, excludes, task_dir = None, [], [], None
    while args:
        flag = args.pop(0)
        if flag in ("--out", "--root", "--exclude", "--task-dir") and args:
            val = args.pop(0)
            if flag == "--out":
                out = val
            elif flag == "--task-dir":
                task_dir = os.path.abspath(val)
            else:
                (roots if flag == "--root" else excludes).append(os.path.abspath(val))
        else:
            usage("snap --out <file> [--root <dir>]… [--exclude <dir>]… [--task-dir <glob>]")
    if not out:
        usage("snap needs --out")
    table = procs()
    sess = session_pid(table)
    below, _ = descendants(table, sess)
    doc = {"taken": int(NOW),  # whole seconds, as long-run.sh writes the registry
           "session": sess, "excludes": excludes,
           "procs": {str(p): table[p][1] for p in below},
           "roots": {r: dirty(r, excludes) for r in roots},
           "task_dir": task_dir, "task_files": []}
    if task_dir:
        doc["task_files"] = sorted({p for d in resolve_task_dirs(task_dir) for p in task_candidates(d)})
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    json.dump(doc, open(out, "w", encoding="utf-8"))


def new_roots(doc, table):
    # The topmost process of each subtree the stage started and left: one line per build, not per child.
    # Claude Code's own children are not the stage's: MCP servers, and the Bash-tool shells — but what
    # a shell started is, so the search goes one level into a shell and no further into a server.
    sess = doc["session"]
    below, _ = descendants(table, sess)
    skip = own_chain(table, sess)
    for pid in below:
        if WATCH.search(table[pid][3]):
            skip |= {pid} | descendants(table, pid)[0]
    old = {int(p): s for p, s in doc["procs"].items()}

    def is_new(pid):
        return pid in below and abs(old.get(pid, -1) - table[pid][1]) > 1

    def shell(pid):
        return table[pid][0] == sess and SHELL.match(table[pid][3])

    found = []
    for pid in sorted(below - skip):
        ppid = table[pid][0]
        if ppid == sess or not is_new(pid) or (is_new(ppid) and not shell(ppid)):
            continue
        found.append(pid)
    return found


def shell_orphans(doc, table):
    # A Bash-tool shell leads its own process group, and what it sent to the background keeps the
    # group when the shell exits and the process goes to PID 1. So the stage's orphan is a process
    # under PID 1 whose group's leader is gone, of this user, started after the snapshot. A launchd
    # job leads its own group. An app's helper that double-forks, a crashpad handler, has the same
    # shape as the stage's orphan, so one whose origin differs from the session's is the app's; when
    # either cannot be read, it is shown. The helpers of the app the session itself runs in share its
    # origin and are still shown. A group whose shell names another session's snapshot file is that
    # session's; one with no name at all is shown, the user decides.
    mine = {SNAPSHOT.search(table[p][3]).group(1) for p in own_chain(table, doc["session"])
            if SNAPSHOT.search(table[p][3])}
    groups = {}
    for pid, row in table.items():
        groups.setdefault(row[4], []).append(pid)

    def foreign(pgid):
        names = {m.group(1) for p in groups[pgid] for m in [SNAPSHOT.search(table[p][3])] if m}
        return bool(names) and bool(mine) and not names & mine

    # A watch is the orchestrator's own, not the stage's, wherever it ended up.
    watches = set()
    for pid in table:
        if WATCH.search(table[pid][3]):
            watches |= {pid} | descendants(table, pid)[0]
    mark = session_origin(doc["session"])

    def elsewhere(pid):
        theirs = origin(pid) if mark else None
        return theirs is not None and theirs != mark

    found = []
    for pid in sorted(set(table) - watches):
        ppid, start, _cpu, _cmd, pgid, uid = table[pid]
        if (ppid == 1 and pgid != pid and pgid not in table and uid == os.getuid()
                and start >= doc["taken"] and not foreign(pgid) and not elsewhere(pid)):
            found.append(pid)
    return found


def registry_orphans(doc, table, seen):
    # long-run.sh detaches its job to launchd, out of the claude subtree: its registry names it.
    found = []
    try:
        lines = open(REGISTRY, encoding="utf-8").read().splitlines()
    except OSError:
        return found
    for line in lines:
        # <pid> <epoch> <claude pid> <log>: a line from another session, or older than the session
        # field, is not this stage's; a pid whose process started elsewhen was recycled.
        f = line.split(" ", 3)
        if len(f) < 4 or not (f[0].isdigit() and f[2].isdigit()):
            continue
        pid, when, owner, log = int(f[0]), float(f[1]), int(f[2]), f[3]
        if (owner != doc["session"] or when < doc["taken"] or pid in seen or pid not in table
                or abs(table[pid][1] - when) > 5 or os.path.exists(log + ".exit")):
            continue
        found.append(pid)
    return found


# The task's memory beside its snapshot: what restore put back, with the content it removed, and what
# the user chose to leave. A file restored that comes back with that same content is rewritten by the
# build or the environment, not by the stage's work: diff marks it, so the restore is not offered again
# as the way out. Lost or unreadable, it is an empty memory, and the worst case is one plain question.
def memo_path(snap):
    return os.path.splitext(snap)[0] + ".memo"


def load_memo(snap):
    try:
        memo = json.load(open(memo_path(snap), encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return memo if isinstance(memo, dict) else {}


def save_memo(snap, memo):
    path = memo_path(snap)
    tmp = path + ".tmp"
    json.dump(memo, open(tmp, "w", encoding="utf-8"))
    os.replace(tmp, path)


def checkable(path):
    # A quoted name holds a control character and a trailing / is a nested repository: shown, never acted on.
    return not (path.startswith('"') and path.endswith('"')) and not path.endswith("/")


def path_args(args, name):
    if len(args) < 2:
        usage("%s <snap> <root> <path>…" % name)
    snap, root, paths = args[0], os.path.abspath(args[1]), args[2:]
    for p in paths:
        if not checkable(p):
            usage("%s does not act on %s" % (name, p))
    return snap, root, paths


def sha1_of(path):
    try:
        return hashlib.sha1(open(path, "rb").read()).hexdigest()
    except OSError:
        return None


def restore(args):
    snap, root, paths = path_args(args, "restore")
    # One git call per path, the path taken literally: a path git cannot restore, an untracked file, fails
    # alone, and "a[1].txt" never reverts a1.txt. Only what was restored is remembered.
    memo, code = load_memo(snap), 0
    for p in paths:
        digest = sha1_of(os.path.join(root, p))
        rc = subprocess.run(["git", "-C", root, "restore", "--", ":(literal)" + p]).returncode
        if rc != 0:
            code = code or rc
            continue
        entry = memo.setdefault(root, {}).setdefault(p, {})
        entry["restored"] = digest
        entry.pop("left", None)
    if memo:
        save_memo(snap, memo)
    sys.exit(code)


def leave(args):
    snap, root, paths = path_args(args, "leave")
    if not paths:
        return
    memo = load_memo(snap)
    for p in paths:
        memo.setdefault(root, {}).setdefault(p, {})["left"] = True
    save_memo(snap, memo)


def held(args):
    # What the user left that still differs from HEAD: the orchestrator names it at Done.
    if len(args) != 1:
        usage("held <snap>")
    lines = []
    for root, entries in sorted(load_memo(args[0]).items()):
        for path, entry in sorted((entries or {}).items()):
            if not (isinstance(entry, dict) and entry.get("left")):
                continue
            out = subprocess.run(["git", "-C", root, "status", "--porcelain", "--", ":(literal)" + path],
                                 capture_output=True, text=True).stdout
            if out.strip():
                lines.append("held root=%s path=%s" % (root, path))
    if lines:
        print("\n".join(lines))
    sys.exit(1 if lines else 0)


def diff(args):
    if len(args) == 2 and args[0] == "--out":  # the flag snap was given the file with
        args = args[1:]
    if len(args) != 1:
        usage("diff <file>")
    doc = json.load(open(args[0], encoding="utf-8"))
    memo = load_memo(args[0])
    table = procs()
    hits = new_roots(doc, table)
    hits += shell_orphans(doc, table)
    hits += registry_orphans(doc, table, set(hits))
    lines = []
    for pid in hits:
        ppid, start, _cpu, cmd = table[pid][:4]
        lines.append("process pid=%d start=%d age=%s parent=%d cmd=%s"
                     % (pid, start, age(NOW - start), ppid, cmd[:200]))
    for root, before in doc["roots"].items():
        after = dirty(root, doc["excludes"])
        for path, (xy, digest) in sorted(after.items()):
            if path in before and before[path][1] == digest:
                continue
            change = ("added" if xy in ("??", "A ") and path not in before
                      else "deleted" if digest is None else "modified")
            again = (change == "modified" and digest is not None
                     and (memo.get(root) or {}).get(path, {}).get("restored") == digest)
            lines.append("tree root=%s path=%s change=%s%s"
                         % (root, quoted(path), change, " again=1" if again else ""))
    # The task folder is excluded above; what it may not hold is checked here, against the files it
    # had at the snapshot, under whichever status directory it is in now.
    known = set(doc.get("task_files", []))
    for resolved in resolve_task_dirs(doc["task_dir"]) if doc.get("task_dir") else []:
        for path in task_candidates(resolved):
            if path not in known and not lawful(path):
                lines.append("tree root=%s path=%s change=added" % (resolved, quoted(path)))
    print("\n".join(lines))
    sys.exit(1 if lines else 0)


def kill(args):
    # pid:start, so a pid the system has since handed to another process is never signalled.
    if not args:
        usage("kill <pid>:<start>…")
    table = procs()
    _, kids = descendants(table, 0)
    for arg in args:
        pid, _, start = arg.partition(":")
        if not pid.isdigit() or not start.isdigit():
            usage("kill <pid>:<start>…")
        pid = int(pid)
        if pid not in table or abs(table[pid][1] - int(start)) > 1:
            print("gone pid=%d" % pid)
            continue
        tree, stack = [], [pid]
        while stack:
            p = stack.pop()
            tree.append(p)
            stack.extend(kids.get(p, []))
        for n, sig in enumerate((signal.SIGTERM, signal.SIGKILL)):
            if n:
                time.sleep(2)
            for p in reversed(tree):
                try:
                    os.kill(p, sig)
                except OSError:
                    pass
        print("killed pid=%d" % pid)


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def pending_call(path):
    # The agent's last tool_use that no tool_result has answered yet: (tool, epoch) or None.
    pending = {}
    try:
        fh = open(path, encoding="utf-8")
    except OSError:
        return None
    for line in fh:
        try:
            row = json.loads(line)
        except ValueError:
            continue  # the last line can be half-written
        # Only a turn of the conversation is an event; other rows, such as a copy of the API
        # request, repeat calls already answered. The transcript format is not ours to rely on.
        if not isinstance(row, dict) or row.get("type") not in ("assistant", "user"):
            continue
        content = (row.get("message") or {}).get("content")
        if not isinstance(content, list) or not row.get("timestamp"):
            continue
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get("type") == "tool_use":
                pending[item.get("id")] = (item.get("name") or "", ts(row["timestamp"]))
            elif item.get("type") == "tool_result":
                pending.pop(item.get("tool_use_id"), None)
    return max(pending.values(), key=lambda v: v[1]) if pending else None


def watch(args):
    opts = {"--since": "0"}
    while args:
        flag = args.pop(0)
        if flag in ("--dir", "--stall", "--idle", "--since") and args:
            opts[flag] = args.pop(0)
        else:
            usage("watch --dir <transcript dir> --stall <s> --idle <s> [--since <epoch>]")
    if not {"--dir", "--stall", "--idle"} <= set(opts):
        usage("watch --dir <transcript dir> --stall <s> --idle <s> [--since <epoch>]")
    root, stall, idle = opts["--dir"], float(opts["--stall"]), float(opts["--idle"])
    since = float(opts["--since"])  # "wait more": silence counts from here, not from the call
    if not os.path.isdir(root):
        usage("no transcript dir %s" % root)
    # A watch outlives a session that closed mid-stage, and nobody is left to wake: it ends with it.
    # The start time tells the session from a later process given its pid.
    table = procs()
    sess = session_pid(table)
    born = table[sess][1] if sess in table else None
    while True:
        now = float(os.environ.get("STAGE_LEFTOVERS_NOW") or time.time())
        table = procs()
        if born is None or sess not in table or abs(table[sess][1] - born) > 1:
            print("session gone pid=%d" % sess)
            sys.exit(6)
        names = [n for n in os.listdir(root) if n.startswith("agent-") and n.endswith(".jsonl")]
        newest = max([os.path.getmtime(os.path.join(root, n)) for n in names] + [os.path.getmtime(root)])
        for name in sorted(names):
            call = pending_call(os.path.join(root, name))
            # Bash has its own tool timeout and long-run.sh its own --stall; only an MCP call has neither.
            if call and call[0].startswith("mcp__") and now - max(call[1], since) > stall:
                print("hung agent=%s tool=%s age=%s" % (name[6:-6], call[0], age(now - call[1])))
                below, _ = descendants(table, sess)
                mine = own_chain(table, sess)
                for pid in sorted(below - mine):
                    ppid, start, cpu, cmd = table[pid][:4]
                    if ppid != sess:
                        print("  proc pid=%d start=%d cpu=%s age=%s cmd=%s"
                              % (pid, start, cpu, age(now - start), cmd[:160]))
                sys.exit(4)
        if now - newest > idle:
            print("idle dir=%s for=%s" % (root, age(now - newest)))
            sys.exit(5)
        time.sleep(POLL)


def show_origin(args):
    # One line per pid, empty when its origin cannot be read: what diff compares, to look at by hand.
    if not args or not all(a.isdigit() for a in args):
        usage("origin <pid>…")
    print("\n".join(origin(int(a)) or "" for a in args))


cmd, rest = sys.argv[1], sys.argv[2:]
{"snap": snap, "diff": diff, "foreign": foreign, "kill": kill, "watch": watch, "origin": show_origin,
 "restore": restore, "leave": leave, "held": held}.get(
    cmd, lambda _a: usage("unknown subcommand %s" % cmd))(rest)
PY
