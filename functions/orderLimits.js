const {HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const HERO_WEEKLY_ORDER_LIMIT = 3;
const HERO_ORDERS_PER_WEEKLY_DONATION = 3;
const COUNTED_HERO_ORDER_STATUSES = new Set([
  "pendingpayment",
  "paid",
  "queued",
  "assigned",
  "pickedup",
  "intransit",
  "delivered",
]);
const COUNTED_WEEKLY_DONATION_STATUSES = new Set(["active", "soldout"]);

function normalizeOrderStatusForLimit(value) {
  return String(value || "").trim().toLowerCase().replace(/[_-]/g, "");
}

function countsAsHeroWeeklyOrder(order) {
  return COUNTED_HERO_ORDER_STATUSES.has(
    normalizeOrderStatusForLimit(order && order.status),
  );
}

function normalizeOfferStatusForLimit(value) {
  return String(value || "").trim().toLowerCase().replace(/[_-]/g, "");
}

function countsAsHeroWeeklyDonation(offer) {
  return COUNTED_WEEKLY_DONATION_STATUSES.has(
    normalizeOfferStatusForLimit(offer && offer.status),
  );
}

function weeklyOrderLimitForDonations(donationCount) {
  const safeDonationCount = Math.max(0, Math.round(Number(donationCount) || 0));
  return HERO_WEEKLY_ORDER_LIMIT +
    (safeDonationCount * HERO_ORDERS_PER_WEEKLY_DONATION);
}

function timestampToMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === "object" && Number.isFinite(value._seconds)) {
    return (value._seconds * 1000) + Math.round((value._nanoseconds || 0) / 1000000);
  }
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : 0;
}

function getCurrentIsoWeekBounds(now = new Date()) {
  const start = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
  const day = start.getUTCDay() || 7;
  start.setUTCDate(start.getUTCDate() + 1 - day);

  const end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 7);
  return {start, end};
}

async function countHeroWeeklyDonations({transaction, db, heroId, start, end}) {
  const offersSnap = await transaction.get(
    db.collection("offers").where("heroId", "==", heroId),
  );
  const startMs = start.getTime();
  const endMs = end.getTime();

  return offersSnap.docs.filter((doc) => {
    const offer = doc.data() || {};
    if (!countsAsHeroWeeklyDonation(offer)) return false;

    const publishedAtMs = timestampToMillis(offer.publishedAt) ||
      timestampToMillis(offer.createdAt);
    return publishedAtMs >= startMs && publishedAtMs < endMs;
  }).length;
}

async function assertHeroWeeklyOrderLimit({
  transaction,
  db = admin.firestore(),
  heroId,
  excludingOrderId = "",
}) {
  const cleanHeroId = String(heroId || "").trim();
  if (!cleanHeroId) {
    throw new HttpsError("invalid-argument", "heroId es requerido");
  }

  const {start, end} = getCurrentIsoWeekBounds();
  const ordersRef = db
    .collection("user_orders")
    .doc(cleanHeroId)
    .collection("orders");
  const tsStart = admin.firestore.Timestamp.fromDate(start);
  const tsEnd = admin.firestore.Timestamp.fromDate(end);
  const docsById = new Map();

  const timestampSnap = await transaction.get(
    ordersRef
      .where("timestamps.createdAt", ">=", tsStart)
      .where("timestamps.createdAt", "<", tsEnd),
  );
  timestampSnap.docs.forEach((doc) => docsById.set(doc.id, doc.data() || {}));

  const stringSnap = await transaction.get(
    ordersRef
      .where("timestamps.createdAt", ">=", start.toISOString())
      .where("timestamps.createdAt", "<", end.toISOString()),
  );
  stringSnap.docs.forEach((doc) => docsById.set(doc.id, doc.data() || {}));

  const weeklyDonations = await countHeroWeeklyDonations({
    transaction,
    db,
    heroId: cleanHeroId,
    start,
    end,
  });
  const weeklyLimit = weeklyOrderLimitForDonations(weeklyDonations);

  const excludedId = String(excludingOrderId || "").trim();
  const used = [...docsById.entries()].filter(([id, order]) =>
    id !== excludedId && countsAsHeroWeeklyOrder(order),
  ).length;

  if (used >= weeklyLimit) {
    throw new HttpsError(
      "resource-exhausted",
      `Ya alcanzaste el limite de ${weeklyLimit} pedidos de esta semana. Publica una donacion para desbloquear ${HERO_ORDERS_PER_WEEKLY_DONATION} pedidos mas.`,
    );
  }

  return {
    used,
    weeklyDonations,
    limit: weeklyLimit,
    remaining: weeklyLimit - used,
  };
}

module.exports = {
  HERO_WEEKLY_ORDER_LIMIT,
  HERO_ORDERS_PER_WEEKLY_DONATION,
  assertHeroWeeklyOrderLimit,
  countsAsHeroWeeklyDonation,
  countsAsHeroWeeklyOrder,
  getCurrentIsoWeekBounds,
  weeklyOrderLimitForDonations,
};
