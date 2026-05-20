const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {MercadoPagoConfig, Preference} = require("mercadopago");

/**
 * Creates a MercadoPago payment preference for an order
 * @param {Object} request - Request object with data and auth
 * @return {Object} Preference with init_point URL
 */
exports.createPaymentPreference = onCall(
  {
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

  try {
    const accessToken = process.env.MERCADOPAGO_ACCESS_TOKEN;
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
        console.warn("MercadoPago users/me failed:", meRes.status, text);
      }
    } catch (meErr) {
      console.warn("MercadoPago users/me error:", meErr?.message ?? meErr);
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
      heroId,
      delivery,
      payerEmailOverride,
      isSandbox,
    } = request.data;

    orderIdForLogs = orderId ?? null;
    heroIdForLogs = heroId ?? null;

    if (!orderId || !items || !amountTotal) {
      throw new HttpsError(
          "invalid-argument",
          "Missing required order data",
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

    const reservationsRef = admin.firestore().collection("stockReservations").doc(orderId);
    const orderDocAtStart = await admin
      .firestore()
      .collection("orders")
      .doc(String(orderId))
      .get();
    const orderExistedAtStart = orderDocAtStart.exists;

    const reserveStock = async () => {
      const existing = await reservationsRef.get();
      if (existing.exists) {
        // Idempotent: if reservation already exists for this orderId, keep going.
        return false;
      }

      let createdInThisCall = false;
      await admin.firestore().runTransaction(async (transaction) => {
        const existingTx = await transaction.get(reservationsRef);
        if (existingTx.exists) return;

        if (!Array.isArray(items) || items.length === 0) {
          throw new HttpsError("invalid-argument", "Items are required to reserve stock");
        }

        // IMPORTANT: Firestore requires all reads to happen before all writes.
        // So we first read & validate everything, then apply updates.

        const normalizedItems = items.map((i) => {
          const offerId = i.offerId || i.id;
          const qty = Number(i.qty ?? i.quantity ?? 1);
          const qtyInt = Number.isFinite(qty) ? Math.max(1, Math.round(qty)) : 1;
          if (!offerId) {
            throw new HttpsError("invalid-argument", "Item missing offerId");
          }
          return {
            offerId: String(offerId),
            qty: qtyInt,
          };
        });

        const offerRefs = normalizedItems.map((it) =>
          admin.firestore().collection("offers").doc(it.offerId),
        );

        const offerDocs = await Promise.all(
          offerRefs.map((ref) => transaction.get(ref)),
        );

        const updates = [];

        for (let idx = 0; idx < normalizedItems.length; idx++) {
          const it = normalizedItems[idx];
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
          orderId,
          heroId,
          items: normalizedItems,
          status: "reserved",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          expiresAt: admin.firestore.Timestamp.fromDate(
            new Date(Date.now() + 30 * 60 * 1000),
          ),
        });
        createdInThisCall = true;
      });

      return createdInThisCall;
    };

    const reservationCreatedInThisCall = await reserveStock();
    shouldRollbackReservationOnFailure =
      reservationCreatedInThisCall && !orderExistedAtStart;

    const offerCategoryById = new Map();
    try {
      const unresolvedOfferIds = Array.from(
        new Set(
          (Array.isArray(items) ? items : [])
              .filter((item) => {
                const localCategory =
                  item?.category_id ??
                  item?.categoryId ??
                  item?.categorySnapshot ??
                  item?.category;
                return String(localCategory ?? "").trim().length === 0;
              })
              .map((item) => item?.offerId ?? item?.id ?? "")
              .map((rawId) => String(rawId).trim())
              .filter((offerId) => offerId.length > 0),
        ),
      );

      if (unresolvedOfferIds.length > 0) {
        const offerDocs = await Promise.all(
          unresolvedOfferIds.map((offerId) =>
            admin.firestore().collection("offers").doc(offerId).get(),
          ),
        );

        for (const offerDoc of offerDocs) {
          if (!offerDoc.exists) continue;
          const data = offerDoc.data() || {};
          const rawCategory =
            data.category ?? data.categoryId ?? data.category_id ?? "";
          const category = String(rawCategory).trim();
          if (!category) continue;
          offerCategoryById.set(offerDoc.id, category);
        }
      }
    } catch (categoryError) {
      console.warn(
        `Unable to enrich items with offer category_id for order ${orderId}:`,
        categoryError?.message ?? categoryError,
      );
    }

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

    // Prepare items for MercadoPago
    // NOTE: This project supports a donation model where product items may have unit_price = 0.
    // MercadoPago requires at least one payable item (> 0), so we skip zero-priced items and
    // rely on delivery/service/tax items to represent the payable amount.
    const skippedZeroPricedItems = [];
    const mpItems = [];

    for (const item of items) {
      const resolvedId = item.offerId || item.id;
      const resolvedTitle = item.titleSnapshot || item.title || "Producto";
      const resolvedUnitPrice = toInt(item.unitPriceSnapshot ?? item.price ?? 0);
      const categorySource =
        item.category_id ??
        item.categoryId ??
        item.categorySnapshot ??
        item.category ??
        offerCategoryById.get(String(resolvedId ?? "").trim());
      const resolvedCategoryId = resolveCategoryId(categorySource);

      if (resolvedUnitPrice <= 0) {
        skippedZeroPricedItems.push({id: resolvedId, title: resolvedTitle});
        continue;
      }

      mpItems.push({
        id: resolvedId,
        title: resolvedTitle,
        description: item.description || "",
        category_id: resolvedCategoryId,
        quantity: toQtyInt(item.qty ?? item.quantity ?? 1),
        unit_price: resolvedUnitPrice,
        currency_id: "CLP",
      });
    }

    // Add delivery fee as a separate item
    if (deliveryFee && deliveryFee > 0) {
      mpItems.push({
        id: "delivery_fee",
        category_id: "others",
        title: "Costo de envío",
        description: "Tarifa de entrega",
        quantity: 1,
        unit_price: toInt(deliveryFee),
        currency_id: "CLP",
      });
    }

    // Add service fee as a separate item
    if (serviceFee && serviceFee > 0) {
      mpItems.push({
        id: "service_fee",
        category_id: "others",
        title: "Tarifa de servicio",
        description: "Comisión de plataforma",
        quantity: 1,
        unit_price: toInt(serviceFee),
        currency_id: "CLP",
      });
    }

    // Add tax as a separate item
    if (tax && tax > 0) {
      mpItems.push({
        id: "tax",
        category_id: "others",
        title: "Impuestos",
        description: "IVA y otros impuestos",
        quantity: 1,
        unit_price: toInt(tax),
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
      `Creating preference for order ${orderId} (sandbox=${requestedSandbox}) with ${mpItems.length} payable items (skippedZeroPricedItems=${skippedZeroPricedItems.length}), total: ${amountTotal}, tokenPrefix=${tokenPrefix}`,
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
        success: `https://${process.env.GCLOUD_PROJECT}.web.app/payment/success?orderId=${orderId}`,
        failure: `https://${process.env.GCLOUD_PROJECT}.web.app/payment/failure?orderId=${orderId}`,
        pending: `https://${process.env.GCLOUD_PROJECT}.web.app/payment/pending?orderId=${orderId}`,
      },
      auto_return: "approved",
      notification_url: resolvedNotificationUrl,
      external_reference: orderId,
      statement_descriptor: "THE HERO",
      expires: true,
      expiration_date_from: new Date().toISOString(),
      expiration_date_to: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(), // 24 hours
    };

    // Create preference
    const result = await preference.create({body: preferenceData});

    console.log(`Payment preference created: ${result.id} for order ${orderId}`);

    try {
      const paymentsCollection = admin.firestore().collection("payments");
      const paymentRef = paymentsCollection.doc(String(result.id));
      await paymentRef.set(
        {
          orderId: String(orderId),
          preferenceId: String(result.id),
          status: "pending",
          amount: Number(amountTotal) || 0,
          currency: "CLP",
          heroId: String(heroId),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
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
      orderId: orderId,
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
      message: error?.message,
      name: error?.name,
      stack: error?.stack,
      status: error?.status,
      cause: error?.cause,
      error: error?.error,
      apiResponse: error?.api_response,
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
          message: error?.message ? String(error.message) : null,
          status: error?.status ?? null,
          cause: error?.cause ?? null,
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
        `Failed to create payment preference: ${error.message}`,
    );
  }
  },
);
