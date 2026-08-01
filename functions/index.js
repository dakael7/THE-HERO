const admin = require("firebase-admin");

admin.initializeApp();

function exportLazy(name, modulePath, exportName = name) {
  Object.defineProperty(exports, name, {
    enumerable: true,
    configurable: true,
    get() {
      const value = require(modulePath)[exportName];
      Object.defineProperty(exports, name, {
        value,
        enumerable: true,
        configurable: true,
      });
      return value;
    },
  });
}

exportLazy("createPaymentPreference", "./mercadopago/createPaymentPreference");
exportLazy("mercadopagoWebhook", "./mercadopago/webhook");
exportLazy("verifyPayment", "./mercadopago/verifyPayment");
exportLazy("simulatePaymentApproved", "./mercadopago/simulatePaymentApproved");
exportLazy("cancelExpiredPendingPayments", "./mercadopago/cancelExpiredPendingPayments");

exportLazy("onOrderPaidCreateInvoice", "./billing/onOrderPaidCreateInvoice");
exportLazy("retryInvoiceEmission", "./billing/onOrderPaidCreateInvoice");
exportLazy("wasabilInvoiceWebhook", "./billing/onOrderPaidCreateInvoice");
exportLazy("getInvoiceDownloadLink", "./billing/getInvoiceDownloadLink");
exportLazy("emitFiscalDocument", "./billing/emitFiscalDocument");
exportLazy("runSiiCertificationSet", "./billing/emitFiscalDocument");
exportLazy("generateFiscalBooksDraft", "./billing/generateFiscalBooks");

exportLazy("deleteMyAccount", "./accountDeletion");
exportLazy("adminUpdatePricing", "./adminSupport");
exportLazy("adminGetPricing", "./adminSupport");
exportLazy("adminCreateCupo", "./adminSupport");
exportLazy("adminListCupos", "./adminSupport");
exportLazy("adminUpdateCupo", "./adminSupport");
exportLazy("adminDeleteCupo", "./adminSupport");
exportLazy("adminSupportInboxOffers", "./adminSupport");
exportLazy("adminSupportInboxUsers", "./adminSupport");
exportLazy("adminSupportGetOffer", "./adminSupport");
exportLazy("adminSupportGetUser", "./adminSupport");
exportLazy("adminSupportListOfferReports", "./adminSupport");
exportLazy("adminSupportListUserReports", "./adminSupport");
exportLazy("adminSupportSetOfferReviewStatus", "./adminSupport");
exportLazy("adminSupportSetUserReviewStatus", "./adminSupport");
exportLazy("adminSupportModerateOffer", "./adminSupport");
exportLazy("adminSupportModerateUser", "./adminSupport");
exportLazy("adminSupportDeleteOffer", "./adminSupport");
exportLazy("adminPayoutRider", "./adminSupport");

const orders = require("./orders");
exports.createOrder = orders.createOrder;
exports.claimOrder = orders.claimOrder;
exports.updateOrderStatus = orders.updateOrderStatus;
exports.cancelOrder = orders.cancelOrder;

exportLazy("processImage1200Webp", "./imageProcessing");
exportLazy("processOrderRatings", "./orderRatings");

exportLazy("notifyNewChatMessage", "./notifications");
exportLazy("notifyPickupStopProgress", "./notifications");
exportLazy("notifyOrderStatusChange", "./notifications");
exportLazy("notifyNearbyRiders", "./notifications");
exportLazy("sendOperatorNotification", "./notifications");
exportLazy("sendBroadcastNotification", "./notifications");

exportLazy("syncRiderStatsOnOrderWrite", "./riderStats");

exportLazy("reviewVehicleVerificationRequest", "./riderVerification");
exportLazy("reviewRutVerificationRequest", "./riderVerification");
exportLazy("ocrVehicleVerificationLicenseOnUpload", "./riderVerification");
exportLazy("ocrLicenseVerificationOnUpload", "./riderVerification");
exportLazy("ocrRutVerificationOnUpload", "./riderVerification");
