const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

const PENDING_PAYMENT_TIMEOUT_MS = 5 * 60 * 1000;
const MAX_RESERVATIONS_PER_RUN = 100;
const PENDING_ORDER_STATUSES = new Set([
  "created",
  "pending_payment",
  "pendingpayment",
]);

const normalizeStatus = (value) => {
  return String(value || "").trim().toLowerCase().replace(/[_-]/g, "");
};

const isApprovedPaymentDoc = (data) => {
  return normalizeStatus(data?.status) === "approved" || Boolean(data?.approvedAt);
};

const toMillis = (value) => {
  if (!value) return 0;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const parsed = new Date(value).getTime();
  return Number.isFinite(parsed) ? parsed : 0;
};

const isExpired = (reservation) => {
  const expiresAtMs = toMillis(reservation?.expiresAt);
  return expiresAtMs > 0 && expiresAtMs <= Date.now();
};

const qtyInt = (value) => {
  const parsed = Number(value ?? 1);
  if (!Number.isFinite(parsed)) return 1;
  const rounded = Math.round(parsed);
  return rounded > 0 ? rounded : 1;
};

const aggregateReservationItems = (items) => {
  const qtyByOfferId = new Map();
  for (const item of Array.isArray(items) ? items : []) {
    const offerId = String(item?.offerId || "").trim();
    if (!offerId) continue;
    qtyByOfferId.set(offerId, (qtyByOfferId.get(offerId) || 0) + qtyInt(item?.qty));
  }
  return Array.from(qtyByOfferId.entries()).map(([offerId, qty]) => ({
    offerId,
    qty,
  }));
};

const incrementOrderCounts = async (transaction, db, items) => {
  const entries = [];
  for (const item of items) {
    const offerRef = db.collection("offers").doc(item.offerId);
    const offerDoc = await transaction.get(offerRef);
    entries.push({offerRef, offerDoc});
  }

  for (const entry of entries) {
    if (!entry.offerDoc.exists) continue;

    const data = entry.offerDoc.data() || {};
    const orderCount = Number(data.orderCount ?? 0);
    transaction.update(entry.offerRef, {
      orderCount: (Number.isFinite(orderCount) ? orderCount : 0) + 1,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
};

const readPaymentDocsForOrder = async (transaction, db, orderIds) => {
  const ids = [...new Set(orderIds
    .map((value) => String(value || "").trim())
    .filter(Boolean))].slice(0, 10);
  if (ids.length === 0) return [];

  const query = ids.length === 1 ?
    db.collection("payments").where("orderId", "==", ids[0]) :
    db.collection("payments").where("orderId", "in", ids);
  const snap = await transaction.get(query);
  return snap.docs.map((doc) => doc.data() || {});
};

const updatePendingPaymentDocs = async (db, orderId) => {
  const snapshot = await db
    .collection("payments")
    .where("orderId", "==", String(orderId))
    .get();

  if (snapshot.empty) return 0;

  const batch = db.batch();
  let updates = 0;

  for (const doc of snapshot.docs) {
    const payment = doc.data() || {};
    const status = String(payment.status || "").toLowerCase();
    if (status === "approved" || status === "cancelled") continue;

    batch.set(
      doc.ref,
      {
        status: "cancelled",
        statusDetail: "payment_expired",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    updates++;
  }

  if (updates > 0) {
    await batch.commit();
  }

  return updates;
};

const releaseExpiredReservation = async (reservationRef) => {
  const db = admin.firestore();
  const nowMs = Date.now();
  const result = {
    orderId: reservationRef.id,
    released: false,
    skippedReason: null,
  };

  await db.runTransaction(async (transaction) => {
    const reservationDoc = await transaction.get(reservationRef);
    if (!reservationDoc.exists) {
      result.skippedReason = "reservation_missing";
      return;
    }

    const reservation = reservationDoc.data() || {};
    if (reservation.status !== "reserved") {
      result.skippedReason = "reservation_not_reserved";
      return;
    }

    if (!isExpired(reservation)) {
      result.skippedReason = "reservation_not_expired";
      return;
    }

    const orderId = String(reservation.orderId || reservationRef.id);
    const orderRef = db.collection("orders").doc(orderId);
    const orderDoc = await transaction.get(orderRef);
    const orderData = orderDoc.exists ? (orderDoc.data() || {}) : {};
    const orderStatus = String(orderData.status || "").toLowerCase();
    const stockRestored = orderData.stockRestored === true;

    const paymentDocs = await readPaymentDocsForOrder(transaction, db, [
      orderId,
      orderData.orderId,
    ]);
    if (paymentDocs.some(isApprovedPaymentDoc)) {
      await incrementOrderCounts(
        transaction,
        db,
        aggregateReservationItems(reservation.items),
      );

      transaction.update(reservationRef, {
        status: "consumed",
        consumedAt: admin.firestore.FieldValue.serverTimestamp(),
        consumedBy: "cancelExpiredPendingPayments",
        consumedReason: "payment_already_approved",
        orderCountIncremented: true,
      });

      if (orderDoc.exists) {
        const approvedPayload = {
          status: "queued",
          paymentStatus: "approved",
          "timestamps.paidAt": admin.firestore.FieldValue.serverTimestamp(),
          "timestamps.queuedAt": admin.firestore.FieldValue.serverTimestamp(),
          cancelReason: admin.firestore.FieldValue.delete(),
          canceledBy: admin.firestore.FieldValue.delete(),
          "timestamps.canceledAt": admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        transaction.update(orderRef, approvedPayload);
      }

      result.skippedReason = "payment_already_approved";
      return;
    }

    const canReleaseForOrder =
      !orderDoc.exists ||
      PENDING_ORDER_STATUSES.has(orderStatus) ||
      (orderStatus === "canceled" && !stockRestored);

    if (!canReleaseForOrder) {
      result.skippedReason = `order_status_${orderStatus || "unknown"}`;
      return;
    }

    const items = Array.isArray(reservation.items) ? reservation.items : [];
    const offerQtyDeltas = new Map();

    for (const item of items) {
      const offerId = String(item?.offerId || "").trim();
      if (!offerId) continue;
      offerQtyDeltas.set(
        offerId,
        (offerQtyDeltas.get(offerId) || 0) + qtyInt(item?.qty),
      );
    }

    const offerDocs = new Map();
    for (const [offerId] of offerQtyDeltas) {
      const offerRef = db.collection("offers").doc(offerId);
      const offerDoc = await transaction.get(offerRef);
      offerDocs.set(offerId, {ref: offerRef, doc: offerDoc});
    }

    for (const [offerId, delta] of offerQtyDeltas) {
      const entry = offerDocs.get(offerId);
      if (!entry?.doc?.exists) continue;

      const offer = entry.doc.data() || {};
      const currentQty = Number(offer.availableQty ?? 0);
      const restoredQty = currentQty + delta;

      const updateData = {
        stock: restoredQty,
        availableQty: restoredQty,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (offer.status === "sold_out" && restoredQty > 0) {
        updateData.status = "active";
      }

      transaction.update(entry.ref, updateData);
    }

    const releasePayload = {
      status: "released",
      releasedAt: admin.firestore.FieldValue.serverTimestamp(),
      releasedBy: "cancelExpiredPendingPayments",
      releasedReason: "pending_payment_expired",
      expiredAfterMs: PENDING_PAYMENT_TIMEOUT_MS,
    };
    transaction.update(reservationRef, releasePayload);

    if (orderDoc.exists) {
      const cancelPayload = {
        status: "canceled",
        cancelReason: "Pago no completado dentro de 5 minutos",
        canceledBy: "system:payment_expiration",
        paymentStatus: "expired",
        paymentExpiredAt: admin.firestore.FieldValue.serverTimestamp(),
        "timestamps.canceledAt": admin.firestore.FieldValue.serverTimestamp(),
        stockRestored: true,
        stockRestoredAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      transaction.update(orderRef, cancelPayload);

      const heroId = String(orderData.heroId || "").trim();
      if (heroId) {
        const buyerIndexRef = db
          .collection("user_orders")
          .doc(heroId)
          .collection("orders")
          .doc(orderId);
        transaction.set(buyerIndexRef, cancelPayload, {merge: true});
      }

      const sellerIds = Array.isArray(orderData.sellerHeroIds) ?
        orderData.sellerHeroIds :
        [];
      for (const rawSellerId of sellerIds) {
        const sellerId = String(rawSellerId || "").trim();
        if (!sellerId) continue;
        const sellerIndexRef = db
          .collection("user_orders")
          .doc(sellerId)
          .collection("orders")
          .doc(orderId);
        transaction.set(sellerIndexRef, cancelPayload, {merge: true});
      }
    }

    result.orderId = orderId;
    result.released = true;
    result.expiredByMs = nowMs - toMillis(reservation.expiresAt);
  });

  if (result.released) {
    result.updatedPayments = await updatePendingPaymentDocs(
      db,
      result.orderId,
    );
  }

  return result;
};

exports.cancelExpiredPendingPayments = onSchedule(
  {
    schedule: "every 1 minutes",
    region: "us-central1",
    timeZone: "America/Santiago",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const db = admin.firestore();
    const snapshot = await db
      .collection("stockReservations")
      .where("status", "==", "reserved")
      .limit(MAX_RESERVATIONS_PER_RUN)
      .get();

    let scanned = 0;
    let expired = 0;
    let released = 0;
    let skipped = 0;
    let updatedPayments = 0;

    for (const doc of snapshot.docs) {
      scanned++;
      const reservation = doc.data() || {};
      if (!isExpired(reservation)) continue;

      expired++;
      try {
        const result = await releaseExpiredReservation(doc.ref);
        if (result.released) {
          released++;
          updatedPayments += result.updatedPayments || 0;
        } else {
          skipped++;
          logger.info("[pending-payment-expiry] skipped reservation", {
            orderId: result.orderId,
            reason: result.skippedReason,
          });
        }
      } catch (error) {
        skipped++;
        logger.error("[pending-payment-expiry] failed reservation", {
          orderId: doc.id,
          error: error?.message || error,
        });
      }
    }

    logger.info("[pending-payment-expiry] run complete", {
      scanned,
      expired,
      released,
      skipped,
      updatedPayments,
    });
  },
);
