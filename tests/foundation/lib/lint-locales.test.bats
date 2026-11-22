#!/usr/bin/env bats
# lint-locales.sh holds Russian strings to one address form, the informal one
# (conventions/i18n.md). The orchestrator's locale mixed both for months because
# nothing checked it.

setup() {
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  TREE="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$TREE/scripts" "$TREE/skills/demo/locales"
  cp "$ROOT/scripts/lint-locales.sh" "$TREE/scripts/"
  printf '# demo\n\n## Language Resolution\n' > "$TREE/skills/demo/SKILL.md"
  printf '# demo — en\n\n## hint\nRun `/setup` again.\n' > "$TREE/skills/demo/locales/en.md"
}

# A Russian string as \uXXXX escapes: no Cyrillic outside *.ru.md.
ru() { python3 -c 'import sys; sys.stdout.write(sys.argv[1].encode().decode("unicode_escape"))' "$1"; }

ru_hint() { printf '# demo \xe2\x80\x94 ru\n\n## hint\n%s\n' "$(ru "$1")" > "$TREE/skills/demo/locales/ru.md"; }

@test "the toolkit tree passes the locale lint" {
  run "$ROOT/scripts/lint-locales.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a formal imperative in ru.md fails the lint" {
  # "Zapustite /setup snova."
  ru_hint '\u0417\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u0435 `/setup` \u0441\u043d\u043e\u0432\u0430.'
  run "$TREE/scripts/lint-locales.sh"
  [ "$status" -ne 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"ru.md:4: formal address"* ]] || { echo "$output"; return 1; }
}

@test "a formal pronoun in ru.md fails the lint" {
  # "Eto ne vashe slovo."
  ru_hint '\u042d\u0442\u043e \u043d\u0435 \u0432\u0430\u0448\u0435 \u0441\u043b\u043e\u0432\u043e.'
  run "$TREE/scripts/lint-locales.sh"
  [ "$status" -ne 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"formal address"* ]] || { echo "$output"; return 1; }
}

@test "an informal imperative passes the lint" {
  # "Zapusti /setup snova."
  ru_hint '\u0417\u0430\u043f\u0443\u0441\u0442\u0438 `/setup` \u0441\u043d\u043e\u0432\u0430.'
  run "$TREE/scripts/lint-locales.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a noun with an imperative-like ending passes the lint" {
  # "Pravka lezhit v kommite." -- "kommite" ends like an imperative and is not one.
  ru_hint '\u041f\u0440\u0430\u0432\u043a\u0430 \u043b\u0435\u0436\u0438\u0442 \u0432 \u043a\u043e\u043c\u043c\u0438\u0442\u0435.'
  run "$TREE/scripts/lint-locales.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
