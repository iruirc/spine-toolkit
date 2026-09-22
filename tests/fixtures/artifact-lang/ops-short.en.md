# Ops Checklist — 042-promo-delivery

## Release & rollout
- N/A: Feature flag — a fix to an existing calculation, nothing to gate

## State & lifecycle
- N/A: Background sync — the cart is priced on the device only

## Error handling
- [x] Applicable — a promo code that fails to parse leaves the price as it was

## Accessibility
- N/A: no screen changed, the price label reads the same value

## Analytics
- N/A: no event added or renamed by this change

## Testing
- [x] Applicable — one regression test pins the discount base with delivery
