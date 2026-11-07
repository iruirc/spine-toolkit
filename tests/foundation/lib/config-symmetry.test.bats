#!/usr/bin/env bats
# The config's `## Task defaults` and the configuration doc are two halves of one vocabulary: a field
# in one and not the other is a field a user can set in a project and not in a task, or the reverse,
# and nothing but this test would say so. The task templates no longer list the fields; they point
# at the doc, and this test holds the pointer to what it points at.
load "$(dirname "$BATS_TEST_FILENAME")/../helpers/config-doc"

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  TPL="$ROOT/templates/spine-md/en.md"
}

fields_of_block() {
  awk '/^## Task defaults$/{f=1;next} f&&/^## /{exit} f' "$TPL" \
    | sed -n 's/^\[\([A-Z_]*\)\].*/\1/p' | sort
}

@test "the config's task defaults are exactly the fields the doc lets a task override" {
  diff <(fields_of_block) <(config_doc_overridable) \
    || { echo "## Task defaults of the template and the doc's Task override entries disagree"; return 1; }
}

@test "every field the doc lets a task override sits under its Task defaults, and none else does" {
  diff <(config_doc_fields | awk -F'\t' '$2 == "Task defaults" { print $1 }' | sort) \
       <(config_doc_overridable) \
    || { echo "the doc's ## Task defaults and its Task override entries disagree"; return 1; }
}

@test "every section of the doc states its Task override" {
  ! config_doc_fields | awk -F'\t' '$3 == "missing"' | grep . \
    || { echo "a section above has no **Task override:** entry"; return 1; }
}

@test "the doc names DOCS_NEW inside the DOCS section" {
  config_doc_section DOCS | grep -qF '[DOCS_NEW]' || { echo "[DOCS_NEW] is not documented in [DOCS]"; return 1; }
}

@test "every field of both config blocks is documented" {
  doc="$ROOT/docs/configuration.md"
  for f in $(sed -n 's/^\[\([A-Z_]*\)\].*/\1/p' "$TPL" | sort -u); do
    grep -qF "[$f]" "$doc" || { echo "docs/configuration.md does not document [$f]"; return 1; }
  done
}

@test "both task templates point at the configuration doc and list no field" {
  for t in task-root task-step; do
    f="$ROOT/templates/task-md/$t.md"
    grep -qxF '# Optional overrides: any field under "Task defaults" in the toolkit'"'"'s docs/configuration.md,' "$f" \
      || { echo "$t.md: the first pointer line is missing"; return 1; }
    grep -qxF '# written here as [FIELD] = [value] on a line of its own, replaces the project'"'"'s value for this task.' "$f" \
      || { echo "$t.md: the second pointer line is missing"; return 1; }
    # the pointer sits directly under the fixed lines, one block, two lines
    [ "$(grep -c '^# [^{]' "$f")" -eq 2 ] || { echo "$t.md: more comment lines than the pointer"; return 1; }
    ! grep -E '^# *\[[A-Z_]+\] *=' "$f" || { echo "$t.md still lists a field above"; return 1; }
    [ "$(grep -cE '^\[[A-Z_]+\] *=' "$f")" -ge 3 ] || { echo "$t.md lost its non-comment fields"; return 1; }
    grep -q '^\[TASK_TYPE\] = ' "$f" || { echo "$t.md lost [TASK_TYPE]"; return 1; }
  done
  grep -q '^\[STATUS\] = ' "$ROOT/templates/task-md/task-step.md" || { echo "task-step.md lost [STATUS]"; return 1; }
}
