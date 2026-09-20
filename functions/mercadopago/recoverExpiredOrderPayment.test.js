const assert = require("assert");

// Mirrors the guard logic in recoverExpiredOrderPayment: which orders may be
// revived after an expiry-cancel, and which must never be touched.
const RECOVERABLE_STATUSES = new Set([
  "created",
  "pendingpayment",
  "canceled",
  "cancelled",
  "failed",
  "paid",
]);

const REFUNDING_STATUSES = [
  "requested",
  "pending",
  "approved",
  "refunded",
  "completed",
];

const normalizeStatus = (value) =>
  String(value || "").trim().toLowerCase().replace(/[_-]/g, "");

// Refund is checked FIRST: "refunded" is not a recoverable status, so testing
// it after the status gate would report a refunded order as "already active".
const canRecover = ({status, refundStatus}) => {
  const orderStatus = normalizeStatus(status);
  if (
    orderStatus === "refunded" ||
    REFUNDING_STATUSES.includes(normalizeStatus(refundStatus))
  ) {
    return "refunded";
  }
  if (!RECOVERABLE_STATUSES.has(orderStatus)) return "already_active";
  return "eligible";
};

// The case that actually happened: auto-canceled after expiry, money taken.
assert.strictEqual(canRecover({status: "canceled"}), "eligible");
assert.strictEqual(canRecover({status: "pending_payment"}), "eligible");
assert.strictEqual(canRecover({status: "failed"}), "eligible");
assert.strictEqual(canRecover({status: "paid"}), "eligible");

// Never revive an order whose money is already going back to the buyer.
assert.strictEqual(canRecover({status: "refunded"}), "refunded");
assert.strictEqual(
  canRecover({status: "canceled", refundStatus: "requested"}),
  "refunded",
);
assert.strictEqual(
  canRecover({status: "canceled", refundStatus: "approved"}),
  "refunded",
);

// Never re-run fulfillment on an order already moving.
assert.strictEqual(canRecover({status: "queued"}), "already_active");
assert.strictEqual(canRecover({status: "assigned"}), "already_active");
assert.strictEqual(canRecover({status: "in_transit"}), "already_active");
assert.strictEqual(canRecover({status: "delivered"}), "already_active");

console.log("recoverExpiredOrderPayment guards OK");
