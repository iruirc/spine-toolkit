#!/usr/bin/env bats
# The task's own documents are committed in one place, the orchestrator, after Done — never with Run.json.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  SKILL="$ROOT/skills/orchestrator/SKILL.md"
}

S_OF() { awk -v h="## $1" '$0==h{f=1;next} f&&/^## /{exit} f' "$SKILL"; }

@test "the orchestrator commits the task folder after Done, once Run.json is gone, and never stages it" {
  w="$(S_OF "The run's own words")"
  for f in "**The task's documents.**" "once a return's \`last_completed_stage\` is \`Done\`" \
           "— after \`Run.json\`" "\`-- . ':(exclude,glob)**/Run.json'\`" "\`git -C <task dir> add -A X\`" \
           "\`git -C <task dir> commit -m '<message>' X\`" 'holding nothing else the index has' \
           '`check-ignore -q .`' 'info_task_docs_uncommitted'; do
    grep -qF -- "$f" <<<"$w" || { echo "the rule lost: $f"; return 1; }
  done
  deleted="$(grep -n -- '^- \*\*Deleted\*\* once' "$SKILL" | cut -d: -f1)"
  rule="$(grep -n -- "^\*\*The task's documents\.\*\*" "$SKILL" | cut -d: -f1)"
  [ -n "$deleted" ] || { echo "the Run.json deletion bullet is gone"; return 1; }
  [ -n "$rule" ] || return 1
  [ "$rule" -gt "$deleted" ] || { echo "the commit rule precedes the deletion of Run.json"; return 1; }
}

@test "both locales carry the line for a folder git does not keep" {
  for l in en ru; do
    grep -qx '## info_task_docs_uncommitted' "$ROOT/skills/orchestrator/locales/$l.md" \
      || { echo "$l lacks info_task_docs_uncommitted"; return 1; }
  done
}

# Acceptance of milestone 6 (545, 548): Tasks/ was a repository of its own, the project's .gitignore
# listed it, and the run concluded from the project root that the folder was ignored — nothing committed.
@test "the ignore check runs in the task folder, and a tasks repository of its own is committed" {
  w="$(S_OF "The run's own words")"
  for f in 'never from the project root' 'a repository of its own' 'No stage decides the folder is ignored'; do
    grep -qF -- "$f" <<<"$w" || { echo "the rule lost: $f"; return 1; }
  done
}

# The orchestrator's commit of a task folder: foreign names what the folder may not hold, add -A takes
# the rest. An evidence folder holds only scrubbed excerpts, so no secret and no raw log reaches history.
@test "a task's commit holds no secret and no raw file" {
  FIX="$ROOT/tests/foundation/fixtures/evidence"
  P="$BATS_TEST_TMPDIR/Proj"; TASK="$P/Tasks/ACTIVE/042"
  mkdir -p "$TASK"; cp "$FIX/SPINE.md" "$P/SPINE.md"; printf '# Task\n' >"$TASK/Task.md"
  git -C "$P" init -q -b main
  "$ROOT/scripts/evidence.sh" keep "$FIX/secrets.log" "$TASK/validation-evidence/t" --name app
  "$ROOT/scripts/evidence.sh" keep "$FIX/secrets.log" "$TASK/phase-evidence/phase-1" --name build
  mkdir -p "$TASK/validation-evidence/t/raw"; printf 'png' >"$TASK/validation-evidence/t/raw/shot.png"
  [ -f "$TASK/validation-evidence/t/raw/app.log" ]
  run "$ROOT/scripts/stage-leftovers.sh" foreign "$TASK"
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$status $output"; return 1; }
  # A raw copy made by hand is found, and excluded the way the orchestrator excludes it.
  cp "$FIX/secrets.log" "$TASK/validation-evidence/t/by-hand.log"
  run "$ROOT/scripts/stage-leftovers.sh" foreign "$TASK"
  [ "$status" -eq 1 ] && [ "$output" = "foreign path=validation-evidence/t/by-hand.log" ] || { echo "$status $output"; return 1; }
  X=(-- . ':(exclude,glob)**/Run.json')
  while IFS= read -r line; do X+=(":(exclude,literal)${line#foreign path=}"); done <<<"$output"
  git -C "$TASK" add -A "${X[@]}"
  git -C "$TASK" -c user.email=t@t -c user.name=t commit -qm docs "${X[@]}"
  run git -C "$P" grep FAKE HEAD
  [ "$status" -eq 1 ] && [ -z "$output" ] || { echo "$status $output"; return 1; }
  ! git -C "$P" ls-tree -r HEAD --name-only | grep -q '/raw/' || { git -C "$P" ls-tree -r HEAD --name-only; return 1; }
  git -C "$P" ls-tree -r HEAD --name-only | grep -qx 'Tasks/ACTIVE/042/validation-evidence/t/app.log'
}
