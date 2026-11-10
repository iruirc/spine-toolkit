#!/usr/bin/env bash
# Says what a project config still needs for the model tiers, and writes it. How setup uses it:
# skills/setup/SKILL.md; the tiers themselves: conventions/task-settings.md → Fields (model_tiers).
#
# Usage: scripts/model-tiers.sh check <config> --runtime <id>
#        scripts/model-tiers.sh apply <config> [--migrate] [--set fast@<id>=<model>]…
# check prints, each only when true and in this order: `sonnet <key>[,<key>…]` — the [MODELS] keys
# whose value is sonnet, in file order — and `tier-missing fast@<id>` — at least one [MODELS] entry
# says fast and [MODEL_TIERS] has no line for that runtime; a tier no key uses needs no model, so a
# config with no fast entry never asks for one. It exits 0 either way. apply edits the config in
# place: --migrate turns every `: sonnet` of [MODELS] into `: fast` and ensures
# `fast@claude-code: sonnet`; --set adds that entry when its fast@<id> is absent and never overwrites
# one. <model> may be `session`: the tier then runs on the session's model, which is a choice, so
# check stops asking for that runtime. A missing [MODEL_TIERS] line goes directly above the first
# [MODELS] line (at the end of the file when there is none); otherwise entries are appended inside
# the existing brackets, and a trailing # comment stays.
# Exit: 0; 1 when the config cannot be read or written (one `model-tiers: ` line on stderr, the file
# as it was); 2 on a usage error, with the usage line.
#
# Lines are read as resolve-settings.sh reads them: `[FIELD] = [value]` at column 0, so a
# commented-out line is never edited.
set -euo pipefail

exec python3 - "$@" <<'PY'
import os, re, sys, tempfile

USAGE = ("usage: model-tiers.sh check <config> --runtime <id> | "
         "apply <config> [--migrate] [--set fast@<id>=<model>]")
FIELD = re.compile(r'^\[([A-Z_]+)\]\s*=\s*\[([^\]]*)\](.*)$')
ENTRY = re.compile(r'([A-Za-z]+)@([A-Za-z0-9-]+)\s*:\s*(\S+)')
RUNTIME = re.compile(r'[a-z0-9-]+')
TOKEN = re.compile(r'[A-Za-z0-9][A-Za-z0-9._:/+-]*')
SET = re.compile(r'fast@([a-z0-9-]+)=(.+)', re.S)


def usage(msg):
    print("model-tiers: " + msg, file=sys.stderr)
    print(USAGE, file=sys.stderr)
    sys.exit(2)


def parse(argv):
    if len(argv) < 2 or argv[0] not in ("check", "apply"):
        usage("expected check or apply and a config file")
    cmd, path, rest = argv[0], argv[1], argv[2:]
    if not os.path.isfile(path):
        usage("no config file: " + path)
    runtime, migrate, sets, i = None, False, [], 0
    while i < len(rest):
        a = rest[i]
        if cmd == "check" and a == "--runtime" and i + 1 < len(rest):
            runtime, i = rest[i + 1], i + 2
        elif cmd == "apply" and a == "--migrate":
            migrate, i = True, i + 1
        elif cmd == "apply" and a == "--set" and i + 1 < len(rest):
            m = SET.fullmatch(rest[i + 1])
            if not m or not TOKEN.fullmatch(m.group(2)):
                usage("--set takes fast@<id>=<model>, <id> of [a-z0-9-] and <model> a model token: " + rest[i + 1])
            sets.append((m.group(1), m.group(2)))
            i += 2
        else:
            usage("unexpected argument: " + a)
    if cmd == "check" and (runtime is None or not RUNTIME.fullmatch(runtime)):
        usage("check needs --runtime <id> of [a-z0-9-]")
    if cmd == "apply" and not migrate and not sets:
        usage("apply needs --migrate or --set")
    return cmd, path, runtime, migrate, sets


def split_lines(text):
    return re.findall(r'[^\n]*\n|[^\n]+', text)


def entries(inner):
    return [e.strip() for e in inner.split(",") if e.strip()]


class Config:
    def __init__(self, path):
        self.path = path
        with open(path, encoding="utf-8", newline="") as fh:
            self.lines = split_lines(fh.read())

    def fields(self, name):
        """(index, match) of every column-0 [NAME] = [...] line, in file order."""
        out = []
        for i, line in enumerate(self.lines):
            m = FIELD.match(line.rstrip("\r\n"))
            if m and m.group(1) == name:
                out.append((i, m))
        return out

    def sonnet_keys(self):
        keys = []
        for _, m in self.fields("MODELS"):
            for e in entries(m.group(2)):
                key, sep, val = e.partition(":")
                if sep and val.strip().lower() == "sonnet" and key.strip() not in keys:
                    keys.append(key.strip())
        return keys

    def uses_tier(self):
        for _, m in self.fields("MODELS"):
            for e in entries(m.group(2)):
                key, sep, val = e.partition(":")
                if sep and val.strip().lower() == "fast":
                    return True
        return False

    def has_tier(self, runtime):
        for _, m in self.fields("MODEL_TIERS"):
            for e in entries(m.group(2)):
                t = ENTRY.fullmatch(e)
                if t and t.group(1).lower() == "fast" and t.group(2).lower() == runtime:
                    return True
        return False

    def migrate(self):
        for i, m in self.fields("MODELS"):
            segs = m.group(2).split(",")
            segs = [re.sub(r'^(\s*[^:\s][^:]*:\s*)sonnet(\s*)$', r'\1fast\2', s, flags=re.I) for s in segs]
            self.replace_inner(i, m, ",".join(segs))

    def replace_inner(self, i, m, inner):
        line = self.lines[i]
        eol = line[len(line.rstrip("\r\n")):]
        body = line[:len(line) - len(eol)]
        self.lines[i] = body[:m.start(2)] + inner + body[m.end(2):] + eol

    def add_tier(self, runtime, model):
        if self.has_tier(runtime):
            return
        entry = "fast@%s: %s" % (runtime, model)
        found = self.fields("MODEL_TIERS")
        if found:
            i, m = found[0]
            inner = m.group(2)
            if not inner.strip():
                self.replace_inner(i, m, entry)
            else:
                body = inner.rstrip()
                tail = inner[len(body):]
                self.replace_inner(i, m, body + (" " if body.endswith(",") else ", ") + entry + tail)
            return
        target = self.fields("MODELS")
        line = "[MODEL_TIERS] = [%s]" % entry
        if target:
            at = target[0][0]
            old = self.lines[at]
            eol = old[len(old.rstrip("\r\n")):] or "\n"
            self.lines.insert(at, line + eol)
        else:
            eol = "\r\n" if any(l.endswith("\r\n") for l in self.lines) else "\n"
            if self.lines and not self.lines[-1].endswith("\n"):
                self.lines[-1] += eol
            self.lines.append(line + eol)

    def save(self, before):
        after = "".join(self.lines)
        if after == before:
            return
        real = os.path.realpath(self.path)
        fd, tmp = tempfile.mkstemp(prefix=".model-tiers-", dir=os.path.dirname(real))
        try:
            with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
                fh.write(after)
            os.chmod(tmp, os.stat(real).st_mode & 0o7777)
            os.replace(tmp, real)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise


def main():
    cmd, path, runtime, migrate, sets = parse(sys.argv[1:])
    cfg = Config(path)
    if cmd == "check":
        keys = cfg.sonnet_keys()
        if keys:
            print("sonnet " + ",".join(keys))
        if cfg.uses_tier() and not cfg.has_tier(runtime):
            print("tier-missing fast@" + runtime)
        return
    before = "".join(cfg.lines)
    if migrate:
        cfg.migrate()
        cfg.add_tier("claude-code", "sonnet")
    for rid, model in sets:
        cfg.add_tier(rid, model)
    cfg.save(before)


try:
    main()
except (OSError, UnicodeDecodeError) as e:
    # Not a usage error: setup reports an apply that could not write, and says nothing on a usage one.
    print("model-tiers: %s" % e, file=sys.stderr)
    sys.exit(1)
PY
