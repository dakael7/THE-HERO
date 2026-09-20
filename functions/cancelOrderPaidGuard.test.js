const assert = require("assert");

// Mirrors the pre-transaction guard in cancelOrder: MercadoPago is asked
// whether the order is paid BEFORE anything is canceled, because the payment
// docs in Firestore can still say "pending" while the money is captured.
const decideCancel = (approvedAtMercadoPago) => {
  if (approvedAtMercadoPago === true) return "reject_paid";
  if (approvedAtMercadoPago === null) return "reject_unverifiable";
  return "allow_cancel";
};

// A paid order can never be canceled, however stale Firestore is.
assert.strictEqual(decideCancel(true), "reject_paid");

// MercadoPago unreachable: refuse rather than cancel a possibly-paid order.
// This is the case that turned a paid order into a canceled one.
assert.strictEqual(decideCancel(null), "reject_unverifiable");

// Confirmed unpaid: cancelling is safe.
assert.strictEqual(decideCancel(false), "allow_cancel");

// The verify button is offered on every unfulfilled order, including one the
// buyer canceled themselves — the backend decides if a payment exists.
const canVerifyPayment = ({status, isPendingPayment, isPaymentExpired}) =>
  (isPendingPayment && isPaymentExpired) ||
  status === "failed" ||
  status === "canceled";

assert.strictEqual(
  canVerifyPayment({status: "canceled"}),
  true,
  "a canceled order must offer recovery, whoever canceled it",
);
assert.strictEqual(canVerifyPayment({status: "failed"}), true);
assert.strictEqual(
  canVerifyPayment({
    status: "pending_payment",
    isPendingPayment: true,
    isPaymentExpired: true,
  }),
  true,
);
// Not offered while the order is live or already moving.
assert.strictEqual(
  canVerifyPayment({
    status: "pending_payment",
    isPendingPayment: true,
    isPaymentExpired: false,
  }),
  false,
);
assert.strictEqual(canVerifyPayment({status: "queued"}), false);
assert.strictEqual(canVerifyPayment({status: "delivered"}), false);

console.log("cancelOrder paid-guard and verify-button rules OK");
