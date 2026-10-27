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
