#!/usr/bin/env bash
# Checks a driver plugin's manifest skill against the spine-toolkit driver contract.
# The doctrine, and the vocabulary duplicated below: conventions/driver-contract.md.
#
# The vocabulary lives here as a literal rather than being parsed out of the
# convention: a lint that reads its own specification accepts whatever the
# specification drifted into. driver-contract.test.bats is what holds the two
# copies together.
#
# Usage: lint-driver-manifest.sh <plugin-dir>
# Exit: 0 clean, 1 violations listed on stdout, 2 usage.
set -euo pipefail

plugin="${1:-}"
[ -n "$plugin" ] || { echo "usage: $0 <plugin-dir>" >&2; exit 2; }

python3 - "$plugin" <<'PY'
import json, os, re, sys

plugin = sys.argv[1]
manifest = os.path.join(plugin, "skills", "manifest", "SKILL.md")

VOCAB = set("""
launch stop install reset_state
ui_tree find assert screenshot video logs
tap type swipe gesture key
deeplink background permissions alerts push biometrics camera location
network_conditions viewport locale webview
a11y_audit visual_baseline performance
record_replay multi_device
""".split())

# The eight drivable surfaces. A second literal, hardcoded for the same reason VOCAB
# is: a lint that parses its own specification accepts whatever the specification
# drifted into. driver-contract.test.bats binds this copy to the convention's.
SURFACES = set("""
ios-simulator ios-device
android-emulator android-device
macos windows linux
browser
""".split())

violations = []
def bad(msg): violations.append(msg)

if not os.path.isfile(manifest):
    print(f"no manifest skill at {manifest}")
    sys.exit(1)

lines = open(manifest, encoding="utf-8").read().splitlines()

# Blocks are bounded by the next H2, the way the platform lint bounds its tables:
# an unbounded window reads the following block's rows as this one's and reports
# a malformed row the manifest never wrote.
def block(pred):
    out, inside = [], False
    for ln in lines:
        if ln.startswith("## "):
            inside = pred(ln)
            continue
        if inside:
            out.append(ln)
    return out

driver = block(lambda h: h.strip() == "## Driver")
targets = block(lambda h: h.strip() == "## Targets")

for name, present in (("Driver", any(l.strip() == "## Driver" for l in lines)),
                      ("Targets", any(l.strip() == "## Targets" for l in lines))):
    if not present:
        bad(f"missing block: {name}")

ns_rows = [l for l in driver if re.match(r"^namespace\s*=", l)]
if len(ns_rows) != 1:
    bad(f"expected exactly one 'namespace =' row in ## Driver, found {len(ns_rows)}")
else:
    names = [p.strip() for p in ns_rows[0].split("=", 1)[1].split(",")]
    if not any(names):
        bad("namespace row lists no name")
    seen_ns = set()
    for n in names:
        if not n:
            bad("empty element in the namespace list")
            continue
        if not re.fullmatch(r"[a-z][a-z0-9_-]*", n):
            bad(f"malformed namespace '{n}' (expected lowercase, starting with a letter)")
        if n in seen_ns:
            bad(f"namespace listed twice: {n}")
        seen_ns.add(n)

# Bare surface names, one per line. Order matters here: a row in the retired
# `target = ecosystem` grammar is caught first and reported, because silently taking
# its left half would let a manifest written against the old contract pass while
# meaning something else. Everything with whitespace after that is prose — a surface
# name is a single token, so this needs no rule about how prose may be capitalised.
declared = []
for l in targets:
    t = l.strip()
    if not t:
        continue
    if re.match(r"^[a-z][a-z0-9-]*[ \t]*=", t):
        bad(f"## Targets row carries a right-hand side (the retired 'target = ecosystem' "
            f"grammar); write the surface alone: {t}")
        continue
    if re.search(r"\s", t):
        continue
    if not re.fullmatch(r"[a-z][a-z0-9-]*", t):
        continue
    if t not in SURFACES:
        bad(f"target outside the surface vocabulary: {t}")
        continue
    if t in declared:
        bad(f"target declared twice (the second row is dead): {t}")
    declared.append(t)

if not declared:
    bad("## Targets declares no target")

# Capability blocks, keyed by the target in their heading.
cap_blocks, current = {}, None
for ln in lines:
    if ln.startswith("## "):
        m = re.fullmatch(r"##\s+Capabilities:\s*(\S+)\s*", ln)
        current = m.group(1) if m else None
        if current is not None and current in cap_blocks:
            bad(f"two capabilities blocks for one target: {current}")
        if current is not None:
            cap_blocks.setdefault(current, [])
        continue
    # Every token here is read as a capability, which is why the contract forbids prose
    # in these blocks: a sentence would be reported word by word.
    if current is not None:
        cap_blocks[current] += ln.split()

if not cap_blocks:
    bad("no '## Capabilities: <target>' block")

for t in cap_blocks:
    if t not in declared:
        bad(f"capabilities block for a target '## Targets' does not declare: {t}")
for t in declared:
    if t not in cap_blocks:
        bad(f"declared target with no capabilities block: {t}")

for t, caps in cap_blocks.items():
    for c in caps:
        if c not in VOCAB:
            bad(f"capability outside the vocabulary, in '{t}': {c}")
    seen = set()
    for c in caps:
        if c in seen:
            bad(f"capability listed twice in '{t}': {c}")
        seen.add(c)

# plugin.json: a name to be addressed by, and a constraint that actually constrains.
pj = os.path.join(plugin, ".claude-plugin", "plugin.json")
try:
    data = json.load(open(pj, encoding="utf-8"))
except Exception as e:
    bad(f"cannot read {pj}: {e}")
    data = None

if isinstance(data, dict):
    if not isinstance(data.get("name"), str) or not data["name"]:
        bad(f'cannot read a top-level "name" from {pj}')
    deps = data.get("dependencies")
    if not isinstance(deps, list) or not deps:
        bad("plugin.json declares no dependencies; core must be one of them")
    else:
        core = [d for d in deps if isinstance(d, dict) and d.get("name") == "spine-toolkit"]
        if any(isinstance(d, str) for d in deps):
            bad("string-form dependency is not permitted (it constrains nothing); use "
                '{"name": ..., "version": ...}')
        if not core:
            bad("plugin.json declares no object-form dependency on spine-toolkit")
        elif not core[0].get("version"):
            bad("the spine-toolkit dependency carries no version range")

for v in violations:
    print(v)
sys.exit(1 if violations else 0)
PY

echo "driver manifest OK: $plugin"
