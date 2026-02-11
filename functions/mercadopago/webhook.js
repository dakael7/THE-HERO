const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {MercadoPagoConfig, Payment} = require("mercadopago");

/**
 * Webhook handler for MercadoPago payment notifications
 * Updates payment and order status based on payment events
 */
exports.mercadopagoWebhook = onRequest(
  {
    secrets: ["MERCADOPAGO_ACCESS_TOKEN"],
  },
  async (req, res) => {
    try {
      const {type, data} = req.body;

      console.log("MercadoPago webhook received:", {type, data});

      // We're only interested in payment notifications
      if (type !== "payment") {
        res.status(200).send("OK - Not a payment notification");
        return;
      }

      const paymentId = data.id;
      if (!paymentId) {
        res.status(400).send("Missing payment ID");
        return;
      }

      // Get MercadoPago Access Token
      const accessToken = process.env.MERCADOPAGO_ACCESS_TOKEN;
      if (!accessToken) {
        console.error("MercadoPago credentials not configured");
        res.status(500).send("Server configuration error");
        return;
      }

      // Initialize MercadoPago client
      const client = new MercadoPagoConfig({
        accessToken: accessToken,
        options: {timeout: 5000},
      });

      const payment = new Payment(client);

      // Get payment details from MercadoPago
      const paymentData = await payment.get({id: paymentId});

      console.log("Payment data from MercadoPago:", {
        id: paymentData.id,
        status: paymentData.status,
        status_detail: paymentData.status_detail,
        external_reference: paymentData.external_reference,
      });

      const orderId = paymentData.external_reference;
      if (!orderId) {
        console.error("No external_reference (orderId) in payment");
        res.status(400).send("Missing order reference");
        return;
      }

      // Update payment document in Firestore
      const paymentRef = admin
        .firestore()
        .collection("payments")
        .doc(paymentData.id.toString());

      const paymentUpdate = {
        paymentId: paymentData.id.toString(),
        status: paymentData.status,
        statusDetail: paymentData.status_detail,
        paymentMethod: paymentData.payment_type_id,
        paymentMethodId: paymentData.payment_method_id,
        amount: paymentData.transaction_amount,
        currency: paymentData.currency_id,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          transactionAmount: paymentData.transaction_amount,
          netAmount: paymentData.transaction_details?.net_received_amount,
          installments: paymentData.installments,
          cardLastFourDigits: paymentData.card?.last_four_digits,
        },
      };

      // If approved, add approval timestamp
      if (paymentData.status === "approved") {
        paymentUpdate.approvedAt = admin.firestore.FieldValue.serverTimestamp();
      }

      await paymentRef.set(paymentUpdate, {merge: true});

      // Update order status based on payment status
      const orderRef = admin.firestore().collection("orders").doc(orderId);
      const orderDoc = await orderRef.get();

      if (!orderDoc.exists) {
        console.error(`Order ${orderId} not found`);
        res.status(404).send("Order not found");
        return;
      }

      let newOrderStatus = null;

      switch (paymentData.status) {
      case "approved":
        newOrderStatus = "queued"; // Order is ready for riders
        break;
      case "rejected":
      case "cancelled":
        newOrderStatus = "payment_failed";
        break;
      case "pending":
      case "in_process":
      case "in_mediation":
        newOrderStatus = "pending_payment";
        break;
      case "refunded":
      case "charged_back":
        newOrderStatus = "refunded";
        break;
      }

      if (newOrderStatus) {
        await orderRef.update({
          status: newOrderStatus,
          paymentId: paymentData.id.toString(),
          paymentStatus: paymentData.status,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`Order ${orderId} status updated to ${newOrderStatus}`);
      }

      res.status(200).send("OK");
    } catch (error) {
      console.error("Error processing webhook:", error);
      res.status(500).send("Internal Server Error");
    }
  },
);
