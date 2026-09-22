# Ops Checklist — 042-promo-delivery

## Release & rollout
- N/A: Feature flag — a fix to an existing calculation, so there is nothing new to gate behind a flag

## State & lifecycle
- N/A: Background sync — the cart is priced on the device only and is never synced in the background

## Error handling
- [x] Applicable — a promo code that fails to parse leaves the price exactly as it was before

## Accessibility
- N/A: Assistive-technology labels — no screen changed, and the price label reads the same value

## Analytics
- N/A: Key user actions instrumented — no event is added or renamed by this change

## Testing
- [x] Applicable — one regression test pins the discount base for an order with delivery
