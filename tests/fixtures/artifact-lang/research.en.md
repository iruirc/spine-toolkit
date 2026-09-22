# Research — 042-promo-delivery

[TASK_TYPE] = [BUG]

## Summary

The promo code is subtracted from the whole order, delivery included. The cause is that
`PromoCalculator` receives the total instead of the subtotal: DiscountPolicy builds it from the
whole CartState and adds delivery before the policy applies the discount. So an order of 1000
with 300 of delivery costs 1170 instead of 1200. The fix is narrow: the policy reads the goods only.

## Root cause

DiscountPolicy takes CartState.total and hands it to PromoCalculator. That sum already holds the
delivery fee, because `CartState` recomputes the total on every change of address. Checked on a
branch with one item and one delivery: the discount is taken from 1300 where it should be taken
from 1000. The same scenario on an empty cart breaks nothing, since its total is zero.

## Evidence

The history of the change is two commits, and both touch the discount calculation only. The rates
of delivery live elsewhere and are not changed here: this task moves the base the discount is
taken from, not the delivery itself. A later task may revisit the rates on their own.
