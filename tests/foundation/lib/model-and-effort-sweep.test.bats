#!/usr/bin/env bats
# changed: sweep skills conventions workflows
# Split from model-and-effort.test.bats: the tests that walk the source trees.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  RULE="$ROOT/conventions/stage-dispatch.md"
}

section() { awk -v h="$2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"; }
# A step's own [MODELS] may say fast, and so may the run's --set; the step must be dispatched on what
# the tier resolves to, never on the literal "fast". The step's resolve-settings.sh run is what resolves it.
epic_project() {
  P="$BATS_TEST_TMPDIR/p"; E="$P/Tasks/ACTIVE/050-e"; S="$E/01-x.step"
  mkdir -p "$S"
  printf '[MODEL_TIERS] = [fast@claude-code: haiku]\n[MODELS] = [light: session, validator: session, reviewer: session]\n' >"$P/SPINE.md"
  printf '[TASK_TYPE] = [EPIC]\n' >"$E/Task.md"
  printf '[TASK_TYPE] = [BUG]\n[MODELS] = [validator: fast]\n' >"$S/Task.md"
}

epic_walk() {
  AGENTS='{"architect":"a","developer":"d","tester":"t","reviewer":"r","refactorer":"f","validator":"v","security":"—","diagnostics":"g","init":"—"}'
  MODELS='{"light":"session","walkthrough":"session","done":"session","architect":"session","developer":"session","tester":"session","reviewer":"haiku","refactorer":"session","validator":"session","security":"session","diagnostics":"session"}'
  CONTRACT='{"task_id": "050", "task_dir": "'"$E"'", "plugin_root": "'"$ROOT"'", "lang": "en", "mode": "auto", "agents": '"$AGENTS"', "models": '"$MODELS"', "run_settings": {"models.reviewer": "fast"}, "start_stage": "Execute", "stage_scope": "single"}'
  node "$ROOT/tests/foundation/helpers/run-profile.js" "$ROOT/workflows/profile-epic.js" "$CONTRACT" \
    '{"execute:read-steps": {"ok": true, "branch": "decomposition", "steps": ['"$1"']}, "workflow:spine-toolkit:profile-bug": {"status": "ok", "next_recommended_action": "stop", "validation_status": "PASSED", "review_status": "APPROVED"}}'
}

@test "writing Done.md is its own kind, off the light model and off low" {
  # A Done that runs again checks a report against the task: judgement, which the mechanical
  # kind's light model and fixed low effort were never meant to carry.
  s="$(section "$RULE" '## Model and effort')"
  list="$(awk '/^- `mechanical` —/{f=1; print; next} f&&(/^$/||/^- /){exit} f' <<<"$s")"
  [ -n "$list" ] || { echo "no mechanical list"; return 1; }
  ! grep -qF '`done`' <<<"$list" || { echo "done is still listed as mechanical"; return 1; }
  grep -qF -- '- `done` — writing the final report' <<<"$s" || { echo "the rule does not define the done kind"; return 1; }
  grep -qxF "    (r'done', 'done')," "$ROOT/scripts/lint-workflows.sh" || { echo "the lint does not hold done at its own kind"; return 1; }
  n=0
  for p in bug epic feature quick refactor research test; do
    line="$(grep -F "label: 'done'," "$ROOT/workflows/profile-$p.js")"
    grep -qE "\.\.\.tuning\('[a-z]+', 'done'\)" <<<"$line" || { echo "profile-$p.js: the done call is not tuned done"; return 1; }
    n=$((n + 1))
  done
  [ "$n" -eq 7 ] || { echo "checked $n profile(s), expected 7"; return 1; }
}

@test "every profile script defines tuning() as the rule states it" {
  n=0
  for p in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    for line in "const tuning = (role, kind) => {" \
                "  const pick = (map, key, none) => (map && map[key] && map[key] !== none ? map[key] : null)" \
                "  const own = (map) => (kind === 'walkthrough' || kind === 'done' ? pick(map, kind, 'session') : null)" \
                "  const model = own(A.models) || (kind !== 'stage' && kind !== 'done' && kind !== 'walkthrough' && pick(A.models, 'light', 'session')) || pick(A.models, role, 'session')" \
                "  const effort = kind === 'mechanical' ? 'low' : own(A.effort) || pick(A.effort, role, 'session')" \
                "  return { ...(model ? { model } : {}), ...(effort ? { effort } : {}) }"; do
      grep -qxF "$line" "$p" || { echo "$(basename "$p"): missing '$line'"; return 1; }
    done
  done
  [ "$n" -eq 8 ] || { echo "scanned $n script(s), expected 8"; return 1; }
}

@test "every workflow skill dispatches a stage on the model the rule derives" {
  n=0
  for f in "$ROOT"/skills/workflow-*/SKILL.md; do
    n=$((n + 1))
    para="$(grep '^A stage names its owner as a role in brackets' "$f")"
    [ -n "$para" ] || { echo "$f: no dispatch paragraph"; return 1; }
    grep -qF '`conventions/stage-dispatch.md` → Model and effort' <<<"$para" || { echo "$f: the paragraph does not point at the rule"; return 1; }
    grep -qF 'cannot pass an effort' <<<"$para" || { echo "$f: the paragraph does not say effort stays behind"; return 1; }
    grep -qF 'a walkthrough takes its own `walkthrough` key, then its role' <<<"$para" \
      || { echo "$f: the paragraph does not give a walkthrough its own key first"; return 1; }
    grep -qF 'where the rule yields `session`' <<<"$para" || { echo "$f: the paragraph does not name session"; return 1; }
  done
  [ "$n" -eq 8 ] || { echo "scanned $n skill(s), expected 8"; return 1; }
}

@test "the platform contract and the platform guide keep model and effort out of agent frontmatter" {
  roles="$(awk '/^## `## Roles`$/{f=1;next} f&&/^## /{exit} f' "$ROOT/conventions/platform-contract.md")"
  for token in 'no `model` and no `effort`' '`session`' '`conventions/stage-dispatch.md` → Model and effort' '`lint-manifest.sh`'; do
    grep -qF "$token" <<<"$roles" || { echo "## Roles does not say $token"; return 1; }
  done
  ! grep -qF 'plus whatever your' "$ROOT/docs/building-a-platform.md" || { echo "the guide still invites a model in frontmatter"; return 1; }
  grep -qF 'leave `model` and `effort` out' "$ROOT/docs/building-a-platform.md" || { echo "the guide does not say to leave them out"; return 1; }
  ! grep -qF '`sonnet` or `haiku`' <<<"$roles" || { echo "## Roles still allows a lighter model"; return 1; }
  ! grep -qF 'when a lighter model is allowed' "$ROOT/docs/building-a-platform.md" || { echo "the guide still allows a lighter model"; return 1; }
}

@test "a step's own fast and the run's fast reach the step resolved" {
  epic_project
  json="$("$ROOT/scripts/resolve-settings.sh" json "$S" --set models.reviewer=fast)"
  resolved="$(python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["models"]))' <<<"$json")"
  out="$(epic_walk '{"step_id": "01-x.step", "task_id": "050.1", "task_type": "BUG", "status": "PENDING", "models": "validator: fast", "resolved_models": '"$resolved"'}')"
  node -e 'const o = JSON.parse(process.argv[1]); const c = o.calls.find((c) => c.label === "workflow:spine-toolkit:profile-bug")
    const m = c && c.args.models
    if (!m || m.validator !== "haiku" || m.reviewer !== "haiku" || Object.values(m).includes("fast")) { console.log(JSON.stringify(c ? c.args : o)); process.exit(1) }' "$out"
  # The reader asks the step's own resolve-settings.sh run for its models.
  grep -qF 'its models value as resolved_models' "$ROOT/workflows/profile-epic.js"
}

@test "without the resolved map a step's fast is never dispatched as a model name" {
  epic_project
  out="$(epic_walk '{"step_id": "01-x.step", "task_id": "050.1", "task_type": "BUG", "status": "PENDING", "models": "validator: fast, reviewer: opus"}')"
  node -e 'const o = JSON.parse(process.argv[1]); const c = o.calls.find((c) => c.label === "workflow:spine-toolkit:profile-bug")
    const m = c && c.args.models
    // the run said reviewer: fast, which the epic`s own map already resolved; the step`s opus does not beat the run
    if (!m || Object.values(m).includes("fast") || m.reviewer !== "haiku" || m.validator !== "session") { console.log(JSON.stringify(c ? c.args : o)); process.exit(1) }
    if (!/validator: fast/.test(o.result.notes || "")) { console.log(o.result.notes); process.exit(1) }' "$out"
}
