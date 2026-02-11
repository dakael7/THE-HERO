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

  try {
    // Get MercadoPago Access Token from environment
    const accessToken = process.env.MERCADOPAGO_ACCESS_TOKEN;
    if (!accessToken) {
      throw new HttpsError(
          "failed-precondition",
          "MercadoPago credentials not configured",
      );
    }

    // Initialize MercadoPago client
    const client = new MercadoPagoConfig({
      accessToken: accessToken,
      options: {timeout: 5000},
    });

    const preference = new Preference(client);

    // Extract order data
    const {orderId, items, amountTotal, subtotal, deliveryFee, serviceFee, tax, heroId, delivery} = request.data;

    if (!orderId || !items || !amountTotal) {
      throw new HttpsError(
          "invalid-argument",
          "Missing required order data",
      );
    }

    // Get user data for payer information
    const userDoc = await admin.firestore().collection("users").doc(heroId).get();
    const userData = userDoc.data();

    // Prepare items for MercadoPago
    const mpItems = items.map((item) => ({
      id: item.offerId || item.id,
      title: item.titleSnapshot || item.title || "Producto",
      description: item.description || "",
      quantity: item.qty || item.quantity || 1,
      unit_price: item.unitPriceSnapshot || item.price || 0,
      currency_id: "CLP",
    }));

    // Add delivery fee as a separate item
    if (deliveryFee && deliveryFee > 0) {
      mpItems.push({
        id: "delivery_fee",
        title: "Costo de envío",
        description: "Tarifa de entrega",
        quantity: 1,
        unit_price: deliveryFee,
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
        unit_price: serviceFee,
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
        unit_price: tax,
        currency_id: "CLP",
      });
    }

    console.log(`Creating preference with ${mpItems.length} items, total: ${amountTotal}`);

    // Create preference body
    const preferenceData = {
      items: mpItems,
      payer: {
        name: userData?.fullName || delivery?.recipientName || "Cliente",
        email: userData?.email || `${heroId}@thehero.app`,
        phone: {
          area_code: "56",
          number: userData?.phoneNumber?.replace(/\D/g, "") || "000000000",
        },
      },
      back_urls: {
        success: `https://${process.env.GCLOUD_PROJECT}.web.app/payment/success?orderId=${orderId}`,
        failure: `https://${process.env.GCLOUD_PROJECT}.web.app/payment/failure?orderId=${orderId}`,
        pending: `https://${process.env.GCLOUD_PROJECT}.web.app/payment/pending?orderId=${orderId}`,
      },
      auto_return: "approved",
      notification_url: `https://us-central1-${process.env.GCLOUD_PROJECT}.cloudfunctions.net/mercadopagoWebhook`,
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
    console.error("Error creating payment preference:", error);
    throw new HttpsError(
        "internal",
        `Failed to create payment preference: ${error.message}`,
    );
  }
  },
);
