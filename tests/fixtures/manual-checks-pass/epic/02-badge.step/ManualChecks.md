# Manual Checks — Badge on the cart icon

[COVERS] = 4f2a9c1

[STYLE] = full

## Run record

| Field | Value |
|---|---|
| Build | release candidate built from [COVERS] |
| Device / OS | ______ |
| Tester / date | ______ |
| Summary | PASS __ / FAIL __ / BLOCKED __ |

## Scope

The badge on the cart icon counts the items the cart holds. Four cases, about ten minutes.

## Preparation

### P1. Device

- The interface language is English: every label in the cases is quoted from the English app.

## Cases

### MC-1. The badge counts items, not rows

**Priority:** P1 — the main scenario

**Traces to:** Plan.md, Manual acceptance, item 1

**What it checks:** the badge on the cart icon shows the number of items.

**Order:** last — it signs the test account out at the end

**Preconditions:**

- A cart with two Green tea.

**Test data:** test account cart.tester.1; Green tea at 4.50.

**Steps:**

| # | Action | Data | Expected | Actual |
|---|---|---|---|---|
| 1 | Look at the badge on the cart icon | — | The badge shows 2 | |
| 2 | Tap the cart icon at the top right | — | The cart shows one row, Green tea, quantity 2 | |

**Expected result:** the badge shows 2 for one row of two items.

**Failure looks like:** the badge shows 1.

**Cleanup:** —

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED — reason: ______

**Notes / attachments:** ______

### MC-2. The badge disappears with the last item

**Priority:** P1 — the main scenario

**Traces to:** Plan.md, Manual acceptance, item 2

**What it checks:** the badge goes away when the cart is emptied.

**Device:** iPhone 12

**Preconditions:**

- A cart with one Green tea.

**Test data:** test account cart.tester.1; Green tea at 4.50.

**Steps:**

| # | Action | Data | Expected | Actual |
|---|---|---|---|---|
| 1 | Tap the minus button in the Green tea row | — | The row disappears | |
| 2 | Look at the cart icon at the top right | — | The cart icon has no badge | |

**Expected result:** the cart icon has no badge.

**Failure looks like:** the badge still shows 1.

**Cleanup:** —

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED — reason: ______

**Notes / attachments:** ______

### MC-3. The badge shows ten at the limit

**Priority:** P1 — the main scenario

**Traces to:** Plan.md, Manual acceptance, item 3

**What it checks:** the badge shows 10 when a row reaches the limit.

**Preconditions:**

- A cart with nine Green tea.

**Test data:** test account cart.tester.1; Green tea at 4.50.

**Steps:**

| # | Action | Data | Expected | Actual |
|---|---|---|---|---|
| 1 | Tap the plus button in the Green tea row | — | The quantity reads 10 | |
| 2 | Look at the badge on the cart icon | — | The badge shows 10 | |

**Expected result:** the badge shows 10.

**Failure looks like:** the badge shows 9.

**Cleanup:** —

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED — reason: ______

**Notes / attachments:** ______

### MC-4. The badge survives a sign-out and sign-in

**Priority:** P1 — the main scenario

**Traces to:** Plan.md, Manual acceptance, item 4

**What it checks:** the badge shows the saved cart after signing in again.

**Preconditions:**

- A cart with one Green tea.

**Test data:** test account cart.tester.1; Green tea at 4.50.

**Steps:**

| # | Action | Data | Expected | Actual |
|---|---|---|---|---|
| 1 | Sign out and sign in again | — | The home screen | |
| 2 | Look at the cart icon at the top right | — | The badge shows 1 | |

**Expected result:** the badge shows 1.

**Failure looks like:** the badge is gone.

**Cleanup:** —

**Status:** FAIL — reason: the badge was gone

**Notes / attachments:** ______

## On failure — bug report

**Title:** MC-N: what broke, in the shopper's words

**Build / device:** from Run record

**Steps to reproduce:** steps 1–k of case MC-N, from its Preconditions

**Actual:** what is on the screen, and at which step

**Expected:** the Expected cell of that step

**Attachments:** a screenshot

## Not covered

- The cart on the server agreeing with the screen: no person can read it, so no case checks it.

## Code references

| Case | Code |
|---|---|
| MC-1 | (cart/badge_counter.src:18) |
| MC-2 | (cart/badge_counter.src:30) |
| MC-3 | (cart/quantity_limit.src:17) |
| MC-4 | (cart/badge_counter.src:44) |
