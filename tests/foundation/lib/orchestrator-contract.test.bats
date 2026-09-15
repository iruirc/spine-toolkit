#!/usr/bin/env bats
# The role vocabulary is declared in three places that must agree: the lint that
# validates a platform's manifest, the `agents=` map the orchestrator hands to
# every executor, and the contract doc a third party writes a platform from.
# Drift between them resolves a stage to nothing at dispatch time, which is far
# from where the typo lives.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/orchestrator/SKILL.md"
  LINT="$ROOT/scripts/lint-manifest.sh"
  CONTRACT="$ROOT/conventions/platform-contract.md"
  VOCABULARY="$(sed -n 's/^ROLES="\(.*\)"$/\1/p' "$LINT")"
  AGENT_KEYS="$(grep -m1 '^agents={' "$SKILL" \
    | sed 's/^agents={//; s/}$//' | tr ',' '\n' | sed 's/:.*//' | tr -d ' ' | tr '\n' ' ')"
  AGENT_KEYS="${AGENT_KEYS% }"
}

@test "the outbound contract's agents map covers exactly the core role vocabulary" {
  [ -n "$VOCABULARY" ]
  [ "$(tr ' ' '\n' <<<"$AGENT_KEYS" | sort | tr '\n' ' ')" \
    = "$(tr ' ' '\n' <<<"$VOCABULARY" | sort | tr '\n' ' ')" ]
}

@test "the outbound contract's agents map lists roles in vocabulary order" {
  [ "$AGENT_KEYS" = "$VOCABULARY" ]
}

@test "the platform contract names every core role" {
  for role in $VOCABULARY; do
    grep -qw "$role" "$CONTRACT" || {
      echo "role missing from conventions/platform-contract.md: $role"
      return 1
    }
  done
}

@test "the outbound contract carries scale, and its example line is filled" {
  grep -qxF 'scale=lite|full' "$SKILL" || {
    echo "no filled scale= line in the Outbound Contract block"; return 1
  }
}

@test "the scale field documents the whole resolution chain" {
  para="$(awk '/^`scale` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`scale\` paragraph in the Outbound Contract"; return 1; }
  for token in '[SCALE]' '## Scale' '`full`'; do
    case "$para" in
      *"$token"*) ;;
      *) echo "the scale chain does not name $token"; return 1 ;;
    esac
  done
}

@test "the ratchet writes back, refuses to lower, and honours an author's full" {
  grep -q 'scale_escalation' "$SKILL" || { echo "no scale_escalation return field"; return 1; }
  grep -qF '`[SCALE] = [full]`' "$SKILL" || { echo "no write-back into Task.md"; return 1; }
  grep -qi 'never lowered' "$SKILL" || { echo "the one-way rule is not stated"; return 1; }
}

@test "scale reaches the two profiles that have no implementing stage" {
  # Stated rather than omitted: a field that is "sometimes there" is a field
  # every consumer has to test for before reading.
  for p in review research; do
    grep -q 'scale' "$ROOT/skills/workflow-$p/SKILL.md" \
      || { echo "workflow-$p says nothing about scale"; return 1; }
  done
}

@test "the orchestrator documents the driver pre-flight and both its keys" {
  SK="$ROOT/skills/orchestrator/SKILL.md"
  grep -q 'warn_driver_plugin_missing' "$SK" || { echo "key not referenced from the body"; return 1; }
  grep -q 'warn_driver_server_missing' "$SK" || { echo "key not referenced from the body"; return 1; }
  # The check must be conditional, or every run pays for a manifest it will not use.
  # Scoped to the Routing window on purpose: SKILL.md already names drive_app around
  # line 366, explaining why walkthrough travels in the contract and it does not. An
  # unscoped grep is therefore green before this task's edit and tests nothing.
  routing="$(awk '/^## Routing$/{r=1;next} /^## State Detection$/{r=0} r' "$SK")"
  grep -q 'drive_app' <<<"$routing" \
    || { echo "the pre-flight does not name its gate inside ## Routing"; return 1; }
}

@test "the driver does not travel in the Outbound Contract" {
  # D-10 of the spec, as a guard: core holds the driver's name to warn about it and
  # for nothing else. The moment it rides the contract, a workflow script starts
  # gating on it, and core owns a decision that belongs to whoever drives. drive_app
  # is absent for the same reason and stays the reference for this shape.
  SK="$ROOT/skills/orchestrator/SKILL.md"
  contract="$(awk '/^## Outbound Contract$/{c=1;next} /^## Dispatch$/{c=0} c' "$SK")"
  ! grep -qE '\bdriver\b' <<<"$contract" \
    || { echo "the Outbound Contract names the driver; it must not"; return 1; }
}

@test "both driver warning keys exist in both locales with parity" {
  for lang in en ru; do
    L="$ROOT/skills/orchestrator/locales/$lang.md"
    for key in warn_driver_plugin_missing warn_driver_server_missing; do
      grep -q "^## $key\$" "$L" || { echo "$key missing from $lang.md"; return 1; }
    done
  done
}

@test "the pre-flight tries every declared namespace" {
  SK="$ROOT/skills/orchestrator/SKILL.md"
  # Scoped to the Driver pre-flight bullet, not the whole ## Routing section: "every"
  # and "first" both occur elsewhere in Routing already, which would make this pass
  # vacuously even if the pre-flight sentence itself never mentioned trying more than
  # one name. Word-bounded too — "reaches" contains "each".
  preflight="$(awk '/Driver pre-flight\./{r=1} /^## State Detection$/{r=0} r' "$SK")"
  grep -qiE '\beach\b|\bevery\b|first .* present' <<<"$preflight" \
    || { echo "the pre-flight does not say it tries more than one name"; return 1; }
}

@test "the server-missing string names the prefixes tried, plural" {
  for lang in en ru; do
    L="$ROOT/skills/orchestrator/locales/$lang.md"
    body="$(awk '/^## warn_driver_server_missing$/{p=1;next} /^## /{p=0} p' "$L")"
    grep -q '{namespaces}' <<<"$body" \
      || { echo "$lang.md still substitutes a single {namespace}"; return 1; }
  done
}

@test "the outbound contract carries the three-value walkthrough, filled" {
  grep -qxF 'walkthrough=brief|deep|off' "$SKILL" || {
    echo "no filled three-value walkthrough= line in the Outbound Contract block"; return 1
  }
}

@test "the walkthrough field documents the whole resolution chain" {
  para="$(awk '/^`walkthrough` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`walkthrough\` paragraph in the Outbound Contract"; return 1; }
  for token in '[WALKTHROUGH]' '## Reporting' '`deep`' '`brief`' '`off`'; do
    grep -qF "$token" <<<"$para" \
      || { echo "the walkthrough paragraph never mentions $token"; return 1; }
  done
  # Tokens alone leave the chain unpinned: `deep` occurs four times in this
  # paragraph, so each link is asserted in place rather than by presence.
  grep -qF '`off` when `scale` is `lite`' <<<"$para" \
    || { echo "the paragraph's own chain omits the lite step"; return 1; }
  grep -qF '`## Reporting` → `walkthrough` → `deep`' <<<"$para" \
    || { echo "the paragraph's chain does not end at the deep default"; return 1; }
  grep -qF 'Always filled' <<<"$para" \
    || { echo "the paragraph never says the field can be read unconditionally"; return 1; }
  grep -qF 'pre-depth value' <<<"$para" \
    || { echo "the paragraph does not say how a legacy on resolves"; return 1; }
  grep -qF 'Any other value resolves to `deep`' <<<"$para" \
    || { echo "the vocabulary is open: nothing says what an unrecognised value does"; return 1; }
}

@test "scale still moves the walkthrough default, and to deep" {
  grep -qF '`off` when `scale` is `lite` → `CLAUDE-spine-toolkit.md ## Reporting` → `deep`' "$SKILL" \
    || { echo "the scale-to-walkthrough chain still ends at the old default"; return 1; }
}

@test "the unrecognised-value announcement names a key both locales carry" {
  para="$(awk '/^`walkthrough` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  grep -qF 'warn_walkthrough_unrecognised' <<<"$para" \
    || { echo "the paragraph asks for an announcement but names no locale key"; return 1; }
  for lang in en ru; do
    L="$ROOT/skills/orchestrator/locales/$lang.md"
    body="$(awk '/^## warn_walkthrough_unrecognised$/{p=1;next} /^## /{p=0} p' "$L")"
    grep -q '{value}' <<<"$body" \
      || { echo "$lang.md has no warn_walkthrough_unrecognised string substituting {value}"; return 1; }
  done
}

@test "the pre-depth substitution is announced from the one place that sees it" {
  # The writing agent is handed a depth, never the raw value; the orchestrator is
  # the only component that can say a substitution happened at all.
  para="$(awk '/^`walkthrough` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  grep -qF 'warn_walkthrough_pre_depth' <<<"$para" \
    || { echo "nothing announces the pre-depth substitution, so it happens silently"; return 1; }
  for lang in en ru; do
    L="$ROOT/skills/orchestrator/locales/$lang.md"
    body="$(awk '/^## warn_walkthrough_pre_depth$/{p=1;next} /^## /{p=0} p' "$L")"
    [ -n "${body//[[:space:]]/}" ] \
      || { echo "$lang.md carries no warn_walkthrough_pre_depth string"; return 1; }
    for token in '`on`' '`deep`' '`brief`'; do
      grep -qF "$token" <<<"$body" \
        || { echo "$lang.md: the announcement does not name $token"; return 1; }
    done
  done
}

@test "the outbound contract carries budgets as a filled brace map" {
  grep -qxF 'budgets={Done.md: 80, Plan.md: 200, Reproduce.md: 120, Review.md: 120, Task.md: 100, Validation.md: 100}' "$SKILL" \
    || { echo "no filled budgets= line in the Outbound Contract block"; return 1; }
  grep -qF 'The four map-valued fields (`agents`, `budgets`, `models`, `effort`)' "$SKILL" \
    || { echo "the encoding rule does not name all four map-valued fields"; return 1; }
}

@test "the budgets field is resolved by the script, not by reading the config" {
  para="$(awk '/^`budgets` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`budgets\` paragraph in the Outbound Contract"; return 1; }
  for token in 'lint-artifact-budget.sh --budgets' '## Budgets' 'warn_budget_unrecognised' 'Always filled' 'real JSON'; do
    grep -qF "$token" <<<"$para" || { echo "the budgets paragraph does not name $token"; return 1; }
  done
}

@test "the artifact budget runs --task-docs after an epic's Plan, at any scale" {
  para="$(awk '/^\*\*Artifact budget\.\*\*/{f=1} f&&/^On a non-zero exit/{exit} f' "$SKILL")"
  grep -qF -- '--task-docs' <<<"$para" || { echo "the orchestrator never measures a step's Task.md"; return 1; }
  grep -qF 'at any scale' <<<"$para" || { echo "the step check reads as lite-only"; return 1; }
  grep -qF '`task_doc_anchor_missing`' "$SKILL" || { echo "a missing anchor has no announcement"; return 1; }
}

@test "an epic's auto Method A range stops at Plan so its steps are measured before they run" {
  # In auto the whole range returns at once; measured after that, a step has already run on the
  # Task.md the measurement exists to fix.
  para="$(awk '/^In `auto` on a Method A range/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  grep -qF 'end_stage=Plan' <<<"$para" || { echo "an epic's range runs Execute before its steps are measured"; return 1; }
  grep -qF 'stage_scope=forward' <<<"$para" || { echo "the second call's scope is not pinned to forward"; return 1; }
}

@test "both new budget keys exist in both locales" {
  for key in task_doc_anchor_missing warn_budget_unrecognised; do
    for l in en ru; do
      grep -qx "## $key" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md has no $key"; return 1; }
    done
  done
}

@test "the outbound contract carries models and effort as filled brace maps" {
  grep -qxF 'models={light: sonnet, architect: platform, developer: platform, tester: platform, reviewer: platform, refactorer: platform, validator: platform, security: platform, diagnostics: platform}' "$SKILL" \
    || { echo "no filled models= line in the Outbound Contract block"; return 1; }
  grep -qxF 'effort={architect: session, developer: session, tester: session, reviewer: session, refactorer: session, validator: session, security: session, diagnostics: session}' "$SKILL" \
    || { echo "no filled effort= line in the Outbound Contract block"; return 1; }
}

@test "models and effort are resolved by the script, not by reading the config" {
  para="$(awk '/^`models` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`models\` paragraph in the Outbound Contract"; return 1; }
  for token in 'resolve-tuning.sh' '## Models' '[MODELS]' '.step/' 'warn_tuning_unrecognised' 'Always filled' 'real JSON' 'Model and effort'; do
    grep -qF "$token" <<<"$para" || { echo "the models paragraph does not name $token"; return 1; }
  done
  para="$(awk '/^`effort` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`effort\` paragraph in the Outbound Contract"; return 1; }
  for token in 'resolve-tuning.sh' '## Effort' '[EFFORT]' 'Always filled' '**Dispatch**'; do
    grep -qF "$token" <<<"$para" || { echo "the effort paragraph does not name $token"; return 1; }
  done
}

@test "a Method B run announces once that effort does not travel" {
  para="$(awk '/^Under Method B, when the contract.s `effort`/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "Dispatch never says what a Method B run does with effort"; return 1; }
  grep -qF '`warn_effort_method_b`' <<<"$para" || { echo "the paragraph names no key"; return 1; }
  grep -qF '{roles}' <<<"$para" || { echo "the paragraph names no placeholder"; return 1; }
}

@test "both locales carry the two tuning keys with their placeholders" {
  for l in en ru; do
    L="$ROOT/skills/orchestrator/locales/$l.md"
    body="$(awk '/^## warn_tuning_unrecognised$/{p=1;next} /^## /{p=0} p' "$L")"
    grep -qF '{source}' <<<"$body" || { echo "$l: warn_tuning_unrecognised lacks {source}"; return 1; }
    grep -qF '{entry}' <<<"$body" || { echo "$l: warn_tuning_unrecognised lacks {entry}"; return 1; }
    body="$(awk '/^## warn_effort_method_b$/{p=1;next} /^## /{p=0} p' "$L")"
    grep -qF '{roles}' <<<"$body" || { echo "$l: warn_effort_method_b lacks {roles}"; return 1; }
  done
}
