# Manual Checks — Cart quantity stepper

[COVERS] = a1b2c3d..e4f5a6b

## Run record

| Field | Value |
|---|---|
| Build | release candidate, commits from [COVERS] |
| Device / OS | ______ |
| Tester / date | ______ |
| Summary | PASS __ / FAIL __ / BLOCKED __ |

## Scope

The cart now lets a shopper change how many of an item they buy without leaving the cart.
The total and the badge on the cart icon follow every change at once.
Automated tests covered the arithmetic and the upper limit of 10 per item.
This file checks what a person sees: two cases, about ten minutes.

## Preparation

### Screen map

```
+-----------------------------+
| Cart                (badge) |
|-----------------------------|
| Green tea     [-] 1 [+]     |
| Price 4.50                  |
|-----------------------------|
| Total 4.50     [Checkout]   |
+-----------------------------+
```

| Word in the cases | What it is on the screen |
|---|---|
| cart icon | the trolley picture at the top right; tapping it opens the cart |
| badge | the red circle with a number on the cart icon, top right |
| stepper | the minus button, the number and the plus button on an item row |
| total | the line "Total" above the Checkout button |
| Checkout button | the button at the foot of the cart, right of the total |

### P0. Build — **dev-only**

A developer installs the build named in Run record on the test device.

### P1. Account

Sign in with the test account from Test data. The cart must be empty before each case.

## Cases

### MC-1. The plus button raises the quantity and the total

**Priority:** P1 — the main scenario

**Traces to:** Plan.md, Manual acceptance, item 1

**What it checks:** one tap on plus adds one item and the total grows by its price.

**Preconditions:**

- The build from Run record is installed and the test account is signed in (Preparation, P1).
- The cart holds one Green tea at 4.50.

**Test data:** Green tea, price 4.50, version 2.1.0 of the catalogue.

**Steps:**

| # | Action | Data | Expected | Actual |
|---|---|---|---|---|
| 1 | Open the cart from the cart icon, top right | — | The cart shows one row, Green tea, quantity 1 | |
| 2 | Tap the plus button on the Green tea row | — | The quantity reads 2 | |
| 3 | Look at the total above the Checkout button | — | Total 9.00; the badge shows 2 | |

**Expected result:** the cart holds two Green tea and the total reads 9.00.

**Failure looks like:** the quantity reads 2 while the total still reads 4.50.

**Cleanup:** tap the minus button until the row disappears.

**Code:** (cart/quantity_stepper.src:41)

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED — reason: ______

**Notes / attachments:** ______

### MC-2. The plus button stops at ten items

**Priority:** P2 — an important side path

**Traces to:** Plan.md, Manual acceptance, item 2

**What it checks:** the quantity never goes above the limit of 10 per item.

**Preconditions:**

- The build from Run record is installed and the test account is signed in (Preparation, P1).
- The cart holds nine Green tea.

**Test data:** limit of 10 items per row; the plus button fades within 0.8 s at the limit.

**Steps:**

| # | Action | Data | Expected | Actual |
|---|---|---|---|---|
| 1 | Open the cart from the cart icon, top right | — | Green tea, quantity 9 | |
| 2 | Tap the plus button on the Green tea row | — | The quantity reads 10; the plus button turns grey | |
| 3 | Tap the grey plus button once more | — | The quantity still reads 10; the text "Limit 10 per item" appears under the row | |

**Expected result:** the quantity stays at 10 and the limit text is on the screen.

**Failure looks like:** the quantity reads 11, or the plus button stays blue at 10.

**Cleanup:** tap the minus button until the row disappears.

**Code:** (cart/quantity_limit.src:17)

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED — reason: ______

**Notes / attachments:** ______

## On failure — bug report

**Title:** MC-N: what broke, in the shopper's words

**Build / device:** from Run record

**Steps to reproduce:** steps 1–k of case MC-N

**Actual:** what is on the screen, at which step

**Expected:** the Expected cell of that step

**Attachments:** a screenshot or a screen recording

## Not covered

- Paying for the order: the checkout screen did not change.

## Troubleshooting

- The cart icon shows no badge: sign out and sign in again with the test account.
