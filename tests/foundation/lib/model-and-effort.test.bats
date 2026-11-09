#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# A subagent's model and effort come from one rule (conventions/stage-dispatch.md → Model and effort)
# and one resolver (scripts/resolve-settings.sh). These tests hold every surface that restates a piece
# of the rule to it: a surface that drifts is how a project's choice stops reaching a dispatch.

load "$(dirname "$BATS_TEST_FILENAME")/../helpers/config-doc"

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
  grep -qxF '| `walkthrough` | `models.walkthrough`, else `models[role]` | `effort.walkthrough`, else `effort[role]` |' <<<"$s" \
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
  for token in 'CLAUDE_CODE_SUBAGENT_MODEL' '200k' 'Sonnet 4.5' '[MODELS]' 'as if its line were absent' 'walkthrough: sonnet'; do
    grep -qF "$token" "$doc" || { echo "the guidance does not mention $token"; return 1; }
  done
}

@test "the doc lets a task override MODELS and EFFORT, with the resolver's roles and the runtime's values" {
  roles="$(sed -n 's/^ROLES="\(.*\)"$/\1/p' "$ROOT/scripts/resolve-settings.sh")"
  [ "$(wc -w <<<"$roles")" -eq 8 ] || { echo "the resolver has '$roles', not the eight roles the doc counts"; return 1; }
  # Keys beyond the roles: MODELS has light, walkthrough and done; EFFORT has no light.
  extra_MODELS="light walkthrough done"
  extra_EFFORT="walkthrough done"
  # The vocabulary the doc quotes is the Claude runtime's, named as such: other runtimes have their own.
  rt() { python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$ROOT/runtimes/claude-code.json" "$1"; }
  for pair in MODELS:models EFFORT:effort; do
    field="${pair%%:*}"
    config_doc_offers "$field" || { echo "no overridable [$field] in the doc"; return 1; }
    sec="$(config_doc_section "$field" | tr '\n' ' ')"
    grep -qF "\`[$field] = [<key>: <value>, …]\`" <<<"$sec" || { echo "[$field]: the override spelling is missing"; return 1; }
    grep -qF 'the eight role' <<<"$sec" || { echo "[$field]: the doc does not count the eight roles"; return 1; }
    # the key paragraph, as the doc's first paragraph of the section, names the keys beyond the roles
    keys="$(config_doc_section "$field" | awk '$0 == "" { if (n) exit; next } { n = 1; print }' | tr '\n' ' ')"
    extra="extra_$field"
    for k in ${!extra} $roles; do
      grep -qF "\`$k\`" <<<"$sec" || { echo "[$field]: the key $k is not in the doc section"; return 1; }
    done
    for k in ${!extra}; do
      grep -qF "\`$k\`" <<<"$keys" || { echo "[$field]: the key $k is not in the Values paragraph"; return 1; }
    done
    if [ "$field" = EFFORT ]; then
      ! grep -qF '`light`' <<<"$keys" || { echo "[EFFORT] lists a light key; the resolver has none"; return 1; }
    fi
    for v in $(rt "${pair##*:}"); do
      grep -qF "\`$v\`" <<<"$sec" || { echo "[$field]: the runtime value $v is not in the doc"; return 1; }
    done
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
                "  const model = own(A.models) || (kind !== 'stage' && kind !== 'done' && kind !== 'walkthrough' && pick(A.models, 'light', 'session')) || pick(A.models, role, 'session')" \
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
    grep -qF 'a walkthrough takes its own `walkthrough` key, then its role' <<<"$para" \
      || { echo "$f: the paragraph does not give a walkthrough its own key first"; return 1; }
    grep -qF 'where the rule yields `session`' <<<"$para" || { echo "$f: the paragraph does not name session"; return 1; }
  done
  [ "$n" -eq 8 ] || { echo "scanned $n skill(s), expected 8"; return 1; }
}

@test "a walkthrough never falls onto light" {
  command -v node >/dev/null 2>&1 || skip "node is not installed"
  block="$(awk '/^const tuning = /,/^}/' "$ROOT/workflows/profile-feature.js")"
  [ -n "$block" ] || { echo "no tuning block in profile-feature.js"; return 1; }
  run node -e "
    const run = (models) => {
      const A = { models, effort: null }
      $block
      return tuning
    }
    const m = (models, role, kind) => run(models)(role, kind).model
    const same = { architect: 'session', developer: 'session', walkthrough: 'session', light: 'session', done: 'session' }
    const cases = [
      [m({ walkthrough: 'session', light: 'sonnet', architect: 'opus' }, 'architect', 'walkthrough'), 'opus'],
      [m({ walkthrough: 'session', light: 'sonnet', architect: 'opus' }, 'architect', 'light'), 'sonnet'],
      [m({ walkthrough: 'session', light: 'sonnet', architect: 'opus' }, 'architect', 'done'), 'opus'],
      [m({ walkthrough: 'sonnet', architect: 'opus' }, 'architect', 'walkthrough'), 'sonnet'],
      [m({ walkthrough: 'session', light: 'sonnet', architect: 'session' }, 'architect', 'walkthrough'), undefined],
      [m(same, 'architect', 'walkthrough'), undefined],
      [Object.keys(run(same)('architect', 'walkthrough')).includes('model'), false],
    ]
    const bad = cases.map(([got, want], i) => [i, got, want]).filter(([, got, want]) => got !== want)
    if (bad.length) { console.log(JSON.stringify(bad)); process.exit(1) }
  "
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
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
  # validator is the shipped fast default with no line for the runtime, so the column names it too.
  grep -qF '[MODELS] = [reviewer: opus, validator: fast → session, no fast@claude-code, light: haiku]' <<<"$output" || { echo "$output"; return 1; }
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

@test "codex-cli reads a Claude model as session and says so" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODELS] = [validator: sonnet, tester: opus, reviewer: gpt-6-luna]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "session" ]
  [ "$(json_field 'd["models"]["tester"]' <<<"$output")" = "session" ]
  [ "$(json_field 'd["models"]["reviewer"]' <<<"$output")" = "gpt-6-luna" ]
  [ "$(json_field 'd["sources"]["models.validator"]' <<<"$output")" = "project" ]
  grep -qF "'validator: sonnet' is not a codex-cli model, read as session" <<<"$stderr"
  grep -qF "'tester: opus' is not a codex-cli model, read as session" <<<"$stderr"
}

@test "codex-cli reads a full Claude model id as session" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODELS] = [validator: claude-sonnet-4-6, reviewer: gpt-6-luna]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "session" ]
  [ "$(json_field 'd["models"]["reviewer"]' <<<"$output")" = "gpt-6-luna" ]
  grep -qF "'validator: claude-sonnet-4-6' is not a codex-cli model, read as session" <<<"$stderr"
}

@test "a nearer Claude model still decides the key under codex-cli" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODELS] = [validator: gpt-6-luna]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli --set models.validator=sonnet
  [ "$status" -eq 0 ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "session" ]
  [ "$(json_field 'd["sources"]["models.validator"]' <<<"$output")" = "run" ]
}

@test "claude-code keeps sonnet as written" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODELS] = [validator: sonnet, tester: opus]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "sonnet" ]
  [ "$(json_field 'd["models"]["tester"]' <<<"$output")" = "opus" ]
}

@test "only the source that decides a key reports a Claude model" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODELS] = [validator: sonnet]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli --set models.validator=gpt-6-luna
  [ "$status" -eq 0 ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "gpt-6-luna" ]
  ! grep -qF 'read as session' <<<"$stderr" || { echo "$stderr"; false; }
}

# --- Model tiers: fast resolves through [MODEL_TIERS] (docs/superpowers/specs/2026-11-10-model-tiers-design.md) ---

@test "fast resolves through the project's MODEL_TIERS in each runtime" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODEL_TIERS] = [fast@claude-code: sonnet, fast@codex-cli: gpt-6-mini]\n[MODELS] = [validator: fast]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t"
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "sonnet" ]
  [ "$(json_field 'd["model_tiers"]["validator"]["source"]' <<<"$output")" = "project" ]
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "gpt-6-mini" ]
}

@test "fast without a line for the runtime reads as session and says so" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODEL_TIERS] = [fast@claude-code: sonnet]\n[MODELS] = [validator: fast]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "session" ]
  [ "$(json_field 'd["model_tiers"]["validator"]["source"]' <<<"$output")" = "unset" ]
  grep -qF "'validator: fast' has no fast@codex-cli in [MODEL_TIERS], read as session" <<<"$stderr"
}

@test "claude-code defaults light and validator to fast" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  : > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t"
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$(json_field 'd["models"]["light"]' <<<"$output")" = "session" ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "session" ]
  [ "$(json_field 'd["model_tiers"]["light"]["source"]' <<<"$output")" = "unset" ]
  [ "$(json_field 'sorted(d["model_tiers"])' <<<"$output")" = "['light', 'validator']" ]
}

@test "codex-cli has no fast default, so model_tiers is empty" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  : > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$(json_field 'd["model_tiers"]' <<<"$output")" = "{}" ]
}

@test "explicit session in MODEL_TIERS is session, silently" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODEL_TIERS] = [fast@codex-cli: session]\n[MODELS] = [validator: fast]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "session" ]
  [ "$(json_field 'd["model_tiers"]["validator"]["source"]' <<<"$output")" = "project" ]
}

@test "MODEL_TIERS in a Task.md is not read" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  : > "$p/SPINE.md"
  printf '[MODEL_TIERS] = [fast@claude-code: sonnet]\n[MODELS] = [validator: fast]\n' >> "$t/Task.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t"
  [ "$status" -eq 0 ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "session" ]
}

@test "a run-level fast resolves through the project's tiers" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODEL_TIERS] = [fast@claude-code: haiku]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --set models.validator=fast
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "haiku" ]
  [ "$(json_field 'd["sources"]["models.validator"]' <<<"$output")" = "run" ]
  printf '[MODEL_TIERS] = [fast@claude-code: haiku]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli --set models.validator=fast
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "session" ]
  grep -qF -- "--set models: 'validator: fast' has no fast@codex-cli in [MODEL_TIERS], read as session" <<<"$stderr"
}

@test "a Task.md fast names its source in the unset line" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  : > "$p/SPINE.md"
  printf '[MODELS] = [tester: fast]\n' >> "$t/Task.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]
  [ "$(json_field 'd["sources"]["models.tester"]' <<<"$output")" = "task" ]
  grep -qF "Task.md [MODELS]: 'tester: fast' has no fast@codex-cli in [MODEL_TIERS], read as session" <<<"$stderr"
}

@test "tier keys are case-insensitive, malformed ones are skipped" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODEL_TIERS] = [FAST@Codex-CLI: GPT-X]\n[MODELS] = [Validator: FAST]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "GPT-X" ]
  printf '[MODEL_TIERS] = [fast @ codex-cli: x]\n[MODELS] = [validator: fast]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "session" ]
  grep -qF "[MODEL_TIERS]: 'fast @ codex-cli: x' not recognized, skipped" <<<"$stderr"
}

@test "bad MODEL_TIERS entries are skipped by name" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  for entry in 'slow@codex-cli: x' 'fast@nope: x' 'fast@claude-code: gpt-6-mini' 'fast@codex-cli: opus'; do
    printf '[MODEL_TIERS] = [%s]\n[MODELS] = [validator: fast]\n' "$entry" > "$p/SPINE.md"
    run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
    [ "$status" -eq 0 ]
    grep -qF "[MODEL_TIERS]: '$entry' not recognized, skipped" <<<"$stderr" || { echo "$entry: $stderr"; return 1; }
    [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "session" ]
  done
}

@test "a good entry survives a bad neighbour, and a line for another runtime is checked too" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODEL_TIERS] = [fast@claude-code: gpt-6-mini, fast@codex-cli: gpt-6-mini]\n[MODELS] = [validator: fast]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "gpt-6-mini" ]
  grep -qF "[MODEL_TIERS]: 'fast@claude-code: gpt-6-mini' not recognized, skipped" <<<"$stderr"
}

@test "the later of two lines for a tier wins" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODEL_TIERS] = [fast@codex-cli: first]\n[MODEL_TIERS] = [fast@codex-cli: second]\n[MODELS] = [validator: fast]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" json "$t" --runtime codex-cli
  [ "$status" -eq 0 ]; [ -z "$stderr" ]
  [ "$(json_field 'd["models"]["validator"]' <<<"$output")" = "second" ]
}

# --- Model tiers in the settings column ---

@test "show names a tier and what it became" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODEL_TIERS] = [fast@claude-code: sonnet]\n[MODELS] = [reviewer: fast]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" show "$t"
  [ "$status" -eq 0 ]
  grep -qF 'reviewer: fast → sonnet' <<<"$output" || { echo "$output"; return 1; }
}

@test "show always names a tier with no line for the runtime" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  : > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" show "$t" --runtime claude-code
  [ "$status" -eq 0 ]
  grep -qF 'light: fast → session, no fast@claude-code' <<<"$output" || { echo "$output"; return 1; }
  grep -qF 'validator: fast → session, no fast@claude-code' <<<"$output" || { echo "$output"; return 1; }
}

@test "show leaves a set default tier out of the diff" {
  p="$BATS_TEST_TMPDIR/p"; t="$(rt_task "$p")"
  printf '[MODEL_TIERS] = [fast@claude-code: sonnet]\n[MODELS] = [light: fast, validator: fast]\n' > "$p/SPINE.md"
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" show "$t"
  [ "$status" -eq 0 ]
  ! grep -q '^\[MODELS\]' <<<"$output" || { echo "$output"; return 1; }
  run --separate-stderr "$ROOT/scripts/resolve-settings.sh" show "$t" --all
  grep -qF 'validator: fast → sonnet' <<<"$output" || { echo "$output"; return 1; }
}
