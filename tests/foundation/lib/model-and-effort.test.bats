#!/usr/bin/env bats
# A subagent's model and effort come from one rule (conventions/stage-dispatch.md → Model and effort)
# and one resolver (scripts/resolve-tuning.sh). These tests hold every surface that restates a piece
# of the rule to it: a surface that drifts is how a project's choice stops reaching a dispatch.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  RULE="$ROOT/conventions/stage-dispatch.md"
  TPL="$ROOT/templates/claude-toolkit-md/en.md"
}

section() { awk -v h="$2" '$0==h{f=1;next} f&&/^## /{exit} f' "$1"; }

@test "the rule names the three kinds and both closed lists" {
  s="$(section "$RULE" '## Model and effort')"
  [ -n "$s" ] || { echo "no ## Model and effort section"; return 1; }
  for token in '`stage`' '`light`' '`mechanical`' '`walkthrough`' '`<stage>:read-plan`' '`execute:read-steps`' \
               '`execute:tick:<step>`' '`done:read-branch`' '`auto-move`' '`done`'; do
    grep -qF "$token" <<<"$s" || { echo "the rule does not name $token"; return 1; }
  done
}

@test "the rule's table gives each kind its model and effort" {
  s="$(section "$RULE" '## Model and effort')"
  grep -qxF '| `stage` | `models[role]` | `effort[role]` |' <<<"$s" || { echo "no stage row"; return 1; }
  grep -qxF '| `light` | `models.light`, else `models[role]` | `effort[role]` |' <<<"$s" || { echo "no light row"; return 1; }
  grep -qxF '| `mechanical` | `models.light`, else `models[role]` | `low` |' <<<"$s" || { echo "no mechanical row"; return 1; }
}

@test "the rule states the host's order with its version, and what Method B cannot pass" {
  s="$(section "$RULE" '## Model and effort')"
  for token in 'CLAUDE_CODE_SUBAGENT_MODEL' '2.1.251' 'Method B' 'cannot pass effort' 'main context'; do
    grep -qF "$token" <<<"$s" || { echo "the rule does not say $token"; return 1; }
  done
}

@test "agent tooling points a dispatch's model and effort at the rule" {
  grep -qF '`conventions/stage-dispatch.md` → Model and effort' "$ROOT/conventions/agent-tooling.md" \
    || { echo "agent-tooling.md does not point at the rule"; return 1; }
}

@test "the config template ships every Models key at its default, and no init" {
  block="$(section "$TPL" '## Models')"
  for line in 'light: sonnet' 'architect: platform' 'developer: platform' 'tester: platform' 'reviewer: platform' \
              'refactorer: platform' 'validator: platform' 'security: platform' 'diagnostics: platform'; do
    grep -qxF "$line" <<<"$block" || { echo "## Models lacks '$line'"; return 1; }
  done
  ! grep -q '^init:' <<<"$block" || { echo "## Models names init, which no profile dispatches"; return 1; }
}

@test "the config template ships every Effort key at session, and no light" {
  block="$(section "$TPL" '## Effort')"
  for role in architect developer tester reviewer refactorer validator security diagnostics; do
    grep -qxF "$role: session" <<<"$block" || { echo "## Effort lacks '$role: session'"; return 1; }
  done
  ! grep -q '^light:' <<<"$block" || { echo "## Effort carries light, which no effort reads"; return 1; }
}

@test "the Models guidance names what platform passes and the limits a user can trip on" {
  block="$(section "$TPL" '## Models')"
  for token in 'CLAUDE_CODE_SUBAGENT_MODEL' '200k' 'Sonnet 4.5' '[MODELS]'; do
    grep -qF "$token" <<<"$block" || { echo "## Models guidance does not mention $token"; return 1; }
  done
}

@test "both task templates offer the MODELS and EFFORT overrides" {
  for t in task-root task-step; do
    grep -qF '# [MODELS] = [architect: opus]' "$ROOT/templates/task-md/$t.md" || { echo "no [MODELS] in $t.md"; return 1; }
    grep -qF '# [EFFORT] = [reviewer: high]' "$ROOT/templates/task-md/$t.md" || { echo "no [EFFORT] in $t.md"; return 1; }
  done
}

@test "task-new says when a task overrides a model or an effort" {
  f="$ROOT/skills/task-new/SKILL.md"
  grep -qF '`[MODELS] = [<key>: <value>, …]`' "$f" || { echo "task-new lacks [MODELS]"; return 1; }
  grep -qF '`[EFFORT] = [<role>: <value>, …]`' "$f" || { echo "task-new lacks [EFFORT]"; return 1; }
}

@test "every profile script defines tuning() as the rule states it" {
  n=0
  for p in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    for line in "const tuning = (role, kind) => {" \
                "  const pick = (map, key, none) => (map && map[key] && map[key] !== none ? map[key] : null)" \
                "  const model = (kind !== 'stage' && pick(A.models, 'light', 'platform')) || pick(A.models, role, 'platform')" \
                "  const effort = kind === 'mechanical' ? 'low' : pick(A.effort, role, 'session')" \
                "  return { ...(model ? { model } : {}), ...(effort ? { effort } : {}) }"; do
      grep -qxF "$line" "$p" || { echo "$(basename "$p"): missing '$line'"; return 1; }
    done
  done
  [ "$n" -eq 7 ] || { echo "scanned $n script(s), expected 7"; return 1; }
}

@test "the epic's copy of the vocabulary is the resolver's" {
  verdict="$(python3 - "$ROOT/scripts/resolve-tuning.sh" "$ROOT/workflows/profile-epic.js" <<'PY'
import re, sys
sh = open(sys.argv[1], encoding='utf-8').read()
js = open(sys.argv[2], encoding='utf-8').read()
var = lambda name: re.search(r'^%s="([^"]*)"' % name, sh, re.M).group(1).split()
keys = re.search(r'^const TUNING_KEYS = \{ models: \[([^\]]*)\], effort: \[([^\]]*)\] \}$', js, re.M)
values = re.search(r'^const TUNING_VALUES = \{ models: \[([^\]]*)\], effort: \[([^\]]*)\] \}$', js, re.M)
if not keys or not values:
    print('profile-epic.js carries no TUNING_KEYS / TUNING_VALUES line'); raise SystemExit
q = lambda s: re.findall(r"'([a-z]+)'", s)
want = (['light'] + var('ROLES'), var('ROLES'), var('MODELS'), var('EFFORTS'))
have = (q(keys.group(1)), q(keys.group(2)), q(values.group(1)), q(values.group(2)))
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
}

@test "every workflow skill dispatches a stage on the model the rule derives" {
  n=0
  for f in "$ROOT"/skills/workflow-*/SKILL.md; do
    n=$((n + 1))
    para="$(grep '^A stage names its owner as a role in brackets' "$f")"
    [ -n "$para" ] || { echo "$f: no dispatch paragraph"; return 1; }
    grep -qF '`conventions/stage-dispatch.md` → Model and effort' <<<"$para" || { echo "$f: the paragraph does not point at the rule"; return 1; }
    grep -qF 'cannot pass an effort' <<<"$para" || { echo "$f: the paragraph does not say effort stays behind"; return 1; }
  done
  [ "$n" -eq 7 ] || { echo "scanned $n skill(s), expected 7"; return 1; }
}
