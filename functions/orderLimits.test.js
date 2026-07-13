const test = require("node:test");
const assert = require("node:assert/strict");

const {
  HERO_WEEKLY_ORDER_LIMIT,
  HERO_ORDERS_PER_WEEKLY_DONATION,
  countsAsHeroWeeklyDonation,
  countsAsHeroWeeklyOrder,
  getCurrentIsoWeekBounds,
  weeklyOrderLimitForDonations,
} = require("./orderLimits");

test("hero weekly limit is three active orders", () => {
  assert.equal(HERO_WEEKLY_ORDER_LIMIT, 3);
  assert.equal(countsAsHeroWeeklyOrder({status: "pending_payment"}), true);
  assert.equal(countsAsHeroWeeklyOrder({status: "delivered"}), true);
  assert.equal(countsAsHeroWeeklyOrder({status: "canceled"}), false);
  assert.equal(countsAsHeroWeeklyOrder({status: "failed"}), false);
  assert.equal(countsAsHeroWeeklyOrder({status: "created"}), false);
});

test("each weekly donation unlocks three more hero orders", () => {
  assert.equal(HERO_ORDERS_PER_WEEKLY_DONATION, 3);
  assert.equal(weeklyOrderLimitForDonations(0), 3);
  assert.equal(weeklyOrderLimitForDonations(1), 6);
  assert.equal(weeklyOrderLimitForDonations(2), 9);
  assert.equal(countsAsHeroWeeklyDonation({status: "active"}), true);
  assert.equal(countsAsHeroWeeklyDonation({status: "sold_out"}), true);
  assert.equal(countsAsHeroWeeklyDonation({status: "paused"}), false);
  assert.equal(countsAsHeroWeeklyDonation({status: "draft"}), false);
});

test("hero weekly limit uses Monday UTC boundaries", () => {
  const {start, end} = getCurrentIsoWeekBounds(
    new Date("2026-07-15T12:00:00.000Z"),
  );

  assert.equal(start.toISOString(), "2026-07-13T00:00:00.000Z");
  assert.equal(end.toISOString(), "2026-07-20T00:00:00.000Z");
});
