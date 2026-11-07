# Plan: promo code discount

## For the owner

**Goal.** A promo code takes its percentage off the goods only, never off delivery.

**Phases.** Two phases: the totals first, then the cart screen. Each ends with a green test run.

**Risks.** Old orders keep their stored totals, so a report that mixes old and new orders may show a small gap.

**Decision for you.** Round once at the end of the order, or after every line. We recommend once at the end (rounding drift is the reason).

## For the implementer

### Phases

| Phase | Scope | Check |
|---|---|---|
| 1 | Totals | Unit tests of `CartTotals` |
| 2 | Cart screen | Snapshot of the cart screen |

### Steps

- [x] Read the current discount code
- [x] Write the failing test for delivery
- [x] Move the discount before delivery
- [x] Round once at the end
- [x] Cover the empty cart
- [x] Cover a zero percent code
- [ ] Update the cart screen
- [ ] Update the snapshot
- [ ] Run the full suite
- [ ] Check the order history report
- [ ] Update the changelog
- [ ] Ask for review

1. Run the unit tests of the totals
2. Run the snapshot tests
3. Run the full suite

### Files

```
Sources/Cart/CartTotals.swift
Tests/Cart/CartTotalsTests.swift
```
