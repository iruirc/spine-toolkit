# Manual Checks — Cart quantity stepper

[COVERS] = a1b2c3d..e4f5a6b

## Scope

Built and tested; the stepper arithmetic is covered by unit tests (cart/quantity_stepper.src:41).

## Cases

### 1. The plus button raises the quantity

**Scene:** a cart holding one Green tea.

**Action:** tap the plus button on the Green tea row.

**By eye:** the quantity reads 2 and the total reads 9.00.

**Failure looks like:** the total stays at 4.50 (cart/quantity_stepper.src:41)

### 2. The plus button stops at ten items

**Scene:** a cart holding nine Green tea.

**Action:** tap the plus button twice.

**By eye:** the quantity stops at 10.

**Failure looks like:** the quantity reads 11 (cart/quantity_limit.src:17)

## Not covered

none
