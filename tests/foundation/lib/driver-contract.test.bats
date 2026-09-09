#!/usr/bin/env bats
# The driver contract is prose, and prose drifts from the lint that enforces it.
# These tests bind the two: one compares the convention's vocabulary block against
# the lint's VOCAB literal directly, and the rest check the fixture against the
# vocabulary this file owns. Without this the three copies diverge silently and the
# first symptom is a legal driver rejected, or an illegal one accepted.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  DOC="$ROOT/conventions/driver-contract.md"
  LINT="$ROOT/scripts/lint-driver-manifest.sh"
}

# The 32 capabilities, in the six groups the convention declares. Written out here
# rather than parsed from the doc: a test that reads its subject cannot catch the
# subject losing a line.
ALL_CAPS="launch stop install reset_state
ui_tree find assert screenshot video logs
tap type swipe gesture key
deeplink background permissions alerts push biometrics camera location network_conditions viewport locale webview
a11y_audit visual_baseline performance
record_replay multi_device"

@test "the convention exists" {
  [ -f "$DOC" ]
}

@test "the convention names every capability of the vocabulary" {
  block="$(sed -n '/^<!-- vocabulary:start -->$/,/^<!-- vocabulary:end -->$/p' "$DOC")"
  missing=""
  for cap in $ALL_CAPS; do
    grep -qF "\`$cap\`" <<<"$block" || missing="$missing $cap"
  done
  [ -z "$missing" ] || { echo "capabilities the vocabulary block does not name:$missing"; return 1; }
}

@test "the convention declares exactly 32 capabilities and no more" {
  # Counted from the vocabulary block alone, not the whole document: the prose
  # below it legitimately mentions capability names while explaining them.
  n="$(sed -n '/^<!-- vocabulary:start -->$/,/^<!-- vocabulary:end -->$/p' "$DOC" \
       | grep -oE '`[a-z][a-z0-9_]*`' | sort -u | wc -l | tr -d ' ')"
  [ "$n" -eq 32 ] || { echo "vocabulary block holds $n capabilities, expected 32"; return 1; }
}

@test "the convention's vocabulary and the lint's VOCAB are the same set" {
  # The lint deliberately hardcodes VOCAB rather than parsing the convention (see the
  # lint's own header comment) — so nothing but a test that reads both sides catches
  # them drifting apart. Fails in both directions: a name only in one file is real
  # duplication rotting, not a formatting difference this diff would smooth over.
  conv_caps="$(sed -n '/^<!-- vocabulary:start -->$/,/^<!-- vocabulary:end -->$/p' "$DOC" \
       | grep -oE '`[a-z][a-z0-9_]*`' | tr -d '`' | sort -u)"
  lint_caps="$(sed -n '/^VOCAB = set("""$/,/^"""\.split())$/p' "$LINT" \
       | sed '1d;$d' | tr -s ' \t\n' '\n' | grep -v '^$' | sort -u)"
  only_convention="$(comm -23 <(echo "$conv_caps") <(echo "$lint_caps") | tr '\n' ' ')"
  only_lint="$(comm -13 <(echo "$conv_caps") <(echo "$lint_caps") | tr '\n' ' ')"
  if [ -n "$only_convention" ] || [ -n "$only_lint" ]; then
    echo "in the convention but not the lint's VOCAB: ${only_convention:-none}"
    echo "in the lint's VOCAB but not the convention: ${only_lint:-none}"
    return 1
  fi
}

@test "the convention names all four blocks of a driver manifest" {
  for block in "## Driver" "## Targets" "## Capabilities:" "## Procedure"; do
    grep -qF "$block" "$DOC" || { echo "block not documented: $block"; return 1; }
  done
}

@test "the convention names all four driver states" {
  for state in ok none unavailable incompatible; do
    grep -qF "\`$state\`" "$DOC" || { echo "state not documented: $state"; return 1; }
  done
}

@test "the convention names no real MCP server" {
  # dispatch-vocabulary.test.bats scans conventions/*.md for the retired tool name
  # already; this catches the two servers that motivated the contract, which that
  # guard does not know about.
  hits="$(grep -ioE 'agent-device|claude-in-mobile|mcp__[a-z_]+' "$DOC" | sort -u | tr '\n' ' ')"
  [ -z "$hits" ] || { echo "the convention names a concrete server: $hits"; return 1; }
}

@test "the fixture driver uses only vocabulary the convention declares" {
  fixture="$ROOT/tests/fixtures/fixture-driver/skills/manifest/SKILL.md"
  [ -f "$fixture" ] || { echo "no fixture manifest at $fixture"; return 1; }
  # Every token of every capabilities block, against the list this file owns.
  bad=""
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    grep -qw "$tok" <<<"$ALL_CAPS" || bad="$bad $tok"
  done < <(awk '/^## Capabilities:/{c=1;next} /^## /{c=0} c' "$fixture" | tr -s ' \t' '\n')
  [ -z "$bad" ] || { echo "fixture names capabilities outside the vocabulary:$bad"; return 1; }
}

@test "the fixture driver names no real MCP server" {
  fixture="$ROOT/tests/fixtures/fixture-driver/skills/manifest/SKILL.md"
  hits="$(grep -ioE 'agent-device|claude-in-mobile|mcp__[a-z_]+' "$fixture" | sort -u | tr '\n' ' ')"
  [ -z "$hits" ] || { echo "the fixture names a concrete server: $hits"; return 1; }
}

@test "every workflow with a driving stage points at the driver contract" {
  # Four profiles have a Validation stage that may drive; each has to say what a
  # non-working driver means, and none may say it in its own words — that is how
  # four paragraphs drift into four different rules.
  for wf in feature bug refactor test; do
    f="$ROOT/skills/workflow-$wf/SKILL.md"
    grep -q 'driver-contract' "$f" || { echo "workflow-$wf does not reference the driver contract"; return 1; }
    grep -q 'driver_status' "$f" || { echo "workflow-$wf does not name driver_status"; return 1; }
  done
}

@test "no workflow names an individual driver state" {
  # The states live in the convention and in the validator's digest. A workflow
  # spelling them out is a fifth copy that no test binds to the other four.
  for wf in feature bug refactor test; do
    f="$ROOT/skills/workflow-$wf/SKILL.md"
    hits="$(grep -oE '\bdriver_status: (ok|none|unavailable|incompatible)\b' "$f" | sort -u | tr '\n' ' ')"
    [ -z "$hits" ] || { echo "workflow-$wf spells out a state: $hits"; return 1; }
  done
}

@test "every profile script with a driving Validation stage points at the driver contract" {
  # Method A (the workflow script) carries the prose that actually reaches the validator agent
  # on a scripted run. Method B naming the four causes and Method A staying on the old two-cause
  # story is a silent split: lint-workflows.sh only checks structural parity, and this is a text
  # difference that structural parity cannot see.
  for wf in feature bug refactor test; do
    f="$ROOT/workflows/profile-$wf.js"
    grep -q 'driver-contract' "$f" || { echo "profile-$wf.js does not reference the driver contract"; return 1; }
    grep -q 'driver_status' "$f" || { echo "profile-$wf.js does not name driver_status"; return 1; }
  done
}

@test "every driving surface scopes cause two to a platform inside the driver contract" {
  # No platform declares a `## Driver` block yet, so "no driver resolving at all" is true
  # everywhere: without this clause the release stops driving on every installed project.
  # Method A and Method B both carry it, or the two halves disagree about the release's
  # central compatibility claim.
  for wf in feature bug refactor test; do
    for f in "$ROOT/skills/workflow-$wf/SKILL.md" "$ROOT/workflows/profile-$wf.js"; do
      grep -qE 'declares no .?## Driver.? block' "$f" \
        || { echo "$f: no clause exempting a platform that declares no ## Driver block"; return 1; }
    done
  done
}

@test "every driving profile's VALIDATION schema declares driver_status" {
  # additionalProperties: false — a field the prose asks for and the schema omits is
  # rejected on the scripted path, so the four-way distinction never leaves the agent.
  for wf in feature bug refactor test; do
    f="$ROOT/workflows/profile-$wf.js"
    schema="$(awk '/^const VALIDATION = \{/,/^\}$/' "$f")"
    grep -q 'driver_status' <<<"$schema" \
      || { echo "profile-$wf.js: VALIDATION has no driver_status property"; return 1; }
    for state in ok none unavailable incompatible; do
      grep -qF "'$state'" <<<"$schema" \
        || { echo "profile-$wf.js: the driver_status enum omits $state"; return 1; }
    done
  done
}

@test "every driving profile pushes driver_status into the stage report" {
  # Returned and then dropped is the same as never returned, which is how manual_checks
  # earned its own push.
  for wf in feature bug refactor test; do
    f="$ROOT/workflows/profile-$wf.js"
    grep -q 'result.notes.push(`driver_status' "$f" \
      || { echo "profile-$wf.js: driver_status never reaches result.notes"; return 1; }
  done
}

# The eight drivable surfaces. Written out here rather than parsed from the
# convention: a test that reads its subject cannot catch the subject losing a line.
ALL_SURFACES="ios-simulator ios-device
android-emulator android-device
macos windows linux
browser"

@test "the convention declares exactly the eight surfaces" {
  block="$(sed -n '/^<!-- surfaces:start -->$/,/^<!-- surfaces:end -->$/p' "$DOC")"
  [ -n "$block" ] || { echo "no surfaces block in the convention"; return 1; }
  missing=""
  for s in $ALL_SURFACES; do
    grep -qF "\`$s\`" <<<"$block" || missing="$missing $s"
  done
  [ -z "$missing" ] || { echo "surfaces the convention does not name:$missing"; return 1; }
  n="$(grep -oE '`[a-z][a-z0-9-]*`' <<<"$block" | sort -u | wc -l | tr -d ' ')"
  [ "$n" -eq 8 ] || { echo "surfaces block holds $n names, expected 8"; return 1; }
}

@test "the convention's surfaces and the driver lint's SURFACES are the same set" {
  # Third copy of a list, bound the way the capability vocabulary already is: the
  # lint hardcodes rather than parsing its own specification, so only a test that
  # reads both sides catches them drifting.
  conv="$(sed -n '/^<!-- surfaces:start -->$/,/^<!-- surfaces:end -->$/p' "$DOC" \
       | grep -oE '`[a-z][a-z0-9-]*`' | tr -d '`' | sort -u)"
  lint="$(sed -n '/^SURFACES = set("""$/,/^"""\.split())$/p' "$LINT" \
       | sed '1d;$d' | tr -s ' \t\n' '\n' | grep -v '^$' | sort -u)"
  only_conv="$(comm -23 <(echo "$conv") <(echo "$lint") | tr '\n' ' ')"
  only_lint="$(comm -13 <(echo "$conv") <(echo "$lint") | tr '\n' ' ')"
  if [ -n "$only_conv" ] || [ -n "$only_lint" ]; then
    echo "in the convention but not the lint's SURFACES: ${only_conv:-none}"
    echo "in the lint's SURFACES but not the convention: ${only_lint:-none}"
    return 1
  fi
}
