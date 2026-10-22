#!/usr/bin/env bash
# Says which of Spine's Codex CLI settings a project is missing, and writes the ones the user agreed to.
# How setup and the orchestrator use it: skills/setup/SKILL.md → Codex permissions (Codex CLI).
#
# Usage: scripts/codex-permissions.sh check --project <dir> [--platform-root <dir>] [--config-home <dir>]
#        scripts/codex-permissions.sh apply --project <dir> [--platform-root <dir>] [--config-home <dir>] <item>…
# check prints one item per line — rules <file> missing|outdated, menu off — and exits 0 when it
# printed none, 1 when it did. apply takes those lines as items and writes only them. 2: usage, either.
# --config-home defaults to ${CODEX_HOME:-~/.codex}.
set -uo pipefail

[ $# -ge 1 ] || { sed -n '5,9p' "$0" >&2; exit 2; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 - "$HERE" "$@" <<'PY'
import argparse, glob, os, re, sys

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

    def set_line(self, table, key, line):
        # Replace key's lines with one line, or add it after the table's last key; a new table goes at the end.
        t = self.tables.get(table)
        if t and key in t[2]:
            s, e = t[2][key]
            self.lines[s:e + 1] = [line]
        elif t:
            last = max([e for _, e in t[2].values()] + [t[0]])
            self.lines.insert(last + 1, line)
        else:
            while self.lines and not self.lines[-1].strip():
                self.lines.pop()
            if self.lines:
                self.lines.append("")
            self.lines += ["[" + ".".join(table) + "]", line]
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


def check(a):
    items = []
    for name, src in rule_sources(a.platform_root):
        want, have = read(src), read(os.path.join(a.project, ".codex", "rules", name))
        if want is None:
            usage("cannot read " + src)
        if have is None:
            items.append("rules %s missing" % name)
        elif have != want:
            items.append("rules %s outdated" % name)
    user = Toml(os.path.join(a.config_home, "config.toml"))
    if user.get(("features",), "default_mode_request_user_input") is not True:
        items.append("menu off")
    return items


def known(item, sources):
    m = re.match(r"^rules (\S+) (missing|outdated)$", item)
    return (m and m.group(1) in sources) or item == "menu off"


def apply(a, wanted):
    # Every item is checked before the first write; an item already in place is written again as is.
    sources = dict(rule_sources(a.platform_root))
    for item in wanted:
        if not known(item, sources):
            usage("unknown item: " + item)
    for item in wanted:
        if item.startswith("rules "):
            name = item.split()[1]
            dest = os.path.join(a.project, ".codex", "rules", name)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as f:
                f.write(read(sources[name]))
        elif item == "menu off":
            user = Toml(os.path.join(a.config_home, "config.toml"))
            if user.get(("features",), "default_mode_request_user_input") is not True:
                user.set_line(("features",), "default_mode_request_user_input", "default_mode_request_user_input = true")
                user.save()


def main():
    p = Parser(prog="codex-permissions.sh")
    p.add_argument("command", choices=["check", "apply"])
    p.add_argument("--project", required=True)
    p.add_argument("--platform-root")
    p.add_argument("--config-home", default=os.environ.get("CODEX_HOME") or os.path.expanduser("~/.codex"))
    p.add_argument("items", nargs="*")
    a = p.parse_intermixed_args(sys.argv[2:])
    a.project = os.path.abspath(a.project)
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


main()
PY
