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
