# Walkthrough: promo code discount

[COVERS] = a1b2c3d..e4f5a6b

## What changed

**Before:** a promo code took its percentage off the whole order.

**After:** the discount applies to the goods only.

## Summary

**Why.** The totals did not match the promo rule, because the discount was taken from the whole order including delivery, which made a free-delivery order drop below zero whenever the code was worth a hundred percent of the goods.

**What was done.** The discount is computed from the goods total. Delivery is added after it.

## Notes

- A short bullet without a final dot
- Another short bullet without a final dot
