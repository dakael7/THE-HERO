const test = require("node:test");
const assert = require("node:assert/strict");

const {
  calculateRiderCommission,
} = require("./money");

test("rider commission does not wipe out low app delivery fees by default", () => {
  const result = calculateRiderCommission({deliveryFee: 1500});

  assert.equal(result.serviceFee, 0);
  assert.equal(result.netEarnings, 1395);
});

test("rider commission respects an explicit zero service fee", () => {
  const result = calculateRiderCommission({
    deliveryFee: 3000,
    serviceFeeCLP: 0,
    taxPercentage: 0.07,
  });

  assert.equal(result.serviceFee, 0);
  assert.equal(result.netEarnings, 2790);
});
