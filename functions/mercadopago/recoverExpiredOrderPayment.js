const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {MercadoPagoConfig, Payment} = require("mercadopago");
const {
  getMercadoPagoAccessToken,
  redactMercadoPagoSecrets,
} = require("./credentials");
const {resolveApprovedOrderFulfillment} = require("./orderFulfillment");

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

const normalizeStatus = (value) => {
  return String(value || "").trim().toLowerCase().replace(/[_-]/g, "");
};

const timestamp = () => admin.firestore.FieldValue.serverTimestamp();

const resolveOrderRef = async (db, rawOrderId) => {
  const raw = String(rawOrderId).trim();
  const prefixed = raw.startsWith("HRO-") ? raw : `HRO-${raw}`;
  const unprefixed = raw.startsWith("HRO-") ? raw.substring(4) : raw;
  const candidates = [raw, prefixed, unprefixed].filter(
    (value, index, arr) => value && arr.indexOf(value) === index,
  );

  for (const candidate of candidates) {
    const ref = db.collection("orders").doc(candidate);
    const doc = await ref.get();
    if (doc.exists) return {ref, doc};
  }
  return {ref: null, doc: null};
};

const mirrorToUserOrders = async (db, orderId, orderData, payload) => {
  const ids = [
    String(orderData.heroId || "").trim(),
    ...(Array.isArray(orderData.sellerHeroIds) ? orderData.sellerHeroIds : [])
      .map((value) => String(value || "").trim()),
  ].filter(Boolean);

  for (const id of [...new Set(ids)]) {
    await db
      .collection("user_orders")
      .doc(id)
      .collection("orders")
      .doc(orderId)
      .set(payload, {merge: true});
  }
};

// Finds the approved MercadoPago payment for this order by asking MercadoPago
// directly: Firestore can be stale, which is the failure this recovers from.
const findApprovedPayment = async (db, orderId) => {
  const accessToken = getMercadoPagoAccessToken();
  if (!accessToken) {
    throw new HttpsError(
      "failed-precondition",
      "MercadoPago no esta configurado.",
    );
  }

  const client = new MercadoPagoConfig({
    accessToken,
    options: {timeout: 8000},
  });
  const payment = new Payment(client);

  // Authoritative: search MercadoPago by our own order id.
  try {
    const search = await payment.search({
      options: {external_reference: String(orderId), limit: 50},
    });
    const results = Array.isArray(search?.results) ? search.results : [];
    const approved = results.find(
      (item) => normalizeStatus(item?.status) === "approved",
    );
    if (approved) return approved;
    if (results.length > 0) return null;
  } catch (error) {
    logger.warn("[recover-payment] search failed, falling back", {
      orderId,
      error: redactMercadoPagoSecrets(error?.message ?? error),
    });
  }

  // Fallback: re-check every payment id we already know for this order.
  const snapshot = await db
    .collection("payments")
    .where("orderId", "==", String(orderId))
    .get();

  const paymentIds = [
    ...new Set(
      snapshot.docs
        .map((doc) => String((doc.data() || {}).paymentId || "").trim())
        .filter(Boolean),
    ),
  ];

  for (const paymentId of paymentIds) {
    try {
      const data = await payment.get({id: paymentId});
      if (normalizeStatus(data?.status) === "approved") return data;
    } catch (error) {
      logger.warn("[recover-payment] payment lookup failed", {
        orderId,
        paymentId,
        error: redactMercadoPagoSecrets(error?.message ?? error),
      });
    }
  }

  return null;
};

exports.recoverExpiredOrderPayment = onCall(
  {
    memory: "512MiB",
    secrets: ["MERCADOPAGO_ACCESS_TOKEN"],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Debes iniciar sesion para verificar el pago.",
      );
    }

    const callerUid = request.auth.uid;
    const orderId = String(request.data?.orderId || "").trim();
    if (!orderId) {
      throw new HttpsError("invalid-argument", "Falta el orderId.");
    }

    const db = admin.firestore();
    const {ref: orderRef, doc: orderDoc} = await resolveOrderRef(db, orderId);
    if (!orderRef || !orderDoc) {
      throw new HttpsError("not-found", "Pedido no encontrado.");
    }

    const orderData = orderDoc.data() || {};

    // Only the buyer can recover their own order.
    if (String(orderData.heroId || "") !== callerUid) {
      throw new HttpsError(
        "permission-denied",
        "No puedes verificar el pago de este pedido.",
      );
    }

    const orderStatus = normalizeStatus(orderData.status);
    const resolvedOrderId = orderRef.id;

    // Checked before the status gate: a refunded order must never be revived
    // (the money is already going back), and "refunded" is not a recoverable
    // status, so this cannot be reported as "already active".
    const refundStatus = normalizeStatus(orderData.refundStatus);
    if (orderStatus === "refunded" || REFUNDING_STATUSES.includes(refundStatus)) {
      return {
        recovered: false,
        status: "refunded",
        message:
          "Este pago fue devuelto. El reembolso llegara a tu medio de pago.",
      };
    }

    // Already fulfilled: nothing to recover, report it so the UI settles.
    if (!RECOVERABLE_STATUSES.has(orderStatus)) {
      return {
        recovered: false,
        status: "already_active",
        orderStatus: orderData.status || null,
        message: "Este pedido ya esta activo.",
      };
    }

    const approvedPayment = await findApprovedPayment(db, resolvedOrderId);
    if (!approvedPayment) {
      return {
        recovered: false,
        status: "not_paid",
        message: "No encontramos un pago aprobado para este pedido.",
      };
    }

    const paymentId = approvedPayment.id?.toString?.() ??
      String(approvedPayment.id);
    const reservationRef = db
      .collection("stockReservations")
      .doc(resolvedOrderId);

    const fulfillment = await resolveApprovedOrderFulfillment({
      db,
      orderId: resolvedOrderId,
      orderData,
      reservationRef,
      paymentId,
    });

    // Mirror the verified payment into Firestore either way, so support and
    // the webhook see the real state.
    const paymentPayload = {
      orderId: resolvedOrderId,
      paymentId,
      preferenceId: approvedPayment.preference_id ?
        String(approvedPayment.preference_id) :
        null,
      status: "approved",
      statusDetail: approvedPayment.status_detail ?? null,
      amount: approvedPayment.transaction_amount ?? null,
      currency: approvedPayment.currency_id ?? null,
      paymentMethod: approvedPayment.payment_type_id ?? null,
      paymentMethodId: approvedPayment.payment_method_id ?? null,
      approvedAt: timestamp(),
      recoveredBy: "recoverExpiredOrderPayment",
      recoveredAt: timestamp(),
      updatedAt: timestamp(),
    };
    if (!paymentPayload.preferenceId) delete paymentPayload.preferenceId;

    const paymentDocId = paymentPayload.preferenceId || paymentId;
    await db
      .collection("payments")
      .doc(paymentDocId)
      .set(paymentPayload, {merge: true});
    if (paymentDocId !== paymentId) {
      await db
        .collection("payments")
        .doc(paymentId)
        .set(paymentPayload, {merge: true});
    }

    // Stock could not be re-secured: keep the money and flag for support
    // instead of leaving a paid order silently cancelled.
    if (!fulfillment.canFulfill) {
      const blockedPayload = {
        status: "paid",
        paymentStatus: "approved",
        paymentId,
        fulfillmentStatus: "blocked",
        fulfillmentBlockReason: "approved_payment_without_stock_reservation",
        supportReviewStatus: "pending",
        recoveryAttemptedAt: timestamp(),
        recoveryStatus: fulfillment.recoveryStatus,
        recoveryReason: fulfillment.recoveryReason || null,
        cancelReason: admin.firestore.FieldValue.delete(),
        canceledBy: admin.firestore.FieldValue.delete(),
        "timestamps.canceledAt": admin.firestore.FieldValue.delete(),
        "timestamps.paidAt": timestamp(),
        updatedAt: timestamp(),
      };
      await orderRef.set(blockedPayload, {merge: true});
      await mirrorToUserOrders(db, resolvedOrderId, orderData, blockedPayload);

      logger.warn("[recover-payment] paid but not fulfillable", {
        orderId: resolvedOrderId,
        paymentId,
        recoveryStatus: fulfillment.recoveryStatus,
        recoveryReason: fulfillment.recoveryReason,
      });

      return {
        recovered: true,
        status: "needs_support",
        message:
          "Confirmamos tu pago, pero el producto ya no tiene stock. " +
          "Soporte revisara tu pedido.",
      };
    }

    const recoveredPayload = {
      status: "queued",
      paymentStatus: "approved",
      paymentId,
      fulfillmentStatus: admin.firestore.FieldValue.delete(),
      fulfillmentBlockReason: admin.firestore.FieldValue.delete(),
      cancelReason: admin.firestore.FieldValue.delete(),
      canceledBy: admin.firestore.FieldValue.delete(),
      paymentExpiredAt: admin.firestore.FieldValue.delete(),
      stockRestored: admin.firestore.FieldValue.delete(),
      stockRestoredAt: admin.firestore.FieldValue.delete(),
      "timestamps.canceledAt": admin.firestore.FieldValue.delete(),
      "timestamps.paidAt": timestamp(),
      "timestamps.queuedAt": timestamp(),
      recoveredAt: timestamp(),
      recoveredBy: "hero:verify_button",
      updatedAt: timestamp(),
    };

    await orderRef.set(recoveredPayload, {merge: true});
    await mirrorToUserOrders(db, resolvedOrderId, orderData, recoveredPayload);

    logger.info("[recover-payment] order recovered", {
      orderId: resolvedOrderId,
      paymentId,
      recoveryStatus: fulfillment.recoveryStatus,
    });

    return {
      recovered: true,
      status: "recovered",
      orderStatus: "queued",
      message: "Pago confirmado. Tu pedido ya esta en camino a un rider.",
    };
  },
);

module.exports.RECOVERABLE_STATUSES = RECOVERABLE_STATUSES;
module.exports._normalizeStatus = normalizeStatus;
