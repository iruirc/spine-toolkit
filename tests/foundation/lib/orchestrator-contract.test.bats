#!/usr/bin/env bats
# changed: sweep conventions
# The role vocabulary is declared in three places that must agree: the lint that
# validates a platform's manifest, the `agents=` map the orchestrator hands to
# every executor, and the contract doc a third party writes a platform from.
# Drift between them resolves a stage to nothing at dispatch time, which is far
# from where the typo lives.

unescape() { python3 -c 'import sys; print(sys.argv[1].encode("ascii").decode("unicode_escape"))' "$1"; }

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

@test "the outbound contract carries known_failures, a path to the project's registry" {
  grep -qxF 'known_failures=/Users/<user>/App/Tasks/KnownFailures.md' "$SKILL" \
    || { echo "no filled known_failures= line in the contract block"; return 1; }
  para="$(awk '/^`known_failures` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`known_failures\` paragraph in the Outbound Contract"; return 1; }
  for token in 'conventions/known-failures.md' 'resolve-settings.sh json' 'does not exist is an empty registry'; do
    grep -qF -- "$token" <<<"$para" || { echo "the known_failures paragraph does not say $token"; return 1; }
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
  for token in '[SCALE]' 'the project config'"'"'s `[SCALE]` → `full`' '`full`'; do
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
  # pre-flight must not walk Task.md / the project config on its own to find it —
  # both would duplicate what Resolution step 3's resolve-settings.sh call already read.
  SK="$ROOT/skills/orchestrator/SKILL.md"
  preflight="$(awk '/Driver pre-flight\./{r=1} /^## State Detection$/{r=0} r' "$SK")"
  grep -qF 'resolve-settings.sh' <<<"$preflight" \
    || { echo "the pre-flight does not say it reads the resolver's driver field"; return 1; }
  ! grep -qF 'Task.md [DRIVER]' <<<"$preflight" \
    || { echo "the pre-flight still walks Task.md [DRIVER] itself"; return 1; }
  ! grep -qE "(CLAUDE-spine-toolkit\.md|SPINE\.md|project config'?s?) \\[DRIVER\\]" <<<"$preflight" \
    || { echo "the pre-flight still reads the project config itself"; return 1; }
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
  for token in '[WALKTHROUGH]' 'the project config' '`deep`' '`brief`' '`off`'; do
    grep -qF "$token" <<<"$para" \
      || { echo "the walkthrough paragraph never mentions $token"; return 1; }
  done
  # Tokens alone leave the chain unpinned: `deep` occurs four times in this
  # paragraph, so each link is asserted in place rather than by presence.
  grep -qF '`off` when `scale` is `lite`' <<<"$para" \
    || { echo "the paragraph's own chain omits the lite step"; return 1; }
  grep -qF "the project config's \`[WALKTHROUGH]\` → \`deep\`" <<<"$para" \
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
  grep -qF "\`off\` when \`scale\` is \`lite\` → the project config's \`[WALKTHROUGH]\` → \`deep\`" "$SKILL" \
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
  grep -qxF 'budgets={Done.md: 80, Plan.md: 200, Reproduce.md: 120, Review.md: 120, Task.md: 100, Validation.md: 100, words-per-sentence: 30}' "$SKILL" \
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

@test "both artifact checks after a REVIEW that moved the task run at its new path" {
  # The rule lives once, in the budget paragraph; the language check runs at the budget's path.
  para="$(awk '/^\*\*Artifact budget\.\*\*/{f=1} f&&/^On a non-zero exit/{exit} f' "$SKILL")"
  for token in '`moved-to-done`' 'Tasks/DONE/<folder>' 'both checks'; do
    grep -qF -- "$token" <<<"$para" || { echo "the Artifact budget paragraph does not name $token"; return 1; }
  done
  lang="$(awk '/^\*\*Artifact language\.\*\*/{f=1} f&&/^On exit 1/{exit} f' "$SKILL")"
  grep -qF 'at the path the budget measured' <<<"$lang" || { echo "the language check does not share the budget's path"; return 1; }
  if grep -qF 'Tasks/DONE/<folder>' <<<"$lang"; then echo "the language paragraph keeps its own copy of the rule"; return 1; fi
}

@test "an epic's auto Method A range stops at Plan so its steps are measured before they run" {
  # In auto the whole range returns at once; measured after that, a step has already run on the
  # Task.md the measurement exists to fix.
  para="$(awk '/^In `auto` on a Method A range/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  grep -qF 'end_stage=Plan' <<<"$para" || { echo "an epic's range runs Execute before its steps are measured"; return 1; }
  grep -qF 'stage_scope=forward' <<<"$para" || { echo "the second call's scope is not pinned to forward"; return 1; }
}

@test "the budget warning names words-per-sentence and a Task.md entry in both locales" {
  for l in en ru; do
    body="$(awk '/^## warn_budget_unrecognised$/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/orchestrator/locales/$l.md")"
    for token in '`words-per-sentence`' '`Task.md`' '`Plan.md`'; do
      grep -qF -- "$token" <<<"$body" || { echo "$l.md: warn_budget_unrecognised does not name $token"; return 1; }
    done
  done
}

@test "the budgets paragraph names words-per-sentence and the per-key chain" {
  para="$(awk '/^`budgets` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  for token in 'words-per-sentence' 'Task.md'; do
    grep -qF -- "$token" <<<"$para" || { echo "the budgets paragraph does not name $token"; return 1; }
  done
}

@test "both new budget keys exist in both locales" {
  for key in task_doc_anchor_missing warn_budget_unrecognised; do
    for l in en ru; do
      grep -qx "## $key" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md has no $key"; return 1; }
    done
  done
}

@test "every language key exists in both locales" {
  for key in lang_mismatch lang_mismatch_persists lang_mismatch_unowned lang_readers_disagree; do
    for l in en ru; do
      grep -qx "## $key" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md has no $key"; return 1; }
    done
  done
}

@test "the walkthrough is measured at the same boundaries and the file goes back once" {
  para="$(awk '/^\*\*Walkthrough integrity\.\*\*/{f=1;print;next} f&&/^\*\*/{exit} f' "$SKILL")"
  [ -n "$para" ] || { echo "no Walkthrough integrity paragraph in the orchestrator"; return 1; }
  for token in '<core root>/scripts/lint-walkthrough.sh' '`walkthrough_lint_finding` (`{line}`)' '`walkthrough_lint_persists` (`{line}`)' \
               '**once**' 'kind `walkthrough`' '`task-walkthrough` → `## Refreshing`' 'to the lines named' 'Exit 2 is reported' \
               'every folder the language check measures' 'is not sent again' 'the walkthrough goes first'; do
    grep -qF -- "$token" <<<"$para" || { echo "the Walkthrough integrity paragraph does not name $token"; return 1; }
  done
  lang_at="$(grep -n '^\*\*Artifact language\.\*\*' "$SKILL" | cut -d: -f1)"
  here_at="$(grep -n '^\*\*Walkthrough integrity\.\*\*' "$SKILL" | cut -d: -f1)"
  [ "$here_at" -gt "$lang_at" ] || { echo "the paragraph does not follow Artifact language"; return 1; }
  for l in en ru; do
    for key in walkthrough_lint_finding walkthrough_lint_persists; do
      grep -qx "## $key" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md has no $key"; return 1; }
    done
    if grep -q '^## walkthrough_unreachable_' "$ROOT/skills/orchestrator/locales/$l.md"; then echo "$l.md keeps a key nothing sends"; return 1; fi
  done
}

@test "the integrity pass takes the word limit from the contract's budgets, not from the folder" {
  para="$(awk '/^\*\*Walkthrough integrity\.\*\*/{f=1;print;next} f&&/^\*\*/{exit} f' "$SKILL")"
  [ -n "$para" ] || { echo "no Walkthrough integrity paragraph in the orchestrator"; return 1; }
  for token in 'with `--words-per-sentence` taken from the contract'"'"'s `budgets`' 'a `--set budgets.words-per-sentence` included'; do
    grep -qF -- "$token" <<<"$para" || { echo "the Walkthrough integrity paragraph does not say $token"; return 1; }
  done
}

@test "the integrity pass reports a style line and sends the file back only for the other classes" {
  # Style findings reach the writer once, through its own lint run; the rest goes into the report.
  para="$(awk '/^\*\*Walkthrough integrity\.\*\*/{f=1;print;next} f&&/^\*\*/{exit} f' "$SKILL")"
  [ -n "$para" ] || { echo "no Walkthrough integrity paragraph in the orchestrator"; return 1; }
  for token in '`walkthrough_lint_style` (`{line}`)' 'A `style` line never sends the file back' \
               'when a line of any other class is among them' 'name only the lines of the other classes' \
               '`walkthrough_lint_finding` (`{line}`)' '**once**' '`walkthrough_lint_persists` (`{line}`)'; do
    grep -qF -- "$token" <<<"$para" || { echo "the Walkthrough integrity paragraph does not say $token"; return 1; }
  done
  for l in en ru; do
    body="$(awk '/^## walkthrough_lint_style$/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/orchestrator/locales/$l.md")"
    [ -n "$body" ] || { echo "$l.md has no walkthrough_lint_style"; return 1; }
    grep -qF '{line}' <<<"$body" || { echo "$l.md walkthrough_lint_style does not carry {line}"; return 1; }
  done
  grep -qF 'not sent back' <<<"$(awk '/^## walkthrough_lint_style$/{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/orchestrator/locales/en.md")" \
    || { echo "the en walkthrough_lint_style line does not say the file is not sent back"; return 1; }
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
  for token in 'resolve-settings.sh' "→ the project config's \`[MODELS]\` →" '[MODELS]' '.step/' 'warn_tuning_unrecognised' 'Always filled' 'real JSON' 'Model and effort' \
              '`fast` for `light` and `validator`, `session` for every other role' '[MODEL_TIERS]'; do
    grep -qF "$token" <<<"$para" || { echo "the models paragraph does not name $token"; return 1; }
  done
  para="$(awk '/^`effort` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`effort\` paragraph in the Outbound Contract"; return 1; }
  for token in 'resolve-settings.sh' "the project config's \`[EFFORT]\` → \`session\`" '[EFFORT]' 'Always filled' '**Dispatch**'; do
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
  para="$(awk '/^\*\*The dispatch line\*\*/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "Progress reporting never ties a /workflows row to its stage"; return 1; }
  for f in '`manual`' '`<start> → <end>`' 'the new top row in `/workflows`' 'a hand-back or a retry'; do
    grep -qF -- "$f" <<<"$para" || { echo "the dispatch line lost: $f"; return 1; }
  done
}

@test "the contract carries the three validation fields" {
  block="$(section "$SKILL" '## Outbound Contract')"
  for line in 'drive_app=auto|off' 'manual_checks=auto|always' 'phase_verification=proportional|full'; do
    grep -qxF "$line" <<<"$block" || { echo "the contract does not carry '$line'"; return 1; }
  done
}

@test "a report names facts, not a template" {
  block="$(section "$SKILL" '## Progress reporting')"
  grep -qF 'a fact left out is the failure,' <<<"$block" \
    || { echo "the section does not say facts are the contract"; return 1; }
}

@test "the opening block is the hook's, and the reply neither prints nor retells it" {
  para="$(awk '/^\*\*The opening block\*\*/{f=1} /^\*\*The experiment line\*\*/{exit} f' "$SKILL")"
  [ -n "$para" ] || { echo "no opening block paragraph"; return 1; }
  for f in '`PreToolUse` hook' '`hooks/opening-block`' 'resolve-settings.sh open --contract' "the script's header" \
           'Do not print it and do not retell it' 'fill `progress` and `method_reason`' 'there is no block' \
           'At `quiet` the hook prints nothing' '`from → to`' '`user_directive`, verbatim'; do
    grep -qF -- "$f" <<<"$para" || { echo "the opening block lost: $f"; return 1; }
  done
  for f in 'open <task dir> --method' '--run-file' 'in a code block' '`meta.phases[].agent`'; do
    ! grep -qF -- "$f" <<<"$para" || { echo "the reply is still told to write the block: $f"; return 1; }
  done
}

@test "both invoke paragraphs leave the opening block to the hook" {
  for m in 'Method A' 'Method B'; do
    para="$(awk -v h="**$m — invoke.**" 'index($0,h)==1{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
    [ -n "$para" ] || { echo "no $m invoke paragraph"; return 1; }
    grep -qF 'shows the opening block' <<<"$para" || { echo "$m: the call does not show the block"; return 1; }
    ! grep -qF 'goes out before this call' <<<"$para" || { echo "$m: the reply still sends the block"; return 1; }
  done
}

@test "the outbound contract carries what the opening block reads" {
  c="$(section "$SKILL" '## Outbound Contract')"
  for f in 'progress=quiet|normal|live' 'method_reason=""' '`progress`, `method_reason` —' '`progress_override` included' \
           "Method A's \`method_reason\` aside"; do
    grep -qF -- "$f" <<<"$c" || { echo "outbound contract lost: $f"; return 1; }
  done
}

@test "the stage report names each of its facts" {
  para="$(awk '/^\*\*The stage report\*\*/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  for f in 'the stage and its agent' "the artifact's path" 'one-or-two-sentence summary' 'the verdict'; do
    grep -qF -- "$f" <<<"$para" || { echo "the stage report lost: $f"; return 1; }
  done
}

@test "an auto run names its time once, at the close, and quiet moves the method to the final report" {
  para="$(awk '/^\*\*Timing\.\*\*/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  grep -qF 'name it once, at the end' <<<"$para" || { echo "the close lost the run's time"; return 1; }
  d="$(section "$SKILL" '## Dispatch')"
  grep -qF 'state it in the final report instead' <<<"$d" || { echo "quiet no longer names the method"; return 1; }
}

@test "the outbound contract carries walkthrough_check, on, once or off and never auto" {
  grep -qxF 'walkthrough_check=on|once|off' "$SKILL" || { echo "no walkthrough_check= line in the contract block"; return 1; }
  para="$(awk '/^`walkthrough_check` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`walkthrough_check\` paragraph in the Outbound Contract"; return 1; }
  for token in 'resolve-settings.sh json' 'Always filled' '`auto` never reaches the contract' \
               '`task-walkthrough` → `## Check`' 'wherever `walkthrough` is `off`'; do
    grep -qF "$token" <<<"$para" || { echo "the walkthrough_check paragraph does not say $token"; return 1; }
  done
}

@test "the outbound contract carries walkthrough_when, stage or done, and done is the default" {
  grep -qxF 'walkthrough_when=stage|done' "$SKILL" || { echo "no walkthrough_when= line in the contract block"; return 1; }
  [ "$(grep -n '^walkthrough_when=' "$SKILL" | cut -d: -f1)" -eq $(($(grep -n '^walkthrough=' "$SKILL" | cut -d: -f1) + 1)) ] \
    || { echo "the walkthrough_when line does not follow walkthrough="; return 1; }
  para="$(awk '/^`walkthrough_when` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`walkthrough_when\` paragraph in the Outbound Contract"; return 1; }
  for token in 'resolve-settings.sh json' 'Always filled' '`done`, the default' '`stage`'; do
    grep -qF "$token" <<<"$para" || { echo "the walkthrough_when paragraph does not say $token"; return 1; }
  done
}

@test "under walkthrough_when done a stage boundary before Done measures only the history" {
  para="$(awk '/^\*\*Walkthrough integrity\.\*\*/{f=1;print;next} f&&/^\*\*/{exit} f' "$SKILL")"
  [ -n "$para" ] || { echo "no Walkthrough integrity paragraph in the orchestrator"; return 1; }
  for token in '`--history-only`' '`walkthrough_when` is `done`' 'before Done'; do
    grep -qF -- "$token" <<<"$para" || { echo "the Walkthrough integrity paragraph does not say $token"; return 1; }
  done
}

@test "the outbound contract carries plan_check and done_check, on or off and never auto, and no artifact_check" {
  own="$(awk '/^`walkthrough_check` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL" | wc -c)"
  for f in plan_check done_check; do
    grep -qxF "$f=on|off" "$SKILL" || { echo "no $f= line in the contract block"; return 1; }
    para="$(awk -v h="^\`$f\` —" '$0 ~ h {f=1} f{print} f&&/^$/{exit}' "$SKILL")"
    [ -n "$para" ] || { echo "no \`$f\` paragraph in the Outbound Contract"; return 1; }
    for token in 'resolve-settings.sh json' 'Always filled' '`auto` never reaches the contract' \
                 '`artifact-reader` → `## Check`'; do
      grep -qF "$token" <<<"$para" || { echo "the $f paragraph does not say $token"; return 1; }
    done
    [ "$(printf '%s' "$para" | wc -c)" -le "$own" ] || { echo "the $f paragraph outgrew the walkthrough_check one"; return 1; }
  done
  ! grep -q '^artifact_check=' "$SKILL" || { echo "the contract block still carries artifact_check"; return 1; }
  ! grep -q '^`artifact_check` —' "$SKILL" || { echo "the contract still describes artifact_check"; return 1; }
}

@test "the outbound contract carries estimation, estimation_unit and estimation_from, and never auto" {
  grep -qxF 'estimation=on|off' "$SKILL" || { echo "no estimation= line in the contract block"; return 1; }
  grep -qxF 'estimation_unit=agent-run|days|both' "$SKILL" || { echo "no estimation_unit= line in the contract block"; return 1; }
  grep -qxF 'estimation_from=run|task|epic|project|default|scale' "$SKILL" || { echo "no estimation_from= line in the contract block"; return 1; }
  for f in estimation estimation_unit estimation_from; do
    para="$(awk -v h="^\`$f\` —" '$0 ~ h {f=1} f{print} f&&/^$/{exit}' "$SKILL")"
    [ -n "$para" ] || { echo "no \`$f\` paragraph in the Outbound Contract"; return 1; }
    for token in 'resolve-settings.sh json' 'Always filled'; do
      grep -qF "$token" <<<"$para" || { echo "the $f paragraph does not say $token"; return 1; }
    done
  done
  para="$(awk '/^`estimation` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  for token in '`auto` never reaches the contract' '`on` at `scale = full`' '`off` at `lite`'; do
    grep -qF "$token" <<<"$para" || { echo "the estimation paragraph does not say $token"; return 1; }
  done
  para="$(awk '/^`estimation_from` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  for token in 'sources.estimation' '`scale`' '`run`, `task`, `epic`, `project`, `default`'; do
    grep -qF "$token" <<<"$para" || { echo "the estimation_from paragraph does not say $token"; return 1; }
  done
}

@test "the pre-split spelling of the checks is announced with its own key" {
  grep -qF "| \`is the pre-split spelling, read as [PLAN_CHECK] and [DONE_CHECK]\` | \`[ARTIFACT_CHECK]\` | \`warn_artifact_check_pre_split\` |" "$SKILL" \
    || { echo "the warnings table has no row for the pre-split spelling"; return 1; }
  for lang in en ru; do
    L="$ROOT/skills/orchestrator/locales/$lang.md"
    body="$(awk '/^## warn_artifact_check_pre_split$/{p=1;next} /^## /{p=0} p' "$L")"
    [ -n "${body//[[:space:]]/}" ] || { echo "$lang.md carries no warn_artifact_check_pre_split string"; return 1; }
    for token in '[ARTIFACT_CHECK]' '[PLAN_CHECK]' '[DONE_CHECK]'; do
      grep -qF "$token" <<<"$body" || { echo "$lang.md: the announcement does not name $token"; return 1; }
    done
  done
}

@test "the pre-split announcement says to replace the line by hand, not to run /setup" {
  # /setup reaches an existing config only through Overwrite, which resets most fields: it is no way
  # to migrate one line.
  en="$(awk '/^## warn_artifact_check_pre_split$/{p=1;next} /^## /{p=0} p' "$ROOT/skills/orchestrator/locales/en.md")"
  ru="$(awk '/^## warn_artifact_check_pre_split$/{p=1;next} /^## /{p=0} p' "$ROOT/skills/orchestrator/locales/ru.md")"
  grep -qF 'replace the `[ARTIFACT_CHECK] = [X]` line by hand' <<<"$en" || { echo "en.md: $en"; return 1; }
  grep -qF "$(unescape '\u0437\u0430\u043c\u0435\u043d\u0438 \u0432\u0440\u0443\u0447\u043d\u0443\u044e \u0441\u0442\u0440\u043e\u043a\u0443 `[ARTIFACT_CHECK] = [X]`')" <<<"$ru" || { echo "ru.md: $ru"; return 1; }
  for body in "$en" "$ru"; do
    grep -qF '`[PLAN_CHECK] = [X]`' <<<"$body" && grep -qF '`[DONE_CHECK] = [X]`' <<<"$body" \
      || { echo "the announcement does not name the two lines: $body"; return 1; }
    ! grep -qF '/setup' <<<"$body" || { echo "the announcement still points to /setup: $body"; return 1; }
  done
  ! grep -qF '`/setup` rewrites the line as the two' "$ROOT/docs/configuration.md" \
    || { echo "docs/configuration.md still points to /setup"; return 1; }
  tr '\n' ' ' <"$ROOT/docs/configuration.md" | tr -s ' ' | grep -qF 'replace the `[ARTIFACT_CHECK] = [X]` line by hand' \
    || { echo "docs/configuration.md does not say to replace the line by hand"; return 1; }
}

@test "the outbound contract carries manual_checks_check, on or off" {
  grep -qxF 'manual_checks_check=on|off' "$SKILL" || { echo "no manual_checks_check= line in the contract block"; return 1; }
  para="$(awk '/^`manual_checks_check` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`manual_checks_check\` paragraph in the Outbound Contract"; return 1; }
  for token in 'resolve-settings.sh json' 'Always filled' '`manual-checks` → `## Check`'; do
    grep -qF "$token" <<<"$para" || { echo "the manual_checks_check paragraph does not say $token"; return 1; }
  done
  own="$(awk '/^`walkthrough_check` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL" | wc -c)"
  [ "$(printf '%s' "$para" | wc -c)" -le "$own" ] || { echo "the paragraph outgrew the walkthrough_check one"; return 1; }
}

@test "the outbound contract carries manual_checks_style, brief or full" {
  grep -qxF 'manual_checks_style=brief|full' "$SKILL" || { echo "no manual_checks_style= line in the contract block"; return 1; }
  para="$(awk '/^`manual_checks_style` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`manual_checks_style\` paragraph in the Outbound Contract"; return 1; }
  for token in 'resolve-settings.sh json' 'Always filled' '`brief` or `full`'; do
    grep -qF "$token" <<<"$para" || { echo "the manual_checks_style paragraph does not say $token"; return 1; }
  done
  own="$(awk '/^`walkthrough_check` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL" | wc -c)"
  [ "$(printf '%s' "$para" | wc -c)" -le "$own" ] || { echo "the paragraph outgrew the walkthrough_check one"; return 1; }
}

@test "the outbound contract carries manual_checks_pass, per-step or end" {
  grep -qxF 'manual_checks_pass=per-step|end' "$SKILL" || { echo "no manual_checks_pass= line in the contract block"; return 1; }
  para="$(awk '/^`manual_checks_pass` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`manual_checks_pass\` paragraph in the Outbound Contract"; return 1; }
  for token in 'resolve-settings.sh json' 'Always filled' '`per-step`' '`end`' '`Acceptance`'; do
    grep -qF "$token" <<<"$para" || { echo "the manual_checks_pass paragraph does not say $token"; return 1; }
  done
  own="$(awk '/^`walkthrough_check` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL" | wc -c)"
  [ "$(printf '%s' "$para" | wc -c)" -le "$own" ] || { echo "the paragraph outgrew the walkthrough_check one"; return 1; }
}

@test "the outbound contract carries report, auto on or off" {
  grep -qxF 'report=auto|on|off' "$SKILL" || { echo "no report= line in the contract block"; return 1; }
  para="$(awk '/^`report` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`report\` paragraph in the Outbound Contract"; return 1; }
  for token in 'resolve-settings.sh json' 'Always filled' '`auto`' '`task-report`' 'Plan'; do
    grep -qF "$token" <<<"$para" || { echo "the report paragraph does not say $token"; return 1; }
  done
  own="$(awk '/^`walkthrough_check` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL" | wc -c)"
  [ "$(printf '%s' "$para" | wc -c)" -le "$own" ] || { echo "the paragraph outgrew the walkthrough_check one"; return 1; }
}

@test "the outbound contract carries walkthrough_current, measured by the lint's --current" {
  grep -qxF 'walkthrough_current=true|false' "$SKILL" || { echo "no walkthrough_current= line in the contract block"; return 1; }
  para="$(awk '/^`walkthrough_current` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no \`walkthrough_current\` paragraph in the Outbound Contract"; return 1; }
  for token in 'lint-walkthrough.sh --current <task dir>' 'exit 0 is `true`' 'Always filled' \
               'wherever `walkthrough` is `off`' 'JSON boolean' 'a Method B run asks the same script after Done' \
               'a `style` finding does not count there'; do
    grep -qF "$token" <<<"$para" || { echo "the walkthrough_current paragraph does not say $token"; return 1; }
  done
  integrity="$(awk '/^\*\*Walkthrough integrity\.\*\*/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  for token in 'as class `style`' '`--current`, which measures `walkthrough_current`, does not count'; do
    grep -qF "$token" <<<"$integrity" || { echo "the integrity paragraph does not say $token"; return 1; }
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
               '`run_in_background`' '`mcp__*`' 'long_run.stall' '`added` file in a root is shown, never removed' \
               "--task-dir '…/Tasks/*/<task folder>'" 'leftovers_option_remove_added' 'whose `root` is the task folder' 'A path in double quotes' 'A path that ends in `/`' \
               'Act on nothing before the user answers' 'Method B has no watch' 'stage_watch_failed' \
               "status directory is replaced by \`*\`" "'…/Tasks/*/<task folder>'" '--since <now>' \
               'stage-leftovers.sh restore' 'stage-leftovers.sh leave' 'stage-leftovers.sh held' 'again=1' \
               'leftover_tree_again' 'leftovers_option_restore_again' 'leftovers_held' \
               'the `root` of its line' 'When `restore` exits non-zero'; do
    grep -qF -- "$token" <<<"$para" || { echo "the Stage leftovers paragraph does not name $token"; return 1; }
  done
  grep -qF 'stop it with `TaskStop` on its background task' <<<"$para" \
    || { echo "the Stage leftovers paragraph does not say how the orchestrator stops its watch"; return 1; }
  grep -qF 'never through `pkill` or `pgrep`' <<<"$para" \
    || { echo "the Stage leftovers paragraph does not forbid finding a watch by pattern"; return 1; }
  grep -qF "is **Stage leftovers**'s, before \`stage_error_prompt\`" "$SKILL" \
    || { echo "Error mid-range does not hand the failed stage's leftovers to Stage leftovers"; return 1; }
}

# A restore the build undoes after every stage is a loop, and the general rule of a recommended first
# option put restore first: no leftovers option is recommended, unless a file came back the same.
@test "no leftovers option is recommended unless a file came back the same" {
  para="$(awk '/^\*\*Stage leftovers\.\*\*/{f=1} f&&/^\*\*Per-phase commits/{exit} f' "$SKILL")"
  for token in 'carries no suffix `auq_stage_recovery_recommended_suffix`' '`leftovers_option_leave` goes first'; do
    grep -qF -- "$token" <<<"$para" || { echo "the Stage leftovers paragraph does not say $token"; return 1; }
  done
  ! grep -qF 'git -C <root> restore' <<<"$para" || { echo "the orchestrator restores outside stage-leftovers.sh"; return 1; }
}

@test "every leftovers key exists in both locales" {
  for key in leftover_process leftover_tree leftovers_prompt leftovers_option_kill leftovers_option_restore \
             leftovers_option_leave leftovers_option_remove_added stage_call_hung stage_call_hung_option_kill stage_call_hung_option_wait \
             stage_call_hung_option_stop stage_watch_failed leftover_tree_again leftovers_option_restore_again \
             leftovers_held; do
    for l in en ru; do
      grep -qx "## $key" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md has no $key"; return 1; }
    done
  done
}

@test "the task's documents are checked for foreign files before add -A" {
  para="$(awk '/^\*\*The task.s documents\.\*\*/{f=1} f&&/^## /{exit} f' "$SKILL")"
  [ -n "$para" ] || { echo "no task's documents paragraph in the orchestrator"; return 1; }
  for token in 'stage-leftovers.sh foreign' task_docs_foreign_file task_docs_foreign_prompt \
               task_docs_foreign_option_exclude task_docs_foreign_option_remove task_docs_foreign_option_commit_all \
               "':(exclude,literal)<path>'" 'A path in double quotes' 'A path that ends in `/`'; do
    grep -qF -- "$token" <<<"$para" || { echo "the task's documents paragraph does not name $token"; return 1; }
  done
  check="$(grep -bo 'stage-leftovers.sh foreign' <<<"$para" | head -1 | cut -d: -f1)"
  add="$(grep -bo 'add -A X' <<<"$para" | head -1 | cut -d: -f1)"
  [ "$check" -lt "$add" ] || { echo "the foreign check comes after add -A"; return 1; }
  gate="$(grep -bo 'rev-parse` fails' <<<"$para" | head -1 | cut -d: -f1)"
  [ -n "$gate" ] && [ "$gate" -lt "$check" ] \
    || { echo "the foreign check comes before the checks that decide the folder is committed at all"; return 1; }
}

@test "every task-docs foreign key exists in both locales" {
  for key in task_docs_foreign_file task_docs_foreign_prompt task_docs_foreign_option_exclude \
             task_docs_foreign_option_remove task_docs_foreign_option_commit_all; do
    for l in en ru; do
      grep -qx "## $key" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md has no $key"; return 1; }
    done
  done
}

@test "the plugin registers the opening-block hook on the orchestrator's dispatch tools" {
  python3 - "$ROOT/hooks/hooks.json" <<'PY' || return 1
import json, sys
entries = json.load(open(sys.argv[1]))['hooks'].get('PreToolUse', [])
hit = [e for e in entries if e.get('matcher') == 'Workflow|Skill'
       and any(h.get('command', '').endswith('/hooks/opening-block"') for h in e.get('hooks', []))]
sys.exit(0 if hit else 'no PreToolUse hook on Workflow|Skill runs hooks/opening-block')
PY
  [ -x "$ROOT/hooks/opening-block" ] || { echo "hooks/opening-block is not executable"; return 1; }
}

@test "nothing waits for the opening block, which comes out at the dispatch itself" {
  para="$(awk '/^\*\*The experiment line\.\*\*/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  [ -n "$para" ] || { echo "no experiment line paragraph"; return 1; }
  grep -qF 'before the first dispatch, at every `progress` value' <<<"$para" || { echo "$para"; return 1; }
  ! grep -qF 'follows the opening block' <<<"$para" || { echo "the experiment line waits for the block"; return 1; }
  ! grep -qF 'no second opening block' "$SKILL" || { echo "a dispatch in a turn of its own is said to have no block"; return 1; }
}

@test "Resolution step 1 finds the task folder with task-dir.sh and maps every refusal to a key" {
  step="$(awk '/^1\. Validate & find task folder/{f=1} f&&/^2\. /{exit} f' "$SKILL")"
  [ -n "$step" ] || { echo "no step 1"; return 1; }
  grep -qF 'scripts/task-dir.sh' <<<"$step" || { echo "step 1 does not call task-dir.sh"; return 1; }
  grep -qF -- '--from' <<<"$step" || { echo "step 1 does not pass --from"; return 1; }
  # An epic's step: step ids repeat across epics (every epic has a 2.step), so the folder the epic hands over decides.
  grep -qF 'pending_steps' <<<"$step" || { echo "step 1 does not take the task_dir an epic hands over"; return 1; }
  for k in error_task_not_found error_task_ambiguous error_task_outside_tasks; do
    grep -qF "$k" <<<"$step" || { echo "step 1 lacks $k"; return 1; }
    for l in en ru; do
      grep -qx "## $k" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l lacks $k"; return 1; }
    done
  done
}

@test "a task id with no task stops: Routing never creates the task step 1 refuses" {
  routing="$(awk '/^## Routing$/{r=1;next} /^## State Detection$/{r=0} r' "$SKILL")"
  check4="$(awk '/^4\. \*\*Otherwise\*\*/{f=1;print;next} f&&/^[0-9]+\. /{exit} f' <<<"$routing")"
  [ -n "$check4" ] || { echo "no check 4 in Routing"; return 1; }
  # Step 1 answers a missing task with error_task_not_found and dispatches nothing;
  # check 4 must not answer the same request by creating a task nobody asked for.
  ! grep -qF 'task-new' <<<"$check4" || { echo "check 4 still runs task-new"; return 1; }
  # Creating a task stays with the explicit request of check 2.
  grep -E '^2\. \*\*Task management\*\*' <<<"$routing" | grep -qF '`task-new`' \
    || { echo "check 2 no longer routes to task-new"; return 1; }
  # The stop says how to create the task, in every locale.
  for l in en ru; do
    grep -A1 -x '## error_task_not_found' "$ROOT/skills/orchestrator/locales/$l.md" \
      | grep -qF '/task-new' || { echo "locale $l: error_task_not_found does not say how to create the task"; return 1; }
  done
}

@test "the known_failures paragraph says how each method carries it" {
  para="$(awk '/^`known_failures` —/{f=1} f{print} f&&/^$/{exit}' "$SKILL")"
  for token in 'Method A' 'Method B' 'Validation'; do
    grep -qF -- "$token" <<<"$para" || { echo "the known_failures paragraph does not say $token"; return 1; }
  done
}

@test "Method A's result names the fields of failures outside the task" {
  para="$(grep -F '**Method A — reading the result.**' "$SKILL")"
  for token in '`outside_failures`' '`known_failures_cleared`'; do
    grep -qF -- "$token" <<<"$para" || { echo "Method A — reading the result does not name $token"; return 1; }
  done
}
