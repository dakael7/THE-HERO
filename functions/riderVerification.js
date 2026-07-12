const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onObjectFinalized } = require("firebase-functions/v2/storage");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const sharp = require("sharp");
const path = require("path");
const os = require("os");
const fs = require("fs");
const vision = require("@google-cloud/vision");
const { isSupportUser } = require("./supportAuth");
const {
  decideLicenseVerificationStatus,
} = require("./licenseVerificationPolicy");

const STORAGE_REGION = "southamerica-west1";
const visionClient = new vision.ImageAnnotatorClient();

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
// Manual review for RUT OCR results.
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

async function resolveLicenseVerificationFiles({ bucketName, requestPrefix }) {
  const bucket = admin.storage().bucket(bucketName);
  const [files] = await bucket.getFiles({ prefix: requestPrefix });
  let frontFile = null;
  let backFile = null;

  for (const file of files) {
    const name = path.basename(file.name).toLowerCase();
    if (!frontFile && name.includes("license_front")) frontFile = file;
    if (!backFile && name.includes("license_back")) backFile = file;
  }

  if (!frontFile || !backFile) return null;

  const [[frontMetadata], [backMetadata]] = await Promise.all([
    frontFile.getMetadata(),
    backFile.getMetadata(),
  ]);
  return {
    frontPath: frontFile.name,
    frontContentType: frontMetadata.contentType || "",
    backPath: backFile.name,
    backContentType: backMetadata.contentType || "",
  };
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


exports.ocrLicenseVerificationOnUpload = onObjectFinalized(
  { region: STORAGE_REGION },
  async (event) => {
    const object = event.data;
    const filePath = object.name;
    const contentType = object.contentType || "";

    if (!filePath) return null;

    // Expected path:
    // users/{uid}/documents/license_verification/{requestId}/...license_front|license_back.*
    const segments = filePath.split("/").filter(Boolean);
    if (segments.length < 6) return null;
    if (segments[0] !== "users") return null;
    if (segments[2] !== "documents") return null;
    if (segments[3] !== "license_verification") return null;

    const userId = segments[1];
    const requestId = segments[4];
    const fileName = segments[segments.length - 1];

    const lowerFileName = fileName.toLowerCase();
    const isLicenseFile =
      lowerFileName.includes("license_front") ||
      lowerFileName.includes("license_back");
    if (!isLicenseFile) return null;

    const requestPrefix = `${segments.slice(0, 5).join("/")}/`;
    const licenseFiles = await resolveLicenseVerificationFiles({
      bucketName: object.bucket,
      requestPrefix,
    });
    if (!licenseFiles) {
      logger.info("[ocrLicenseVerification] waiting for both sides", {
        userId,
        requestId,
        filePath,
      });
      return null;
    }

    const ocrFilePath = licenseFiles.frontPath;
    const ocrContentType = licenseFiles.frontContentType || contentType;

    const isPdf =
      ocrContentType === "application/pdf" ||
      ocrFilePath.toLowerCase().endsWith(".pdf");
    const isImage =
      ocrContentType.startsWith("image/") ||
      /\.(jpe?g|png|webp|gif)$/i.test(ocrFilePath);
    if (!isPdf && !isImage) return null;

    // Strict: no PDFs
    if (isPdf) {
      logger.warn("[ocrLicenseVerification] PDF not allowed", {
        userId,
        requestId,
        filePath: ocrFilePath,
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
              filePath: ocrFilePath,
              contentType: ocrContentType,
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
                          filePath: ocrFilePath,
                          contentType: ocrContentType,
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
      filePath: ocrFilePath,
      triggerFilePath: filePath,
      contentType: ocrContentType,
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
    if (
      ["approved", "rejected"].includes(reqData.status) &&
      reqData?.ocr?.processedAt
    ) {
      logger.info("[ocrLicenseVerification] already processed", {
        userId,
        requestId,
        status: reqData.status,
      });
      return null;
    }

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
              filePath: ocrFilePath,
              contentType: ocrContentType,
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
              filePath: ocrFilePath,
              contentType: ocrContentType,
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

    const gcsUri = `gs://${object.bucket}/${ocrFilePath}`;
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
      const frontText = await runVisionOcrForGcsUri({
        gcsUri,
        mimeType: isPdf ? "application/pdf" : ocrContentType,
      });
      const backPath = licenseFiles.backPath;
      const backContentType = licenseFiles.backContentType || "";
      const backGcsUri = `gs://${object.bucket}/${backPath}`;
      const backIsPdf =
        backContentType === "application/pdf" ||
        backPath.toLowerCase().endsWith(".pdf");
      const backText = await runVisionOcrForGcsUri({
        gcsUri: backGcsUri,
        mimeType: backIsPdf ? "application/pdf" : backContentType,
      });

      const ocrText = [frontText, backText].filter(Boolean).join("\n");
      const documentDetected = ocrText.trim().length >= 40;
      const keywordResult = countLicenseKeywords(ocrText);
      const keywordsOk = keywordResult.hits >= 2;

      const candidates = extractRutCandidates(ocrText);
      const declaredRutCandidate = declaredNormalized
        ? candidates.find(
            (candidate) => normalizeRut(candidate) === declaredNormalized,
          )
        : null;
      const extractedRutRaw =
        declaredRutCandidate || (candidates.length > 0 ? candidates[0] : null);
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
        : false;

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
        filePath: ocrFilePath,
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
      if (!expiryIso) errors.push("license_expiry_not_found");
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

      const verificationStatus = decideLicenseVerificationStatus({
        documentDetected,
        keywordsOk,
        extractedRut,
        strictRutOk,
        dvValid,
        declaredRut,
        matchDeclared,
        extractedName,
        nameMatchOk,
        expiryIso,
        expired,
        licenseClassDetected: Boolean(extractedLicenseClass),
        classOk: classCheck.ok,
        textureValid,
        suspiciousAttempt,
      });

      await userRef.set(
        {
          licenseVerification: {
            status: verificationStatus,
            requestId,
            mode: "ocr",
            verifiedAt: verificationStatus === "approved" ? now : null,
            ocr: {
              filePath: ocrFilePath,
              contentType: ocrContentType,
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
              filePath: ocrFilePath,
              contentType: ocrContentType,
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

      if (verificationStatus === "rejected") {
        await userRef.collection("security_events").add({
          type: "license_verification_rejected",
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
        filePath: ocrFilePath,
        error,
      });

      await userRef.set(
        {
          licenseVerification: {
            status: "failed",
            requestId,
            mode: "ocr",
            ocr: {
              filePath: ocrFilePath,
              contentType: ocrContentType,
              processedAt: now,
              errorCodes: ["ocr_error"],
            },
          },
          ...perVehicleLicensePatch({
            status: "failed",
            requestId,
            mode: "ocr",
            ocr: {
              filePath: ocrFilePath,
              contentType: ocrContentType,
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


