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

# The other profiles: $1 profile, $2 stage run alone, $3 report, $4 extra replies, $5 walkthrough.
run_stage() {
  local c
  c="$(contract "$3" "${5:-off}" | sed "s/\"start_stage\": \"Plan\", \"end_stage\": \"Done\"/\"start_stage\": \"$2\", \"end_stage\": \"$2\"/")"
  node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-$1.js" "$c" "{${4:-\"_\": 0}}"
}

@test "every planning brief carries the decision" {
  for ps in feature:Plan:plan bug:Plan:plan refactor:Plan:plan quick:Edit:edit epic:Plan:plan research:Research:research:architect; do
    IFS=: read -r p s label <<<"$ps"
    out="$(run_stage "$p" "$s" auto)"
    prompt="$(pick "o.calls.find((c) => c.label === \"$label\").prompt" <<<"$out")"
    grep -qF '## The decision' <<<"$prompt" || { echo "profile-$p.js: the $s brief does not decide the report"; return 1; }
    grep -qF 'report_decision' <<<"$(pick "o.calls.find((c) => c.label === \"$label\").schema" <<<"$out")" \
      || { echo "profile-$p.js: the $s reply has no report_decision"; return 1; }
    out="$(run_stage "$p" "$s" off)"
    ! grep -qF 'task-report' <<<"$(pick "o.calls.find((c) => c.label === \"$label\").prompt" <<<"$out")" \
      || { echo "profile-$p.js: the $s brief decides the report under off"; return 1; }
  done
}

@test "the Research agent writes the fields and the report itself" {
  prompt="$(pick 'o.calls.find((c) => c.label === "research:architect").prompt' <<<"$(run_stage research Research auto)")"
  grep -qF 'top of Research.md' <<<"$prompt"
  grep -qF '## The document' <<<"$prompt"
  ! grep -qF 'top of Research.md' <<<"$(pick 'o.calls.find((c) => c.label === "research:architect").prompt' <<<"$(run_stage research Research off)")"
}

@test "every implementing stage writes the report before its walkthrough" {
  for ps in feature:Execute bug:Fix refactor:Refactor quick:Edit; do
    p="${ps%%:*}"; s="${ps#*:}"
    out="$(run_stage "$p" "$s" auto '"edit": {"ok": true, "phase_id": "1", "committed": true, "summary": "s"}' brief)"
    order="$(pick "o.calls.filter((c) => c.phase === \"$s\" && [\"report\", \"walkthrough\"].includes(c.label)).map((c) => c.label).join(\" \")" <<<"$out")"
    [ "$order" = "report walkthrough" ] || { echo "profile-$p.js $s: $order"; return 1; }
  done
}

@test "every profile with a Review stage checks the numbers there, but the epic" {
  for p in feature bug refactor quick research; do
    out="$(run_stage "$p" Review auto)"
    grep -qF 'task-report skill, its ## Review section' <<<"$(pick 'o.calls.find((c) => c.label === "review").prompt' <<<"$out")" \
      || { echo "profile-$p.js: the Review brief does not check the report"; return 1; }
  done
}

@test "every profile with an implementing role writes the report before Done" {
  for p in feature bug refactor quick epic; do
    out="$(run_stage "$p" Done auto)"
    order="$(pick 'o.calls.filter((c) => ["report", "done"].includes(c.label)).map((c) => c.label + "/" + c.phase).join(" ")' <<<"$out")"
    [ "$order" = "report/Done done/Done" ] || { echo "profile-$p.js: $order"; return 1; }
  done
}

@test "epic writes the report only before Done" {
  E="$ROOT/workflows/profile-epic.js"
  [ "$(grep -c 'await writeReport(' "$E")" = 1 ] || { grep -n 'writeReport(' "$E"; return 1; }
  grep -qF "await writeReport('Done')" "$E"
  ! grep -qF 'reportReview()}' "$E"
}

@test "RESEARCH dispatches no report agent" {
  [ "$(grep -c 'await writeReport(' "$ROOT/workflows/profile-research.js")" = 0 ]
  out="$(run_stage research Done auto)"
  [ "$(pick 'o.calls.filter((c) => c.label === "report").length' <<<"$out")" = 0 ]
}

@test "with no report agent the Done agent runs the Links steps 1 and 2 itself" {
  prompt="$(pick 'o.calls.find((c) => c.label === "done").prompt' <<<"$(run_stage research Done auto)")"
  ! grep -qF 'steps 1 and 2 ran before you' <<<"$prompt" || { echo "$prompt"; return 1; }
  grep -qF 'steps 1 and 2 yourself' <<<"$prompt"
  grep -qF 'then steps 3 to 6' <<<"$prompt"
  prompt="$(pick 'o.calls.find((c) => c.label === "done").prompt' <<<"$(run_stage feature Done auto)")"
  grep -qF 'steps 1 and 2 ran before you' <<<"$prompt"
}

@test "a report agent that throws is logged before it is noted" {
  out="$(node -e '
    const fs = require("fs")
    const body = fs.readFileSync(process.argv[1], "utf8").replace(/^export const meta/m, "const meta")
    const cut = body.split("// ── end prelude")[0] + "\nreturn writeReport(\"Done\").then(() => result.notes)\n"
    globalThis.agent = async () => { throw new Error("socket hang up") }
    const logged = []
    const run = new (Object.getPrototypeOf(async function () {}).constructor)("args", "log", cut)
    run(JSON.parse(process.argv[2]), (m) => logged.push(m)).then((n) => console.log(JSON.stringify({ n, logged })))
  ' "$ROOT/workflows/profile-test.js" '{"task_id": "001", "task_dir": "/p/Tasks/ACTIVE/001-x", "plugin_root": "/core", "agents": {"tester": "t"}, "report": "on"}')"
  grep -qF 'report: socket hang up' <<<"$out" || { echo "$out"; return 1; }
  grep -qF 'report agent returned nothing' <<<"$out"
}

@test "the Research brief lets the report past the one-file rule" {
  prompt="$(pick 'o.calls.find((c) => c.label === "research:architect").prompt' <<<"$(run_stage research Research auto)")"
  grep -qF 'write no file other than Research.md' <<<"$prompt"
  grep -qF 'the one file besides Research.md this task lets you write' <<<"$prompt"
}
