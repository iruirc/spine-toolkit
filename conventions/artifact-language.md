# Artifact Language

`conventions/i18n.md` → "Artifact authoring rule" fixes what language an artifact's prose is written
in. This convention is how that rule is measured rather than only asked for:
`scripts/lint-artifact-lang.sh` reads a task folder's artifacts and names every part whose prose is
not in the project's `[LANG]`. The orchestrator runs it at the artifact budget's boundaries and sends
each file it names back once (`skills/orchestrator/SKILL.md` → Artifact language).

## Scripts

| `[LANG]` | Script | Letters counted |
|---|---|---|
| `en` | Latin | `A–Z`, `a–z` |
| `ru` | Cyrillic | U+0400–U+04FF |

A part's share is the letters of the project's script over the letters of every script in this
table. The check runs both ways: a `ru` project is told about Latin prose, an `en` project about
Cyrillic prose.

A new language is its locales and one row here, copied into the script's `SCRIPTS`. Two languages
written in one script cannot be told apart by this check: only a foreign script is caught.

## What counts as prose

Everything the authoring rule keeps English at any `[LANG]` is removed before counting:

- fenced code blocks, including one indented under a list item, opened and closed as CommonMark
  says: a backtick fence's info string holds no backtick, and only the fence run alone closes it;
- inline code;
- HTML comments;
- block quotes, the lines starting with `>`: quoted logs and messages;
- headings;
- field lines, `[FIELD] = …`;
- bold labels ending in a colon, up to 40 characters, `**Label:**`;
- table rows and their separators;
- URLs, paths (a word holding `/` or `\`) and file names with an extension;
- quoted commit subjects, `type(scope): …` or `type: …`, for the types in
  `conventions/commit-messages.md`.

In `OpsChecklist.md`, a list item (`-`, `*` or `+`) keeps only its text after the first ` — `
(space, em dash, space), and an item with no ` — ` is removed whole: an item's own text is the
catalog's, English at any `[LANG]` (`skills/ops-checklist/SKILL.md` → Output artifact). Every other
line is read as in any other artifact.

What remains is prose, and a Latin word in it counts: a term, an unquoted identifier, a status word
inside a sentence. The check asks what language a part is written in, not how much of another
language it carries.

## Where a finding starts

A part is the text before the first heading, and the text under each heading up to the next heading
of any level. A part is a finding when, after the removals above, it holds at least **200** letters
and fewer than **10%** of them are in the project's script. When no part of a file is a finding, the
same measure is applied to the whole file and reported as `(file)`: a file made of many short parts
would otherwise pass every one.

The threshold is on the absence of the project's script, not on its majority. In 200 letters, 10% is
under 20 letters — two or three words of the project's language to a paragraph, which is no longer
text written in it. Prose dense with terms stays far above that: verbs, prepositions and endings
carry their own letters. On a Russian project of about a thousand artifacts, the lowest real Russian
part held 24%, every file written in English was caught, and the result did not move for
thresholds from 3% to 10%.

## Which files

The artifacts in the task folder itself: `Research.md`, `Reproduce.md`, `Plan.md`, `Validation.md`,
`Review.md`, `ChangesRequested.md`, `Done.md`, `Walkthrough.md`, `OpsChecklist.md`,
`ManualChecks.md`, `Docs.md`.

Not read: `Task.md` and `Questions.md`, which carry the user's own words; anything under `_archive/`;
`.step/` folders below the folder named. A step folder is measured when it is named itself: by its
own run, or, for the steps an EPIC range ran as nested workflows, by the orchestrator after that range
(`skills/orchestrator/SKILL.md` → Artifact language).

## Output

One line per finding, then a total:

```
Tasks/ACTIVE/042-promo/OpsChecklist.md § ## Testing: 0% Cyrillic in 214 letters of prose (lang ru)
artifact language failed: 1 finding(s)
```

The part after `§` is a heading as the file writes it, `(preamble)` for the text before the first
heading, or `(file)`, which asks for the prose of the whole file.

Exit `0` — nothing in the wrong language, printed as `artifact language passed`; `1` — findings;
`2` — usage, a missing directory, or a config the resolver could not read.
