# Done: promo code discount

## Summary

A promo code now takes its percentage off the goods only, so a free-delivery order can no longer go below zero. A shopper who enters a code sees a correct total at checkout. Nothing else in the cart looks different.

## Why

A code worth more than the goods took the rest off delivery. The total went below zero, and the payment failed at checkout.

## What is left and risks

Old orders keep their stored totals, so a report that mixes old and new orders may show a small gap.

## Objections

The owner chose to round once at the end of the order. The agents proposed rounding after every line, because the old receipts did so.

## Phases

| Phase | What |
|---|---|
| 1 | The discount is computed from the goods total (`CartTotals`) |
| 2 | The cart screen shows the new total (`CartView`) |

## Verification

| What | Evidence |
|---|---|
| Totals with a promo code | The test `promo_applies_to_goods_only` passes |
| Empty cart | The test `empty_cart_costs_nothing` passes |

## Review findings closed

None.

[DONE_COMMIT] = a1b2c3d
[REVIEW_FIXES] = none
**Run:** 2026-11-07 on a clean checkout
**Device:** none
