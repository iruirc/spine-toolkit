#!/usr/bin/env bats
# A configured project (state C) is asked whether to reconfigure before anything else: the
# language and the platform come from the config, and are asked again only after Overwrite
# (spec: multi-llm milestone 6). Cancel used to discard two answers given for nothing.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/setup/SKILL.md"
}

# One numbered step of the Algorithm block, up to the next numbered step.
algorithm_step() {
  awk -v n="$1" '/^## Algorithm$/{a=1} a && $0 ~ ("^" n "[.] ") {f=1; print; next} f && /^[0-9]+b?[.] / {exit} f' "$SKILL"
}

# Step 4's state C branch, up to state D.
state_c_branch() { awk '/^   STATE C \(already_configured\):/{f=1} /^   STATE D /{exit} f' "$SKILL"; }

line_of() { grep -nF -- "$2" <<<"$1" | head -1 | cut -d: -f1; }

@test "step 0 takes the language from the config in state C" {
  algorithm_step 0 | grep -qF '↓ state C → the config'"'"'s `[LANG]` answers it'
}

@test "step 1 takes the platform from the config in state C" {
  algorithm_step 1 | grep -qF '↓ state C → the config'"'"'s `## Platform` names it'
}

@test "state C falls back to asking when the config lacks the value" {
  algorithm_step 0 | grep -qF 'no `[LANG]` line' || { echo "step 0: no fallback"; return 1; }
  algorithm_step 1 | grep -qF '`<platform-plugin>`' || { echo "step 1: no fallback"; return 1; }
}

@test "the input still beats the config in state C" {
  for n in 0 1; do
    s="$(algorithm_step $n)"
    input="$(line_of "$s" 'in the input')"; c="$(line_of "$s" '↓ state C')"
    [ -n "$input" ] && [ -n "$c" ] && [ "$input" -lt "$c" ] || { echo "step $n: input after state C"; return 1; }
  done
}

@test "state C asks to reconfigure first, then language and platform after Overwrite" {
  b="$(state_c_branch)"
  first="$(line_of "$b" 'auq_reconfigure_toolkit')"
  lang="$(line_of "$b" 'q0')"; plat="$(line_of "$b" 'Platform Discovery')"; mode="$(line_of "$b" 'qM')"
  [ -n "$first" ] && [ -n "$lang" ] && [ -n "$plat" ] && [ -n "$mode" ] || { echo "missing: $first $lang $plat $mode"; return 1; }
  [ "$first" -lt "$lang" ] && [ "$lang" -le "$plat" ] && [ "$plat" -lt "$mode" ]
}

@test "Cancel in state C asks nothing more than step 6d" {
  grep -A1 -F 'Cancel →' <<<"$(state_c_branch)" | tr -s ' \n' ' ' | grep -qF 'language and platform from the config'
}

@test "the state is known before step 0 in state C as well" {
  grep -qF 'F is decided before G, and G before C' "$SKILL"
  grep -qF 'lets F, G and C take the language and the platform from the file' "$SKILL"
}

# Final review: a rename before the questions left a project with SPINE.md.bak only when
# Platform Discovery stopped or the user walked away.
@test "Backup-and-overwrite renames SPINE.md only after the questions" {
  b="$(state_c_branch)"
  bak="$(line_of "$b" 'SPINE.md.bak')"; plat="$(line_of "$b" 'Platform Discovery')"; mode="$(line_of "$b" 'qM')"
  [ -n "$bak" ] && [ "$bak" -gt "$plat" ] && [ "$bak" -gt "$mode" ] || { echo "rename at $bak, discovery at $plat, qM at $mode"; return 1; }
}

@test "a value step 0 or step 1 already asked is not asked again after Overwrite" {
  state_c_branch | tr -s ' \n' ' ' | grep -qF 'nor step 0 or step 1 asked it in this run'
}

# Acceptance of milestone 6: the menu's cursor stood on Overwrite, so Enter alone rewrote SPINE.md.
@test "the reconfigure menu offers Cancel first and Overwrite last" {
  for l in en ru; do
    opts="$(awk '/^## auq_reconfigure_toolkit_options$/{getline; print; exit}' "$ROOT/skills/setup/locales/$l.md")"
    [ "$opts" = "Cancel | Backup-and-overwrite | Overwrite" ] || { echo "$l: $opts"; false; }
  done
  grep -qF '(Cancel / Backup-and-overwrite / Overwrite)' "$ROOT/skills/setup/SKILL.md"
}

@test "state C keeps the project's blocks verbatim, in place" {
  b="$(state_c_branch)"
  for t in 'Agents, EstimationDeltas, DeliveryMode, AILeverage, Paths' \
           'any heading in neither the canonical list nor the mapping' \
           'in place, as state F step c places them' \
           'a block the old file lacks stays the template'"'"'s'; do
    grep -qF -- "$t" <<<"$b" || { echo "state C does not say: $t"; return 1; }
  done
}

@test "state C writes Platform, Stack, Modules and Orchestration anew" {
  state_c_branch | grep -qF 'Platform, Orchestration, Stack and Modules are written anew'
}

@test "state C compares Persona and Rules under the old config's language" {
  b="$(state_c_branch)"
  for t in 'Persona' 'Rules' "rendered with the old config's \`[LANG]\`" \
           '`auq_reconfigure_template_blocks`' 'unchanged → the new template, asked nothing'; do
    grep -qF -- "$t" <<<"$b" || { echo "state C does not say: $t"; return 1; }
  done
}

@test "the state C report names the blocks it kept" {
  algorithm_step 7 | grep -qF '`report_reconfigure_kept_blocks`'
}

@test "the state table says state C keeps the project's blocks" {
  grep -F '| **C · already_configured**' "$SKILL" | grep -qF "keeps the project's blocks"
}

@test "the reconfigure keys exist in both locales with their placeholders" {
  for l in en ru; do
    f="$ROOT/skills/setup/locales/$l.md"
    for k in auq_reconfigure_template_blocks auq_reconfigure_template_blocks_options report_reconfigure_kept_blocks; do
      grep -qx "## $k" "$f" || { echo "$l.md: no $k"; return 1; }
    done
    awk '/^## auq_reconfigure_template_blocks$/{f=1;next} f&&/^## /{exit} f' "$f" | grep -qF '{blocks}' || { echo "$l.md: no {blocks}"; return 1; }
    awk '/^## report_reconfigure_kept_blocks$/{f=1;next} f&&/^## /{exit} f' "$f" | grep -qF '{kept_blocks}' || { echo "$l.md: no {kept_blocks}"; return 1; }
    [ "$(awk '/^## auq_reconfigure_template_blocks_options$/{f=1;next} f&&NF{print;exit}' "$f" | awk -F' \\| ' '{print NF}')" = 2 ] || { echo "$l.md: options are not two"; return 1; }
  done
}

@test "the SPINE.md header lets the project edit its own blocks" {
  h="$(sed -n '1,/^## /p' "$ROOT/templates/spine-md/en.md")"
  ! grep -qF 'Do not edit by hand' <<<"$h" || { echo "header still forbids editing"; return 1; }
  for t in '`## Paths`' 'survive `/setup`' '`/setup` asks before replacing your edits'; do
    grep -qF -- "$t" <<<"$h" || { echo "header does not say: $t"; return 1; }
  done
  grep -qF 'survive `/setup`' "$ROOT/docs/configuration.md" || { echo "docs/configuration.md does not say which blocks survive"; return 1; }
}
