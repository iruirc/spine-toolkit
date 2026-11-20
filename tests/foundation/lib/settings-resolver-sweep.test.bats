#!/usr/bin/env bats
# changed: sweep workflows
# Split from settings-resolver.test.bats: the tests that walk the source trees.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

field() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }
@test "no profile script tells an agent where to look a setting up" {
  n=0
  for p in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    for token in '[DRIVE_APP]' '[MANUAL_CHECKS]' '[PHASE_VERIFICATION]' '## Validation'; do
      # `## Validation's regression` is a section of the phase-verification skill, not a config block.
      ! sed "s/## Validation's regression//g" "$p" | grep -qF "$token" || {
        echo "$(basename "$p") still spells the chain for $token"
        [ "$token" != '## Validation' ] || echo 'hint: "## Validation" reads as a section of the config, and the config has no such section any more: its settings are [FIELD] = [value] lines. Name a stage without "##" (the Validation stage) and a task file as Validation.md.'
        return 1
      }
    done
  done
  [ "$n" -eq 8 ] || { echo "scanned $n script(s), expected 8"; return 1; }
}

@test "an epic run through Plan and Execute reads its steps off disk before pushing them" {
  # The Plan agent reports the steps it created, never their settings: only read-steps runs the resolver.
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  contract='{"task_id": "050", "task_dir": "/p/Tasks/ACTIVE/050-e", "plugin_root": "/core", "lang": "en", "mode": "auto", "walkthrough": "deep", "agents": '"$AGENTS"', "start_stage": "Plan", "end_stage": "Execute", "stage_scope": "forward"}'
  step='"step_id": "1.step", "task_id": "050.1", "task_type": "BUG", "status": "PENDING"'
  replies='{"plan": {"ok": true, "artifact_path": "Plan.md", "summary": "s", "branch": "decomposition", "steps": [{'"$step"'}]}, "execute:read-steps": {"ok": true, "branch": "decomposition", "steps": [{'"$step"', "walkthrough": "brief", "security": "on"}]}, "workflow:spine-toolkit:profile-bug": {"status": "ok", "next_recommended_action": "stop"}}'
  out="$(node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-epic.js" "$contract" "$replies")"
  node -e 'const o = JSON.parse(process.argv[1]); const w = o.calls.find((c) => c.label === "workflow:spine-toolkit:profile-bug")
    if (!o.calls.some((c) => c.label === "execute:read-steps") || !w || w.args.walkthrough !== "brief" || w.args.security !== "on") { console.log(JSON.stringify(o.calls.map((c) => c.args || c.label))); process.exit(1) }' "$out"
}

@test "every contract field a script gates on defaults through a guarded local" {
  for p in "$ROOT"/workflows/profile-*.js; do
    grep -qxF "const DRIVE_APP = A.drive_app === 'off' ? 'off' : 'auto'" "$p" \
      || { echo "$(basename "$p"): drive_app is not guarded"; return 1; }
    grep -qxF "const MANUAL_CHECKS = A.manual_checks === 'always' ? 'always' : 'auto'" "$p" \
      || { echo "$(basename "$p"): manual_checks is not guarded"; return 1; }
    grep -qxF "const MANUAL_CHECKS_CHECK = A.manual_checks_check === 'off' ? 'off' : 'on'" "$p" \
      || { echo "$(basename "$p"): manual_checks_check is not guarded"; return 1; }
    grep -qxF "const MANUAL_CHECKS_STYLE = A.manual_checks_style === 'full' ? 'full' : 'brief'" "$p" \
      || { echo "$(basename "$p"): manual_checks_style is not guarded"; return 1; }
    grep -qxF "const MANUAL_CHECKS_PASS = A.manual_checks_pass === 'end' ? 'end' : 'per-step'" "$p" \
      || { echo "$(basename "$p"): manual_checks_pass is not guarded"; return 1; }
    grep -qxF "const PHASE_VERIFICATION = A.phase_verification === 'full' ? 'full' : 'proportional'" "$p" \
      || { echo "$(basename "$p"): phase_verification is not guarded"; return 1; }
    grep -qxF "const WALKTHROUGH_CHECK = ['on', 'once'].includes(A.walkthrough_check) ? A.walkthrough_check : 'off'" "$p" \
      || { echo "$(basename "$p"): walkthrough_check is not guarded"; return 1; }
    grep -qxF "const ARTIFACT_CHECK = A.artifact_check === 'on' ? 'on' : 'off'" "$p" \
      || { echo "$(basename "$p"): artifact_check is not guarded"; return 1; }
    grep -qxF "const SECURITY = A.security === 'on' || A.security === 'off' ? A.security : 'auto'" "$p" \
      || { echo "$(basename "$p"): security is not guarded"; return 1; }
  done
}

@test "the Validation brief of the five profiles that write ManualChecks.md names the style" {
  for p in feature bug refactor test quick; do
    grep -qF "This run's manual_checks_style is \${MANUAL_CHECKS_STYLE}" "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js: the Validation brief does not name manual_checks_style"; return 1; }
  done
  for p in epic research review; do
    ! grep -qF "This run's manual_checks_style" "$ROOT/workflows/profile-$p.js" \
      || { echo "profile-$p.js names the style in a brief it has no Validation for"; return 1; }
  done
}
