# Manual Checks — Change quantities in the cart

[COVERS] = 4f2a9c1

[STYLE] = brief

## Scope

A shopper now changes the quantity of an item right in the cart, and the total and the badge on the cart icon follow every change.
Automated tests covered the arithmetic of the total and the per-item limit in the model.
Three cases, about ten minutes, on the build made from [COVERS].

## Preparation

### S1. A cart with Green tea

Sign in with the test account cart.tester.1; its password is on the team's test-accounts page.
Add Green tea to the cart in the quantity the case's Start names, and open the cart.

## Cases

### MC-1. The plus button raises the quantity, the total and the badge

**What it checks:** one tap on plus adds one item, the total grows by its price, and the badge counts items, not rows.

**Start:** S1 with one Green tea.

1. Tap the plus button in the Green tea row
   → The quantity reads 2, the row price reads 9.00, and the total reads "Total 9.00"
2. Look at the badge on the cart icon
   → The badge shows 2

**Failure looks like:** the quantity reads 2 while the total still reads 4.50, or the badge still shows 1.

### MC-2. The plus button stops at ten items

**What it checks:** the quantity of a row never goes above the limit of 10 per item, and the limit text reads whole in every theme and text size.

**Start:** S1 with nine Green tea.

**Test data:** walk the steps once per row; between rows, tap the minus button once to get back to nine.

| Theme | Text size |
|---|---|
| light | default |
| dark | default |
| light | largest |

1. Tap the plus button in the Green tea row
   → The quantity reads 10, and the plus button turns grey
2. Tap the grey plus button once more
   → The quantity still reads 10, and "Limit 10 per item" appears under the row, on one line and not cut off

**Failure looks like:** the quantity reads 11, the plus button stays blue at 10, or the limit text is cut off or hard to read.

### MC-3. Removing the last item empties the cart

**What it checks:** the minus button at quantity 1 removes the row, and the empty cart says so.

**Start:** S1 with one Green tea.

1. Tap the minus button in the Green tea row
   → The row disappears, and "Your cart is empty" is in the middle of the screen
2. Tap the grey Checkout button under the message
   → Nothing happens; the cart stays on the screen
3. Look at the cart icon at the top right
   → The cart icon has no badge

**Failure looks like:** a row with quantity 0 stays in the cart, or the badge still shows 1.

## Not covered

- The cart on the server agreeing with the screen: no person can read it, so no case checks it.
- Paying for the order: the checkout screen did not change in this task.

## Code references

| Case | Code |
|---|---|
| MC-1 | (cart/quantity_stepper.src:41), (cart/badge_counter.src:18) |
| MC-2 | (cart/quantity_limit.src:17), (cart/limit_label.src:12) |
| MC-3 | (cart/quantity_stepper.src:58), (cart/empty_state.src:9) |

**Result:** MC-1 __ · MC-2 __ · MC-3 __ — PASS, FAIL or BLOCKED each; after a FAIL or a BLOCKED, why, and the row of conditions it failed on
