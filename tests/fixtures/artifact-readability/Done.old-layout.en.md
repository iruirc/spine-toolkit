[DONE_COMMIT] = a1b2c3d
**Run:** 2026-11-07 on a clean checkout
[REVIEW_FIXES] = none

# Done: promo code discount

## Summary

A promo code now takes its percentage off the goods only, so a free-delivery order can no longer go below zero.

## What was done

- The discount is computed from the goods total.
- Delivery is added after the discount.

## Follow-ups

None.
