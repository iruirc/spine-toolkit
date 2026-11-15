# Manual Checks — Change quantities in the cart

[COVERS] = 4f2a9c1

[STYLE] = brief

## Scope

A shopper now changes the quantity of an item right in the cart, and the total follows every change.
Three cases, about five minutes, on the build made from [COVERS].

## Preparation

### S1. A cart with Green tea

Sign in with the test account cart.tester.1; its password is on the team's test-accounts page.
Add Green tea to the cart in the quantity the case's Start names, and open the cart.

## Cases

### MC-1. The plus button raises the quantity and the total

**What it checks:** one tap on plus adds one item and the total grows by its price.

**Runner:** agent

**Order:** first — the cart must be untouched since sign-in

**Start:** S1 with one Green tea.

1. Tap the plus button in the Green tea row
   → The quantity reads 2, and the total reads "Total 9.00"

**Failure looks like:** the quantity reads 2 while the total still reads 4.50.

### MC-2. Pulling the cart down refreshes it with the finger's speed

**What it checks:** a fast pull on the cart list refreshes it once and the spinner goes away.

**Device:** real

**Start:** S1 with one Green tea.

1. Pull the cart list down fast and let go
   → The spinner shows once and goes away, and the row stays

**Failure looks like:** the spinner stays on the screen, or the row disappears.

### MC-3. Removing the last item empties the cart

**What it checks:** the minus button at quantity 1 removes the row, and the empty cart says so.

**Start:** S1 with one Green tea.

1. Tap the minus button in the Green tea row
   → The row disappears, and "Your cart is empty" is in the middle of the screen

**Failure looks like:** a row with quantity 0 stays in the cart.

## Not covered

- Paying for the order: the checkout screen did not change in this task.

## Code references

| Case | Code |
|---|---|
| MC-1 | (cart/quantity_stepper.src:41) |
| MC-2 | (cart/refresh_control.src:12) |
| MC-3 | (cart/quantity_stepper.src:58) |

**Result:** MC-1 __ · MC-2 __ · MC-3 PASS — PASS, FAIL or BLOCKED each; after a FAIL or a BLOCKED, why
