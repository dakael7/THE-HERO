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

function _readBoolean(value, fallback = false) {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") {
    if (value === 1) return true;
    if (value === 0) return false;
  }
  const normalized = _toLower(value);
  if (!normalized) return fallback;
  if (["1", "true", "yes", "y", "si", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "n", "off"].includes(normalized)) return false;
  return fallback;
}

function _readInteger(value, fallback = 0) {
  const n = Math.round(_asNumber(value));
  if (!Number.isFinite(n)) return fallback;
  return n;
}

function _safeIsoDate(value) {
  if (!value) return new Date().toISOString().slice(0, 10);
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return new Date().toISOString().slice(0, 10);
  return date.toISOString().slice(0, 10);
}

function _looksLikeXmlPayloadText(value) {
  const text = _readString(value);
  if (!text) return false;
  return text.startsWith("<?xml") ||
    text.startsWith("<DTE") ||
    text.startsWith("<Envio") ||
    text.startsWith("<SetDTE") ||
    text.startsWith("<RECEPCIONDTE");
}

function _normalizeXmlEncodingName(value) {
  const normalized = _toLower(value).replace(/[_\s]/g, "");
  if (!normalized) return "";
  if (
    normalized.includes("8859-1") ||
    normalized.includes("iso88591") ||
    normalized.includes("latin1")
  ) {
    return "latin1";
  }
  if (normalized.includes("utf-8") || normalized.includes("utf8")) {
    return "utf8";
  }
  return "";
}

function _detectXmlEncodingFromHeader(headerText) {
  const match = _readString(headerText).match(/<\?xml[^>]*encoding\s*=\s*["']([^"']+)["']/i);
  return _normalizeXmlEncodingName(match?.[1] || "");
}

function _extractXmlFromPayload(payloadText) {
  const text = _readString(payloadText);
  if (!text) return null;

  if (_looksLikeXmlPayloadText(text)) {
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
      if (_looksLikeXmlPayloadText(raw)) {
        return raw;
      }
      try {
        const decodedUtf8 = Buffer.from(raw, "base64").toString("utf8");
        if (_looksLikeXmlPayloadText(decodedUtf8)) {
          return decodedUtf8;
        }
        const decodedLatin1 = Buffer.from(raw, "base64").toString("latin1");
        if (_looksLikeXmlPayloadText(decodedLatin1)) {
          return decodedLatin1;
        }
      } catch (_) {}
    }
  } catch (_) {}

  return null;
}

function _extractXmlPayload(payloadBuffer, payloadText = "") {
  const bodyBuffer = Buffer.isBuffer(payloadBuffer) ? payloadBuffer : Buffer.from(payloadBuffer || "");
  if (bodyBuffer.length > 0) {
    const utf8Text = bodyBuffer.toString("utf8");
    const latin1Text = bodyBuffer.toString("latin1");
    const utf8LooksXml = _looksLikeXmlPayloadText(utf8Text);
    const latin1LooksXml = _looksLikeXmlPayloadText(latin1Text);

    if (utf8LooksXml || latin1LooksXml) {
      let xmlText = utf8LooksXml ? utf8Text : latin1Text;
      const declaredEncoding = _detectXmlEncodingFromHeader(xmlText);
      if (declaredEncoding === "latin1" && latin1LooksXml) {
        xmlText = latin1Text;
      } else if (declaredEncoding === "utf8" && utf8LooksXml) {
        xmlText = utf8Text;
      } else if (utf8Text.includes("\uFFFD") && latin1LooksXml) {
        xmlText = latin1Text;
      }

      return {
        xmlText,
        xmlBuffer: Buffer.from(bodyBuffer),
      };
    }
  }

  const xmlText = _extractXmlFromPayload(payloadText);
  if (!xmlText) return null;
  const encoding = _detectXmlEncodingFromHeader(xmlText) === "latin1" ? "latin1" : "utf8";
  return {
    xmlText,
    xmlBuffer: Buffer.from(xmlText, encoding),
  };
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

function _findNestedValueByKeys(input, keysLower, depth = 0) {
  if (depth > 12 || input == null) return "";
  if (typeof input === "string" || typeof input === "number" || typeof input === "boolean") {
    return "";
  }

  if (Array.isArray(input)) {
    for (const item of input) {
      const found = _findNestedValueByKeys(item, keysLower, depth + 1);
      if (found) return found;
    }
    return "";
  }

  if (typeof input !== "object") return "";

  for (const [key, value] of Object.entries(input)) {
    const normalizedKey = _toLower(key);
    if (keysLower.includes(normalizedKey)) {
      if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
        return String(value).trim();
      }
    }
  }

  for (const value of Object.values(input)) {
    const found = _findNestedValueByKeys(value, keysLower, depth + 1);
    if (found) return found;
  }

  return "";
}

function _extractXmlTagValue(xmlText, tagNames) {
  const text = _readString(xmlText);
  if (!text) return "";

  for (const tag of tagNames) {
    const regex = new RegExp(`<\\s*${tag}\\s*>\\s*([^<]+)\\s*<\\s*\\/\\s*${tag}\\s*>`, "i");
    const match = text.match(regex);
    if (match?.[1]) {
      return _readString(match[1]);
    }
  }

  return "";
}

function _extractSiiMetaFromPayload(payloadText) {
  const text = _readString(payloadText);
  if (!text) {
    return {
      trackId: "",
      receivedAt: "",
      statusCode: "",
    };
  }

  let parsedJson = null;
  try {
    parsedJson = JSON.parse(text);
  } catch (_) {
    parsedJson = null;
  }

  const trackKeyCandidates = ["trackid", "track_id", "nroenvio", "nro_envio"];
  const dateKeyCandidates = [
    "timestamp",
    "fecha",
    "fecharecepcion",
    "fecha_recepcion",
    "fchrecep",
    "tmstfirmaenv",
  ];
  const statusKeyCandidates = ["status", "estado", "codestado", "codigoestado", "codstatus"];

  const fromJsonTrack = parsedJson ?
    _findNestedValueByKeys(parsedJson, trackKeyCandidates) :
    "";
  const fromJsonDate = parsedJson ?
    _findNestedValueByKeys(parsedJson, dateKeyCandidates) :
    "";
  const fromJsonStatus = parsedJson ?
    _findNestedValueByKeys(parsedJson, statusKeyCandidates) :
    "";

  const fromXmlTrack = _extractXmlTagValue(text, ["TRACKID", "TrackId", "NroEnvio", "NROENVIO"]);
  const fromXmlDate = _extractXmlTagValue(
    text,
    ["TIMESTAMP", "TmstFirmaEnv", "FchRecep", "FechaRecepcion", "TmstFirma"],
  );
  const fromXmlStatus = _extractXmlTagValue(
    text,
    ["STATUS", "ESTADO", "CodEstado", "CodigoEstado"],
  );

  return {
    trackId: _firstNonEmpty(fromJsonTrack, fromXmlTrack),
    receivedAt: _firstNonEmpty(fromJsonDate, fromXmlDate),
    statusCode: _firstNonEmpty(fromJsonStatus, fromXmlStatus),
  };
}

function _resolveSimpleApiEndpoint(baseUrl, explicitUrl, fallbackPath) {
  const explicit = _readString(explicitUrl);
  if (explicit) return explicit;
  return `${baseUrl.replace(/\/+$/, "")}${fallbackPath}`;
}

function _resolveSimpleApiPdfEndpoint({
  baseUrl,
  explicitUrl,
  preferCedible = false,
}) {
  const fallbackPath = preferCedible ?
    "/api/v1/impresion/pdf/carta/v2/cedible" :
    "/api/v1/impresion/pdf/carta/v2";
  const resolved = _resolveSimpleApiEndpoint(baseUrl, explicitUrl, fallbackPath).replace(/\/+$/, "");
  if (!preferCedible) return resolved;

  try {
    const parsed = new URL(resolved);
    if (!parsed.pathname.toLowerCase().endsWith("/cedible")) {
      parsed.pathname = `${parsed.pathname.replace(/\/+$/, "")}/cedible`;
    }
    return parsed.toString();
  } catch (_) {
    return resolved.toLowerCase().endsWith("/cedible") ? resolved : `${resolved}/cedible`;
  }
}

function _resolvePdfFileName({preferCedible = false}) {
  return preferCedible ? "invoice_cedible.pdf" : "invoice.pdf";
}

async function _postSimpleApiMultipart({
  url,
  apiKey,
  inputPayload,
  files = [],
  includeInputField = true,
}) {
  const endpointUrl = _readString(url);
  const form = new FormData();
  if (includeInputField) {
    form.append("input", JSON.stringify(inputPayload || {}));
  }

  for (const file of files) {
    const rawFieldName = _readString(file?.fieldName);
    const fieldName = rawFieldName;
    if (!fieldName) continue;
    const fileName = _readString(file?.fileName) || "payload.bin";
    const contentType = _readString(file?.contentType) || "application/octet-stream";
    const contentBuffer = Buffer.isBuffer(file?.buffer) ?
      file.buffer :
      Buffer.from(file?.buffer || "");
    form.append(fieldName, new Blob([contentBuffer], {type: contentType}), fileName);
  }

  const basicAuth = `Basic ${Buffer.from(`api:${apiKey}`, "utf8").toString("base64")}`;
  const response = await fetch(endpointUrl, {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "Authorization": basicAuth,
    },
    body: form,
  });

  const bodyBuffer = Buffer.from(await response.arrayBuffer());
  const bodyText = bodyBuffer.toString("utf8");

  return {
    ok: response.ok,
    statusCode: response.status,
    contentType: _readString(response.headers.get("content-type")),
    bodyBuffer,
    bodyText,
  };
}

function _sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, Math.round(_asNumber(ms)))));
}

function _isTransientSimpleApiSendFailure(statusCode, bodyText) {
  const normalizedStatus = Math.round(_asNumber(statusCode));
  if (normalizedStatus >= 500) return true;

  const normalizedBody = _normalizeErrorText(bodyText);
  if (!normalizedBody) return false;

  if (normalizedBody.includes("trackid\":-999999")) return true;
  if (normalizedBody.includes("an error occurred while sending the request")) return true;
  if (normalizedBody.includes("system.net.webexception")) return true;
  if (normalizedBody.includes("\"estado\":\"error\"") && normalizedBody.includes("\"ok\":true")) {
    return true;
  }

  return false;
}

function _buildSimpleApiEnvioInput({
  certRut,
  pfxPassword,
  emisorRut,
  includeCaratula = false,
  includeAuth = false,
}) {
  const requestedTipoEnvio = _readInteger(process.env.SIMPLEAPI_SII_SEND_TYPE, 1);
  const tipoEnvio = [1, 2].includes(requestedTipoEnvio) ? requestedTipoEnvio : 1;
  const ambiente = Math.max(0, _readInteger(process.env.SIMPLEAPI_SII_AMBIENTE, 0));
  const authRut = _readString(process.env.SIMPLEAPI_SII_AUTH_RUT);
  const authPassword = _readString(process.env.SIMPLEAPI_SII_AUTH_PASSWORD);
  const notificacionEmail = _readString(process.env.SIMPLEAPI_SII_NOTIFICACION_EMAIL);

  const certRuta = _readString(process.env.SIMPLEAPI_SII_CERT_RUTA) ||
    _readString(process.env.SIMPLEAPI_PFX_STORAGE_PATH);
  const payload = {
    Certificado: {
      Ruta: certRuta || undefined,
      Rut: certRut || undefined,
      Password: pfxPassword || undefined,
    },
    Tipo: tipoEnvio,
    Ambiente: ambiente,
    CorreoNotificacion: notificacionEmail || undefined,
  };

  if (includeAuth && authRut && authPassword) {
    payload.Autenticacion = {
      Rut: authRut,
      Password: authPassword,
    };
  }

  if (includeCaratula) {
    payload.Caratula = {
      RutEmisor: emisorRut,
      RutReceptor: _readString(process.env.SIMPLEAPI_SII_RECEPTOR_RUT) || "60803000-K",
      FechaResolucion:
        _readString(process.env.SIMPLEAPI_SII_RESOLUTION_DATE) ||
        _safeIsoDate(new Date().toISOString()),
      NumeroResolucion: Math.max(0, _readInteger(process.env.SIMPLEAPI_SII_RESOLUTION_NUMBER, 0)),
    };
  }

  return payload;
}

async function _sendDteToSiiIfEnabled({
  bucket,
  invoiceId,
  apiKey,
  baseUrl,
  xmlPayloadBuffer,
  pfxBuffer,
  certRut,
  emisorRut,
}) {
  const enabled = _readBoolean(process.env.SIMPLEAPI_ENABLE_SII_SEND, false);
  if (!enabled) {
    return {
      enabled: false,
      sendResponsePath: null,
      sendStatusPath: null,
      trackId: "",
      receivedAt: "",
      statusCode: "",
    };
  }

  const pfxPassword = _readString(process.env.SIMPLEAPI_PFX_PASSWORD);
  if (!pfxPassword) {
    throw new Error("Missing SIMPLEAPI_PFX_PASSWORD for SII send");
  }

  const envioGenerarUrl = _resolveSimpleApiEndpoint(
    baseUrl,
    process.env.SIMPLEAPI_ENVIO_GENERATE_URL,
    "/api/v1/envio/generar",
  );
  const envioEnviarUrl = _resolveSimpleApiEndpoint(
    baseUrl,
    process.env.SIMPLEAPI_ENVIO_SEND_URL,
    "/api/v1/envio/enviar",
  );
  const consultaEnvioUrl = _resolveSimpleApiEndpoint(
    baseUrl,
    process.env.SIMPLEAPI_CONSULTA_ENVIO_URL,
    "/api/v1/consulta/envio",
  );
  const includeSiiAuth = _readBoolean(process.env.SIMPLEAPI_SII_INCLUDE_AUTH, false);
  const sendRetryLimit = Math.max(
    0,
    Math.min(3, _readInteger(process.env.SIMPLEAPI_ENVIO_SEND_RETRY_LIMIT, 1)),
  );
  const sendRetryBackoffMs = Math.max(
    250,
    Math.min(5000, _readInteger(process.env.SIMPLEAPI_ENVIO_SEND_RETRY_BACKOFF_MS, 1200)),
  );
  const hasAuthCredentials = Boolean(
    _readString(process.env.SIMPLEAPI_SII_AUTH_RUT) &&
    _readString(process.env.SIMPLEAPI_SII_AUTH_PASSWORD),
  );

  const generarInput = _buildSimpleApiEnvioInput({
    certRut,
    pfxPassword,
    emisorRut,
    includeCaratula: true,
    includeAuth: includeSiiAuth,
  });

  const generarResponse = await _postSimpleApiMultipart({
    url: envioGenerarUrl,
    apiKey,
    inputPayload: generarInput,
    files: [
      {fieldName: "files", fileName: `certificado_temp_${Date.now()}.pfx`, buffer: pfxBuffer},
      {fieldName: "files2", fileName: `archivo_dte_${Date.now()}.xml`, buffer: xmlPayloadBuffer},
    ],
  });

  if (!generarResponse.ok) {
    throw new Error(
      `Envio generation failed (${generarResponse.statusCode}) [${envioGenerarUrl}]: ${generarResponse.bodyText.slice(0, 300)}`,
    );
  }

  const generatedEnvelope = _extractXmlPayload(generarResponse.bodyBuffer, generarResponse.bodyText);
  if (!generatedEnvelope) {
    throw new Error("Envio generation response did not include a valid XML envelope");
  }
  const generatedEnvelopeBuffer = generatedEnvelope.xmlBuffer;

  const envioXmlPath = `invoices/${invoiceId}/sii/envio.xml`;
  await bucket.file(envioXmlPath).save(generatedEnvelopeBuffer, {
    resumable: false,
    contentType: "application/xml",
    metadata: {cacheControl: "private, max-age=0, no-store"},
  });

  const authStrategies = includeSiiAuth && hasAuthCredentials ?
    [true, false] :
    [false];
  let enviarResponse = null;
  let sendResponsePath = null;
  let lastSendErrorMessage = "";

  for (const useAuth of authStrategies) {
    const enviarInput = _buildSimpleApiEnvioInput({
      certRut,
      pfxPassword,
      emisorRut,
      includeCaratula: false,
      includeAuth: useAuth,
    });

    for (let attempt = 0; attempt <= sendRetryLimit; attempt++) {
      const currentResponse = await _postSimpleApiMultipart({
        url: envioEnviarUrl,
        apiKey,
        inputPayload: enviarInput,
        files: [
          {fieldName: "files", fileName: `certificado_temp_${Date.now()}.pfx`, buffer: pfxBuffer},
          {fieldName: "files2", fileName: `envio_sii_${Date.now()}.xml`, buffer: generatedEnvelopeBuffer},
        ],
      });

      const responsePath =
        authStrategies.length > 1 || sendRetryLimit > 0 ?
          `invoices/${invoiceId}/sii/envio-response-${useAuth ? "auth" : "cert"}-try-${attempt + 1}.txt` :
          `invoices/${invoiceId}/sii/envio-response.txt`;

      await bucket.file(responsePath).save(currentResponse.bodyBuffer, {
        resumable: false,
        contentType: "text/plain; charset=utf-8",
        metadata: {cacheControl: "private, max-age=0, no-store"},
      });
      sendResponsePath = responsePath;

      if (currentResponse.ok) {
        enviarResponse = currentResponse;
        break;
      }

      lastSendErrorMessage =
        `Envio send failed (${currentResponse.statusCode}) [${envioEnviarUrl}]` +
        ` [mode=${useAuth ? "auth" : "cert"} try=${attempt + 1}]: ${currentResponse.bodyText.slice(0, 900)}`;

      const isTransient = _isTransientSimpleApiSendFailure(
        currentResponse.statusCode,
        currentResponse.bodyText,
      );
      const hasRetryLeft = attempt < sendRetryLimit;
      if (isTransient && hasRetryLeft) {
        logger.warn("Transient Envio send failure, retrying", {
          invoiceId,
          mode: useAuth ? "auth" : "cert",
          try: attempt + 1,
          statusCode: currentResponse.statusCode,
        });
        await _sleep(sendRetryBackoffMs * (attempt + 1));
        continue;
      }

      break;
    }

    if (enviarResponse?.ok) break;

    if (authStrategies.length > 1 && useAuth) {
      logger.warn("Envio send failed with auth, retrying in certificate-only mode", {
        invoiceId,
        status: lastSendErrorMessage,
      });
    }
  }

  if (!enviarResponse?.ok) {
    throw new Error(lastSendErrorMessage || `Envio send failed [${envioEnviarUrl}]`);
  }

  const sendMeta = _extractSiiMetaFromPayload(enviarResponse.bodyText);
  const trackIdNumeric = Math.round(_asNumber(sendMeta.trackId));
  const canQueryStatus = _readBoolean(process.env.SIMPLEAPI_ENABLE_SII_STATUS_QUERY, true) &&
    trackIdNumeric > 0;

  let sendStatusPath = null;
  let statusMeta = {
    trackId: sendMeta.trackId,
    receivedAt: sendMeta.receivedAt,
    statusCode: sendMeta.statusCode,
  };

  if (canQueryStatus) {
    const consultaInput = {
      Certificado: {
        Ruta: _readString(process.env.SIMPLEAPI_SII_CERT_RUTA) ||
          _readString(process.env.SIMPLEAPI_PFX_STORAGE_PATH) ||
          undefined,
        Rut: certRut || undefined,
        Password: pfxPassword || undefined,
      },
      RutEmpresa: emisorRut,
      TrackId: trackIdNumeric,
      ServidorBoletaREST: false,
      Ambiente: Math.max(0, _readInteger(process.env.SIMPLEAPI_SII_AMBIENTE, 0)),
    };

    const consultaResponse = await _postSimpleApiMultipart({
      url: consultaEnvioUrl,
      apiKey,
      inputPayload: consultaInput,
      files: [
        {fieldName: "files", fileName: `certificado_temp_${Date.now()}.pfx`, buffer: pfxBuffer},
      ],
    });

    sendStatusPath = `invoices/${invoiceId}/sii/envio-status.txt`;
    await bucket.file(sendStatusPath).save(consultaResponse.bodyBuffer, {
      resumable: false,
      contentType: "text/plain; charset=utf-8",
      metadata: {cacheControl: "private, max-age=0, no-store"},
    });

    if (consultaResponse.ok) {
      const queriedMeta = _extractSiiMetaFromPayload(consultaResponse.bodyText);
      statusMeta = {
        trackId: _firstNonEmpty(queriedMeta.trackId, statusMeta.trackId),
        receivedAt: _firstNonEmpty(queriedMeta.receivedAt, statusMeta.receivedAt),
        statusCode: _firstNonEmpty(queriedMeta.statusCode, statusMeta.statusCode),
      };
    }
  }

  return {
    enabled: true,
    envioXmlPath,
    sendResponsePath,
    sendStatusPath,
    trackId: statusMeta.trackId,
    receivedAt: statusMeta.receivedAt,
    statusCode: statusMeta.statusCode,
  };
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

function _isSimpleApiFileSpecifiedError(statusCode, bodyText) {
  if (Number(statusCode) !== 400) return false;
  const normalized = _normalizeErrorText(bodyText);
  return normalized.includes("cannot find the file specified") ||
    normalized.includes("faltan los archivos en form-data") ||
    normalized.includes("hay al menos un tipo de archivo incorrecto") ||
    normalized.includes("debe ser un archivo xml con formato dte");
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

function _computeRutDv(body) {
  let sum = 0;
  let multiplier = 2;

  for (let i = body.length - 1; i >= 0; i--) {
    sum += Number(body[i]) * multiplier;
    multiplier = multiplier === 7 ? 2 : multiplier + 1;
  }

  const remainder = 11 - (sum % 11);
  if (remainder === 11) return "0";
  if (remainder === 10) return "K";
  return String(remainder);
}

function _hasValidRutDv(rut) {
  if (!_isValidRutShape(rut)) return false;

  const parts = rut.split("-");
  const body = parts[0];
  const dv = parts[1];
  if (!body || !dv) return false;

  return _computeRutDv(body) === dv;
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

function _toMoneyInt(value) {
  return Math.max(0, Math.round(_asNumber(value)));
}

function _firstFiniteNumber(...values) {
  for (const value of values) {
    const n = Number(value);
    if (Number.isFinite(n)) return n;
  }
  return 0;
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
  if (!_hasValidRutDv(receiverRut)) {
    throw new Error("Invalid RUT DV for factura receptor");
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
  if (!_hasValidRutDv(emisorRut)) {
    throw new Error("Invalid SIMPLEAPI_EMISOR_RUT DV");
  }
  if (!_isValidRutShape(certRut)) {
    throw new Error("Invalid SIMPLEAPI_CERT_RUT format");
  }
  if (!_hasValidRutDv(certRut)) {
    throw new Error("Invalid SIMPLEAPI_CERT_RUT DV");
  }
  const emisorActivityCodes = _parseNumericCsv(process.env.SIMPLEAPI_EMISOR_ACTIVITY_CODES);
  if (emisorActivityCodes.length === 0) {
    throw new Error(
      "Missing SIMPLEAPI_EMISOR_ACTIVITY_CODES. Configure at least one valid SII Acteco code, e.g. 532000.",
    );
  }

  const lines = Array.isArray(order?.items) ? order.items : [];
  const normalizedItems = [];
  for (let idx = 0; idx < lines.length; idx++) {
    const item = lines[idx] || {};
    const description = _toMaxLength(
      _firstNonEmpty(
        item?.titleSnapshot,
        item?.title,
        item?.name,
        item?.description,
        `Item ${idx + 1}`,
      ),
      80,
    );
    const qty = Math.max(
      1,
      Math.round(
        _firstFiniteNumber(
          item?.qty,
          item?.quantity,
          item?.cantidad,
          1,
        ),
      ),
    );
    let unitPrice = _toMoneyInt(
      _firstFiniteNumber(
        item?.unitPriceSnapshot,
        item?.unitPrice,
        item?.unit_price,
        item?.price,
        item?.valorUnitario,
      ),
    );
    let lineTotal = _toMoneyInt(
      _firstFiniteNumber(
        item?.lineTotalSnapshot,
        item?.lineTotal,
        item?.totalPriceSnapshot,
        item?.totalPrice,
        item?.total,
        item?.amount,
        item?.monto,
        item?.montoItem,
      ),
    );
    if (lineTotal <= 0 && qty > 0 && unitPrice > 0) {
      lineTotal = qty * unitPrice;
    }
    if (unitPrice <= 0 && qty > 0 && lineTotal > 0) {
      unitPrice = Math.max(1, Math.round(lineTotal / qty));
    }
    if (lineTotal <= 0) continue;

    normalizedItems.push({
      Nombre: description,
      Descripcion: description,
      Cantidad: qty,
      UnidadMedida: "un",
      Precio: unitPrice,
      Descuento: 0,
      Recargo: 0,
      MontoItem: lineTotal,
    });
  }

  const deliveryFee = _toMoneyInt(_firstFiniteNumber(
    order?.deliveryFee,
    order?.shippingCost,
    order?.shippingFee,
  ));
  if (deliveryFee > 0) {
    normalizedItems.push({
      Nombre: "Costo de envio",
      Descripcion: "Tarifa de entrega",
      Cantidad: 1,
      UnidadMedida: "un",
      Precio: deliveryFee,
      Descuento: 0,
      Recargo: 0,
      MontoItem: deliveryFee,
    });
  }

  const serviceFee = _toMoneyInt(_firstFiniteNumber(
    order?.serviceFee,
    order?.platformFee,
  ));
  if (serviceFee > 0) {
    normalizedItems.push({
      Nombre: "Tarifa de servicio",
      Descripcion: "Comision de plataforma",
      Cantidad: 1,
      UnidadMedida: "un",
      Precio: serviceFee,
      Descuento: 0,
      Recargo: 0,
      MontoItem: serviceFee,
    });
  }

  if (normalizedItems.length === 0) {
    throw new Error("Order has no billable items");
  }

  const derivedNetFromLines = normalizedItems.reduce(
    (acc, line) => acc + Math.round(_asNumber(line.MontoItem)),
    0,
  );
  const tipAmount = _toMoneyInt(order?.tip);
  const orderSubtotal = _toMoneyInt(order?.subtotal);
  const orderTax = _toMoneyInt(order?.tax);
  const rawOrderTotal = _toMoneyInt(order?.amountTotal);
  const orderTotalWithoutTip = Math.max(0, rawOrderTotal - tipAmount);

  let subtotal = derivedNetFromLines;
  if (subtotal <= 0 && orderSubtotal > 0) {
    subtotal = orderSubtotal;
  }

  let taxAmount = orderTax;
  if (taxAmount <= 0 && orderTotalWithoutTip > subtotal) {
    taxAmount = Math.max(0, orderTotalWithoutTip - subtotal);
  }

  let total = orderTotalWithoutTip;
  if (total <= 0) {
    total = subtotal + taxAmount;
  }
  if (total < subtotal + taxAmount) {
    total = subtotal + taxAmount;
  }

  // Keep DTE totals aligned with detail lines to avoid SII reparos (HED-2-210).
  subtotal = derivedNetFromLines;
  if (total < subtotal + taxAmount) {
    total = subtotal + taxAmount;
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
  const preferCediblePdf = _readBoolean(
    order?.pdf?.cedible,
    _readBoolean(process.env.SIMPLEAPI_PDF_USE_CEDIBLE, true),
  );
  const dteEndpoint = _readString(process.env.SIMPLEAPI_DTE_GENERATE_URL) ||
    `${baseUrl.replace(/\/+$/, "")}/api/v1/dte/generar`;
  const pdfEndpoint = _resolveSimpleApiPdfEndpoint({
    baseUrl,
    explicitUrl: process.env.SIMPLEAPI_PDF_GENERATE_URL,
    preferCedible: preferCediblePdf,
  });
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
    let dteResponse = await _postSimpleApiMultipart({
      url: dteEndpoint,
      apiKey,
      inputPayload: dteInput,
      files: [
        {
          fieldName: "files",
          fileName: `certificado_temp_${Date.now()}.pfx`,
          buffer: pfxBuffer,
          contentType: "application/x-pkcs12",
        },
        {
          fieldName: "files2",
          fileName: `archivo_caf_${Date.now()}.xml`,
          buffer: cafBuffer,
          contentType: "text/xml",
        },
      ],
    });

    if (_isSimpleApiFileSpecifiedError(dteResponse.statusCode, dteResponse.bodyText)) {
      logger.warn("DTE_GENERATE_RETRY_LEGACY_FILE_FIELDS", {
        orderId,
        invoiceId,
        folio: currentFolio,
        statusCode: dteResponse.statusCode,
        responseBody: _readString(dteResponse.bodyText).slice(0, 900),
      });
      dteResponse = await _postSimpleApiMultipart({
        url: dteEndpoint,
        apiKey,
        inputPayload: dteInput,
        files: [
          {
            fieldName: "file",
            fileName: `certificado_temp_${Date.now()}.pfx`,
            buffer: pfxBuffer,
            contentType: "application/x-pkcs12",
          },
          {
            fieldName: "file",
            fileName: `archivo_caf_${Date.now()}.xml`,
            buffer: cafBuffer,
            contentType: "text/xml",
          },
        ],
      });
    }

    dteStatusCode = dteResponse.statusCode;
    dteBodyBuffer = dteResponse.bodyBuffer;
    dteBodyText = dteResponse.bodyText;
    if (dteResponse.ok) {
      break;
    }

    const shouldRetryWithNextFolio = attempt < maxFolioRetries &&
      _isFolioAlreadyUsedError(dteStatusCode, dteBodyText);
    if (!shouldRetryWithNextFolio) {
      throw new Error(
        `DTE generation failed (${dteStatusCode}) [${dteEndpoint}]: ${dteBodyText.slice(0, 900)}`,
      );
    }

    logger.warn("DTE rejected due to used folio, retrying with next folio", {
      orderId,
      invoiceId,
      attemptedFolio: currentFolio,
      attempt: attempt + 1,
      maxFolioRetries,
      statusCode: dteStatusCode,
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

  const xmlPayloadInfo = _extractXmlPayload(dteBodyBuffer, dteBodyText);
  if (!xmlPayloadInfo) {
    throw new Error(
      `DTE response did not include a valid XML payload (status=${dteStatusCode})`,
    );
  }
  const xmlPayloadBuffer = xmlPayloadInfo.xmlBuffer;

  const bucket = outputBucketName ?
    admin.storage().bucket(outputBucketName) :
    admin.storage().bucket();
  const dteGenerateMeta = _extractSiiMetaFromPayload(dteBodyText);
  const dteGenerateResponsePath = `invoices/${invoiceId}/dte-generate-response.txt`;
  await bucket.file(dteGenerateResponsePath).save(dteBodyBuffer, {
    resumable: false,
    contentType: "text/plain; charset=utf-8",
    metadata: {cacheControl: "private, max-age=0, no-store"},
  });

  const xmlPath = `invoices/${invoiceId}/dte.xml`;
  await bucket.file(xmlPath).save(xmlPayloadBuffer, {
    resumable: false,
    contentType: "application/xml",
    metadata: {cacheControl: "private, max-age=0, no-store"},
  });

  const siiSendEnabled = _readBoolean(process.env.SIMPLEAPI_ENABLE_SII_SEND, false);
  const requireSiiSend = _readBoolean(process.env.SIMPLEAPI_REQUIRE_SII_SEND, true);
  let siiSendResult = {
    enabled: false,
    envioXmlPath: null,
    sendResponsePath: null,
    sendStatusPath: null,
    trackId: "",
    receivedAt: "",
    statusCode: "",
  };

  if (siiSendEnabled) {
    try {
      siiSendResult = await _sendDteToSiiIfEnabled({
        bucket,
        invoiceId,
        apiKey,
        baseUrl,
        xmlPayloadBuffer,
        pfxBuffer,
        certRut,
        emisorRut,
      });
    } catch (error) {
      const message = _readString(error?.message) || "Unknown SII send error";
      if (requireSiiSend) {
        throw new Error(message);
      }
      logger.error("SII send failed but continuing due to SIMPLEAPI_REQUIRE_SII_SEND=false", {
        orderId,
        invoiceId,
        error: message,
      });
    }
  }

  const pdfInput = _buildPdfInput({order, sellerLabel});
  const pdfSellerLabel = _readString(pdfInput?.Vendedor);
  const pdfForm = new FormData();
  pdfForm.append("input", JSON.stringify(pdfInput));
  pdfForm.append("fileEnvio", new Blob([xmlPayloadBuffer]), "dte.xml");
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

  const pdfPath = `invoices/${invoiceId}/${_resolvePdfFileName({preferCedible: preferCediblePdf})}`;
  await bucket.file(pdfPath).save(pdfBuffer, {
    resumable: false,
    contentType: "application/pdf",
    metadata: {cacheControl: "private, max-age=0, no-store"},
  });

  const xmlStoragePath = `gs://${bucket.name}/${xmlPath}`;
  const pdfStoragePath = `gs://${bucket.name}/${pdfPath}`;
  const resolvedTrackId = _firstNonEmpty(siiSendResult.trackId, dteGenerateMeta.trackId) || null;
  const resolvedReceivedAt =
    _firstNonEmpty(siiSendResult.receivedAt, dteGenerateMeta.receivedAt) || null;
  const resolvedStatusCode =
    _firstNonEmpty(siiSendResult.statusCode, dteGenerateMeta.statusCode) || null;

  return {
    folio: currentFolio,
    cafFolioFrom: cafFolioRange.from,
    cafFolioTo: cafFolioRange.to,
    xmlPath,
    pdfPath,
    pdfCedible: preferCediblePdf,
    xmlStoragePath,
    pdfStoragePath,
    providerDocumentId: invoiceId,
    providerTrackId: resolvedTrackId,
    providerReceivedAt: resolvedReceivedAt,
    providerStatusCode: resolvedStatusCode,
    dteGenerateResponsePath,
    siiEnvioXmlPath: siiSendResult.envioXmlPath || null,
    siiSendResponsePath: siiSendResult.sendResponsePath || null,
    siiStatusResponsePath: siiSendResult.sendStatusPath || null,
    siiSendEnabled,
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
    secrets: [],
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
        providerReceivedAt: emission.providerReceivedAt || null,
        providerStatusCode: emission.providerStatusCode || null,
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
          dteGenerateResponsePath: emission.dteGenerateResponsePath || null,
          siiEnvioXmlPath: emission.siiEnvioXmlPath || null,
          siiSendResponsePath: emission.siiSendResponsePath || null,
          siiStatusResponsePath: emission.siiStatusResponsePath || null,
          siiSendEnabled: emission.siiSendEnabled === true,
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
    secrets: [],
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
      providerReceivedAt: null,
      providerStatusCode: null,
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
        providerReceivedAt: emission.providerReceivedAt || null,
        providerStatusCode: emission.providerStatusCode || null,
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
          dteGenerateResponsePath: emission.dteGenerateResponsePath || null,
          siiEnvioXmlPath: emission.siiEnvioXmlPath || null,
          siiSendResponsePath: emission.siiSendResponsePath || null,
          siiStatusResponsePath: emission.siiStatusResponsePath || null,
          siiSendEnabled: emission.siiSendEnabled === true,
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

