#!/usr/bin/env bash
# Shared bats helpers over docs/configuration.md: one `### [FIELD]` section per field, a
# `**Task override:**` entry in its first paragraph, and the `## ` block the section sits in.
# Source from a .bats file via:
#   load "$(dirname "$BATS_TEST_FILENAME")/../helpers/config-doc"

config_doc() {
  echo "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)/docs/configuration.md"
}

# One line per field section: FIELD<TAB>block<TAB>yes|no|missing, where block is the `## ` heading
# the section sits under and the last column says whether a task may override the field. The entry
# may wrap anywhere, so the first paragraph is joined before it is read.
config_doc_fields() {
  awk -F'\t' '
    function flush() {
      if (name == "") return
      gsub(/[ \t]+/, " ", para)
      i = index(para, "**Task override:** ")
      if (i == 0) verdict = "missing"
      else { rest = substr(para, i + 19); verdict = (rest ~ /^no( |$)/) ? "no" : "yes" }
      print name "\t" block "\t" verdict
      name = ""
    }
    /^## / { flush(); block = substr($0, 4); next }
    /^### \[/ { flush(); name = $0; sub(/^### \[/, "", name); sub(/\].*/, "", name); para = ""; open = 1; next }
    /^#/ { flush(); next }
    name != "" && open { if ($0 == "" && para != "") open = 0; else para = para " " $0 }
    END { flush() }
  ' "$(config_doc)"
}

# The fields a task may override, sorted, one per line.
config_doc_overridable() {
  config_doc_fields | awk -F'\t' '$3 == "yes" { print $1 }' | sort
}

# Succeeds when the field has a section a task may override, with the value list or spelling given.
config_doc_offers() {
  config_doc_fields | awk -F'\t' -v f="$1" '$1 == f && $3 == "yes" { ok = 1 } END { exit !ok }'
}

# The text of one field's section, up to the next heading.
config_doc_section() {
  awk -v h="### [$1]" '
    $0 == h { f = 1; next }
    f && /^#/ { exit }
    f' "$(config_doc)"
}
