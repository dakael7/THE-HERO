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

  try {
    // Get MercadoPago Access Token from environment
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

    const requestedSandbox = Boolean(isSandbox);
    const isTestToken =
      typeof accessToken === "string" && accessToken.startsWith("TEST-");

    // Get user data for payer information
    const userDoc = await admin.firestore().collection("users").doc(heroId).get();
    const userData = userDoc.data();

    const reservationsRef = admin.firestore().collection("stockReservations").doc(orderId);

    const reserveStock = async () => {
      const existing = await reservationsRef.get();
      if (existing.exists) {
        // Idempotent: if reservation already exists for this orderId, keep going.
        return;
      }

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
      });
    };

    await reserveStock();

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

      if (resolvedUnitPrice <= 0) {
        skippedZeroPricedItems.push({id: resolvedId, title: resolvedTitle});
        continue;
      }

      mpItems.push({
        id: resolvedId,
        title: resolvedTitle,
        description: item.description || "",
        quantity: toQtyInt(item.qty ?? item.quantity ?? 1),
        unit_price: resolvedUnitPrice,
        currency_id: "CLP",
      });
    }

    // Add delivery fee as a separate item
    if (deliveryFee && deliveryFee > 0) {
      mpItems.push({
        id: "delivery_fee",
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
      if (
        requestedSandbox &&
        typeof payerEmailOverride === "string" &&
        payerEmailOverride.trim().includes("@")
      ) {
        return payerEmailOverride.trim();
      }
      return userData?.email || `${heroId}@thehero.app`;
    })();

    const normalizedPhone =
      userData?.phoneNumber?.toString().replace(/\D/g, "") || "000000000";

    const payerIdentification = requestedSandbox
      ? {
          type: "RUT",
          number: "11111111-1",
        }
      : undefined;

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

    return {
      preferenceId: result.id,
      initPoint: result.init_point,
      sandboxInitPoint: result.sandbox_init_point,
      orderId: orderId,
      createdAt: new Date().toISOString(),
      expiresAt: preferenceData.expiration_date_to,
    };
  } catch (error) {
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

    throw new HttpsError(
        "internal",
        `Failed to create payment preference: ${error.message}`,
    );
  }
  },
);
