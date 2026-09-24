#!/usr/bin/env bats
# Every surface outside the profile that has to know QUICK exists: the orchestrator's tables and
# gate, the settings chain's documents, task-new, the epic that must refuse it, and the docs.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/orchestrator/SKILL.md"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
}

@test "the orchestrator dispatches QUICK and detects its state" {
  grep -qxF '| QUICK | `workflows/profile-quick.js` | `spine-toolkit:workflow-quick` |' "$SKILL" || { echo "no Dispatch row"; return 1; }
  grep -qF '| QUICK | first phase not `✅` |' "$SKILL" || { echo "no State Detection row"; return 1; }
  grep -qF 'QUICK: `Edit`, which finishes an existing `Plan.md` rather than writing one' "$SKILL" || { echo "no unparseable-plan entry"; return 1; }
  for s in 'For FEATURE, BUG, REFACTOR, TEST and QUICK, first run' '(Fix / Execute / Refactor / Write / Edit), forward' \
           '(FEATURE, BUG, REFACTOR, TEST, QUICK only;' '(Execute / Fix / Refactor / Write / Edit),' 'FEATURE, BUG, REFACTOR, TEST and QUICK. The findings'; do
    grep -qF -- "$s" "$SKILL" || { echo "the ranged lists lost QUICK: $s"; return 1; }
  done
}

@test "a failed entry check stops in both modes and never rewrites the type" {
  p="$(grep -F '**After Edit: `quick_escalation`.**' "$SKILL")"
  for s in 'In both modes' '`quick_escalation_stop` (`{task_id}`, `{reason}`)' 'no `stage_done_prompt`' '`[TASK_TYPE]` is not rewritten'; do
    grep -qF -- "$s" <<<"$p" || { echo "the Gating paragraph lost: $s"; return 1; }
  done
}

@test "an epic Plan that types a step QUICK stops before Execute" {
  grep -qF "never QUICK, which only the user chooses" "$ROOT/workflows/profile-epic.js" || { echo "the epic Plan brief allows QUICK"; return 1; }
  grep -qF 'never QUICK, which only the user chooses: a Plan that returns a QUICK step stops the epic before Execute' "$ROOT/skills/workflow-epic/SKILL.md" || { echo "Method B has no Plan check"; return 1; }
  contract='{"task_id": "050", "task_dir": "/p/Tasks/ACTIVE/050-e", "plugin_root": "/core", "lang": "en", "mode": "auto", "agents": '"$AGENTS"', "start_stage": "Plan", "stage_scope": "forward"}'
  replies='{"plan": {"ok": true, "branch": "decomposition", "steps": [{"step_id": "1.step", "task_id": "050.1", "task_type": "BUG", "status": "PENDING"}, {"step_id": "2.step", "task_id": "050.2", "task_type": "QUICK", "status": "PENDING"}]}}'
  out="$(node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-epic.js" "$contract" "$replies")"
  node -e 'const o = JSON.parse(process.argv[1]); if (o.result.status !== "error" || !/2\.step/.test(o.result.reason) || o.calls.some((c) => /^(execute|workflow):/.test(c.label))) { console.log(JSON.stringify(o.result)); process.exit(1) }' "$out"
}

@test "an open QUICK step runs in the epic walk, always lite" {
  if grep -qF 'error_quick_step' "$ROOT/workflows/profile-epic.js" "$ROOT/skills/workflow-epic/SKILL.md"; then echo "the epic still refuses a QUICK step"; return 1; fi
  contract='{"task_id": "050", "task_dir": "/p/Tasks/ACTIVE/050-e", "plugin_root": "/core", "lang": "en", "mode": "auto", "scale": "full", "agents": '"$AGENTS"', "start_stage": "Execute", "stage_scope": "single"}'
  replies='{"execute:read-steps": {"ok": true, "branch": "decomposition", "steps": [{"step_id": "1.step", "task_id": "050.1", "task_type": "QUICK", "status": "PENDING", "scale": "full"}]}, "workflow:spine-toolkit:profile-quick": {"status": "ok"}}'
  out="$(node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-epic.js" "$contract" "$replies")"
  node -e 'const o = JSON.parse(process.argv[1]); const w = o.calls.find((c) => c.label === "workflow:spine-toolkit:profile-quick")
    if (!w || w.args.scale !== "lite" || o.result.completed_steps.length !== 1 || !o.calls.some((c) => c.label === "execute:tick:1.step")) { console.log(JSON.stringify(o)); process.exit(1) }' "$out"
}

@test "a QUICK step that escalates fails the walk and is not ticked" {
  contract='{"task_id": "050", "task_dir": "/p/Tasks/ACTIVE/050-e", "plugin_root": "/core", "lang": "en", "mode": "auto", "agents": '"$AGENTS"', "start_stage": "Execute", "stage_scope": "single"}'
  replies='{"execute:read-steps": {"ok": true, "branch": "decomposition", "steps": [{"step_id": "1.step", "task_id": "050.1", "task_type": "QUICK", "status": "PENDING"}, {"step_id": "2.step", "task_id": "050.2", "task_type": "BUG", "status": "PENDING"}]}, "workflow:spine-toolkit:profile-quick": {"status": "ok", "quick_escalation": {"reason": "three files"}}}'
  out="$(node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-epic.js" "$contract" "$replies")"
  node -e 'const o = JSON.parse(process.argv[1]); const r = o.result
    if (r.completed_steps.length || r.failed_steps.length !== 1 || !/not a QUICK change: three files/.test(r.failed_steps[0].error_reason) || r.pending_steps.map((s) => s.step_id).join() !== "2.step" || o.calls.some((c) => /^execute:tick/.test(c.label))) { console.log(JSON.stringify(o)); process.exit(1) }' "$out"
  grep -qF 'If a QUICK step returned `quick_escalation`' "$ROOT/skills/workflow-epic/SKILL.md" || { echo "Method B does not stop on an escalated step"; return 1; }
}

@test "both new orchestrator keys exist in both locales" {
  for lang in en ru; do
    for k in quick_escalation_stop error_quick_step; do
      grep -qx "## $k" "$ROOT/skills/orchestrator/locales/$lang.md" || { echo "$lang lacks $k"; return 1; }
    done
  done
}

@test "task-new sets QUICK only on the user's word, with its own flags, never for a step" {
  t="$ROOT/skills/task-new/SKILL.md"
  grep -qF 'The user named the type QUICK — the words in locale key `task_type_quick_keywords` → `QUICK`. Checked first, and only ever on the user'"'"'s own word' "$t" || { echo "no QUICK rule"; return 1; }
  grep -qF '`TASK_TYPE` is `QUICK` → `NEED_TEST = false`, `NEED_REVIEW = true`' "$t" || { echo "no QUICK flags"; return 1; }
  grep -qF 'a step is never QUICK: a request naming it for a step is answered with key `quick_not_for_steps`' "$t" || { echo "a step may be QUICK"; return 1; }
  for lang in en ru; do
    for k in task_type_quick_keywords quick_not_for_steps; do
      grep -qx "## $k" "$ROOT/skills/task-new/locales/$lang.md" || { echo "$lang lacks $k"; return 1; }
    done
  done
  grep -qF '# FEATURE | BUG | REFACTOR | QUICK | REVIEW | TEST | EPIC | RESEARCH' "$ROOT/templates/task-md/task-root.md" || { echo "root template"; return 1; }
  if grep -qF 'QUICK' "$ROOT/templates/task-md/task-step.md"; then echo "the step template offers QUICK"; return 1; fi
}

@test "the scale axis, the settings table and the docs say QUICK is always lite and not a third value" {
  grep -qF 'A `QUICK` task is always `lite`, whatever `[SCALE]` says' "$ROOT/conventions/task-scale.md" || { echo "task-scale"; return 1; }
  grep -qF 'That is not a third value either.' "$ROOT/conventions/task-scale.md" || { echo "task-scale: third value"; return 1; }
  grep -qF '`full`; always `lite` for a `QUICK` task |' "$ROOT/conventions/task-settings.md" || { echo "task-settings"; return 1; }
  grep -qF 'A `QUICK` task is always `lite`' "$ROOT/docs/configuration.md" || { echo "configuration"; return 1; }
  grep -qF '| QUICK | Edit → Validation → Review → Done' "$ROOT/README.md" || { echo "README"; return 1; }
  grep -qF 'of eight profiles:' "$ROOT/README.md" || { echo "README count"; return 1; }
  grep -qF 'QUICK Edit' "$ROOT/docs/building-a-platform.md" || { echo "platform guide"; return 1; }
}

@test "no task-new keyword for QUICK is a word a task's own description uses" {
  for lang in en ru; do
    kw="$(awk '/^## task_type_quick_keywords$/{f=1;next} f&&/^## /{exit} f&&NF' "$ROOT/skills/task-new/locales/$lang.md")"
    [ -n "$kw" ] || { echo "$lang: no keywords"; return 1; }
    tr ';' '\n' <<<"$kw" | sed 's/^ *//;s/ *$//' | while read -r k; do
      case "$k" in *QUICK*|*quick-*|*"quick task"*|*"$(python3 -c 'print("".join(map(chr,(1073,1099,1089,1090,1088,1072,1103,32,1079,1072,1076,1072,1095,1072))))')"*) ;;
        *) echo "$lang: '$k' can come from a description of the work"; exit 1 ;; esac
    done || return 1
  done
  grep -qF '`FEATURE` \| `BUG` \| `REFACTOR` \| `QUICK` \| `REVIEW` \| `TEST` \| `EPIC` \| `RESEARCH`' "$ROOT/skills/task-new/SKILL.md" || { echo "the placeholder table does not allow QUICK"; return 1; }
}

@test "a QUICK rerun resumes at Edit when its phase is still open, not only when it is unstarted" {
  grep -qxF '| QUICK | first phase not `✅` | n/a | n/a | n/a | `Edit` |' "$ROOT/skills/orchestrator/SKILL.md" || { echo "State Detection skips a 🔄 Edit phase"; return 1; }
}
