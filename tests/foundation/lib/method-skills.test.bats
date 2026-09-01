#!/usr/bin/env bats
# Core's four methodology skills are the process layer: they say which topic a
# decision belongs to and never which skill answers it. The skills that answer
# are the platform's, listed in its manifest `## Topics`, and a name written back
# into core re-binds core to one ecosystem — silently, because it still reads
# fine on an Apple project.
#
# That a given platform answers all nine topics is that platform's assertion, in
# its own suite: core owns the vocabulary, not the coverage, and a core test that
# opened the sibling tree to check it would not survive core being extracted.

setup() {
  # BATS_TEST_FILENAME, not BASH_SOURCE[0]: bats sources a preprocessed copy of
  # the test file from a tmp dir, so BASH_SOURCE[0] there resolves to the copy.
  ROOT="$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/../../.." && pwd)"
  METHOD_SKILLS="feature-landscape feature-requirements feature-estimation ops-checklist"
  CONTRACT="$ROOT/conventions/platform-contract.md"
  # The topic names core asks a platform for, read from the one file that publishes
  # them. Not derived from the method skills themselves: `**bold**` is overloaded
  # there (`**Applicable**`, `**+30%–50%**`), so that list would be emphasis, not
  # topics. Not a second copy either — a platform author reads the contract, and a
  # vocabulary the tests and the contract can disagree about is the bug this closes.
  TOPICS="$(sed -n '/^```topics$/,/^```$/p' "$CONTRACT" | sed '1d;$d' | paste -sd '|' -)"
}

@test "the contract publishes the topic vocabulary the tests read" {
  # Vacuity guard for the two tests below: lose the block and TOPICS goes empty,
  # both of them iterate nothing, and the suite stays green over no vocabulary.
  [ -n "$TOPICS" ]
  IFS='|' read -r -a topics <<<"$TOPICS"
  [ "${#topics[@]}" -ge 5 ]
  [[ "$TOPICS" == *"state management"* ]]
}

@test "method skills name no platform skill" {
  # Every loop below reads a hard-coded path: without this, a renamed or moved
  # skill drops out of all three checks and the suite stays green over nothing.
  offenders=""
  for s in $METHOD_SKILLS; do
    [ -f "$ROOT/skills/$s/SKILL.md" ] || { echo "method skill missing: $s"; return 1; }
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
    [ -f "$ROOT/skills/$s/SKILL.md" ] || { echo "method skill missing: $s"; return 1; }
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
    [ -f "$ROOT/skills/$s/SKILL.md" ] || { echo "method skill missing: $s"; return 1; }
    grep -qE "\\*\\*($TOPICS)\\*\\*" "$ROOT/skills/$s/SKILL.md" || continue
    grep -q 'manifest `## Topics`' "$ROOT/skills/$s/SKILL.md" \
      || { echo "$s names a topic but no resolution path for it"; return 1; }
    grep -q 'conventions/platform-contract.md' "$ROOT/skills/$s/SKILL.md" \
      || { echo "$s does not point at the contract that resolves topics"; return 1; }
  done
}
