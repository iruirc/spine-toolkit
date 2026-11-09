# Notes — the "before" measurement: note list speed on iPhone

What the note list scenarios cost in the app before optimisation, where the time goes, and what to do about it. For whoever takes steps `03`–`12` of sub-epic `58/2` ("list performance"), and for whoever checks the "after" verdict against the "before" numbers.

All numbers were taken on an iPhone 15, Debug build, in the `Nominal` state (the phone is not hot), unless stated otherwise next to them. Release was not measured.

## 1. Conclusion

1. **Everything that replaces the list model whole or touches every row of the note list is slow.** The folder settings form closes in 118 / 483 / 1312 ms against a 100 ms threshold (at 300 / 2400 / 9000 notes). One density tick at 9000 notes is about 3.4 s of the main thread.
2. **The time sits in the note list layout, not in Core Animation layer commits.** On "Save" almost the whole layout is a UIKit call that writes a warning about row heights to the log. On scrolling every event walks every row of the list, though about twelve are on screen.
3. **The second cost is the snippet pass:** synchronous drawing of the rows' rich-text previews. It is 45–70 % of the busy main thread in a search keystroke.
4. **What to do.** The note list: steps `05` (density, scrolling) and `05a` ("Save", Undo, Redo). The snippet pass: steps `09` and `10`. Opening the app at 9000 notes: step `07`.
5. **What will not help.** Step `03` ("one Core Animation transaction"): on the app's path there is already one commit.
6. **The 9000 tag link limit is not raised.** Recomputing tag links during a drag already exceeds 8.0 ms.
7. **The bounds of the numbers.** Debug, one phone. Scrolling and pinch were taken with one recording per size.

## 2. Words the table cannot be read without

| Word | What it is |
|---|---|
| Note | One entry of the list: a title, the first line of text and a date. |
| Library sizes | The libraries "Pocket", "Desk", "Archive": 300 / 2400 / 9000 notes. "Archive" sits exactly at the tag link limit. |
| Note list | The main screen of the app: one row per note. |
| "Save" | The save button on the settings form of a folder (sort order, grouping). |
| Snippet pass | Redrawing the rows' rich-text previews for the new model. |
| Density tick | One step of a pinch gesture on the list: the list gets a new row height and lays itself out again. |
| Model frame | The tick's time on the main thread. The 8.0 ms threshold is the half of a 60 Hz frame given to the model. |
| `Hitch Time Ratio` | How many milliseconds per second frames are late. The threshold is 5 ms/s. |
| Lower bound | A test's number without the notes' attachment thumbnails. The app's frame is no smaller. |

## 3. Summary table by scenario

Units are milliseconds unless stated otherwise. "Median" is the median of three recordings.

| Scenario (threshold) | 300 | 2400 | 9000 | Where the time goes | Decision | Section |
|---|---|---|---|---|---|---|
| "Save" on the folder form (≤ 100), median | 118.4 | 482.9 | 1311.6 | list layout 38 / 196 / 688, of it the UIKit log 31 / 174 / 612 | `05a`; snippet pass — `09`, `10` | 4.1 |
| Undo of a sort change (≤ 100) | 149.2 | 533.7 | 1622.4 | outside the snippet pass 115 of 149 / ~402 of 534 / ~1290 of 1622 | `05a` | 4.1 |
| Search, one keystroke (≤ 100) | 104.6 | 391.3 | 377.9 | snippet pass 45–70 % of the busy main thread | `09`, `10` | 4.5 |
| Opening the app to the list (≤ 1 s) | 201.4 | 512.8 | 1189.3 | snippet pass and row layout | `07` | 4.5 |
| List scrolling, `Hitch Time Ratio` (≤ 5 ms/s) | 9.4 | 104.7 | 486.2 | every row walked per event | input for `05` | 4.2 |
| Density tick, model frame p95 (≤ 8.0) | 34.9 | 391.6 | 3388.4 | list layout | `05` in full | 4.3 |
| Note drag onto a tag, 9000 tag links (≤ 8.0) | — | — | 8.34 and 12.71 | recomputing tag links | the limit is not raised | 4.4, 5 |

## 4. Why it is slow

### 4.1. "Save" and Undo: list layout and a needless row-height log

1. Tapping "Save" runs the snippet pass on the main thread, then `noteList.setModel`.
2. `noteList.setModel` lays the note list out again. The layout costs 38 / 196 / 688 ms.
3. Almost all of that time (31 / 174 / 612 ms) is a `_NSLogv` call inside UIKit: a function that writes a warning about invalid row heights.
4. Writing the folder settings to disk (94 / 466 / 1418 ms) runs off the main thread and does not lengthen the interval.

The share outside the snippet pass is 64 / 289 / 961 ms. On its own it exceeds the threshold at 2400 and 9000 notes: that is what gives step `05a`. Undo of a sort change takes the same path.

The text of the UIKit warning was not read: the app has no console during a recording. The first action of step `05a` is to read it from a Debug build's log.

### 4.2. Scrolling: every row walked on every event

Every scroll event walks **every row of the list**: there are as many rows as notes, and all of them are alive all the time. The cost of an event grows with the library, though about twelve rows are visible. `updateRelativeDate` takes 44 / 73 / 79 % of the busy main thread.

Decision: input for step `05` — walk the visible rows instead of all of them. The snippet pass's visible-row window (step `10`) does not cure scrolling: scrolling never reaches the snippet pass.

### 4.3. Density: a tick does not fit a frame

A tick does not fit a frame at any size, even without thumbnails. The cost per note grows with size: 116 → 163 → 376 µs. The Research hypothesis "the layout is linear in the number of notes" did not hold; step `05` investigates the cause first.

### 4.4. The 9000 tag link limit

The drag's model frame on one tag linked to all 9000 notes is above 8.0 ms in both measurements (section 5). The decision does not change: the limit is not raised ([Decisions.md](Decisions.md), line 181).

### 4.5. Search and opening the app

Both scenarios hit the snippet pass: building the highlighted previews and laying them out. The search itself (28–92 ms) runs off the main thread. Step `03` gives nothing here: there are no Core Animation commits inside the interval. Opening the app exceeds the threshold only for "Archive" after launch, by 120–231 ms.

## 5. Where sources disagree

A number in one place did not match the number in another: both are below, each marked with where it comes from. The table and conclusions above use the one named first.

| What | Number 1 | Number 2 | Cause or status |
|---|---|---|---|
| Note drag onto a tag, 9000 tag links | 8.34 ms (`Research.md`, "Tag link limit") | 12.71 ms (`Plan.md`, ph. 12, mean of 10 ticks) | unexplained; both above the 8.0 limit |
| Search keystroke at 300 notes | main thread busy 64 and 69 ms (`Done.md`): threshold "met" | "keystroke → shown" interval 104.6 and 102.9 ms (`Plan.md`, ph. 8): threshold exceeded | different quantities: main-thread busy time and the whole interval |
| Folder picker scrolling at 9000, frame p95 | 16.71 ms (`Plan.md`, ph. 6) | 17.42 ms on a repeat (`Plan.md`, ph. 9) | the "borderline" conclusion is now in `Done.md` and `Research.md` |
| "Save" after a search | "not taken" (earlier `Done.md`) | 131.7 / 509.2 / 1342.5 ms (`Plan.md`, ph. 9) | taken as a by-product; now in `Done.md` |

## 6. What was not measured, and why

| Scenario | Why there is no number | What is known |
|---|---|---|
| Pinch on an expanded list at `Nominal`, "Archive" | the phone went to `Fair`, no repeat was made (the owner's decision) | 3716 ms per tick, for reference |
| Note edit → Undo on "Desk" and "Archive" | the tap script cannot carry the edit into the model without a hand | one reference recording: Undo 1288.1 ms |
| Release | every number is Debug | the cost of the UIKit log in Release is unknown |
| Gesture repeats | one recording per size (the owner's decision) | the overruns are many-fold; no decision depends on the spread |

## 7. How to reproduce it, and where the raw data is

**Libraries.** Installed from the developer menu ("Library presets"); details in [Testing.md](Testing.md) §9. After a scenario that changes the library, the library is deleted and installed again.

**Tests (lower bound).** The classes of the `NoteListPerformance` plan; commands in [Testing.md](Testing.md) §8. Check the line `Executed N tests`, not the banner.

**Profiles.** Recording with the Animation Hitches template:

```bash
xcrun xctrace record --template 'Animation Hitches' --instrument os_signpost --instrument 'Thermal State' \
  --device <UDID> --time-limit 60s --no-prompt --output <file>.trace --launch -- com.example.notes
```

**Where the traces are.** `PerfTraces/58-2-02/` in the `notes-perf` working copy, outside git: 54 `.trace` files, about 22 GB. A trace's name starts with the size: `p-` (300), `d-` (2400), `a-` (9000). Next to each trace lies `<name>.json` with its breakdown.

**The thermal rule.** A number taken outside `Nominal` does not go into the table: the run is repeated after cooling down.

## 8. Sources

Source task: `58-notes-list-rework/2.list-performance.step/02-notes-perf-app-baseline.step` (step `02` of sub-epic `58/2`).

| Document | What is in it |
|---|---|
| `Research.md` of step `02`, "Measured by step `02`" | the full numbers and the decision on each finding |
| `Plan.md` of step `02` | phases 3–6 and 8–12 with their "Result" blocks, places and commands |
| `Done.md` of step `02` | answers to the step's questions, the input for step `05a` |
| `Plan.md` of sub-epic `58/2`, question P2 | the scenario thresholds |
| [Testing.md](Testing.md) §8 and §9 | the measurement classes' commands, the libraries, interval export |
| [Decisions.md](Decisions.md), line 181 | the 9000 tag link limit is not raised |
