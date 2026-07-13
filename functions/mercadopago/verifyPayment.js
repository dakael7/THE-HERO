const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {MercadoPagoConfig, Payment} = require("mercadopago");
const {
  getMercadoPagoAccessToken,
  redactMercadoPagoSecrets,
} = require("./credentials");

/**
 * Verifies payment status with MercadoPago API
 * @param {Object} request - Request object with data and auth
 * @return {Object} Payment details
 */
exports.verifyPayment = onCall(
  {
    memory: "512MiB",
    secrets: ["MERCADOPAGO_ACCESS_TOKEN"],
  },
  async (request) => {
  // Verify authentication
  if (!request.auth) {
    throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to verify payment",
    );
  }

  try {
    const {paymentId} = request.data;

    if (!paymentId) {
      throw new HttpsError(
          "invalid-argument",
          "Payment ID is required",
      );
    }

    // Get MercadoPago Access Token
    const accessToken = getMercadoPagoAccessToken();
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

    const payment = new Payment(client);

    // Get payment details
    const paymentData = await payment.get({id: paymentId});

    console.log(`Payment ${paymentId} verified:`, paymentData.status);

    return {
      id: paymentData.id.toString(),
      orderId: paymentData.external_reference,
      preferenceId: paymentData.preference_id,
      paymentId: paymentData.id.toString(),
      status: paymentData.status,
      statusDetail: paymentData.status_detail,
      amount: paymentData.transaction_amount,
      currency: paymentData.currency_id,
      paymentMethod: paymentData.payment_type_id,
      paymentMethodId: paymentData.payment_method_id,
      createdAt: paymentData.date_created,
      approvedAt: paymentData.date_approved,
      updatedAt: paymentData.date_last_updated,
      metadata: {
        transactionAmount: paymentData.transaction_amount,
        netAmount: paymentData.transaction_details?.net_received_amount,
        installments: paymentData.installments,
        cardLastFourDigits: paymentData.card?.last_four_digits,
      },
    };
  } catch (error) {
    console.error("Error verifying payment:", redactMercadoPagoSecrets(error));
    throw new HttpsError(
        "internal",
        "Failed to verify payment",
    );
  }
  },
);
