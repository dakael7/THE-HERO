const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const crypto = require("crypto");

const BILLING_REGION = "southamerica-west1";

function _readString(value) {
  if (typeof value !== "string") return "";
  return value.trim();
}

function _toLower(value) {
  return _readString(value).toLowerCase();
}

function _normalizeDocumentType(order) {
  const billingDocType = _toLower(order?.billing?.documentType);
  if (billingDocType) return billingDocType;
  const legacyDocType = _toLower(order?.documentType);
  if (legacyDocType) return legacyDocType;
  return "boleta";
}

function _isPaidByPaymentStatus(order) {
  const status = _toLower(order?.paymentStatus);
  return status === "approved" || status === "paid";
}

function _isImmediateQueuedFactura(before, after) {
  if (!after) return false;
  const afterStatus = _toLower(after?.status);
  if (afterStatus !== "queued") return false;

  if (!before) return true;

  const beforeStatus = _toLower(before?.status);
  return beforeStatus === "created";
}

function _isPaidTransition(before, after) {
  if (!after) return false;

  const beforePaid = _isPaidByPaymentStatus(before);
  const afterPaid = _isPaidByPaymentStatus(after);
  if (!beforePaid && afterPaid) return true;

  const beforeStatus = _toLower(before?.status);
  const afterStatus = _toLower(after?.status);
  if (beforeStatus === "pending_payment" && afterStatus === "queued") {
    return true;
  }

  if (_isImmediateQueuedFactura(before, after)) {
    return true;
  }

  return false;
}

function _asNumber(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return n;
}

function _safeIsoDate(value) {
  if (!value) return new Date().toISOString().slice(0, 10);
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return new Date().toISOString().slice(0, 10);
  return date.toISOString().slice(0, 10);
}

function _extractXmlFromPayload(payloadText) {
  const text = (payloadText || "").trim();
  if (!text) return null;

  if (text.startsWith("<?xml") || text.includes("<DTE")) {
    return text;
  }

  try {
    const json = JSON.parse(text);
    const candidates = [
      json?.xml,
      json?.dte,
      json?.data?.xml,
      json?.data?.dte,
      json?.result?.xml,
      json?.result?.dte,
    ];

    for (const value of candidates) {
      const raw = _readString(value);
      if (!raw) continue;
      if (raw.startsWith("<?xml") || raw.includes("<DTE")) {
        return raw;
      }
      try {
        const decoded = Buffer.from(raw, "base64").toString("utf8");
        if (decoded.startsWith("<?xml") || decoded.includes("<DTE")) {
          return decoded;
        }
      } catch (_) {}
    }
  } catch (_) {}

  return null;
}

function _extractPdfBuffer(contentType, bodyBuffer, bodyText) {
  const normalizedContentType = _toLower(contentType);
  if (normalizedContentType.includes("application/pdf")) {
    return bodyBuffer;
  }

  if (bodyBuffer && bodyBuffer.length >= 4) {
    const signature = bodyBuffer.subarray(0, 4).toString("utf8");
    if (signature === "%PDF") {
      return bodyBuffer;
    }
  }

  const text = (bodyText || "").trim();
  if (!text) return null;

  try {
    const json = JSON.parse(text);
    const candidates = [
      json?.pdf,
      json?.file,
      json?.data?.pdf,
      json?.data?.file,
      json?.result?.pdf,
      json?.result?.file,
    ];

    for (const value of candidates) {
      const raw = _readString(value);
      if (!raw) continue;
      try {
        const buffer = Buffer.from(raw, "base64");
        if (buffer.length >= 4 && buffer.subarray(0, 4).toString("utf8") === "%PDF") {
          return buffer;
        }
      } catch (_) {}
    }
  } catch (_) {}

  return null;
}

function _normalizeErrorText(value) {
  return _readString(value)
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

function _isFolioAlreadyUsedError(statusCode, bodyText) {
  if (Number(statusCode) !== 400) return false;
  const normalized = _normalizeErrorText(bodyText);
  const hasFolioWord = normalized.includes("folio");
  const hasDuplicateHint =
    normalized.includes("ya utilizado") ||
    normalized.includes("ya fue utilizado") ||
    normalized.includes("utilizado previamente") ||
    normalized.includes("ya existe") ||
    normalized.includes("documento ya recibido");
  return hasFolioWord && hasDuplicateHint;
}

function _readEnvOrThrow(key) {
  const value = _readString(process.env[key]);
  if (!value) {
    throw new Error(`Missing required env: ${key}`);
  }
  return value;
}

function _normalizeRut(value) {
  const raw = _readString(value)
    .toUpperCase()
    .replace(/\s+/g, "")
    .replace(/\./g, "")
    .replace(/[^0-9K-]/g, "");

  if (!raw) return "";

  if (raw.includes("-")) {
    const [body, dv] = raw.split("-");
    if (!body || !dv) return "";
    return `${body}-${dv}`;
  }

  if (raw.length < 2) return "";
  return `${raw.slice(0, -1)}-${raw.slice(-1)}`;
}

function _isValidRutShape(rut) {
  return /^\d{7,8}-[0-9K]$/.test(rut);
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

function _requireFacturaField(order, key, label) {
  const value = _readString(order?.[key]);
  if (!value) {
    throw new Error(`Missing required factura field: ${label}`);
  }
  return value;
}

function _parseNumericCsv(value) {
  const raw = _readString(value);
  if (!raw) return [];
  return raw
    .split(",")
    .map((part) => Number(part.trim()))
    .filter((num) => Number.isInteger(num) && num > 0);
}

function _firstNonEmpty(...values) {
  for (const value of values) {
    const normalized = _readString(value);
    if (normalized) return normalized;
  }
  return "";
}

function _inferReceptorComuna(order, receiverAddress) {
  const explicit =
    _readString(order?.invoiceComuna) ||
    _readString(order?.invoiceCommune) ||
    _readString(order?.invoiceCity) ||
    _readString(order?.invoiceDistrict) ||
    _readString(process.env.SIMPLEAPI_DEFAULT_RECEPTOR_COMUNA);
  if (explicit) return explicit;

  const chunks = _readString(receiverAddress)
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
  if (chunks.length >= 2) {
    return chunks[chunks.length - 1].slice(0, 20);
  }
  return "Santiago";
}

function _inferReceptorCity(order, receiverAddress, receiverComuna) {
  const explicit =
    _readString(order?.invoiceCity) ||
    _readString(order?.invoiceComuna) ||
    _readString(order?.invoiceCommune) ||
    _readString(process.env.SIMPLEAPI_DEFAULT_RECEPTOR_CIUDAD);
  if (explicit) return explicit;

  const chunks = _readString(receiverAddress)
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
  if (chunks.length >= 2) {
    const lastChunk = chunks[chunks.length - 1];
    const prevChunk = chunks[chunks.length - 2];
    const usePrev = /region/i.test(lastChunk);
    return (usePrev ? prevChunk : lastChunk).slice(0, 40);
  }

  return _readString(receiverComuna) || "Santiago";
}

function _resolvePaymentDescriptor(order) {
  const raw = _toLower(
    _firstNonEmpty(
      order?.paymentMethodLabel,
      order?.paymentMethodName,
      order?.paymentMethodId,
      order?.paymentMethod,
      order?.payment?.paymentMethodLabel,
      order?.payment?.paymentMethodName,
      order?.payment?.paymentMethodId,
      order?.payment?.paymentMethod,
      order?.payment?.method,
      order?.payment?.statusDetail,
    ),
  );

  if (!raw) return "";
  if (raw.includes("cash") || raw.includes("efectivo")) return "Efectivo";
  if (raw.includes("debit")) return "Tarjeta Debito";
  if (raw.includes("credit")) return "Tarjeta Credito";
  if (raw.includes("transfer")) return "Transferencia";
  if (raw.includes("mercado")) return "Mercado Pago";
  if (raw.includes("card") || raw.includes("tarjeta")) return "Tarjeta";
  return raw;
}

function _toMaxLength(value, maxLength) {
  const normalized = _readString(value);
  if (!normalized) return "";
  if (normalized.length <= maxLength) return normalized;
  return normalized.slice(0, maxLength);
}

function _collectSellerUserIdsFromOrder(order) {
  const ids = [];
  const pushUnique = (rawId) => {
    const id = _readString(rawId);
    if (!id) return;
    if (ids.includes(id)) return;
    ids.push(id);
  };

  const items = Array.isArray(order?.items) ? order.items : [];
  for (const item of items) {
    pushUnique(item?.sellerHeroIdSnapshot);
    pushUnique(item?.sellerHeroId);
    pushUnique(item?.sellerId);
    pushUnique(item?.donorUserId);
  }

  const sellerHeroIds = Array.isArray(order?.sellerHeroIds) ? order.sellerHeroIds : [];
  for (const sellerId of sellerHeroIds) {
    pushUnique(sellerId);
  }

  return ids;
}

function _extractUserDisplayName(userData) {
  if (!userData || typeof userData !== "object") return "";

  const identity = userData.identity || {};
  const firstName = _readString(identity.firstName);
  const lastName = _readString(identity.lastName);
  const fullName = `${firstName} ${lastName}`.trim();
  if (fullName) return fullName;

  return _firstNonEmpty(
    userData.fullName,
    userData.displayName,
    userData.businessName,
    userData.name,
  );
}

async function _resolveDonorSellerLabel({db, order}) {
  const ids = _collectSellerUserIdsFromOrder(order);
  if (ids.length === 0) return "";

  const userSnaps = await Promise.all(
    ids.map(async (sellerId) => {
      try {
        return await db.collection("users").doc(sellerId).get();
      } catch (_) {
        return null;
      }
    }),
  );

  const names = [];
  for (let i = 0; i < userSnaps.length; i++) {
    const snap = userSnaps[i];
    if (!snap || !snap.exists) continue;

    const name = _extractUserDisplayName(snap.data() || {});
    if (!name) continue;

    if (!names.includes(name)) {
      names.push(name);
    }
  }

  if (names.length === 0) return "";
  if (names.length === 1) return _toMaxLength(names[0], 60);

  const firstTwo = names.slice(0, 2).join(" / ");
  const extraCount = names.length - 2;
  const collapsed = extraCount > 0 ? `${firstTwo} +${extraCount}` : firstTwo;
  return _toMaxLength(collapsed, 60);
}

function _resolveDteFormaPagoCode(order) {
  const explicit = Math.round(
    _asNumber(
      _firstNonEmpty(
        order?.invoiceFormaPago,
        order?.billing?.formaPago,
        process.env.SIMPLEAPI_DEFAULT_FMA_PAGO,
      ),
    ),
  );
  if ([1, 2, 3].includes(explicit)) return explicit;

  const paymentDescriptor = _toLower(_resolvePaymentDescriptor(order));
  if (paymentDescriptor.includes("credito") || paymentDescriptor.includes("credit")) {
    return 2;
  }
  if (paymentDescriptor.includes("sin costo") || paymentDescriptor.includes("gratuita")) {
    return 3;
  }
  if (paymentDescriptor) return 1;

  return _isPaidByPaymentStatus(order) ? 1 : 2;
}

function _resolveInvoiceSellerLabel(order, resolvedDonorSellerLabel = "") {
  return _firstNonEmpty(
    resolvedDonorSellerLabel,
    order?.invoiceSellerName,
    order?.sellerNameSnapshot,
    process.env.SIMPLEAPI_DEFAULT_VENDEDOR,
    process.env.SIMPLEAPI_EMISOR_RAZON_SOCIAL,
  );
}

function _resolveInvoiceSaleCondition(order, paymentLabel) {
  const explicit = _firstNonEmpty(
    order?.invoiceSaleCondition,
    process.env.SIMPLEAPI_DEFAULT_CONDICION_VENTA,
  );
  if (explicit) return explicit;

  const normalizedPayment = _toLower(paymentLabel);
  if (normalizedPayment.includes("credito") || normalizedPayment.includes("credit")) {
    return "Credito";
  }

  const paymentStatus = _toLower(order?.paymentStatus);
  if (paymentStatus === "paid" || paymentStatus === "approved") {
    return "Contado";
  }

  return "Contado";
}

function _buildDteInput({order, folio, sellerLabel = ""}) {
  const receiverName = _requireFacturaField(
    order,
    "invoiceBusinessName",
    "Razon social",
  );
  const receiverRut = _normalizeRut(
    _requireFacturaField(order, "invoiceRut", "RUT"),
  );
  if (!_isValidRutShape(receiverRut)) {
    throw new Error("Invalid RUT format for factura receptor");
  }
  const receiverAddress = _requireFacturaField(
    order,
    "invoiceAddress",
    "Direccion",
  );
  const receiverComuna = _inferReceptorComuna(order, receiverAddress);
  const receiverCity = _inferReceptorCity(order, receiverAddress, receiverComuna);
  const giro = _requireFacturaField(order, "invoiceGiro", "Giro");
  const receiverEmail = _readString(order?.invoiceEmail);
  const receiverPhone = _readString(order?.invoicePhone);
  const receiverContact = receiverEmail || receiverPhone;
  const emisorRut = _normalizeRut(_readEnvOrThrow("SIMPLEAPI_EMISOR_RUT"));
  const certRut = _normalizeRut(_readEnvOrThrow("SIMPLEAPI_CERT_RUT"));
  if (!_isValidRutShape(emisorRut)) {
    throw new Error("Invalid SIMPLEAPI_EMISOR_RUT format");
  }
  if (!_isValidRutShape(certRut)) {
    throw new Error("Invalid SIMPLEAPI_CERT_RUT format");
  }
  const emisorActivityCodes = _parseNumericCsv(process.env.SIMPLEAPI_EMISOR_ACTIVITY_CODES);

  const lines = Array.isArray(order?.items) ? order.items : [];
  const normalizedItems = lines.map((item, idx) => {
    const description =
      _readString(item?.titleSnapshot) || `Item ${idx + 1}`;
    const qty = Math.max(1, Math.round(_asNumber(item?.qty)));
    const unitPrice = Math.max(0, Math.round(_asNumber(item?.unitPriceSnapshot)));
    const lineTotal = Math.max(0, qty * unitPrice);
    return {
      IndicadorExento: 0,
      Nombre: description,
      Descripcion: description,
      Cantidad: qty,
      UnidadMedida: "un",
      Precio: unitPrice,
      Descuento: 0,
      Recargo: 0,
      MontoItem: lineTotal,
    };
  });

  if (normalizedItems.length === 0) {
    throw new Error("Order has no billable items");
  }

  const derivedNetFromLines = normalizedItems.reduce(
    (acc, line) => acc + Math.round(_asNumber(line.MontoItem)),
    0,
  );
  let subtotal = Math.round(_asNumber(order?.subtotal));
  const taxAmount = Math.round(_asNumber(order?.tax));
  const total = Math.round(_asNumber(order?.amountTotal));

  if (subtotal <= 0 && total > taxAmount) {
    subtotal = total - taxAmount;
  }
  if (subtotal <= 0 && derivedNetFromLines > 0) {
    subtotal = derivedNetFromLines;
  }

  const resolvedSellerLabel = _resolveInvoiceSellerLabel(order, sellerLabel);
  const emisor = {
    Rut: emisorRut,
    RazonSocial: _readString(process.env.SIMPLEAPI_EMISOR_RAZON_SOCIAL) || "",
    Giro: _readString(process.env.SIMPLEAPI_EMISOR_GIRO) || "",
    DireccionOrigen: _readString(process.env.SIMPLEAPI_EMISOR_DIRECCION) || "",
    ComunaOrigen: _readString(process.env.SIMPLEAPI_EMISOR_COMUNA) || "",
    CiudadOrigen: _readString(process.env.SIMPLEAPI_EMISOR_CIUDAD) || "",
    ActividadEconomica: emisorActivityCodes,
    Telefono: [],
  };
  if (resolvedSellerLabel) {
    emisor.CodigoVendedor = resolvedSellerLabel;
  }

  return {
    Documento: {
      Encabezado: {
        IdentificacionDTE: {
          TipoDTE: 33,
          Folio: Math.max(1, Math.round(_asNumber(folio))),
          FechaEmision: _safeIsoDate(order?.updatedAt || order?.timestamps?.paidAt),
          FormaPago: _resolveDteFormaPagoCode(order),
        },
        Emisor: emisor,
        Receptor: {
          Rut: receiverRut,
          RazonSocial: receiverName,
          Giro: giro,
          Direccion: receiverAddress,
          Comuna: receiverComuna,
          Ciudad: receiverCity,
          Contacto: receiverContact || undefined,
        },
        Totales: {
          MontoNeto: Math.max(0, subtotal),
          TasaIVA: 19,
          IVA: Math.max(0, taxAmount),
          MontoTotal: Math.max(0, total),
        },
      },
      RutSolicitante: "",
      Transporte: null,
      Detalles: normalizedItems,
    },
    Certificado: {
      Rut: certRut,
      Password: _readString(process.env.SIMPLEAPI_PFX_PASSWORD),
    },
  };
}

function _buildPdfInput({order, sellerLabel = ""}) {
  const paymentLabel =
    _resolvePaymentDescriptor(order) ||
    _readString(process.env.SIMPLEAPI_DEFAULT_FORMA_PAGO) ||
    "Contado";
  const saleCondition = _resolveInvoiceSaleCondition(order, paymentLabel);
  const resolvedSellerLabel = _resolveInvoiceSellerLabel(order, sellerLabel);

  const payload = {
    NumeroResolucion: _readString(process.env.SIMPLEAPI_SII_RESOLUTION_NUMBER) || "",
    UnidadSII: _readString(process.env.SIMPLEAPI_SII_UNIT) || "",
    FechaResolucion: _readString(process.env.SIMPLEAPI_SII_RESOLUTION_DATE) || "",
    PropiedadLogo: _readString(process.env.SIMPLEAPI_LOGO_FIT) || "contain",
  };

  if (resolvedSellerLabel) payload.Vendedor = resolvedSellerLabel;
  if (paymentLabel) payload.FormaPago = paymentLabel;
  if (saleCondition) payload.CondicionVenta = saleCondition;

  return payload;
}

function _resolveStorageObject(storagePath, fallbackBucketName) {
  const raw = _readString(storagePath);
  if (!raw) {
    throw new Error("Missing storage path");
  }

  if (raw.startsWith("gs://")) {
    const withoutScheme = raw.slice(5);
    const slashIndex = withoutScheme.indexOf("/");
    if (slashIndex <= 0 || slashIndex === withoutScheme.length - 1) {
      throw new Error(`Invalid gs:// path: ${raw}`);
    }
    return {
      bucketName: withoutScheme.slice(0, slashIndex),
      objectPath: withoutScheme.slice(slashIndex + 1),
    };
  }

  const objectPath = raw.replace(/^\/+/, "");
  if (!objectPath) {
    throw new Error(`Invalid storage path: ${raw}`);
  }

  return {
    bucketName: _readString(fallbackBucketName),
    objectPath,
  };
}

function _extractCafIssuerRut(cafBuffer) {
  const text = (cafBuffer || Buffer.alloc(0)).toString("utf8");
  if (!text) return "";
  const match = text.match(/<RE>\s*([^<]+)\s*<\/RE>/i);
  if (!match?.[1]) return "";
  return _normalizeRut(match[1]);
}

function _extractCafFolioRange(cafBuffer) {
  const text = (cafBuffer || Buffer.alloc(0)).toString("utf8");
  if (!text) return null;

  const rangeMatch = text.match(
    /<RNG>[\s\S]*?<D>\s*(\d+)\s*<\/D>[\s\S]*?<H>\s*(\d+)\s*<\/H>[\s\S]*?<\/RNG>/i,
  );
  if (!rangeMatch?.[1] || !rangeMatch?.[2]) return null;

  const from = Number(rangeMatch[1]);
  const to = Number(rangeMatch[2]);
  if (!Number.isInteger(from) || !Number.isInteger(to)) return null;
  if (from <= 0 || to <= 0 || to < from) return null;

  return {from, to};
}

function _buildFolioCounterDocId({tipoDte, emisorRut, cafPath, folioRange}) {
  const emisorKey = _readString(emisorRut).replace(/[^0-9K]/gi, "");
  const signature = crypto
    .createHash("sha1")
    .update(
      `${tipoDte}|${emisorRut}|${cafPath}|${folioRange.from}|${folioRange.to}`,
      "utf8",
    )
    .digest("hex")
    .slice(0, 12);

  return `dte${tipoDte}_${emisorKey}_${signature}`;
}

async function _allocateNextFolio({
  db,
  tipoDte,
  emisorRut,
  cafPath,
  folioRange,
}) {
  const counterId = _buildFolioCounterDocId({
    tipoDte,
    emisorRut,
    cafPath,
    folioRange,
  });
  const counterRef = db.collection("billing_folio_counters").doc(counterId);
  const now = admin.firestore.FieldValue.serverTimestamp();

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(counterRef);
    const data = snap.exists ? (snap.data() || {}) : {};
    const persistedMin = Math.round(_asNumber(data.folioMin));
    const persistedMax = Math.round(_asNumber(data.folioMax));
    const persistedNext = Math.round(_asNumber(data.nextFolio));
    const isSameRange = persistedMin === folioRange.from &&
      persistedMax === folioRange.to;

    let candidate = folioRange.from;
    if (snap.exists && isSameRange && persistedNext > 0) {
      candidate = persistedNext;
    }
    if (candidate < folioRange.from) candidate = folioRange.from;

    if (candidate > folioRange.to) {
      throw new Error(
        `CAF folio range exhausted for tipo ${tipoDte}: ${folioRange.from}-${folioRange.to}`,
      );
    }

    tx.set(counterRef, {
      tipoDte,
      emisorRut,
      cafPath,
      folioMin: folioRange.from,
      folioMax: folioRange.to,
      nextFolio: candidate + 1,
      lastAssignedFolio: candidate,
      updatedAt: now,
      createdAt: data.createdAt || now,
    }, {merge: true});

    return candidate;
  });
}

async function _downloadPrivateAsset(storagePath, fallbackBucketName = "") {
  const resolved = _resolveStorageObject(storagePath, fallbackBucketName);
  const bucket = resolved.bucketName ?
    admin.storage().bucket(resolved.bucketName) :
    admin.storage().bucket();
  const [buffer] = await bucket.file(resolved.objectPath).download();
  return {
    buffer,
    bucketName: bucket.name,
    objectPath: resolved.objectPath,
  };
}

async function _emitDteAndPdf({orderId, invoiceId, order, reservedFolio, sellerLabel}) {
  const baseUrl = _readString(process.env.SIMPLEAPI_BASE_URL) || "https://api.simpleapi.cl";
  const dteEndpoint = _readString(process.env.SIMPLEAPI_DTE_GENERATE_URL) ||
    `${baseUrl.replace(/\/+$/, "")}/api/v1/dte/generar`;
  const pdfEndpoint = _readString(process.env.SIMPLEAPI_PDF_GENERATE_URL) ||
    `${baseUrl.replace(/\/+$/, "")}/api/v1/impresion/pdf/carta/v2`;
  const apiKey = _readEnvOrThrow("SIMPLEAPI_API_KEY");
  const pfxPath = _readEnvOrThrow("SIMPLEAPI_PFX_STORAGE_PATH");
  const cafPath = _readEnvOrThrow("SIMPLEAPI_CAF_STORAGE_PATH");
  const certRut = _readString(process.env.SIMPLEAPI_CERT_RUT);
  const logoPath = _readString(process.env.SIMPLEAPI_LOGO_STORAGE_PATH);
  const assetsBucketName = _readString(process.env.SIMPLEAPI_ASSETS_BUCKET);
  const outputBucketName = _readString(process.env.SIMPLEAPI_OUTPUT_BUCKET);
  _readEnvOrThrow("SIMPLEAPI_PFX_PASSWORD");

  logger.info("SimpleAPI endpoints resolved", {
    dteEndpoint,
    pdfEndpoint,
    assetsBucketName: assetsBucketName || null,
    outputBucketName: outputBucketName || null,
  });

  if (certRut && !pfxPath.includes(certRut)) {
    logger.warn("SIMPLEAPI_CERT_RUT does not match certificate path", {
      certRut,
      pfxPath,
    });
  }

  const pfxAsset = await _downloadPrivateAsset(pfxPath, assetsBucketName);
  const cafAsset = await _downloadPrivateAsset(cafPath, assetsBucketName);
  const pfxBuffer = pfxAsset.buffer;
  const cafBuffer = cafAsset.buffer;
  const emisorRut = _normalizeRut(_readString(process.env.SIMPLEAPI_EMISOR_RUT));
  const cafRut = _extractCafIssuerRut(cafBuffer);
  const cafFolioRange = _extractCafFolioRange(cafBuffer);

  if (emisorRut && cafRut && emisorRut !== cafRut) {
    throw new Error(
      `Issuer RUT mismatch between SIMPLEAPI_EMISOR_RUT (${emisorRut}) and CAF (${cafRut})`,
    );
  }

  if (!cafFolioRange) {
    throw new Error("Unable to extract CAF folio range from XML");
  }

  const presetFolio = Math.round(_asNumber(reservedFolio));
  const db = admin.firestore();
  const folioToUse = presetFolio > 0 ?
    presetFolio :
    await _allocateNextFolio({
      db,
      tipoDte: 33,
      emisorRut,
      cafPath,
      folioRange: cafFolioRange,
    });

  if (folioToUse < cafFolioRange.from || folioToUse > cafFolioRange.to) {
    throw new Error(
      `Allocated folio (${folioToUse}) is outside CAF range ${cafFolioRange.from}-${cafFolioRange.to}`,
    );
  }

  logger.info("Using CAF folio for invoice emission", {
    orderId,
    invoiceId,
    folio: folioToUse,
    cafRange: `${cafFolioRange.from}-${cafFolioRange.to}`,
  });

  const maxFolioRetries = Math.max(
    0,
    Math.min(10, Math.round(_asNumber(process.env.SIMPLEAPI_FOLIO_RETRY_LIMIT || 3))),
  );
  let currentFolio = folioToUse;
  let dteBodyBuffer = Buffer.alloc(0);
  let dteBodyText = "";
  let dteStatusCode = 0;

  for (let attempt = 0; ; attempt++) {
    const dteInput = _buildDteInput({
      order,
      folio: currentFolio,
      sellerLabel,
    });
    const dteForm = new FormData();
    dteForm.append("input", JSON.stringify(dteInput));
    dteForm.append("files", new Blob([pfxBuffer]), "certificado.pfx");
    dteForm.append("files2", new Blob([cafBuffer]), "caf.xml");

    const dteResponse = await fetch(dteEndpoint, {
      method: "POST",
      headers: {
        "x-api-key": apiKey,
        "Authorization": apiKey,
      },
      body: dteForm,
    });

    dteStatusCode = dteResponse.status;
    dteBodyBuffer = Buffer.from(await dteResponse.arrayBuffer());
    dteBodyText = dteBodyBuffer.toString("utf8");
    if (dteResponse.ok) {
      break;
    }

    const shouldRetryWithNextFolio = attempt < maxFolioRetries &&
      _isFolioAlreadyUsedError(dteResponse.status, dteBodyText);
    if (!shouldRetryWithNextFolio) {
      throw new Error(
        `DTE generation failed (${dteResponse.status}) [${dteEndpoint}]: ${dteBodyText.slice(0, 300)}`,
      );
    }

    logger.warn("DTE rejected due to used folio, retrying with next folio", {
      orderId,
      invoiceId,
      attemptedFolio: currentFolio,
      attempt: attempt + 1,
      maxFolioRetries,
      statusCode: dteResponse.status,
    });

    currentFolio = await _allocateNextFolio({
      db,
      tipoDte: 33,
      emisorRut,
      cafPath,
      folioRange: cafFolioRange,
    });

    if (currentFolio < cafFolioRange.from || currentFolio > cafFolioRange.to) {
      throw new Error(
        `Allocated folio (${currentFolio}) is outside CAF range ${cafFolioRange.from}-${cafFolioRange.to}`,
      );
    }
  }

  const xmlPayload = _extractXmlFromPayload(dteBodyText);
  if (!xmlPayload) {
    throw new Error(
      `DTE response did not include a valid XML payload (status=${dteStatusCode})`,
    );
  }

  const bucket = outputBucketName ?
    admin.storage().bucket(outputBucketName) :
    admin.storage().bucket();
  const xmlPath = `invoices/${invoiceId}/dte.xml`;
  await bucket.file(xmlPath).save(Buffer.from(xmlPayload, "utf8"), {
    resumable: false,
    contentType: "application/xml; charset=utf-8",
    metadata: { cacheControl: "private, max-age=0, no-store" },
  });

  const pdfInput = _buildPdfInput({order, sellerLabel});
  const pdfSellerLabel = _readString(pdfInput?.Vendedor);
  const pdfForm = new FormData();
  pdfForm.append("input", JSON.stringify(pdfInput));
  pdfForm.append("fileEnvio", new Blob([Buffer.from(xmlPayload, "utf8")]), "dte.xml");
  if (logoPath) {
    try {
      const logoAsset = await _downloadPrivateAsset(logoPath, assetsBucketName);
      if (logoAsset.buffer.length > 0) {
        pdfForm.append("logo", new Blob([logoAsset.buffer]), "logo.png");
      }
    } catch (error) {
      logger.warn("Unable to attach SIMPLEAPI logo, continuing without logo", {
        logoPath,
        message: _readString(error?.message),
      });
    }
  }

  const pdfResponse = await fetch(pdfEndpoint, {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "Authorization": apiKey,
    },
    body: pdfForm,
  });

  const pdfBodyBuffer = Buffer.from(await pdfResponse.arrayBuffer());
  const pdfBodyText = pdfBodyBuffer.toString("utf8");
  if (!pdfResponse.ok) {
    throw new Error(
      `PDF generation failed (${pdfResponse.status}) [${pdfEndpoint}]: ${pdfBodyText.slice(0, 300)}`,
    );
  }

  const pdfBuffer = _extractPdfBuffer(
    pdfResponse.headers.get("content-type"),
    pdfBodyBuffer,
    pdfBodyText,
  );

  if (!pdfBuffer) {
    throw new Error("PDF response did not include a valid PDF payload");
  }

  const pdfPath = `invoices/${invoiceId}/invoice.pdf`;
  await bucket.file(pdfPath).save(pdfBuffer, {
    resumable: false,
    contentType: "application/pdf",
    metadata: { cacheControl: "private, max-age=0, no-store" },
  });

  const xmlStoragePath = `gs://${bucket.name}/${xmlPath}`;
  const pdfStoragePath = `gs://${bucket.name}/${pdfPath}`;

  return {
    folio: currentFolio,
    cafFolioFrom: cafFolioRange.from,
    cafFolioTo: cafFolioRange.to,
    xmlPath,
    pdfPath,
    xmlStoragePath,
    pdfStoragePath,
    providerDocumentId: invoiceId,
    providerTrackId: orderId,
    pfxPath,
    cafPath,
    certRut,
    logoPath,
    sellerLabel: pdfSellerLabel || null,
    sourceBuckets: {
      pfx: pfxAsset.bucketName,
      caf: cafAsset.bucketName,
      output: bucket.name,
    },
  };
}

exports.retryInvoiceEmission = onCall(
  {
    region: "us-central1",
    secrets: ["SIMPLEAPI_API_KEY", "SIMPLEAPI_PFX_PASSWORD"],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Debes iniciar sesion para continuar");
    }

    const invoiceId = _readString(request.data?.invoiceId);
    if (!invoiceId) {
      throw new HttpsError("invalid-argument", "invoiceId es requerido");
    }

    const db = admin.firestore();
    const invoiceRef = db.collection("invoices").doc(invoiceId);
    const invoiceSnap = await invoiceRef.get();
    if (!invoiceSnap.exists) {
      throw new HttpsError("not-found", "Factura no encontrada");
    }

    const invoiceData = invoiceSnap.data() || {};
    if (!_canAccessInvoice(request.auth, invoiceData)) {
      throw new HttpsError("permission-denied", "No tienes permisos para reintentar esta factura");
    }

    const orderId = _readString(invoiceData?.orderId);
    if (!orderId) {
      throw new HttpsError("failed-precondition", "La factura no tiene orderId asociado");
    }

    const orderRef = db.collection("orders").doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
      throw new HttpsError("not-found", "Pedido asociado no encontrado");
    }
    const orderData = orderSnap.data() || {};

    if (_normalizeDocumentType(orderData) !== "factura") {
      throw new HttpsError("failed-precondition", "El pedido no esta configurado para factura");
    }

    const currentStatus = _toLower(invoiceData?.status);
    const alreadyHasPdf = _readString(invoiceData?.pdfPath) || _readString(invoiceData?.pdfUrl);
    if (currentStatus === "issued" && alreadyHasPdf) {
      return {
        invoiceId,
        orderId,
        status: "issued",
        alreadyIssued: true,
      };
    }

    if (currentStatus === "pending") {
      throw new HttpsError("failed-precondition", "La factura ya se esta procesando");
    }

    if (currentStatus !== "failed") {
      throw new HttpsError(
        "failed-precondition",
        `Solo se puede reintentar facturas en failed. Estado actual: ${currentStatus || "unknown"}`,
      );
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    await invoiceRef.set({
      status: "pending",
      updatedAt: now,
      errorCode: null,
      errorMessage: null,
    }, {merge: true});

    await orderRef.set({
      billing: {
        documentType: "factura",
        requestedByUserId: _readString(orderData?.heroId) || null,
        invoiceId,
        invoiceStatus: "pending",
        updatedAt: now,
      },
    }, {merge: true});

    try {
      const resolvedSellerLabel = await _resolveDonorSellerLabel({
        db,
        order: orderData,
      });

      logger.info("Retrying invoice emission", {
        orderId,
        invoiceId,
        requestedBy: _readString(request.auth.uid) || null,
        sellerLabel: resolvedSellerLabel || null,
      });

      const emission = await _emitDteAndPdf({
        orderId,
        invoiceId,
        order: orderData,
        reservedFolio: null,
        sellerLabel: resolvedSellerLabel,
      });

      await invoiceRef.set({
        status: "issued",
        providerDocumentId: emission.providerDocumentId,
        providerTrackId: emission.providerTrackId,
        folio: emission.folio,
        folioRangeFrom: emission.cafFolioFrom,
        folioRangeTo: emission.cafFolioTo,
        xmlPath: emission.xmlPath,
        xmlUrl: emission.xmlStoragePath,
        pdfPath: emission.pdfPath,
        pdfUrl: emission.pdfStoragePath,
        issuedAt: now,
        updatedAt: now,
        errorCode: null,
        errorMessage: null,
        providerMeta: {
          certPath: emission.pfxPath,
          cafPath: emission.cafPath,
          certRut: emission.certRut || null,
          logoPath: emission.logoPath || null,
          sellerLabel: emission.sellerLabel || null,
        },
      }, {merge: true});

      await orderRef.set({
        billing: {
          documentType: "factura",
          requestedByUserId: _readString(orderData?.heroId) || null,
          invoiceId,
          invoiceFolio: emission.folio,
          invoiceStatus: "issued",
          updatedAt: now,
        },
      }, {merge: true});

      return {
        invoiceId,
        orderId,
        status: "issued",
        folio: emission.folio,
      };
    } catch (error) {
      const message = _readString(error?.message) || "Unknown billing error";
      await invoiceRef.set({
        status: "failed",
        errorCode: "emission_failed",
        errorMessage: message.slice(0, 2000),
        retryCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
      }, {merge: true});

      await orderRef.set({
        billing: {
          documentType: "factura",
          requestedByUserId: _readString(orderData?.heroId) || null,
          invoiceId,
          invoiceStatus: "failed",
          updatedAt: now,
        },
      }, {merge: true});

      logger.error("Retry invoice emission failed", {
        orderId,
        invoiceId,
        requestedBy: _readString(request.auth.uid) || null,
        errorDetails: {
          name: _readString(error?.name) || null,
          message,
          stack: _readString(error?.stack).slice(0, 4000) || null,
        },
      });

      throw new HttpsError("internal", message);
    }
  },
);

exports.onOrderPaidCreateInvoice = onDocumentWritten(
  {
    document: "orders/{orderId}",
    region: BILLING_REGION,
    secrets: ["SIMPLEAPI_API_KEY", "SIMPLEAPI_PFX_PASSWORD"],
  },
  async (event) => {
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;
    if (!after) return;

    if (!_isPaidTransition(before, after)) return;

    const documentType = _normalizeDocumentType(after);
    if (documentType !== "factura") return;

    const orderId = _readString(event.params?.orderId) || _readString(after?.orderId);
    if (!orderId) return;

    const db = admin.firestore();
    const existing = await db
      .collection("invoices")
      .where("orderId", "==", orderId)
      .limit(1)
      .get();

    if (!existing.empty) {
      logger.info("Invoice already exists for order", {orderId});
      return;
    }

    const invoiceRef = db.collection("invoices").doc(orderId);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const heroId = _readString(after?.heroId);
    const sellerUserId = Array.isArray(after?.sellerHeroIds) &&
      after.sellerHeroIds.length > 0
      ? _readString(after.sellerHeroIds[0])
      : "";

    const baseInvoiceData = {
      invoiceId: invoiceRef.id,
      orderId,
      payerUserId: heroId,
      sellerUserId: sellerUserId || null,
      documentType: "factura",
      currency: _readString(after?.currency) || "CLP",
      subtotal: _asNumber(after?.subtotal),
      taxAmount: _asNumber(after?.tax),
      total: _asNumber(after?.amountTotal),
      status: "pending",
      provider: "simpleapi",
      providerDocumentId: null,
      providerTrackId: null,
      folio: null,
      folioRangeFrom: null,
      folioRangeTo: null,
      pdfPath: null,
      pdfUrl: null,
      xmlPath: null,
      xmlUrl: null,
      errorCode: null,
      errorMessage: null,
      retryCount: 0,
      issuedAt: null,
      createdAt: now,
      updatedAt: now,
    };

    await invoiceRef.set(baseInvoiceData);

    await db.collection("orders").doc(orderId).set({
      billing: {
        documentType: "factura",
        requestedByUserId: heroId || null,
        invoiceId: invoiceRef.id,
        invoiceStatus: "pending",
        updatedAt: now,
      },
    }, {merge: true});

    try {
      const resolvedSellerLabel = await _resolveDonorSellerLabel({
        db,
        order: after,
      });
      logger.info("Resolved factura vendedor label", {
        orderId,
        sellerLabel: resolvedSellerLabel || null,
      });

      const emission = await _emitDteAndPdf({
        orderId,
        invoiceId: invoiceRef.id,
        order: after,
        reservedFolio: null,
        sellerLabel: resolvedSellerLabel,
      });

      await invoiceRef.set({
        status: "issued",
        providerDocumentId: emission.providerDocumentId,
        providerTrackId: emission.providerTrackId,
        folio: emission.folio,
        folioRangeFrom: emission.cafFolioFrom,
        folioRangeTo: emission.cafFolioTo,
        xmlPath: emission.xmlPath,
        xmlUrl: emission.xmlStoragePath,
        pdfPath: emission.pdfPath,
        pdfUrl: emission.pdfStoragePath,
        issuedAt: now,
        updatedAt: now,
        errorCode: null,
        errorMessage: null,
        providerMeta: {
          certPath: emission.pfxPath,
          cafPath: emission.cafPath,
          certRut: emission.certRut || null,
          logoPath: emission.logoPath || null,
          sellerLabel: emission.sellerLabel || null,
        },
      }, {merge: true});

      await db.collection("orders").doc(orderId).set({
        billing: {
          documentType: "factura",
          requestedByUserId: heroId || null,
          invoiceId: invoiceRef.id,
          invoiceFolio: emission.folio,
          invoiceStatus: "issued",
          updatedAt: now,
        },
      }, {merge: true});

      logger.info("Invoice emitted successfully", {
        orderId,
        invoiceId: invoiceRef.id,
      });
    } catch (error) {
      const message = _readString(error?.message) || "Unknown billing error";
      await invoiceRef.set({
        status: "failed",
        errorCode: "emission_failed",
        errorMessage: message.slice(0, 2000),
        retryCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now,
      }, {merge: true});

      await db.collection("orders").doc(orderId).set({
        billing: {
          documentType: "factura",
          requestedByUserId: heroId || null,
          invoiceId: invoiceRef.id,
          invoiceStatus: "failed",
          updatedAt: now,
        },
      }, {merge: true});

      const safeStack = _readString(error?.stack).slice(0, 4000);
      logger.error("Invoice emission failed", {
        orderId,
        invoiceId: invoiceRef.id,
        errorDetails: {
          name: _readString(error?.name) || null,
          message,
          stack: safeStack || null,
        },
      });
    }
  },
);

