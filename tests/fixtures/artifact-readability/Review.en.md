[REVIEW_STATUS] = APPROVED

# Review: promo code discount

## Summary

The change does what the task asks. The discount applies to the goods only, and one finding is minor.

## Findings

### Rounding is done twice (M1)

**Impact:** a shopper may see a total one cent off when a promo code and an odd price meet.

The total is rounded in `CartTotals` and again on the cart screen. Keep only the first rounding.

## Previous findings

None.

[REVIEWED_COMMIT] = e4f5a6b
**Run:** 2026-11-07 on a clean checkout
**Device:** none
