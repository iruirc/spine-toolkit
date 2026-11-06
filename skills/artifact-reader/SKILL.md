---
name: artifact-reader
description: "Use when writing, refreshing or rewriting any task artifact in Tasks/ — Walkthrough.md, ManualChecks.md, Done.md, Plan.md, Review.md, Questions.md, Research.md, OpsChecklist.md, Validation.md, Docs.md. The reader is someone who was not on the task and does not know this area of the code. The single source of the reader and the style rules for every artifact an agent writes."
---

# Artifact Reader

A task artifact is accurate when it states what happened. It is readable when someone who was not there can follow it without opening the code. This skill fixes the second half: it changes **how** an artifact reads, and leaves **what** the file holds and every line the toolkit's scripts parse exactly where the toolkit's contracts put them.

## Reader

The reader is an engineer or a tester who was **not** on this task and does not know this area of the code. An agent starting in a clean context is in the same position, and so is a person opening the task a month later.

`ManualChecks.md` takes its reader from its own skill, `spine-toolkit:manual-checks`. Every other rule below applies to it unchanged.

Everything in `## Style` follows from this reader.

## Style

1. **One fact per sentence.** A sentence over about 25 words is split. Three facts in one sentence cost the reader three re-reads.

2. **Meaning first, identifier in brackets.** Write "The table of track languages (`TrackLanguageStore`) remembers the last choice", never "`TrackLanguageStore` remembers the last choice".

3. **A label is never the subject.** A label such as `u3`, `M1`, `P5` or `Q1` is a reference. Say the decision or the finding in words, then put the label in brackets: "The selection survives a list refresh (`M2`)", never "`M2` survives a refresh".

4. **Explain the basics the reader needs.** Domain words, and how a mechanism works when the text depends on it: how undo records a change, what a render snapshot is. One sentence too many is cheaper than a reader who has to open the code.

5. **A problem is a chain, not a category.** Number it: 1, then 2, then 3, and the last step is what the user sees. "The list is rebuilt, so the row object is replaced, so the selection points at a row that is gone, so the highlight disappears" says more than "guards against stale state".

6. **Every decision names the rejected alternative.** "Store the choice per project, not per user, because two people share one project file."

7. **Tables for comparisons and lists of cases.** Put anything the reader has to compare in a table. Examples: before and after; "what could break / how it would look"; "case / expected / actual".

8. **Pictures where space or order matters.** Draw what the reader would otherwise have to imagine. Use an ASCII sketch for a layout such as a timeline, lanes or screens, a sequence diagram for one user action passing through several objects, and a dependency graph for what waits for what.

9. **Proof is concrete.** "Removed the words from the copy and 6 tests failed", never "covered by tests".

10. **Human text on the first screen.** Machine lines such as commit lists, run directives and device strings go last wherever the format allows it. They never push the summary below the fold.

11. **No history in the body.** No "changes in this revision" and no round-by-round story. The commit history and the walkthrough carry those.

12. **A blank line before every field, list and table.** Without it Markdown renders the block glued to the previous line.

## Self-check

Read the file as the reader above, and fix each of these before finishing:

- a sentence you had to read twice;
- a term or identifier used before it is explained;
- a sentence that starts with a backticked identifier or a label;
- a commit or a case that does not say why it exists;
- a claim of "works" without how it was checked;
- a field, a list or a table with no blank line above it.

## Anti-patterns

- **Telegraphic compression.** Dropped articles and verbs, arrows instead of sentences. It saves the writer a word and costs the reader a guess.
- **An identifier as the subject.** The sentence names a symbol and never says what it is for.
- **A label with no meaning.** `M3 fixed` tells nobody what was wrong or what is true now.
- **A claim without proof.** "Works", "covered", "verified" with no run, no count, no observed result.
- **Machine lines above human text.** A reader has to scroll past a list of hashes to learn what changed.

## Scope

This skill governs the prose of every task artifact an agent writes: `Walkthrough.md`, `ManualChecks.md`, `Done.md`, `Plan.md`, `Review.md`, `Questions.md`, `Research.md`, `OpsChecklist.md`, `Validation.md` and `Docs.md`.

Where an agent body asks for brevity and this skill asks for a full sentence, the Style above governs: it wins over any brevity instruction in an agent body. Brevity here means no padding, not compression.

Lines the toolkit's scripts parse stay where the toolkit's contracts put them: the section headings, the marker lines and the commit headings that a script reads are written exactly as their contract says, whatever the Style above would prefer.
