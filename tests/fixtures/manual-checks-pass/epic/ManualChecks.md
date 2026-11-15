# Manual Checks — Collective pass: cart and badge

[COVERS] = 4f2a9c1

[STYLE] = brief

[PASS] = 01, 02

## Scope

One pass over the cases of steps 01 and 02 that no earlier walk marked. Five cases, about fifteen minutes.

## Cases

### Session 1. Simulator

#### 01/MC-1. The plus button raises the quantity and the total

**What it checks:** one tap on plus adds one item and the total grows by its price.

#### 02/MC-1. The badge counts items, not rows

**What it checks:** the badge on the cart icon shows the number of items.

#### 02/MC-3. The badge shows ten at the limit

**What it checks:** the badge shows 10 when a row reaches the limit.

### Session 2. Real device

#### 01/MC-2. Pulling the cart down refreshes it with the finger's speed

**What it checks:** a fast pull on the cart list refreshes it once and the spinner goes away.

#### 02/MC-2. The badge disappears with the last item

**What it checks:** the badge goes away when the cart is emptied.

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

**Result:** 01/MC-1 __ · 01/MC-2 FAIL (the spinner stays on the screen) · 02/MC-1 PASS · 02/MC-2 BLOCKED (no real device at hand) · 02/MC-3 DROPPED (the limit was removed from the design) — PASS, FAIL, BLOCKED or DROPPED each; after a FAIL, a BLOCKED or a DROPPED, why
