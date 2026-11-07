---
name: artifact-reader
description: "Use when writing, refreshing or rewriting any task artifact in Tasks/ — Walkthrough.md, ManualChecks.md, Done.md, Plan.md, Review.md, Questions.md, Research.md, OpsChecklist.md, Validation.md, Docs.md. The reader is someone who was not on the task and does not know this area of the code. The single source of the reader, the style rules for every artifact an agent writes, and the fresh reader's check of Done.md and Plan.md."
---

# Artifact Reader

A task artifact is accurate when it states what happened. It is readable when someone who was not there can follow it without opening the code. This skill fixes the second half: it changes **how** an artifact reads. It leaves **what** the file holds, and every line the toolkit's scripts parse, exactly where the toolkit's contracts put them.

## Reader

The reader is an engineer or a tester who was **not** on this task and does not know this area of the code. An agent starting in a clean context is in the same position, and so is a person opening the task a month later.

`ManualChecks.md` takes its reader from its own skill, `spine-toolkit:manual-checks`. Every other rule below applies to it unchanged.

Everything in `## Style` follows from this reader.

## Style

1. **One fact per sentence.** A sentence over about 30 words is split. Three facts in one sentence cost the reader three re-reads.

2. **Meaning first, identifier in brackets.** Write "The table of track languages (`TrackLanguageStore`) remembers the last choice", never "`TrackLanguageStore` remembers the last choice".

3. **A label is never the subject.** A label such as `u3`, `M1`, `P5` or `Q1` is a reference. Say the decision or the finding in words, then put the label in brackets: "The selection survives a list refresh (`M2`)", never "`M2` survives a refresh".

4. **Explain the basics the reader needs.** Domain words, and how a mechanism works when the text depends on it: how undo records a change, what a render snapshot is. One sentence too many is cheaper than a reader who has to open the code.

5. **A problem is a chain, not a category.** Number it: 1, then 2, then 3, and the last step is what the user sees. "The list is rebuilt, so the row object is replaced, so the selection points at a row that is gone, so the highlight disappears" says more than "guards against stale state".

6. **Every decision names the rejected alternative.** "Store the choice per project, not per user, because two people share one project file."

7. **Tables for comparisons and lists of cases.** Put anything the reader has to compare in a table. Examples: before and after; "what could break / how it would look"; "case / expected / actual".

8. **Pictures where space or order matters.** Draw what the reader would otherwise have to imagine. Use an ASCII sketch for a layout such as a timeline, lanes or screens, a sequence diagram for one user action passing through several objects, and a dependency graph for what waits for what.

9. **Proof is concrete.** "Removed the words from the copy and 6 tests failed", never "covered by tests".

10. **Human text on the first screen.** Machine lines go in the closing block, the last lines of the file: the marker lines, the run directive and the device line. Other machine text, such as a list of commit hashes, goes as low as the format allows. Neither pushes the summary below the fold.

11. **No history in the body.** No "changes in this revision" and no round-by-round story: the commit history and the walkthrough carry those. A `Walkthrough.md` keeps the rework of its commits, because that is its content; no other artifact narrates round-by-round history.

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

## Check

`[ARTIFACT_CHECK]` decides whether `Done.md` and `Plan.md` are read back by someone who did not follow the task before the run goes on. It reaches a run as the contract's `artifact_check`, `on` or `off`; `auto`, its default, is `on` at `scale = full` and `off` at `lite` (`conventions/task-settings.md`).

**When.** With `artifact_check` `on`, a file is read once after the stage that wrote it: `Plan.md` after Plan, `Done.md` after Done. The writer never checks its own file: the dispatcher does, the profile script under Method A and the workflow skill's main context under Method B.

**The reader** is a fresh dispatch of the writer's own role, tuned `light`; the fresh dispatch is where its lack of context comes from. Its brief tells it who it is: an owner who did not follow the task. Of the task and the repository it reads the one file and nothing else: no other file of the task, no source file, no git command and no other command. It returns two lists:

- `retelling`: in its own words, what was done (for a plan, what will be done), why, what is left, and what the owner must decide;
- `unclear`: every place it had to guess, each as a quote of at most one line, what is missing, and one kind:
  - `reread`: a sentence it had to read twice;
  - `undefined term`: a term, an identifier or a label used before anything says what it means;
  - `identifier subject`: an identifier or a label as the subject of a sentence, where the thing it names should be;
  - `no reason`: a decision, a phase or a change that does not say why, or a decision with no rejected alternative;
  - `no proof`: a claim that something works, with no run, no count and no observed result.

The role is the writer's so that the reader knows the trade; the brief, not the role, is what keeps it outside the task. The reader returns what it understood, not what it would change: a retelling that misses the point is a finding about the file, not about the reader.

**Revision.** An empty `unclear` ends the check. Otherwise the writer gets both lists and makes one revision pass. It fixes every place named; where the retelling misreads the file, it fixes the text that led the reader there. An entry without a quote names no place, so it is skipped. The revised file is not read again: one revision pass, never a second round, however many places the read named. The status line and the closing block stay as they are. What the reader returns in another language does not change the file's language: the revision is written in the project's `[LANG]`, with the labels in English as before.

The run notes one line per file: `Plan.md check: 3 place(s), revised.`, `Plan.md check: nothing unclear.`, or `Plan.md check: the reader returned nothing, so the file went unchecked.` A failure of either dispatch is noted and stops nothing.

## Scope

This skill governs the prose of every task artifact an agent writes: `Walkthrough.md`, `ManualChecks.md`, `Done.md`, `Plan.md`, `Review.md`, `Questions.md`, `Research.md`, `OpsChecklist.md`, `Validation.md` and `Docs.md`.

Where an agent body asks for brevity and this skill asks for a full sentence, the Style above wins over any brevity instruction in an agent body. Brevity here means no padding, not compression. A line budget still holds: meet it by covering less, never by compressing the sentences.

Lines the toolkit's scripts parse stay where the toolkit's contracts put them. The section headings, the marker lines and the commit headings that a script reads are written exactly as their contract says, whatever the Style above would prefer.

Machine lines go in the closing block at the end of the file (`conventions/stage-dispatch.md` → Closing block): the marker lines first, then `**Run:**`, then `**Device:**`. Two lines keep their place: the status line `[REVIEW_STATUS] = …` is line 1 of `Review.md`, and `[COVERS]` is line 2 of `Walkthrough.md`.

`scripts/lint-artifact-readability.sh` measures six of these files: `Done.md`, `Plan.md`, `Review.md`, `Research.md`, `Questions.md` and `OpsChecklist.md`. It reports a sentence over the `words-per-sentence` budget: 30 words unless the task, its epic or the project sets another number, and a run passes its own as `--words-per-sentence`. It also reports backticked identifiers piled into the first section or into one table cell, and a label with nothing beside it that says what it means. It reports a `Questions.md` entry without its question, and an `OpsChecklist.md` written as a table. It skips the closing block. The writer runs it once on its own file, fixes its findings once, and names what is left in its summary. Nothing sends the file back for a lint line a second time. `Walkthrough.md` and `ManualChecks.md` have lints of their own.
