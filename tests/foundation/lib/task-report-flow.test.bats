#!/usr/bin/env bats
# The task's topic report under Method A (spine-toolkit:task-report): the prelude's REPORT constant,
# the Plan and Review clauses, the `report` dispatch at the end of the implementing stage and before
# Done, and the link lint in Done's brief. Driven through profile-test.js with stubbed agents.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  PHASES='"phases": [{"id": "1", "title": "t", "kind": "test"}]'
  STAGES='"write:1": {"ok": true, "phase_id": "1", "committed": true, "summary": "s"}, "validation": {"validation_status": "PASSED", "artifact_path": "v", "summary": "s"}, "review": {"review_status": "APPROVED", "artifact_path": "r", "summary": "s"}, "done": {"ok": true, "artifact_path": "d", "summary": "s", "committed_outside_tasks": true}'
}

# $1 report ("" leaves the field out), $2 walkthrough.
contract() {
  local report=''
  [ -n "$1" ] && report=", \"report\": \"$1\""
  printf '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "lang": "en", "agents": %s, "start_stage": "Plan", "end_stage": "Done", "stage_scope": "forward", "walkthrough": "%s"%s}' \
    "$AGENTS" "${2:-off}" "$report"
}

# $1 report, $2 plan's report_decision ("" leaves it out), $3 extra replies, $4 walkthrough.
run_test_profile() {
  local decision=''
  [ -n "$2" ] && decision=", \"report_decision\": \"$2\""
  node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-test.js" "$(contract "$1" "${4:-off}")" \
    "{\"plan\": {\"ok\": true, \"artifact_path\": \"p\", \"summary\": \"s\", $PHASES$decision}, $STAGES${3:+, $3}}"
}

pick() { node -e 'const o = JSON.parse(require("fs").readFileSync(0, "utf8")); const v = eval(process.argv[1]); console.log(typeof v === "string" ? v : JSON.stringify(v))' "$1"; }

@test "the prelude is still byte-identical" {
  run "$ROOT/scripts/lint-workflows.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "report off dispatches no report agent and no report clause" {
  out="$(run_test_profile off needed)"
  [ "$(pick 'o.calls.filter((c) => c.label === "report").length' <<<"$out")" = 0 ]
  [ "$(pick 'o.calls.filter((c) => (c.prompt || "").includes("task-report")).map((c) => c.label).join(" ")' <<<"$out")" = "" ]
  [ "$(pick 'o.result.last_completed_stage' <<<"$out")" = Done ]
}

@test "report auto puts the decision into the Plan brief" {
  out="$(run_test_profile auto)"
  prompt="$(pick 'o.calls.find((c) => c.label === "plan").prompt' <<<"$out")"
  grep -qF '## The decision' <<<"$prompt"
  grep -qF "This run's report is auto" <<<"$prompt"
  grep -qF 'report_decision' <<<"$(pick 'o.calls.find((c) => c.label === "plan").schema' <<<"$out")"
}

@test "a missing report field reads as auto" {
  out="$(run_test_profile '')"
  grep -qF "This run's report is auto" <<<"$(pick 'o.calls.find((c) => c.label === "plan").prompt' <<<"$out")"
}

@test "a not-needed plan skips the write at the implementing stage but not before Done" {
  out="$(run_test_profile auto not-needed)"
  [ "$(pick 'o.calls.filter((c) => c.label === "report").map((c) => c.phase).join(" ")' <<<"$out")" = Done ]
}

@test "a needed plan writes the report after the phases and before the walkthrough" {
  out="$(run_test_profile auto needed '' brief)"
  order="$(pick 'o.calls.filter((c) => ["write:1", "report", "walkthrough", "done"].includes(c.label)).map((c) => c.label + "/" + c.phase).join(" ")' <<<"$out")"
  [ "$order" = "write:1/Write report/Write walkthrough/Write report/Done done/Done walkthrough/Done" ] || { echo "$order"; return 1; }
}

@test "the implementing-stage brief writes by the document and leaves the link lint to Done" {
  out="$(run_test_profile auto needed)"
  prompt="$(pick 'o.calls.find((c) => c.label === "report" && c.phase === "Write").prompt' <<<"$out")"
  grep -qF '## The document' <<<"$prompt"
  grep -qF 'docs(<scope>)' <<<"$prompt"
  ! grep -qF '## Links' <<<"$prompt"
  done_prompt="$(pick 'o.calls.find((c) => c.label === "report" && c.phase === "Done").prompt' <<<"$out")"
  grep -qF '## Links' <<<"$done_prompt"
  grep -qF 'changed false' <<<"$done_prompt"
}

@test "the Done brief runs the link lint" {
  out="$(run_test_profile auto needed)"
  grep -qF '/core/scripts/lint-report-links.sh' <<<"$(pick 'o.calls.find((c) => c.label === "done").prompt' <<<"$out")"
}

@test "the Review brief makes a diverging number blocking" {
  out="$(run_test_profile auto needed)"
  prompt="$(pick 'o.calls.find((c) => c.label === "review").prompt' <<<"$out")"
  grep -qF 'task-report' <<<"$prompt"
  grep -qF '## Review' <<<"$prompt"
  grep -qF 'blocking_findings' <<<"$prompt"
}

@test "a repeat Done with nothing to change leaves no note" {
  out="$(run_test_profile on needed '"report": {"changed": false, "decision": "needed"}')"
  [ "$(pick 'o.calls.filter((c) => c.label === "report").length' <<<"$out")" = 2 ]
  ! grep -qi 'report' <<<"$(pick 'o.result.notes' <<<"$out")"
}

@test "a report agent that returns nothing is noted, never fatal" {
  out="$(run_test_profile auto needed '"report": null')"
  [ "$(pick 'o.result.last_completed_stage' <<<"$out")" = Done ]
  grep -qF 'report agent returned nothing' <<<"$(pick 'o.result.notes' <<<"$out")"
}

@test "a platform without the report role is noted and the run goes on" {
  # Done's own need() hands back before the call site, so the helper is reached directly.
  out="$(node -e '
    const fs = require("fs")
    const body = fs.readFileSync(process.argv[1], "utf8").replace(/^export const meta/m, "const meta")
    // Stop right after the prelude and call writeReport directly, with the tester role absent.
    const cut = body.split("// ── end prelude")[0] + "\nreturn writeReport(\"Done\").then(() => result.notes)\n"
    globalThis.agent = async () => { throw new Error("dispatched") }
    const run = new (Object.getPrototypeOf(async function () {}).constructor)("args", "log", cut)
    run(JSON.parse(process.argv[2]), () => {}).then((n) => console.log(JSON.stringify(n)))
  ' "$ROOT/workflows/profile-test.js" '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "agents": {"tester": "—"}, "report": "on"}')"
  grep -qF 'No agent implements the \"tester\" role' <<<"$out" || { echo "$out"; return 1; }
}

@test "the eight scripts declare REPORT_AGENT by the implementing role" {
  for pair in feature:developer bug:developer quick:developer refactor:refactorer test:tester epic:architect; do
    grep -qxF "const REPORT_AGENT = '${pair#*:}'" "$ROOT/workflows/profile-${pair%%:*}.js" || { echo "profile-${pair%%:*}.js"; return 1; }
  done
}

@test "REVIEW and RESEARCH have no REPORT_AGENT" {
  grep -qx "const REPORT_AGENT = null" "$ROOT/workflows/profile-review.js"
  grep -qx "const REPORT_AGENT = null" "$ROOT/workflows/profile-research.js"
}
