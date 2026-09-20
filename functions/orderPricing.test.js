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
    7500,
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
  assert.equal(order.deliveryFee, 1000);
  assert.equal(order.coupon.discountAmount, 7500);
  assert.equal(order.amountTotal, 250);
});


test("percent coupon is capped at the service fee", () => {
  const serviceFee = 100;
  const coupon = couponDiscountFromData(
    "FREEORDER",
    {active: true, type: "percent", value: 100},
    serviceFee,
  );
  const order = computeServerOrderMoney(
    {
      items: [{offerId: "offer-1", qty: 1, unitPriceSnapshot: 0}],
      deliveryFee: 500,
      serviceFee,
      tax: 100,
      tip: 0,
    },
    new Map([["offer-1", 2000]]),
    coupon,
  );

  assert.equal(order.subtotal, 2000);
  assert.equal(order.deliveryFee, 500);
  assert.equal(order.coupon.discountAmount, 100);
  assert.equal(order.amountTotal, 2600);
});

test("fixed coupon cannot exceed the service fee", () => {
  const serviceFee = 400;
  const coupon = couponDiscountFromData(
    "BIGFIXED",
    {active: true, type: "fixed", value: 99999},
    serviceFee,
  );

  assert.equal(coupon.amount, serviceFee);

  const order = computeServerOrderMoney(
    {
      items: [{offerId: "offer-1", qty: 2, unitPriceSnapshot: 1}],
      deliveryFee: 1000,
      serviceFee,
      tax: 100,
      tip: 250,
    },
    new Map([["offer-1", 3000]]),
    coupon,
  );

  // 6000 + 1000 + 400 + 100 + 250 - 400
  assert.equal(order.amountTotal, 7350);
});

test("50% coupon halves only the service fee", () => {
  const serviceFee = 2000;
  const coupon = couponDiscountFromData(
    "HALF",
    {active: true, type: "percent", value: 50},
    serviceFee,
  );

  assert.equal(coupon.amount, 1000);

  const order = computeServerOrderMoney(
    {
      items: [{offerId: "offer-1", qty: 1, unitPriceSnapshot: 0}],
      deliveryFee: 1500,
      serviceFee,
      tax: 1900,
      tip: 0,
    },
    new Map([["offer-1", 10000]]),
    coupon,
  );

  // 10000 + 1500 + 2000 + 1900 - 1000
  assert.equal(order.amountTotal, 14400);
});
