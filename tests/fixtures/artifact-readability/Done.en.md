# Done: promo code discount

## Summary

A promo code now takes its percentage off the goods only, so a free-delivery order can no longer go below zero. The change touches `CartTotals` and its tests, and nothing else in the cart.

## What was done

- The discount is computed from the goods total.
- Delivery is added after the discount.
- An empty cart still costs nothing.

## Verification

| What | Evidence |
|---|---|
| Totals with a promo code | The test `promo_applies_to_goods_only` passes |
| Empty cart | The test `empty_cart_costs_nothing` passes |

## Follow-ups

None.

[DONE_COMMIT] = a1b2c3d
[REVIEW_FIXES] = none
**Run:** 2026-11-07 on a clean checkout
**Device:** none
