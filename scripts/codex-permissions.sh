#!/usr/bin/env bash
# Says which of Spine's Codex CLI settings a project is missing, and writes the ones the user agreed to.
# How setup and the orchestrator use it: skills/setup/SKILL.md → Codex permissions (Codex CLI).
#
# Usage: scripts/codex-permissions.sh check --project <dir> [--platform-root <dir>] [--config-home <dir>]
#        scripts/codex-permissions.sh apply --project <dir> [--platform-root <dir>] [--config-home <dir>] <item>…
# check prints one item per line — rules <file> missing|outdated, menu off, mcp <server> prompts,
# root <path> missing|stale — and exits 0 when it printed none, 1 when it did. apply takes those
# lines as items and writes only them. 2: usage, either.
# --config-home defaults to ${CODEX_HOME:-~/.codex}.
set -uo pipefail

[ $# -ge 1 ] || { sed -n '5,10p' "$0" >&2; exit 2; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 - "$HERE" "$@" <<'PY'
import argparse, glob, json, os, re, sys

HERE = sys.argv[1]
CORE_RULES = os.path.join(HERE, "..", "templates", "codex-rules", "spine.rules")


def usage(msg):
    print("codex-permissions: " + msg, file=sys.stderr)
    sys.exit(2)


class Parser(argparse.ArgumentParser):
    def error(self, message):
        usage(message)


# --- a TOML subset: table headers, key = string | boolean | array of strings, comments ----------
# macOS ships python3 3.9, which has no tomllib; config.toml files Spine reads stay in this subset.

HEADER = re.compile(r'^\s*\[\[?\s*([^\[\]]+?)\s*\]\]?\s*(#.*)?$')
KEY = re.compile(r'^\s*("(?:[^"\\]|\\.)*"|\'[^\']*\'|[A-Za-z0-9_-]+)\s*=\s*(.*)$')
DOTTED = re.compile(r'^\s*((?:"[^"]*"|\'[^\']*\'|[A-Za-z0-9_-]+)(?:\s*\.\s*(?:"[^"]*"|\'[^\']*\'|[A-Za-z0-9_-]+))+)\s*=')


def split_key(text):
    # A dotted key, each part bare or quoted: mcp_servers."XcodeBuildMCP".tools
    parts, i = [], 0
    while i < len(text):
        c = text[i]
        if c in " \t.":
            i += 1
        elif c == '"':
            j = i + 1
            while j < len(text) and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            parts.append(text[i + 1:j].encode().decode("unicode_escape"))
            i = j + 1
        elif c == "'":
            j = text.index("'", i + 1)
            parts.append(text[i + 1:j])
            i = j + 1
        else:
            j = i
            while j < len(text) and text[j] not in " \t.":
                j += 1
            parts.append(text[i:j])
            i = j
    return tuple(parts)


def scan(text):
    # Yields (kind, piece) over a value: str for a string, "[" "]" "," for structure, word for the rest.
    i = 0
    while i < len(text):
        c = text[i]
        if c in " \t\r\n":
            i += 1
        elif c == "#":
            while i < len(text) and text[i] != "\n":
                i += 1
        elif c == '"':
            j, out = i + 1, []
            while j < len(text) and text[j] != '"':
                if text[j] == "\\" and j + 1 < len(text):
                    out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(text[j + 1], text[j + 1]))
                    j += 2
                else:
                    out.append(text[j])
                    j += 1
            yield "str", "".join(out)
            i = j + 1
        elif c == "'":
            j = text.find("'", i + 1)
            j = len(text) if j < 0 else j
            yield "str", text[i + 1:j]
            i = j + 1
        elif c in "[],{}":
            yield c, c
            i += 1
        else:
            j = i
            while j < len(text) and text[j] not in " \t\r\n,]}#":
                j += 1
            yield "word", text[i:j]
            i = j


def value(text):
    toks = list(scan(text))
    if not toks:
        return None
    if toks[0][0] == "str":
        return toks[0][1]
    if toks[0][0] == "word":
        return {"true": True, "false": False}.get(toks[0][1], toks[0][1])
    if toks[0][0] == "[":
        return [t[1] for t in toks if t[0] == "str"]
    return None


def depth(line):
    # Bracket balance of one line outside strings and comments.
    d = 0
    for kind, _ in scan(line):
        d += {"[": 1, "]": -1}.get(kind, 0)
    return d


class Toml:
    """A config.toml as lines, with each table's span and each key's span."""

    def __init__(self, path):
        self.path = path
        self.lines = open(path, encoding="utf-8").read().splitlines() if os.path.isfile(path) else []
        self.parse()

    def parse(self):
        self.tables = {(): [0, len(self.lines), {}]}  # path -> [header line or 0, end, {key: (start, end)}]
        self.dotted = set()  # the full path of every table a dotted key defines, `a.b.c = 1` → (a, b)
        cur, i = (), 0
        while i < len(self.lines):
            line = self.lines[i]
            h = HEADER.match(line)
            if h and not KEY.match(line):
                self.tables[cur][1] = i
                cur = split_key(h.group(1))
                self.tables.setdefault(cur, [i, len(self.lines), {}])
                i += 1
                continue
            d = DOTTED.match(line)
            if d:
                parts = cur + split_key(d.group(1))
                for n in range(len(cur) + 1, len(parts)):
                    self.dotted.add(parts[:n])
            k = KEY.match(line)
            if k:
                start, d = i, depth(k.group(2))
                while d > 0 and i + 1 < len(self.lines):
                    i += 1
                    d += depth(self.lines[i])
                self.tables[cur][2][split_key(k.group(1))[0]] = (start, i)
            i += 1
        self.tables[cur][1] = len(self.lines)

    def get(self, table, key):
        t = self.tables.get(table)
        if not t or key not in t[2]:
            return None
        s, e = t[2][key]
        return value(KEY.match(self.lines[s]).group(2) + "\n" + "\n".join(self.lines[s + 1:e + 1]))

    def has(self, table, key):
        t = self.tables.get(table)
        return bool(t) and key in t[2]

    def set_lines(self, table, key, lines):
        # Replace key's lines, or add them after the table's last key; a new table goes at the end.
        t = self.tables.get(table)
        if t and key in t[2]:
            s, e = t[2][key]
            self.lines[s:e + 1] = lines
        elif t:
            last = max([e for _, e in t[2].values()] + [t[0]])
            self.lines[last + 1:last + 1] = lines
        else:
            while self.lines and not self.lines[-1].strip():
                self.lines.pop()
            if self.lines:
                self.lines.append("")
            self.lines += ["[" + ".".join(table) + "]"] + lines
        self.parse()

    def insert_after_header(self, table, line):
        self.lines.insert(self.tables[table][0] + 1, line)
        self.parse()

    def save(self):
        os.makedirs(os.path.dirname(self.path) or ".", exist_ok=True)
        with open(self.path, "w", encoding="utf-8") as f:
            f.write("\n".join(self.lines) + ("\n" if self.lines else ""))


# --- the items -------------------------------------------------------------------------------------

def rule_sources(platform_root):
    # project file name -> template path; the core's first, then each of the platform's.
    out = [("spine.rules", CORE_RULES)]
    if platform_root:
        for p in sorted(glob.glob(os.path.join(platform_root, "runtimes", "codex-cli", "rules", "*.rules"))):
            out.append(("spine-" + os.path.basename(p), p))
    return out


def read(path):
    try:
        return open(path, "rb").read()
    except OSError:
        return None


def platform_servers(platform_root):
    # The commands of the MCP servers the platform's stages call, from runtimes/codex-cli/mcp.json.
    path = os.path.join(platform_root or "", "runtimes", "codex-cli", "mcp.json")
    if not platform_root or not os.path.isfile(path):
        return []
    try:
        return [str(n) for n in json.load(open(path, encoding="utf-8"))["servers"]]
    except (ValueError, KeyError, TypeError, OSError):
        usage("cannot read " + path)


def package_name(arg):
    # npx's package argument without its version: xcodebuildmcp@1.2.3 → xcodebuildmcp, @s/p@1 → @s/p.
    scope, rest = ("@", arg[1:]) if arg.startswith("@") else ("", arg)
    return scope + rest.split("@")[0]


def wanted_roots(project):
    # Each `- External packages: <glob>` line of the project config, cut before its first glob part.
    for name in ("SPINE.md", "CLAUDE-spine-toolkit.md"):
        path = os.path.join(project, name)
        if os.path.isfile(path):
            break
    else:
        return []
    out = []
    for line in open(path, encoding="utf-8"):
        m = re.match(r"^- External packages:\s*(.+?)\s*$", line)
        if not m:
            continue
        parts = []
        for part in m.group(1).lstrip("/").split("/"):
            if re.search(r"[*?\[]", part):
                break
            parts.append(part)
        root = os.path.normpath(os.path.join(project, *parts))
        if root not in out:
            out.append(root)
    return out


ROOTS = ("sandbox_workspace_write",)


def listed_roots(conf):
    # writable_roots as (the user's, Spine's): an element on a line ending in `# spine` is Spine's.
    t = conf.tables.get(ROOTS)
    if not t or "writable_roots" not in t[2]:
        return [], []
    s, e = t[2]["writable_roots"]
    user, own = [], []
    for i in range(s, e + 1):
        line = conf.lines[i]
        found = [p for k, p in scan(KEY.match(line).group(2) if i == s else line) if k == "str"]
        (own if re.search(r"#\s*spine\s*$", line) else user).extend(found)
    return user, own


class State:
    """What check reports and apply writes, read once from the files."""

    def __init__(self, a):
        self.a = a
        self.rules = rule_sources(a.platform_root)
        self.user = Toml(os.path.join(a.config_home, "config.toml"))
        self.conf = Toml(os.path.join(a.project, ".codex", "config.toml"))
        names = platform_servers(a.platform_root)
        self.servers = {}  # server key → its table path, for every server the platform lists
        for path in self.user.tables:
            if len(path) != 2 or path[0] != "mcp_servers":
                continue
            cmd, args = self.user.get(path, "command"), self.user.get(path, "args")
            if not isinstance(cmd, str):
                continue
            base = os.path.basename(cmd)
            if base in names or (base == "npx" and any(
                    isinstance(x, str) and not x.startswith("-") and package_name(x) in names
                    for x in (args if isinstance(args, list) else []))):
                self.servers[path[1]] = path
        self.wanted = wanted_roots(a.project)
        self.listed, self.own = listed_roots(self.conf)

    def items(self):
        out = []
        for name, src in self.rules:
            want, have = read(src), read(os.path.join(self.a.project, ".codex", "rules", name))
            if want is None:
                usage("cannot read " + src)
            if have is None:
                out.append("rules %s missing" % name)
            elif have != want:
                out.append("rules %s outdated" % name)
        if self.user.get(("features",), "default_mode_request_user_input") is not True:
            out.append("menu off")
        out += ["mcp %s prompts" % k for k, path in self.servers.items()
                if not self.user.has(path, "default_tools_approval_mode")]
        out += ["root %s missing" % r for r in self.wanted if r not in self.listed + self.own]
        out += ["root %s stale" % r for r in self.own if r not in self.wanted]
        return out

    def known(self, item):
        m = re.match(r"^rules (\S+) (missing|outdated)$", item)
        if m:
            return m.group(1) in dict(self.rules)
        m = re.match(r"^mcp (.+) prompts$", item)
        if m:
            return m.group(1) in self.servers
        m = re.match(r"^root (.+) (missing|stale)$", item)
        if m:
            return m.group(1) in (self.wanted if m.group(2) == "missing" else self.own)
        return item == "menu off"


def check(a):
    return State(a).items()


def apply(a, wanted):
    # Every item is checked before the first write; an item already in place is written again as is.
    st = State(a)
    for item in wanted:
        if not st.known(item):
            usage("unknown item: " + item)
    # A table a dotted key already defines cannot get a header of its own: TOML rejects the file.
    for item in wanted:
        conf, table = ((st.user, ("features",)) if item == "menu off" else
                       (st.conf, ROOTS) if item.startswith("root ") else (None, None))
        if conf is not None and table in conf.dotted:
            usage("%s defines [%s] with a dotted key; set it there by hand" % (conf.path, ".".join(table)))
    sources, own, roots_changed = dict(st.rules), list(st.own), False
    for item in wanted:
        kind, rest = item.split(" ", 1)
        if kind == "rules":
            name = rest.split()[0]
            dest = os.path.join(a.project, ".codex", "rules", name)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as f:
                f.write(read(sources[name]))
        elif kind == "menu":
            if st.user.get(("features",), "default_mode_request_user_input") is not True:
                st.user.set_lines(("features",), "default_mode_request_user_input",
                                  ["default_mode_request_user_input = true"])
                st.user.save()
        elif kind == "mcp":
            path = st.servers[rest[:-len(" prompts")]]
            if not st.user.has(path, "default_tools_approval_mode"):
                st.user.insert_after_header(path, 'default_tools_approval_mode = "approve"')
                st.user.save()
        else:
            root, what = rest.rsplit(" ", 1)
            if what == "missing" and root not in own + st.listed:
                own.append(root)
            elif what == "stale" and root in own:
                own.remove(root)
            roots_changed = True
    if roots_changed:
        q = lambda r: json.dumps(r, ensure_ascii=False)
        body = ["  %s," % q(r) for r in st.listed] + ["  %s, # spine" % q(r) for r in own]
        st.conf.set_lines(ROOTS, "writable_roots",
                          ["writable_roots = ["] + body + ["]"] if body else ["writable_roots = []"])
        st.conf.save()


def main():
    p = Parser(prog="codex-permissions.sh")
    p.add_argument("command", choices=["check", "apply"])
    p.add_argument("--project", required=True)
    p.add_argument("--platform-root")
    p.add_argument("--config-home", default=os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex"))
    p.add_argument("items", nargs="*")
    a = p.parse_intermixed_args(sys.argv[2:])
    a.project = os.path.abspath(os.path.expanduser(a.project))
    a.config_home = os.path.expanduser(a.config_home)
    if a.command == "check":
        if a.items:
            usage("check takes no items")
        items = check(a)
        for i in items:
            print(i)
        sys.exit(1 if items else 0)
    if not a.items:
        usage("apply needs at least one item")
    apply(a, a.items)


try:
    main()
except (OSError, UnicodeDecodeError, ValueError) as e:
    usage(str(e))
PY
