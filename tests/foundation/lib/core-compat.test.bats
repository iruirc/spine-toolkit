#!/usr/bin/env bats
# A session whose core is older than its platform needs: scripts/lib/core_compat.py reads the
# platform's spine-toolkit range, resolve-settings.sh puts the verdict into json and open, and the
# orchestrator stops on it at step 5.7.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

# py <code>: runs the code with scripts/lib on the path and core_compat's names imported.
py() {
  python3 -c "
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, '$ROOT/scripts/lib')
from core_compat import parse_version, in_range
$1"
}

@test "a version inside >=2.44.0 <3 is in range" {
  run py "print(in_range('2.44.0', '>=2.44.0 <3'), in_range('2.45.1', '>=2.44.0 <3'))"
  [ "$output" = "True True" ] || { echo "$output"; return 1; }
}

@test "a version on either side of >=2.44.0 <3 is out of range" {
  run py "print(in_range('2.43.9', '>=2.44.0 <3'), in_range('3.0.0', '>=2.44.0 <3'))"
  [ "$output" = "False False" ] || { echo "$output"; return 1; }
}

@test "a short version is padded with zeros" {
  run py "print(parse_version('3'), in_range('2.44', '>=2.44.0'))"
  [ "$output" = "(3, 0, 0) True" ] || { echo "$output"; return 1; }
}

@test "= > <= match exactly what they say" {
  run py "print(in_range('2.44.0', '=2.44.0'), in_range('2.44.0', '>2.44.0'), in_range('2.44.0', '<=2.44.0'))"
  [ "$output" = "True False True" ] || { echo "$output"; return 1; }
}

@test "a range or version it cannot read is None, never False" {
  run py "print(in_range('2.44.0', '^2.44.0'), in_range('2.44.0', ''), in_range('2.44.0-rc1', '>=2'), in_range('2.44.0', '>=2.44.0 || <1'))"
  [ "$output" = "None None None None" ] || { echo "$output"; return 1; }
}

# ── core_compat in resolve-settings.sh json ──────────────────────────────────────────────────

# project <platform line>: a project whose config names the platform, and a task in it.
project() {
  PROJ="$BATS_TEST_TMPDIR/proj"
  TASK="$PROJ/Tasks/ACTIVE/042-a-task"
  mkdir -p "$TASK"
  printf '# SPINE.md\n\n## Platform\n\n%s\n' "$1" >"$PROJ/SPINE.md"
  printf '[TASK_TYPE] = [BUG]\n' >"$TASK/Task.md"
}

# platform_dir <name> <range|-> : an installed copy of a platform; - leaves the dependency out.
platform_dir() {
  local dir="$BATS_TEST_TMPDIR/cache/$1-$RANDOM"
  mkdir -p "$dir/.claude-plugin"
  python3 -c '
import json, sys
d = {"name": sys.argv[1], "version": "1.0.0"}
if sys.argv[2] != "-":
    d["dependencies"] = [{"name": "spine-toolkit", "version": sys.argv[2]}]
json.dump(d, open(sys.argv[3], "w"))' "$1" "$2" "$dir/.claude-plugin/plugin.json"
  echo "$dir"
}

# registry <json of plugins>: writes the registry in the shape of the real file.
registry() {
  REG="$BATS_TEST_TMPDIR/registry.json"
  printf '{"version": 2, "plugins": %s}\n' "$1" >"$REG"
}

# user_entry <installPath> <version>
user_entry() { printf '[{"scope": "user", "installPath": "%s", "version": "%s"}]' "$1" "$2"; }

compat() {
  SPINE_PLUGIN_REGISTRY="$REG" "$ROOT/scripts/resolve-settings.sh" json "$TASK" "$@" \
    | python3 -c 'import json,sys; c=json.load(sys.stdin)["core_compat"]; print(c["status"], c["core"], c["installed_core"], c["platform_version"], c["requires"])'
}

core_v() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ROOT/.claude-plugin/plugin.json"; }

@test "a platform whose range takes the session's core is ok" {
  project fixture-platform
  p="$(platform_dir fixture-platform '>=1.0.0 <100')"
  registry "{\"fixture-platform@m\": $(user_entry "$p" 1.0.0), \"spine-toolkit@m\": $(user_entry /x "$(core_v)")}"
  run compat
  [ "$output" = "ok $(core_v) $(core_v) 1.0.0 >=1.0.0 <100" ] || { echo "$output"; return 1; }
}

@test "a session core older than the installed one but in range is lag" {
  project fixture-platform
  p="$(platform_dir fixture-platform '>=1.0.0 <100')"
  registry "{\"fixture-platform@m\": $(user_entry "$p" 1.0.0), \"spine-toolkit@m\": $(user_entry /x 99.0.0)}"
  run compat
  [ "${output%% *}" = lag ] || { echo "$output"; return 1; }
}

@test "a session core newer than the installed one is ok" {
  project fixture-platform
  p="$(platform_dir fixture-platform '>=0.0.1 <100')"
  registry "{\"fixture-platform@m\": $(user_entry "$p" 1.0.0), \"spine-toolkit@m\": $(user_entry /x 0.0.1)}"
  run compat
  [ "${output%% *}" = ok ] || { echo "$output"; return 1; }
}

@test "a session core outside the platform's range is incompatible" {
  project fixture-platform
  p="$(platform_dir fixture-platform '>=99.0.0 <100')"
  registry "{\"fixture-platform@m\": $(user_entry "$p" 1.0.0), \"spine-toolkit@m\": $(user_entry /x 99.0.0)}"
  run compat
  [ "${output%% *}" = incompatible ] || { echo "$output"; return 1; }
}

@test "an installed core the registry does not hold leaves an in-range core ok" {
  project fixture-platform
  p="$(platform_dir fixture-platform '>=1.0.0 <100')"
  registry "{\"fixture-platform@m\": $(user_entry "$p" 1.0.0)}"
  run compat
  [ "$output" = "ok $(core_v)  1.0.0 >=1.0.0 <100" ] || { echo "$output"; return 1; }
}

@test "what cannot be read is unknown" {
  project fixture-platform
  good="$(platform_dir fixture-platform '>=1.0.0 <100')"
  expect_unknown() {  # <why> [json args...]
    local why="$1"; shift
    out="$(compat "$@")" || { echo "$why: json failed"; return 1; }
    [ "${out%% *}" = unknown ] || { echo "$why: $out"; return 1; }
  }
  REG="$BATS_TEST_TMPDIR/none.json"; expect_unknown 'no registry file'
  registry 'not json'; printf 'not json' >"$REG"; expect_unknown 'registry not JSON'
  registry "{\"other@m\": $(user_entry "$good" 1.0.0)}"; expect_unknown 'no platform key'
  registry '{"fixture-platform@m": [{"scope": "user", "version": "1.0.0"}]}'; expect_unknown 'no installPath'
  registry "{\"fixture-platform@m\": $(user_entry "$BATS_TEST_TMPDIR/nowhere" 1.0.0)}"; expect_unknown 'no plugin.json'
  p="$(platform_dir fixture-platform -)"
  registry "{\"fixture-platform@m\": $(user_entry "$p" 1.0.0)}"; expect_unknown 'no spine-toolkit dependency'
  p="$(platform_dir fixture-platform '^2.0.0')"
  registry "{\"fixture-platform@m\": $(user_entry "$p" 1.0.0)}"; expect_unknown 'unreadable range'
  registry "{\"fixture-platform@m\": $(user_entry "$good" 1.0.0)}"; expect_unknown 'codex' --runtime codex-cli
  registry "{\"fixture-platform@m\": $(user_entry "$good" 1.0.0), \"fixture-platform@n\": $(user_entry "$good" 1.0.0)}"
  expect_unknown 'two marketplaces'
  registry "{\"fixture-platform@m\": $(user_entry "$good" 1.0.0)}"
  printf '# SPINE.md\n\n## Platform\n\n' >"$PROJ/SPINE.md"; expect_unknown 'empty ## Platform'
}

@test "a project-scoped entry beats the user one" {
  project fixture-platform
  far="$(platform_dir fixture-platform '>=99.0.0')"
  near="$(platform_dir fixture-platform '>=1.0.0 <100')"
  registry "{\"fixture-platform@m\": [{\"scope\": \"user\", \"installPath\": \"$far\", \"version\": \"1.0.0\"}, {\"scope\": \"local\", \"projectPath\": \"$PROJ\", \"installPath\": \"$near\", \"version\": \"1.0.0\"}]}"
  run compat
  [ "${output%% *}" = ok ] || { echo "$output"; return 1; }
}
