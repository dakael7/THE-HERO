const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {MercadoPagoConfig, Preference} = require("mercadopago");
const {
  getMercadoPagoAccessToken,
  redactMercadoPagoSecrets,
} = require("./credentials");
const {assertHeroWeeklyOrderLimit} = require("../orderLimits");
const {couponDiscountFromData} = require("../orderPricing");

const PENDING_PAYMENT_TIMEOUT_MS = 5 * 60 * 1000;

/**
 * Creates a MercadoPago payment preference for an order
 * @param {Object} request - Request object with data and auth
 * @return {Object} Preference with init_point URL
 */
exports.createPaymentPreference = onCall(
  {
    memory: "512MiB",
    secrets: ["MERCADOPAGO_ACCESS_TOKEN"],
  },
  async (request) => {
  // Verify authentication
  if (!request.auth) {
    throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to create payment preference",
    );
  }

  let orderIdForLogs = null;
  let heroIdForLogs = null;
  let shouldRollbackReservationOnFailure = false;

  const timestampToMillis = (value) => {
    if (!value) return 0;
    if (typeof value.toMillis === "function") return value.toMillis();
    if (value instanceof Date) return value.getTime();
    const parsed = new Date(value).getTime();
    return Number.isFinite(parsed) ? parsed : 0;
  };

  const isExpiredReservation = (reservation) => {
    const expiresAtMs = timestampToMillis(reservation?.expiresAt);
    return expiresAtMs > 0 && expiresAtMs <= Date.now();
  };

  const releaseReservedStock = async (orderId, reason) => {
    if (!orderId) return;

    const reservationRef = admin
      .firestore()
      .collection("stockReservations")
      .doc(String(orderId));

    await admin.firestore().runTransaction(async (transaction) => {
      const reservationDoc = await transaction.get(reservationRef);
      if (!reservationDoc.exists) return;

      const reservation = reservationDoc.data() || {};
      if (reservation.status !== "reserved") return;

      const items = Array.isArray(reservation.items) ? reservation.items : [];
      const offerQtyDeltas = new Map();

      for (const item of items) {
        const offerId = item?.offerId;
        if (!offerId) continue;
        const qty = Number(item?.qty ?? 1);
        const qtyInt = Number.isFinite(qty) ? Math.max(1, Math.round(qty)) : 1;
        const key = String(offerId);
        offerQtyDeltas.set(key, (offerQtyDeltas.get(key) ?? 0) + qtyInt);
      }

      const offerDocs = new Map();
      for (const [offerId] of offerQtyDeltas) {
        const offerRef = admin.firestore().collection("offers").doc(offerId);
        const offerDoc = await transaction.get(offerRef);
        offerDocs.set(offerId, {ref: offerRef, doc: offerDoc});
      }

      for (const [offerId, delta] of offerQtyDeltas) {
        const entry = offerDocs.get(offerId);
        if (!entry?.doc?.exists) continue;

        const data = entry.doc.data() || {};
        const currentQty = Number(data.availableQty ?? 0);
        const newQty = currentQty + Number(delta ?? 0);

        const updateData = {
          stock: newQty,
          availableQty: newQty,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        if (data.status === "sold_out" && newQty > 0) {
          updateData.status = "active";
        }

        transaction.update(entry.ref, updateData);
      }

      transaction.update(reservationRef, {
        status: "released",
        releasedAt: admin.firestore.FieldValue.serverTimestamp(),
        releasedReason: reason || "preference_creation_failed",
      });
    });
  };

  const cancelPendingPaymentOrderIfExists = async (orderId, reason) => {
    if (!orderId) return;

    const orderRef = admin.firestore().collection("orders").doc(String(orderId));
    await admin.firestore().runTransaction(async (transaction) => {
      const orderDoc = await transaction.get(orderRef);
      if (!orderDoc.exists) return;

      const order = orderDoc.data() || {};
      const status = String(order.status || "").toLowerCase();
      const canCancel =
        status === "pending_payment" ||
        status === "pendingpayment" ||
        status === "created";

      if (!canCancel) return;

      transaction.update(orderRef, {
        status: "canceled",
        cancelReason: reason || "Pago no completado dentro de 5 minutos",
        canceledBy: "system:payment_expiration",
        paymentStatus: "expired",
        "timestamps.canceledAt": admin.firestore.FieldValue.serverTimestamp(),
        stockRestored: true,
        stockRestoredAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  };

  try {
    const accessToken = getMercadoPagoAccessToken();
    if (!accessToken) {
      throw new HttpsError(
          "failed-precondition",
          "MercadoPago credentials not configured",
      );
    }

    try {
      const meRes = await fetch("https://api.mercadopago.com/users/me", {
        method: "GET",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
      });

      if (meRes.ok) {
        const me = await meRes.json();
        console.log(
          "MercadoPago users/me:",
          JSON.stringify(
            {
              id: me?.id ?? null,
              nickname: me?.nickname ?? null,
              site_id: me?.site_id ?? null,
              email: me?.email ?? null,
            },
            null,
            2,
          ),
        );
      } else {
        const text = await meRes.text();
        console.warn(
          "MercadoPago users/me failed:",
          meRes.status,
          redactMercadoPagoSecrets(text),
        );
      }
    } catch (meErr) {
      console.warn(
        "MercadoPago users/me error:",
        redactMercadoPagoSecrets(meErr?.message ?? meErr),
      );
    }

    const tokenPrefix = typeof accessToken === "string" ? accessToken.split("-")[0] : "unknown";

    // Initialize MercadoPago client
    const client = new MercadoPagoConfig({
      accessToken: accessToken,
      options: {timeout: 5000},
    });

    const preference = new Preference(client);

    // Extract order data
    const {
      orderId,
      items,
      amountTotal,
      subtotal,
      deliveryFee,
      serviceFee,
      tax,
      tip,
      heroId,
      delivery,
      coupon,
    } = request.data || {};

    orderIdForLogs = orderId ?? null;
    heroIdForLogs = heroId ?? null;

    const toInt = (value) => {
      const n = Number(value);
      if (!Number.isFinite(n)) return 0;
      return Math.round(n);
    };

    const toQtyInt = (value) => {
      const n = Number(value);
      if (!Number.isFinite(n)) return 1;
      const q = Math.round(n);
      return q > 0 ? q : 1;
    };

    const resolveCategoryId = (value) => {
      const category = String(value ?? "").trim();
      return category.length > 0 ? category : "others";
    };

    const toOfferId = (value) => String(value ?? "").trim();

    const readCouponDiscount = async (discountBase) => {
      const source =
        orderDataAtStart?.coupon && typeof orderDataAtStart.coupon === "object" ?
          orderDataAtStart.coupon :
          coupon;
      const code = String(source?.code ?? "").trim().toUpperCase();
      if (!code) return {amount: 0, coupon: null};

      const couponDoc = await admin.firestore().collection("cupos").doc(code).get();
      if (!couponDoc.exists) {
        throw new HttpsError("not-found", "Cupo no encontrado");
      }

      return couponDiscountFromData(code, couponDoc.data() || {}, discountBase);
    };

    if (!orderId) {
      throw new HttpsError(
          "invalid-argument",
          "Missing required orderId",
      );
    }

    const orderIdStr = String(orderId).trim();
    if (!orderIdStr) {
      throw new HttpsError(
          "invalid-argument",
          "Invalid orderId",
      );
    }

    const requestUid = String(request.auth.uid ?? "").trim();
    const requestHeroId = String(heroId ?? "").trim();
    if (!requestHeroId || requestHeroId !== requestUid) {
      throw new HttpsError(
        "permission-denied",
        "heroId must match the authenticated user",
      );
    }

    const requestedSandbox = false;
    const isTestToken =
      typeof accessToken === "string" && accessToken.startsWith("TEST-");

    // Get user data for payer information
    const userDoc = await admin.firestore().collection("users").doc(heroId).get();
    const userData = userDoc.data();

    const reservationsRef = admin
      .firestore()
      .collection("stockReservations")
      .doc(orderIdStr);
    const orderDocAtStart = await admin
      .firestore()
      .collection("orders")
      .doc(orderIdStr)
      .get();
    const orderDataAtStart = orderDocAtStart.exists ? (orderDocAtStart.data() || {}) : {};
    const orderExistedAtStart = orderDocAtStart.exists;

    if (orderExistedAtStart) {
      const orderHeroId = String(orderDataAtStart.heroId ?? "").trim();
      if (orderHeroId && orderHeroId !== requestHeroId) {
        throw new HttpsError(
          "permission-denied",
          "Order does not belong to authenticated user",
        );
      }
    } else {
      await admin.firestore().runTransaction(async (transaction) => {
        await assertHeroWeeklyOrderLimit({
          transaction,
          heroId: requestHeroId,
          excludingOrderId: orderIdStr,
        });
      });
    }

    const buildNormalizedItems = (rawItems, sourceLabel) => {
      if (!Array.isArray(rawItems) || rawItems.length === 0) {
        throw new HttpsError(
          "invalid-argument",
          `Items are required in ${sourceLabel}`,
        );
      }

      return rawItems.map((rawItem) => {
        const offerId = toOfferId(rawItem?.offerId ?? rawItem?.id);
        if (!offerId) {
          throw new HttpsError("invalid-argument", "Item missing offerId");
        }

        return {
          offerId,
          qty: toQtyInt(rawItem?.qty ?? rawItem?.quantity ?? 1),
        };
      });
    };

    const requestItems = Array.isArray(items) ? items : [];
    const orderItemsFromDoc = Array.isArray(orderDataAtStart.items)
      ? orderDataAtStart.items
      : [];
    const rawItemsForReservation =
      orderItemsFromDoc.length > 0 ? orderItemsFromDoc : requestItems;

    const normalizedItemsForReservation = buildNormalizedItems(
      rawItemsForReservation,
      orderItemsFromDoc.length > 0 ? "order document" : "request",
    );

    const itemSnapshotByOfferId = new Map();
    const collectSnapshotMetadata = (rawItems) => {
      if (!Array.isArray(rawItems)) return;
      for (const rawItem of rawItems) {
        const offerId = toOfferId(rawItem?.offerId ?? rawItem?.id);
        if (!offerId) continue;

        const existing = itemSnapshotByOfferId.get(offerId) || {};
        const title = String(rawItem?.titleSnapshot ?? rawItem?.title ?? "").trim();
        const description = String(rawItem?.description ?? "").trim();
        const category = String(
          rawItem?.category_id ??
            rawItem?.categoryId ??
            rawItem?.categorySnapshot ??
            rawItem?.category ??
            "",
        ).trim();

        if (!existing.title && title) existing.title = title;
        if (!existing.description && description) existing.description = description;
        if (!existing.category && category) existing.category = category;

        itemSnapshotByOfferId.set(offerId, existing);
      }
    };

    collectSnapshotMetadata(orderItemsFromDoc);
    collectSnapshotMetadata(requestItems);

    let activeReservationExpiresAt = null;

    const reserveStock = async () => {
      const existing = await reservationsRef.get();
      if (existing.exists) {
        const existingReservation = existing.data() || {};
        if (
          existingReservation.status === "reserved" &&
          !isExpiredReservation(existingReservation)
        ) {
          const existingExpiresAtMs = timestampToMillis(existingReservation.expiresAt);
          activeReservationExpiresAt = existingExpiresAtMs > 0 ?
            new Date(existingExpiresAtMs) :
            new Date(Date.now() + PENDING_PAYMENT_TIMEOUT_MS);
          // Idempotent: if a live reservation already exists for this orderId, keep going.
          return false;
        }

        if (
          existingReservation.status === "reserved" &&
          isExpiredReservation(existingReservation)
        ) {
          await releaseReservedStock(
            orderIdStr,
            "pending_payment_expired_before_preference_retry",
          );
          await cancelPendingPaymentOrderIfExists(
            orderIdStr,
            "Pago no completado dentro de 5 minutos",
          );
        }

        throw new HttpsError(
          "deadline-exceeded",
          "La reserva de este pedido expiró. Crea una nueva solicitud para volver a pagar.",
        );
      }

      const reservationExpiresAt = new Date(
        Date.now() + PENDING_PAYMENT_TIMEOUT_MS,
      );
      activeReservationExpiresAt = reservationExpiresAt;

      if (orderExistedAtStart) {
        const currentStatus = String(orderDataAtStart.status || "").toLowerCase();
        const canCreatePreference =
          currentStatus === "pending_payment" ||
          currentStatus === "pendingpayment" ||
          currentStatus === "created";
        if (!canCreatePreference) {
          throw new HttpsError(
            "failed-precondition",
            "This order is not pending payment",
          );
        }
      }

      const existingOrderExpiresAtMs = timestampToMillis(
        orderDataAtStart.paymentExpiresAt,
      );
      if (orderExistedAtStart && existingOrderExpiresAtMs > 0) {
        const nowMs = Date.now();
        if (existingOrderExpiresAtMs <= nowMs) {
          await cancelPendingPaymentOrderIfExists(
            orderIdStr,
            "Pago no completado dentro de 5 minutos",
          );
          throw new HttpsError(
            "deadline-exceeded",
            "La reserva de este pedido expiró. Crea una nueva solicitud para volver a pagar.",
          );
        }
      }

      let createdInThisCall = false;
      await admin.firestore().runTransaction(async (transaction) => {
        const existingTx = await transaction.get(reservationsRef);
        if (existingTx.exists) return;

        // IMPORTANT: Firestore requires all reads to happen before all writes.
        // So we first read & validate everything, then apply updates.
        const qtyByOfferId = new Map();
        for (const item of normalizedItemsForReservation) {
          qtyByOfferId.set(
            item.offerId,
            (qtyByOfferId.get(item.offerId) ?? 0) + toQtyInt(item.qty),
          );
        }

        const aggregatedItems = Array.from(qtyByOfferId.entries()).map(
          ([offerId, qty]) => ({
            offerId,
            qty,
          }),
        );

        const offerRefs = aggregatedItems.map((it) =>
          admin.firestore().collection("offers").doc(it.offerId),
        );

        const offerDocs = await Promise.all(
          offerRefs.map((ref) => transaction.get(ref)),
        );

        const updates = [];

        for (let idx = 0; idx < aggregatedItems.length; idx++) {
          const it = aggregatedItems[idx];
          const offerRef = offerRefs[idx];
          const offerDoc = offerDocs[idx];

          if (!offerDoc.exists) {
            throw new HttpsError("not-found", `Offer not found: ${it.offerId}`);
          }

          const data = offerDoc.data() || {};
          const currentQty = Number(data.availableQty ?? 0);
          if (!Number.isFinite(currentQty)) {
            throw new HttpsError(
              "failed-precondition",
              `Invalid availableQty for offer: ${it.offerId}`,
            );
          }

          const newQty = currentQty - it.qty;
          if (newQty < 0) {
            throw new HttpsError(
              "failed-precondition",
              `Stock insuficiente para la oferta ${it.offerId}`,
            );
          }

          const updateData = {
            stock: newQty,
            availableQty: newQty,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          };

          if (newQty === 0) {
            updateData.status = "sold_out";
          }

          updates.push({offerRef, updateData});
        }

        // Writes after all reads
        for (const u of updates) {
          transaction.update(u.offerRef, u.updateData);
        }

        transaction.set(reservationsRef, {
          orderId: orderIdStr,
          heroId: requestHeroId,
          items: aggregatedItems,
          status: "reserved",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: admin.firestore.Timestamp.fromDate(reservationExpiresAt),
        });
        createdInThisCall = true;
      });

      return createdInThisCall;
    };

    const reservationCreatedInThisCall = await reserveStock();
    shouldRollbackReservationOnFailure =
      reservationCreatedInThisCall && !orderExistedAtStart;

    const reservationAfterStock = await reservationsRef.get();
    if (!activeReservationExpiresAt) {
      const expiresAtMs = timestampToMillis(reservationAfterStock.data()?.expiresAt);
      activeReservationExpiresAt = expiresAtMs > 0 ?
        new Date(expiresAtMs) :
        new Date(Date.now() + PENDING_PAYMENT_TIMEOUT_MS);
    }
    const reservationItems = Array.isArray(reservationAfterStock.data()?.items)
      ? reservationAfterStock.data().items
      : normalizedItemsForReservation;
    const reservedItemsForPricing = buildNormalizedItems(
      reservationItems,
      "stock reservation",
    );

    const offerDocsForPricing = await Promise.all(
      reservedItemsForPricing.map((item) =>
        admin.firestore().collection("offers").doc(item.offerId).get(),
      ),
    );

    const offerDocsById = new Map();
    for (let idx = 0; idx < reservedItemsForPricing.length; idx++) {
      offerDocsById.set(reservedItemsForPricing[idx].offerId, offerDocsForPricing[idx]);
    }

    const pricedItems = [];
    let serverSubtotal = 0;
    for (const reservedItem of reservedItemsForPricing) {
      const offerDoc = offerDocsById.get(reservedItem.offerId);
      if (!offerDoc?.exists) {
        throw new HttpsError("not-found", `Offer not found: ${reservedItem.offerId}`);
      }

      const offerData = offerDoc.data() || {};
      const unitPrice = toInt(offerData.price ?? 0);
      const qty = toQtyInt(reservedItem.qty);
      const snapshot = itemSnapshotByOfferId.get(reservedItem.offerId) || {};

      const title = String(snapshot.title ?? offerData.title ?? "Producto").trim() || "Producto";
      const description = String(snapshot.description ?? "").trim();
      const categoryId = resolveCategoryId(
        snapshot.category ??
          offerData.category ??
          offerData.categoryId ??
          offerData.category_id,
      );

      pricedItems.push({
        offerId: reservedItem.offerId,
        title,
        description,
        categoryId,
        qty,
        unitPrice,
      });

      serverSubtotal += unitPrice * qty;
    }

    const requestedSubtotal = toInt(subtotal);
    const requestedDeliveryFee = toInt(deliveryFee);
    const requestedServiceFee = toInt(serviceFee);
    const requestedTax = toInt(tax);
    const requestedTip = toInt(tip);
    const requestedAmountTotal = toInt(amountTotal);

    const serverDeliveryFee = toInt(
      orderDataAtStart.deliveryFee ?? requestedDeliveryFee,
    );
    const serverServiceFee = toInt(
      orderDataAtStart.serviceFee ?? requestedServiceFee,
    );
    const serverTax = toInt(orderDataAtStart.tax ?? requestedTax);
    const serverTip = toInt(orderDataAtStart.tip ?? requestedTip);
    const discountBase =
      serverSubtotal + serverDeliveryFee + serverServiceFee + serverTax;
    const serverCoupon = await readCouponDiscount(discountBase);
    const serverAmountTotal = toInt(
      discountBase - serverCoupon.amount + serverTip,
    );

    if (requestedAmountTotal > 0 && requestedAmountTotal !== serverAmountTotal) {
      console.warn(
        `Client amount mismatch for order ${orderIdStr}: client=${requestedAmountTotal}, server=${serverAmountTotal}`,
      );
    }

    if (
      requestedSubtotal > 0 &&
      Math.abs(requestedSubtotal - serverSubtotal) > 0
    ) {
      console.warn(
        `Client subtotal mismatch for order ${orderIdStr}: client=${requestedSubtotal}, server=${serverSubtotal}`,
      );
    }

    // Prepare items for MercadoPago
    // NOTE: This project supports a donation model where product items may have unit_price = 0.
    // MercadoPago requires at least one payable item (> 0), so we skip zero-priced items and
    // rely on delivery/service/tax/tip items to represent the payable amount.
    const skippedZeroPricedItems = [];
    const mpItems = [];
    let remainingDiscount = serverCoupon.amount;
    const applyCoupon = (amount) => {
      const discount = Math.min(amount, remainingDiscount);
      remainingDiscount -= discount;
      return amount - discount;
    };

    for (const pricedItem of pricedItems) {
      const itemTotal = Math.max(0, pricedItem.unitPrice * pricedItem.qty);
      const payableItemTotal = applyCoupon(itemTotal);
      if (payableItemTotal <= 0) {
        skippedZeroPricedItems.push({
          id: pricedItem.offerId,
          title: pricedItem.title,
        });
        continue;
      }

      mpItems.push({
        id: pricedItem.offerId,
        title: pricedItem.qty > 1 ?
          `${pricedItem.title} x${pricedItem.qty}` :
          pricedItem.title,
        description: pricedItem.description,
        category_id: pricedItem.categoryId,
        quantity: 1,
        unit_price: payableItemTotal,
        currency_id: "CLP",
      });
    }

    const payableDeliveryFee = applyCoupon(serverDeliveryFee);
    const payableServiceFee = applyCoupon(serverServiceFee);
    const payableTax = applyCoupon(serverTax);

    // Add delivery fee as a separate item
    if (payableDeliveryFee > 0) {
      mpItems.push({
        id: "delivery_fee",
        category_id: "others",
        title: "Costo de envio",
        description: "Tarifa de entrega",
        quantity: 1,
        unit_price: payableDeliveryFee,
        currency_id: "CLP",
      });
    }

    // Add service fee as a separate item
    if (payableServiceFee > 0) {
      mpItems.push({
        id: "service_fee",
        category_id: "others",
        title: "Tarifa de servicio",
        description: "Comision de plataforma",
        quantity: 1,
        unit_price: payableServiceFee,
        currency_id: "CLP",
      });
    }

    // Add tax as a separate item
    if (payableTax > 0) {
      mpItems.push({
        id: "tax",
        category_id: "others",
        title: "Impuestos",
        description: "IVA y otros impuestos",
        quantity: 1,
        unit_price: payableTax,
        currency_id: "CLP",
      });
    }

    // Add tip as a separate item
    if (serverTip > 0) {
      mpItems.push({
        id: "tip",
        category_id: "others",
        title: "Propina",
        description: "Propina del comprador",
        quantity: 1,
        unit_price: serverTip,
        currency_id: "CLP",
      });
    }

    if (mpItems.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "No payable items to charge in MercadoPago. All order items have unit_price=0 and no fees were added.",
      );
    }

    console.log(
      `Creating preference for order ${orderIdStr} (sandbox=${requestedSandbox}) with ${mpItems.length} payable items (skippedZeroPricedItems=${skippedZeroPricedItems.length}), total: ${serverAmountTotal}, tokenPrefix=${tokenPrefix}, isTestToken=${isTestToken}`,
    );

    const resolvedPayerEmail = (() => {
      return userData?.email || `${heroId}@thehero.app`;
    })();

    const normalizedPhone =
      userData?.phoneNumber?.toString().replace(/\D/g, "") || "000000000";

    const payerIdentification = undefined;

    const resolvedNotificationUrl =
      (process.env.MERCADOPAGO_NOTIFICATION_URL || "").toString().trim() ||
      `https://us-central1-${process.env.GCLOUD_PROJECT}.cloudfunctions.net/mercadopagoWebhook`;

    const preferenceExpiresAt = activeReservationExpiresAt;

    // Create preference body
    const preferenceData = {
      items: mpItems,
      payer: {
        name: userData?.fullName || delivery?.recipientName || "Cliente",
        email: resolvedPayerEmail,
        phone: {
          area_code: "56",
          number: normalizedPhone,
        },
        ...(payerIdentification ? {identification: payerIdentification} : {}),
      },
      back_urls: {
        success: `theheroprojects://payment/success?orderId=${orderIdStr}`,
        failure: `theheroprojects://payment/failure?orderId=${orderIdStr}`,
        pending: `theheroprojects://payment/pending?orderId=${orderIdStr}`,
      },
      auto_return: "approved",
      notification_url: resolvedNotificationUrl,
      external_reference: orderIdStr,
      statement_descriptor: "THE HERO",
      expires: true,
      expiration_date_from: new Date().toISOString(),
      expiration_date_to: preferenceExpiresAt.toISOString(),
    };

    // Create preference
    const result = await preference.create({body: preferenceData});

    console.log(`Payment preference created: ${result.id} for order ${orderIdStr}`);

    if (orderExistedAtStart) {
      await admin
        .firestore()
        .collection("orders")
        .doc(orderIdStr)
        .set(
          {
            paymentPreferenceId: String(result.id),
            paymentExpiresAt: admin.firestore.Timestamp.fromDate(preferenceExpiresAt),
            paymentStatus: "pending",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
        );
    }

    try {
      const paymentsCollection = admin.firestore().collection("payments");
      const paymentRef = paymentsCollection.doc(String(result.id));
      await paymentRef.set(
        {
          orderId: orderIdStr,
          preferenceId: String(result.id),
          status: "pending",
          amount: serverAmountTotal,
          currency: "CLP",
          heroId: String(heroId),
          ...(serverCoupon.coupon ? {coupon: serverCoupon.coupon} : {}),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: admin.firestore.Timestamp.fromDate(preferenceExpiresAt),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
    } catch (persistPaymentErr) {
      console.warn(
        `Failed to persist initial payment doc for preference ${result.id}:`,
        persistPaymentErr?.message ?? persistPaymentErr,
      );
    }

    return {
      preferenceId: result.id,
      initPoint: result.init_point,
      sandboxInitPoint: result.init_point,
      orderId: orderIdStr,
      createdAt: new Date().toISOString(),
      expiresAt: preferenceData.expiration_date_to,
    };
  } catch (error) {
    if (shouldRollbackReservationOnFailure && orderIdForLogs) {
      try {
        await releaseReservedStock(
          orderIdForLogs,
          "preference_creation_failed_before_order_creation",
        );
        console.warn(
          `Stock reservation released after preference failure for order ${orderIdForLogs}`,
        );
      } catch (rollbackError) {
        console.error(
          `Failed to release reserved stock for order ${orderIdForLogs}:`,
          rollbackError?.message ?? rollbackError,
        );
      }
    }

    const errorDetails = {
      message: redactMercadoPagoSecrets(error?.message),
      name: error?.name,
      stack: redactMercadoPagoSecrets(error?.stack),
      status: error?.status,
      cause: redactMercadoPagoSecrets(error?.cause),
      error: redactMercadoPagoSecrets(error?.error),
      apiResponse: redactMercadoPagoSecrets(error?.api_response),
    };

    console.error(
      "Error creating payment preference:",
      JSON.stringify(
        {
          orderId: orderIdForLogs,
          heroId: heroIdForLogs,
          errorDetails,
        },
        null,
        2,
      ),
    );

    try {
      await admin
        .firestore()
        .collection("paymentPreferenceErrors")
        .add({
          orderId: orderIdForLogs,
          heroId: heroIdForLogs,
          message: error?.message ?
            redactMercadoPagoSecrets(String(error.message)) :
            null,
          status: error?.status ?? null,
          cause: redactMercadoPagoSecrets(error?.cause ?? null),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (persistError) {
      console.error(
        "Failed to persist payment preference error:",
        persistError?.message ?? persistError,
      );
    }

    if (error instanceof HttpsError) {
      throw error;
    }

    throw new HttpsError(
        "internal",
        "Failed to create payment preference",
    );
  }
  },
);
