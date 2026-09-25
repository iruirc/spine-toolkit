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

# A section's body, heading excluded, up to the next H2. $2 carries its own "## ".
section() {
  awk -v h="$2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"
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
  for token in '[SCALE]' '`CLAUDE-spine-toolkit.md` `[SCALE]` → `full`' '`full`'; do
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

@test "the pre-flight takes the driver from the resolver, not by parsing the config itself" {
  # The other half of the guard above: the contract must not name the driver, and the
  # pre-flight must not walk Task.md / CLAUDE-spine-toolkit.md on its own to find it —
  # both would duplicate what Resolution step 3's resolve-settings.sh call already read.
  SK="$ROOT/skills/orchestrator/SKILL.md"
  preflight="$(awk '/Driver pre-flight\./{r=1} /^## State Detection$/{r=0} r' "$SK")"
  grep -qF 'resolve-settings.sh' <<<"$preflight" \
    || { echo "the pre-flight does not say it reads the resolver's driver field"; return 1; }
  ! grep -qF 'Task.md [DRIVER]' <<<"$preflight" \
    || { echo "the pre-flight still walks Task.md [DRIVER] itself"; return 1; }
  ! grep -qF 'CLAUDE-spine-toolkit.md [DRIVER]' <<<"$preflight" \
    || { echo "the pre-flight still reads CLAUDE-spine-toolkit.md itself"; return 1; }
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
  for token in '[WALKTHROUGH]' 'CLAUDE-spine-toolkit.md' '`deep`' '`brief`' '`off`'; do
    grep -qF "$token" <<<"$para" \
      || { echo "the walkthrough paragraph never mentions $token"; return 1; }
  done
  # Tokens alone leave the chain unpinned: `deep` occurs four times in this
  # paragraph, so each link is asserted in place rather than by presence.
  grep -qF '`off` when `scale` is `lite`' <<<"$para" \
    || { echo "the paragraph's own chain omits the lite step"; return 1; }
  grep -qF '`CLAUDE-spine-toolkit.md` `[WALKTHROUGH]` → `deep`' <<<"$para" \
    || { echo "the paragraph's chain does not end at the deep default"; return 1; }
  grep -qF 'Always filled' <<<"$para" \
    || { echo "the paragraph never says the field can be read unconditionally"; return 1; }
  grep -qF 'pre-depth value' <<<"$para" \
    || { echo "the paragraph does not say how a legacy on resolves"; return 1; }
  # The chain continues past a value it cannot use (conventions/task-settings.md), so a paragraph
  # promising `deep` is false for the one case it exists to describe: a project whose config says
  # `brief` under a task file with a typo.
  grep -qF 'Any other value is reported and skipped, and the chain carries on past it' <<<"$para" \
    || { echo "nothing says an unrecognised value falls through to the next source"; return 1; }
  grep -qF 'only a chain that names no usable value anywhere lands on `deep`' <<<"$para" \
    || { echo "the paragraph does not say when deep is actually what lands"; return 1; }
  ! grep -qF 'Any other value resolves to `deep`' <<<"$para" \
    || { echo "the old promise survives beside the new one"; return 1; }
}

@test "scale still moves the walkthrough default, and to deep" {
  grep -qF '`off` when `scale` is `lite` → `CLAUDE-spine-toolkit.md [WALKTHROUGH]` → `deep`' "$SKILL" \
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
    # Named twice: once as the source that decides after the skipped value, once as where to fix
    # it. A string that names it only as the place to fix is one still claiming a depth of its own.
    # Counted rather than grepped, both locales being one paragraph on one line.
    n="$(grep -oF -- '[WALKTHROUGH]' <<<"$body" | wc -l | tr -d ' ')"
    [ "$n" -ge 2 ] \
      || { echo "$lang.md: the announcement never names what decides after the value is skipped"; return 1; }
  done
  ! grep -qF 'so this run writes the `deep` one' "$ROOT/skills/orchestrator/locales/en.md" \
    || { echo "en.md still promises a depth the chain may not land on"; return 1; }
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
  for token in 'lint-artifact-budget.sh --budgets' '[BUDGETS]' 'warn_budget_unrecognised' 'Always filled' 'real JSON'; do
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

@test "the artifact language is measured at the budget's boundaries and each file goes back once" {
  para="$(awk '/^\*\*Artifact language\.\*\*/{f=1} f&&/^\*\*Per-phase commits/{exit} f' "$SKILL")"
  [ -n "$para" ] || { echo "no Artifact language paragraph in the orchestrator"; return 1; }
  for token in 'lint-artifact-lang.sh <task_dir>' 'conventions/artifact-language.md' 'stage_done_prompt' \
               '`auto` Method A range' '`lang_mismatch`' '`lang_mismatch_persists`' '**once**' \
               '`research_agent`' 'names the' 'language goes first' 'before sending either rewrite' \
               '`moved-to-done`' 'Tasks/DONE/<folder>' '`<task_dir>/<step_id>`' '`completed_steps`' '`failed_steps`' \
               '`[TASK_TYPE]` names' 'is not sent again' '`lang_mismatch_unowned`' '`lang_readers_disagree`' \
               'for `Done.md`, `mechanical` for what REVIEW'"'"'s `auto-move` writes' 'quoted logs and messages' "case title" \
               'Exit 0 reports only what the script printed on'; do
    grep -qF -- "$token" <<<"$para" || { echo "the Artifact language paragraph does not name $token"; return 1; }
  done
  for artifact in Research Reproduce Plan Validation OpsChecklist ManualChecks Review ChangesRequested Walkthrough Done Docs; do
    grep -qF "\`$artifact.md\`" <<<"$para" || { echo "no owner for $artifact.md"; return 1; }
  done
}

@test "every language key exists in both locales" {
  for key in lang_mismatch lang_mismatch_persists lang_mismatch_unowned lang_readers_disagree; do
    for l in en ru; do
      grep -qx "## $key" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md has no $key"; return 1; }
    done
  done
}

@test "the walkthrough's history is measured at the same boundaries and the file goes back once" {
  para="$(awk '/^\*\*Walkthrough history\.\*\*/{f=1;print;next} f&&/^\*\*/{exit} f' "$SKILL")"
  [ -n "$para" ] || { echo "no Walkthrough history paragraph in the orchestrator"; return 1; }
  for token in 'lint-walkthrough.sh <task_dir>' '`walkthrough_unreachable_commit`' '`walkthrough_unreachable_persists`' \
               '**once**' 'kind `walkthrough`' '`task-walkthrough` → `## Refreshing`' 'Exit 2 is reported'; do
    grep -qF -- "$token" <<<"$para" || { echo "the Walkthrough history paragraph does not name $token"; return 1; }
  done
  lang_at="$(grep -n '^\*\*Artifact language\.\*\*' "$SKILL" | cut -d: -f1)"
  here_at="$(grep -n '^\*\*Walkthrough history\.\*\*' "$SKILL" | cut -d: -f1)"
  [ "$here_at" -gt "$lang_at" ] || { echo "the paragraph does not follow Artifact language"; return 1; }
  for key in walkthrough_unreachable_commit walkthrough_unreachable_persists; do
    for l in en ru; do
      grep -qx "## $key" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md has no $key"; return 1; }
    done
  done
}

@test "a subagent is told the language in words, first and last" {
  grep -qF 'at the start of the prompt and again as its last' "$SKILL" \
    || { echo "Subagent Context still hands the language over as a bare code"; return 1; }
}

@test "the outbound contract carries models and effort as filled brace maps" {
  grep -qxF 'models={light: sonnet, walkthrough: session, done: session, architect: session, developer: session, tester: session, reviewer: session, refactorer: session, validator: sonnet, security: session, diagnostics: session}' "$SKILL" \
    || { echo "no filled models= line in the Outbound Contract block"; return 1; }
  grep -qxF 'effort={walkthrough: session, done: session, architect: session, developer: session, tester: session, reviewer: session, refactorer: session, validator: session, security: session, diagnostics: session}' "$SKILL" \
    || { echo "no filled effort= line in the Outbound Contract block"; return 1; }
}

@test "models and effort are resolved by the script, not by reading the config" {
  para="$(awk '/^`models` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`models\` paragraph in the Outbound Contract"; return 1; }
  for token in 'resolve-settings.sh' '→ `CLAUDE-spine-toolkit.md` `[MODELS]` →' '[MODELS]' '.step/' 'warn_tuning_unrecognised' 'Always filled' 'real JSON' 'Model and effort' \
              '`sonnet` for `light` and `validator`, `session` for every other role'; do
    grep -qF "$token" <<<"$para" || { echo "the models paragraph does not name $token"; return 1; }
  done
  para="$(awk '/^`effort` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`effort\` paragraph in the Outbound Contract"; return 1; }
  for token in 'resolve-settings.sh' '`CLAUDE-spine-toolkit.md` `[EFFORT]` → `session`' '[EFFORT]' 'Always filled' '**Dispatch**'; do
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
    grep -qF '`walkthrough`' <<<"$body" || { echo "$l: warn_tuning_unrecognised does not list the walkthrough key"; return 1; }
    grep -qF '`session`; ' <<<"$body" || { echo "$l: warn_tuning_unrecognised does not list session among model values"; return 1; }
    ! grep -qF '`platform`' <<<"$body" || { echo "$l: warn_tuning_unrecognised still lists platform"; return 1; }
    body="$(awk '/^## warn_effort_method_b$/{p=1;next} /^## /{p=0} p' "$L")"
    grep -qF '{roles}' <<<"$body" || { echo "$l: warn_effort_method_b lacks {roles}"; return 1; }
  done
}

@test "the stage metrics line is read from the stage's fold, with its tuning" {
  para="$(awk '/^and render `progress_stage_metrics`/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no progress_stage_metrics paragraph"; return 1; }
  grep -qF '`phases[]`' <<<"$para" || { echo "the line is not read from phases[]"; return 1; }
  grep -qF '`tuningText`' <<<"$para" || { echo "the line does not fill {tuning}"; return 1; }
  grep -qF '`cacheWriteText`, `cacheReadText`' <<<"$para" || { echo "the line does not fill the cache columns"; return 1; }
  ! grep -qF 'the record in `agents[]`' <<<"$para" || { echo "the line still quotes one agent"; return 1; }
  for l in en ru; do
    grep -qxF '{tuning} · {out} out · {ctx} ctx · {cacheWrite} cache-w · {cacheRead} cache-r · {tools} tools · {elapsed}' "$ROOT/skills/orchestrator/locales/$l.md" \
      || { echo "$l: progress_stage_metrics does not carry {tuning}"; return 1; }
  done
}

# The host labels a run by meta.name alone, so a manual task's rows are identical.
@test "every Method A dispatch says which stages its /workflows row runs" {
  para="$(awk '/^Under Method A, every `Workflow` call/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "Progress reporting never ties a /workflows row to its stage"; return 1; }
  grep -qF '`progress_dispatch`' <<<"$para" || { echo "the paragraph names no key"; return 1; }
  grep -qF '`manual`' <<<"$para" || { echo "the paragraph does not cover manual"; return 1; }
  for l in en ru; do
    L="$ROOT/skills/orchestrator/locales/$l.md"
    body="$(awk '/^## progress_dispatch$/{p=1;next} /^## /{p=0} p' "$L")"
    grep -qF '{range}' <<<"$body" || { echo "$l: progress_dispatch lacks {range}"; return 1; }
    grep -qF '{workflow}' <<<"$body" || { echo "$l: progress_dispatch lacks {workflow}"; return 1; }
    body="$(awk '/^## progress_open_live_hint$/{p=1;next} /^## /{p=0} p' "$L")"
    grep -qF '{workflow}' <<<"$body" || { echo "$l: progress_open_live_hint lacks {workflow}"; return 1; }
  done
}

@test "the contract carries the three validation fields" {
  block="$(section "$SKILL" '## Outbound Contract')"
  for line in 'drive_app=auto|off' 'manual_checks=auto|always' 'phase_verification=proportional|full'; do
    grep -qxF "$line" <<<"$block" || { echo "the contract does not carry '$line'"; return 1; }
  done
}

@test "the opening block names the settings column and its key" {
  block="$(section "$SKILL" '## Progress reporting')"
  grep -qF 'progress_open_settings' <<<"$block" || { echo "the opening block does not render the settings column"; return 1; }
  grep -qF 'settings_report' <<<"$block" || { echo "nothing says which key sizes the column"; return 1; }
}

@test "both locales carry the settings keys" {
  for l in en ru; do
    f="$ROOT/skills/orchestrator/locales/$l.md"
    grep -qxF '## progress_open_settings' "$f" || { echo "$l.md lacks progress_open_settings"; return 1; }
    grep -qF '{count}' "$f" || { echo "$l.md lacks the {count} placeholder"; return 1; }
  done
}

@test "the outbound contract carries walkthrough_check, on or off and never auto" {
  grep -qxF 'walkthrough_check=on|off' "$SKILL" || { echo "no walkthrough_check= line in the contract block"; return 1; }
  para="$(awk '/^`walkthrough_check` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`walkthrough_check\` paragraph in the Outbound Contract"; return 1; }
  for token in 'resolve-settings.sh json' 'Always filled' '`auto` never reaches the contract' \
               '`task-walkthrough` → `## Check`' 'wherever `walkthrough` is `off`'; do
    grep -qF "$token" <<<"$para" || { echo "the walkthrough_check paragraph does not say $token"; return 1; }
  done
}

@test "the outbound contract carries research_experiment, for research only" {
  contract="$(awk '/^## Outbound Contract$/{c=1;next} /^## Dispatch$/{c=0} c' "$SKILL")"
  para="$(grep -F '**RESEARCH-only field — `research_experiment`.**' <<<"$contract")"
  [ -n "$para" ] || { echo "no research_experiment paragraph in the Outbound Contract"; return 1; }
  for token in 'research_experiment=on|off' '[RESEARCH_EXPERIMENT]' 'an absent line is `off`' \
               '`resolve-settings.sh` does not read it' 'Never infer it' 'workflow-research rejects it'; do
    grep -qF "$token" <<<"$para" || { echo "the paragraph does not say $token"; return 1; }
  done
}

@test "the driver pre-flight runs for an experiment too" {
  routing="$(awk '/^## Routing$/{r=1;next} /^## State Detection$/{r=0} r' "$SKILL")"
  grep -qF 'research_experiment=on' <<<"$routing" \
    || { echo "the pre-flight does not name the experiment"; return 1; }
}

@test "the experiment line is announced at every progress value" {
  grep -qF '`research_experiment_announce`' "$SKILL" || { echo "key not referenced from the body"; return 1; }
  grep -qF '`quiet` included' "$SKILL" || { echo "the line is not said to survive quiet"; return 1; }
  for l in en ru; do
    grep -A1 -x '## research_experiment_announce' "$ROOT/skills/orchestrator/locales/$l.md" \
      | grep -qF '{branch}' || { echo "locale $l: research_experiment_announce lacks {branch}"; return 1; }
  done
}

@test "the orchestrator reads the experiment a research run returns" {
  dispatch="$(awk '/^## Dispatch$/{d=1;next} /^## Progress reporting$/{d=0} d' "$SKILL")"
  grep -qF '`restored: false`' <<<"$dispatch" || { echo "restored is not read"; return 1; }
  grep -qF '`experiment`' <<<"$dispatch" || { echo "experiment is not read"; return 1; }
}

@test "the outbound contract carries security as resolved, auto included" {
  grep -qxF 'security=auto|on|off' "$SKILL" || { echo "no security= line in the contract block"; return 1; }
  para="$(awk '/^`security` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`security\` paragraph in the Outbound Contract"; return 1; }
  for token in 'resolve-settings.sh json' 'Always filled' '`auto` reaches the contract' \
               '`security-lens`' '`scale` does not move it'; do
    grep -qF "$token" <<<"$para" || { echo "the security paragraph does not say $token"; return 1; }
  done
}

@test "what a stage leaves behind is measured on both sides of it and acted on only by the user" {
  para="$(awk '/^\*\*Stage leftovers\.\*\*/{f=1} f&&/^\*\*Per-phase commits/{exit} f' "$SKILL")"
  [ -n "$para" ] || { echo "no Stage leftovers paragraph in the orchestrator"; return 1; }
  for token in 'stage-leftovers.sh snap' 'stage-leftovers.sh diff' 'stage-leftovers.sh kill' 'stage-leftovers.sh watch' \
               '`roots`' '`status: interrupted`' '`TaskStop`' 'stage_error_prompt' \
               '`run_in_background`' '`mcp__*`' 'long_run.stall' '`added` file is shown, never removed' \
               'Act on nothing before the user answers' 'Method B has no watch' \
               "status directory is replaced by \`*\`" "'…/Tasks/*/<task folder>'" '--since <now>'; do
    grep -qF -- "$token" <<<"$para" || { echo "the Stage leftovers paragraph does not name $token"; return 1; }
  done
  grep -qF "is **Stage leftovers**'s, before \`stage_error_prompt\`" "$SKILL" \
    || { echo "Error mid-range does not hand the failed stage's leftovers to Stage leftovers"; return 1; }
}

@test "every leftovers key exists in both locales" {
  for key in leftover_process leftover_tree leftovers_prompt leftovers_option_kill leftovers_option_restore \
             leftovers_option_leave stage_call_hung stage_call_hung_option_kill stage_call_hung_option_wait \
             stage_call_hung_option_stop; do
    for l in en ru; do
      grep -qx "## $key" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md has no $key"; return 1; }
    done
  done
}
