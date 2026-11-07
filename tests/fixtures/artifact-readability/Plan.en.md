# Plan: promo code discount

## For the owner

**Goal.** A promo code takes its percentage off the goods only, never off delivery. A free-delivery order never goes below zero.

| Phase | What | Status |
|---|---|---|
| 1 | The totals take the discount off the goods only | done |
| 2 | The cart screen shows the new total | pending |

**Risks.** Old orders keep their stored totals, so a report that mixes old and new orders may show a small gap.

**Decision for you.** Round once at the end of the order, or after every line. We recommend once at the end (rounding drift is the reason).

## For the implementer

### Phase 1: totals

- [x] Read the current discount code
- [x] Write the failing test for delivery
- [x] Move the discount before delivery
- [x] Round once at the end
- [x] Cover the empty cart
- [x] Cover a zero percent code

**Verification:** the unit tests of `CartTotals` pass.

### Phase 2: cart screen

- [ ] Update the cart screen
- [ ] Update the snapshot
- [ ] Run the full suite
- [ ] Check the order history report
- [ ] Update the changelog
- [ ] Ask for review

**Verification:** the snapshot of the cart screen matches.

1. Run the unit tests of the totals
2. Run the snapshot tests
3. Run the full suite

### Files

```
Sources/Cart/CartTotals.swift
Tests/Cart/CartTotalsTests.swift
```
