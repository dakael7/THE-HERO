const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

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

  const paymentRef = paymentsCollection.doc(String(preferenceId));
  const paymentByIdRef = paymentsCollection.doc(String(simulatedPaymentId));
  const rawOrderId = String(orderId);
  const orderRef = ordersCollection.doc(rawOrderId);
  const prefixedOrderId = rawOrderId.startsWith("HRO-")
    ? rawOrderId
    : `HRO-${rawOrderId}`;
  const orderPrefixedRef = ordersCollection.doc(prefixedOrderId);

  const reservationRef = admin
    .firestore()
    .collection("stockReservations")
    .doc(String(orderId));

  try {
    await admin.firestore().runTransaction(async (tx) => {
      const reservationDoc = await tx.get(reservationRef);

      tx.set(paymentRef, paymentUpdate, {merge: true});
      tx.set(paymentByIdRef, paymentUpdate, {merge: true});

      const orderUpdate = {
        status: "queued",
        paymentId: simulatedPaymentId,
        paymentStatus: "approved",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        paymentSimulated: true,
        paymentPreferenceId: String(preferenceId),
      };

      tx.set(orderRef, orderUpdate, {merge: true});

      if (orderPrefixedRef.id !== orderRef.id) {
        tx.set(orderPrefixedRef, orderUpdate, {merge: true});
      }

      if (reservationDoc.exists) {
        const reservation = reservationDoc.data() || {};
        if (reservation.status === "reserved") {
          tx.update(reservationRef, {
            status: "consumed",
            consumedAt: admin.firestore.FieldValue.serverTimestamp(),
            paymentId: simulatedPaymentId,
            paymentStatusSnapshot: "approved",
          });
        }
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
