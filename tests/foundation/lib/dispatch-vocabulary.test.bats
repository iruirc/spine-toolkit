#!/usr/bin/env bats
# Core composes the briefs a platform's agents execute. A tool or framework name
# in one of them is not a slip of prose: it is core telling somebody else's
# validator that two Apple-only MCP tools are mandatory, on an Android project, in
# the word "mandatory". That validator either fails a working feature or ignores
# the word, and the gate means nothing either way.
#
# Both dispatch forms carry the same text, so the stage-parity lint is satisfied
# by the two being wrong together. Vocabulary is the only thing that separates
# them, which is what this file reads.

setup() {
  # BATS_TEST_FILENAME, not BASH_SOURCE[0]: bats sources a preprocessed copy of
  # the test file from a tmp dir, so BASH_SOURCE[0] there resolves to the copy.
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  # One ecosystem's languages, frameworks and tooling.
  VOCAB='\b(swift|swiftui|uikit|appkit|objective-?c|xcode[a-z]*|xcframework|xctest|swiftdata|grdb|swinject|rxswift|mainactor|build_sim|test_sim|nimble|viewinspector|snapshottesting|iphone|ipad|cocoapods|carthage|testflight|bgtask)\b|core data'
  # Tooling of *some* ecosystems, not all. Core states the Validation policy; the
  # platform's validator names the tool that carries it out.
  TOOL_VOCAB='mobile[ _-]?mcp'
}

offenders_in() {
  local hits offenders="" f
  for f in "$@"; do
    hits="$(grep -ioE "$VOCAB" "$f" | sort -u | tr '\n' ' ')"
    [ -z "$hits" ] || offenders="$offenders${f#"$ROOT/"}: $hits"$'\n'
  done
  printf '%s' "$offenders"
}

@test "no workflow skill names one ecosystem's tooling" {
  files=("$ROOT"/skills/workflow-*/SKILL.md "$ROOT"/skills/workflow-*/locales/*.md)
  # Seven profiles, each with a SKILL.md; a glob that matched nothing would leave
  # this test green over an empty list.
  [ "${#files[@]}" -ge 7 ] || { echo "scanned ${#files[@]} file(s); the glob went vacuous"; return 1; }
  offenders="$(offenders_in "${files[@]}")"
  [ -z "$offenders" ] || { echo "single-ecosystem vocabulary in a workflow skill:"; echo "$offenders"; return 1; }
}

@test "no profile script names one ecosystem's tooling" {
  files=("$ROOT"/workflows/profile-*.js)
  [ "${#files[@]}" -eq 7 ] || { echo "scanned ${#files[@]} script(s), expected 7"; return 1; }
  offenders="$(offenders_in "${files[@]}")"
  [ -z "$offenders" ] || { echo "single-ecosystem vocabulary in a profile script:"; echo "$offenders"; return 1; }
}

@test "the orchestrator names one ecosystem's tooling nowhere either" {
  # It composes the micro-edit branch's instruction, which never reaches a
  # workflow script or a workflow skill and so is outside both checks above.
  offenders="$(offenders_in "$ROOT/skills/orchestrator/SKILL.md" "$ROOT"/skills/orchestrator/locales/*.md)"
  [ -z "$offenders" ] || { echo "single-ecosystem vocabulary in the orchestrator:"; echo "$offenders"; return 1; }
}

@test "core names no external driving tool anywhere in a brief or a config it writes" {
  files=("$ROOT"/workflows/profile-*.js "$ROOT"/skills/*/SKILL.md "$ROOT"/skills/*/locales/*.md \
         "$ROOT"/skills/*/agents/*.yaml \
         "$ROOT"/templates/claude-toolkit-md/*.md "$ROOT"/templates/task-md/*.md)
  # A glob that matched nothing would leave this test green over an empty list.
  [ "${#files[@]}" -ge 30 ] || { echo "scanned ${#files[@]} file(s); a glob went vacuous"; return 1; }
  offenders=""
  for f in "${files[@]}"; do
    # setup/SKILL.md names the retired key once, to migrate configs off it.
    if [ "$f" = "$ROOT/skills/setup/SKILL.md" ]; then
      # The migration paragraph names the retired key on exactly two lines; a
      # third means the exception has drifted and must be re-read, not widened.
      n="$(grep -ciF 'mobile_mcp' "$f")"
      [ "$n" -eq 2 ] || { echo "setup/SKILL.md names the retired key on $n line(s), expected 2"; return 1; }
      hits="$(grep -viF 'mobile_mcp' "$f" | grep -ioE "$TOOL_VOCAB" | sort -u | tr '\n' ' ')"
    else
      hits="$(grep -ioE "$TOOL_VOCAB" "$f" | sort -u | tr '\n' ' ')"
    fi
    [ -z "$hits" ] || offenders="$offenders${f#"$ROOT/"}: $hits"$'\n'
  done
  [ -z "$offenders" ] || { echo "core names an ecosystem-specific tool:"; echo "$offenders"; return 1; }
}
