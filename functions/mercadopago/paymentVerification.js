const logger = require("firebase-functions/logger");
const {MercadoPagoConfig, Payment} = require("mercadopago");
const {
  getMercadoPagoAccessToken,
  redactMercadoPagoSecrets,
} = require("./credentials");

const normalizeStatus = (value) => {
  return String(value || "").trim().toLowerCase().replace(/[_-]/g, "");
};

/**
 * Asks MercadoPago whether an order has an approved payment.
 *
 * Firestore is not trustworthy for this question: a delayed webhook leaves the
 * payment doc "pending" while the money is already captured, which is how paid
 * orders ended up canceled. Callers must treat `null` as "unknown" and refuse
 * to cancel, rather than assuming "not paid".
 *
 * @param {Object} db Firestore instance, used for the payment-id fallback.
 * @param {string} orderId Order id, sent to MercadoPago as external_reference.
 * @param {string} logPrefix Log tag identifying the caller.
 * @return {Promise<boolean|null>} true if approved, false if confirmed not
 *   approved, null if MercadoPago could not be reached.
 */
const hasApprovedPaymentAtMercadoPago = async (db, orderId, logPrefix) => {
  const tag = logPrefix || "payment-verification";
  const accessToken = getMercadoPagoAccessToken();
  if (!accessToken) {
    logger.warn(`[${tag}] missing MercadoPago credentials`);
    return null;
  }

  const client = new MercadoPagoConfig({
    accessToken,
    options: {timeout: 8000},
  });
  const payment = new Payment(client);

  try {
    const search = await payment.search({
      options: {external_reference: String(orderId), limit: 50},
    });
    const results = Array.isArray(search?.results) ? search.results : [];
    if (results.some((item) => normalizeStatus(item?.status) === "approved")) {
      return true;
    }
    if (results.length > 0) return false;
  } catch (error) {
    logger.warn(`[${tag}] MercadoPago search failed`, {
      orderId,
      error: redactMercadoPagoSecrets(error?.message ?? error),
    });
    return null;
  }

  // No results for the external_reference: re-check known payment ids.
  try {
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
      const data = await payment.get({id: paymentId});
      if (normalizeStatus(data?.status) === "approved") return true;
    }
  } catch (error) {
    logger.warn(`[${tag}] MercadoPago lookup failed`, {
      orderId,
      error: redactMercadoPagoSecrets(error?.message ?? error),
    });
    return null;
  }

  return false;
};

module.exports = {
  hasApprovedPaymentAtMercadoPago,
  _normalizeStatus: normalizeStatus,
};
