#!/usr/bin/env bats
# runtimes/<id>.json is where a runtime's model and effort vocabulary and its model defaults
# live (conventions/task-settings.md → Runtime). The resolver reads it; nothing else may
# restate it. A file that is not valid or not complete leaves every project on that runtime
# without a resolver, so the shape is held here.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "every runtime file is valid and complete" {
  verdict="$(python3 - "$ROOT/runtimes" <<'PY'
import glob, json, os, re, sys
KEYS = {'light', 'walkthrough', 'done', 'architect', 'developer', 'tester', 'reviewer', 'refactorer',
        'validator', 'security', 'diagnostics'}
files = sorted(glob.glob(os.path.join(sys.argv[1], '*.json')))
if not files:
    print('no runtime files'); raise SystemExit
for f in files:
    rt = json.load(open(f, encoding='utf-8'))
    name = os.path.basename(f)[:-5]
    if rt.get('id') != name:
        print('%s: id %r is not %r' % (name, rt.get('id'), name)); raise SystemExit
    models = rt.get('models')
    if models != 'any' and not (isinstance(models, list) and 'session' in models):
        print('%s: models must be a list holding session, or "any"' % name); raise SystemExit
    effort = rt.get('effort')
    if not (isinstance(effort, list) and 'session' in effort):
        print('%s: effort must be a list holding session' % name); raise SystemExit
    defaults = rt.get('model_defaults')
    if not isinstance(defaults, dict) or set(defaults) - KEYS:
        print('%s: model_defaults keys must be tuning keys' % name); raise SystemExit
    if models != 'any' and set(defaults.values()) - set(models):
        print('%s: model_defaults values must be in models' % name); raise SystemExit
    if models == 'any' and any(not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._:/+-]*', v) for v in defaults.values()):
        print('%s: model_defaults values must be tokens' % name); raise SystemExit
print('ok %d' % len(files))
PY
)"
  case "$verdict" in ok\ [2-9]|ok\ [1-9][0-9]) ;; *) echo "$verdict"; return 1 ;; esac
}

@test "the two first-iteration runtimes exist with the presets the spec names" {
  [ "$(python3 -c 'import json; print(json.load(open("'"$ROOT"'/runtimes/claude-code.json"))["model_defaults"]["light"])')" = "sonnet" ]
  [ "$(python3 -c 'import json; print(json.load(open("'"$ROOT"'/runtimes/codex-cli.json"))["models"])')" = "any" ]
  [ "$(python3 -c 'import json; print(json.load(open("'"$ROOT"'/runtimes/codex-cli.json"))["model_defaults"])')" = "{}" ]
}

@test "every runtime but claude-code has a markdown map" {
  for f in "$ROOT"/runtimes/*.json; do
    id="$(basename "$f" .json)"
    [ "$id" = claude-code ] || [ -f "$ROOT/runtimes/$id.md" ] || { echo "no runtimes/$id.md"; false; }
  done
}

@test "the Codex map names the tools a stage needs" {
  f="$ROOT/runtimes/codex-cli.md"
  for s in spawn_agent fork_turns '"none"' wait_agent 'numbered options' 'answer with its number' 'Do not use `functions.request_user_input_async`' '--runtime codex-cli' 'agents/<agent>.md'; do
    grep -qF -- "$s" "$f" || { echo "missing: $s"; false; }
  done
}

@test "the Codex map keeps runtime notes out of stage reports" {
  # A Codex run repeated "Codex, Method B, ps refused" and paraphrased SKILL.md paths after a stage.
  f="$ROOT/runtimes/codex-cli.md"
  grep -q '^## What the user sees' "$f"
  sec="$(awk '/^## What the user sees/{on=1; next} on && /^## /{exit} on' "$f")"
  grep -qF 'only in the final report' <<<"$sec"
  grep -qiF 'never paraphrase' <<<"$sec"
}

@test "the Codex map asks through the request_user_input menu when Default mode allows it" {
  # Interactive Codex 0.162.1 draws a menu for request_user_input once default_mode_request_user_input is on;
  # its description then names Default mode, and without the feature a call fails with "unavailable in".
  f="$ROOT/runtimes/codex-cli.md"
  row="$(grep -F '`AskUserQuestion`' "$f")"
  for s in '`functions.request_user_input`' 'Default mode' 'unavailable in' 'more than three options'; do
    grep -qF -- "$s" <<<"$row" || { echo "missing: $s"; false; }
  done
  ! grep -qF 'does not offer it' <<<"$row"
}

@test "the Codex map says a spine question is not a permission request" {
  # Codex reserves request_user_input for optional questions, never permission requests; a manual-mode
  # confirmation read as permission falls back to the async tool, which the CLI shows as plain text.
  grep -qF 'not a permission request' "$ROOT/runtimes/codex-cli.md"
}
