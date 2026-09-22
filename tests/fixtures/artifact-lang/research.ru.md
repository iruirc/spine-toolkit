# Research — 042-promo-delivery

[TASK_TYPE] = [BUG]

## Summary

Промокод вычитается из всей суммы заказа, включая доставку. Причина в том, что `PromoCalculator`
получает total вместо subtotal: DiscountPolicy собирает его из CartState целиком, а доставку
добавляет ещё до того, как policy применяет скидку. Поэтому заказ на 1000 рублей с доставкой
300 рублей стоит 1170, а не 1200. Fix узкий: policy должна читать только сумму товаров.

## Root cause

DiscountPolicy берёт CartState.total и передаёт его в PromoCalculator. Сумма уже содержит
delivery fee, потому что `CartState` пересчитывает total при каждом изменении адреса. Проверено
на ветке с одним товаром и одной доставкой: скидка считается от 1300, а должна от 1000. Тот же
сценарий на пустой корзине ничего не ломает, там total равен нулю.

- Исправление затрагивает один вызов:

    ```
    /// Applies the promo code to the goods only; delivery is priced after the discount.
    fun discountFor(cart: CartState): Money = calculator.apply(cart.subtotal)
    ```

## Evidence

| Scenario | Before | After |
|---|---|---|
| one item, delivery | 1170 | 1200 |
| empty cart | 0 | 0 |

**Commits:** история изменения лежит в двух коммитах, оба трогают только расчёт скидки:

- `a1b2c3d` fix(cart): apply the promo code to the goods, not the delivery
- `e4f5a6b` test(cart): pin the discount base for an order with delivery

Файлы: src/cart/DiscountPolicy.kt и src/cart/PromoCalculator.kt, отчёт в Validation.md. Подробности
про ставки доставки лежат по адресу https://example.com/docs/delivery-rates и в этой задаче не
меняются: мы трогаем только базу, от которой считается скидка, а не саму доставку.
