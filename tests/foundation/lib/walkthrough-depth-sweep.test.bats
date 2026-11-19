#!/usr/bin/env bats
# changed: sweep skills workflows
# Split from walkthrough-depth.test.bats: the tests that walk the source trees.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
}

@test "every profile script hands the resolved depth to the writing agent" {
  for p in "$ROOT"/workflows/profile-*.js; do
    grep -qF "const depth = A.walkthrough === 'brief' ? 'brief' : 'deep'" "$p" \
      || { echo "first miss — $(basename "$p"): does not normalise the axis to a depth"; return 1; }
    grep -qF 'Walkthrough.md at depth ${depth}' "$p" \
      || { echo "first miss — $(basename "$p"): the depth never reaches the brief"; return 1; }
    grep -qF 'its ## The switch section says what ${depth} changes, and its ## Reader section' "$p" \
      || { echo "first miss — $(basename "$p"): the brief drops where depth is defined"; return 1; }
  done
}

@test "the off gate still short-circuits before any agent is dispatched" {
  # brief and deep must both fall through it; only off and the legacy false stop. Anchored at both
  # ends, so an appended limb that stops brief goes red instead of still containing the substring.
  for p in "$ROOT"/workflows/profile-*.js; do
    grep -qF "if (!WALKTHROUGH_AGENT || A.walkthrough === 'off' || A.walkthrough === false) return" "$p" \
      || { echo "first miss — $(basename "$p"): the off gate moved or changed shape"; return 1; }
  done
}

@test "every profile that writes the file tells its agent the value is a depth" {
  for p in feature bug refactor test epic; do
    S="$ROOT/skills/workflow-$p/SKILL.md"
    grep -qF 'the depth the contract carries' "$S" \
      || { echo "workflow-$p: the stage does not say the value is a depth"; return 1; }
  done
}

@test "every profile script checks a changed walkthrough when the contract says so" {
  n=0
  for p in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    for line in "if (WALKTHROUGH_CHECK === 'on' && w.changed !== false) await checkWalkthrough(stage, agentType, depth, extra)" \
                'return w' \
                "label: 'walkthrough:check'" "label: 'walkthrough:revise'" \
                "schema: COLD_READ, ...tuning(WALKTHROUGH_AGENT, 'light')" \
                "schema: WALKTHROUGH_ARTIFACT, ...tuning(WALKTHROUGH_AGENT, 'walkthrough')" \
                "required: ['ok', 'artifact_path', 'summary', 'changed']" \
                'Return changed true when you wrote the file, false when you left it as it was.'; do
      grep -qF "$line" "$p" || { echo "$(basename "$p"): missing '$line'"; return 1; }
    done
  done
  [ "$n" -eq 8 ] || { echo "scanned $n script(s), expected 8"; return 1; }
}

@test "every profile script's writer reads the task and its research before git, and the skill's style wins" {
  n=0
  for p in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    for line in 'Before any git show, read ${DIR}/Task.md as a whole and, when it exists, ${DIR}/Research.md' \
                'list the 3 to 8 concepts the reader needs to follow this task' 'at deep they become ## Glossary' \
                "This skill's ## Style overrides any brevity instruction in your agent body."; do
      grep -qF -- "$line" "$p" || { echo "$(basename "$p"): missing '$line'"; return 1; }
    done
  done
  [ "$n" -eq 8 ] || { echo "scanned $n script(s), expected 8"; return 1; }
}

@test "the reader of the check is kept away from everything but the file" {
  for p in "$ROOT"/workflows/profile-*.js; do
    grep -qF 'open no other file of the task and no source file' "$p" \
      || { echo "$(basename "$p"): the reader is not confined to the file"; return 1; }
    grep -qF 'run no git command' "$p" || { echo "$(basename "$p"): the reader may still read git"; return 1; }
  done
}

@test "every profile that writes the file runs the check the contract asks for" {
  for p in feature bug refactor test epic; do
    S="$ROOT/skills/workflow-$p/SKILL.md"
    grep -qF '`walkthrough_check` is `on`' "$S" || { echo "workflow-$p: the check is never mentioned"; return 1; }
    grep -qF '`task-walkthrough` → `## Check`' "$S" || { echo "workflow-$p: the check does not point at its protocol"; return 1; }
  done
}

@test "every profile script has the writer run the history lint and reports what it left" {
  n=0
  for p in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    for line in "that range already ends at the task's last commit and \"\${core('scripts/lint-walkthrough.sh')}\" --words-per-sentence \${BUDGETS['words-per-sentence']} \${DIR} exits 0, change nothing" \
                "Last, run \"\${core('scripts/lint-walkthrough.sh')}\" --words-per-sentence \${BUDGETS['words-per-sentence']} \${DIR}." \
                'On exit 2 stop and return its output' 'a line that rule does not resolve is returned, not forced' \
                "lint: { type: 'string'" \
                'if (w.lint) result.notes.push(`Walkthrough.md lint: ${w.lint}`)'; do
      grep -qF -- "$line" "$p" || { echo "$(basename "$p"): missing '$line'"; return 1; }
    done
  done
  [ "$n" -eq 8 ] || { echo "scanned $n script(s), expected 8"; return 1; }
}

@test "every profile script's writer repairs each class the lint names" {
  n=0
  for p in "$ROOT"/workflows/profile-*.js; do
    n=$((n + 1))
    grep -qF "Each line it prints names a class: apply the skill's ## Refreshing rule for that class and run it once more." "$p" \
      || { echo "$(basename "$p"): the writer still reads every line as a commit gone from history"; return 1; }
  done
  [ "$n" -eq 8 ] || { echo "scanned $n script(s), expected 8"; return 1; }
}

@test "every workflow skill with an implementing stage refreshes the walkthrough after Done" {
  for p in feature bug refactor test quick; do
    S="$ROOT/skills/workflow-$p/SKILL.md"
    grep -qF 'Refresh `Walkthrough.md` after `Done.md` is written and its commits are made' "$S" \
      || { echo "workflow-$p: the refresh does not follow Done's commits"; return 1; }
    grep -qF 'Done never edits `Walkthrough.md`' "$S" || { echo "workflow-$p: Done is not kept out of the file"; return 1; }
    grep -qF 'When no item went to it and `scripts/lint-walkthrough.sh --current <task dir>` exits 0, the writer is not dispatched' "$S" \
      || { echo "workflow-$p: the writer runs even over a current file"; return 1; }
    if grep -qF 'Refresh `Walkthrough.md` here when' "$S"; then echo "workflow-$p: the old gate is still there"; return 1; fi
  done
}
