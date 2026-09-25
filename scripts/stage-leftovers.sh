#!/usr/bin/env bash
# Shows what a stage left behind — processes it started, files it changed — and a stalled MCP call.
# How the orchestrator uses it: skills/orchestrator/SKILL.md → Stage leftovers.
#
# Usage: scripts/stage-leftovers.sh snap --out <file> [--root <dir>]… [--exclude <dir>]…
#        scripts/stage-leftovers.sh diff <file>
#        scripts/stage-leftovers.sh kill <pid>:<start>…
#        scripts/stage-leftovers.sh watch --dir <transcript dir> --stall <s> --idle <s>
# Exit: diff 0 nothing, 1 findings; kill 0; watch 4 stalled call, 5 idle. 2: usage, any subcommand.
set -uo pipefail

[ $# -ge 1 ] || { sed -n '5,9p' "$0" >&2; exit 2; }
exec python3 - "$@" <<'PY'
import hashlib, json, os, signal, subprocess, sys, time
from datetime import datetime

# Test seams: a ps listing, the session's claude pid, the clock and the registry path.
PS_FILE = os.environ.get("STAGE_LEFTOVERS_PS")
NOW = float(os.environ.get("STAGE_LEFTOVERS_NOW") or time.time())
POLL = float(os.environ.get("STAGE_LEFTOVERS_POLL") or 15)
REGISTRY = os.environ.get("LONG_RUN_REGISTRY") or os.path.join(
    os.environ.get("TMPDIR") or "/tmp", "spine-long-run.registry")


def usage(msg):
    print("stage-leftovers: " + msg, file=sys.stderr)
    sys.exit(2)


def procs():
    # pid -> (ppid, start epoch, cpu, command); lstart is five words: "Fri Sep 25 14:24:01 2026".
    if PS_FILE:
        text = open(PS_FILE, encoding="utf-8").read()
    else:
        text = subprocess.run(["ps", "-axo", "pid=,ppid=,pcpu=,lstart=,command="],
                              capture_output=True, text=True).stdout
    table = {}
    for line in text.splitlines():
        f = line.split(None, 8)
        if len(f) < 9:
            continue
        try:
            start = time.mktime(time.strptime(" ".join(f[3:8]), "%a %b %d %H:%M:%S %Y"))
            table[int(f[0])] = (int(f[1]), start, f[2], f[8])
        except ValueError:
            continue
    return table


def session_pid(table):
    if os.environ.get("STAGE_LEFTOVERS_SESSION_PID"):
        return int(os.environ["STAGE_LEFTOVERS_SESSION_PID"])
    pid = os.getppid()
    while pid in table and pid > 1:
        if os.path.basename(table[pid][3].split()[0]) == "claude":
            return pid
        pid = table[pid][0]
    usage("no claude process above this one: run it from the session's Bash tool")


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


def own_chain(table):
    # This script, the shell that ran it and whatever it forked: new, but not the stage's.
    mine, pid = set(), os.getpid()
    while pid in table and pid > 1:
        mine.add(pid)
        pid = table[pid][0]
    return mine | descendants(table, os.getpid())[0]


def dirty(root, excludes):
    out = subprocess.run(["git", "-C", root, "status", "--porcelain", "-z", "--untracked-files=all"],
                         capture_output=True, text=True).stdout
    state, parts, i = {}, out.split("\0"), 0
    while i < len(parts):
        entry = parts[i]
        i += 1
        if len(entry) < 4:
            continue
        xy, path = entry[:2], entry[3:]
        if "R" in xy or "C" in xy:
            i += 1  # a rename carries its source path as the next field
        full = os.path.join(root, path)
        if any(os.path.abspath(full).startswith(os.path.abspath(e) + os.sep) for e in excludes):
            continue
        try:
            digest = hashlib.sha1(open(full, "rb").read()).hexdigest()
        except OSError:
            digest = None
        state[path] = [xy, digest]
    return state


def age(seconds):
    m = int(seconds) // 60
    return "%dh%02dm" % (m // 60, m % 60) if m >= 60 else "%dm" % m


def snap(args):
    out, roots, excludes = None, [], []
    while args:
        flag = args.pop(0)
        if flag in ("--out", "--root", "--exclude") and args:
            val = args.pop(0)
            if flag == "--out":
                out = val
            else:
                (roots if flag == "--root" else excludes).append(os.path.abspath(val))
        else:
            usage("snap --out <file> [--root <dir>]… [--exclude <dir>]…")
    if not out:
        usage("snap needs --out")
    table = procs()
    sess = session_pid(table)
    below, _ = descendants(table, sess)
    doc = {"taken": int(NOW),  # whole seconds, as long-run.sh writes the registry
           "session": sess, "excludes": excludes,
           "procs": {str(p): table[p][1] for p in below},
           "roots": {r: dirty(r, excludes) for r in roots}}
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    json.dump(doc, open(out, "w", encoding="utf-8"))


def new_roots(doc, table):
    # The topmost process of each subtree the stage started and left: one line per build, not per child.
    sess = doc["session"]
    below, kids = descendants(table, sess)
    mine = own_chain(table)
    old = {int(p): s for p, s in doc["procs"].items()}

    def is_new(pid):
        return pid in below and pid not in mine and abs(old.get(pid, -1) - table[pid][1]) > 1

    found = []
    for pid in sorted(below):
        ppid, start, _cpu, cmd = table[pid]
        if ppid == sess or not is_new(pid) or is_new(ppid) or "stage-leftovers.sh watch" in cmd:
            continue
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
        f = line.split(" ", 2)
        if len(f) < 3 or not f[0].isdigit():
            continue
        pid, when, log = int(f[0]), float(f[1]), f[2]
        if when < doc["taken"] or pid in seen or pid not in table or os.path.exists(log + ".exit"):
            continue
        found.append(pid)
    return found


def diff(args):
    if len(args) != 1:
        usage("diff <file>")
    doc = json.load(open(args[0], encoding="utf-8"))
    table = procs()
    hits = new_roots(doc, table)
    hits += registry_orphans(doc, table, set(hits))
    lines = []
    for pid in hits:
        ppid, start, _cpu, cmd = table[pid]
        lines.append("process pid=%d start=%d age=%s parent=%d cmd=%s"
                     % (pid, start, age(NOW - start), ppid, cmd[:200]))
    for root, before in doc["roots"].items():
        after = dirty(root, doc["excludes"])
        for path, (xy, digest) in sorted(after.items()):
            if path in before and before[path][1] == digest:
                continue
            change = ("added" if xy in ("??", "A ") and path not in before
                      else "deleted" if digest is None else "modified")
            lines.append("tree root=%s path=%s change=%s" % (root, path, change))
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
        content = (row.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for item in content:
            if item.get("type") == "tool_use":
                pending[item.get("id")] = (item.get("name") or "", ts(row["timestamp"]))
            elif item.get("type") == "tool_result":
                pending.pop(item.get("tool_use_id"), None)
    return max(pending.values(), key=lambda v: v[1]) if pending else None


def watch(args):
    opts = {}
    while args:
        flag = args.pop(0)
        if flag in ("--dir", "--stall", "--idle") and args:
            opts[flag] = args.pop(0)
        else:
            usage("watch --dir <transcript dir> --stall <s> --idle <s>")
    if set(opts) != {"--dir", "--stall", "--idle"}:
        usage("watch --dir <transcript dir> --stall <s> --idle <s>")
    root, stall, idle = opts["--dir"], float(opts["--stall"]), float(opts["--idle"])
    if not os.path.isdir(root):
        usage("no transcript dir %s" % root)
    while True:
        now = float(os.environ.get("STAGE_LEFTOVERS_NOW") or time.time())
        names = [n for n in os.listdir(root) if n.startswith("agent-") and n.endswith(".jsonl")]
        newest = max([os.path.getmtime(os.path.join(root, n)) for n in names] + [os.path.getmtime(root)])
        for name in sorted(names):
            call = pending_call(os.path.join(root, name))
            # Bash has its own tool timeout and long-run.sh its own --stall; only an MCP call has neither.
            if call and call[0].startswith("mcp__") and now - call[1] > stall:
                print("hung agent=%s tool=%s age=%s" % (name[6:-6], call[0], age(now - call[1])))
                table = procs()
                sess = session_pid(table)
                below, _ = descendants(table, sess)
                mine = own_chain(table)
                for pid in sorted(below - mine):
                    ppid, start, cpu, cmd = table[pid]
                    if ppid != sess:
                        print("  proc pid=%d start=%d cpu=%s age=%s cmd=%s"
                              % (pid, start, cpu, age(now - start), cmd[:160]))
                sys.exit(4)
        if now - newest > idle:
            print("idle dir=%s for=%s" % (root, age(now - newest)))
            sys.exit(5)
        time.sleep(POLL)


cmd, rest = sys.argv[1], sys.argv[2:]
{"snap": snap, "diff": diff, "kill": kill, "watch": watch}.get(
    cmd, lambda _a: usage("unknown subcommand %s" % cmd))(rest)
PY
