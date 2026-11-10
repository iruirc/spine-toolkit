#!/usr/bin/env bats
# The orchestrator and the skills it loads name Claude Code tools. Outside Claude Code the host
# reads runtimes/<runtime>.md, which maps each of them (spec: multi-llm milestone 2). The runtime
# id is stated once, in the orchestrator's Runtime paragraph, and every place that names a Claude
# tool on the dispatch path points at the map — otherwise Codex reads an instruction it cannot
# follow and improvises.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  ORCH="$ROOT/skills/orchestrator/SKILL.md"
}

# A Russian phrase written as \uXXXX escapes: this file is not a locale, so it carries no Cyrillic.
unescape() { python3 -c 'import sys; print(sys.argv[1].encode("ascii").decode("unicode_escape"))' "$1"; }

@test "the orchestrator states the runtime once" {
  ! grep -q -- '--runtime claude-code' "$ORCH" || { grep -n -- '--runtime claude-code' "$ORCH"; false; }
  grep -qE 'resolve-settings\.sh"? json .*--runtime <runtime>' "$ORCH"
  para="$(grep -m1 '^\*\*Runtime\.\*\*' "$ORCH")"
  [ -n "$para" ]
  grep -qF '`claude-code` in Claude Code' <<<"$para"
  grep -qF '`codex-cli` in Codex CLI' <<<"$para"
  grep -qF 'runtimes/<runtime>.md' <<<"$para"
}

@test "every workflow skill allows a contract as text" {
  for f in "$ROOT"/skills/workflow-*/SKILL.md; do
    grep -qF 'runtimes/<runtime>.md' "$f" || { echo "no runtime map in $f"; false; }
  done
}

@test "dispatch conventions point outside Claude Code to the runtime map" {
  for f in conventions/stage-dispatch.md conventions/agent-tooling.md; do
    grep -qF 'runtimes/<runtime>.md' "$ROOT/$f" || { echo "no runtime map in $f"; false; }
  done
}

@test "the orchestrator loads skills by the runtime map outside Claude Code" {
  grep -qF 'elsewhere per `runtimes/<runtime>.md`' "$ORCH"
  ! grep -qE 'Then invoke the `Skill` tool with the name from the table' "$ORCH"
}

# Codex's workspace-write sandbox refuses the simulator over XPC and keeps .git read-only
# (spec: multi-llm milestone 3, section 1 and 2). The map says what runs outside it and how.
codex_section() { awk -v h="$1" '$0==h{on=1; next} on && /^## /{exit} on' "$ROOT/runtimes/codex-cli.md"; }

@test "the Codex map says which build steps leave the sandbox" {
  sec="$(codex_section '## Builds and the simulator')"
  [ -n "$sec" ] || { echo "no ## Builds and the simulator"; false; }
  for s in 'require_escalated' 'long-run.sh start' 'ManualChecks.md' 'no escalation'; do
    grep -qF -- "$s" <<<"$sec" || { echo "missing: $s"; false; }
  done
}

# Milestone 5: Codex matches a rule by the program's file name (execpolicy/src/policy.rs), and an
# allow rule runs the command outside the sandbox without a question — but only when the first
# word is the program: a shell wrapper with variables or redirections is matched whole and misses.
@test "the Codex map calls Spine's scripts and the platform's build tools by rule, escalating only on refusal" {
  sec="$(codex_section '## Builds and the simulator')"
  for s in '.codex/rules/' 'long-run.sh' 'stage-leftovers.sh' 'without escalation' 'first word' 'bash -lc' '`cd … &&`' 'asks or refuses'; do
    grep -qF -- "$s" <<<"$sec" || { echo "missing: $s"; false; }
  done
  grep -F 'long-run.sh wait' <<<"$sec" | grep -qF 'not permitted' || { echo "wait inside the sandbox is no longer explained"; false; }
}

# Acceptance of milestone 6 (544): Fix and Validation wrapped simctl in a script, the rule saw only
# the interpreter and every call asked; a compiler check (548) wrote its cache under the home folder.
@test "the Codex map forbids wrapping a ruled command and moves a compiler cache to a writable root" {
  sec="$(codex_section '## Builds and the simulator')"
  grep -F 'never inside a script' <<<"$sec" | grep -qF 'another program' || { echo "no wrapper rule"; false; }
  grep -qF 'long-run.sh start -- <interpreter> <script>' <<<"$sec" || { echo "no long-run way for a loop"; false; }
  grep -F 'compiler run outside a build' <<<"$sec" | grep -qF 'no escalation' || { echo "no compiler cache rule"; false; }
}

@test "the Codex map keeps the leftovers skip only for a run without the rules" {
  sec="$(codex_section '## Known limits')"
  grep -F 'ps is not permitted here' <<<"$sec" | grep -qF 'rule' || { echo "skip is not tied to the missing rule"; false; }
}

@test "outside the Codex map no brief tells a stage to escalate" {
  hits="$(grep -rlF 'require_escalated' "$ROOT/conventions" "$ROOT/skills" "$ROOT/workflows" | grep -v '/skills/setup/' || true)"
  [ -z "$hits" ] || { echo "$hits"; false; }
}

@test "the orchestrator checks Spine's Codex settings at the start of a task in Codex only" {
  ORCH="$ROOT/skills/orchestrator/SKILL.md"
  para="$(grep -F 'codex-permissions.sh check' "$ORCH")"
  [ -n "$para" ] || { echo "no check in the orchestrator"; false; }
  for s in 'codex-cli' 'codex_permissions_outdated' 'carries on'; do
    grep -qF -- "$s" <<<"$para" || { echo "missing: $s"; false; }
  done
  for l in en ru; do
    grep -qx '## codex_permissions_outdated' "$ROOT/skills/orchestrator/locales/$l.md" || { echo "no key in $l"; false; }
  done
  grep -qF 'codex-permissions.sh check' "$ROOT/runtimes/codex-cli.md" || { echo "the map does not name the check"; false; }
}

# A field project: one line "settings are missing or out of date" for five items, one of them a root the
# session could already write. Each item now says its fact and what follows from it for this run,
# and the report says the check reads only Spine's own settings.
@test "the orchestrator names each item of the check with its own line" {
  ORCH="$ROOT/skills/orchestrator/SKILL.md"
  para="$(grep -F 'codex-permissions.sh check' "$ORCH")"
  for k in codex_perm_rules codex_perm_rules_outdated codex_perm_menu codex_perm_mcp codex_perm_root_missing codex_perm_root_unlisted codex_perm_root_stale; do
    grep -qF -- "$k" <<<"$para" || { echo "SKILL.md does not map $k"; false; }
    for l in en ru; do
      grep -qx "## $k" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "no $k in $l"; false; }
    done
  done
  for l in en ru; do
    awk '/^## codex_permissions_outdated$/{on=1; next} on && /^## /{exit} on' "$ROOT/skills/orchestrator/locales/$l.md" \
      | grep -qF '{items}' || { echo "$l report lacks the items"; false; }
  done
  awk '/^## codex_permissions_outdated$/{on=1; next} on && /^## /{exit} on' "$ROOT/skills/orchestrator/locales/en.md" \
    | grep -qF "only Spine's" || { echo "en report does not say what the check cannot see"; false; }
  awk '/^## codex_permissions_outdated$/{on=1; next} on && /^## /{exit} on' "$ROOT/skills/orchestrator/locales/ru.md" \
    | grep -qF 'Spine' || { echo "ru report does not say what the check cannot see"; false; }
  grep -qiF 'not escalated' <<<"$para" || { echo "the check may be escalated"; false; }
}

@test "the setup question has a line for an unlisted root" {
  grep -qF '`root <path> unlisted`' "$ROOT/skills/setup/SKILL.md" || { echo "SKILL.md does not map it"; false; }
  for l in en ru; do
    grep -qx '## codex_item_root_unlisted' "$ROOT/skills/setup/locales/$l.md" || { echo "no key in $l"; false; }
  done
}

@test "the SPINE.md template says External packages are writable in Codex and Roots are not" {
  T="$ROOT/templates/spine-md/en.md"
  awk '/^`External packages` may repeat/{on=1} on && /^$/{exit} on' "$T" | grep -qF 'writable_roots' || { echo "External packages paragraph lacks writable_roots"; false; }
  awk '/^`Roots` may repeat/{on=1} on && /^$/{exit} on' "$T" | grep -qF 'read-only in Codex CLI' || { echo "Roots paragraph lacks read-only"; false; }
}

@test "the Codex map says how commits pass the read-only .git" {
  sec="$(codex_section '## Git')"
  [ -n "$sec" ] || { echo "no ## Git"; false; }
  for s in '.codex/rules/spine.rules' 'without `-C`' '`Tasks/`'; do
    grep -qF -- "$s" <<<"$sec" || { echo "missing: $s"; false; }
  done
}

@test "the Codex map's tool table routes long-run.sh" {
  grep -E '^\| [^|]*long-run\.sh' "$ROOT/runtimes/codex-cli.md" | grep -qF 'Builds and the simulator'
}

@test "the Codex map keeps a commit in the plain words the rule matches" {
  sec="$(codex_section '## Git')"
  for s in "-m '<subject>'" 'no `$(…)`' 'heredoc' '`cd … &&`' 'working directory'; do
    grep -qF -- "$s" <<<"$sec" || { echo "missing: $s"; false; }
  done
}

@test "the Codex map says Claude model names read as session" {
  grep -qF '`opus`, `sonnet`, `haiku`, `fable`' "$ROOT/runtimes/codex-cli.md"
  ! grep -qF 'any model name is accepted, and' "$ROOT/runtimes/codex-cli.md"
}

# Acceptance of milestone 6: the shared config's Claude models warned at every task in Codex, and the
# user could not act on it without breaking the config for Claude Code. Setup asks instead of reporting.
@test "setup offers the model tier questions instead of a report" {
  S="$ROOT/skills/setup/SKILL.md"
  grep -F 'warn_model_read_as_session' "$ORCH" | grep -qF 'say nothing at task launch' || { echo "launch still warns"; false; }
  # From the project config the opening block shows the key, and setup offers the migration.
  row="$(grep -F '| `is not a <runtime> model, read as session`' "$ORCH")"
  grep -qF '`<key>: <value> → session`' <<<"$row" || { echo "the row does not point at the opening block: $row"; false; }
  [ -z "$(grep -F 'names it once' <<<"$row")" ] || { echo "the row still says setup names it once"; false; }
  for s in '6e.' 'model-tiers.sh check' 'model-tiers.sh apply' 'auq_models_migrate' 'auq_models_codex_tier' 'report_models_migrated'; do
    grep -qF -- "$s" "$S" || { echo "setup lacks $s"; false; }
  done
  [ -z "$(grep -F 'report_models_read_as_session' "$S")" ] || { echo "setup keeps the old report"; false; }
  for l in en ru; do
    f="$ROOT/skills/setup/locales/$l.md"
    ! grep -qx '## report_models_read_as_session' "$f" || { echo "$l keeps the old report"; false; }
    for k in auq_models_migrate auq_models_migrate_options auq_models_codex_tier auq_models_codex_tier_options report_models_migrated report_models_tier_added report_models_migrated_keys_only; do
      grep -qx "## $k" "$f" || { echo "$l lacks $k"; false; }
    done
  done
}

@test "setup's 6e runs in every state but F" {
  step="$(awk '/^6e\. /{p=1} /^7\. /{p=0} p' "$ROOT/skills/setup/SKILL.md")"
  [ -n "$step" ] || { echo "no step 6e"; false; }
  grep -qF 'state F → skip' <<<"$step"
  grep -qF 'every state but' <<<"$step"
}

@test "setup's Cancel and Keep paths run 6e as well" {
  S="$ROOT/skills/setup/SKILL.md"
  grep -qF 'Cancel on the AUQ in state C runs step 6c and step 6d, then step 6e' "$S"
  grep -qF 'run step 6c and step 6d, then step 6e, with the' "$S"
}

@test "the Codex tier question is asked whenever check reports the missing line" {
  sec="$(awk '/^## Model tiers/{p=1} /^## Migration Algorithm/{p=0} p' "$ROOT/skills/setup/SKILL.md")"
  [ -n "$sec" ] || { echo "no ## Model tiers"; false; }
  grep -qF 'tier-missing fast@codex-cli' <<<"$sec"
  grep -qF 'whatever the state and whatever step 2 was' <<<"$sec"
  [ -z "$(grep -F 'created from the template' <<<"$sec")" ] || { echo "the question is limited to a new config"; false; }
  [ -z "$(grep -F 'Gap left' <<<"$sec")" ] || { echo "the section keeps the gap note"; false; }
}

# A tier no key uses needs no model, and keeping the session's model is an answer: written down,
# so a rerun of setup does not ask again.
@test "the Codex tier question is asked only for a fast key, and its answers are written" {
  sec="$(awk '/^## Model tiers/{p=1} /^## Migration Algorithm/{p=0} p' "$ROOT/skills/setup/SKILL.md")"
  grep -qF 'at least one `fast` entry' <<<"$sec" || { echo "check's condition is not named"; false; }
  grep -qF 'run `check` again' <<<"$sec" || { echo "a Yes does not re-run check"; false; }
  grep -qF -- '--set fast@codex-cli=session' <<<"$sec" || { echo "keep writes nothing"; false; }
  [ -z "$(grep -F 'keep the session'"'"'s model → write nothing' <<<"$sec")" ] || { echo "keep still writes nothing"; false; }
  # In Claude Code a fast with no line may be a default or a 1.11.0 platform, not a choice.
  [ -z "$(grep -F "explicit choice" <<<"$sec")" ] || { echo "the Claude Code case calls the gap a choice"; false; }
  grep -qF '`fast → session`' <<<"$sec" || { echo "the Claude Code case does not name the column"; false; }
  head="$(sed -n '2,20p' "$ROOT/scripts/model-tiers.sh")"
  grep -qF 'at least one [MODELS] entry' <<<"$head" || { echo "model-tiers.sh header: $head"; false; }
  for l in en ru; do
    grep -qF 'fast@codex-cli: session' "$ROOT/skills/setup/locales/$l.md" || { echo "$l: the question does not say what keep writes"; false; }
  done
  grep -qF 'fast@<runtime>: session' "$ROOT/docs/configuration.md" || { echo "docs do not name a session tier line"; false; }
}

# A config setup could not write is reported, never silently left as it was.
@test "an apply that could not write is reported and setup carries on" {
  sec="$(awk '/^## Model tiers/{p=1} /^## Migration Algorithm/{p=0} p' "$ROOT/skills/setup/SKILL.md")"
  grep -qF 'exits 1' <<<"$sec" || { echo "no exit 1 rule"; false; }
  grep -qF 'report_models_not_written' <<<"$sec" || { echo "no report key"; false; }
  for l in en ru; do
    body="$(awk '/^## /{p=($0=="## report_models_not_written")} p' "$ROOT/skills/setup/locales/$l.md")"
    [ -n "$body" ] || { echo "$l lacks report_models_not_written"; false; }
    for s in '{config}' '{reason}'; do grep -qF "$s" <<<"$body" || { echo "$l lacks $s"; false; }; done
  done
}

# Step 7 names every line 6e can leave, and a path that stops before step 7 still prints it.
@test "step 7 names every 6e report, and the stop paths print it first" {
  S="$ROOT/skills/setup/SKILL.md"
  step7="$(awk '/^7\. Render the report/{p=1} /^```$/{p=0} p' "$S")"
  for k in report_models_migrated report_models_tier_added report_models_migrated_keys_only report_models_not_written; do
    grep -qF "\`$k\`" <<<"$step7" || { echo "step 7 lacks $k"; false; }
  done
  [ "$(grep -cF "print the line step 6e names, then stop" "$S")" -ge 2 ] || { echo "a stop path drops 6e's line"; false; }
}

@test "setup derives {tiers} from the line before and after, and names the Claude Code case" {
  sec="$(awk '/^## Model tiers/{p=1} /^## Migration Algorithm/{p=0} p' "$ROOT/skills/setup/SKILL.md")"
  grep -qF 'before-state' <<<"$sec"
  grep -qF 'tier-missing fast@claude-code' <<<"$sec"
  grep -qF 'exits 2' <<<"$sec"
  grep -qF 'report_models_tier_added' <<<"$sec"
}

@test "a Yes to the migration always reports, with or without tiers; an exit 2 covers both applies" {
  sec="$(awk '/^## Model tiers/{p=1} /^## Migration Algorithm/{p=0} p' "$ROOT/skills/setup/SKILL.md")"
  grep -qF 'always `report_models_migrated`' <<<"$sec"
  grep -qF '`report_models_migrated_keys_only`' <<<"$sec"
  grep -qF 'nothing changed → no report line' <<<"$sec"
  grep -qF 'Any `apply` in steps 2 and 3 that exits 2' <<<"$sec"
  for l in en ru; do
    body="$(awk '/^## /{p=($0=="## report_models_migrated_keys_only")} p' "$ROOT/skills/setup/locales/$l.md")"
    grep -qF '{keys}' <<<"$body" || { echo "$l lacks {keys}"; false; }
    ! grep -qF '{tiers}' <<<"$body" || { echo "$l names tiers"; false; }
  done
}

@test "the Codex tier question offers no model list" {
  line="$(awk '/^## /{p=($0=="## auq_models_codex_tier_options")} p && NF && !/^## /' "$ROOT/skills/setup/locales/en.md")"
  [ "$(grep -c '' <<<"$line")" -eq 1 ]
  [ "$(tr '|' '\n' <<<"$line" | grep -c '[^[:space:]]')" -eq 2 ]
}

@test "the orchestrator announces a Claude model read as session" {
  ORCH="$ROOT/skills/orchestrator/SKILL.md"
  grep -F 'model, read as session' "$ORCH" | grep -qF 'warn_model_read_as_session'
  for l in en ru; do
    grep -qx '## warn_model_read_as_session' "$ROOT/skills/orchestrator/locales/$l.md" || { echo "no key in $l"; false; }
  done
}

# Model tiers: the orchestrator says what a tier or a Claude model became, and how to change it.
@test "the orchestrator announces a fast tier with no line" {
  row="$(grep -F 'has no fast@<runtime> in [MODEL_TIERS], read as session' "$ORCH")"
  [ -n "$row" ] || { echo "no row"; false; }
  grep -qF 'warn_model_tier_unset' <<<"$row"
  grep -qF 'say nothing at task launch' <<<"$row"
  for l in en ru; do
    f="$ROOT/skills/orchestrator/locales/$l.md"
    grep -qx '## warn_model_tier_unset' "$f" || { echo "no key in $l"; false; }
    body="$(awk '/^## /{p=($0=="## warn_model_tier_unset")} p' "$f")"
    for s in '{source}' '{entry}' '{runtime}' '`fast@{runtime}: '; do
      grep -qF -- "$s" <<<"$body" || { echo "$l lacks $s"; false; }
    done
  done
  # A Task.md [MODEL_TIERS] is ignored, so the text names the file that is read.
  grep -qF "the project config's \`[MODEL_TIERS]\`" <<<"$(awk '/^## /{p=($0=="## warn_model_tier_unset")} p' "$ROOT/skills/orchestrator/locales/en.md")"
  grep -qF "$(unescape '\u0432 `[MODEL_TIERS]` \u043a\u043e\u043d\u0444\u0438\u0433\u0430 \u043f\u0440\u043e\u0435\u043a\u0442\u0430')" <<<"$(awk '/^## /{p=($0=="## warn_model_tier_unset")} p' "$ROOT/skills/orchestrator/locales/ru.md")"
}

@test "the Claude-model text says what to do" {
  for l in en ru; do
    body="$(awk '/^## /{p=($0=="## warn_model_read_as_session")} p' "$ROOT/skills/orchestrator/locales/$l.md")"
    for s in '`fast`' '[MODEL_TIERS]' '{runtime}'; do
      grep -qF -- "$s" <<<"$body" || { echo "$l lacks $s"; false; }
    done
  done
  # setup migrates the project config only, never a Task.md or a --set: it can add the line, no more.
  en="$(awk '/^## /{p=($0=="## warn_model_read_as_session")} p' "$ROOT/skills/orchestrator/locales/en.md")"
  ru="$(awk '/^## /{p=($0=="## warn_model_read_as_session")} p' "$ROOT/skills/orchestrator/locales/ru.md")"
  grep -qF '`/setup` can add the `[MODEL_TIERS]` line' <<<"$en" || { echo "$en"; false; }
  grep -qF "$(unescape '`/setup` \u043c\u043e\u0436\u0435\u0442 \u0434\u043e\u0431\u0430\u0432\u0438\u0442\u044c \u0441\u0442\u0440\u043e\u043a\u0443 `[MODEL_TIERS]`')" <<<"$ru" || { echo "$ru"; false; }
  [ -z "$(grep -F 'offers to do it' <<<"$en")" ] || { echo "$en"; false; }
  [ -z "$(grep -F "$(unescape '\u043f\u0440\u0435\u0434\u043b\u043e\u0436\u0438\u0442 \u0441\u0434\u0435\u043b\u0430\u0442\u044c')" <<<"$ru")" ] || { echo "$ru"; false; }
}

@test "the tuning warning lists fast" {
  for l in en ru; do
    body="$(awk '/^## /{p=($0=="## warn_tuning_unrecognised")} p' "$ROOT/skills/orchestrator/locales/$l.md")"
    grep -qF '`fast`' <<<"$body" || { echo "$l lacks fast"; false; }
  done
}

@test "the Codex map keeps resolver stderr from the user" {
  sec="$(awk '/^## /{p=($0=="## What the user sees")} p' "$ROOT/runtimes/codex-cli.md")"
  grep -qF "resolver's stderr" <<<"$sec"
  top="$(sed -n '1,/^## Tools/p' "$ROOT/runtimes/codex-cli.md")"
  grep -qF '`fast`' <<<"$top"
  grep -qF '[MODEL_TIERS]' <<<"$top"
}

@test "the orchestrator locales keep the same keys" {
  d="$ROOT/skills/orchestrator/locales"
  diff <(grep '^## ' "$d/en.md" | sort) <(grep '^## ' "$d/ru.md" | sort)
}

# Codex hides every platform's manifest from its skill list (allow_implicit_invocation: false), so
# setup's Platform Discovery found no platform in state C (milestone 3 acceptance, first run).
@test "the Codex map finds installed platforms by their manifest files" {
  row="$(grep -F 'installed skills named `manifest`' "$ROOT/runtimes/codex-cli.md")"
  [ -n "$row" ] || { echo "no row for Platform Discovery"; false; }
  for s in 'plugins/cache/' 'skills/manifest/SKILL.md' 'CODEX_HOME' '`## Roles`' 'driver'; do
    grep -qF -- "$s" <<<"$row" || { echo "missing: $s"; false; }
  done
  grep -m1 '^\*\*Runtime\.\*\*' "$ROOT/skills/setup/SKILL.md" | grep -qF 'finding the installed platforms'
}

# Acceptance of milestone 3, QUICK 534: Codex's Default-mode request_user_input auto-resolves after
# two minutes with an empty answer (tui request_user_input/mod.rs, is_blocking = mode == Plan); a
# stage waiting for the user's sandbox approval looked hung, and the orchestrator ran its build itself.
@test "the Codex map reads an empty menu answer as no answer" {
  row="$(grep -F '`AskUserQuestion`' "$ROOT/runtimes/codex-cli.md")"
  for s in 'empty answer' 'two minutes' 'numbered text' 'end your turn'; do
    grep -qF -- "$s" <<<"$row" || { echo "missing: $s"; false; }
  done
}

# Acceptance of milestone 6 (544, 545, setup): the model wrote its own options at a FAILED
# validation, reordered setup's menu as text and swapped Skip for an alternative of its own.
@test "the Codex map keeps a question's options exactly as the locale has them" {
  row="$(grep -F '`AskUserQuestion`' "$ROOT/runtimes/codex-cli.md")"
  for s in "exactly the locale's" 'never add, drop, rename, merge or reorder' 'alternative of your own' \
           '`stage_done_prompt`' 'numbered from 1 in the same order'; do
    grep -qF -- "$s" <<<"$row" || { echo "missing: $s"; false; }
  done
  ! grep -qF 'the recommended one first' <<<"$row" || { echo "the fallback still reorders"; false; }
}

@test "the Codex map never takes over a stage that waits for the user" {
  row="$(grep -F 'collaboration.spawn_agent' "$ROOT/runtimes/codex-cli.md" | head -1)"
  for s in 'waiting for the user' 'never interrupt' 'never run its commands yourself'; do
    grep -qF -- "$s" <<<"$row" || { echo "missing: $s"; false; }
  done
}

@test "the Codex map reads a driver's manifest from its plugin cache" {
  row="$(grep -F 'invoke / load a skill' "$ROOT/runtimes/codex-cli.md")"
  grep -qF '<driver>:manifest' <<<"$row" || { echo "no driver manifest in the load row"; false; }
}

@test "the orchestrator says only REVIEW moves a task folder" {
  grep -qF 'Only the REVIEW profile moves a task folder' "$ROOT/skills/orchestrator/SKILL.md"
}

@test "the Codex map sanitizes a driver prefix" {
  M="$ROOT/runtimes/codex-cli.md"
  grep -qF 'mcp__agent_device__' "$M"
  grep -qF '[A-Za-z0-9_]' "$M"
}

# Milestone 7: the orchestrator filtered ALL_TOOLS by words in descriptions, missed every mcp__mobile__ tool and
# warned that the driver had no tools.
@test "the Codex map says where a driver's tools are and to look them up by prefix" {
  M="$ROOT/runtimes/codex-cli.md"
  grep -qF 'ALL_TOOLS' "$M"
  grep -qF 'startsWith("mcp__' "$M"
}

# Milestone 6: panels, step ids and the epic's dispatch in Codex.

@test "the map names each panel agent and the synthesis" {
  MAP="$ROOT/runtimes/codex-cli.md"
  grep -qF '`task_name: "<stage>_<lens>_<task id>"`' "$MAP" || { echo "no lens task_name"; return 1; }
  grep -qF '`diagnose_diagnostics_540`' "$MAP" || { echo "no example"; return 1; }
  grep -qF '`"<stage>_synthesis_<task id>"`' "$MAP" || { echo "no synthesis task_name"; return 1; }
}

@test "the map waits on every parallel panel agent" {
  grep -qF 'spawn every lens first, then `collaboration.wait_agent` on each' "$ROOT/runtimes/codex-cli.md"
}

@test "the map turns a step id into a task_name" {
  MAP="$ROOT/runtimes/codex-cli.md"
  grep -qF 'every character outside `[a-z0-9_]` becomes `_`' "$MAP" || { echo "no rule"; return 1; }
  grep -qF '`research_540_1_step`' "$MAP" || { echo "no example"; return 1; }
}

@test "the map says an epic always pulls in Codex" {
  grep -qF 'An EPIC always returns its steps as `pending_steps`' "$ROOT/runtimes/codex-cli.md"
}

@test "workflow-epic forces pull under codex-cli, whatever the args say" {
  E="$ROOT/skills/workflow-epic/SKILL.md"
  grep -qF '**Four things force pull' "$E" || { echo "not four"; return 1; }
  ! grep -qF 'Three things force pull' "$E" || { echo "still three"; return 1; }
  grep -qF 'And the runtime `codex-cli`' "$E" || { echo "no codex condition"; return 1; }
  grep -A4 '^  \*\*Mode selection' "$E" | grep -qF 'the four forced-pull conditions' || { echo "mode selection"; return 1; }
  grep -A4 '^  \*\*Mode selection' "$E" | grep 'epic_dispatch_mode=push' | grep -qF 'except under the four conditions above' \
    || { echo "push in args still wins"; return 1; }
}

@test "Concurrency: three lenses and the main agent fit" {
  grep -A3 '^- \*\*Concurrency' "$ROOT/runtimes/codex-cli.md" | tr -s ' \n' ' ' | grep -qF 'three lenses and the main agent are four'
}

@test "the map names TEST Analyze's tester too" {
  grep -qF '`analyze_tester_541`' "$ROOT/runtimes/codex-cli.md"
}

# Milestone 7, task 003: a Kotlin UI task touched only *Screen.kt files, so stack-detect never made
# `target` needed, step 5.7 found no resolved value, and developer/tester/validator fell back to the
# bare KMP/JVM rows although SPINE.md said `Target: Android`.
@test "agent resolution reads a fan-out axis from the config even when the task's files did not need it" {
  grep -qF 'even when the task'"'"'s files did not make it needed' "$ROOT/skills/orchestrator/SKILL.md"
}

# Milestone 7: setup's report in Codex told the user to run `/task-new` — Claude Code's syntax.
@test "the Codex map turns a slash command a locale names into the skill the user types in Codex" {
  M="$ROOT/runtimes/codex-cli.md"
  grep -qF '$spine-toolkit:task-new' "$M"
  grep -qF 'the one change' "$M"
}

# Milestone 6: after every Spine update Codex asks to trust its hooks again, though they did not
# change — its fingerprint covers the whole plugin. Spine cannot avoid it; the user is told why.
@test "Known limits and the README say Codex asks to trust the hooks again after an update" {
  sec="$(awk '/^## Known limits$/{on=1; next} on && /^## /{exit} on' "$ROOT/runtimes/codex-cli.md")"
  grep -qF 'Hooks need review' <<<"$sec" || { echo "Known limits does not name it"; false; }
  grep -qF 'trusted_content_hash' <<<"$sec" || { echo "Known limits does not say why"; false; }
  awk '/^### Codex CLI$/{on=1; next} on && /^##/{exit} on' "$ROOT/README.md" | grep -qF 'Hooks need review' \
    || { echo "README does not name it"; false; }
}

# Milestone 2 found a skill `source-command-setup` in Codex's list and no reason for it: Codex turns a
# plugin command whose body takes no $ARGUMENTS into a skill of its own (checked 2026-11-03, 0.166).
@test "Known limits says why source-command-setup is in Codex's skill list" {
  sec="$(awk '/^## Known limits$/{on=1; next} on && /^## /{exit} on' "$ROOT/runtimes/codex-cli.md")"
  grep -qF 'source-command-setup' <<<"$sec" || { echo "Known limits does not name it"; false; }
  grep -qF '$ARGUMENTS' <<<"$sec" || { echo "Known limits does not say why"; false; }
}
