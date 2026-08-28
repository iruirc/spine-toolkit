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
  # One ecosystem's languages, frameworks and tooling. `mobile MCP` is deliberately
  # absent: it drives an app on either mobile ecosystem, and `mobile_mcp` is core's
  # own config key for whether a stage may reach for it at all.
  VOCAB='\b(swift|swiftui|uikit|appkit|objective-?c|xcode[a-z]*|xcframework|xctest|swiftdata|grdb|swinject|rxswift|mainactor|build_sim|test_sim|nimble|viewinspector|snapshottesting|iphone|ipad|cocoapods|carthage|testflight|bgtask)\b|core data'
}

# `swift-lang` is a core skill's own name, not an ecosystem word; it loses the
# prefix in a later rename and is filtered out until then.
offenders_in() {
  local hits offenders="" f
  for f in "$@"; do
    hits="$(grep -viF 'swift-lang' "$f" | grep -ioE "$VOCAB" | sort -u | tr '\n' ' ')"
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
