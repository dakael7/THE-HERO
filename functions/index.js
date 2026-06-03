const {
  onCall,
  onRequest,
  HttpsError,
} = require("firebase-functions/v2/https");
const { onObjectFinalized } = require("firebase-functions/v2/storage");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const sharp = require("sharp");
const path = require("path");
const os = require("os");
const fs = require("fs");
const vision = require("@google-cloud/vision");
admin.initializeApp();

// MercadoPago Functions
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

// Export MercadoPago functions
exports.createPaymentPreference = createPaymentPreference;
exports.mercadopagoWebhook = mercadopagoWebhook;
exports.verifyPayment = verifyPayment;
exports.simulatePaymentApproved = simulatePaymentApproved;
exports.cancelExpiredPendingPayments = cancelExpiredPendingPayments;
exports.onOrderPaidCreateInvoice = onOrderPaidCreateInvoice;
exports.retryInvoiceEmission = retryInvoiceEmission;
exports.getInvoiceDownloadLink = getInvoiceDownloadLink;
exports.emitFiscalDocument = emitFiscalDocument;
exports.runSiiCertificationSet = runSiiCertificationSet;
exports.generateFiscalBooksDraft = generateFiscalBooksDraft;

const STORAGE_REGION = "southamerica-west1";

const visionClient = new vision.ImageAnnotatorClient();

function isSupportUser(auth) {
  const allowlistRaw = process.env.SUPPORT_EMAIL_ALLOWLIST || "";
  const allowlist = allowlistRaw
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);

  const email = auth?.token?.email
    ? String(auth.token.email).toLowerCase()
    : null;
  if (email && allowlist.includes(email)) return true;

  if (auth?.token?.support === true) return true;
  if (auth?.token?.admin === true) return true;

  return false;
}

function _getBearerToken(req) {
  const authHeader = req.get("authorization") || req.get("Authorization") || "";
  const prefix = "bearer ";
  const raw = String(authHeader || "");
  if (!raw.toLowerCase().startsWith(prefix)) return null;
  const token = raw.slice(prefix.length).trim();
  return token || null;
}

async function _requireWebAdmin(req) {
  const idToken = _getBearerToken(req);
  if (!idToken) {
    return {
      ok: false,
      status: 401,
      message: "Missing Authorization Bearer token",
    };
  }

  let decoded;
  try {
    decoded = await admin.auth().verifyIdToken(idToken);
  } catch (e) {
    logger.warn("[auth] invalid token", e);
    return { ok: false, status: 401, message: "Invalid token" };
  }

  const uid = decoded?.uid ? String(decoded.uid) : null;
  if (!uid) {
    return { ok: false, status: 401, message: "Invalid token" };
  }

  const firestore = admin.firestore();
  const adminSnap = await firestore.collection("web_admins").doc(uid).get();
  if (!adminSnap.exists) {
    return { ok: false, status: 403, message: "Forbidden" };
  }

  const adminData = adminSnap.data() || {};
  if (adminData.enabled === false) {
    return { ok: false, status: 403, message: "Forbidden" };
  }

  return { ok: true, uid, email: decoded.email || null };
}

async function _logModerationEvent({
  actorUid,
  actorEmail,
  targetType,
  targetId,
  action,
  payload,
}) {
  const firestore = admin.firestore();
  const event = {
    actorUid: actorUid || null,
    actorEmail: actorEmail || null,
    targetType: String(targetType || '').trim(),
    targetId: String(targetId || '').trim(),
    action: String(action || '').trim(),
    payload: payload != null && typeof payload === 'object' ? payload : null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  // Best-effort: do not throw if logging fails.
  try {
    await firestore.collection('moderation_events').add(event);
  } catch (e) {
    logger.warn('[moderation_events] failed to log event', e);
  }
}

const _deleteQueryDocumentTrees = async (query, stats, statKey) => {
  const snapshot = await query.get();
  if (snapshot.empty) return;

  for (const doc of snapshot.docs) {
    await admin.firestore().recursiveDelete(doc.ref);
    stats[statKey] = (stats[statKey] || 0) + 1;
  }
};

const _deleteDocumentTreeIfExists = async (docRef, stats, statKey) => {
  const snap = await docRef.get();
  if (!snap.exists) return;

  await admin.firestore().recursiveDelete(docRef);
  stats[statKey] = (stats[statKey] || 0) + 1;
};

const _deleteStoragePrefix = async (bucket, prefix, stats) => {
  const [files] = await bucket.getFiles({ prefix });
  if (!files.length) return;

  await Promise.all(files.map((file) => file.delete({ ignoreNotFound: true })));
  stats.storageFiles = (stats.storageFiles || 0) + files.length;
};

exports.deleteMyAccount = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  async (request) => {
    const uid = request.auth?.uid ? String(request.auth.uid).trim() : "";
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "Debes iniciar sesion para eliminar tu cuenta",
      );
    }

    if (request.data?.confirm !== true) {
      throw new HttpsError(
        "failed-precondition",
        "Confirma la eliminacion de la cuenta para continuar",
      );
    }

    const db = admin.firestore();
    const stats = {};
    const userRef = db.collection("users").doc(uid);

    await userRef.set(
      {
        accountDeletion: {
          status: "processing",
          requestedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      },
      { merge: true },
    );

    try {
      const bucket = admin.storage().bucket();
      await _deleteStoragePrefix(bucket, `users/${uid}/`, stats);
      await _deleteStoragePrefix(bucket, `offers/${uid}/`, stats);
      await _deleteStoragePrefix(bucket, `processed/offers/${uid}/`, stats);

      await _deleteQueryDocumentTrees(
        db.collection("offers").where("heroId", "==", uid),
        stats,
        "offers",
      );
      await _deleteQueryDocumentTrees(
        db.collection("notifications").where("userId", "==", uid),
        stats,
        "notifications",
      );
      await _deleteQueryDocumentTrees(
        db.collection("chats").where("participantIds", "array-contains", uid),
        stats,
        "chats",
      );
      await _deleteQueryDocumentTrees(
        db.collection("offer_reports").where("reporterId", "==", uid),
        stats,
        "offerReports",
      );
      await _deleteQueryDocumentTrees(
        db.collection("user_reports").where("reporterId", "==", uid),
        stats,
        "userReports",
      );

      await _deleteDocumentTreeIfExists(
        db.collection("favorites").doc(uid),
        stats,
        "favoritesRoots",
      );
      await _deleteDocumentTreeIfExists(
        db.collection("user_orders").doc(uid),
        stats,
        "userOrderRoots",
      );
      await _deleteDocumentTreeIfExists(
        db.collection("rider_stats").doc(uid),
        stats,
        "riderStats",
      );
      await _deleteDocumentTreeIfExists(userRef, stats, "users");

      await admin.auth().deleteUser(uid);

      logger.info("Account deleted", { uid, stats });
      return { success: true, stats };
    } catch (error) {
      logger.error("deleteMyAccount failed", { uid, error });
      await userRef.set(
        {
          accountDeletion: {
            status: "failed",
            failedAt: admin.firestore.FieldValue.serverTimestamp(),
            message: error?.message || String(error),
          },
        },
        { merge: true },
      ).catch(() => {});

      throw new HttpsError(
        "internal",
        "No pudimos eliminar la cuenta. Intentalo nuevamente o contacta soporte.",
      );
    }
  },
);

function _toCents(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) return null;
  return Math.round(num * 100);
}

function _round2(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) return null;
  return Math.round(num * 100) / 100;
}

function _normalizeNonNegativeNumber(value) {
  const num = Number(value);
  if (!Number.isFinite(num) || Number.isNaN(num) || num < 0) return null;
  return num;
}

function _pickVehicleMap(input) {
  if (input == null) return null;
  if (typeof input !== "object") return null;

  const allowed = new Set(["bicycle", "motorcycle", "car", "truck"]);
  const out = {};
  for (const [k, v] of Object.entries(input)) {
    const key = String(k || "").trim();
    if (!allowed.has(key)) continue;
    const num = _normalizeNonNegativeNumber(v);
    if (num == null) continue;
    out[key] = num;
  }
  return Object.keys(out).length ? out : null;
}

function _normalizePositiveInt(value, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n) || Number.isNaN(n) || n <= 0) return fallback;
  return Math.floor(n);
}

function _parseMillisToTimestamp(value) {
  if (value == null) return null;
  const n = Number(value);
  if (!Number.isFinite(n) || Number.isNaN(n)) return null;
  return admin.firestore.Timestamp.fromMillis(n);
}

function _docIdOrderBy(query, direction) {
  return query.orderBy(admin.firestore.FieldPath.documentId(), direction);
}

async function _getInboxPage(collectionName, req, filter) {
  const firestore = admin.firestore();

  const limit = _normalizePositiveInt(req.query?.limit, 25);
  const startAfterLastReportedAtMs = req.query?.startAfterLastReportedAtMs;
  const startAfterId = req.query?.startAfterId;

  let q = firestore
    .collection(collectionName)
    .where(filter.field, "==", filter.value)
    .orderBy(filter.orderByField, "desc");

  q = _docIdOrderBy(q, "desc");

  if (startAfterLastReportedAtMs != null && startAfterId != null) {
    const ts = _parseMillisToTimestamp(startAfterLastReportedAtMs);
    if (ts) {
      q = q.startAfter(ts, String(startAfterId));
    }
  }

  q = q.limit(limit);
  const snap = await q.get();

  const items = snap.docs.map((d) => ({ id: d.id, data: d.data() || {} }));
  const last = snap.docs.length ? snap.docs[snap.docs.length - 1] : null;
  const lastData = last ? last.data() || {} : null;

  return {
    items,
    nextPage: last
      ? {
          startAfterLastReportedAtMs: lastData?.[filter.orderByField]?.toMillis
            ? lastData[filter.orderByField].toMillis()
            : null,
          startAfterId: last.id,
        }
      : null,
  };
}

exports.adminUpdatePricing = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const pricePerKm = _pickVehicleMap(req.body?.pricePerKm);
      const minimumCharge = _pickVehicleMap(req.body?.minimumCharge);

      const taxBasisPoints = req.body?.taxBasisPoints;
      const taxPercent = req.body?.taxPercent;
      const taxPercentage = req.body?.taxPercentage;

      // maxDistanceKm: vehicle → km (null allowed = uncapped)
      const maxDistanceKmRaw = req.body?.maxDistanceKm;
      let maxDistanceKmUpdate = null;
      if (maxDistanceKmRaw != null && typeof maxDistanceKmRaw === "object") {
        const allowed = new Set(["bicycle", "motorcycle", "car", "truck"]);
        const out = {};
        for (const [k, v] of Object.entries(maxDistanceKmRaw)) {
          const key = String(k || "").trim();
          if (!allowed.has(key)) continue;
          if (v === null) {
            out[key] = null; // null = infinity in Flutter
            continue;
          }
          const num = _normalizeNonNegativeNumber(v);
          if (num == null) continue;
          out[key] = num;
        }
        if (Object.keys(out).length) maxDistanceKmUpdate = out;
      }

      // riderCommission: { serviceFeeCLP, taxPercent }
      const riderCommissionRaw = req.body?.riderCommission;
      let riderCommissionUpdate = null;
      if (
        riderCommissionRaw != null &&
        typeof riderCommissionRaw === "object"
      ) {
        riderCommissionUpdate = {};
        const feeCLP = _normalizeNonNegativeNumber(
          riderCommissionRaw.serviceFeeCLP,
        );
        const riderTaxPercent = _normalizeNonNegativeNumber(
          riderCommissionRaw.taxPercent ?? riderCommissionRaw.taxPercentage,
        );
        if (feeCLP != null) riderCommissionUpdate.serviceFeeCLP = feeCLP;
        if (riderTaxPercent != null)
          riderCommissionUpdate.taxPercent = riderTaxPercent;
        if (!Object.keys(riderCommissionUpdate).length)
          riderCommissionUpdate = null;
      }

      const update = {};
      if (pricePerKm != null) update.pricePerKm = pricePerKm;
      if (minimumCharge != null) update.minimumCharge = minimumCharge;
      if (maxDistanceKmUpdate != null)
        update.maxDistanceKm = maxDistanceKmUpdate;
      if (riderCommissionUpdate != null)
        update.riderCommission = riderCommissionUpdate;

      // distanceDiscount: per-vehicle { thresholdKm, reducedPricePerKm }
      // null for a vehicle key = disable discount for that vehicle.
      const distanceDiscountRaw = req.body?.distanceDiscount;
      let distanceDiscountUpdate = null;
      if (distanceDiscountRaw != null && typeof distanceDiscountRaw === 'object') {
        const allowed = new Set(['bicycle', 'motorcycle', 'car', 'truck']);
        const out = {};
        for (const [k, v] of Object.entries(distanceDiscountRaw)) {
          const key = String(k || '').trim();
          if (!allowed.has(key)) continue;
          if (v === null) {
            out[key] = null; // null = no discount for this vehicle
            continue;
          }
          if (typeof v !== 'object') continue;
          const threshold = _normalizeNonNegativeNumber(v.thresholdKm);
          const reduced = _normalizeNonNegativeNumber(v.reducedPricePerKm);
          if (threshold == null && reduced == null) continue;
          out[key] = {};
          if (threshold != null) out[key].thresholdKm = threshold;
          if (reduced != null) out[key].reducedPricePerKm = reduced;
        }
        if (Object.keys(out).length) distanceDiscountUpdate = out;
      }
      if (distanceDiscountUpdate != null) update.distanceDiscount = distanceDiscountUpdate;


      const taxBpsNum = _normalizeNonNegativeNumber(taxBasisPoints);
      const taxPercentNum = _normalizeNonNegativeNumber(taxPercent);
      const taxPercentageNum = _normalizeNonNegativeNumber(taxPercentage);

      if (taxBpsNum != null) update.taxBasisPoints = taxBpsNum;
      if (taxPercentNum != null) update.taxPercent = taxPercentNum;
      if (taxPercentageNum != null) update.taxPercentage = taxPercentageNum;

      if (!Object.keys(update).length) {
        return res.status(400).json({ error: "No valid fields to update" });
      }

      update.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      update.updatedByUid = authCheck.uid;
      if (authCheck.email) update.updatedByEmail = authCheck.email;

      const firestore = admin.firestore();
      await firestore
        .collection("settings")
        .doc("pricing")
        .set(update, { merge: true });

      return res.status(200).json({ ok: true });
    } catch (e) {
      logger.error("[adminUpdatePricing] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminGetPricing = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const firestore = admin.firestore();
      const snap = await firestore.collection("settings").doc("pricing").get();
      const data = snap.exists ? snap.data() : null;

      return res.status(200).json({
        ok: true,
        exists: snap.exists,
        pricing: data || {},
      });
    } catch (e) {
      logger.error("[adminGetPricing] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportInboxOffers = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const page = await _getInboxPage("offers", req, {
        field: "supportReviewStatus",
        value: "pending",
        orderByField: "lastReportedAt",
      });

      return res.status(200).json({ ok: true, ...page });
    } catch (e) {
      logger.error("[adminSupportInboxOffers] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportInboxUsers = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const page = await _getInboxPage("users", req, {
        field: "supportReviewStatus",
        value: "pending",
        orderByField: "lastReportedAt",
      });

      return res.status(200).json({ ok: true, ...page });
    } catch (e) {
      logger.error("[adminSupportInboxUsers] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportGetOffer = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const offerId = String(req.query?.offerId || "").trim();
      if (!offerId) {
        return res.status(400).json({ error: "Missing offerId" });
      }

      const firestore = admin.firestore();
      const snap = await firestore.collection("offers").doc(offerId).get();
      if (!snap.exists) {
        return res.status(404).json({ error: "Not found" });
      }

      return res
        .status(200)
        .json({ ok: true, offer: { id: snap.id, data: snap.data() || {} } });
    } catch (e) {
      logger.error("[adminSupportGetOffer] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportGetUser = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const userId = String(req.query?.userId || "").trim();
      if (!userId) {
        return res.status(400).json({ error: "Missing userId" });
      }

      const firestore = admin.firestore();
      const snap = await firestore.collection("users").doc(userId).get();
      if (!snap.exists) {
        return res.status(404).json({ error: "Not found" });
      }

      return res
        .status(200)
        .json({ ok: true, user: { id: snap.id, data: snap.data() || {} } });
    } catch (e) {
      logger.error("[adminSupportGetUser] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportListOfferReports = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const offerId = String(req.query?.offerId || "").trim();
      if (!offerId) {
        return res.status(400).json({ error: "Missing offerId" });
      }

      const limit = _normalizePositiveInt(req.query?.limit, 200);
      const firestore = admin.firestore();
      const snap = await firestore
        .collection("offers")
        .doc(offerId)
        .collection("reports")
        .orderBy("createdAt", "desc")
        .limit(limit)
        .get();

      const reports = snap.docs.map((d) => ({ id: d.id, data: d.data() || {} }));
      return res.status(200).json({ ok: true, reports });
    } catch (e) {
      logger.error("[adminSupportListOfferReports] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportListUserReports = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "GET") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const userId = String(req.query?.userId || "").trim();
      if (!userId) {
        return res.status(400).json({ error: "Missing userId" });
      }

      const limit = _normalizePositiveInt(req.query?.limit, 200);
      const firestore = admin.firestore();
      const snap = await firestore
        .collection("users")
        .doc(userId)
        .collection("reports")
        .orderBy("createdAt", "desc")
        .limit(limit)
        .get();

      const reports = snap.docs.map((d) => ({ id: d.id, data: d.data() || {} }));
      return res.status(200).json({ ok: true, reports });
    } catch (e) {
      logger.error("[adminSupportListUserReports] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportSetOfferReviewStatus = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const offerId = String(req.body?.offerId || "").trim();
      const status = String(req.body?.status || "").trim();
      const notes = req.body?.notes != null ? String(req.body.notes) : null;

      if (!offerId) return res.status(400).json({ error: "Missing offerId" });
      if (!new Set(["reviewed", "dismissed"]).has(status)) {
        return res.status(400).json({ error: "Invalid status" });
      }

      const firestore = admin.firestore();
      await firestore.collection("offers").doc(offerId).set(
        {
          supportReviewStatus: status,
          lastModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(notes != null ? { moderationNotes: notes } : {}),
          moderatedByUid: authCheck.uid,
          ...(authCheck.email ? { moderatedByEmail: authCheck.email } : {}),
        },
        { merge: true },
      );

      await _logModerationEvent({
        actorUid: authCheck.uid,
        actorEmail: authCheck.email,
        targetType: 'offer',
        targetId: offerId,
        action: 'set_review_status',
        payload: { status, notes },
      });

      return res.status(200).json({ ok: true });
    } catch (e) {
      logger.error("[adminSupportSetOfferReviewStatus] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportSetUserReviewStatus = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const userId = String(req.body?.userId || "").trim();
      const status = String(req.body?.status || "").trim();
      const notes = req.body?.notes != null ? String(req.body.notes) : null;

      if (!userId) return res.status(400).json({ error: "Missing userId" });
      if (!new Set(["reviewed", "dismissed"]).has(status)) {
        return res.status(400).json({ error: "Invalid status" });
      }

      const firestore = admin.firestore();
      await firestore.collection("users").doc(userId).set(
        {
          supportReviewStatus: status,
          lastModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(notes != null ? { moderationNotes: notes } : {}),
          moderatedByUid: authCheck.uid,
          ...(authCheck.email ? { moderatedByEmail: authCheck.email } : {}),
        },
        { merge: true },
      );

      await _logModerationEvent({
        actorUid: authCheck.uid,
        actorEmail: authCheck.email,
        targetType: 'user',
        targetId: userId,
        action: 'set_review_status',
        payload: { status, notes },
      });

      return res.status(200).json({ ok: true });
    } catch (e) {
      logger.error("[adminSupportSetUserReviewStatus] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportModerateOffer = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const offerId = String(req.body?.offerId || "").trim();
      const moderationStatus = String(req.body?.moderationStatus || "").trim();
      const notes = req.body?.notes != null ? String(req.body.notes) : null;

      if (!offerId) return res.status(400).json({ error: "Missing offerId" });
      if (!new Set(["visible", "hidden", "blocked"]).has(moderationStatus)) {
        return res.status(400).json({ error: "Invalid moderationStatus" });
      }

      const firestore = admin.firestore();
      await firestore.collection("offers").doc(offerId).set(
        {
          moderationStatus,
          supportReviewStatus: "reviewed",
          lastModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(notes != null ? { moderationNotes: notes } : {}),
          moderatedByUid: authCheck.uid,
          ...(authCheck.email ? { moderatedByEmail: authCheck.email } : {}),
        },
        { merge: true },
      );

      await _logModerationEvent({
        actorUid: authCheck.uid,
        actorEmail: authCheck.email,
        targetType: 'offer',
        targetId: offerId,
        action: 'set_moderation_status',
        payload: { moderationStatus, notes },
      });

      return res.status(200).json({ ok: true });
    } catch (e) {
      logger.error("[adminSupportModerateOffer] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportModerateUser = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const userId = String(req.body?.userId || "").trim();
      const accountStatus = String(req.body?.accountStatus || "").trim();
      const suspendedUntilMs = req.body?.suspendedUntilMs;
      const notes = req.body?.notes != null ? String(req.body.notes) : null;

      if (!userId) return res.status(400).json({ error: "Missing userId" });
      if (!new Set(["active", "suspended", "banned"]).has(accountStatus)) {
        return res.status(400).json({ error: "Invalid accountStatus" });
      }

      let suspendedUntil = null;
      if (accountStatus === "suspended") {
        suspendedUntil = _parseMillisToTimestamp(suspendedUntilMs);
        if (!suspendedUntil) {
          return res.status(400).json({ error: "Missing/invalid suspendedUntilMs" });
        }
      }

      const firestore = admin.firestore();
      await firestore.collection("users").doc(userId).set(
        {
          accountStatus,
          suspendedUntil: accountStatus === "suspended" ? suspendedUntil : null,
          supportReviewStatus: "reviewed",
          lastModeratedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(notes != null ? { moderationNotes: notes } : {}),
          moderatedByUid: authCheck.uid,
          ...(authCheck.email ? { moderatedByEmail: authCheck.email } : {}),
        },
        { merge: true },
      );

      await _logModerationEvent({
        actorUid: authCheck.uid,
        actorEmail: authCheck.email,
        targetType: 'user',
        targetId: userId,
        action: 'set_account_status',
        payload: {
          accountStatus,
          suspendedUntilMs: suspendedUntil ? suspendedUntil.toMillis() : null,
          notes,
        },
      });

      return res.status(200).json({ ok: true });
    } catch (e) {
      logger.error("[adminSupportModerateUser] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminSupportDeleteOffer = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const offerId = String(req.body?.offerId || "").trim();
      if (!offerId) return res.status(400).json({ error: "Missing offerId" });

      const firestore = admin.firestore();
      const offerRef = firestore.collection("offers").doc(offerId);
      await firestore.recursiveDelete(offerRef);

      await _logModerationEvent({
        actorUid: authCheck.uid,
        actorEmail: authCheck.email,
        targetType: 'offer',
        targetId: offerId,
        action: 'delete_offer',
        payload: null,
      });

      return res.status(200).json({ ok: true });
    } catch (e) {
      logger.error("[adminSupportDeleteOffer] error", e);
      return res.status(500).json({ error: "Internal error" });
    }
  },
);

exports.adminPayoutRider = onRequest(
  {
    region: "southamerica-west1",
    cors: true,
  },
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        return res.status(405).json({ error: "Method not allowed" });
      }

      const authCheck = await _requireWebAdmin(req);
      if (!authCheck.ok) {
        return res.status(authCheck.status).json({ error: authCheck.message });
      }

      const riderId = String(req.body?.riderId || "").trim();
      const idempotencyKey = String(req.body?.idempotencyKey || "").trim();
      const reference =
        req.body?.reference != null ? String(req.body.reference) : null;
      const note = req.body?.note != null ? String(req.body.note) : null;

      if (!riderId) {
        return res.status(400).json({ error: "riderId is required" });
      }
      if (!idempotencyKey) {
        return res.status(400).json({ error: "idempotencyKey is required" });
      }

      const requestedCents =
        req.body?.amount == null ? null : _toCents(req.body.amount);
      if (
        req.body?.amount != null &&
        (requestedCents == null || requestedCents <= 0)
      ) {
        return res.status(400).json({ error: "amount must be > 0" });
      }

      const firestore = admin.firestore();
      const userRef = firestore.collection("users").doc(riderId);
      const idemRef = firestore
        .collection("admin_payout_requests")
        .doc(idempotencyKey);
      const payoutTxRef = userRef.collection("riderWalletTransactions").doc();

      const result = await firestore.runTransaction(async (tx) => {
        const idemSnap = await tx.get(idemRef);
        if (idemSnap.exists) {
          const idem = idemSnap.data() || {};
          if (idem.status === "completed") {
            return {
              replay: true,
              riderId,
              payoutTxId: idem.payoutTxId || null,
              paidAmount: idem.paidAmount || 0,
              paidAmountCents: idem.paidAmountCents || 0,
              currency: idem.currency || "CLP",
              walletBefore: idem.walletBefore || null,
              walletAfter: idem.walletAfter || null,
            };
          }
          throw new Error("Idempotency key is already in use");
        }

        const userSnap = await tx.get(userRef);
        if (!userSnap.exists) {
          throw new Error("Rider not found");
        }
        const user = userSnap.data() || {};
        const wallet =
          user.riderWallet && typeof user.riderWallet === "object"
            ? user.riderWallet
            : {};

        let earningsBalanceCents =
          wallet.earningsBalanceCents != null
            ? Number(wallet.earningsBalanceCents)
            : null;

        const legacyEarnings =
          wallet.earningsBalance != null ? Number(wallet.earningsBalance) : 0;

        if (
          earningsBalanceCents == null ||
          !Number.isFinite(earningsBalanceCents)
        ) {
          earningsBalanceCents = _toCents(legacyEarnings) || 0;
          tx.update(userRef, {
            "riderWallet.earningsBalanceCents": earningsBalanceCents,
          });
        }

        earningsBalanceCents = Math.max(0, Math.trunc(earningsBalanceCents));
        const maxPayableCents = earningsBalanceCents;
        const payoutCents = Math.min(
          requestedCents == null ? maxPayableCents : requestedCents,
          maxPayableCents,
        );

        const isPartial = payoutCents < maxPayableCents;

        if (payoutCents <= 0) {
          const payload = {
            status: "completed",
            riderId,
            payoutTxId: null,
            paidAmountCents: 0,
            paidAmount: 0,
            currency: wallet.currency || "CLP",
            walletBefore: {
              earningsBalanceCents: earningsBalanceCents,
              earningsBalance: legacyEarnings,
            },
            walletAfter: {
              earningsBalanceCents: earningsBalanceCents,
              earningsBalance: legacyEarnings,
            },
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          };
          tx.set(idemRef, payload);
          return {
            replay: false,
            riderId,
            payoutTxId: null,
            paidAmountCents: 0,
            paidAmount: 0,
            currency: payload.currency,
            walletBefore: payload.walletBefore,
            walletAfter: payload.walletAfter,
          };
        }

        const paidAmount = payoutCents / 100;
        const walletBefore = {
          earningsBalanceCents: earningsBalanceCents,
          earningsBalance: legacyEarnings,
        };
        const walletAfter = {
          earningsBalanceCents: earningsBalanceCents - payoutCents,
          earningsBalance:
            _round2(legacyEarnings - paidAmount) ?? legacyEarnings - paidAmount,
        };

        tx.set(payoutTxRef, {
          type: "payout",
          riderId,
          amountCents: -payoutCents,
          amount: -paidAmount,
          currency: wallet.currency || "CLP",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          meta: {
            method: "bank_transfer",
            reference,
            note,
            isPartial,
            requestedAmountCents: requestedCents,
          },
        });

        const walletUpdate = {
          "riderWallet.earningsBalanceCents":
            admin.firestore.FieldValue.increment(-payoutCents),
          "riderWallet.earningsBalance":
            admin.firestore.FieldValue.increment(-paidAmount),
        };
        if (!isPartial) {
          walletUpdate["riderWallet.lastPayoutAt"] =
            admin.firestore.FieldValue.serverTimestamp();
          walletUpdate["riderWallet.lastPayoutAmountCents"] = payoutCents;
        }
        tx.update(userRef, walletUpdate);

        tx.set(idemRef, {
          status: "completed",
          riderId,
          payoutTxId: payoutTxRef.id,
          paidAmountCents: payoutCents,
          paidAmount,
          currency: wallet.currency || "CLP",
          walletBefore,
          walletAfter,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {
          replay: false,
          riderId,
          payoutTxId: payoutTxRef.id,
          paidAmountCents: payoutCents,
          paidAmount,
          currency: wallet.currency || "CLP",
          walletBefore,
          walletAfter,
        };
      });

      return res.status(200).json(result);
    } catch (e) {
      logger.error("[adminPayoutRider] Error", e);
      const msg = e?.message ? String(e.message) : String(e);
      if (msg.toLowerCase().includes("not found")) {
        return res.status(404).json({ error: msg });
      }
      if (msg.toLowerCase().includes("idempotency")) {
        return res.status(409).json({ error: msg });
      }
      return res.status(500).json({ error: msg });
    }
  },
);

/**
 * Asigna un pedido a un rider de forma segura
 * Valida: rider verificado, compatibilidad de vehículo, estado del pedido
 *
 * @param {Object} data - { orderId: string }
 * @param {Object} context - Firebase auth context
 * @returns {Promise<Object>} - { success: boolean, orderId: string, message: string }
 */
exports.claimOrder = onCall(async (request) => {
  // ==========================================
  // 1. VALIDAR AUTENTICACIÓN
  // ==========================================
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Usuario no autenticado");
  }

  const riderId = request.auth.uid;
  const orderId = request.data.orderId;

  if (!orderId) {
    throw new HttpsError("invalid-argument", "orderId es requerido");
  }

  console.log(
    `[claimOrder] Rider ${riderId} intentando tomar pedido ${orderId}`,
  );

  // ==========================================
  // 2. OBTENER PERFIL DEL RIDER
  // ==========================================
  const riderDoc = await admin
    .firestore()
    .collection("users")
    .doc(riderId)
    .get();

  if (!riderDoc.exists) {
    throw new HttpsError("not-found", "Rider no encontrado");
  }

  const riderData = riderDoc.data();
  const riderProfile = riderData.riderProfile;

  // Validar que el usuario tenga rol de rider
  if (!riderData.roles || !riderData.roles.includes("rider")) {
    throw new HttpsError("permission-denied", "No tienes permisos de rider");
  }

  // ==========================================
  // 3. VALIDAR RIDER VERIFICADO (CRÍTICO)
  // ==========================================
  if (!riderProfile || !riderProfile.isVerified) {
    throw new HttpsError(
      "failed-precondition",
      "Tu cuenta debe estar verificada para tomar pedidos",
    );
  }

  if (!riderProfile.isActive) {
    throw new HttpsError("failed-precondition", "Tu cuenta no está activa");
  }

  console.log(`[claimOrder] Rider verificado: ${riderData.identity.firstName}`);

  // ==========================================
  // 4. TRANSACCIÓN ATÓMICA
  // ==========================================
  const orderRef = admin.firestore().collection("orders").doc(orderId);

  return admin.firestore().runTransaction(async (transaction) => {
    const orderDoc = await transaction.get(orderRef);

    if (!orderDoc.exists) {
      throw new HttpsError('not-found', 'Pedido no encontrado');
    }

    const order = orderDoc.data();

    // Validar estado
    if (order.status !== 'queued') {
      throw new HttpsError(
        'failed-precondition',
        `Pedido ya no está disponible (estado: ${order.status})`,
      );
    }

    if (order.rider && order.rider.assignedRiderId) {
      throw new HttpsError('failed-precondition', 'Pedido ya tiene rider asignado');
    }

    // ==========================================
    // 5. VALIDAR COMPATIBILIDAD DE VEHÍCULO
    // ==========================================
    const requiredVehicle = order.requirements.requiredVehicle;
    const riderVehicle = riderProfile.vehicle.type;
    const compatibleVehicles = getCompatibleVehicles(riderVehicle);

    if (!compatibleVehicles.includes(requiredVehicle)) {
      throw new HttpsError(
        'failed-precondition',
        `Tu vehículo (${riderVehicle}) no es compatible con este pedido (requiere ${requiredVehicle})`,
      );
    }

    if (riderProfile.limits && riderProfile.limits.maxWeightKg) {
      if (order.requirements.weightKg > riderProfile.limits.maxWeightKg) {
        throw new HttpsError(
          'failed-precondition',
          `El peso del pedido excede tu capacidad`,
        );
      }
    }

    if (riderProfile.limits && riderProfile.limits.maxDistanceKm) {
      if (order.requirements.estimatedDistanceKm > riderProfile.limits.maxDistanceKm) {
        throw new HttpsError(
          'failed-precondition',
          `La distancia del pedido excede tu rango`,
        );
      }
    }

    // ==========================================
    // 5b. VALIDAR SALDO PARA PEDIDO EN EFECTIVO
    // ==========================================
    const paymentRef = admin.firestore().collection('payments').doc(`cash-${orderId}`);
    const paymentSnap = await transaction.get(paymentRef);

    const isCashOrder = paymentSnap.exists && (() => {
      const pd = paymentSnap.data() || {};
      const methodId = (pd.paymentMethodId || '').toLowerCase();
      const statusDetail = (pd.statusDetail || '').toLowerCase();
      const method = (pd.paymentMethod || '').toLowerCase();
      return methodId === 'cash' || statusDetail === 'cash_on_delivery' ||
             statusDetail === 'cash_collected' || method === 'cash';
    })();

    const riderRef = admin.firestore().collection('users').doc(riderId);
    const riderSnap = await transaction.get(riderRef);
    const walletData = (riderSnap.exists && riderSnap.data()?.riderWallet) || {};

    let cashAmountToCollect = 0;

    if (isCashOrder) {
      const total = typeof order.amountTotal === 'number' ? order.amountTotal : 0;
      cashAmountToCollect = Math.max(0, total); // incluye propina — el rider cobra el total completo

      // Saldo disponible = earningsBalance - cashOnHold (ya retenido por otros pedidos)
      const earningsBalanceCents = typeof walletData.earningsBalanceCents === 'number'
        ? walletData.earningsBalanceCents
        : _toCents(walletData.earningsBalance ?? 0);
      const cashOnHoldCents = typeof walletData.cashOnHoldCents === 'number'
        ? walletData.cashOnHoldCents
        : _toCents(walletData.cashOnHold ?? 0);

      const availableCents = Math.max(0, earningsBalanceCents - cashOnHoldCents);
      const requiredCents = _toCents(cashAmountToCollect);

      if (availableCents < requiredCents) {
        const available = (availableCents / 100).toFixed(0);
        const required = cashAmountToCollect.toFixed(0);
        throw new HttpsError(
          'failed-precondition',
          `Saldo insuficiente para pedido en efectivo. Necesitas $${required} CLP disponibles, tienes $${available} CLP.`,
        );
      }
    }

    // ==========================================
    // 6. ASIGNAR PEDIDO
    // ==========================================
    const now = admin.firestore.FieldValue.serverTimestamp();

    const orderUpdate = {
      status: 'assigned',
      'rider.assignedRiderId': riderId,
      'rider.assignedAt': now,
      'rider.vehicleTypeSnapshot': riderProfile.vehicle.type,
      'rider.riderNameSnapshot':
        riderData.identity.firstName + ' ' + (riderData.identity.lastName || ''),
      'rider.riderPhoneSnapshot': riderData.contact.phoneNumber || '',
      'timestamps.assignedAt': now,
      updatedAt: now,
    };

    if (isCashOrder && cashAmountToCollect > 0) {
      orderUpdate['rider.cashHoldAmount'] = cashAmountToCollect;

      const holdCents = _toCents(cashAmountToCollect);
      transaction.update(riderRef, {
        'riderWallet.cashOnHold': admin.firestore.FieldValue.increment(cashAmountToCollect),
        'riderWallet.cashOnHoldCents': admin.firestore.FieldValue.increment(holdCents),
      });

      const holdTxRef = riderRef.collection('riderWalletTransactions').doc();
      transaction.set(holdTxRef, {
        type: 'cash_hold',
        orderId,
        amount: cashAmountToCollect,
        amountCents: holdCents,
        currency: order.currency || 'CLP',
        createdAt: now,
      });
    }

    transaction.update(orderRef, orderUpdate);

    return {
      success: true,
      orderId: orderId,
      message: 'Pedido asignado exitosamente',
    };
  });
});

/**
 * Helper: Obtiene vehículos compatibles según el tipo de vehículo del rider
 *
 * Lógica:
 * - Camión puede tomar: bicycle, motorcycle, car, truck (todos)
 * - Auto puede tomar: bicycle, motorcycle, car
 * - Moto puede tomar: bicycle, motorcycle
 * - Bicicleta puede tomar: bicycle
 *
 * @param {string} riderVehicleType - Tipo de vehículo del rider
 * @returns {string[]} - Array de tipos de vehículos compatibles
 */
function getCompatibleVehicles(riderVehicleType) {
  switch (riderVehicleType) {
    case "bicycle":
      return ["bicycle"];
    case "motorcycle":
      return ["bicycle", "motorcycle"];
    case "car":
      return ["bicycle", "motorcycle", "car"];
    case "truck":
      return ["bicycle", "motorcycle", "car", "truck"];
    default:
      console.warn(
        `[getCompatibleVehicles] Tipo de vehículo desconocido: ${riderVehicleType}`,
      );
      return [];
  }
}

/**
 * Aprueba o rechaza una solicitud de verificación de vehículo.
 *
 * Seguridad:
 * - Solo usuarios soporte/admin (allowlist por email o custom claim) pueden ejecutar.
 *
 * Entrada:
 * - { userId: string, requestId: string, decision: 'approved'|'rejected', reason?: string }
 */
exports.reviewVehicleVerificationRequest = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Usuario no autenticado");
  }

  if (!isSupportUser(request.auth)) {
    throw new HttpsError("permission-denied", "No autorizado");
  }

  const userId = request.data?.userId;
  const requestId = request.data?.requestId;
  const decision = request.data?.decision;
  const reason = request.data?.reason;

  if (!userId || !requestId || !decision) {
    throw new HttpsError(
      "invalid-argument",
      "userId, requestId y decision son requeridos",
    );
  }

  if (!["approved", "rejected"].includes(decision)) {
    throw new HttpsError("invalid-argument", "decision inválida");
  }

  const reqRef = admin
    .firestore()
    .collection("users")
    .doc(userId)
    .collection("vehicle_verification_requests")
    .doc(requestId);

  const userRef = admin.firestore().collection("users").doc(userId);
  const reviewerId = request.auth.uid;

  await admin.firestore().runTransaction(async (tx) => {
    const reqSnap = await tx.get(reqRef);
    if (!reqSnap.exists) {
      throw new HttpsError("not-found", "Solicitud no encontrada");
    }

    const reqData = reqSnap.data() || {};
    const vehicleType = reqData.vehicleType;
    if (!vehicleType || typeof vehicleType !== "string") {
      throw new HttpsError(
        "failed-precondition",
        "vehicleType faltante en solicitud",
      );
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    tx.update(reqRef, {
      status: decision,
      updatedAt: now,
      verification: {
        verifiedAt: now,
        verificationMode: "manual",
        reason: reason || null,
        reviewerId,
      },
    });

    tx.set(
      userRef,
      {
        riderProfile: {
          vehicles: {
            [vehicleType]: {
              verification: {
                status: decision,
                verifiedAt: now,
                reviewerId,
                reason: reason || null,
                requestId,
              },
            },
          },
        },
      },
      { merge: true },
    );
  });

  return { success: true };
});

/**
 * Aprueba o rechaza una solicitud de verificación de RUT.
 *
 * Seguridad:
 * - Solo usuarios soporte/admin (allowlist por email o custom claim) pueden ejecutar.
 *
 * Entrada:
 * - { userId: string, requestId: string, decision: 'approved'|'rejected', reason?: string }
 */
exports.reviewRutVerificationRequest = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Usuario no autenticado");
  }

  if (!isSupportUser(request.auth)) {
    throw new HttpsError("permission-denied", "No autorizado");
  }

  const userId = request.data?.userId;
  const requestId = request.data?.requestId;
  const decision = request.data?.decision;
  const reason = request.data?.reason;

  if (!userId || !requestId || !decision) {
    throw new HttpsError(
      "invalid-argument",
      "userId, requestId y decision son requeridos",
    );
  }

  if (!["approved", "rejected"].includes(decision)) {
    throw new HttpsError("invalid-argument", "decision inválida");
  }

  const userRef = admin.firestore().collection("users").doc(userId);
  const reqRef = userRef.collection("rut_verification_requests").doc(requestId);
  const reviewerId = request.auth.uid;

  await admin.firestore().runTransaction(async (tx) => {
    const reqSnap = await tx.get(reqRef);
    if (!reqSnap.exists) {
      throw new HttpsError("not-found", "Solicitud no encontrada");
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    tx.set(
      reqRef,
      {
        status: decision,
        updatedAt: now,
        verification: {
          verifiedAt: now,
          verificationMode: "manual",
          reason: reason || null,
          reviewerId,
        },
      },
      { merge: true },
    );

    tx.set(
      userRef,
      {
        rutVerification: {
          status: decision,
          verifiedAt: decision === "approved" ? now : now,
          reviewerId,
          reason: reason || null,
          requestId,
          mode: "manual",
        },
      },
      { merge: true },
    );
  });

  return { success: true };
});

/**
 * Función para actualizar el estado de un pedido
 * Solo el rider asignado puede actualizar el estado
 *
 * @param {Object} data - { orderId: string, newStatus: string }
 * @param {Object} context - Firebase auth context
 */
exports.updateOrderStatus = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Usuario no autenticado");
  }

  const { orderId, newStatus } = request.data;
  const riderId = request.auth.uid;

  if (!orderId || !newStatus) {
    throw new HttpsError(
      "invalid-argument",
      "orderId y newStatus son requeridos",
    );
  }

  // Estados válidos para actualización por rider
  const validStatuses = ["picked_up", "in_transit", "delivered"];
  if (!validStatuses.includes(newStatus)) {
    throw new HttpsError(
      "invalid-argument",
      `Estado inválido. Debe ser uno de: ${validStatuses.join(", ")}`,
    );
  }

  const orderRef = admin.firestore().collection("orders").doc(orderId);
  const orderDoc = await orderRef.get();

  if (!orderDoc.exists) {
    throw new HttpsError("not-found", "Pedido no encontrado");
  }

  const order = orderDoc.data();

  // Validar que el rider sea el asignado
  if (!order.rider || order.rider.assignedRiderId !== riderId) {
    throw new HttpsError(
      "permission-denied",
      "No tienes permiso para actualizar este pedido",
    );
  }

  // Validar transición de estado
  const validTransitions = {
    assigned: ["picked_up"],
    picked_up: ["in_transit"],
    in_transit: ["delivered"],
  };

  if (
    !validTransitions[order.status] ||
    !validTransitions[order.status].includes(newStatus)
  ) {
    throw new HttpsError(
      "failed-precondition",
      `No se puede cambiar de ${order.status} a ${newStatus}`,
    );
  }

  // Actualizar estado
  const now = admin.firestore.FieldValue.serverTimestamp();
  const updates = {
    status: newStatus,
    updatedAt: now,
  };

  // Actualizar timestamp específico
  if (newStatus === "picked_up") {
    updates["timestamps.pickedUpAt"] = now;
  } else if (newStatus === "in_transit") {
    updates["timestamps.inTransitAt"] = now;
  } else if (newStatus === "delivered") {
    updates["timestamps.deliveredAt"] = now;
  }

  await orderRef.update(updates);

  console.log(
    `[updateOrderStatus] Pedido ${orderId} actualizado a ${newStatus}`,
  );

  return {
    success: true,
    orderId: orderId,
    newStatus: newStatus,
    message: `Pedido actualizado a ${newStatus}`,
  };
});

/**
 * Procesa imágenes subidas a Storage:
 * - Solo archivos de imagen
 * - Evita re-procesar imágenes ya convertidas o en carpeta processed/
 * - Genera versión 1200x1200 en WebP y la guarda en processed/<ruta>/*_1200.webp
 */
exports.processImage1200Webp = onObjectFinalized(
  { region: STORAGE_REGION },
  async (event) => {
    const object = event.data;
    const filePath = object.name;
    const contentType = object.contentType || "";

    if (!filePath) return null;
    if (!contentType.startsWith("image/")) return null;
    if (filePath.endsWith("_1200.webp")) return null;
    if (filePath.startsWith("processed/")) return null;

    const bucket = admin.storage().bucket(object.bucket);
    const fileName = path.basename(filePath);
    const dirName = path.dirname(filePath);
    const tempLocalFile = path.join(os.tmpdir(), fileName);

    const isAd = filePath.startsWith("ads/");
    const isOffer = filePath.startsWith("offers/");
    const metadata = object.metadata || {};

    const baseName = fileName.replace(/\.[^.]+$/, "");
    const processedFileName = isAd
      ? `${baseName}.webp`
      : `${baseName}_1200.webp`;
    const processedDir = path.join("processed", dirName === "." ? "" : dirName);
    const processedPath = path.join(processedDir, processedFileName);
    const tempProcessedFile = path.join(os.tmpdir(), processedFileName);

    try {
      // Descargar original
      await bucket.file(filePath).download({ destination: tempLocalFile });

      const transformer = sharp(tempLocalFile).rotate();

      if (isAd) {
        // Banners: sin resize, solo convertir a WebP
        await transformer
          .toFormat("webp", { quality: 85 })
          .toFile(tempProcessedFile);
      } else {
        // Productos y resto: estandarizar a 1200x1200 WebP (recorte centrado)
        await transformer
          .resize(1200, 1200, { fit: "cover", position: "centre" })
          .toFormat("webp", { quality: 80 })
          .toFile(tempProcessedFile);
      }

      // Subir procesado
      await bucket.upload(tempProcessedFile, {
        destination: processedPath,
        contentType: "image/webp",
        metadata: {
          metadata: {
            processed: "true",
            original: filePath,
          },
        },
      });

      if (isAd) {
        // Crear/actualizar documento en colección de lectura
        const downloadUrl = buildDownloadUrl(bucket.name, processedPath);
        const docId = processedPath
          .replace(/^processed\//, "")
          .replace(/[^\w\-\/.]/g, "_")
          .replace(/\//g, "__");

        const rawOrder = metadata.order;
        const rawActive = metadata.active;
        const order =
          typeof rawOrder === "string" ? parseInt(rawOrder, 10) || 0 : 0;
        const active =
          typeof rawActive === "string"
            ? ["true", "1", "yes"].includes(rawActive.toLowerCase())
            : true;

        await admin.firestore().collection("promo_banners").doc(docId).set(
          {
            imageUrl: downloadUrl,
            order,
            active,
            cacheBuster: admin.firestore.FieldValue.serverTimestamp(),
            storagePath: processedPath,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }

      if (isOffer) {
        // Crear/actualizar documento de oferta usando el ID del path: offers/{userId}/{offerId}/file
        const segments = filePath.split("/").filter(Boolean);
        const offerId = segments.length >= 3 ? segments[2] : null;
        if (offerId) {
          const downloadUrl = buildDownloadUrl(bucket.name, processedPath);
          const offersCol = admin.firestore().collection("offers");
          await offersCol.doc(offerId).set(
            {
              coverImageUrl: downloadUrl,
              imageUrls: admin.firestore.FieldValue.arrayUnion(downloadUrl),
              storagePath: processedPath,
              cacheBuster: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
      }

      logger.info("Imagen procesada", {
        original: filePath,
        processed: processedPath,
      });
    } catch (error) {
      logger.error("Error procesando imagen", { filePath, error });
      throw error;
    } finally {
      // Limpieza local
      if (fs.existsSync(tempLocalFile)) {
        fs.unlinkSync(tempLocalFile);
      }
      if (fs.existsSync(tempProcessedFile)) {
        fs.unlinkSync(tempProcessedFile);
      }
    }

    return null;
  },
);

function normalizeRut(raw) {
  if (!raw) return null;
  const cleaned = String(raw)
    .toUpperCase()
    .replace(/\s+/g, "")
    .replace(/\./g, "")
    .replace(/–|—/g, "-")
    .replace(/[^0-9K-]/g, "");

  const withDash = cleaned.includes("-")
    ? cleaned
    : cleaned.length >= 2
      ? `${cleaned.slice(0, -1)}-${cleaned.slice(-1)}`
      : cleaned;

  const match = withDash.match(/^(\d{7,8})-([0-9K])$/);
  if (!match) return null;
  return `${match[1]}-${match[2]}`;
}

function computeRutDv(body) {
  let sum = 0;
  let multiplier = 2;

  for (let i = body.length - 1; i >= 0; i -= 1) {
    sum += parseInt(body[i], 10) * multiplier;
    multiplier = multiplier === 7 ? 2 : multiplier + 1;
  }

  const remainder = 11 - (sum % 11);
  if (remainder === 11) return "0";
  if (remainder === 10) return "K";
  return String(remainder);
}

function isValidRutDv(rut) {
  const normalized = normalizeRut(rut);
  if (!normalized) return false;
  const [body, dv] = normalized.split("-");
  return computeRutDv(body) === dv;
}

function extractRutCandidates(text) {
  if (!text) return [];
  const normalizedText = String(text)
    .toUpperCase()
    .replace(/\./g, "")
    .replace(/\s+/g, " ");

  const candidates = new Set();

  const patterns = [
    /\b\d{1,2}(?:\.?\d{3}){2}-[0-9K]\b/g,
    /\b\d{7,8}-[0-9K]\b/g,
    /\b\d{7,8}[0-9K]\b/g,
  ];

  for (const re of patterns) {
    const matches = normalizedText.match(re) || [];
    for (const m of matches) {
      const n = normalizeRut(m);
      if (n) candidates.add(n);
    }
  }

  return Array.from(candidates);
}

function stripDiacritics(input) {
  if (!input) return "";
  return String(input)
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "");
}

function countRutKeywords(text) {
  const t = stripDiacritics(String(text || "")).toUpperCase();
  const keywords = ["REPUBLICA DE CHILE", "CEDULA DE IDENTIDAD", "RUN"];

  let hits = 0;
  const matched = [];
  for (const k of keywords) {
    if (t.includes(k)) {
      hits += 1;
      matched.push(k);
    }
  }

  return { hits, matched };
}

function countLicenseKeywords(text) {
  const t = stripDiacritics(String(text || "")).toUpperCase();
  const keywords = ["LICENCIA DE CONDUCIR", "CLASE", "REPUBLICA DE CHILE"];

  let hits = 0;
  const matched = [];
  for (const k of keywords) {
    if (t.includes(k)) {
      hits++;
      matched.push(k);
    }
  }
  return { hits, matched };
}

function normalizeLicenseClass(raw) {
  if (!raw) return null;
  const c = stripDiacritics(String(raw)).toUpperCase().replace(/\s+/g, "");
  return c;
}

function extractLicenseClass(text) {
  const t = stripDiacritics(String(text || "")).toUpperCase();
  // Prefer explicit "CLASE" marker
  const m = t.match(/\bCLASE\b\s*[:\-]?\s*([A-C]\s?\d?)/);
  if (m && m[1]) return normalizeLicenseClass(m[1]);

  // Secondary: look for A4/A5 tokens
  if (t.includes("A4")) return "A4";
  if (t.includes("A5")) return "A5";

  // Very conservative fallback for B/C
  if (t.match(/\bCLASE\s*B\b/)) return "B";
  if (t.match(/\bCLASE\s*C\b/)) return "C";

  return null;
}

function extractExpiryDate(text) {
  const t = stripDiacritics(String(text || "")).toUpperCase();
  // Common patterns: VENCIMIENTO 12/09/2028, VENC. 12-09-2028
  const near = t.match(
    /(VENC|VENCIMIENTO|CADUCIDAD)[^0-9]{0,25}(\d{2}[\/-]\d{2}[\/-]\d{4})/,
  );
  const raw =
    near && near[2]
      ? near[2]
      : (t.match(/\b(\d{2}[\/-]\d{2}[\/-]\d{4})\b/) || [null, null])[1];
  if (!raw) return null;

  const parts = raw.split(/[\/-]/).map((n) => Number(n));
  if (parts.length !== 3) return null;
  const [dd, mm, yyyy] = parts;
  if (!dd || !mm || !yyyy) return null;

  const d = new Date(Date.UTC(yyyy, mm - 1, dd, 23, 59, 59));
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

function normalizeNameForMatch(name) {
  return stripDiacritics(String(name || ""))
    .toUpperCase()
    .replace(/[^A-Z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function nameTokenSet(name) {
  return new Set(
    normalizeNameForMatch(name)
      .split(" ")
      .map((t) => t.trim())
      .filter((t) => t.length >= 2),
  );
}

function nameMatchRatio({ declaredFullName, extractedFullName }) {
  const d = nameTokenSet(declaredFullName);
  const e = nameTokenSet(extractedFullName);
  if (d.size === 0 || e.size === 0) return 0;
  let inter = 0;
  for (const t of d) {
    if (e.has(t)) inter++;
  }
  return inter / d.size;
}

function extractNameHeuristic({ ocrText, declaredFullName }) {
  const lines = String(ocrText || "")
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);

  const declared = normalizeNameForMatch(declaredFullName);
  const declaredTokens = nameTokenSet(declared);

  // 1) Explicit markers
  for (let i = 0; i < lines.length; i++) {
    const ln = normalizeNameForMatch(lines[i]);
    if (ln.includes("NOMBRES") || ln.includes("NOMBRE")) {
      const candidate = normalizeNameForMatch(lines[i + 1] || "");
      if (candidate.length >= 8) return candidate;
    }
    if (ln.includes("APELLIDOS") || ln.includes("APELLIDO")) {
      const candidate = normalizeNameForMatch(lines[i + 1] || "");
      if (candidate.length >= 8) return candidate;
    }
  }

  // 2) Best overlap line
  let best = null;
  let bestScore = 0;
  for (const raw of lines) {
    const candidate = normalizeNameForMatch(raw);
    if (candidate.length < 8 || candidate.length > 60) continue;
    if (
      /\b(REPUBLICA|CHILE|LICENCIA|CONDUCIR|CLASE|VENC|VENCIMIENTO|FECHA|DIRECCION|DOMICILIO|NACIONALIDAD)\b/.test(
        candidate,
      )
    ) {
      continue;
    }

    const tokens = nameTokenSet(candidate);
    if (tokens.size < 2) continue;

    let inter = 0;
    for (const t of declaredTokens) {
      if (tokens.has(t)) inter++;
    }
    const score = declaredTokens.size > 0 ? inter / declaredTokens.size : 0;
    if (score > bestScore) {
      bestScore = score;
      best = candidate;
    }
  }

  return best;
}

function validateLicenseClassForVehicle({ vehicleType, licenseClass }) {
  const vt = String(vehicleType || "").toLowerCase();
  const lc = normalizeLicenseClass(licenseClass);

  if (vt === "bicycle" || vt === "bicicleta") {
    return { ok: true, reason: null };
  }

  if (!lc) return { ok: false, reason: "no_license_class_detected" };

  if (vt === "motorcycle" || vt === "moto") {
    return { ok: lc.includes("C"), reason: "requires_class_c" };
  }

  if (vt === "car" || vt === "auto" || vt === "camioneta") {
    return { ok: lc.includes("B"), reason: "requires_class_b" };
  }

  // In this repo the heavy vehicle is 'truck'
  if (vt === "truck" || vt === "camion" || vt === "transporte_profesional") {
    const ok = lc.includes("A4") || lc.includes("A5");
    return { ok, reason: "requires_class_a4_or_a5" };
  }

  return { ok: false, reason: "unknown_vehicle_type" };
}

async function computeAntifraudSignalsFromStorageObject({
  bucketName,
  filePath,
}) {
  const bucket = admin.storage().bucket(bucketName);
  const tempLocalFile = path.join(os.tmpdir(), path.basename(filePath));

  await bucket.file(filePath).download({ destination: tempLocalFile });

  try {
    const { data, info } = await sharp(tempLocalFile)
      .rotate()
      .resize(160, 160, { fit: "inside", withoutEnlargement: true })
      .removeAlpha()
      .raw()
      .toBuffer({ resolveWithObject: true });

    const channels = info.channels;
    const pixels = info.width * info.height;
    if (!pixels || channels < 3) {
      return {
        ok: false,
        whiteRatio: null,
        luminanceVariance: null,
        luminanceMin: null,
        luminanceMax: null,
        errorCodes: ["antifraud_invalid_image"],
      };
    }

    let whiteCount = 0;
    let sumL = 0;
    let sumL2 = 0;
    let minL = 255;
    let maxL = 0;

    for (let i = 0; i < data.length; i += channels) {
      const r = data[i];
      const g = data[i + 1];
      const b = data[i + 2];
      const l = 0.2126 * r + 0.7152 * g + 0.0722 * b;

      sumL += l;
      sumL2 += l * l;
      if (l < minL) minL = l;
      if (l > maxL) maxL = l;

      if (r > 245 && g > 245 && b > 245) {
        whiteCount += 1;
      }
    }

    const meanL = sumL / pixels;
    const variance = Math.max(0, sumL2 / pixels - meanL * meanL);
    const whiteRatio = whiteCount / pixels;

    return {
      ok: true,
      whiteRatio,
      luminanceVariance: variance,
      luminanceMin: minL,
      luminanceMax: maxL,
      errorCodes: [],
    };
  } finally {
    if (fs.existsSync(tempLocalFile)) {
      fs.unlinkSync(tempLocalFile);
    }
  }
}

async function runVisionOcrForGcsUri({ gcsUri, mimeType }) {
  if (mimeType === "application/pdf") {
    const [result] = await visionClient.documentTextDetection({
      image: { source: { imageUri: gcsUri } },
    });
    return result?.fullTextAnnotation?.text || "";
  }

  const [result] = await visionClient.documentTextDetection({
    image: { source: { imageUri: gcsUri } },
  });
  return result?.fullTextAnnotation?.text || "";
}

exports.ocrVehicleVerificationLicenseOnUpload = onObjectFinalized(
  { region: STORAGE_REGION },
  async (event) => {
    const object = event.data;
    const filePath = object.name;
    const contentType = object.contentType || "";

    if (!filePath) return null;
    if (!filePath.startsWith("riders/")) return null;

    // Expected path:
    // riders/{uid}/documents/vehicle_verification/{vehicleType}/{requestId}/...license_front.*
    const segments = filePath.split("/").filter(Boolean);
    // 0 riders, 1 uid, 2 documents, 3 vehicle_verification, 4 vehicleType, 5 requestId, ... filename
    if (segments.length < 7) return null;
    if (segments[0] !== "riders") return null;
    if (segments[2] !== "documents") return null;
    if (segments[3] !== "vehicle_verification") return null;

    const riderId = segments[1];
    const vehicleType = segments[4];
    const requestId = segments[5];
    const fileName = segments[segments.length - 1];

    const isLicenseFront = fileName.toLowerCase().includes("license_front");
    if (!isLicenseFront) return null;

    const isPdf =
      contentType === "application/pdf" ||
      fileName.toLowerCase().endsWith(".pdf");
    const isImage = contentType.startsWith("image/");
    if (!isPdf && !isImage) return null;

    logger.info("[ocrVehicleVerification] Start", {
      riderId,
      vehicleType,
      requestId,
      filePath,
      contentType,
    });

    const userRef = admin.firestore().collection("users").doc(riderId);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      logger.warn("[ocrVehicleVerification] user not found", { riderId });
      return null;
    }

    const userData = userSnap.data() || {};
    const declaredRut = userData?.identity?.documentId;
    const declaredNormalized = normalizeRut(declaredRut);

    const reqRef = userRef
      .collection("vehicle_verification_requests")
      .doc(requestId);

    const gcsUri = `gs://${object.bucket}/${filePath}`;
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Mark processing
    await userRef.set(
      {
        riderProfile: {
          vehicles: {
            [vehicleType]: {
              ocr: {
                status: "processing",
                filePath,
                contentType,
                processedAt: now,
              },
            },
          },
        },
      },
      { merge: true },
    );

    try {
      const text = await runVisionOcrForGcsUri({
        gcsUri,
        mimeType: isPdf ? "application/pdf" : contentType,
      });

      const candidates = extractRutCandidates(text);
      const extractedRut = candidates.length > 0 ? candidates[0] : null;
      const extractedNormalized = normalizeRut(extractedRut);
      const dvValid = extractedRut ? isValidRutDv(extractedRut) : false;
      const matchDeclared =
        extractedNormalized && declaredNormalized
          ? extractedNormalized === declaredNormalized
          : false;

      const errors = [];
      let verificationStatus = "needs_review";

      if (!declaredRut) {
        errors.push("missing_declared_rut");
      }

      if (!extractedRut) {
        errors.push("rut_not_found");
        verificationStatus = "rejected";
      } else if (!dvValid) {
        errors.push("rut_dv_invalid");
        verificationStatus = "rejected";
      } else if (declaredRut && !matchDeclared) {
        errors.push("rut_mismatch_declared");
        verificationStatus = "needs_review";
      } else if (declaredRut && matchDeclared && dvValid) {
        verificationStatus = "approved";
      }

      await userRef.set(
        {
          riderProfile: {
            vehicles: {
              [vehicleType]: {
                ocr: {
                  status: verificationStatus,
                  filePath,
                  contentType,
                  processedAt: now,
                  extractedRut,
                  dvValid,
                  matchDeclared,
                  rutCandidates: candidates.slice(0, 5),
                  errorCodes: errors,
                },
                verification: {
                  status: verificationStatus,
                  verifiedAt: verificationStatus === "approved" ? now : null,
                  requestId,
                  mode: "ocr",
                },
              },
            },
          },
        },
        { merge: true },
      );

      // Update request doc if exists
      await reqRef.set(
        {
          updatedAt: now,
          status: verificationStatus,
          ocr: {
            extractedRut,
            dvValid,
            matchDeclared,
            errorCodes: errors,
            processedAt: now,
          },
        },
        { merge: true },
      );

      logger.info("[ocrVehicleVerification] Done", {
        riderId,
        vehicleType,
        requestId,
        verificationStatus,
      });
    } catch (error) {
      logger.error("[ocrVehicleVerification] OCR failed", {
        riderId,
        vehicleType,
        requestId,
        filePath,
        error,
      });

      await userRef.set(
        {
          riderProfile: {
            vehicles: {
              [vehicleType]: {
                ocr: {
                  status: "failed",
                  filePath,
                  contentType,
                  processedAt: now,
                  errorCodes: ["ocr_error"],
                },
              },
            },
          },
        },
        { merge: true },
      );

      await reqRef.set(
        {
          updatedAt: now,
          status: "failed",
          ocr: {
            errorCodes: ["ocr_error"],
            processedAt: now,
          },
        },
        { merge: true },
      );
    }

    return null;
  },
);

exports.processOrderRatings = onDocumentWritten(
  { document: "orders/{orderId}", region: STORAGE_REGION },
  async (event) => {
    const before =
      event.data && event.data.before.exists ? event.data.before.data() : null;
    const after =
      event.data && event.data.after.exists ? event.data.after.data() : null;

    if (!after) return;

    const afterConfirmed = after.confirmedByHero === true;
    if (!afterConfirmed) return;

    if (after.ratingStatsProcessed === true) return;

    // Only process when at least one rating field exists.
    // This allows processing even if confirmedByHero was set earlier by another update.
    const heroRating =
      typeof after.heroRating === "number" ? after.heroRating : null;
    const sellerRating =
      typeof after.sellerRating === "number" ? after.sellerRating : null;
    if (heroRating == null && sellerRating == null) return;

    const orderId = event.params.orderId;

    const riderId = after.rider?.assignedRiderId
      ? String(after.rider.assignedRiderId).trim()
      : "";

    let sellerHeroId = "";
    if (Array.isArray(after.sellerHeroIds)) {
      for (const raw of after.sellerHeroIds) {
        const id = raw != null ? String(raw).trim() : "";
        if (id) {
          sellerHeroId = id;
          break;
        }
      }
    } else if (typeof after.sellerHeroIds === "string") {
      sellerHeroId = after.sellerHeroIds.trim();
    }

    if (!sellerHeroId && Array.isArray(after.items)) {
      for (const item of after.items) {
        if (!item || typeof item !== "object") continue;
        const raw =
          item.sellerHeroIdSnapshot != null
            ? String(item.sellerHeroIdSnapshot).trim()
            : "";
        if (raw) {
          sellerHeroId = raw;
          break;
        }
      }
    }

    const db = admin.firestore();
    const orderRef = db.collection("orders").doc(orderId);

    await db.runTransaction(async (tx) => {
      const freshOrderSnap = await tx.get(orderRef);
      const freshOrder = freshOrderSnap.exists ? freshOrderSnap.data() : null;
      if (!freshOrder) return;
      if (freshOrder.ratingStatsProcessed === true) return;
      if (freshOrder.confirmedByHero !== true) return;

      const freshHeroRating =
        typeof freshOrder.heroRating === "number"
          ? freshOrder.heroRating
          : null;
      const freshSellerRating =
        typeof freshOrder.sellerRating === "number"
          ? freshOrder.sellerRating
          : null;
      if (freshHeroRating == null && freshSellerRating == null) return;

      function applyNewAverage(currentAvg, currentCount, newValue) {
        const safeAvg = typeof currentAvg === "number" ? currentAvg : 0;
        const safeCount = typeof currentCount === "number" ? currentCount : 0;
        const nextCount = safeCount + 1;
        const nextAvg = (safeAvg * safeCount + newValue) / nextCount;
        return { nextAvg, nextCount };
      }

      const riderRef =
        riderId && freshHeroRating != null
          ? db.collection("users").doc(riderId)
          : null;
      const sellerRef =
        sellerHeroId && freshSellerRating != null
          ? db.collection("users").doc(sellerHeroId)
          : null;

      const riderSnap = riderRef ? await tx.get(riderRef) : null;
      const sellerSnap = sellerRef ? await tx.get(sellerRef) : null;

      if (riderRef && riderSnap && riderSnap.exists) {
        const riderData = riderSnap.data() || {};
        const rp =
          riderData.riderProfile && typeof riderData.riderProfile === "object"
            ? riderData.riderProfile
            : {};
        const { nextAvg, nextCount } = applyNewAverage(
          rp.rating,
          rp.totalRatings,
          freshHeroRating,
        );
        tx.update(riderRef, {
          "riderProfile.rating": nextAvg,
          "riderProfile.totalRatings": nextCount,
        });
      }

      if (sellerRef && sellerSnap && sellerSnap.exists) {
        const sellerData = sellerSnap.data() || {};
        const hp =
          sellerData.heroProfile && typeof sellerData.heroProfile === "object"
            ? sellerData.heroProfile
            : {};
        const { nextAvg, nextCount } = applyNewAverage(
          hp.rating,
          hp.totalRatings,
          freshSellerRating,
        );
        tx.update(sellerRef, {
          "heroProfile.rating": nextAvg,
          "heroProfile.totalRatings": nextCount,
        });
      }

      tx.update(orderRef, {
        ratingStatsProcessed: true,
        ratingStatsProcessedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  },
);

/**
 * Trigger: Send notification when a new chat message is created.
 * Notifies all participants except the sender.
 */
exports.notifyNewChatMessage = onDocumentWritten(
  { document: "chats/{chatId}/messages/{messageId}", region: STORAGE_REGION },
  async (event) => {
    const before =
      event.data && event.data.before.exists ? event.data.before.data() : null;
    const after =
      event.data && event.data.after.exists ? event.data.after.data() : null;

    // Only on create
    if (!after || before) {
      return;
    }

    const chatId = event.params.chatId;
    const messageId = event.params.messageId;
    const senderId = after.senderId;
    const text = after.text;

    if (!chatId || !senderId) return;

    // Load chat to get participants and context
    const chatSnap = await admin
      .firestore()
      .collection("chats")
      .doc(chatId)
      .get();
    if (!chatSnap.exists) return;
    const chat = chatSnap.data() || {};

    // Sender display name
    let senderName = "Usuario";
    try {
      const senderSnap = await admin
        .firestore()
        .collection("users")
        .doc(senderId)
        .get();
      if (senderSnap.exists) {
        const senderData = senderSnap.data() || {};
        const identity = senderData.identity || {};
        const firstName =
          typeof identity.firstName === "string"
            ? identity.firstName.trim()
            : "";
        const lastName =
          typeof identity.lastName === "string" ? identity.lastName.trim() : "";
        const fullName = `${firstName} ${lastName}`.trim();
        if (fullName) {
          senderName = fullName;
        } else if (
          typeof senderData.fullName === "string" &&
          senderData.fullName.trim()
        ) {
          senderName = senderData.fullName.trim();
        } else if (
          typeof senderData.displayName === "string" &&
          senderData.displayName.trim()
        ) {
          senderName = senderData.displayName.trim();
        }
      }
    } catch (_) {
      // ignore
    }

    const typeRaw =
      typeof chat.type === "string" ? chat.type.toLowerCase() : "";
    const chatLabel = typeRaw.includes("rider") ? "Rider" : "Hero";

    const orderIdRaw =
      typeof chat.orderId === "string" ? chat.orderId.trim() : "";
    const shortOrderId = orderIdRaw
      ? orderIdRaw.length > 8
        ? orderIdRaw.substring(0, 8)
        : orderIdRaw
      : "";

    const participantIds = Array.isArray(chat.participantIds)
      ? chat.participantIds.map((x) => String(x)).filter(Boolean)
      : [];

    const recipients = participantIds.filter((id) => id && id !== senderId);
    if (recipients.length === 0) return;

    const preview = typeof text === "string" ? text.trim() : "";
    const trimmedText =
      preview.length > 140 ? `${preview.substring(0, 137)}...` : preview;
    const body = trimmedText
      ? `${senderName}: ${trimmedText}`
      : `${senderName}: Nuevo mensaje`;

    const title = shortOrderId
      ? `Nuevo mensaje (${chatLabel}) • Pedido #${shortOrderId}`
      : `Nuevo mensaje (${chatLabel})`;

    await sendNotificationToUsers(
      recipients,
      {
        title,
        body,
      },
      {
        type: "chat_message",
        action: "open_chat",
        chatId,
        orderId: chat.orderId || "",
        offerId: chat.offerId || "",
        messageId,
        priority: "high",
      },
    );
  },
);

exports.ocrLicenseVerificationOnUpload = onObjectFinalized(
  { region: STORAGE_REGION },
  async (event) => {
    const object = event.data;
    const filePath = object.name;
    const contentType = object.contentType || "";

    if (!filePath) return null;

    // Expected path:
    // users/{uid}/documents/license_verification/{requestId}/...license_front.*
    const segments = filePath.split("/").filter(Boolean);
    if (segments.length < 6) return null;
    if (segments[0] !== "users") return null;
    if (segments[2] !== "documents") return null;
    if (segments[3] !== "license_verification") return null;

    const userId = segments[1];
    const requestId = segments[4];
    const fileName = segments[segments.length - 1];

    const isFront = fileName.toLowerCase().includes("license_front");
    if (!isFront) return null;

    const isPdf =
      contentType === "application/pdf" ||
      fileName.toLowerCase().endsWith(".pdf");
    const isImage = contentType.startsWith("image/");
    if (!isPdf && !isImage) return null;

    // Strict: no PDFs
    if (isPdf) {
      logger.warn("[ocrLicenseVerification] PDF not allowed", {
        userId,
        requestId,
        filePath,
      });
      const userRef = admin.firestore().collection("users").doc(userId);
      const reqRef = userRef
        .collection("license_verification_requests")
        .doc(requestId);
      const reqSnap = await reqRef.get();
      const reqData = reqSnap.exists ? reqSnap.data() || {} : {};
      const requestedVehicleTypeRaw = reqData?.declared?.vehicleType;
      const requestedVehicleType =
        typeof requestedVehicleTypeRaw === "string" &&
        ["bicycle", "motorcycle", "car", "truck"].includes(
          requestedVehicleTypeRaw.trim().toLowerCase(),
        )
          ? requestedVehicleTypeRaw.trim().toLowerCase()
          : null;
      const now = admin.firestore.FieldValue.serverTimestamp();

      await userRef.set(
        {
          licenseVerification: {
            status: "rejected",
            requestId,
            mode: "ocr",
            updatedAt: now,
            ocr: {
              filePath,
              contentType,
              processedAt: now,
              errorCodes: ["pdf_not_allowed"],
            },
          },
          ...(requestedVehicleType
            ? {
                riderProfile: {
                  vehicles: {
                    [requestedVehicleType]: {
                      licenseVerification: {
                        status: "rejected",
                        requestId,
                        mode: "ocr",
                        updatedAt: now,
                        ocr: {
                          filePath,
                          contentType,
                          processedAt: now,
                          errorCodes: ["pdf_not_allowed"],
                        },
                      },
                    },
                  },
                },
              }
            : {}),
        },
        { merge: true },
      );

      await reqRef.set(
        {
          updatedAt: now,
          status: "rejected",
          ocr: {
            errorCodes: ["pdf_not_allowed"],
            processedAt: now,
          },
        },
        { merge: true },
      );

      return null;
    }

    logger.info("[ocrLicenseVerification] Start", {
      userId,
      requestId,
      filePath,
      contentType,
    });

    const userRef = admin.firestore().collection("users").doc(userId);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      logger.warn("[ocrLicenseVerification] user not found", { userId });
      return null;
    }

    const userData = userSnap.data() || {};
    const reqRef = userRef
      .collection("license_verification_requests")
      .doc(requestId);
    const reqSnap = await reqRef.get();
    const reqData = reqSnap.exists ? reqSnap.data() || {} : {};

    const normalizeVehicleType = (raw) => {
      if (typeof raw !== "string") return null;
      const value = raw.trim().toLowerCase();
      return ["bicycle", "motorcycle", "car", "truck"].includes(value)
        ? value
        : null;
    };

    const requestedVehicleType = normalizeVehicleType(
      reqData?.declared?.vehicleType,
    );
    const fallbackVehicleType = normalizeVehicleType(
      userData?.riderProfile?.activeVehicleType ||
        userData?.riderProfile?.vehicle?.type,
    );
    const vehicleType = requestedVehicleType || fallbackVehicleType;

    const perVehicleLicensePatch = (payload) =>
      vehicleType
        ? {
            riderProfile: {
              vehicles: {
                [vehicleType]: {
                  licenseVerification: payload,
                },
              },
            },
          }
        : {};

    const roles = Array.isArray(userData.roles) ? userData.roles : [];
    const isRider = roles.includes("rider");
    if (!isRider) {
      logger.warn("[ocrLicenseVerification] rejected: not rider", {
        userId,
        requestId,
      });
      const now = admin.firestore.FieldValue.serverTimestamp();

      await userRef.set(
        {
          licenseVerification: {
            status: "rejected",
            requestId,
            mode: "ocr",
            updatedAt: now,
            ocr: {
              filePath,
              contentType,
              processedAt: now,
              errorCodes: ["not_rider"],
            },
          },
          ...perVehicleLicensePatch({
            status: "rejected",
            requestId,
            mode: "ocr",
            updatedAt: now,
            ocr: {
              filePath,
              contentType,
              processedAt: now,
              errorCodes: ["not_rider"],
            },
          }),
        },
        { merge: true },
      );

      await reqRef.set(
        {
          updatedAt: now,
          status: "rejected",
          ocr: {
            errorCodes: ["not_rider"],
            processedAt: now,
          },
        },
        { merge: true },
      );

      return null;
    }

    const declaredRut = userData?.identity?.documentId;
    const declaredNormalized = normalizeRut(declaredRut);
    const declaredFullName =
      `${userData?.identity?.firstName || ""} ${userData?.identity?.lastName || ""}`.trim();
    const declaredFullNameNorm = normalizeNameForMatch(declaredFullName);

    const gcsUri = `gs://${object.bucket}/${filePath}`;
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Mark processing
    await userRef.set(
      {
        licenseVerification: {
          status: "processing",
          requestId,
          mode: "ocr",
          updatedAt: now,
        },
        ...perVehicleLicensePatch({
          status: "processing",
          requestId,
          mode: "ocr",
          updatedAt: now,
        }),
      },
      { merge: true },
    );

    await reqRef.set(
      {
        updatedAt: now,
        status: "processing",
        declared: {
          rut: declaredNormalized,
          fullName: declaredFullName,
          vehicleType,
        },
      },
      { merge: true },
    );

    try {
      const text = await runVisionOcrForGcsUri({
        gcsUri,
        mimeType: isPdf ? "application/pdf" : contentType,
      });

      const ocrText = String(text || "");
      const documentDetected = ocrText.trim().length >= 40;
      const keywordResult = countLicenseKeywords(ocrText);
      const keywordsOk = keywordResult.hits >= 2;

      const candidates = extractRutCandidates(ocrText);
      const extractedRutRaw = candidates.length > 0 ? candidates[0] : null;
      const extractedRut = extractedRutRaw
        ? normalizeRut(extractedRutRaw)
        : null;
      const strictRutOk = extractedRut
        ? /^\d{7,8}-[0-9K]$/.test(extractedRut)
        : false;
      const dvValid = extractedRut ? isValidRutDv(extractedRut) : false;
      const matchDeclared =
        extractedRut && declaredNormalized
          ? extractedRut === declaredNormalized
          : false;

      const extractedLicenseClass = extractLicenseClass(ocrText);
      const expiryIso = extractExpiryDate(ocrText);
      const expired = expiryIso
        ? new Date(expiryIso).getTime() < Date.now()
        : true;

      const extractedName = extractNameHeuristic({
        ocrText,
        declaredFullName: declaredFullNameNorm,
      });
      const nameRatio = extractedName
        ? nameMatchRatio({
            declaredFullName: declaredFullNameNorm,
            extractedFullName: extractedName,
          })
        : 0;
      const nameMatchOk = extractedName ? nameRatio >= 0.7 : false;

      const classCheck = validateLicenseClassForVehicle({
        vehicleType,
        licenseClass: extractedLicenseClass,
      });

      const antifraud = await computeAntifraudSignalsFromStorageObject({
        bucketName: object.bucket,
        filePath,
      });

      const whiteRatio =
        typeof antifraud.whiteRatio === "number" ? antifraud.whiteRatio : null;
      const variance =
        typeof antifraud.luminanceVariance === "number"
          ? antifraud.luminanceVariance
          : null;

      const thresholds = {
        maxWhiteRatio: 0.85,
        minVariance: 250,
      };

      const textureValid =
        antifraud.ok &&
        whiteRatio !== null &&
        variance !== null &&
        whiteRatio <= thresholds.maxWhiteRatio &&
        variance >= thresholds.minVariance;

      const score =
        (documentDetected ? 20 : 0) +
        (keywordsOk ? 15 : 0) +
        (dvValid ? 20 : 0) +
        (matchDeclared ? 20 : 0) +
        (nameMatchOk ? 15 : 0) +
        (classCheck.ok ? 5 : 0) +
        (!expired ? 5 : 0) +
        (textureValid ? 20 : 0);

      const suspiciousAttempt = score < 80;
      const errors = [];

      if (!documentDetected) errors.push("document_not_detected");
      if (!keywordsOk) errors.push("missing_keywords");
      if (!declaredRut) errors.push("missing_declared_rut");
      if (!extractedRut) errors.push("rut_not_found");
      if (extractedRut && !strictRutOk) errors.push("rut_format_invalid");
      if (extractedRut && strictRutOk && !dvValid)
        errors.push("rut_dv_invalid");
      if (declaredRut && extractedRut && dvValid && !matchDeclared)
        errors.push("rut_mismatch_declared");

      if (!extractedName) errors.push("name_not_found");
      if (extractedName && !nameMatchOk) errors.push("name_mismatch_declared");

      if (!extractedLicenseClass && vehicleType !== "bicycle")
        errors.push("license_class_not_found");
      if (expired) errors.push("license_expired");
      if (!classCheck.ok) errors.push(classCheck.reason);

      if (!textureValid) errors.push("antifraud_texture_invalid");
      if (suspiciousAttempt) errors.push("suspicious_low_score");
      if (
        Array.isArray(antifraud.errorCodes) &&
        antifraud.errorCodes.length > 0
      ) {
        errors.push(...antifraud.errorCodes);
      }

      const verificationStatus =
        documentDetected &&
        keywordsOk &&
        extractedRut &&
        strictRutOk &&
        dvValid &&
        declaredRut &&
        matchDeclared &&
        extractedName &&
        nameMatchOk &&
        !expired &&
        classCheck.ok &&
        textureValid &&
        !suspiciousAttempt
          ? "approved"
          : "rejected";

      await userRef.set(
        {
          licenseVerification: {
            status: verificationStatus,
            requestId,
            mode: "ocr",
            verifiedAt: verificationStatus === "approved" ? now : null,
            ocr: {
              filePath,
              contentType,
              processedAt: now,
              extractedRut,
              dvValid,
              matchDeclared,
              keywordHits: keywordResult.hits,
              keywordMatched: keywordResult.matched,
              documentDetected,
              extractedName,
              nameMatchRatio: nameRatio,
              licenseClass: extractedLicenseClass,
              expiryDate: expiryIso,
              vehicleType,
              classOk: classCheck.ok,
              antifraud: {
                score,
                suspiciousAttempt,
                whiteRatio,
                luminanceVariance: variance,
                luminanceMin: antifraud.luminanceMin ?? null,
                luminanceMax: antifraud.luminanceMax ?? null,
                thresholds,
                textureValid,
              },
              errorCodes: errors,
            },
          },
          ...perVehicleLicensePatch({
            status: verificationStatus,
            requestId,
            mode: "ocr",
            verifiedAt: verificationStatus === "approved" ? now : null,
            ocr: {
              filePath,
              contentType,
              processedAt: now,
              extractedRut,
              dvValid,
              matchDeclared,
              keywordHits: keywordResult.hits,
              keywordMatched: keywordResult.matched,
              documentDetected,
              extractedName,
              nameMatchRatio: nameRatio,
              licenseClass: extractedLicenseClass,
              expiryDate: expiryIso,
              vehicleType,
              classOk: classCheck.ok,
              antifraud: {
                score,
                suspiciousAttempt,
                whiteRatio,
                luminanceVariance: variance,
                luminanceMin: antifraud.luminanceMin ?? null,
                luminanceMax: antifraud.luminanceMax ?? null,
                thresholds,
                textureValid,
              },
              errorCodes: errors,
            },
          }),
        },
        { merge: true },
      );

      await reqRef.set(
        {
          updatedAt: now,
          status: verificationStatus,
          score,
          ocr: {
            extractedRut,
            dvValid,
            matchDeclared,
            extractedName,
            nameMatchRatio: nameRatio,
            licenseClass: extractedLicenseClass,
            expiryDate: expiryIso,
            vehicleType,
            classOk: classCheck.ok,
            keywordHits: keywordResult.hits,
            keywordMatched: keywordResult.matched,
            errorCodes: errors,
            processedAt: now,
          },
        },
        { merge: true },
      );

      if (verificationStatus !== "approved") {
        await userRef.collection("security_events").add({
          type: "license_verification_failed",
          requestId,
          vehicleType,
          score,
          errorCodes: errors,
          createdAt: now,
        });
      }

      logger.info("[ocrLicenseVerification] Done", {
        userId,
        requestId,
        verificationStatus,
      });
    } catch (error) {
      logger.error("[ocrLicenseVerification] OCR failed", {
        userId,
        requestId,
        filePath,
        error,
      });

      await userRef.set(
        {
          licenseVerification: {
            status: "failed",
            requestId,
            mode: "ocr",
            ocr: {
              filePath,
              contentType,
              processedAt: now,
              errorCodes: ["ocr_error"],
            },
          },
          ...perVehicleLicensePatch({
            status: "failed",
            requestId,
            mode: "ocr",
            ocr: {
              filePath,
              contentType,
              processedAt: now,
              errorCodes: ["ocr_error"],
            },
          }),
        },
        { merge: true },
      );

      await reqRef.set(
        {
          updatedAt: now,
          status: "failed",
          ocr: {
            errorCodes: ["ocr_error"],
            processedAt: now,
          },
        },
        { merge: true },
      );

      await userRef.collection("security_events").add({
        type: "license_verification_failed",
        requestId,
        score: 0,
        errorCodes: ["ocr_error"],
        createdAt: now,
      });
    }

    return null;
  },
);

exports.ocrRutVerificationOnUpload = onObjectFinalized(
  { region: STORAGE_REGION },
  async (event) => {
    const object = event.data;
    const filePath = object.name;
    const contentType = object.contentType || "";

    if (!filePath) return null;

    // Expected path:
    // users/{uid}/documents/rut_verification/{requestId}/...id_front.*
    const segments = filePath.split("/").filter(Boolean);
    // 0 users, 1 uid, 2 documents, 3 rut_verification, 4 requestId, ... filename
    if (segments.length < 6) return null;
    if (segments[0] !== "users") return null;
    if (segments[2] !== "documents") return null;
    if (segments[3] !== "rut_verification") return null;

    const userId = segments[1];
    const requestId = segments[4];
    const fileName = segments[segments.length - 1];

    const isFront = fileName.toLowerCase().includes("id_front");
    if (!isFront) return null;

    const isPdf =
      contentType === "application/pdf" ||
      fileName.toLowerCase().endsWith(".pdf");
    const isImage = contentType.startsWith("image/");
    if (!isPdf && !isImage) return null;
    if (isPdf) {
      logger.warn("[ocrRutVerification] PDF not allowed for strict mode", {
        userId,
        requestId,
        filePath,
      });
      const userRef = admin.firestore().collection("users").doc(userId);
      const reqRef = userRef
        .collection("rut_verification_requests")
        .doc(requestId);
      const now = admin.firestore.FieldValue.serverTimestamp();

      await userRef.set(
        {
          rutVerification: {
            status: "rejected",
            requestId,
            mode: "ocr",
            updatedAt: now,
            ocr: {
              filePath,
              contentType,
              processedAt: now,
              errorCodes: ["pdf_not_allowed"],
            },
          },
        },
        { merge: true },
      );

      await reqRef.set(
        {
          updatedAt: now,
          status: "rejected",
          ocr: {
            errorCodes: ["pdf_not_allowed"],
            processedAt: now,
          },
        },
        { merge: true },
      );

      return null;
    }

    logger.info("[ocrRutVerification] Start", {
      userId,
      requestId,
      filePath,
      contentType,
    });

    const userRef = admin.firestore().collection("users").doc(userId);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      logger.warn("[ocrRutVerification] user not found", { userId });
      return null;
    }

    const userData = userSnap.data() || {};
    const declaredRut = userData?.identity?.documentId;
    const declaredNormalized = normalizeRut(declaredRut);

    const reqRef = userRef
      .collection("rut_verification_requests")
      .doc(requestId);
    const gcsUri = `gs://${object.bucket}/${filePath}`;
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Mark processing
    await userRef.set(
      {
        rutVerification: {
          status: "processing",
          requestId,
          mode: "ocr",
          updatedAt: now,
        },
      },
      { merge: true },
    );

    await reqRef.set(
      {
        updatedAt: now,
        status: "processing",
      },
      { merge: true },
    );

    try {
      const text = await runVisionOcrForGcsUri({
        gcsUri,
        mimeType: isPdf ? "application/pdf" : contentType,
      });

      const ocrText = String(text || "");
      const documentDetected = ocrText.trim().length >= 20;
      const keywordResult = countRutKeywords(ocrText);
      const keywordsOk = keywordResult.hits >= 2;

      const candidates = extractRutCandidates(ocrText);
      const extractedRutRaw = candidates.length > 0 ? candidates[0] : null;
      const extractedRut = extractedRutRaw
        ? normalizeRut(extractedRutRaw)
        : null;
      const strictRutOk = extractedRut
        ? /^\d{7,8}-[0-9K]$/.test(extractedRut)
        : false;
      const dvValid = extractedRut ? isValidRutDv(extractedRut) : false;
      const matchDeclared =
        extractedRut && declaredNormalized
          ? extractedRut === declaredNormalized
          : false;

      const antifraud = await computeAntifraudSignalsFromStorageObject({
        bucketName: object.bucket,
        filePath,
      });

      const whiteRatio =
        typeof antifraud.whiteRatio === "number" ? antifraud.whiteRatio : null;
      const variance =
        typeof antifraud.luminanceVariance === "number"
          ? antifraud.luminanceVariance
          : null;

      const thresholds = {
        maxWhiteRatio: 0.85,
        minVariance: 250,
      };

      const textureValid =
        antifraud.ok &&
        whiteRatio !== null &&
        variance !== null &&
        whiteRatio <= thresholds.maxWhiteRatio &&
        variance >= thresholds.minVariance;

      const score =
        (documentDetected ? 30 : 0) +
        (keywordsOk ? 20 : 0) +
        (dvValid ? 30 : 0) +
        (textureValid ? 20 : 0);

      const suspiciousAttempt = score < 80;
      const errors = [];

      if (!documentDetected) errors.push("document_not_detected");
      if (!keywordsOk) errors.push("missing_keywords");
      if (!declaredRut) errors.push("missing_declared_rut");
      if (!extractedRut) errors.push("rut_not_found");
      if (extractedRut && !strictRutOk) errors.push("rut_format_invalid");
      if (extractedRut && strictRutOk && !dvValid)
        errors.push("rut_dv_invalid");
      if (declaredRut && extractedRut && dvValid && !matchDeclared)
        errors.push("rut_mismatch_declared");
      if (!textureValid) errors.push("antifraud_texture_invalid");
      if (suspiciousAttempt) errors.push("suspicious_low_score");
      if (
        Array.isArray(antifraud.errorCodes) &&
        antifraud.errorCodes.length > 0
      ) {
        errors.push(...antifraud.errorCodes);
      }

      const verificationStatus =
        documentDetected &&
        keywordsOk &&
        extractedRut &&
        strictRutOk &&
        dvValid &&
        declaredRut &&
        matchDeclared &&
        textureValid &&
        !suspiciousAttempt
          ? "approved"
          : "rejected";

      await userRef.set(
        {
          rutVerification: {
            status: verificationStatus,
            requestId,
            mode: "ocr",
            verifiedAt: verificationStatus === "approved" ? now : null,
            ocr: {
              filePath,
              contentType,
              processedAt: now,
              extractedRut,
              dvValid,
              matchDeclared,
              rutCandidates: candidates.slice(0, 5),
              keywordHits: keywordResult.hits,
              keywordMatched: keywordResult.matched,
              documentDetected,
              antifraud: {
                score,
                suspiciousAttempt,
                whiteRatio,
                luminanceVariance: variance,
                luminanceMin: antifraud.luminanceMin ?? null,
                luminanceMax: antifraud.luminanceMax ?? null,
                thresholds,
                textureValid,
              },
              errorCodes: errors,
            },
          },
        },
        { merge: true },
      );

      await reqRef.set(
        {
          updatedAt: now,
          status: verificationStatus,
          ocr: {
            extractedRut,
            dvValid,
            matchDeclared,
            errorCodes: errors,
            processedAt: now,
          },
        },
        { merge: true },
      );

      logger.info("[ocrRutVerification] Done", {
        userId,
        requestId,
        verificationStatus,
      });
    } catch (error) {
      logger.error("[ocrRutVerification] OCR failed", {
        userId,
        requestId,
        filePath,
        error,
      });

      await userRef.set(
        {
          rutVerification: {
            status: "failed",
            requestId,
            mode: "ocr",
            ocr: {
              filePath,
              contentType,
              processedAt: now,
              errorCodes: ["ocr_error"],
            },
          },
        },
        { merge: true },
      );

      await reqRef.set(
        {
          updatedAt: now,
          status: "failed",
          ocr: {
            errorCodes: ["ocr_error"],
            processedAt: now,
          },
        },
        { merge: true },
      );
    }

    return null;
  },
);

/**
 * Trigger: Notify hero when rider completes a pickup stop
 * Uses orders/{orderId}.pickupProgress.currentStopIndex (0-based) changes.
 */
exports.notifyPickupStopProgress = onDocumentWritten(
  { document: "orders/{orderId}", region: STORAGE_REGION },
  async (event) => {
    const before =
      event.data && event.data.before.exists ? event.data.before.data() : null;
    const after =
      event.data && event.data.after.exists ? event.data.after.data() : null;

    if (!after || !before) {
      return;
    }

    const orderId = event.params.orderId;
    const heroId = after.heroId;

    const beforeIndexRaw =
      before.pickupProgress &&
      typeof before.pickupProgress.currentStopIndex !== "undefined"
        ? before.pickupProgress.currentStopIndex
        : null;
    const afterIndexRaw =
      after.pickupProgress &&
      typeof after.pickupProgress.currentStopIndex !== "undefined"
        ? after.pickupProgress.currentStopIndex
        : null;

    if (afterIndexRaw === null || typeof afterIndexRaw === "undefined") {
      return;
    }

    // Convert to number and ensure it's a progress forward.
    const beforeIndex =
      beforeIndexRaw === null || typeof beforeIndexRaw === "undefined"
        ? -1
        : Number(beforeIndexRaw);
    const afterIndex = Number(afterIndexRaw);

    if (!Number.isFinite(afterIndex)) {
      return;
    }

    // Only notify when index increases.
    if (afterIndex <= beforeIndex) {
      return;
    }

    const totalStops = Array.isArray(after.pickupStops)
      ? after.pickupStops.length
      : 0;
    if (totalStops <= 0) {
      return;
    }

    const humanIndex = Math.min(Math.max(afterIndex + 1, 1), totalStops);

    console.log(
      `Order ${orderId} pickup progress: ${beforeIndex} -> ${afterIndex} (stop ${humanIndex}/${totalStops})`,
    );

    const isLastStop = humanIndex >= totalStops;
    const ordinal =
      humanIndex === 1
        ? "primer"
        : humanIndex === 2
          ? "segundo"
          : humanIndex === 3
            ? "tercer"
            : `${humanIndex}°`;
    const body = isLastStop
      ? "El rider ya está en el último punto de recogida. Te avisaremos cuando vaya en camino a la entrega."
      : `El rider ya está en el ${ordinal} punto de recogida. Te avisaremos cuando vaya en camino.`;

    await sendNotificationToUsers(
      heroId,
      {
        title: "📦 Tu pedido avanza",
        body,
      },
      {
        type: "pickup_progress",
        action: "open_order",
        orderId,
        pickupStopIndex: String(afterIndex),
        pickupStopsCount: String(totalStops),
        priority: "high",
      },
    );
  },
);

function getIsoWeekKey(date) {
  const d = new Date(
    Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()),
  );
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNo = Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
  const year = d.getUTCFullYear();
  const week = String(weekNo).padStart(2, "0");
  return `${year}-W${week}`;
}

exports.syncRiderStatsOnOrderWrite = onDocumentWritten(
  { document: "orders/{orderId}", region: STORAGE_REGION },
  async (event) => {
    const before =
      event.data && event.data.before.exists ? event.data.before.data() : null;
    const after =
      event.data && event.data.after.exists ? event.data.after.data() : null;

    if (!after) {
      return;
    }

    const beforeStatus =
      before && typeof before.status === "string" ? before.status : null;
    const afterStatus = typeof after.status === "string" ? after.status : null;

    if (beforeStatus === afterStatus) {
      return;
    }

    const riderId =
      (after.rider && after.rider.assignedRiderId) ||
      (before && before.rider && before.rider.assignedRiderId) ||
      null;

    if (!riderId) {
      return;
    }

    const deliveryFee =
      typeof after.deliveryFee === "number" ? after.deliveryFee : 0;
    const tipAfterRaw = typeof after.tip === "number" ? after.tip : 0;
    const tipBeforeRaw =
      before && typeof before.tip === "number" ? before.tip : 0;
    const statsRef = admin.firestore().collection("rider_stats").doc(riderId);
    const inc = admin.firestore.FieldValue.increment;

    const currentWeekKey = getIsoWeekKey(new Date());

    const toCounters = (status) => {
      switch ((status || "").toLowerCase()) {
        case "delivered":
          return { deliveredTrips: 1, canceledTrips: 0, failedTrips: 0 };
        case "canceled":
        case "cancelled":
          return { deliveredTrips: 0, canceledTrips: 1, failedTrips: 0 };
        case "failed":
          return { deliveredTrips: 0, canceledTrips: 0, failedTrips: 1 };
        default:
          return { deliveredTrips: 0, canceledTrips: 0, failedTrips: 0 };
      }
    };

    const isRiderUnassignToQueue = () => {
      const b = (beforeStatus || "").toLowerCase();
      const a = (afterStatus || "").toLowerCase();
      if (!(b === "assigned" && a === "queued")) return false;

      const beforeAssigned =
        before &&
        before.rider &&
        typeof before.rider.assignedRiderId === "string"
          ? before.rider.assignedRiderId
          : null;
      const afterAssigned =
        after && after.rider && typeof after.rider.assignedRiderId === "string"
          ? after.rider.assignedRiderId
          : null;

      const beforeHas = !!(beforeAssigned && beforeAssigned.trim().length > 0);
      const afterHas = !!(afterAssigned && afterAssigned.trim().length > 0);
      return beforeHas && !afterHas;
    };

    const tipIfDelivered = (status, tip) => {
      return (status || "").toLowerCase() === "delivered" ? tip : 0;
    };

    const beforeC = toCounters(beforeStatus);
    const afterC = toCounters(afterStatus);

    const deltaDelivered = afterC.deliveredTrips - beforeC.deliveredTrips;
    let deltaCanceled = afterC.canceledTrips - beforeC.canceledTrips;
    const deltaFailed = afterC.failedTrips - beforeC.failedTrips;

    // Rider unassign (assigned -> queued) should count as a cancellation for rider stats.
    if (isRiderUnassignToQueue()) {
      deltaCanceled += 1;
    }

    const beforeTip = tipIfDelivered(beforeStatus, tipBeforeRaw);
    const afterTip = tipIfDelivered(afterStatus, tipAfterRaw);
    const deltaTips = afterTip - beforeTip;

    const updates = {
      riderId,
      deliveredTrips: inc(deltaDelivered),
      canceledTrips: inc(deltaCanceled),
      failedTrips: inc(deltaFailed),
      tips: inc(deltaTips),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (deltaDelivered !== 0) {
      updates.totalEarnings = inc(deltaDelivered * deliveryFee);
      updates.totalTrips = inc(deltaDelivered);

      const deliveredAt =
        after.timestamps &&
        after.timestamps.deliveredAt &&
        typeof after.timestamps.deliveredAt.toDate === "function"
          ? after.timestamps.deliveredAt.toDate()
          : new Date();
      const deliveredWeekKey = getIsoWeekKey(deliveredAt);

      updates.weekKey = currentWeekKey;

      if (deliveredWeekKey === currentWeekKey) {
        updates.weeklyEarnings = inc(deltaDelivered * deliveryFee);
        updates.weeklyTrips = inc(deltaDelivered);
      }
    }

    if (deltaTips !== 0) {
      updates.totalEarnings = inc(deltaTips);

      const deliveredAtForTips =
        afterStatus && afterStatus.toLowerCase() === "delivered"
          ? after.timestamps &&
            after.timestamps.deliveredAt &&
            typeof after.timestamps.deliveredAt.toDate === "function"
            ? after.timestamps.deliveredAt.toDate()
            : new Date()
          : new Date();

      const tipsWeekKey = getIsoWeekKey(deliveredAtForTips);

      updates.weekKey = currentWeekKey;
      if (tipsWeekKey === currentWeekKey) {
        updates.weeklyEarnings = inc(deltaTips);
      }
    }

    const deltaCompleted = deltaDelivered + deltaCanceled + deltaFailed;
    if (deltaCompleted !== 0) {
      updates.completedTrips = inc(deltaCompleted);
    }

    await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(statsRef);
      const existingWeekKey =
        snap.exists && snap.data() && typeof snap.data().weekKey === "string"
          ? snap.data().weekKey
          : null;

      if (existingWeekKey !== currentWeekKey) {
        tx.set(
          statsRef,
          {
            weekKey: currentWeekKey,
            weeklyEarnings: 0,
            weeklyTrips: 0,
          },
          { merge: true },
        );
      }

      tx.set(statsRef, updates, { merge: true });
    });
  },
);

function buildDownloadUrl(bucketName, filePath) {
  const encodedPath = encodeURIComponent(filePath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedPath}?alt=media`;
}

// ==========================================
// PUSH NOTIFICATIONS (FCM)
// ==========================================

/**
 * Helper: Send FCM notification to user(s)
 * @param {string|string[]} userIds - Single user ID or array of user IDs
 * @param {Object} notification - { title, body, imageUrl? }
 * @param {Object} data - Custom data payload
 * @returns {Promise<void>}
 */
async function sendNotificationToUsers(userIds, notification, data = {}) {
  try {
    const ids = Array.isArray(userIds) ? userIds : [userIds];
    const userTokensMap = new Map(); // Map userId -> tokens[]

    // Get FCM tokens for all users
    for (const userId of ids) {
      const userDoc = await admin
        .firestore()
        .collection("users")
        .doc(userId)
        .get();
      if (userDoc.exists) {
        const userData = userDoc.data();
        const tokens = [];

        if (userData.fcmTokens && Array.isArray(userData.fcmTokens)) {
          tokens.push(...userData.fcmTokens);
        }

        if (userData.fcmToken && typeof userData.fcmToken === "string") {
          const t = userData.fcmToken.trim();
          if (t) tokens.push(t);
        }

        const uniqueTokens = [...new Set(tokens.filter(Boolean))];
        if (uniqueTokens.length > 0) {
          userTokensMap.set(userId, uniqueTokens);
        }
      }
    }

    if (userTokensMap.size === 0) {
      console.log("No FCM tokens found for users:", ids);
      return;
    }

    // Collect all tokens
    const allTokens = [];
    userTokensMap.forEach((tokens) => {
      allTokens.push(...tokens);
    });

    if (allTokens.length === 0) {
      console.log("No FCM tokens to send to");
      return;
    }

    // Build FCM message
    const message = {
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: {
        ...data,
        // Ensure all data values are strings
        ...Object.fromEntries(
          Object.entries(data).map(([k, v]) => [k, String(v)]),
        ),
      },
    };

    if (notification.imageUrl) {
      message.notification.imageUrl = notification.imageUrl;
    }

    // Send to all tokens
    const results = await admin.messaging().sendEachForMulticast({
      tokens: allTokens,
      ...message,
      android: {
        priority: data.priority === "high" ? "high" : "normal",
      },
      apns: {
        payload: {
          aps: {
            contentAvailable: true,
          },
        },
      },
    });

    console.log(
      `Sent ${results.successCount} notifications, ${results.failureCount} failed`,
    );

    // Clean up invalid tokens
    if (results.failureCount > 0) {
      const invalidTokens = [];
      results.responses.forEach((response, idx) => {
        if (!response.success) {
          const errorCode = response.error?.code;
          // Remove tokens that are invalid, not registered, or unregistered
          if (
            errorCode === "messaging/invalid-registration-token" ||
            errorCode === "messaging/registration-token-not-registered"
          ) {
            invalidTokens.push(allTokens[idx]);
          }
        }
      });

      // Remove invalid tokens from user documents
      if (invalidTokens.length > 0) {
        console.log(`Cleaning up ${invalidTokens.length} invalid tokens`);

        for (const [userId, userTokens] of userTokensMap.entries()) {
          const tokensToRemove = userTokens.filter((token) =>
            invalidTokens.includes(token),
          );

          if (tokensToRemove.length > 0) {
            await admin
              .firestore()
              .collection("users")
              .doc(userId)
              .update({
                fcmTokens: admin.firestore.FieldValue.arrayRemove(
                  ...tokensToRemove,
                ),
              });
            console.log(
              `Removed ${tokensToRemove.length} invalid tokens from user ${userId}`,
            );
          }
        }
      }
    }

    // Save notification to Firestore for each user
    const batch = admin.firestore().batch();
    for (const userId of ids) {
      const notificationRef = admin
        .firestore()
        .collection("notifications")
        .doc();
      batch.set(notificationRef, {
        userId,
        type: data.type || "system",
        title: notification.title,
        body: notification.body,
        data,
        action: data.action,
        imageUrl: notification.imageUrl || null,
        priority: data.priority || "normal",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        read: false,
      });
    }
    await batch.commit();
  } catch (error) {
    console.error("Error sending notification:", error);
    throw error;
  }
}

/**
 * Trigger: Send notification when order status changes
 * Notifies hero and rider about order status updates
 */
exports.notifyOrderStatusChange = onDocumentWritten(
  { document: "orders/{orderId}", region: STORAGE_REGION },
  async (event) => {
    const before =
      event.data && event.data.before.exists ? event.data.before.data() : null;
    const after =
      event.data && event.data.after.exists ? event.data.after.data() : null;

    // Only proceed if status changed
    if (!after || !before || before.status === after.status) {
      return;
    }

    const orderId = event.params.orderId;
    const heroId = after.heroId;
    const riderId = after.rider?.assignedRiderId;
    const newStatus = after.status;
    const oldStatus = before.status;

    console.log(
      `Order ${orderId} status changed: ${oldStatus} -> ${newStatus}`,
    );

    // Define notification messages for each status
    const statusMessages = {
      // Hero notifications
      hero: {
        assigned: {
          title: "🚴 Rider Asignado",
          body: "Un rider ha sido asignado a tu pedido",
        },
        picked_up: {
          title: "📦 Pedido Recogido",
          body: "Tu pedido ha sido recogido por el rider",
        },
        in_transit: {
          title: "🚚 En Camino",
          body: "Tu pedido está en camino",
        },
        delivered: {
          title: "✅ Pedido Entregado",
          body: "Tu pedido ha sido entregado",
        },
        canceled: {
          title: "❌ Pedido Cancelado",
          body: "Tu pedido ha sido cancelado",
        },
      },
      // Rider notifications
      rider: {
        canceled: {
          title: "❌ Pedido Cancelado",
          body: "El pedido ha sido cancelado",
        },
      },
    };

    // Send notification to hero
    if (statusMessages.hero[newStatus]) {
      await sendNotificationToUsers(heroId, statusMessages.hero[newStatus], {
        type: "order_status",
        action: "open_order",
        orderId,
        status: newStatus,
        priority: "high",
      });
    }

    // Send notification to rider if assigned
    if (riderId && statusMessages.rider[newStatus]) {
      await sendNotificationToUsers(riderId, statusMessages.rider[newStatus], {
        type: "order_status",
        action: "open_order",
        orderId,
        status: newStatus,
        priority: "high",
      });
    }
  },
);

/**
 * Trigger: Notify nearby riders when order is queued
 * Sends notification to riders within a certain radius
 */
exports.notifyNearbyRiders = onDocumentWritten(
  { document: "orders/{orderId}", region: STORAGE_REGION },
  async (event) => {
    const before =
      event.data && event.data.before.exists ? event.data.before.data() : null;
    const after =
      event.data && event.data.after.exists ? event.data.after.data() : null;

    // Only proceed if order just became queued
    if (!after || after.status !== "queued" || before?.status === "queued") {
      return;
    }

    const orderId = event.params.orderId;
    const pickupLocation = after.pickup?.location;

    if (
      !pickupLocation ||
      !pickupLocation.latitude ||
      !pickupLocation.longitude
    ) {
      console.log(
        "Order has no pickup location, skipping nearby rider notification",
      );
      return;
    }

    // Get all active riders
    const ridersSnapshot = await admin
      .firestore()
      .collection("users")
      .where("roles", "array-contains", "rider")
      .where("riderProfile.isActive", "==", true)
      .where("riderProfile.isVerified", "==", true)
      .get();

    if (ridersSnapshot.empty) {
      console.log("No active riders found");
      return;
    }

    // Calculate distance and filter nearby riders (within 10km)
    const RADIUS_KM = 10;
    const nearbyRiders = [];

    for (const riderDoc of ridersSnapshot.docs) {
      const riderData = riderDoc.data();
      const riderLocation = riderData.riderProfile?.currentLocation;

      if (
        !riderLocation ||
        !riderLocation.latitude ||
        !riderLocation.longitude
      ) {
        continue;
      }

      // Simple distance calculation (Haversine formula)
      const distance = calculateDistance(
        pickupLocation.latitude,
        pickupLocation.longitude,
        riderLocation.latitude,
        riderLocation.longitude,
      );

      if (distance <= RADIUS_KM) {
        nearbyRiders.push({
          riderId: riderDoc.id,
          distance,
        });
      }
    }

    if (nearbyRiders.length === 0) {
      console.log("No nearby riders found");
      return;
    }

    console.log(
      `Found ${nearbyRiders.length} nearby riders for order ${orderId}`,
    );

    // Sort by distance
    nearbyRiders.sort((a, b) => a.distance - b.distance);

    // Send notification to nearby riders
    const riderIds = nearbyRiders.map((r) => r.riderId);
    await sendNotificationToUsers(
      riderIds,
      {
        title: "🎯 Nuevo Pedido Cercano",
        body: `Hay un pedido disponible a ${nearbyRiders[0].distance.toFixed(1)} km de ti`,
      },
      {
        type: "nearby_order",
        action: "open_order",
        orderId,
        distance: String(nearbyRiders[0].distance),
        priority: "high",
      },
    );
  },
);

/**
 * Helper: Calculate distance between two coordinates (Haversine formula)
 * @param {number} lat1 - Latitude 1
 * @param {number} lon1 - Longitude 1
 * @param {number} lat2 - Latitude 2
 * @param {number} lon2 - Longitude 2
 * @returns {number} Distance in kilometers
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth's radius in km
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(degrees) {
  return degrees * (Math.PI / 180);
}

/**
 * Callable: Send notification from system operator
 * Allows authorized users to send notifications to specific users or broadcast
 *
 * @param {Object} data - { targetUserIds?: string[], title: string, body: string, type?: string, imageUrl?: string, useTopic?: boolean }
 */
exports.sendOperatorNotification = onCall(async (request) => {
  // Verify user is authorized (support/admin)
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Usuario no autenticado");
  }

  if (!isSupportUser(request.auth)) {
    throw new HttpsError("permission-denied", "No autorizado");
  }

  const { targetUserIds, title, body, type, imageUrl, targetScreen, useTopic } =
    request.data;

  if (!title || !body) {
    throw new HttpsError("invalid-argument", "title y body son requeridos");
  }

  let recipients = targetUserIds;

  if (!recipients || recipients.length === 0) {
    if (useTopic) {
      const message = {
        notification: {
          title,
          body,
        },
        data: {
          type: type || "system",
          action: targetScreen ? "open_screen" : "open_notifications",
          targetScreen: targetScreen || "",
        },
        topic: "all_users",
      };

      if (imageUrl) {
        message.notification.imageUrl = imageUrl;
      }

      await admin.messaging().send(message);

      return {
        success: true,
        method: "topic",
        message: "Notificación enviada a todos los usuarios vía topic",
      };
    } else {
      const BATCH_SIZE = 500;
      let totalSent = 0;
      let lastDoc = null;

      while (true) {
        let query = admin.firestore().collection("users").limit(BATCH_SIZE);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const usersSnapshot = await query.get();

        if (usersSnapshot.empty) {
          break;
        }

        const batchUserIds = usersSnapshot.docs.map((doc) => doc.id);

        await sendNotificationToUsers(
          batchUserIds,
          { title, body, imageUrl },
          {
            type: type || "system",
            action: targetScreen ? "open_screen" : "open_notifications",
            targetScreen,
            priority: "normal",
          },
        );

        totalSent += batchUserIds.length;
        lastDoc = usersSnapshot.docs[usersSnapshot.docs.length - 1];

        if (usersSnapshot.docs.length < BATCH_SIZE) {
          break;
        }
      }

      return {
        success: true,
        method: "paginated",
        recipientCount: totalSent,
        message: `Notificación enviada a ${totalSent} usuario(s)`,
      };
    }
  }

  // Send to specific users
  await sendNotificationToUsers(
    recipients,
    { title, body, imageUrl },
    {
      type: type || "system",
      action: targetScreen ? "open_screen" : "open_notifications",
      targetScreen,
      priority: "normal",
    },
  );

  return {
    success: true,
    method: "direct",
    recipientCount: recipients.length,
    message: `Notificación enviada a ${recipients.length} usuario(s)`,
  };
});

/**
 * Callable: Send broadcast notification using FCM topics
 * More efficient for mass notifications
 *
 * @param {Object} data - { title: string, body: string, topic?: string, imageUrl?: string }
 */
exports.sendBroadcastNotification = onCall(async (request) => {
  // Verify user is authorized (support/admin)
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Usuario no autenticado");
  }

  if (!isSupportUser(request.auth)) {
    throw new HttpsError("permission-denied", "No autorizado");
  }

  const { title, body, topic, imageUrl, type, targetScreen } = request.data;

  if (!title || !body) {
    throw new HttpsError("invalid-argument", "title y body son requeridos");
  }

  const targetTopic = topic || "all_users";

  const message = {
    notification: {
      title,
      body,
    },
    data: {
      type: type || "system",
      action: targetScreen ? "open_screen" : "open_notifications",
      targetScreen: targetScreen || "",
    },
    topic: targetTopic,
    android: {
      priority: "normal",
    },
    apns: {
      payload: {
        aps: {
          contentAvailable: true,
        },
      },
    },
  };

  if (imageUrl) {
    message.notification.imageUrl = imageUrl;
  }

  await admin.messaging().send(message);

  return {
    success: true,
    topic: targetTopic,
    message: `Notificación broadcast enviada al topic '${targetTopic}'`,
  };
});
