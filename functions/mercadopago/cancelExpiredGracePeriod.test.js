const assert = require("assert");


const PENDING_PAYMENT_TIMEOUT_MS = 5 * 60 * 1000;
const CANCELLATION_GRACE_MS = 10 * 60 * 1000;

const toMillis = (value) => {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : 0;
};

const isExpired = (reservation, nowMs) => {
  const expiresAtMs = toMillis(reservation?.expiresAt);
  return expiresAtMs > 0 && expiresAtMs <= nowMs;
};

const isPastGracePeriod = (reservation, nowMs) => {
  const expiresAtMs = toMillis(reservation?.expiresAt);
  return expiresAtMs > 0 && expiresAtMs + CANCELLATION_GRACE_MS <= nowMs;
};

const decide = ({minutesSinceReservation, approvedAtMercadoPago}) => {
  const createdAtMs = 0;
  const nowMs = minutesSinceReservation * 60 * 1000;
  const reservation = {
    expiresAt: new Date(createdAtMs + PENDING_PAYMENT_TIMEOUT_MS),
  };

  if (!isExpired(reservation, nowMs)) return "not_expired";
  if (!isPastGracePeriod(reservation, nowMs)) return "in_grace_period";
  if (approvedAtMercadoPago === null) return "verification_unavailable";
  if (approvedAtMercadoPago === true) return "recover_paid_order";
  return "cancel";
};

const notPaid = {approvedAtMercadoPago: false};

// Before the 5-minute timeout: untouched.
assert.strictEqual(decide({minutesSinceReservation: 2, ...notPaid}), "not_expired");
assert.strictEqual(decide({minutesSinceReservation: 4, ...notPaid}), "not_expired");

// Expired but inside the 10-minute grace window: this is the window in which
// the real incident happened. Nothing may be canceled here.
assert.strictEqual(
  decide({minutesSinceReservation: 6, ...notPaid}),
  "in_grace_period",
);
assert.strictEqual(
  decide({minutesSinceReservation: 14, ...notPaid}),
  "in_grace_period",
);
// Exactly at the boundary (5 + 10) cancellation becomes allowed.
assert.strictEqual(decide({minutesSinceReservation: 15, ...notPaid}), "cancel");
assert.strictEqual(decide({minutesSinceReservation: 30, ...notPaid}), "cancel");

// A late payment is recovered, never canceled, however long it took.
assert.strictEqual(
  decide({minutesSinceReservation: 20, approvedAtMercadoPago: true}),
  "recover_paid_order",
);
assert.strictEqual(
  decide({minutesSinceReservation: 120, approvedAtMercadoPago: true}),
  "recover_paid_order",
);

// MercadoPago unreachable: never cancel on a guess.
assert.strictEqual(
  decide({minutesSinceReservation: 60, approvedAtMercadoPago: null}),
  "verification_unavailable",
);

console.log("cancelExpiredPendingPayments grace-period guards OK");
