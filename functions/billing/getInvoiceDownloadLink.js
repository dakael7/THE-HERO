const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const crypto = require("crypto");

function _readString(value) {
  if (typeof value !== "string") return "";
  return value.trim();
}

function _extractStorageReference(invoiceData) {
  const explicitPath = _readString(invoiceData?.pdfPath);
  if (explicitPath.startsWith("gs://")) {
    return _parseGsPath(explicitPath);
  }
  if (explicitPath) {
    return {
      bucketName: "",
      objectPath: explicitPath,
    };
  }

  const gsUrl = _readString(invoiceData?.pdfUrl);
  if (!gsUrl.startsWith("gs://")) return null;
  return _parseGsPath(gsUrl);
}

function _parseGsPath(gsPath) {
  const raw = _readString(gsPath);
  if (!raw.startsWith("gs://")) return null;
  const withoutScheme = raw.slice(5);
  const firstSlash = withoutScheme.indexOf("/");
  if (firstSlash <= 0 || firstSlash >= withoutScheme.length - 1) return null;
  const bucketName = withoutScheme.slice(0, firstSlash).trim();
  const objectPath = withoutScheme.slice(firstSlash + 1).trim();
  if (!bucketName || !objectPath) return null;
  return {bucketName, objectPath};
}

function _canAccessInvoice(auth, invoiceData) {
  if (!auth) return false;
  if (auth.token?.admin === true || auth.token?.support === true) {
    return true;
  }

  const uid = _readString(auth.uid);
  if (!uid) return false;

  const payerUserId = _readString(invoiceData?.payerUserId);
  const sellerUserId = _readString(invoiceData?.sellerUserId);

  return uid === payerUserId || uid === sellerUserId;
}

function _isSignUrlPermissionError(error) {
  const message = _readString(error?.message).toLowerCase();
  return message.includes("signblob") ||
    message.includes("cannot sign data") ||
    message.includes("client_email") ||
    message.includes("token creator");
}

function _buildFirebaseDownloadUrl(bucketName, objectPath, token) {
  const encoded = encodeURIComponent(objectPath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}?alt=media&token=${token}`;
}

async function _ensureDownloadToken(file, objectPath) {
  const [metadata] = await file.getMetadata();
  const custom = metadata?.metadata || {};
  const existingRaw = _readString(custom?.firebaseStorageDownloadTokens);
  if (existingRaw) {
    const token = existingRaw.split(",").map((s) => s.trim()).find(Boolean);
    if (token) return token;
  }

  const token = crypto.randomUUID();
  await file.setMetadata({
    metadata: {
      ...custom,
      firebaseStorageDownloadTokens: token,
    },
  });
  logger.info("Created firebaseStorageDownloadTokens for invoice PDF", {
    bucket: file.bucket.name,
    objectPath,
  });
  return token;
}

exports.getInvoiceDownloadLink = onCall(
  {region: "us-central1"},
  async (request) => {
    try {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "User must be authenticated");
      }

      const invoiceId = _readString(request.data?.invoiceId);
      if (!invoiceId) {
        throw new HttpsError("invalid-argument", "invoiceId is required");
      }

      const invoiceRef = admin.firestore().collection("invoices").doc(invoiceId);
      const snapshot = await invoiceRef.get();
      if (!snapshot.exists) {
        throw new HttpsError("not-found", "Invoice not found");
      }

      const invoice = snapshot.data() || {};
      if (!_canAccessInvoice(request.auth, invoice)) {
        throw new HttpsError("permission-denied", "You cannot access this invoice");
      }

      const storageRef = _extractStorageReference(invoice);
      if (!storageRef?.objectPath) {
        throw new HttpsError(
          "failed-precondition",
          "Invoice PDF is not available yet",
        );
      }

      const resolvedBucketName = _readString(storageRef.bucketName) ||
        _readString(process.env.WASABIL_OUTPUT_BUCKET) ||
        _readString(process.env.SIMPLEAPI_OUTPUT_BUCKET);
      const bucket = resolvedBucketName ?
        admin.storage().bucket(resolvedBucketName) :
        admin.storage().bucket();
      const file = bucket.file(storageRef.objectPath);
      const [exists] = await file.exists();
      if (!exists) {
        throw new HttpsError(
          "not-found",
          `Invoice PDF file not found in bucket ${bucket.name}`,
        );
      }

      let url = "";
      let expiresAt = null;
      try {
        const expiresAtMs = Date.now() + (15 * 60 * 1000);
        const [signedUrl] = await file.getSignedUrl({
          action: "read",
          expires: expiresAtMs,
          version: "v4",
        });
        url = signedUrl;
        expiresAt = new Date(expiresAtMs).toISOString();
      } catch (signError) {
        if (!_isSignUrlPermissionError(signError)) {
          throw signError;
        }
        logger.warn("Signed URL generation failed, falling back to token URL", {
          message: _readString(signError?.message),
          bucket: bucket.name,
          objectPath: storageRef.objectPath,
        });
        const token = await _ensureDownloadToken(file, storageRef.objectPath);
        url = _buildFirebaseDownloadUrl(
          bucket.name,
          storageRef.objectPath,
          token,
        );
      }

      if (!_readString(url)) {
        throw new HttpsError("internal", "Unable to resolve invoice download URL");
      }

      return {
        url,
        expiresAt,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      logger.error("getInvoiceDownloadLink failed", {
        message: _readString(error?.message),
        stack: _readString(error?.stack).slice(0, 4000),
      });

      throw new HttpsError(
        "internal",
        _readString(error?.message) || "Unable to generate invoice download link",
      );
    }
  },
);
