# Walkthrough: promo code discount

[COVERS] = a1b2c3d..e4f5a6b

| Repository | Range | Commits | ± lines |
|---|---|---|---|
| `.` | `a1b2c3d..e4f5a6b` | 2 | +210/−14 |

> **How to read.** Start with What changed, then read the commits in order. Every `CartService` name in a quote is a reference only.

## What changed

**Before:** a promo code took its percentage off the whole order, delivery included, so a free-delivery order could go below zero.

**After:** the discount applies to the goods only, and delivery is added after it. An empty cart still costs nothing.

1. The discount no longer touches delivery.
2. An order of 1000 with delivery of 300 now costs 1200, not 1170.

## Glossary

- Goods total: the sum of item prices before delivery.
- Promo code: a code that takes a percentage off the goods total.

## Summary

**Why.** Customers saw totals that did not match the promo rule, e.g. 0.8 of the order instead of 0.8 of the goods.

**What was done.** The discount is now computed from the goods total only, and `CartTotals` adds delivery afterwards.

**Main decisions.** Rounding happens once, at the end, so a total never drifts by a cent.

## Commit order

1. The sanitiser first, because the totals read its output.
2. The totals second.

## Plan vs. outcome

| Planned | Landed | Why | Trigger |
|---|---|---|---|
| One `CartTotals` | One `CartTotals` | Nothing changed | implementation |

## Commits

### 1. `a1b2c3d` — the discount reads goods only

`fix(cart): take the promo discount from the goods total`

**In short:** the discount no longer includes delivery, so a free-delivery order stays above zero.

**Files:** `CartTotals` (+40), `CartTotalsTests` (+90), `Sources/Cart/Promo.src`, `docs/promo.md`, `a.b.c`.

**Changes:** 1, 2.

#### What appeared

The goods total is a new read-only property that sums item prices.

#### What failure this is written against

A promo code of 100% on a free-delivery order returned a negative total.

```swift
let total = goods - discount(goods) + delivery
```

**How verified:** the new test fails on the old code and passes now.

### 2. `e4f5a6b` — delivery joins after rounding

`fix(cart): add delivery after rounding`

**In short:** delivery is added last, so rounding cannot move it.

### Bookkeeping

- `a1b2c3d..e4f5a6b` — two commits.
- `0a1b2c3` — formatting only

## Plan vs. outcome notes

- First bullet without a final dot, written in the plain words of the reader
- Second bullet without a final dot, written in the plain words of the reader
- Third bullet without a final dot, written in the plain words of the reader
- Fourth bullet without a final dot, written in the plain words of the reader

1. First numbered item without a final dot, in the plain words of the reader
2. Second numbered item without a final dot, in the plain words of the reader
3. Third numbered item without a final dot, in the plain words of the reader
4. Call `a. b` to read the total, then `c. d` to read the delivery.

## Follow-ups

- Nothing yet.

## Out of scope

- Coupons that stack.
