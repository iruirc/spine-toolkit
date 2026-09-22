#!/usr/bin/env bats
# The security lens is the one look at security a task gets before its code is written, and
# whether it runs follows from what the task touches, never from its size. This suite holds the
# rule's text and every surface that points at it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/security-lens/SKILL.md"
}

# A section's body, heading excluded, up to the next H2.
section() { # $1 = file, $2 = heading text without "## "
  awk -v h="## $2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"
}

@test "the skill exists and resolves under its own name" {
  [ -f "$SKILL" ] || { echo "no skills/security-lens/SKILL.md"; return 1; }
  grep -qxF 'name: security-lens' "$SKILL" || { echo "frontmatter name is not security-lens"; return 1; }
  grep -qF 'Governed by `[SECURITY]` in Task.md and CLAUDE-spine-toolkit.md.' "$SKILL" \
    || { echo "the description does not name the field that governs it"; return 1; }
}

@test "the skill carries its six sections" {
  for h in 'The switch' 'Perimeter' 'Triage' 'Lens' 'Verdict line' 'Review rule'; do
    grep -qxF "## $h" "$SKILL" || { echo "no ## $h"; return 1; }
  done
}

@test "the lens follows the subject, not the size" {
  grep -qF "Whether it runs follows from the task's subject, never from its size." "$SKILL" \
    || { echo "the skill does not state the rule"; return 1; }
}

@test "the switch gives each value what runs, places the lens, and scale moves none of it" {
  s="$(section "$SKILL" 'The switch')"
  for row in '| `auto` (default) |' '| `on` |' '| `off` |' '| FEATURE |' '| BUG |' '| REFACTOR |'; do
    grep -qF "$row" <<<"$s" || { echo "## The switch has no row $row"; return 1; }
  done
  grep -qF '`scale` does not move it.' <<<"$s" || { echo "nothing says scale leaves the field alone"; return 1; }
}

@test "the perimeter is the closed list of eight" {
  s="$(section "$SKILL" 'Perimeter')"
  for item in '**credentials and secrets**' '**network and transport**' '**data at rest**' \
              '**external entry points**' '**authentication and authorization**' '**personal data**' \
              '**permissions and entitlements**' '**third-party dependencies**'; do
    grep -qF -- "- $item" <<<"$s" || { echo "## Perimeter has no item $item"; return 1; }
  done
  [ "$(grep -c '^- \*\*' <<<"$s")" -eq 8 ] || { echo "## Perimeter is not exactly eight items"; return 1; }
  grep -qF 'The list is closed.' <<<"$s" || { echo "nothing closes the list"; return 1; }
}

@test "the triage errs toward the lens" {
  s="$(section "$SKILL" 'Triage')"
  for token in '`touches`' '`perimeter`' '`reason`' '**When in doubt, `touches` is `true`.**' \
               'A triage that returns nothing runs the lens anyway.'; do
    grep -qF "$token" <<<"$s" || { echo "## Triage does not say $token"; return 1; }
  done
}

@test "the lens asks each profile its own question and writes nothing" {
  s="$(section "$SKILL" 'Lens')"
  for row in '| FEATURE |' '| BUG |' '| REFACTOR |'; do
    grep -qF "$row" <<<"$s" || { echo "## Lens has no row $row"; return 1; }
  done
  grep -qF 'It writes no artifact and applies no patch' <<<"$s" || { echo "nothing stops the lens writing"; return 1; }
  grep -qF "assesses this task's perimeter, not the project" <<<"$s" || { echo "the lens is not scoped to the task"; return 1; }
}

@test "the four verdict lines are spelled in the skill" {
  s="$(section "$SKILL" 'Verdict line')"
  for line in '`Security lens: skipped by triage — <reason>`' '`Security lens: off by [SECURITY]`' \
              '`Security lens: no agent on this platform`' '`Security lens: returned nothing`'; do
    grep -qF "$line" <<<"$s" || { echo "## Verdict line has no $line"; return 1; }
  done
}

@test "the review rule fires on a skipped or empty lens, and never blocks" {
  s="$(section "$SKILL" 'Review rule')"
  for token in '`skipped by triage`' '`returned nothing`' '`blocking_findings`' '`[SECURITY] = [on]`'; do
    grep -qF "$token" <<<"$s" || { echo "## Review rule does not say $token"; return 1; }
  done
}

@test "task-scale hands the security question to the skill" {
  f="$ROOT/conventions/task-scale.md"
  grep -qF '`[SECURITY]` and the triage the `security-lens` skill defines' "$f" \
    || { echo "task-scale.md does not point the security question at the skill"; return 1; }
  ! grep -qF 'it is not invoked on a `lite` task' "$f" || { echo "task-scale.md still states the old rule"; return 1; }
}

@test "task-new writes [SECURITY] only on the user's word" {
  f="$ROOT/skills/task-new/SKILL.md"
  grep -qF '`[SECURITY] = [<auto|on|off>]`' "$f" || { echo "task-new never offers [SECURITY]"; return 1; }
  grep -qF 'let the triage decide' "$f" || { echo "task-new does not leave the default to the triage"; return 1; }
}

@test "every prelude runs the triage and the lens by the skill's sections" {
  for p in "$ROOT"/workflows/profile-*.js; do
    for token in 'const securityLens = async (stage, role, agentType) => {' \
                 'its ## Triage section' 'its ## Lens section, the ${PROFILE} row' \
                 "label: 'security:triage'" "...tuning(role, 'light')" \
                 'label: `${stage.toLowerCase()}:security`' "...tuning(role, 'stage')" \
                 'const securityNote = (sec, where) =>'; do
      grep -qF -- "$token" "$p" || { echo "$(basename "$p"): the prelude lacks $token"; return 1; }
    done
  done
}

@test "the prelude errs toward the lens and records why it did not run" {
  p="$ROOT/workflows/profile-feature.js"
  for token in 'Security triage returned nothing; the lens ran anyway.' \
               "'Security lens: off by [SECURITY]'" "'Security lens: no agent on this platform'" \
               '`Security lens: skipped by triage — ${t.reason}`' "'Security lens: returned nothing'"; do
    grep -qF -- "$token" "$p" || { echo "the prelude lacks $token"; return 1; }
  done
}

@test "no role is named inside the prelude" {
  # scripts/lint-workflows.sh would count one as dispatched by all seven scripts.
  pre="$(awk '/^\/\/ ── prelude ─/{f=1} f{print} /^\/\/ ── end prelude ─/{exit}' "$ROOT/workflows/profile-feature.js")"
  [ -n "$pre" ] || { echo "no prelude found"; return 1; }
  ! grep -qE "tuning\('[a-z]+'|lens\('[a-z]+'\)|A\.agents\.[a-z]+" <<<"$pre" || { echo "the prelude names a role"; return 1; }
}

@test "each profile runs the lens at its investigating stage, and before Plan at lite" {
  for pair in feature:Research bug:Diagnose refactor:Analyze; do
    p="$ROOT/workflows/profile-${pair%%:*}.js"; stage="${pair#*:}"
    grep -qF "securityLens('$stage', 'security', lens('security'))" "$p" \
      || { echo "$(basename "$p") does not run the lens at $stage"; return 1; }
    grep -qF "const security = lite() ? await securityLens('Plan', 'security', lens('security')) : null" "$p" \
      || { echo "$(basename "$p") does not run the lens before Plan at lite"; return 1; }
    [ "$(grep -c 'securityNote(security, ' "$p")" -ge 2 ] \
      || { echo "$(basename "$p") does not hand both writers the lens"; return 1; }
  done
}

@test "no other profile runs the lens" {
  for p in review research test epic; do
    ! grep -qF "securityLens('" "$ROOT/workflows/profile-$p.js" || { echo "profile-$p.js runs the lens"; return 1; }
  done
}

@test "every Review brief applies the review rule" {
  for p in feature bug refactor; do
    grep -qF 'Apply the spine-toolkit:security-lens skill, its ## Review rule, to the security verdict line of Research.md, or of Plan.md where there is no Research.md' "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js: Review does not apply the review rule"; return 1; }
  done
}

@test "Method B runs the same lens, from the same skill" {
  for p in feature bug refactor; do
    f="$ROOT/skills/workflow-$p/SKILL.md"
    [ "$(grep -c '`security-lens` skill' "$f")" -ge 3 ] \
      || { echo "workflow-$p does not name the skill at its stage, at lite and at Review"; return 1; }
  done
}

@test "the platform guide says where the security role is dispatched" {
  g="$ROOT/docs/building-a-platform.md"
  grep -qF '`spine-toolkit:security-lens`' "$g" || { echo "the role table does not point at the skill"; return 1; }
  awk '/^Do \*\*not\*\* name that skill `setup`/{f=1} f' "$g" | grep -qF '`security-lens`' \
    || { echo "security-lens is missing from the reserved core skill names"; return 1; }
}
