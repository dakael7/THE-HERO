const test = require("node:test");
const assert = require("node:assert/strict");

const {
  computeServerOrderMoney,
  couponDiscountFromData,
} = require("./orderPricing");

test("server order money ignores client item price and coupon amount", () => {
  const coupon = couponDiscountFromData(
    "TEST",
    {active: true, type: "fixed", value: 9999},
    1500,
  );
  const order = computeServerOrderMoney(
    {
      items: [{offerId: "offer-1", qty: 2, unitPriceSnapshot: 1}],
      subtotal: 2,
      deliveryFee: 1000,
      serviceFee: 400,
      tax: 100,
      tip: 250,
      amountTotal: 1,
      coupon: {code: "TEST", discountAmount: 9999},
    },
    new Map([["offer-1", 3000]]),
    coupon,
  );

  assert.equal(order.items[0].unitPriceSnapshot, 3000);
  assert.equal(order.subtotal, 6000);
  assert.equal(order.coupon.discountAmount, 1500);
  assert.equal(order.amountTotal, 6250);
});

test("percent coupon discounts only delivery, service fee and tax", () => {
  const coupon = couponDiscountFromData(
    "FREEFEES",
    {active: true, type: "percent", value: 100},
    700,
  );
  const order = computeServerOrderMoney(
    {
      items: [{offerId: "offer-1", qty: 1, unitPriceSnapshot: 0}],
      deliveryFee: 500,
      serviceFee: 100,
      tax: 100,
      tip: 0,
    },
    new Map([["offer-1", 2000]]),
    coupon,
  );

  assert.equal(order.subtotal, 2000);
  assert.equal(order.coupon.discountAmount, 700);
  assert.equal(order.amountTotal, 2000);
});
