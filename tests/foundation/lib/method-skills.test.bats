#!/usr/bin/env bats
# Core's four methodology skills are the process layer: they say which topic a
# decision belongs to and never which skill answers it. The skills that answer
# are the platform's, listed in its manifest `## Topics`, and a name written back
# into core re-binds core to one ecosystem — silently, because it still reads
# fine on an Apple project.

setup() {
  # BATS_TEST_FILENAME, not BASH_SOURCE[0]: bats sources a preprocessed copy of
  # the test file from a tmp dir, so BASH_SOURCE[0] there resolves to the copy.
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  METHOD_SKILLS="feature-landscape feature-requirements feature-estimation mobile-ops-checklist"
  # The topic names core's method skills use. Maintained by hand: `**bold**` is
  # overloaded in these files (`**Applicable**`, `**+30%–50%**`), so deriving the
  # list from them would flag emphasis, not topics.
  TOPICS='state management|navigation|networking|persistence|dependency graph|concurrency|errors|packaging|deep links'
}

@test "method skills name no platform skill" {
  offenders=""
  for s in $METHOD_SKILLS; do
    hits="$(grep -oE '\b(arch-[a-z-]+|architecture-choice|di-[a-z-]+|persistence-[a-z-]+|net-[a-z-]+|reactive-[a-z-]+|pkg-spm-design|nav-deeplinks|error-architecture|concurrency-architecture|workspace-[a-z-]+)\b' \
              "$ROOT/skills/$s/SKILL.md" | sort -u | tr '\n' ' ')"
    [ -z "$hits" ] || offenders="$offenders$s: $hits"$'\n'
  done
  [ -z "$offenders" ] || { echo "platform skill named in core:"; echo "$offenders"; return 1; }
}

@test "method skills carry no single-ecosystem implementation vocabulary" {
  # Framework, language and tooling names of one ecosystem — not the mobile
  # domain itself. App-store review windows, OS fragmentation, deep links and
  # paired examples (Keychain/Keystore, VoiceOver/TalkBack) are the subject
  # matter of these skills and stay; `@MainActor` or Core Data is one
  # ecosystem's answer written as if it were the only one.
  offenders=""
  for s in $METHOD_SKILLS; do
    hits="$(grep -ioE '\b(swift|swiftui|uikit|appkit|objective-?c|xcode|xcframework|xctest|swiftdata|grdb|swinject|rxswift|mainactor|view ?controllers?|iphone|ipad|spm|cocoapods|carthage|testflight|bgtask)\b|core data' \
              "$ROOT/skills/$s/SKILL.md" | sort -u | tr '\n' ' ')"
    [ -z "$hits" ] || offenders="$offenders$s: $hits"$'\n'
  done
  [ -z "$offenders" ] || { echo "single-ecosystem vocabulary in core:"; echo "$offenders"; return 1; }
}

@test "a method skill that names a topic says how to resolve it" {
  # The half-migrated state this forbids: skill names dropped, bold topics in
  # their place, and nothing telling the reader the names live in the platform
  # manifest. The skill then reads as if the topic were the answer. Skills that
  # name no topic (feature-estimation today) are exempt, not excused: the check
  # is the pairing, so the pointer arrives with the first topic either way.
  for s in $METHOD_SKILLS; do
    grep -qE "\\*\\*($TOPICS)\\*\\*" "$ROOT/skills/$s/SKILL.md" || continue
    grep -q 'manifest `## Topics`' "$ROOT/skills/$s/SKILL.md" \
      || { echo "$s names a topic but no resolution path for it"; return 1; }
    grep -q 'conventions/platform-contract.md' "$ROOT/skills/$s/SKILL.md" \
      || { echo "$s does not point at the contract that resolves topics"; return 1; }
  done
}

@test "every topic core names has a row in the installed platform's manifest" {
  # The sibling tree, the way lint-manifest.test.bats already reaches it: a bats
  # path is not a backticked path in prose, so it is outside the cross-plugin
  # path guard by design. This closes the half of the binding that is closable —
  # core naming `deep links` while the platform spells the row `deeplinks`
  # resolves to nothing, and reads fine on both sides. The other half is not
  # closable: core inventing a tenth topic no platform answers passes every
  # lexical check there is.
  M="$ROOT/../platform/skills/manifest/SKILL.md"
  [ -f "$M" ]
  rows="$(sed -n '/^## Topics/,/^## Entrypoints/p' "$M")"
  missing=""
  IFS='|' read -r -a topics <<<"$TOPICS"
  for t in "${topics[@]}"; do
    grep -qE "^${t}[[:space:]]*→" <<<"$rows" || missing="$missing '$t'"
  done
  [ -z "$missing" ] || { echo "topic named by core with no row in swift-platform:$missing"; return 1; }
}
