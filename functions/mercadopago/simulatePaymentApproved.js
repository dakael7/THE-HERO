const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {
  resolveApprovedOrderFulfillment,
} = require("./orderFulfillment");

exports.simulatePaymentApproved = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "User must be authenticated to simulate payment",
    );
  }

  console.log("simulatePaymentApproved called", {
    uid: request.auth.uid,
    env: {
      MERCADOPAGO_ENV: process.env.MERCADOPAGO_ENV ?? null,
      MERCADOPAGO_SIMULATOR_ENABLED: process.env.MERCADOPAGO_SIMULATOR_ENABLED ?? null,
    },
    dataKeys: Object.keys(request.data || {}),
  });

  if (String(process.env.MERCADOPAGO_SIMULATOR_ENABLED || "").toLowerCase() !== "true") {
    throw new HttpsError(
      "failed-precondition",
      "Payment simulator disabled. Set MERCADOPAGO_SIMULATOR_ENABLED=true to enable.",
    );
  }

  if (String(process.env.MERCADOPAGO_ENV || "").toLowerCase() !== "sandbox") {
    throw new HttpsError(
      "failed-precondition",
      "Payment simulator is sandbox-only. Set MERCADOPAGO_ENV=sandbox to enable.",
    );
  }

  // Sandbox-only: for testing we allow any authenticated caller.

  const {orderId, preferenceId, amount, paymentMethod} = request.data || {};

  console.log("simulatePaymentApproved input", {
    orderId: orderId ?? null,
    preferenceId: preferenceId ?? null,
    amount: typeof amount === "number" ? amount : null,
    paymentMethod: paymentMethod ?? null,
  });

  if (!orderId || !preferenceId) {
    throw new HttpsError(
      "invalid-argument",
      "orderId and preferenceId are required",
    );
  }

  const nowIso = new Date().toISOString();
  const simulatedPaymentId = `sandbox-sim-${Date.now()}`;

  const paymentUpdate = {
    paymentId: simulatedPaymentId,
    preferenceId: String(preferenceId),
    orderId: String(orderId),
    status: "approved",
    statusDetail: "sandbox_simulated",
    paymentMethod: paymentMethod || "sandbox",
    paymentMethodId: paymentMethod || "sandbox",
    amount: typeof amount === "number" ? amount : null,
    currency: "CLP",
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    approvedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    metadata: {
      simulated: true,
      simulatedAt: nowIso,
      callerUid: request.auth.uid,
      callerEmail: request.auth.token?.email ?? null,
    },
  };

  const paymentsCollection = admin.firestore().collection("payments");
  const ordersCollection = admin.firestore().collection("orders");
  const db = admin.firestore();

  const paymentRef = paymentsCollection.doc(String(preferenceId));
  const paymentByIdRef = paymentsCollection.doc(String(simulatedPaymentId));
  const rawOrderId = String(orderId);
  const orderRef = ordersCollection.doc(rawOrderId);
  const prefixedOrderId = rawOrderId.startsWith("HRO-")
    ? rawOrderId
    : `HRO-${rawOrderId}`;
  const unprefixedOrderId = rawOrderId.startsWith("HRO-")
    ? rawOrderId.substring(4)
    : rawOrderId;
  const orderPrefixedRef = ordersCollection.doc(prefixedOrderId);

  const reservationRef = admin
    .firestore()
    .collection("stockReservations")
    .doc(String(orderId));

  try {
    let resolvedOrderRef = orderRef;
    let resolvedOrderData = {};
    let foundOrder = false;
    const candidateOrderIds = [rawOrderId, prefixedOrderId, unprefixedOrderId]
      .filter(Boolean)
      .filter((value, index, values) => values.indexOf(value) === index);

    for (const candidateId of candidateOrderIds) {
      const candidateDoc = await ordersCollection.doc(candidateId).get();
      if (candidateDoc.exists) {
        resolvedOrderRef = candidateDoc.ref;
        resolvedOrderData = candidateDoc.data() || {};
        foundOrder = true;
        break;
      }
    }

    const fulfillmentResult = await resolveApprovedOrderFulfillment({
      db,
      orderId: rawOrderId,
      orderData: resolvedOrderData,
      reservationRef,
      paymentId: simulatedPaymentId,
    });
    const currentFulfillmentBlockReason = String(
      resolvedOrderData.fulfillmentBlockReason || "",
    ).trim().toLowerCase();
    const shouldClearStockReservationBlock =
      currentFulfillmentBlockReason ===
      "approved_payment_without_stock_reservation";

    await admin.firestore().runTransaction(async (tx) => {
      const effectivePaymentUpdate = fulfillmentResult.canFulfill
        ? paymentUpdate
        : {
          ...paymentUpdate,
          status: "refunded",
          refundStatus: "sandbox_simulated",
          refundReason: "approved_payment_without_stock_reservation",
          refundedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

      tx.set(paymentRef, effectivePaymentUpdate, {merge: true});
      tx.set(paymentByIdRef, effectivePaymentUpdate, {merge: true});

      const orderUpdate = {
        status: fulfillmentResult.canFulfill ? "queued" : "refunded",
        paymentId: simulatedPaymentId,
        paymentStatus: fulfillmentResult.canFulfill ? "approved" : "refunded",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        paymentSimulated: true,
        paymentPreferenceId: String(preferenceId),
      };

      if (fulfillmentResult.canFulfill) {
        orderUpdate["timestamps.queuedAt"] =
          admin.firestore.FieldValue.serverTimestamp();
        if (shouldClearStockReservationBlock) {
          orderUpdate.fulfillmentStatus = admin.firestore.FieldValue.delete();
          orderUpdate.fulfillmentBlockReason =
            admin.firestore.FieldValue.delete();
          orderUpdate.supportReviewStatus =
            admin.firestore.FieldValue.delete();
        }
      } else {
        orderUpdate.refundStatus = "sandbox_simulated";
        orderUpdate.refundReason =
          "approved_payment_without_stock_reservation";
        orderUpdate.cancelReason =
          "Pago devuelto automaticamente: no pudimos confirmar stock para este pedido.";
        orderUpdate.canceledBy = "system:auto_refund";
        orderUpdate["timestamps.refundedAt"] =
          admin.firestore.FieldValue.serverTimestamp();
        orderUpdate.fulfillmentStatus = admin.firestore.FieldValue.delete();
        orderUpdate.fulfillmentBlockReason =
          admin.firestore.FieldValue.delete();
        orderUpdate.supportReviewStatus =
          admin.firestore.FieldValue.delete();
      }

      tx.set(resolvedOrderRef, orderUpdate, {merge: true});

      if (!foundOrder && resolvedOrderRef.id !== orderPrefixedRef.id) {
        tx.set(orderPrefixedRef, orderUpdate, {merge: true});
      }

      tx.set(
        admin
          .firestore()
          .collection("mercadopagoSandboxSimulations")
          .doc(simulatedPaymentId),
        {
          simulatedPaymentId,
          orderId: String(orderId),
          preferenceId: String(preferenceId),
          amount: typeof amount === "number" ? amount : null,
          callerUid: request.auth.uid,
          callerEmail: request.auth.token?.email ?? null,
          fulfillment: fulfillmentResult,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    });

    console.log("simulatePaymentApproved success", {
      orderId: String(orderId),
      orderDocIdsWritten: [orderRef.id, orderPrefixedRef.id],
      preferenceId: String(preferenceId),
      simulatedPaymentId,
    });
  } catch (e) {
    console.error("simulatePaymentApproved failed", {
      orderId: String(orderId),
      preferenceId: String(preferenceId),
      error: e?.message ?? e,
    });
    throw new HttpsError("internal", `Simulation failed: ${e?.message ?? e}`);
  }

  return {
    ok: true,
    orderId: String(orderId),
    preferenceId: String(preferenceId),
    paymentId: simulatedPaymentId,
    status: "approved",
  };
});
