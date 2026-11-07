# Manual Checks — Change quantities in the cart

[COVERS] = 4f2a9c1

## Run record

| Field | Value |
|---|---|
| Build | release candidate built from [COVERS] |
| Device / OS | ______ |
| Tester / date | ______ |
| Summary | PASS __ / FAIL __ / BLOCKED __ |

## Scope

A shopper can now change how many of an item they buy without leaving the cart.
The total and the badge on the cart icon follow every change at once, and the cart says so when it is empty.
Automated tests covered the arithmetic of the total and the limit of 10 per item.
This file checks what a person sees: three cases, about fifteen minutes.

## Preparation

### Screen map

```
Product page                    Cart
+--------------------------+    +------------------------------+
| < Back          [cart] 2 |    | < Back    Cart    [cart] 2   |
| Green tea                |    |------------------------------|
| 4.50                     |    | Green tea   [-] 2 [+]   9.00 |
| Quantity [ 1 v ]         |    | Limit 10 per item            |
| [ Add to cart ]          |    |------------------------------|
+--------------------------+    | Total 9.00      [ Checkout ] |
                                +------------------------------+
```

| Word in the cases | What it is on the screen |
|---|---|
| cart icon | the trolley picture at the top right of every screen; tapping it opens the cart |
| badge | the red circle with a number on the cart icon; it shows how many items the cart holds, not how many rows |
| row | one product in the cart: its name, the stepper and its price |
| stepper | the minus button, the number and the plus button in a row |
| total | the line "Total" above the Checkout button |
| limit text | the grey line "Limit 10 per item" that appears under a row at ten |
| sign-in screen | the first screen after the app opens, with the Sign in button |
| home screen | the screen right after sign-in, with the search field |
| search field | the box at the top of the home screen with the grey word "Search" |
| Quantity list | the "Quantity" box on a product page; tapping it lists the numbers 1 to 10 |
| Checkout button | the button at the foot of the cart, right of the total |

### P0. Build

**dev-only:** a developer installs the build named in Run record on the test device and signs out of any account left on it. The tester starts after this.

### P1. Device

- The interface language is English: every label in the cases is quoted from the English app.
- The test account is the one in Test data of each case; its password is on the team's test-accounts page.

### P2. A cart with Green tea

| # | Action | Expected |
|---|---|---|
| 1 | Open the app | The sign-in screen |
| 2 | Sign in with the test account from the case's Test data | The home screen; the cart icon shows no badge |
| 3 | Type "Green tea" in the search field at the top | One result: Green tea, 4.50 |
| 4 | Tap the Green tea result | The product page of Green tea; the Quantity list reads 1 |
| 5 | Choose the quantity from the case's Test data in the Quantity list | The Quantity list reads that quantity |
| 6 | Tap Add to cart | The badge on the cart icon shows that quantity |

If the badge shows a number before step 6, the account's cart is not empty: record the case as BLOCKED with that number.

## Cases

### MC-1. The plus button raises the quantity, the total and the badge

**Priority:** P1 — the main scenario

**Traces to:** Plan.md, Manual acceptance, item 1

**What it checks:** one tap on plus adds one item, the total grows by its price, and the badge counts items.

**Preconditions:**

- A cart with one Green tea (Preparation, P2).

**Test data:** test account cart.tester.1; quantity 1 at P2; Green tea at 4.50.

**Steps:**

| # | Action | Data | Expected | Actual |
|---|---|---|---|---|
| 1 | Tap the cart icon at the top right | — | The cart shows one row, Green tea, quantity 1, total 4.50 | |
| 2 | Tap the plus button in the Green tea row | — | The quantity reads 2 and the row price reads 9.00 | |
| 3 | Look at the total above the Checkout button | — | "Total 9.00" | |
| 4 | Look at the badge on the cart icon | — | The badge shows 2 | |

**Expected result:** the cart holds two Green tea, the total reads 9.00 and the badge shows 2.

**By instrument:** the server's cart agrees with the screen. A developer runs `curl -s -H "Authorization: Bearer <token>" https://shop.example.com/api/cart`, with the test account's token, and reads `item_count`: it must be 2.

**Failure looks like:** the quantity reads 2 while the total still reads 4.50, or the badge still shows 1.

**Cleanup:** tap the minus button in the Green tea row until the row disappears.

**Code:** (cart/quantity_stepper.src:41), (cart/badge_counter.src:18)

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED — reason: ______

**Notes / attachments:** ______

### MC-2. The plus button stops at ten items

**Priority:** P2 — an important side path

**Traces to:** Plan.md, Manual acceptance, item 2

**What it checks:** the quantity of a row never goes above the limit of 10 per item.

**Preconditions:**

- A cart with nine Green tea (Preparation, P2).

**Test data:** test account cart.tester.1; quantity 9 at P2; limit of 10 per item.

**Steps:**

| # | Action | Data | Expected | Actual |
|---|---|---|---|---|
| 1 | Tap the cart icon at the top right | — | One row, Green tea, quantity 9 | |
| 2 | Tap the plus button in the Green tea row | — | The quantity reads 10; the plus button turns grey | |
| 3 | Tap the grey plus button once more | — | The quantity still reads 10; the limit text "Limit 10 per item" appears under the row | |
| 4 | Look at the badge on the cart icon | — | The badge shows 10 | |

**Expected result:** the quantity stays at 10, the limit text is under the row and the badge shows 10.

**Failure looks like:** the quantity reads 11, or the plus button stays blue at 10.

**Cleanup:** tap the minus button in the Green tea row until the row disappears.

**Code:** (cart/quantity_limit.src:17)

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED — reason: ______

**Notes / attachments:** ______

### MC-3. Removing the last item empties the cart

**Priority:** P3 — a rare edge

**Traces to:** Plan.md, Manual acceptance, item 3

**What it checks:** the minus button at quantity 1 removes the row, and the empty cart says so.

**Preconditions:**

- A cart with one Green tea (Preparation, P2).

**Test data:** test account cart.tester.1; quantity 1 at P2; the shop's address shop.example.com, shown at the foot of the empty cart.

**Steps:**

| # | Action | Data | Expected | Actual |
|---|---|---|---|---|
| 1 | Tap the cart icon at the top right | — | One row, Green tea, quantity 1 | |
| 2 | Tap the minus button in the Green tea row | — | The row disappears; the text "Your cart is empty" is in the middle of the screen | |
| 3 | Tap the grey Checkout button under the message | — | Nothing happens; the cart stays on the screen | |
| 4 | Look at the cart icon at the top right | — | The cart icon has no badge | |
| 5 | Look at the foot of the screen | the shop's address from Test data | The line "Continue shopping at" and the shop's address | |

**Expected result:** the cart shows "Your cart is empty", the Checkout button is grey and the cart icon has no badge.

**Failure looks like:** a row with quantity 0 stays in the cart, or the badge still shows 1.

**Cleanup:** —

**Code:** (cart/quantity_stepper.src:58), (cart/empty_state.src:9)

**Status:** ☐ PASS ☐ FAIL ☐ BLOCKED — reason: ______

**Notes / attachments:** ______

## On failure — bug report

**Title:** MC-N: what broke, in the shopper's words

**Build / device:** from Run record

**Steps to reproduce:** steps 1–k of case MC-N, from its Preconditions

**Actual:** what is on the screen, and at which step

**Expected:** the Expected cell of that step

**Attachments:** a screenshot or a screen recording

## Not covered

- Paying for the order: the checkout screen did not change in this task.
- A cart shared between two devices: the sync between devices is a later step of the epic.

## Troubleshooting

| Symptom | Cause | What to do |
|---|---|---|
| The badge shows a number before P2 starts | The test account kept a cart from an earlier run | Empty the cart with the minus buttons, then start P2 again |
| Green tea is not in the search results | The device is offline, or the catalogue is still loading | Check the connection, wait ten seconds and search again |
