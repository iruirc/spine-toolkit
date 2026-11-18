# Manual Checks — Collective pass: cart and badge

[COVERS] = 4f2a9c1

[STYLE] = brief

[PASS] = 01, 02

## Scope

One pass over the cases of steps 01 and 02 that no earlier walk marked. Five cases, about fifteen minutes.

## Preparation

### S1. A cart with Green tea

Sign in with the test account cart.tester.1; its password is on the team's test-accounts page.
Add Green tea to the cart in the quantity the case's Start names, and open the cart.

## Cases

### Session 1. Simulator

#### 01/MC-1. The plus button raises the quantity and the total

**What it checks:** one tap on plus adds one item and the total grows by its price.

**Start:** S1 with one Green tea.

1. Tap the plus button in the Green tea row
   → The quantity reads 2, and the total reads "Total 9.00"

**Failure looks like:** the quantity reads 2 while the total still reads 4.50.

#### 02/MC-1. The badge counts items, not rows

**What it checks:** the badge on the cart icon shows the number of items.

**Start:** S1 with two Green tea.

1. Look at the badge on the cart icon
   → The badge shows 2

**Failure looks like:** the badge shows 1.

#### 02/MC-3. The badge shows ten at the limit

**What it checks:** the badge shows 10 when a row reaches the limit.

**Start:** S1 with nine Green tea.

1. Tap the plus button in the Green tea row
   → The quantity reads 10, and the badge shows 10

**Failure looks like:** the badge shows 9.

### Session 2. Real device

#### 01/MC-2. Pulling the cart down refreshes it with the finger's speed

**What it checks:** a fast pull on the cart list refreshes it once and the spinner goes away.

**Start:** S1 with one Green tea.

1. Pull the cart list down fast and let go
   → The spinner shows once and goes away, and the row stays

**Failure looks like:** the spinner stays on the screen, or the row disappears.

#### 02/MC-2. The badge disappears with the last item

**What it checks:** the badge goes away when the cart is emptied.

**Start:** S1 with one Green tea.

1. Tap the minus button in the Green tea row
   → The row disappears, and the cart icon has no badge

**Failure looks like:** the badge still shows 1.

## Not covered

- Paying for the order: the checkout screen did not change in this task.

## Code references

| Case | Code |
|---|---|
| 01/MC-1 | (cart/quantity_stepper.src:41) |
| 01/MC-2 | (cart/refresh_control.src:12) |
| 02/MC-1 | (cart/badge_counter.src:18) |
| 02/MC-2 | (cart/badge_counter.src:30) |
| 02/MC-3 | (cart/quantity_limit.src:17) |
| S1 | (cart/add_to_cart.src:22), (cart/cart_screen.src:14) |

**Result:** 01/MC-1 __ · 01/MC-2 FAIL (the spinner stays on the screen) · 02/MC-1 PASS · 02/MC-2 BLOCKED (no real device at hand) · 02/MC-3 DROPPED (the limit was removed from the design) — PASS, FAIL, BLOCKED or DROPPED each; after a FAIL, a BLOCKED or a DROPPED, why
