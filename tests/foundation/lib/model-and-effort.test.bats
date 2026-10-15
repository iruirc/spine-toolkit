#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# A subagent's model and effort come from one rule (conventions/stage-dispatch.md → Model and effort)
# and one resolver (scripts/resolve-settings.sh). These tests hold every surface that restates a piece
# of the rule to it: a surface that drifts is how a project's choice stops reaching a dispatch.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  RULE="$ROOT/conventions/stage-dispatch.md"
  TPL="$ROOT/templates/spine-md/en.md"
}

section() { awk -v h="$2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"; }

@test "the rule names the five kinds and the four closed lists" {
  s="$(section "$RULE" '## Model and effort')"
  [ -n "$s" ] || { echo "no ## Model and effort section"; return 1; }
  for token in '`stage`' '`light`' '`mechanical`' '`walkthrough`' '`done`' '`walkthrough:check`' '`walkthrough:revise`' \
               '`security:triage`' '`manual-checks:check`' \
               '`<stage>:read-plan`' '`execute:read-steps`' '`execute:tick:<step>`' '`done:read-branch`' \
               '`auto-move`' '`done`'; do
    grep -qF "$token" <<<"$s" || { echo "the rule does not name $token"; return 1; }
  done
}

@test "the rule's table gives each kind its model and effort" {
  s="$(section "$RULE" '## Model and effort')"
  grep -qxF '| `stage` | `models[role]` | `effort[role]` |' <<<"$s" || { echo "no stage row"; return 1; }
  grep -qxF '| `walkthrough` | `models.walkthrough`, else `models.light`, else `models[role]` | `effort.walkthrough`, else `effort[role]` |' <<<"$s" \
    || { echo "no walkthrough row"; return 1; }
  grep -qxF '| `light` | `models.light`, else `models[role]` | `effort[role]` |' <<<"$s" || { echo "no light row"; return 1; }
  grep -qxF '| `mechanical` | `models.light`, else `models[role]` | `low` |' <<<"$s" || { echo "no mechanical row"; return 1; }
  grep -qxF '| `done` | `models.done`, else `models[role]` | `effort.done`, else `effort[role]` |' <<<"$s" || { echo "no done row"; return 1; }
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

@test "the rule states the host's order with its version, and what Method B cannot pass" {
  s="$(section "$RULE" '## Model and effort')"
  for token in 'CLAUDE_CODE_SUBAGENT_MODEL' '2.1.251' 'Method B' 'cannot pass effort' 'main context' '`session` means pass nothing'; do
    grep -qF "$token" <<<"$s" || { echo "the rule does not say $token"; return 1; }
  done
  ! grep -qF '`platform`' <<<"$s" || { echo "the rule still names platform"; return 1; }
}

@test "agent tooling points a dispatch's model and effort at the rule" {
  grep -qF '`conventions/stage-dispatch.md` → Model and effort' "$ROOT/conventions/agent-tooling.md" \
    || { echo "agent-tooling.md does not point at the rule"; return 1; }
}

@test "the config template ships every Models key at its default, and no init" {
  field="$(grep -F '[MODELS] = [' "$TPL")"
  for entry in 'light: sonnet' 'walkthrough: session' 'done: session' 'architect: session' 'developer: session' 'tester: session' 'reviewer: session' \
               'refactorer: session' 'validator: sonnet' 'security: session' 'diagnostics: session'; do
    grep -qF "$entry" <<<"$field" || { echo "[MODELS] lacks '$entry'"; return 1; }
  done
  ! grep -qF 'init:' <<<"$field" || { echo "[MODELS] names init, which no profile dispatches"; return 1; }
  ! grep -qE ': platform(,|\])' <<<"$field" || { echo "[MODELS] still writes platform"; return 1; }
}

@test "the config template ships every Effort key at session, and no light" {
  field="$(grep -F '[EFFORT] = [' "$TPL")"
  for role in architect developer tester reviewer refactorer validator security diagnostics; do
    grep -qF "$role: session" <<<"$field" || { echo "[EFFORT] lacks '$role: session'"; return 1; }
  done
  grep -qF 'walkthrough: session' <<<"$field" || { echo "[EFFORT] lacks 'walkthrough: session'"; return 1; }
  grep -qF 'done: session' <<<"$field" || { echo "[EFFORT] lacks 'done: session'"; return 1; }
  ! grep -qF 'light:' <<<"$field" || { echo "[EFFORT] carries light, which no effort reads"; return 1; }
}

@test "the Models guidance names what session passes, the 1.11.0 spelling and the limits a user can trip on" {
  # The guidance left the template when the settings became one-line fields; the reference page is
  # where it lands, and this assertion goes live with it.
  doc="$ROOT/docs/configuration.md"
  for token in 'CLAUDE_CODE_SUBAGENT_MODEL' '200k' 'Sonnet 4.5' '[MODELS]' 'as if its line were absent' 'walkthrough: opus'; do
    grep -qF "$token" "$doc" || { echo "the guidance does not mention $token"; return 1; }
  done
}

@test "both task templates offer the MODELS and EFFORT overrides with the resolver's keys and values" {
  var() { sed -n "s/^$1=\"\(.*\)\"$/\1/p" "$ROOT/scripts/resolve-settings.sh" | tr ' ' '|'; }
  # The vocabulary a template quotes is the Claude runtime's, named as such: other runtimes have their own.
  rt() { python3 -c 'import json,sys; print("|".join(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$ROOT/runtimes/claude-code.json" "$1"; }
  models="# [MODELS] = [architect: opus]  # <light|walkthrough|done|$(var ROLES)>: <$(rt models) in Claude Code; the runtime's own names elsewhere>, comma-separated"
  effort="# [EFFORT] = [reviewer: high]   # <walkthrough|done|$(var ROLES)>: <$(rt effort) in Claude Code; the runtime's own names elsewhere>, comma-separated"
  for t in task-root task-step; do
    grep -qxF "$models" "$ROOT/templates/task-md/$t.md" || { echo "$t.md: [MODELS] is not '$models'"; return 1; }
    grep -qxF "$effort" "$ROOT/templates/task-md/$t.md" || { echo "$t.md: [EFFORT] is not '$effort'"; return 1; }
  done
}

@test "task-new says when a task overrides a model or an effort" {
  f="$ROOT/skills/task-new/SKILL.md"
  grep -qF '`[MODELS] = [<key>: <value>, …]`' "$f" || { echo "task-new lacks [MODELS]"; return 1; }
  grep -qF '`[EFFORT] = [<key>: <value>, …]`' "$f" || { echo "task-new lacks [EFFORT]"; return 1; }
  grep -qF 'Keys are `light`, `walkthrough`, `done` and the eight roles' "$f" || { echo "task-new does not list the done key"; return 1; }
}

@test "every profile script defines tuning() as the rule states it" {
  n=0
  for p in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    for line in "const tuning = (role, kind) => {" \
                "  const pick = (map, key, none) => (map && map[key] && map[key] !== none ? map[key] : null)" \
                "  const own = (map) => (kind === 'walkthrough' || kind === 'done' ? pick(map, kind, 'session') : null)" \
                "  const model = own(A.models) || (kind !== 'stage' && kind !== 'done' && pick(A.models, 'light', 'session')) || pick(A.models, role, 'session')" \
                "  const effort = kind === 'mechanical' ? 'low' : own(A.effort) || pick(A.effort, role, 'session')" \
                "  return { ...(model ? { model } : {}), ...(effort ? { effort } : {}) }"; do
      grep -qxF "$line" "$p" || { echo "$(basename "$p"): missing '$line'"; return 1; }
    done
  done
  [ "$n" -eq 8 ] || { echo "scanned $n script(s), expected 8"; return 1; }
}

@test "the epic's copy of the vocabulary is the resolver's" {
  verdict="$(python3 - "$ROOT/scripts/resolve-settings.sh" "$ROOT/workflows/profile-epic.js" "$ROOT/runtimes/claude-code.json" <<'PY'
import json, re, sys
sh = open(sys.argv[1], encoding='utf-8').read()
js = open(sys.argv[2], encoding='utf-8').read()
rt = json.load(open(sys.argv[3], encoding='utf-8'))
# ROLES and UNSET_MODELS stay in the resolver; the model and effort vocabulary belongs to the Claude runtime file.
var = lambda name: rt['models'] if name == 'MODELS' else rt['effort'] if name == 'EFFORTS' else re.search(r'^%s="([^"]*)"' % name, sh, re.M).group(1).split()
keys = re.search(r'^const TUNING_KEYS = \{ models: \[([^\]]*)\], effort: \[([^\]]*)\] \}$', js, re.M)
values = re.search(r'^const TUNING_VALUES = \{ models: \[([^\]]*)\], effort: \[([^\]]*)\] \}$', js, re.M)
unset = re.search(r'^const TUNING_UNSET = \{ models: \[([^\]]*)\], effort: \[([^\]]*)\] \}$', js, re.M)
if not keys or not values or not unset:
    print('profile-epic.js carries no TUNING_KEYS / TUNING_VALUES / TUNING_UNSET line'); raise SystemExit
q = lambda s: re.findall(r"'([a-z]+)'", s)
want = (['light', 'walkthrough', 'done'] + var('ROLES'), ['walkthrough', 'done'] + var('ROLES'), var('MODELS'), var('EFFORTS'), var('UNSET_MODELS'), [])
have = (q(keys.group(1)), q(keys.group(2)), q(values.group(1)), q(values.group(2)), q(unset.group(1)), q(unset.group(2)))
print('same' if want == have else 'differ: %s vs %s' % (want, have))
PY
)"
  [ "$verdict" = "same" ] || { echo "$verdict"; return 1; }
}

@test "a pushed step gets the epic's maps with its own keys over them" {
  E="$ROOT/workflows/profile-epic.js"
  block="$(sed -n '/const stepArgs/,/^    })$/p' "$E")"
  grep -qF "models: overlay('models', st)," <<<"$block" || { echo "stepArgs does not hand the step its models"; return 1; }
  grep -qF "effort: overlay('effort', st)," <<<"$block" || { echo "stepArgs does not hand the step its effort"; return 1; }
  grep -qF "models: { type: 'string', description: 'only when the step declares its own [MODELS]" "$E" || { echo "the step record has no models"; return 1; }
  grep -qF "effort: { type: 'string', description: 'only when the step declares its own [EFFORT]" "$E" || { echo "the step record has no effort"; return 1; }
  grep -qF 'the text between the brackets of its [MODELS] and [EFFORT]' "$E" || { echo "read-steps never asks for them"; return 1; }
  grep -qF "if (m && TUNING_KEYS[field].includes(key) && TUNING_UNSET[field].includes(value)) continue" "$E" \
    || { echo "overlay does not skip a 1.11.0 platform silently"; return 1; }
  skip_at="$(grep -nF 'TUNING_UNSET[field].includes(value)) continue' "$E" | cut -d: -f1)"
  note_at="$(grep -nF 'TUNING_VALUES[field].includes(value)) out[key] = value' "$E" | cut -d: -f1)"
  [ -n "$skip_at" ] && [ -n "$note_at" ] && [ "$skip_at" -lt "$note_at" ] \
    || { echo "the silent skip ($skip_at) must come before the branch that writes a note ($note_at)"; return 1; }
}

@test "every workflow skill dispatches a stage on the model the rule derives" {
  n=0
  for f in "$ROOT"/skills/workflow-*/SKILL.md; do
    n=$((n + 1))
    para="$(grep '^A stage names its owner as a role in brackets' "$f")"
    [ -n "$para" ] || { echo "$f: no dispatch paragraph"; return 1; }
    grep -qF '`conventions/stage-dispatch.md` → Model and effort' <<<"$para" || { echo "$f: the paragraph does not point at the rule"; return 1; }
    grep -qF 'cannot pass an effort' <<<"$para" || { echo "$f: the paragraph does not say effort stays behind"; return 1; }
    grep -qF 'a walkthrough takes its own `walkthrough` key, then `light`' <<<"$para" \
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

# --- The runtime axis: runtimes/<id>.json and --runtime (conventions/task-settings.md → Runtime) ---

rt_task() {
  local p="$1"; local t="$p/Tasks/ACTIVE/001-x"
  mkdir -p "$t"; cp "$ROOT/templates/task-md/task-root.md" "$t/Task.md"
  printf '%s' "$t"
}
json_field() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1], {"d": d}))' "$1"; }

@test "without --runtime the resolver answers as claude-code" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  cp "$TPL" "$p/SPINE.md"
  plain="$("$ROOT/scripts/resolve-settings.sh" json "$t" 2>/dev/null)"
  flagged="$("$ROOT/scripts/resolve-settings.sh" json "$t" --runtime claude-code 2>/dev/null)"
  [ "$plain" = "$flagged" ]
  [ "$(json_field 'd["runtime"]' <<<"$plain")" = "claude-code" ]
}

@test "codex-cli takes any model token and defaults every key to session" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODELS] = [reviewer: gpt-6.1-sol]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(json_field 'd["models"]["reviewer"]' <<<"$output")" = "gpt-6.1-sol" ]
  [ "$(json_field 'd["models"]["light"]' <<<"$output")" = "session" ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "session" ]
  [ "$(json_field 'd["runtime"]' <<<"$output")" = "codex-cli" ]
}

@test "codex-cli accepts a run-level model token" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli --set models.reviewer=gpt-6.1-sol
  [ "$status" -eq 0 ]
  [ "$(json_field 'd["models"]["reviewer"]' <<<"$output")" = "gpt-6.1-sol" ]
  [ "$(json_field 'd["sources"]["models.reviewer"]' <<<"$output")" = "run" ]
}

@test "codex-cli has no max effort and warns past it" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[EFFORT] = [reviewer: max]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]
  [ "$(json_field 'd["effort"]["reviewer"]' <<<"$output")" = "session" ]
  grep -q "'reviewer: max' not recognized, skipped" <<<"$stderr"
}

@test "claude-code still rejects a foreign model name" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODELS] = [reviewer: gpt-6.1-sol]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t"
  [ "$status" -eq 0 ]
  [ "$(json_field 'd["models"]["reviewer"]' <<<"$output")" = "session" ]
  grep -q "'reviewer: gpt-6.1-sol' not recognized, skipped" <<<"$stderr"
}

@test "an unknown runtime, a repeated flag and raw --runtime exit 2" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime nope
  [ "$status" -eq 2 ]
  grep -q -- '--runtime nope: no runtimes/nope.json' <<<"$stderr"
  run "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime claude-code --runtime codex-cli
  [ "$status" -eq 2 ]
  run "$ROOT/scripts/resolve-settings.sh" raw "$t" Platform --runtime codex-cli
  [ "$status" -eq 2 ]
}

@test "show passes --runtime through to its plain json run" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  run "$ROOT/scripts/resolve-settings.sh" show "$t" --runtime codex-cli --set models.reviewer=gpt-6.1-sol
  [ "$status" -eq 0 ]
  grep -q 'gpt-6.1-sol' <<<"$output"
}

@test "show keeps the 2.28.0 key order: roles first, then light, walkthrough, done" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODELS] = [reviewer: opus, light: haiku]\n' >> "$t/Task.md"
  run "$ROOT/scripts/resolve-settings.sh" show "$t"
  [ "$status" -eq 0 ]
  grep -qF '[MODELS] = [reviewer: opus, light: haiku]' <<<"$output" || { echo "$output"; return 1; }
}

@test "an open vocabulary still folds session to lowercase" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODELS] = [reviewer: Session, light: GPT-X]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]
  [ "$(json_field 'd["models"]["reviewer"]' <<<"$output")" = "session" ]
  [ "$(json_field 'd["models"]["light"]' <<<"$output")" = "GPT-X" ]
}

@test "a runtime file with the wrong shape is refused by name" {
  mkdir -p "$BATS_TEST_TMPDIR/core/runtimes" "$BATS_TEST_TMPDIR/core/scripts"
  cp "$ROOT/scripts/resolve-settings.sh" "$BATS_TEST_TMPDIR/core/scripts/"
  printf '{"id": "bad", "models": "opus", "model_defaults": {"Light": "opus"}, "effort": ["session"]}\n' > "$BATS_TEST_TMPDIR/core/runtimes/bad.json"
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  run --separate-stderr "$BATS_TEST_TMPDIR/core/scripts/resolve-settings.sh" json "$t" --runtime bad
  [ "$status" -eq 2 ]
  grep -q 'runtimes/bad.json' <<<"$stderr"
}
