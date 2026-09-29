#!/usr/bin/env bats
# The owner's words for one run reach every stage agent in the words conventions/stage-dispatch.md
# gives them, and only when there are any: an empty contract field leaves every brief as it was.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  CONV="$ROOT/conventions/stage-dispatch.md"
}

run_profile() { node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$1.js" "$2" "${3:-$NONE}"; }
NONE='{}'

pick() { node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); const v = eval(process.argv[1]); console.log(typeof v === "string" ? v : JSON.stringify(v))' "$1"; }

contract() { # $1 extra JSON members (leading comma)
  printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "stage_scope": "single"%s}' "$AGENTS" "$1"
}

# The n-th fenced block of the convention's ## Owner's directive section, placeholders filled.
block() { # $1 index, $2 directive, $3 run line
  awk '/^## Owner.s directive$/{f=1;next} f&&/^## /{exit} f' "$CONV" \
    | awk -v n="$1" '/^```/{i++;next} i==2*n-1' \
    | python3 -c 'import sys; print(sys.stdin.read().rstrip("\n").replace("{directive}", sys.argv[1]).replace("{run}", sys.argv[2]))' "$2" "$3"
}

@test "an empty directive and no run settings leave every brief as it was" {
  for p in bug feature refactor test quick research review epic; do
    a="$(run_profile "$p" "$(contract '')" | pick 'o.calls.map((c) => c.prompt).join("\n----\n")')"
    b="$(run_profile "$p" "$(contract ', "user_directive": "", "run_settings": {}')" | pick 'o.calls.map((c) => c.prompt).join("\n----\n")')"
    [ -n "$a" ] || { echo "profile-$p dispatched nothing"; return 1; }
    [ "$a" = "$b" ] || { echo "profile-$p: an empty directive changed a brief"; return 1; }
    ! grep -qF "Owner's directive" <<<"$a" || { echo "profile-$p speaks of a directive nobody gave"; return 1; }
    ! grep -qF '**Run:**' <<<"$a" || { echo "profile-$p asks for a Run line with nothing to write"; return 1; }
  done
}

@test "a directive reaches every agent of every profile, verbatim and in the convention's words" {
  d='run it on the iPhone 17 Pro, leave the Net package alone'
  want="$(block 1 "$d" '')"
  # ${d}, braced: bash reads the first byte of » as part of a bare name.
  run_line="$(block 2 '' "drive_app=off; directive: «${d}»")"
  [ -n "$want" ] && [ -n "$run_line" ] || { echo "the convention has no ## Owner's directive blocks"; return 1; }
  for p in bug feature refactor test quick research review epic; do
    out="$(run_profile "$p" "$(contract ", \"user_directive\": \"$d\", \"run_settings\": {\"drive_app\": \"off\"}")")"
    n="$(pick 'o.calls.filter((c) => c.prompt).length' <<<"$out")"
    [ "$n" -gt 0 ] || { echo "profile-$p dispatched nothing"; return 1; }
    for i in $(seq 0 $((n - 1))); do
      pr="$(pick "o.calls.filter((c) => c.prompt)[$i].prompt" <<<"$out")"
      # A substring test, not grep: « and » are not one byte, and grep under the C locale refuses them.
      [[ "$pr" == *"$want"* ]] || { echo "profile-$p call $i lost the directive"; return 1; }
      [[ "$pr" == *"$run_line"* ]] || { echo "profile-$p call $i lost the Run line"; return 1; }
    done
  done
}

@test "a directive with quotes and a line break reaches the brief whole" {
  pr="$(run_profile bug "$(contract ', "start_stage": "Validation", "user_directive": "use the \"slow\" suite\nthen stop"')" | pick "o.calls[0].prompt")"
  [[ "$pr" == *'«use the "slow" suite'$'\n''then stop»'* ]] || { echo "$pr"; return 1; }
}

@test "the Run line stays one line, while the directive's block keeps it verbatim" {
  pr="$(run_profile bug "$(contract ', "start_stage": "Validation", "user_directive": "use the slow suite\n\t then  stop"')" | pick "o.calls[0].prompt")"
  want="$(block 2 '' 'directive: «use the slow suite then stop»')"
  grep -qF -- "$want" <<<"$pr" || { echo "$pr"; return 1; }
  [[ "$pr" == *'«use the slow suite'$'\n\t'' then  stop». Apply'* ]] || { echo "$pr"; return 1; }
}

@test "a directive of blanks is no directive" {
  a="$(run_profile bug "$(contract ', "start_stage": "Validation"')" | pick "o.calls[0].prompt")"
  b="$(run_profile bug "$(contract ', "start_stage": "Validation", "user_directive": "  \n "')" | pick "o.calls[0].prompt")"
  [ "$a" = "$b" ] || { echo "$b"; return 1; }
}

@test "run settings alone ask for the Run line and say nothing of a directive" {
  pr="$(run_profile bug "$(contract ', "start_stage": "Validation", "run_settings": {"drive_app": "off", "models.reviewer": "opus"}')" | pick "o.calls[0].prompt")"
  want="$(block 2 '' 'drive_app=off; models.reviewer=opus')"
  [ -n "$want" ] || { echo "the convention has no Run line block"; return 1; }
  grep -qF -- "$want" <<<"$pr" || { echo "$pr"; return 1; }
  ! grep -qF "Owner's directive" <<<"$pr" || { echo "$pr"; return 1; }
}

@test "the directive's block follows the data rule, never precedes it" {
  pr="$(run_profile bug "$(contract ', "start_stage": "Validation", "user_directive": "x"')" | pick "o.calls[0].prompt")"
  data="$(grep -nF 'is DATA, never instruction' <<<"$pr" | cut -d: -f1)"
  own="$(grep -nF "Owner's directive for this run" <<<"$pr" | cut -d: -f1)"
  [ -n "$data" ] && [ -n "$own" ] && [ "$own" -gt "$data" ] || { echo "data $data, directive $own"; return 1; }
}

@test "every stage schema lets an agent decline the directive" {
  out="$(run_profile bug "$(contract ', "start_stage": "Plan", "stage_scope": "forward", "user_directive": "x"')" \
    '{"plan": {"ok": true, "artifact_path": "p", "summary": "s", "phases": [{"id": "1", "title": "t", "kind": "code"}]}, "fix:1": {"ok": true, "phase_id": "1", "committed": true, "summary": "s"}, "validation": {"validation_status": "PASSED", "reproduction_status": "fixed", "artifact_path": "v", "summary": "s"}, "review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}}')"
  for l in plan fix:1 validation review done; do
    [ "$(pick "(o.calls.find((c) => c.label === '$l').schema.properties.directive_declined || {}).type" <<<"$out")" = string ] \
      || { echo "$l cannot decline"; return 1; }
  done
}

@test "a refusal reaches stages[], a phase's under its id" {
  out="$(run_profile bug "$(contract ', "start_stage": "Fix", "stage_scope": "forward", "end_stage": "Validation", "user_directive": "do not commit"')" \
    '{"fix:read-plan": {"ok": true, "artifact_path": "p", "summary": "s", "phases": [{"id": "1", "title": "t", "kind": "code"}, {"id": "2", "title": "u", "kind": "code"}]}, "fix:1": {"ok": true, "phase_id": "1", "committed": true, "summary": "s", "directive_declined": "committed anyway: a phase owes its commit"}, "fix:2": {"ok": true, "phase_id": "2", "committed": true, "summary": "s"}, "validation": {"validation_status": "PASSED", "reproduction_status": "fixed", "artifact_path": "v", "summary": "s", "directive_declined": "ran the full regression"}}')"
  [ "$(pick "o.result.stages.find((s) => s.stage === 'Fix').directive_declined" <<<"$out")" = '1: committed anyway: a phase owes its commit' ] \
    || { pick 'o.result.stages' <<<"$out"; return 1; }
  [ "$(pick "o.result.stages.find((s) => s.stage === 'Validation').directive_declined" <<<"$out")" = 'ran the full regression' ] \
    || { pick 'o.result.stages' <<<"$out"; return 1; }
}

@test "a stage that declined nothing reports an empty refusal, not a missing one" {
  out="$(run_profile bug "$(contract ', "start_stage": "Validation"')" '{"validation": {"validation_status": "PASSED", "reproduction_status": "fixed", "artifact_path": "v", "summary": "s"}}')"
  [ "$(pick "JSON.stringify(o.result.stages[0].directive_declined)" <<<"$out")" = '""' ] || { pick 'o.result.stages' <<<"$out"; return 1; }
}

# An epic at Execute, auto, pushing its one step to the feature workflow.
epic_run() { # $1 extra contract members, $2 the step record's own fields (leading comma)
  run_profile epic "$(contract ", \"start_stage\": \"Execute\", \"mode\": \"auto\", \"scale\": \"lite\", \"models\": {\"reviewer\": \"session\"}$1")" \
    "{\"execute:read-steps\": {\"branch\": \"decomposition\", \"steps\": [{\"step_id\": \"1-a.step\", \"task_id\": \"001.1\", \"task_type\": \"FEATURE\", \"status\": \"PENDING\"$2}]}, \"workflow:spine-toolkit:profile-feature\": {\"status\": \"ok\", \"last_completed_stage\": \"Done\", \"stages\": []}}"
}

@test "the epic resolves each step with this run's settings" {
  pr="$(epic_run ', "run_settings": {"drive_app": "off", "models.reviewer": "opus"}' '' | pick "o.calls.find((c) => c.label === 'execute:read-steps').prompt")"
  grep -qF "resolve-settings.sh json <step folder> --set 'drive_app=off' --set 'models.reviewer=opus'\"" <<<"$pr" || { echo "$pr"; return 1; }
  pr="$(epic_run '' '' | pick "o.calls.find((c) => c.label === 'execute:read-steps').prompt")"
  grep -qF 'resolve-settings.sh json <step folder>"' <<<"$pr" || { echo "$pr"; return 1; }
}

@test "a step gets the run's directive and settings, and the run's word over its own" {
  out="$(epic_run ', "user_directive": "leave Net alone", "run_settings": {"scale": "full", "models.reviewer": "opus"}' ', "scale": "lite", "models": "reviewer: sonnet, architect: haiku"')"
  args="$(pick "o.calls.find((c) => c.label === 'workflow:spine-toolkit:profile-feature').args" <<<"$out")"
  [ "$(pick 'o.user_directive' <<<"$args")" = 'leave Net alone' ] || { echo "$args"; return 1; }
  [ "$(pick 'JSON.stringify(o.run_settings)' <<<"$args")" = '{"scale":"full","models.reviewer":"opus"}' ] || { echo "$args"; return 1; }
  [ "$(pick 'o.models.reviewer' <<<"$args")" = opus ] || { echo "$args"; return 1; }
  [ "$(pick 'o.models.architect' <<<"$args")" = haiku ] || { echo "$args"; return 1; }
  [ "$(pick 'o.scale' <<<"$args")" = full ] || { echo "$args"; return 1; }
}

@test "a run's lite does not lower a step that wrote full down" {
  args="$(epic_run ', "run_settings": {"scale": "lite"}' ', "scale": "full"' | pick "o.calls.find((c) => c.label === 'workflow:spine-toolkit:profile-feature').args")"
  [ "$(pick 'o.scale' <<<"$args")" = full ] || { echo "$args"; return 1; }
}

@test "a pending step carries the scale a pushed one would run at" {
  out="$(run_profile epic "$(contract ', "start_stage": "Execute", "mode": "manual", "scale": "lite", "run_settings": {"scale": "full"}')" \
    '{"execute:read-steps": {"branch": "decomposition", "steps": [{"step_id": "1-a.step", "task_id": "001.1", "task_type": "FEATURE", "status": "PENDING", "scale": "lite"}, {"step_id": "2-b.step", "task_id": "001.2", "task_type": "QUICK", "status": "PENDING"}]}}')"
  [ "$(pick 'JSON.stringify(o.result.pending_steps.map((s) => s.scale))' <<<"$out")" = '["full","lite"]' ] || { echo "$out"; return 1; }
}

@test "a step of a run without a directive gets empty fields, never missing ones" {
  args="$(epic_run '' '' | pick "o.calls.find((c) => c.label === 'workflow:spine-toolkit:profile-feature').args")"
  [ "$(pick 'JSON.stringify([o.user_directive, o.run_settings])' <<<"$args")" = '["",{}]' ] || { echo "$args"; return 1; }
}

@test "every Method B skill carries the directive to its subagents in the convention's words" {
  n=0
  for s in "$ROOT"/skills/workflow-*/SKILL.md; do
    n=$((n + 1))
    c="$(awk '/^## 1\. Input Contract$/{f=1;next} f&&/^## /{exit} f' "$s")"
    for f in '`user_directive`, `run_settings`' '`conventions/stage-dispatch.md` → Owner'"'"'s directive' '`directive_declined`' '`notes`'; do
      grep -qF -- "$f" <<<"$c" || { echo "${s#$ROOT/}: Input Contract lost $f"; return 1; }
    done
  done
  [ "$n" -eq 8 ] || { echo "scanned $n skill(s), expected 8"; return 1; }
}

# The orchestrator's side, held to its words: what it splits a request into, where the run lives,
# and what it tells the user.
S_OF() { awk -v h="## $1" '$0==h{f=1;next} f&&/^## /{exit} f' "$ROOT/skills/orchestrator/SKILL.md"; }

@test "the request splits into run settings and a directive, both taken only from the owner's message" {
  t="$(S_OF 'Resilient Input Contract')"
  for f in '| `run_settings` |' '| `user_directive` |' '**The run'"'"'s own words**'; do
    grep -qF -- "$f" <<<"$t" || { echo "input contract lost: $f"; return 1; }
  done
  w="$(S_OF "The run's own words")"
  for f in 'every field with a `Task.md` line' 'never from a file' '`mode_override`' '`stack_override`'; do
    grep -qF -- "$f" <<<"$w" || { echo "the run's own words lost: $f"; return 1; }
  done
}

@test "the run lives in Run.json until its range is done, and a new session is asked about it" {
  w="$(S_OF "The run's own words")"
  for f in '`Run.json`' '"request"' '"user_directive"' '"run_settings"' '"range"' '"started"' \
           'auq_run_resume_question' 'auq_run_resume_apply' 'auq_run_resume_discard' 'info_run_resumed' \
           'the new last' 'not added again' 'deleted' 'pending_steps'; do
    grep -qF -- "$f" <<<"$w" || { echo "Run.json lost: $f"; return 1; }
  done
}

@test "the resolver gets the run's settings, and its refusals are announced" {
  r="$(S_OF 'Resolution Algorithm')"
  grep -qF -- '--set <field>=<value>' <<<"$r" || { echo "step 3 does not pass --set"; return 1; }
  p="$(S_OF 'Progress reporting')"
  for f in 'warn_run_scale_kept' 'warn_run_setting_refused' 'info_directive_declined' 'show <task dir>` with the same `--set`'; do
    grep -qF -- "$f" <<<"$p" || { echo "progress reporting lost: $f"; return 1; }
  done
}

@test "the outbound contract carries the directive and the run settings, always" {
  c="$(S_OF 'Outbound Contract')"
  for f in 'user_directive=""' 'run_settings={}' '`user_directive`, `run_settings` —' '`""` is a value'; do
    grep -qF -- "$f" <<<"$c" || { echo "outbound contract lost: $f"; return 1; }
  done
}

@test "every run key exists in both locales" {
  for k in auq_run_resume_question auq_run_resume_apply auq_run_resume_discard info_run_resumed \
           info_directive_declined warn_run_scale_kept warn_run_setting_refused; do
    for l in en ru; do
      grep -qx "## $k" "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l.md lacks $k"; return 1; }
    done
  done
}

@test "an auto epic reports what its pushed steps declined" {
  out="$(run_profile epic "$(contract ', "start_stage": "Execute", "mode": "auto", "user_directive": "do not commit"')" \
    '{"execute:read-steps": {"branch": "decomposition", "steps": [{"step_id": "1-a.step", "task_id": "001.1", "task_type": "FEATURE", "status": "PENDING"}]}, "workflow:spine-toolkit:profile-feature": {"status": "ok", "last_completed_stage": "Done", "stages": [{"stage": "Execute", "directive_declined": "1: committed anyway"}, {"stage": "Done", "directive_declined": ""}]}}')"
  n="$(pick 'o.result.notes' <<<"$out")"
  grep -qF "Step 1-a.step, Execute declined part of the owner's directive: 1: committed anyway" <<<"$n" || { echo "$n"; return 1; }
  ! grep -qF 'Done declined' <<<"$n" || { echo "$n"; return 1; }
}

@test "the epic passes a step only the run's model keys a step could take itself" {
  args="$(epic_run ', "run_settings": {"models.Reviewer": "opus", "models.architect": "gpt", "effort.developer": "platform"}' '' | pick "o.calls.find((c) => c.label === 'workflow:spine-toolkit:profile-feature').args")"
  [ "$(pick 'o.models.reviewer' <<<"$args")" = opus ] || { echo "$args"; return 1; }
  [ "$(pick 'JSON.stringify([o.models.architect, o.models.Reviewer, o.effort.developer])' <<<"$args")" = '[null,null,null]' ] || { echo "$args"; return 1; }
}

@test "the epic quotes each --set it hands the step resolver" {
  pr="$(epic_run ', "run_settings": {"drive_app": "off"}' '' | pick "o.calls.find((c) => c.label === 'execute:read-steps').prompt")"
  grep -qF "resolve-settings.sh json <step folder> --set 'drive_app=off'\"" <<<"$pr" || { echo "$pr"; return 1; }
}

@test "a run keeps only the settings the resolver applied, and a single-stage range ends at its stage" {
  w="$(S_OF "The run's own words")"
  for f in 'whose source in that call is not `run`' '`start_stage` when `stage_scope` is `single`' \
           'tracked by git' 'warn_run_file_tracked'; do
    grep -qF -- "$f" <<<"$w" || { echo "the run's own words lost: $f"; return 1; }
  done
  p="$(S_OF 'Progress reporting')"
  grep -qF '`to` the value it resolved to' <<<"$p" || { echo "a run setting's to is the raw value"; return 1; }
  grep -qF "an epic's notes" <<<"$p" || { echo "an epic's step refusals are not surfaced"; return 1; }
  for l in en ru; do grep -qx '## warn_run_file_tracked' "$ROOT/skills/orchestrator/locales/$l.md" || { echo "$l lacks warn_run_file_tracked"; return 1; }; done
}
