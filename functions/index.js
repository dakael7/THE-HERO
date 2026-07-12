const admin = require("firebase-admin");

admin.initializeApp();

const {
  createPaymentPreference,
} = require("./mercadopago/createPaymentPreference");
const { mercadopagoWebhook } = require("./mercadopago/webhook");
const { verifyPayment } = require("./mercadopago/verifyPayment");
const {
  simulatePaymentApproved,
} = require("./mercadopago/simulatePaymentApproved");
const {
  cancelExpiredPendingPayments,
} = require("./mercadopago/cancelExpiredPendingPayments");
const {
  onOrderPaidCreateInvoice,
  retryInvoiceEmission,
  wasabilInvoiceWebhook,
} = require("./billing/onOrderPaidCreateInvoice");
const {
  getInvoiceDownloadLink,
} = require("./billing/getInvoiceDownloadLink");
const {
  emitFiscalDocument,
  runSiiCertificationSet,
} = require("./billing/emitFiscalDocument");
const {
  generateFiscalBooksDraft,
} = require("./billing/generateFiscalBooks");

exports.createPaymentPreference = createPaymentPreference;
exports.mercadopagoWebhook = mercadopagoWebhook;
exports.verifyPayment = verifyPayment;
exports.simulatePaymentApproved = simulatePaymentApproved;
exports.cancelExpiredPendingPayments = cancelExpiredPendingPayments;
exports.onOrderPaidCreateInvoice = onOrderPaidCreateInvoice;
exports.retryInvoiceEmission = retryInvoiceEmission;
exports.wasabilInvoiceWebhook = wasabilInvoiceWebhook;
exports.getInvoiceDownloadLink = getInvoiceDownloadLink;
exports.emitFiscalDocument = emitFiscalDocument;
exports.runSiiCertificationSet = runSiiCertificationSet;
exports.generateFiscalBooksDraft = generateFiscalBooksDraft;

Object.assign(exports, require("./accountDeletion"));
Object.assign(exports, require("./adminSupport"));
Object.assign(exports, require("./orders"));
Object.assign(exports, require("./imageProcessing"));
Object.assign(exports, require("./orderRatings"));
Object.assign(exports, require("./notifications"));
Object.assign(exports, require("./riderStats"));
Object.assign(exports, require("./riderVerification"));
