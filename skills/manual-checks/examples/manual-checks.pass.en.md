# Manual Checks — Collective pass: cart quantities and the cart badge

[COVERS] = 4f2a9c1

[STYLE] = brief

[PASS] = 01, 02

## Scope

One pass over the cases of two steps: 01, the quantity stepper in the cart, and 02, the badge on the cart icon. The interface language is English. Five cases in two sessions, about fifteen minutes.
The agent walked the other cases of both steps on a simulator; 01/MC-1 came back from it, because the driver could not sign in.
The two steps built their scenes differently. Step 01 signed in with cart.tester.1 and step 02 with cart.tester.2; the pass uses cart.tester.1 for both. Step 01 started with the cart open and step 02 with the home screen; the pass starts with the cart open.

## Preparation

### S1. A cart with Green tea

Sign in with the test account cart.tester.1; its password is on the team's test-accounts page.
Add Green tea to the cart in the quantity the case's Start names, and open the cart.

## Cases

### Session 1. Any device, about ten minutes

#### 01/MC-1. The plus button raises the quantity and the total

**What it checks:** one tap on plus adds one item and the total grows by its price.

**Runner:** agent

**Order:** first — the cart must be untouched since sign-in

**Start:** S1 with one Green tea.

1. Tap the plus button in the Green tea row
   → The quantity reads 2, and the total reads "Total 9.00"

**Failure looks like:** the quantity reads 2 while the total still reads 4.50.

#### 02/MC-1. The badge counts items, not rows

**What it checks:** the badge on the cart icon shows the number of items.

**Start:** S1 with two Green tea.

1. Look at the badge on the cart icon
   → The badge shows 2
2. Tap the cart icon at the top right
   → The cart shows one row, Green tea, quantity 2

**Failure looks like:** the badge shows 1.

#### 02/MC-2. The badge disappears with the last item

**What it checks:** the badge goes away when the cart is emptied.

**Start:** S1 with one Green tea.

1. Tap the minus button in the Green tea row
   → The row disappears, and "Your cart is empty" is in the middle of the screen
2. Look at the cart icon at the top right
   → The cart icon has no badge

**Failure looks like:** the badge still shows 1 over an empty cart.

#### 02/MC-3. The badge survives a sign-out and sign-in

**What it checks:** the badge shows the saved cart after signing in again.

**Order:** last — it signs the test account out

**Start:** S1 with one Green tea.

1. Sign out from the profile screen and sign in again with the same account
   → The home screen opens
2. Look at the cart icon at the top right
   → The badge shows 1

**Failure looks like:** the badge is gone after signing in.

### Session 2. Real device, about five minutes

#### 01/MC-2. Pulling the cart down refreshes it with the finger's speed

**What it checks:** a fast pull on the cart list refreshes it once and the spinner goes away.

**Device:** real

**Start:** S1 with one Green tea.

1. Pull the cart list down fast and let go
   → The spinner shows once and goes away, and the row stays

**Failure looks like:** the spinner stays on the screen, or the row disappears.

## Not covered

- Paying for the order: the checkout screen did not change in either step.

## Code references

| Case | Code |
|---|---|
| 01/MC-1 | (cart/quantity_stepper.src:41) |
| 02/MC-1 | (cart/badge_counter.src:18) |
| 02/MC-2 | (cart/badge_counter.src:30) |
| 02/MC-3 | (cart/badge_counter.src:44) |
| 01/MC-2 | (cart/refresh_control.src:12) |
| S1 | (cart/add_to_cart.src:22), (cart/cart_screen.src:14) |

**Result:** 01/MC-1 __ · 02/MC-1 __ · 02/MC-2 __ · 02/MC-3 __ · 01/MC-2 __ — PASS, FAIL, BLOCKED or DROPPED each; after a FAIL, a BLOCKED or a DROPPED, why, without an unbalanced parenthesis
