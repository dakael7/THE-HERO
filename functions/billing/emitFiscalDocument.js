const {onCall, HttpsError} = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const crypto = require('crypto');

const FISCAL_REGION = 'southamerica-west1';
const SUPPORTED_TIPO_DTE = new Set([33, 34, 39, 41, 46, 52, 56, 61]);

function _readString(value) {
  if (typeof value !== 'string') return '';
  return value.trim();
}

function _toLower(value) {
  return _readString(value).toLowerCase();
}

function _asNumber(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return n;
}

function _readBoolean(value, fallback = false) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') {
    if (value === 1) return true;
    if (value === 0) return false;
  }
  const normalized = _toLower(value);
  if (!normalized) return fallback;
  if (['1', 'true', 'yes', 'y', 'si', 'on'].includes(normalized)) return true;
  if (['0', 'false', 'no', 'n', 'off'].includes(normalized)) return false;
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
    .replace(/\s+/g, '')
    .replace(/\./g, '')
    .replace(/[^0-9K-]/g, '');

  if (!raw) return '';

  if (raw.includes('-')) {
    const [body, dv] = raw.split('-');
    if (!body || !dv) return '';
    return `${body}-${dv}`;
  }

  if (raw.length < 2) return '';
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
  if (remainder === 11) return '0';
  if (remainder === 10) return 'K';
  return String(remainder);
}

function _hasValidRutDv(rut) {
  if (!_isValidRutShape(rut)) return false;
  const parts = rut.split('-');
  const body = parts[0];
  const dv = parts[1];
  if (!body || !dv) return false;
  return _computeRutDv(body) === dv;
}

function _toMoneyInt(value) {
  return Math.round(_asNumber(value));
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
  return '';
}

function _toMaxLength(value, maxLength) {
  const normalized = _readString(value);
  if (!normalized) return '';
  if (normalized.length <= maxLength) return normalized;
  return normalized.slice(0, maxLength);
}

function _parseNumericCsv(value) {
  const raw = _readString(value);
  if (!raw) return [];
  return raw
    .split(',')
    .map((part) => Number(part.trim()))
    .filter((num) => Number.isInteger(num) && num > 0);
}

function _normalizeTaxCodeList(value) {
  const out = [];
  const seen = new Set();
  const pushCode = (rawCode) => {
    const n = Math.round(_asNumber(rawCode));
    if (!Number.isInteger(n) || n <= 0 || seen.has(n)) return;
    seen.add(n);
    out.push(n);
  };

  const source = Array.isArray(value) ? value : [value];
  for (const part of source) {
    if (Array.isArray(part)) {
      for (const nested of part) pushCode(nested);
      continue;
    }
    if (typeof part === 'string') {
      const chunks = part.split(',');
      for (const chunk of chunks) pushCode(chunk.trim());
      continue;
    }
    pushCode(part);
  }

  return out;
}

function _looksLikeXmlPayloadText(value) {
  const text = _readString(value);
  if (!text) return false;
  return text.startsWith('<?xml') ||
    text.startsWith('<DTE') ||
    text.startsWith('<Envio') ||
    text.startsWith('<SetDTE') ||
    text.startsWith('<RECEPCIONDTE');
}

function _normalizeXmlEncodingName(value) {
  const normalized = _toLower(value).replace(/[_\s]/g, '');
  if (!normalized) return '';
  if (
    normalized.includes('8859-1') ||
    normalized.includes('iso88591') ||
    normalized.includes('latin1')
  ) {
    return 'latin1';
  }
  if (normalized.includes('utf-8') || normalized.includes('utf8')) {
    return 'utf8';
  }
  return '';
}

function _detectXmlEncodingFromHeader(headerText) {
  const match = _readString(headerText).match(/<\?xml[^>]*encoding\s*=\s*["']([^"']+)["']/i);
  return _normalizeXmlEncodingName(match?.[1] || '');
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
        const decodedUtf8 = Buffer.from(raw, 'base64').toString('utf8');
        if (_looksLikeXmlPayloadText(decodedUtf8)) {
          return decodedUtf8;
        }
        const decodedLatin1 = Buffer.from(raw, 'base64').toString('latin1');
        if (_looksLikeXmlPayloadText(decodedLatin1)) {
          return decodedLatin1;
        }
      } catch (_) {}
    }
  } catch (_) {}

  return null;
}

function _extractXmlPayload(payloadBuffer, payloadText = '') {
  const bodyBuffer = Buffer.isBuffer(payloadBuffer) ? payloadBuffer : Buffer.from(payloadBuffer || '');
  if (bodyBuffer.length > 0) {
    const utf8Text = bodyBuffer.toString('utf8');
    const latin1Text = bodyBuffer.toString('latin1');
    const utf8LooksXml = _looksLikeXmlPayloadText(utf8Text);
    const latin1LooksXml = _looksLikeXmlPayloadText(latin1Text);

    if (utf8LooksXml || latin1LooksXml) {
      let xmlText = utf8LooksXml ? utf8Text : latin1Text;
      const declaredEncoding = _detectXmlEncodingFromHeader(xmlText);
      if (declaredEncoding === 'latin1' && latin1LooksXml) {
        xmlText = latin1Text;
      } else if (declaredEncoding === 'utf8' && utf8LooksXml) {
        xmlText = utf8Text;
      } else if (utf8Text.includes('\uFFFD') && latin1LooksXml) {
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
  const encoding = _detectXmlEncodingFromHeader(xmlText) === 'latin1' ? 'latin1' : 'utf8';
  return {
    xmlText,
    xmlBuffer: Buffer.from(xmlText, encoding),
  };
}

function _extractPdfBuffer(contentType, bodyBuffer, bodyText) {
  const normalizedContentType = _toLower(contentType);
  if (normalizedContentType.includes('application/pdf')) {
    return bodyBuffer;
  }

  if (bodyBuffer && bodyBuffer.length >= 4) {
    const signature = bodyBuffer.subarray(0, 4).toString('utf8');
    if (signature === '%PDF') {
      return bodyBuffer;
    }
  }

  const text = _readString(bodyText);
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
        const buffer = Buffer.from(raw, 'base64');
        if (buffer.length >= 4 && buffer.subarray(0, 4).toString('utf8') === '%PDF') {
          return buffer;
        }
      } catch (_) {}
    }
  } catch (_) {}

  return null;
}

function _findNestedValueByKeys(input, keysLower, depth = 0) {
  if (depth > 12 || input == null) return '';
  if (typeof input === 'string' || typeof input === 'number' || typeof input === 'boolean') {
    return '';
  }

  if (Array.isArray(input)) {
    for (const item of input) {
      const found = _findNestedValueByKeys(item, keysLower, depth + 1);
      if (found) return found;
    }
    return '';
  }

  if (typeof input !== 'object') return '';

  for (const [key, value] of Object.entries(input)) {
    const normalizedKey = _toLower(key);
    if (keysLower.includes(normalizedKey)) {
      if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
        return String(value).trim();
      }
    }
  }

  for (const value of Object.values(input)) {
    const found = _findNestedValueByKeys(value, keysLower, depth + 1);
    if (found) return found;
  }

  return '';
}

function _extractXmlTagValue(xmlText, tagNames) {
  const text = _readString(xmlText);
  if (!text) return '';

  for (const tag of tagNames) {
    const regex = new RegExp(`<\\s*${tag}\\s*>\\s*([^<]+)\\s*<\\s*\\/\\s*${tag}\\s*>`, 'i');
    const match = text.match(regex);
    if (match?.[1]) {
      return _readString(match[1]);
    }
  }

  return '';
}

function _extractSiiMetaFromPayload(payloadText) {
  const text = _readString(payloadText);
  if (!text) {
    return {
      trackId: '',
      receivedAt: '',
      statusCode: '',
    };
  }

  let parsedJson = null;
  try {
    parsedJson = JSON.parse(text);
  } catch (_) {
    parsedJson = null;
  }

  const fromJsonTrack = parsedJson ?
    _findNestedValueByKeys(parsedJson, ['trackid', 'track_id', 'nroenvio', 'nro_envio']) :
    '';
  const fromJsonDate = parsedJson ?
    _findNestedValueByKeys(
      parsedJson,
      ['timestamp', 'fecha', 'fecharecepcion', 'fecha_recepcion', 'fchrecep', 'tmstfirmaenv'],
    ) :
    '';
  const fromJsonStatus = parsedJson ?
    _findNestedValueByKeys(parsedJson, ['status', 'estado', 'codestado', 'codigoestado', 'codstatus']) :
    '';

  const fromXmlTrack = _extractXmlTagValue(text, ['TRACKID', 'TrackId', 'NroEnvio', 'NROENVIO']);
  const fromXmlDate = _extractXmlTagValue(
    text,
    ['TIMESTAMP', 'TmstFirmaEnv', 'FchRecep', 'FechaRecepcion', 'TmstFirma'],
  );
  const fromXmlStatus = _extractXmlTagValue(
    text,
    ['STATUS', 'ESTADO', 'CodEstado', 'CodigoEstado'],
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
  return `${baseUrl.replace(/\/+$/, '')}${fallbackPath}`;
}

function _resolveSimpleApiPdfEndpoint({
  baseUrl,
  explicitUrl,
  preferCedible = false,
}) {
  const fallbackPath = preferCedible ?
    '/api/v1/impresion/pdf/carta/v2/cedible' :
    '/api/v1/impresion/pdf/carta/v2';
  const resolved = _resolveSimpleApiEndpoint(baseUrl, explicitUrl, fallbackPath).replace(/\/+$/, '');
  if (!preferCedible) return resolved;

  try {
    const parsed = new URL(resolved);
    if (!parsed.pathname.toLowerCase().endsWith('/cedible')) {
      parsed.pathname = `${parsed.pathname.replace(/\/+$/, '')}/cedible`;
    }
    return parsed.toString();
  } catch (_) {
    return resolved.toLowerCase().endsWith('/cedible') ? resolved : `${resolved}/cedible`;
  }
}

function _resolvePdfFileName({preferCedible = false}) {
  return preferCedible ? 'document_cedible.pdf' : 'document.pdf';
}

function _sanitizeSiiText(value) {
  const raw = typeof value === 'string' ? value : String(value ?? '');
  if (!raw) return '';

  const punctuationNormalized = raw
    .replace(/[“”]/g, '"')
    .replace(/[‘’]/g, '\'')
    .replace(/[‐‑‒–—]/g, '-')
    .replace(/\u2026/g, '...')
    .replace(/\u00A0/g, ' ');

  // Keep only XML-safe characters representable in ISO-8859-1.
  return punctuationNormalized.replace(/[^\x09\x0A\x0D\x20-\x7E\xA0-\xFF]/g, ' ');
}

function _sanitizeSiiPayload(value, depth = 0) {
  if (depth > 16) return value;
  if (typeof value === 'string') return _sanitizeSiiText(value);
  if (Array.isArray(value)) {
    return value.map((entry) => _sanitizeSiiPayload(entry, depth + 1));
  }
  if (value && typeof value === 'object') {
    const out = {};
    for (const [key, entry] of Object.entries(value)) {
      out[key] = _sanitizeSiiPayload(entry, depth + 1);
    }
    return out;
  }
  return value;
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
    form.append('input', JSON.stringify(_sanitizeSiiPayload(inputPayload || {})));
  }

  for (const file of files) {
    const rawFieldName = _readString(file?.fieldName);
    const fieldName = rawFieldName;
    if (!fieldName) continue;
    const fileName = _readString(file?.fileName) || 'payload.bin';
    const contentType = _readString(file?.contentType) || 'application/octet-stream';
    const contentBuffer = Buffer.isBuffer(file?.buffer) ?
      file.buffer :
      Buffer.from(file?.buffer || '');
    form.append(fieldName, new Blob([contentBuffer], {type: contentType}), fileName);
  }

  const basicAuth = `Basic ${Buffer.from(`api:${apiKey}`, 'utf8').toString('base64')}`;
  const response = await fetch(endpointUrl, {
    method: 'POST',
    headers: {
      'x-api-key': apiKey,
      'Authorization': basicAuth,
    },
    body: form,
  });

  const bodyBuffer = Buffer.from(await response.arrayBuffer());
  const bodyText = bodyBuffer.toString('utf8');

  return {
    ok: response.ok,
    statusCode: response.status,
    contentType: _readString(response.headers.get('content-type')),
    bodyBuffer,
    bodyText,
  };
}

function _sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, Math.round(_asNumber(ms)))));
}

function _normalizeErrorText(value) {
  return _readString(value)
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
}

function _isFolioAlreadyUsedError(statusCode, bodyText) {
  if (Number(statusCode) !== 400) return false;
  const normalized = _normalizeErrorText(bodyText);
  const hasFolioWord = normalized.includes('folio');
  const hasDuplicateHint =
    normalized.includes('ya utilizado') ||
    normalized.includes('ya fue utilizado') ||
    normalized.includes('utilizado previamente') ||
    normalized.includes('ya existe') ||
    normalized.includes('documento ya recibido');
  return hasFolioWord && hasDuplicateHint;
}

function _isSimpleApiFileSpecifiedError(statusCode, bodyText) {
  if (Number(statusCode) !== 400) return false;
  const normalized = _normalizeErrorText(bodyText);
  return normalized.includes('cannot find the file specified') ||
    normalized.includes('faltan los archivos en form-data') ||
    normalized.includes('hay al menos un tipo de archivo incorrecto') ||
    normalized.includes('debe ser un archivo xml con formato dte');
}

function _isTransientSimpleApiSendFailure(statusCode, bodyText) {
  const normalizedStatus = Math.round(_asNumber(statusCode));
  if (normalizedStatus >= 500) return true;

  const normalizedBody = _normalizeErrorText(bodyText);
  if (!normalizedBody) return false;

  if (normalizedBody.includes('trackid":-999999')) return true;
  if (normalizedBody.includes('an error occurred while sending the request')) return true;
  if (normalizedBody.includes('system.net.webexception')) return true;
  if (normalizedBody.includes('"estado":"error"') && normalizedBody.includes('"ok":true')) {
    return true;
  }

  return false;
}

function _resolveStorageObject(storagePath, fallbackBucketName) {
  const raw = _readString(storagePath);
  if (!raw) {
    throw new Error('Missing storage path');
  }

  if (raw.startsWith('gs://')) {
    const withoutScheme = raw.slice(5);
    const slashIndex = withoutScheme.indexOf('/');
    if (slashIndex <= 0 || slashIndex === withoutScheme.length - 1) {
      throw new Error(`Invalid gs:// path: ${raw}`);
    }
    return {
      bucketName: withoutScheme.slice(0, slashIndex),
      objectPath: withoutScheme.slice(slashIndex + 1),
    };
  }

  const objectPath = raw.replace(/^\/+/, '');
  if (!objectPath) {
    throw new Error(`Invalid storage path: ${raw}`);
  }

  return {
    bucketName: _readString(fallbackBucketName),
    objectPath,
  };
}

async function _downloadPrivateAsset(storagePath, fallbackBucketName = '') {
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

function _extractCafIssuerRut(cafBuffer) {
  const text = (cafBuffer || Buffer.alloc(0)).toString('utf8');
  if (!text) return '';
  const match = text.match(/<RE>\s*([^<]+)\s*<\/RE>/i);
  if (!match?.[1]) return '';
  return _normalizeRut(match[1]);
}

function _extractCafFolioRange(cafBuffer) {
  const text = (cafBuffer || Buffer.alloc(0)).toString('utf8');
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
  const emisorKey = _readString(emisorRut).replace(/[^0-9K]/gi, '');
  const signature = crypto
    .createHash('sha1')
    .update(
      `${tipoDte}|${emisorRut}|${cafPath}|${folioRange.from}|${folioRange.to}`,
      'utf8',
    )
    .digest('hex')
    .slice(0, 12);
  return `dte${tipoDte}_${emisorKey}_${signature}`;
}

async function _allocateNextFolio({db, tipoDte, emisorRut, cafPath, folioRange}) {
  const counterId = _buildFolioCounterDocId({
    tipoDte,
    emisorRut,
    cafPath,
    folioRange,
  });
  const counterRef = db.collection('billing_folio_counters').doc(counterId);
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
      RutReceptor: _readString(process.env.SIMPLEAPI_SII_RECEPTOR_RUT) || '60803000-K',
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
  storagePrefix,
  apiKey,
  baseUrl,
  xmlPayloadBuffer,
  xmlPayloadBuffers = null,
  pfxBuffer,
  certRut,
  emisorRut,
  enabledOverride = null,
}) {
  const envEnabled = _readBoolean(process.env.SIMPLEAPI_ENABLE_SII_SEND, false);
  const enabled = enabledOverride == null ? envEnabled : enabledOverride;
  if (!enabled) {
    return {
      enabled: false,
      envioXmlPath: null,
      sendResponsePath: null,
      sendStatusPath: null,
      trackId: '',
      receivedAt: '',
      statusCode: '',
    };
  }

  const pfxPassword = _readString(process.env.SIMPLEAPI_PFX_PASSWORD);
  if (!pfxPassword) {
    throw new Error('Missing SIMPLEAPI_PFX_PASSWORD for SII send');
  }

  const envioGenerarUrl = _resolveSimpleApiEndpoint(
    baseUrl,
    process.env.SIMPLEAPI_ENVIO_GENERATE_URL,
    '/api/v1/envio/generar',
  );
  const envioEnviarUrl = _resolveSimpleApiEndpoint(
    baseUrl,
    process.env.SIMPLEAPI_ENVIO_SEND_URL,
    '/api/v1/envio/enviar',
  );
  const consultaEnvioUrl = _resolveSimpleApiEndpoint(
    baseUrl,
    process.env.SIMPLEAPI_CONSULTA_ENVIO_URL,
    '/api/v1/consulta/envio',
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
  const xmlBuffers = Array.isArray(xmlPayloadBuffers) ?
    xmlPayloadBuffers.filter((item) => Buffer.isBuffer(item) && item.length > 0) :
    [];
  if (Buffer.isBuffer(xmlPayloadBuffer) && xmlPayloadBuffer.length > 0) {
    xmlBuffers.push(xmlPayloadBuffer);
  }
  if (xmlBuffers.length === 0) {
    throw new Error('No XML payload buffers provided for SII send');
  }

  const envioFileFieldStrategies = [
    {certField: 'files', xmlField: 'files2', label: 'files/files2'},
    {certField: 'file', xmlField: 'file', label: 'file/file'},
  ];
  const buildEnvioGenerarFiles = (strategy) => ([
    {
      fieldName: strategy.certField,
      fileName: `certificado_temp_${Date.now()}.pfx`,
      buffer: pfxBuffer,
      contentType: 'application/x-pkcs12',
    },
    ...xmlBuffers.map((xmlBuffer, index) => ({
      fieldName: strategy.xmlField,
      fileName: `archivo_dte_${Date.now()}_${index + 1}.xml`,
      buffer: xmlBuffer,
      contentType: 'text/xml',
    })),
  ]);
  const buildEnvioEnviarFiles = (strategy, envelopeBuffer) => ([
    {
      fieldName: strategy.certField,
      fileName: `certificado_temp_${Date.now()}.pfx`,
      buffer: pfxBuffer,
      contentType: 'application/x-pkcs12',
    },
    {
      fieldName: strategy.xmlField,
      fileName: `envio_sii_${Date.now()}.xml`,
      buffer: envelopeBuffer,
      contentType: 'text/xml',
    },
  ]);

  const generarInput = _buildSimpleApiEnvioInput({
    certRut,
    pfxPassword,
    emisorRut,
    includeCaratula: true,
    includeAuth: includeSiiAuth,
  });

  let generarResponse = null;
  let lastGenerarErrorMessage = '';
  for (let strategyIndex = 0; strategyIndex < envioFileFieldStrategies.length; strategyIndex++) {
    const strategy = envioFileFieldStrategies[strategyIndex];
    const currentResponse = await _postSimpleApiMultipart({
      url: envioGenerarUrl,
      apiKey,
      inputPayload: generarInput,
      files: buildEnvioGenerarFiles(strategy),
    });
    if (currentResponse.ok) {
      generarResponse = currentResponse;
      break;
    }

    lastGenerarErrorMessage =
      `Envio generation failed (${currentResponse.statusCode}) [${envioGenerarUrl}]` +
      ` [strategy=${strategy.label}]: ${currentResponse.bodyText.slice(0, 900)}`;

    const shouldTryNextStrategy =
      strategyIndex < envioFileFieldStrategies.length - 1 &&
      _isSimpleApiFileSpecifiedError(currentResponse.statusCode, currentResponse.bodyText);
    if (shouldTryNextStrategy) {
      logger.warn('ENVIO_GENERATE_RETRY_ALTERNATE_FILE_FIELDS', {
        storagePrefix,
        strategy: strategy.label,
        statusCode: currentResponse.statusCode,
        responseBody: _readString(currentResponse.bodyText).slice(0, 900),
      });
      continue;
    }

    generarResponse = currentResponse;
    break;
  }

  if (!generarResponse?.ok) {
    throw new Error(
      lastGenerarErrorMessage ||
      `Envio generation failed (${generarResponse?.statusCode || 0}) [${envioGenerarUrl}]`,
    );
  }

  const generatedEnvelope = _extractXmlPayload(generarResponse.bodyBuffer, generarResponse.bodyText);
  if (!generatedEnvelope) {
    throw new Error('Envio generation response did not include a valid XML envelope');
  }
  const generatedEnvelopeBuffer = generatedEnvelope.xmlBuffer;

  const envioXmlPath = `${storagePrefix}/sii/envio.xml`;
  await bucket.file(envioXmlPath).save(generatedEnvelopeBuffer, {
    resumable: false,
    contentType: 'application/xml',
    metadata: {cacheControl: 'private, max-age=0, no-store'},
  });

  const authStrategies = includeSiiAuth && hasAuthCredentials ? [true, false] : [false];
  let enviarResponse = null;
  let sendResponsePath = null;
  let lastSendErrorMessage = '';

  for (const useAuth of authStrategies) {
    const enviarInput = _buildSimpleApiEnvioInput({
      certRut,
      pfxPassword,
      emisorRut,
      includeCaratula: false,
      includeAuth: useAuth,
    });

    for (let attempt = 0; attempt <= sendRetryLimit; attempt++) {
      let currentResponse = null;
      let usedStrategyLabel = '';
      for (let strategyIndex = 0; strategyIndex < envioFileFieldStrategies.length; strategyIndex++) {
        const strategy = envioFileFieldStrategies[strategyIndex];
        const strategyResponse = await _postSimpleApiMultipart({
          url: envioEnviarUrl,
          apiKey,
          inputPayload: enviarInput,
          files: buildEnvioEnviarFiles(strategy, generatedEnvelopeBuffer),
        });
        currentResponse = strategyResponse;
        usedStrategyLabel = strategy.label;
        if (strategyResponse.ok) break;

        const shouldTryNextStrategy =
          strategyIndex < envioFileFieldStrategies.length - 1 &&
          _isSimpleApiFileSpecifiedError(strategyResponse.statusCode, strategyResponse.bodyText);
        if (shouldTryNextStrategy) {
          logger.warn('ENVIO_SEND_RETRY_ALTERNATE_FILE_FIELDS', {
            storagePrefix,
            strategy: strategy.label,
            mode: useAuth ? 'auth' : 'cert',
            attempt: attempt + 1,
            statusCode: strategyResponse.statusCode,
            responseBody: _readString(strategyResponse.bodyText).slice(0, 900),
          });
          continue;
        }
        break;
      }
      if (!currentResponse) {
        throw new Error('Envio send failed without HTTP response');
      }

      const responsePath =
        authStrategies.length > 1 || sendRetryLimit > 0 ?
          `${storagePrefix}/sii/envio-response-${useAuth ? 'auth' : 'cert'}-try-${attempt + 1}.txt` :
          `${storagePrefix}/sii/envio-response.txt`;
      await bucket.file(responsePath).save(currentResponse.bodyBuffer, {
        resumable: false,
        contentType: 'text/plain; charset=utf-8',
        metadata: {cacheControl: 'private, max-age=0, no-store'},
      });
      sendResponsePath = responsePath;

      if (currentResponse.ok) {
        enviarResponse = currentResponse;
        break;
      }

      lastSendErrorMessage =
        `Envio send failed (${currentResponse.statusCode}) [${envioEnviarUrl}]` +
        ` [mode=${useAuth ? 'auth' : 'cert'} try=${attempt + 1} strategy=${usedStrategyLabel || 'unknown'}]: ` +
        `${currentResponse.bodyText.slice(0, 900)}`;

      const isTransient = _isTransientSimpleApiSendFailure(
        currentResponse.statusCode,
        currentResponse.bodyText,
      );
      const hasRetryLeft = attempt < sendRetryLimit;
      if (isTransient && hasRetryLeft) {
        await _sleep(sendRetryBackoffMs * (attempt + 1));
        continue;
      }
      break;
    }

    if (enviarResponse?.ok) break;
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
        {
          fieldName: 'files',
          fileName: `certificado_temp_${Date.now()}.pfx`,
          buffer: pfxBuffer,
          contentType: 'application/x-pkcs12',
        },
      ],
    });

    sendStatusPath = `${storagePrefix}/sii/envio-status.txt`;
    await bucket.file(sendStatusPath).save(consultaResponse.bodyBuffer, {
      resumable: false,
      contentType: 'text/plain; charset=utf-8',
      metadata: {cacheControl: 'private, max-age=0, no-store'},
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

function _normalizeDocumentTypeInput(value) {
  const raw = _readString(value);
  if (!raw) return '';
  const normalized = _toLower(raw)
    .replace(/[\s-]+/g, '_')
    .replace(/Ã¡/g, 'a')
    .replace(/Ã©/g, 'e')
    .replace(/Ã­/g, 'i')
    .replace(/Ã³/g, 'o')
    .replace(/Ãº/g, 'u');

  const aliasMap = {
    '33': 'factura',
    factura: 'factura',
    factura_electronica: 'factura',
    '61': 'nota_credito',
    nota_credito: 'nota_credito',
    nota_de_credito: 'nota_credito',
    nce: 'nota_credito',
    '56': 'nota_debito',
    nota_debito: 'nota_debito',
    nota_de_debito: 'nota_debito',
    nde: 'nota_debito',
    '52': 'guia_despacho',
    guia_despacho: 'guia_despacho',
    guia_de_despacho: 'guia_despacho',
    gde: 'guia_despacho',
    '46': 'factura_compra',
    factura_compra: 'factura_compra',
    factura_de_compra: 'factura_compra',
  };

  return aliasMap[normalized] || normalized;
}

function _resolveTipoDte(documentType) {
  const normalized = _normalizeDocumentTypeInput(documentType);
  const map = {
    factura: 33,
    nota_credito: 61,
    nota_debito: 56,
    guia_despacho: 52,
    factura_compra: 46,
  };

  if (map[normalized]) return map[normalized];
  const numeric = Math.round(_asNumber(normalized));
  if (SUPPORTED_TIPO_DTE.has(numeric)) return numeric;
  throw new Error(`Unsupported document type: ${documentType || 'unknown'}`);
}

function _resolveCafPathByTipoDte(tipoDte) {
  const explicit = _readString(process.env[`SIMPLEAPI_CAF_STORAGE_PATH_${tipoDte}`]);
  if (explicit) return explicit;

  const legacy = _readString(process.env.SIMPLEAPI_CAF_STORAGE_PATH);
  if (tipoDte === 33 && legacy) return legacy;

  throw new Error(
    `Missing CAF path for tipo ${tipoDte}. Configure SIMPLEAPI_CAF_STORAGE_PATH_${tipoDte}.`,
  );
}

function _resolveFormaPagoCode(payload, tipoDte) {
  if (![33, 46].includes(tipoDte)) {
    return 0;
  }

  const explicit = Math.round(
    _asNumber(
      _firstNonEmpty(
        payload?.formaPago,
        payload?.fmaPago,
        payload?.paymentCode,
        process.env.SIMPLEAPI_DEFAULT_FMA_PAGO,
      ),
    ),
  );
  if ([1, 2, 3].includes(explicit)) return explicit;
  return 1;
}

function _resolveTipoDespacho(payload, tipoDte) {
  if (tipoDte !== 52) return 0;
  const traslado = Math.round(_asNumber(payload?.guia?.tipoTraslado));
  if (traslado === 5) {
    // Traslado interno (no venta): en certificacion SII no se informa TipoDespacho.
    return 0;
  }
  const explicit = Math.round(_asNumber(payload?.guia?.tipoDespacho));
  if ([1, 2, 3].includes(explicit)) return explicit;

  const trasladoPor = _toLower(payload?.guia?.trasladoPor);
  if (trasladoPor.includes('cliente')) return 1;
  if (trasladoPor.includes('emisor')) return 2;
  return 2;
}

function _resolveTipoTraslado(payload, tipoDte) {
  if (tipoDte !== 52) return 0;
  const explicit = Math.round(_asNumber(payload?.guia?.tipoTraslado));
  if (explicit >= 1 && explicit <= 9) return explicit;
  return 1;
}

function _buildEmisorPayload(payloadSellerLabel = '') {
  const emisorRut = _normalizeRut(_readEnvOrThrow('SIMPLEAPI_EMISOR_RUT'));
  if (!_isValidRutShape(emisorRut)) {
    throw new Error('Invalid SIMPLEAPI_EMISOR_RUT format');
  }
  if (!_hasValidRutDv(emisorRut)) {
    throw new Error('Invalid SIMPLEAPI_EMISOR_RUT DV');
  }

  const activityCodes = _parseNumericCsv(process.env.SIMPLEAPI_EMISOR_ACTIVITY_CODES);
  if (activityCodes.length === 0) {
    throw new Error(
      'Missing SIMPLEAPI_EMISOR_ACTIVITY_CODES. Configure at least one SII Acteco code.',
    );
  }

  const sellerLabel = _toMaxLength(
    _firstNonEmpty(
      payloadSellerLabel,
      process.env.SIMPLEAPI_DEFAULT_VENDEDOR,
      process.env.SIMPLEAPI_EMISOR_RAZON_SOCIAL,
    ),
    60,
  );

  const emisor = {
    Rut: emisorRut,
    RazonSocial: _readString(process.env.SIMPLEAPI_EMISOR_RAZON_SOCIAL) || '',
    Giro: _readString(process.env.SIMPLEAPI_EMISOR_GIRO) || '',
    DireccionOrigen: _readString(process.env.SIMPLEAPI_EMISOR_DIRECCION) || '',
    ComunaOrigen: _readString(process.env.SIMPLEAPI_EMISOR_COMUNA) || '',
    CiudadOrigen: _readString(process.env.SIMPLEAPI_EMISOR_CIUDAD) || '',
    ActividadEconomica: activityCodes,
    Telefono: [],
  };

  if (sellerLabel) {
    emisor.CodigoVendedor = sellerLabel;
  }

  return emisor;
}

function _buildReceptorPayload(payload, tipoDte, emisor) {
  const isInternalGuide = tipoDte === 52 && _resolveTipoTraslado(payload, tipoDte) === 5;
  const receptor = payload?.receptor || {};

  const receiverRutInput = _firstNonEmpty(
    receptor?.rut,
    receptor?.Rut,
    payload?.invoiceRut,
    isInternalGuide ? emisor?.Rut : '',
  );
  const receiverRut = _normalizeRut(receiverRutInput);
  if (!_isValidRutShape(receiverRut)) {
    throw new Error('Invalid receptor RUT format');
  }
  if (!_hasValidRutDv(receiverRut)) {
    throw new Error('Invalid receptor RUT DV');
  }

  const receiverName = _firstNonEmpty(
    receptor?.razonSocial,
    receptor?.RazonSocial,
    payload?.invoiceBusinessName,
    isInternalGuide ? emisor?.RazonSocial : '',
  );
  if (!receiverName) {
    throw new Error('Missing receptor Razon Social');
  }

  const receiverGiro = _firstNonEmpty(
    receptor?.giro,
    receptor?.Giro,
    payload?.invoiceGiro,
    isInternalGuide ? emisor?.Giro : '',
  );

  const receiverAddress = _firstNonEmpty(
    receptor?.direccion,
    receptor?.Direccion,
    payload?.invoiceAddress,
    isInternalGuide ? emisor?.DireccionOrigen : '',
  );
  if (!receiverAddress) {
    throw new Error('Missing receptor Direccion');
  }

  const receiverComuna = _firstNonEmpty(
    receptor?.comuna,
    receptor?.Comuna,
    payload?.invoiceComuna,
    payload?.invoiceCommune,
    process.env.SIMPLEAPI_DEFAULT_RECEPTOR_COMUNA,
    isInternalGuide ? emisor?.ComunaOrigen : '',
  ) || 'Santiago';

  const receiverCity = _firstNonEmpty(
    receptor?.ciudad,
    receptor?.Ciudad,
    payload?.invoiceCity,
    process.env.SIMPLEAPI_DEFAULT_RECEPTOR_CIUDAD,
    isInternalGuide ? emisor?.CiudadOrigen : '',
  ) || receiverComuna;

  const receiverEmail = _firstNonEmpty(receptor?.email, receptor?.Email, payload?.invoiceEmail);
  const receiverPhone = _firstNonEmpty(
    receptor?.telefono,
    receptor?.Telefono,
    payload?.invoicePhone,
  );
  const receiverContact = _firstNonEmpty(receptor?.contacto, receiverEmail, receiverPhone);

  return {
    Rut: receiverRut,
    RazonSocial: _toMaxLength(receiverName, 100),
    Giro: _toMaxLength(receiverGiro, 80) || undefined,
    Direccion: _toMaxLength(receiverAddress, 70),
    Comuna: _toMaxLength(receiverComuna, 20),
    Ciudad: _toMaxLength(receiverCity, 40),
    Contacto: _toMaxLength(receiverContact, 80) || undefined,
    CorreoElectronico: _toMaxLength(receiverEmail, 80) || undefined,
  };
}

function _parseCodRefValue(rawValue) {
  const asString = _readString(rawValue).toUpperCase();
  if (asString === 'SET') return 'SET';

  const numeric = Math.round(_asNumber(rawValue));
  if ([1, 2, 3].includes(numeric)) {
    return String(numeric);
  }
  return '';
}

function _buildReferences(payload, currentFolio = 0) {
  const references = Array.isArray(payload?.references) ? payload.references : [];
  const out = [];
  const defaultRefDate = _safeIsoDate(payload?.emitDate);
  const selfFolio = Math.max(1, Math.round(_asNumber(currentFolio)));

  for (let idx = 0; idx < references.length; idx++) {
    const ref = references[idx] || {};
    const tipoDocumentoRaw = _readString(ref?.tipoDocumento || ref?.tipoDte || ref?.documentType);
    const tipoDocumento = tipoDocumentoRaw.toUpperCase();
    const folio = _readString(ref?.folioReferencia || ref?.folioRef || ref?.folio);
    const rutRef = _normalizeRut(_readString(ref?.rutReferencia || ref?.rutRef || ref?.rut));
    const refDate = _safeIsoDate(
      ref?.fechaDocumentoReferencia ||
      ref?.fechaRef ||
      ref?.fecha ||
      defaultRefDate,
    );
    const codRef = _parseCodRefValue(ref?.codigoReferencia || ref?.codRef || ref?.code);
    const reason = _toMaxLength(
      _readString(ref?.razonReferencia || ref?.razonRef || ref?.reason),
      90,
    );
    const indicator = Math.max(0, Math.round(_asNumber(ref?.indicadorGlobal)));

    const entry = {
      Numero: idx + 1,
    };
    if (tipoDocumento) entry.TipoDocumento = tipoDocumento;
    if (tipoDocumento === 'SET') {
      entry.FolioReferencia = String(selfFolio);
    } else if (folio) {
      entry.FolioReferencia = folio;
    }
    if (_isValidRutShape(rutRef) && _hasValidRutDv(rutRef)) {
      entry.RutReferencia = rutRef;
    }
    if (refDate) entry.FechaDocumentoReferencia = refDate;
    if (indicator > 0) entry.IndicadorGlobal = indicator;
    if (codRef) entry.CodigoReferencia = codRef;
    if (reason) entry.RazonReferencia = reason;

    if (
      entry.TipoDocumento ||
      entry.FolioReferencia ||
      entry.RutReferencia ||
      entry.CodigoReferencia ||
      entry.RazonReferencia
    ) {
      out.push(entry);
    }
  }

  return out;
}

function _buildGlobalDiscounts(payload) {
  const source = [];
  if (payload?.globalDiscount && typeof payload.globalDiscount === 'object') {
    source.push(payload.globalDiscount);
  }
  if (Array.isArray(payload?.globalDiscounts)) {
    source.push(...payload.globalDiscounts);
  }

  const lines = [];
  for (let i = 0; i < source.length; i++) {
    const item = source[i] || {};
    const amount = _asNumber(item?.amount);
    const percent = _asNumber(item?.percent);
    const movement = _toLower(item?.movement || item?.type);
    const isRecargo = movement.includes('recargo') || movement === 'r';

    let tipoValor = 0;
    let valor = 0;
    if (percent > 0) {
      tipoValor = 1;
      valor = percent;
    } else if (amount > 0) {
      tipoValor = 2;
      valor = amount;
    }
    if (!tipoValor || valor <= 0) continue;

    const line = {
      Numero: lines.length + 1,
      TipoMovimiento: isRecargo ? 2 : 1,
      TipoValor: tipoValor,
      Valor: valor,
    };

    const desc = _toMaxLength(_readString(item?.description || item?.descripcion), 45);
    if (desc) line.Descripcion = desc;
    if (_readBoolean(item?.appliesToExempt, false)) {
      line.IndicadorExento = 1;
    }

    lines.push(line);
  }

  return lines;
}

function _allowZeroAmountLine({tipoDte, tipoTraslado, references}) {
  if ([56, 61].includes(tipoDte)) return true;
  if (tipoDte === 52 && tipoTraslado !== 1) return true;

  for (const reference of references || []) {
    const codRef = _readString(reference?.CodigoReferencia || reference?.codigoReferencia);
    if (codRef === '1' || codRef === '2' || codRef === 'SET') {
      return true;
    }
  }

  return false;
}

function _buildDetails(payload, tipoDte, references) {
  const items = Array.isArray(payload?.items) ? payload.items : [];
  const details = [];
  const tipoTraslado = _resolveTipoTraslado(payload, tipoDte);
  const canIncludeZero = _allowZeroAmountLine({tipoDte, tipoTraslado, references});
  const defaultTaxCodeCandidates = [
    payload?.codigoImpuestoAdicional,
    payload?.impuestoRetenido?.tipoImpuesto,
    payload?.impuestoRetenido?.tipo,
    payload?.retencionIva?.tipoImpuesto,
    payload?.retainedTaxCode,
  ];
  let defaultTaxCodes = [];
  for (const candidate of defaultTaxCodeCandidates) {
    const parsed = _normalizeTaxCodeList(candidate);
    if (parsed.length > 0) {
      defaultTaxCodes = parsed;
      break;
    }
  }

  for (let i = 0; i < items.length; i++) {
    const item = items[i] || {};
    const compactLine = _readBoolean(
      item?.compactLine ?? item?.minimalLine ?? item?.setMinimalLine,
      false,
    );
    const keepQuantityInCompact = _readBoolean(
      item?.keepQuantity ?? item?.includeQuantityWhenCompact,
      false,
    );
    const omitAmountInCompact = _readBoolean(
      item?.omitLineAmount ?? item?.omitMontoItem,
      false,
    );
    const nombre = _toMaxLength(
      _firstNonEmpty(item?.name, item?.nombre, item?.title, item?.descripcion, `Item ${i + 1}`),
      80,
    );
    const descripcion = _toMaxLength(
      _firstNonEmpty(item?.description, item?.detalle, item?.descripcion, nombre),
      1000,
    );

    const cantidad = _firstFiniteNumber(item?.quantity, item?.qty, item?.cantidad, 1);
    const qty = Math.max(0.000001, cantidad);
    const unidad = _toMaxLength(
      _firstNonEmpty(item?.unit, item?.unidad, item?.unidadMedida, 'un'),
      4,
    );

    const unitPriceRaw = _firstFiniteNumber(
      item?.unitPrice,
      item?.precioUnitario,
      item?.price,
      item?.precio,
      0,
    );
    const descuentoPct = Math.max(0, _firstFiniteNumber(item?.discountPercent, item?.descuentoPct, 0));
    let descuentoMonto = Math.max(0, _toMoneyInt(item?.discountAmount || item?.descuentoMonto || 0));
    const recargoMonto = Math.max(0, _toMoneyInt(item?.recargoMonto || item?.surchargeAmount || 0));

    const explicitAmount = Number(item?.amount ?? item?.montoItem ?? item?.lineTotal);
    const hasExplicitAmount = Number.isFinite(explicitAmount);

    let montoItem = 0;
    const precioUnitario = unitPriceRaw > 0 ? unitPriceRaw : 0;

    if (hasExplicitAmount) {
      montoItem = _toMoneyInt(explicitAmount);
    } else {
      if (descuentoMonto <= 0 && descuentoPct > 0 && precioUnitario > 0) {
        descuentoMonto = Math.max(
          0,
          Math.round((precioUnitario * qty) * (descuentoPct / 100)),
        );
      }
      montoItem = _toMoneyInt((precioUnitario * qty) - descuentoMonto + recargoMonto);
    }

    const exempt = _readBoolean(item?.exempt, false) ||
      Math.round(_asNumber(item?.indicadorExento)) === 1;

    const line = {
      NumeroLinea: details.length + 1,
      Nombre: nombre,
    };
    if (!(compactLine && omitAmountInCompact)) {
      line.MontoItem = montoItem;
    }
    if (!compactLine) {
      line.Cantidad = qty;
      line.UnidadMedida = unidad;
      line.Precio = precioUnitario;
      if (descripcion) line.Descripcion = descripcion;
      if (descuentoPct > 0) line.DescuentoPorcentaje = descuentoPct;
      if (descuentoMonto > 0) line.Descuento = descuentoMonto;
      if (recargoMonto > 0) line.Recargo = recargoMonto;
      if (exempt) line.IndicadorExento = 1;
    } else if (keepQuantityInCompact) {
      line.Cantidad = qty;
    }
    const itemTaxCodeCandidates = [
      item?.codigoImpuestoAdicional,
      item?.CodImpAdic,
      item?.codImpAdic,
      item?.taxCodes,
    ];
    let itemTaxCodes = [];
    for (const candidate of itemTaxCodeCandidates) {
      const parsed = _normalizeTaxCodeList(candidate);
      if (parsed.length > 0) {
        itemTaxCodes = parsed;
        break;
      }
    }
    const lineTaxCodes = itemTaxCodes.length > 0 ? itemTaxCodes : defaultTaxCodes;
    if (lineTaxCodes.length > 0) {
      line.CodigoImpuestoAdicional = lineTaxCodes;
    }

    const lineAmount = Math.max(0, Math.round(_asNumber(line?.MontoItem)));
    if (lineAmount > 0 || canIncludeZero || _readBoolean(item?.allowZero, false)) {
      details.push(line);
    }
  }

  if (details.length === 0 && canIncludeZero) {
    details.push({
      NumeroLinea: 1,
      Nombre: 'Ajuste administrativo',
      Descripcion: 'Documento de referencia sin movimiento monetario',
      Cantidad: 1,
      UnidadMedida: 'un',
      Precio: 0,
      MontoItem: 0,
      IndicadorExento: 1,
    });
  }

  if (details.length === 0) {
    throw new Error('Document has no valid detail lines');
  }

  return details;
}

function _applyGlobalAdjustments(baseAmount, discounts, targetExempt) {
  let amount = Math.max(0, Math.round(_asNumber(baseAmount)));
  for (const discount of discounts || []) {
    const indicatorExempt = Math.round(_asNumber(discount?.IndicadorExento));
    const appliesToExempt = indicatorExempt === 1;
    const appliesToTarget = targetExempt ? appliesToExempt : !appliesToExempt;
    if (!appliesToTarget) continue;

    const moveType = Math.round(_asNumber(discount?.TipoMovimiento));
    const valueType = Math.round(_asNumber(discount?.TipoValor));
    const value = _asNumber(discount?.Valor);
    if (value <= 0) continue;

    let delta = 0;
    if (valueType === 1) {
      delta = Math.round(amount * (value / 100));
    } else if (valueType === 2) {
      delta = Math.round(value);
    }
    if (delta <= 0) continue;

    if (moveType === 2) {
      amount += delta;
    } else {
      amount -= delta;
      if (amount < 0) amount = 0;
    }
  }
  return Math.max(0, amount);
}

function _resolveRetainedTaxConfig({payload, tipoDte, details, iva}) {
  if (![46, 56, 61].includes(tipoDte)) return null;

  const retentionInput = payload?.impuestoRetenido || payload?.retencionIva || payload?.retencion || {};
  const explicitApplyRaw = retentionInput?.aplicar ?? retentionInput?.enabled ?? retentionInput?.activo;
  const hasExplicitApply = explicitApplyRaw !== undefined && explicitApplyRaw !== null;
  const explicitApply = hasExplicitApply ? _readBoolean(explicitApplyRaw, false) : null;

  const detailTaxCodes = new Set();
  for (const line of details || []) {
    const codes = _normalizeTaxCodeList(
      line?.CodigoImpuestoAdicional ||
      line?.codigoImpuestoAdicional ||
      line?.CodImpAdic ||
      line?.codImpAdic,
    );
    for (const code of codes) detailTaxCodes.add(code);
  }

  const configuredType = Math.round(
    _asNumber(
      retentionInput?.tipoImpuesto ??
      retentionInput?.tipo ??
      payload?.retainedTaxCode ??
      0,
    ),
  );
  const inferredType = configuredType > 0 ?
    configuredType :
    (detailTaxCodes.has(15) ? 15 : (detailTaxCodes.values().next().value || 0));
  if (inferredType <= 0) return null;

  const shouldApply = hasExplicitApply ? explicitApply : detailTaxCodes.has(inferredType);
  if (!shouldApply) return null;

  const tasa = _firstFiniteNumber(
    retentionInput?.tasaImpuesto,
    retentionInput?.tasa,
    payload?.retainedTaxRate,
    19,
  );
  const resolvedRate = tasa > 0 ? tasa : 19;

  const explicitAmountSource =
    retentionInput?.montoImpuesto ??
    retentionInput?.monto ??
    payload?.retainedTaxAmount;
  let retainedAmount = 0;
  if (explicitAmountSource !== undefined && explicitAmountSource !== null) {
    retainedAmount = Math.max(0, _toMoneyInt(explicitAmountSource));
  } else {
    retainedAmount = Math.max(0, _toMoneyInt(iva * (resolvedRate / 19)));
  }

  const modeRaw = _toLower(
    retentionInput?.modo ||
    retentionInput?.mode ||
    payload?.retainedTaxMode,
  );
  const isPartial = modeRaw === 'partial' || modeRaw === 'parcial';
  const ivaNoRetenido = isPartial ? Math.max(0, iva - retainedAmount) : 0;

  return {
    tipoImpuesto: inferredType,
    tasaImpuesto: resolvedRate,
    montoImpuesto: retainedAmount,
    ivaNoRetenido,
  };
}

function _computeTotals({payload, tipoDte, details, globalDiscounts}) {
  const EXEMPT_TYPES = new Set([34, 41]);
  const isExemptType = EXEMPT_TYPES.has(tipoDte);

  let affected = 0;
  let exempt = 0;
  for (const line of details) {
    const amount = Math.max(0, Math.round(_asNumber(line?.MontoItem)));
    const isExemptLine = Math.round(_asNumber(line?.IndicadorExento)) === 1;
    if (isExemptType || isExemptLine) {
      exempt += amount;
    } else {
      affected += amount;
    }
  }

  affected = _applyGlobalAdjustments(affected, globalDiscounts, false);
  exempt = _applyGlobalAdjustments(exempt, globalDiscounts, true);

  let iva = 0;
  if (!isExemptType && affected > 0) {
    iva = Math.round(affected * 0.19);
  }
  const retainedTax = _resolveRetainedTaxConfig({
    payload,
    tipoDte,
    details,
    iva,
  });
  const retainedAmount = Math.max(0, _toMoneyInt(retainedTax?.montoImpuesto || 0));
  const total = Math.max(0, affected + exempt + iva - retainedAmount);

  const totals = {
    MontoTotal: total,
  };
  if (affected > 0) {
    totals.MontoNeto = affected;
    totals.TasaIVA = 19;
    totals.IVA = iva;
  }
  if (exempt > 0 || isExemptType) {
    totals.MontoExento = exempt;
  }

  if (isExemptType) {
    delete totals.MontoNeto;
    delete totals.TasaIVA;
    delete totals.IVA;
  }

  const forceTasaIva = _readBoolean(payload?.forceTasaIva, false);
  if (!isExemptType && forceTasaIva && !Object.prototype.hasOwnProperty.call(totals, 'TasaIVA')) {
    totals.TasaIVA = 19;
  }

  if (retainedTax && retainedAmount > 0) {
    totals.ImpuestosRetenciones = [{
      TipoImpuesto: retainedTax.tipoImpuesto,
      TasaImpuesto: retainedTax.tasaImpuesto,
      MontoImpuesto: retainedAmount,
    }];
    if (retainedTax.ivaNoRetenido > 0) {
      totals.IVANoRetenido = retainedTax.ivaNoRetenido;
    }
  }

  return totals;
}

function _buildTransportePayload(payload, tipoDte, receptorPayload) {
  if (tipoDte !== 52) return null;
  const info = payload?.guia?.transporte || payload?.transporte || {};

  const direccionDestino = _toMaxLength(
    _firstNonEmpty(info?.direccionDestino, info?.direccion, receptorPayload?.Direccion),
    70,
  );
  const comunaDestino = _toMaxLength(
    _firstNonEmpty(info?.comunaDestino, info?.comuna, receptorPayload?.Comuna),
    20,
  );
  const ciudadDestino = _toMaxLength(
    _firstNonEmpty(info?.ciudadDestino, info?.ciudad, receptorPayload?.Ciudad),
    40,
  );

  if (!direccionDestino && !comunaDestino && !ciudadDestino) {
    return null;
  }

  return {
    DireccionDestino: direccionDestino || undefined,
    ComunaDestino: comunaDestino || undefined,
    CiudadDestino: ciudadDestino || undefined,
  };
}

function _buildDteInput({payload, folio, tipoDte}) {
  const certRut = _normalizeRut(_readEnvOrThrow('SIMPLEAPI_CERT_RUT'));
  if (!_isValidRutShape(certRut)) {
    throw new Error('Invalid SIMPLEAPI_CERT_RUT format');
  }
  if (!_hasValidRutDv(certRut)) {
    throw new Error('Invalid SIMPLEAPI_CERT_RUT DV');
  }

  const emisor = _buildEmisorPayload(payload?.sellerLabel);
  const receptor = _buildReceptorPayload(payload, tipoDte, emisor);

  const idDoc = {
    TipoDTE: tipoDte,
    Folio: Math.max(1, Math.round(_asNumber(folio))),
    FechaEmision: _safeIsoDate(payload?.emitDate),
  };

  const referencias = _buildReferences(payload, idDoc.Folio);
  const detalles = _buildDetails(payload, tipoDte, referencias);
  const descuentosGlobales = _buildGlobalDiscounts(payload);
  const totales = _computeTotals({
    payload,
    tipoDte,
    details: detalles,
    globalDiscounts: descuentosGlobales,
  });

  const formaPago = _resolveFormaPagoCode(payload, tipoDte);
  if (formaPago > 0) {
    idDoc.FormaPago = formaPago;
  }

  const tipoDespacho = _resolveTipoDespacho(payload, tipoDte);
  if (tipoDespacho > 0) {
    idDoc.TipoDespacho = tipoDespacho;
  }

  const tipoTraslado = _resolveTipoTraslado(payload, tipoDte);
  if (tipoTraslado > 0) {
    idDoc.TipoTraslado = tipoTraslado;
  }

  const encabezado = {
    IdentificacionDTE: idDoc,
    Emisor: emisor,
    Receptor: receptor,
    Totales: totales,
  };

  const transporte = _buildTransportePayload(payload, tipoDte, receptor);
  if (transporte) {
    encabezado.Transporte = transporte;
  }

  const documento = {
    Encabezado: encabezado,
    Detalles: detalles,
  };

  const rutSolicitante = _normalizeRut(_readString(payload?.rutSolicitante));
  if (_isValidRutShape(rutSolicitante) && _hasValidRutDv(rutSolicitante)) {
    documento.RutSolicitante = rutSolicitante;
  }

  if (descuentosGlobales.length > 0) {
    documento.DescuentosRecargos = descuentosGlobales;
  }
  if (referencias.length > 0) {
    documento.Referencias = referencias;
  }

  return {
    Documento: documento,
    Certificado: {
      Rut: certRut,
      Password: _readString(process.env.SIMPLEAPI_PFX_PASSWORD),
    },
  };
}

function _buildPdfInput(payload) {
  const paymentLabel = _firstNonEmpty(
    payload?.pdf?.formaPago,
    payload?.formaPagoLabel,
    process.env.SIMPLEAPI_DEFAULT_FORMA_PAGO,
    'Contado',
  );
  const saleCondition = _firstNonEmpty(
    payload?.pdf?.condicionVenta,
    payload?.saleCondition,
    process.env.SIMPLEAPI_DEFAULT_CONDICION_VENTA,
    'Contado',
  );
  const sellerLabel = _toMaxLength(
    _firstNonEmpty(
      payload?.pdf?.vendedor,
      payload?.sellerLabel,
      process.env.SIMPLEAPI_DEFAULT_VENDEDOR,
      process.env.SIMPLEAPI_EMISOR_RAZON_SOCIAL,
    ),
    60,
  );

  const pdfInput = {
    NumeroResolucion: _readString(process.env.SIMPLEAPI_SII_RESOLUTION_NUMBER) || '',
    UnidadSII: _readString(process.env.SIMPLEAPI_SII_UNIT) || '',
    FechaResolucion: _readString(process.env.SIMPLEAPI_SII_RESOLUTION_DATE) || '',
    PropiedadLogo: _readString(process.env.SIMPLEAPI_LOGO_FIT) || 'contain',
  };
  if (sellerLabel) pdfInput.Vendedor = sellerLabel;
  if (paymentLabel) pdfInput.FormaPago = paymentLabel;
  if (saleCondition) pdfInput.CondicionVenta = saleCondition;

  return pdfInput;
}

async function _emitFiscalDocument({
  documentId,
  payload,
  forceSiiSend = null,
  includePdf = true,
}) {
  const tipoDte = _resolveTipoDte(payload?.documentType);
  const cedibleByDocTypeDefault = [33, 34, 43, 46, 52].includes(tipoDte);
  const preferCediblePdf = _readBoolean(
    payload?.pdf?.cedible,
    _readBoolean(process.env.SIMPLEAPI_PDF_USE_CEDIBLE, cedibleByDocTypeDefault),
  );
  const baseUrl = _readString(process.env.SIMPLEAPI_BASE_URL) || 'https://api.simpleapi.cl';
  const dteEndpoint = _resolveSimpleApiEndpoint(
    baseUrl,
    process.env.SIMPLEAPI_DTE_GENERATE_URL,
    '/api/v1/dte/generar',
  );
  const pdfEndpoint = _resolveSimpleApiPdfEndpoint({
    baseUrl,
    explicitUrl: process.env.SIMPLEAPI_PDF_GENERATE_URL,
    preferCedible: preferCediblePdf,
  });
  const apiKey = _readEnvOrThrow('SIMPLEAPI_API_KEY');
  const pfxPath = _readEnvOrThrow('SIMPLEAPI_PFX_STORAGE_PATH');
  const cafPath = _resolveCafPathByTipoDte(tipoDte);
  const certRut = _readString(process.env.SIMPLEAPI_CERT_RUT);
  const logoPath = _readString(process.env.SIMPLEAPI_LOGO_STORAGE_PATH);
  const assetsBucketName = _readString(process.env.SIMPLEAPI_ASSETS_BUCKET);
  const outputBucketName = _readString(process.env.SIMPLEAPI_OUTPUT_BUCKET);
  _readEnvOrThrow('SIMPLEAPI_PFX_PASSWORD');

  const pfxAsset = await _downloadPrivateAsset(pfxPath, assetsBucketName);
  const cafAsset = await _downloadPrivateAsset(cafPath, assetsBucketName);
  const pfxBuffer = pfxAsset.buffer;
  const cafBuffer = cafAsset.buffer;
  if (!pfxBuffer.length) {
    throw new Error(`Downloaded empty PFX buffer from ${pfxAsset.bucketName}/${pfxAsset.objectPath}`);
  }
  if (!cafBuffer.length) {
    throw new Error(`Downloaded empty CAF buffer from ${cafAsset.bucketName}/${cafAsset.objectPath}`);
  }

  logger.info('FISCAL_ASSETS_LOADED', {
    documentId,
    tipoDte,
    assetsBucketName: assetsBucketName || null,
    pfxPath: `${pfxAsset.bucketName}/${pfxAsset.objectPath}`,
    pfxBytes: pfxBuffer.length,
    cafPath: `${cafAsset.bucketName}/${cafAsset.objectPath}`,
    cafBytes: cafBuffer.length,
  });

  const emisorRut = _normalizeRut(_readString(process.env.SIMPLEAPI_EMISOR_RUT));
  const cafRut = _extractCafIssuerRut(cafBuffer);
  const cafFolioRange = _extractCafFolioRange(cafBuffer);
  if (!cafFolioRange) {
    throw new Error(`Unable to extract CAF folio range for tipo ${tipoDte}`);
  }
  if (emisorRut && cafRut && emisorRut !== cafRut) {
    throw new Error(
      `Issuer RUT mismatch between SIMPLEAPI_EMISOR_RUT (${emisorRut}) and CAF (${cafRut})`,
    );
  }

  const db = admin.firestore();
  const presetFolio = Math.round(_asNumber(payload?.folio));
  let currentFolio = presetFolio > 0 ?
    presetFolio :
    await _allocateNextFolio({
      db,
      tipoDte,
      emisorRut,
      cafPath,
      folioRange: cafFolioRange,
    });
  if (currentFolio < cafFolioRange.from || currentFolio > cafFolioRange.to) {
    throw new Error(
      `Allocated folio (${currentFolio}) is outside CAF range ${cafFolioRange.from}-${cafFolioRange.to}`,
    );
  }

  const maxFolioRetries = Math.max(
    0,
    Math.min(10, Math.round(_asNumber(process.env.SIMPLEAPI_FOLIO_RETRY_LIMIT || 3))),
  );

  let dteBodyBuffer = Buffer.alloc(0);
  let dteBodyText = '';
  let dteStatusCode = 0;
  for (let attempt = 0; ; attempt++) {
    const dteInput = _buildDteInput({
      payload,
      folio: currentFolio,
      tipoDte,
    });
    const dteFileStrategies = [
      [
        {
          fieldName: 'files',
          fileName: `certificado_temp_${Date.now()}.pfx`,
          buffer: pfxBuffer,
          contentType: 'application/x-pkcs12',
        },
        {
          fieldName: 'files2',
          fileName: `archivo_caf_${Date.now()}.xml`,
          buffer: cafBuffer,
          contentType: 'text/xml',
        },
      ],
      [
        {
          fieldName: 'file',
          fileName: `certificado_temp_${Date.now()}.pfx`,
          buffer: pfxBuffer,
          contentType: 'application/x-pkcs12',
        },
        {
          fieldName: 'file',
          fileName: `archivo_caf_${Date.now()}.xml`,
          buffer: cafBuffer,
          contentType: 'text/xml',
        },
      ],
    ];

    let dteResponse = null;
    for (let strategyIndex = 0; strategyIndex < dteFileStrategies.length; strategyIndex++) {
      const files = dteFileStrategies[strategyIndex];
      dteResponse = await _postSimpleApiMultipart({
        url: dteEndpoint,
        apiKey,
        inputPayload: dteInput,
        files,
      });
      if (dteResponse.ok) break;

      const shouldTryNextStrategy = strategyIndex < dteFileStrategies.length - 1 &&
        _isSimpleApiFileSpecifiedError(dteResponse.statusCode, dteResponse.bodyText);
      if (!shouldTryNextStrategy) break;

      logger.warn('DTE_GENERATE_RETRY_ALTERNATE_FILE_FIELDS', {
        documentId,
        tipoDte,
        folio: currentFolio,
        statusCode: dteResponse.statusCode,
        strategyIndex: strategyIndex + 1,
        responseBody: _readString(dteResponse.bodyText).slice(0, 900),
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
      logger.error('DTE_GENERATE_FAILED', {
        documentId,
        tipoDte,
        folio: currentFolio,
        statusCode: dteStatusCode,
        pfxPath,
        cafPath,
        responseBody: _readString(dteBodyText).slice(0, 3500),
      });
      throw new Error(
        `DTE generation failed (${dteStatusCode}) [${dteEndpoint}]: ${dteBodyText.slice(0, 900)}`,
      );
    }

    currentFolio = await _allocateNextFolio({
      db,
      tipoDte,
      emisorRut,
      cafPath,
      folioRange: cafFolioRange,
    });
  }

  const xmlPayloadInfo = _extractXmlPayload(dteBodyBuffer, dteBodyText);
  if (!xmlPayloadInfo) {
    throw new Error(`DTE response did not include a valid XML payload (status=${dteStatusCode})`);
  }
  const xmlPayloadBuffer = xmlPayloadInfo.xmlBuffer;

  const bucket = outputBucketName ?
    admin.storage().bucket(outputBucketName) :
    admin.storage().bucket();
  const storagePrefix = `fiscal_documents/${documentId}`;
  const dteGenerateMeta = _extractSiiMetaFromPayload(dteBodyText);
  const dteGenerateResponsePath = `${storagePrefix}/dte-generate-response.txt`;
  await bucket.file(dteGenerateResponsePath).save(dteBodyBuffer, {
    resumable: false,
    contentType: 'text/plain; charset=utf-8',
    metadata: {cacheControl: 'private, max-age=0, no-store'},
  });

  const xmlPath = `${storagePrefix}/dte.xml`;
  await bucket.file(xmlPath).save(xmlPayloadBuffer, {
    resumable: false,
    contentType: 'application/xml',
    metadata: {cacheControl: 'private, max-age=0, no-store'},
  });

  const requireSiiSend = _readBoolean(process.env.SIMPLEAPI_REQUIRE_SII_SEND, true);
  let siiSendResult = {
    enabled: false,
    envioXmlPath: null,
    sendResponsePath: null,
    sendStatusPath: null,
    trackId: '',
    receivedAt: '',
    statusCode: '',
  };
  try {
    siiSendResult = await _sendDteToSiiIfEnabled({
      bucket,
      storagePrefix,
      apiKey,
      baseUrl,
      xmlPayloadBuffer,
      pfxBuffer,
      certRut,
      emisorRut,
      enabledOverride: forceSiiSend,
    });
  } catch (error) {
    const message = _readString(error?.message) || 'Unknown SII send error';
    if (requireSiiSend) {
      throw new Error(message);
    }
    logger.error('SII send failed but continuing due to SIMPLEAPI_REQUIRE_SII_SEND=false', {
      documentId,
      error: message,
    });
  }

  let pdfPath = null;
  if (includePdf) {
    const pdfInput = _buildPdfInput(payload);
    const pdfForm = new FormData();
    pdfForm.append('input', JSON.stringify(pdfInput));
    pdfForm.append('fileEnvio', new Blob([xmlPayloadBuffer]), 'dte.xml');
    if (logoPath) {
      try {
        const logoAsset = await _downloadPrivateAsset(logoPath, assetsBucketName);
        if (logoAsset.buffer.length > 0) {
          pdfForm.append('logo', new Blob([logoAsset.buffer]), 'logo.png');
        }
      } catch (error) {
        logger.warn('Unable to attach SIMPLEAPI logo, continuing without logo', {
          logoPath,
          message: _readString(error?.message),
        });
      }
    }

    const pdfResponse = await fetch(pdfEndpoint, {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'Authorization': apiKey,
      },
      body: pdfForm,
    });

    const pdfBodyBuffer = Buffer.from(await pdfResponse.arrayBuffer());
    const pdfBodyText = pdfBodyBuffer.toString('utf8');
    if (!pdfResponse.ok) {
      throw new Error(
        `PDF generation failed (${pdfResponse.status}) [${pdfEndpoint}]: ${pdfBodyText.slice(0, 300)}`,
      );
    }

    const pdfBuffer = _extractPdfBuffer(
      pdfResponse.headers.get('content-type'),
      pdfBodyBuffer,
      pdfBodyText,
    );
    if (!pdfBuffer) {
      throw new Error('PDF response did not include a valid PDF payload');
    }

    pdfPath = `${storagePrefix}/${_resolvePdfFileName({preferCedible: preferCediblePdf})}`;
    await bucket.file(pdfPath).save(pdfBuffer, {
      resumable: false,
      contentType: 'application/pdf',
      metadata: {cacheControl: 'private, max-age=0, no-store'},
    });
  }

  const xmlStoragePath = `gs://${bucket.name}/${xmlPath}`;
  const pdfStoragePath = pdfPath ? `gs://${bucket.name}/${pdfPath}` : null;
  const resolvedTrackId = _firstNonEmpty(siiSendResult.trackId, dteGenerateMeta.trackId) || null;
  const resolvedReceivedAt =
    _firstNonEmpty(siiSendResult.receivedAt, dteGenerateMeta.receivedAt) || null;
  const resolvedStatusCode =
    _firstNonEmpty(siiSendResult.statusCode, dteGenerateMeta.statusCode) || null;

  return {
    tipoDte,
    folio: currentFolio,
    cafFolioFrom: cafFolioRange.from,
    cafFolioTo: cafFolioRange.to,
    xmlPath,
    pdfPath,
    pdfCedible: preferCediblePdf,
    xmlStoragePath,
    pdfStoragePath,
    providerDocumentId: documentId,
    providerTrackId: resolvedTrackId,
    providerReceivedAt: resolvedReceivedAt,
    providerStatusCode: resolvedStatusCode,
    dteGenerateResponsePath,
    siiEnvioXmlPath: siiSendResult.envioXmlPath || null,
    siiSendResponsePath: siiSendResult.sendResponsePath || null,
    siiStatusResponsePath: siiSendResult.sendStatusPath || null,
    siiSendEnabled: siiSendResult.enabled === true,
    pfxPath,
    cafPath,
    certRut,
    logoPath,
    sourceBuckets: {
      pfx: pfxAsset.bucketName,
      caf: cafAsset.bucketName,
      output: bucket.name,
    },
  };
}

function _isPrivilegedAuth(auth) {
  if (!auth) return false;
  if (auth.token?.admin === true || auth.token?.support === true) return true;

  const allowlistRaw = _readString(process.env.SUPPORT_EMAIL_ALLOWLIST);
  if (!allowlistRaw) return false;
  const email = _toLower(auth.token?.email);
  if (!email) return false;
  return allowlistRaw
    .split(',')
    .map((part) => _toLower(part))
    .filter(Boolean)
    .includes(email);
}

function _buildInternalGuideReceptorFromEnv() {
  return {
    rut: _readString(process.env.SIMPLEAPI_EMISOR_RUT),
    razonSocial: _readString(process.env.SIMPLEAPI_EMISOR_RAZON_SOCIAL),
    giro: _readString(process.env.SIMPLEAPI_EMISOR_GIRO),
    direccion: _readString(process.env.SIMPLEAPI_EMISOR_DIRECCION),
    comuna: _readString(process.env.SIMPLEAPI_EMISOR_COMUNA),
    ciudad: _readString(process.env.SIMPLEAPI_EMISOR_CIUDAD),
  };
}

function _assertReceptorData(receptor) {
  const rut = _normalizeRut(receptor?.rut);
  if (!_isValidRutShape(rut) || !_hasValidRutDv(rut)) {
    throw new HttpsError('invalid-argument', 'receptor.rut invalido');
  }
  if (!_readString(receptor?.razonSocial)) {
    throw new HttpsError('invalid-argument', 'receptor.razonSocial es requerido');
  }
  if (!_readString(receptor?.direccion)) {
    throw new HttpsError('invalid-argument', 'receptor.direccion es requerido');
  }
}

async function _emitAndPersist({
  db,
  documentId,
  payload,
  requestAuth,
  source,
  setCaseCode = null,
  forceSiiSend = null,
}) {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const docRef = db.collection('fiscal_documents').doc(documentId);
  const tipoDte = _resolveTipoDte(payload?.documentType);
  await docRef.set({
    documentId,
    status: 'pending',
    source: _readString(source) || 'manual',
    setCaseCode: _readString(setCaseCode) || null,
    requestedByUid: _readString(requestAuth?.uid) || null,
    requestedByEmail: _readString(requestAuth?.token?.email) || null,
    documentType: _normalizeDocumentTypeInput(payload?.documentType),
    tipoDte,
    createdAt: now,
    updatedAt: now,
    errorCode: null,
    errorMessage: null,
    input: {
      receptor: payload?.receptor || null,
      itemCount: Array.isArray(payload?.items) ? payload.items.length : 0,
      referenceCount: Array.isArray(payload?.references) ? payload.references.length : 0,
      emitDate: _safeIsoDate(payload?.emitDate),
    },
  }, {merge: true});

  try {
    const includePdf = _readBoolean(
      payload?.includePdf,
      _readBoolean(process.env.SIMPLEAPI_DEFAULT_INCLUDE_PDF, true),
    );
    const result = await _emitFiscalDocument({
      documentId,
      payload,
      forceSiiSend,
      includePdf,
    });

    await docRef.set({
      status: 'issued',
      issuedAt: now,
      updatedAt: now,
      folio: result.folio,
      folioRangeFrom: result.cafFolioFrom,
      folioRangeTo: result.cafFolioTo,
      providerDocumentId: result.providerDocumentId,
      providerTrackId: result.providerTrackId,
      providerReceivedAt: result.providerReceivedAt || null,
      providerStatusCode: result.providerStatusCode || null,
      xmlPath: result.xmlPath,
      xmlUrl: result.xmlStoragePath,
      pdfPath: result.pdfPath || null,
      pdfUrl: result.pdfStoragePath || null,
      errorCode: null,
      errorMessage: null,
      providerMeta: {
        certPath: result.pfxPath,
        cafPath: result.cafPath,
        certRut: result.certRut || null,
        logoPath: result.logoPath || null,
        dteGenerateResponsePath: result.dteGenerateResponsePath || null,
        siiEnvioXmlPath: result.siiEnvioXmlPath || null,
        siiSendResponsePath: result.siiSendResponsePath || null,
        siiStatusResponsePath: result.siiStatusResponsePath || null,
        siiSendEnabled: result.siiSendEnabled === true,
        sourceBuckets: result.sourceBuckets || null,
      },
    }, {merge: true});

    return result;
  } catch (error) {
    const message = _readString(error?.message) || 'Unknown fiscal emission error';
    await docRef.set({
      status: 'failed',
      updatedAt: now,
      errorCode: 'emission_failed',
      errorMessage: message.slice(0, 2000),
      retryCount: admin.firestore.FieldValue.increment(1),
    }, {merge: true});
    throw error;
  }
}

exports.emitFiscalDocument = onCall(
  {
    region: FISCAL_REGION,
    secrets: [],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Debes iniciar sesion para continuar');
    }
    if (!_isPrivilegedAuth(request.auth)) {
      throw new HttpsError(
        'permission-denied',
        'Solo usuarios support/admin pueden emitir documentos fiscales manualmente',
      );
    }

    const payload = request.data || {};
    const documentType = _readString(payload?.documentType);
    if (!documentType) {
      throw new HttpsError('invalid-argument', 'documentType es requerido');
    }

    _resolveTipoDte(documentType);
    if (!payload?.receptor || typeof payload.receptor !== 'object') {
      throw new HttpsError('invalid-argument', 'receptor es requerido');
    }
    _assertReceptorData(payload.receptor);

    const db = admin.firestore();
    const requestedDocumentId = _readString(payload?.documentId);
    const documentId = requestedDocumentId || db.collection('fiscal_documents').doc().id;
    const forceSiiSendRaw = payload?.forceSiiSend;
    const forceSiiSend = forceSiiSendRaw == null ? null : _readBoolean(forceSiiSendRaw, false);

    try {
      const result = await _emitAndPersist({
        db,
        documentId,
        payload,
        requestAuth: request.auth,
        source: 'manual',
        forceSiiSend,
      });

      return {
        ok: true,
        documentId,
        tipoDte: result.tipoDte,
        folio: result.folio,
        providerTrackId: result.providerTrackId,
        xmlPath: result.xmlPath,
        pdfPath: result.pdfPath,
      };
    } catch (error) {
      const message = _readString(error?.message) || 'Error al emitir documento';
      logger.error('emitFiscalDocument failed', {
        documentId,
        message,
        stack: _readString(error?.stack).slice(0, 4000) || null,
      });
      throw new HttpsError('internal', message);
    }
  },
);

exports.runSiiCertificationSet = onCall(
  {
    region: FISCAL_REGION,
    secrets: [],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Debes iniciar sesion para continuar');
    }
    if (!_isPrivilegedAuth(request.auth)) {
      throw new HttpsError('permission-denied', 'Solo usuarios support/admin');
    }

    const data = request.data || {};
    const setMode = _toLower(data?.setMode || 'all');
    const allowedModes = new Set(['all', 'basic', 'guia', 'factura_compra']);
    if (!allowedModes.has(setMode)) {
      throw new HttpsError('invalid-argument', 'setMode invalido. Usa: all, basic, guia o factura_compra');
    }

    if (!data?.receptor || typeof data.receptor !== 'object') {
      throw new HttpsError('invalid-argument', 'receptor es requerido para ejecutar el set');
    }
    _assertReceptorData(data.receptor);

    const externalReceiver = {
      rut: _normalizeRut(data.receptor.rut),
      razonSocial: _readString(data.receptor.razonSocial),
      giro: _readString(data.receptor.giro),
      direccion: _readString(data.receptor.direccion),
      comuna: _readString(data.receptor.comuna),
      ciudad: _readString(data.receptor.ciudad),
      email: _readString(data.receptor.email),
      contacto: _readString(data.receptor.contacto),
    };
    const internalReceiver = _buildInternalGuideReceptorFromEnv();
    const emitDate = _safeIsoDate(data?.emitDate);
    const forceSiiSendRaw = data?.forceSiiSend;
    const forceSiiSend = forceSiiSendRaw == null ? null : _readBoolean(forceSiiSendRaw, false);
    const sendDocumentsIndividually = _readBoolean(
      process.env.SIMPLEAPI_CERT_SET_SEND_INDIVIDUAL,
      false,
    );

    const db = admin.firestore();
    const runRef = db.collection('fiscal_certification_runs').doc();
    const runId = runRef.id;
    const runNow = admin.firestore.FieldValue.serverTimestamp();

    await runRef.set({
      runId,
      status: 'running',
      mode: setMode,
      requestedByUid: _readString(request.auth.uid) || null,
      requestedByEmail: _readString(request.auth.token?.email) || null,
      startedAt: runNow,
      updatedAt: runNow,
      completedAt: null,
      results: [],
      errorMessage: null,
    });

    const resultRows = [];
    const refs = {};
    const shouldRunBasic = setMode === 'all' || setMode === 'basic';
    const shouldRunGuia = setMode === 'all' || setMode === 'guia';
    const shouldRunCompra = setMode === 'all' || setMode === 'factura_compra';

    async function emitCase(caseCode, payload) {
      const caseCodeParts = _readString(caseCode).split('_');
      const setNumber = _readString(caseCodeParts[0]);
      const caseNumber = _readString(caseCodeParts[1]);
      const caseLabel = setNumber && caseNumber ? `${setNumber}-${caseNumber}` : _readString(caseCode);

      // Primera referencia obligatoria para certificacion SII:
      // TpoDocRef=SET y RazonRef=CASO <NRO_SET>-<CASO>
      const setReference = {
        tipoDocumento: 'SET',
        folio: String(Math.max(1, _readInteger(caseNumber, 1))),
        fecha: _safeIsoDate(new Date().toISOString()),
        razonReferencia: `CASO ${caseLabel}`,
      };
      const existingReferences = Array.isArray(payload?.references) ? payload.references : [];
      const payloadWithSetReference = {
        ...(payload || {}),
        references: [setReference, ...existingReferences],
      };

      const documentId = `${runId}_${caseCode}`;
      const result = await _emitAndPersist({
        db,
        documentId,
        payload: payloadWithSetReference,
        requestAuth: request.auth,
        source: 'sii_certification',
        setCaseCode: caseCode,
        // Para certificacion SII, por defecto el set se envia en un solo sobre consolidado.
        forceSiiSend: sendDocumentsIndividually ? forceSiiSend : false,
      });
      refs[caseCode] = {
        tipoDte: result.tipoDte,
        folio: result.folio,
        date: emitDate,
      };
      resultRows.push({
        caseCode,
        documentId,
        tipoDte: result.tipoDte,
        folio: result.folio,
        providerTrackId: result.providerTrackId,
        xmlPath: result.xmlPath,
        xmlStoragePath: result.xmlStoragePath || null,
        pdfPath: result.pdfPath,
      });
      await runRef.set({
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        results: resultRows,
      }, {merge: true});
    }

    try {
      if (shouldRunBasic) {
        await emitCase('4842775_1', {
          documentType: 'factura',
          emitDate,
          receptor: externalReceiver,
          items: [
            {name: 'Cajón AFECTO', quantity: 170, unitPrice: 3617},
            {name: 'Relleno AFECTO', quantity: 72, unitPrice: 6027},
          ],
        });

        await emitCase('4842775_2', {
          documentType: 'factura',
          emitDate,
          receptor: externalReceiver,
          items: [
            {name: 'Pañuelo AFECTO', quantity: 785, unitPrice: 6069, discountPercent: 10},
            {name: 'ITEM 2 AFECTO', quantity: 730, unitPrice: 5119, discountPercent: 24},
          ],
        });

        await emitCase('4842775_3', {
          documentType: 'factura',
          emitDate,
          receptor: externalReceiver,
          items: [
            {name: 'Pintura B&W AFECTO', quantity: 67, unitPrice: 7085},
            {name: 'ITEM 2 AFECTO', quantity: 241, unitPrice: 4086},
            {name: 'ITEM 3 SERVICIO EXENTO', quantity: 1, unitPrice: 35321, exempt: true},
          ],
        });

        await emitCase('4842775_4', {
          documentType: 'factura',
          emitDate,
          receptor: externalReceiver,
          items: [
            {name: 'ITEM 1 AFECTO', quantity: 431, unitPrice: 6128},
            {name: 'ITEM 2 AFECTO', quantity: 182, unitPrice: 7490},
            {name: 'ITEM 3 SERVICIO EXENTO', quantity: 2, unitPrice: 6836, exempt: true},
          ],
          globalDiscount: {
            description: 'DESCUENTO GLOBAL ITEMES AFECTOS',
            percent: 23,
          },
        });

        await emitCase('4842775_5', {
          documentType: 'nota_credito',
          emitDate,
          receptor: externalReceiver,
          forceTasaIva: true,
          references: [
            {
              tipoDocumento: '33',
              folio: String(refs['4842775_1']?.folio || ''),
              fecha: refs['4842775_1']?.date || emitDate,
              codigoReferencia: 2,
              razonReferencia: 'CORRIGE GIRO DEL RECEPTOR',
            },
          ],
          items: [
            {
              name: 'CORRIGE GIRO DEL RECEPTOR',
              amount: 0,
              compactLine: true,
              allowZero: true,
            },
          ],
        });

        await emitCase('4842775_6', {
          documentType: 'nota_credito',
          emitDate,
          receptor: externalReceiver,
          references: [
            {
              tipoDocumento: '33',
              folio: String(refs['4842775_2']?.folio || ''),
              fecha: refs['4842775_2']?.date || emitDate,
              codigoReferencia: 3,
              razonReferencia: 'DEVOLUCION DE MERCADERIAS',
            },
          ],
          items: [
            {name: 'Pañuelo AFECTO', quantity: 288, unitPrice: 6069, discountPercent: 10},
            {name: 'ITEM 2 AFECTO', quantity: 495, unitPrice: 5119, discountPercent: 24},
          ],
        });

        await emitCase('4842775_7', {
          documentType: 'nota_credito',
          emitDate,
          receptor: externalReceiver,
          references: [
            {
              tipoDocumento: '33',
              folio: String(refs['4842775_3']?.folio || ''),
              fecha: refs['4842775_3']?.date || emitDate,
              codigoReferencia: 1,
              razonReferencia: 'ANULA FACTURA',
            },
          ],
          items: [
            {name: 'Pintura B&W AFECTO', quantity: 67, unitPrice: 7085},
            {name: 'ITEM 2 AFECTO', quantity: 241, unitPrice: 4086},
            {name: 'ITEM 3 SERVICIO EXENTO', quantity: 1, unitPrice: 35321, exempt: true},
          ],
        });

        await emitCase('4842775_8', {
          documentType: 'nota_debito',
          emitDate,
          receptor: externalReceiver,
          forceTasaIva: true,
          references: [
            {
              tipoDocumento: '61',
              folio: String(refs['4842775_5']?.folio || ''),
              fecha: refs['4842775_5']?.date || emitDate,
              codigoReferencia: 1,
              razonReferencia: 'ANULA NOTA DE CREDITO ELECTRONICA',
            },
          ],
          items: [
            {
              name: 'ANULA NOTA DE CREDITO ELECTRONICA',
              amount: 0,
              compactLine: true,
              allowZero: true,
            },
          ],
        });
      }

      if (shouldRunGuia) {
        await emitCase('4842778_1', {
          documentType: 'guia_despacho',
          emitDate,
          receptor: internalReceiver,
          guia: {
            tipoTraslado: 5,
            transporte: {
              direccionDestino: _readString(process.env.SIMPLEAPI_EMISOR_DIRECCION),
              comunaDestino: _readString(process.env.SIMPLEAPI_EMISOR_COMUNA),
              ciudadDestino: _readString(process.env.SIMPLEAPI_EMISOR_CIUDAD),
            },
          },
          items: [
            {
              name: 'ITEM 1',
              quantity: 71,
              compactLine: true,
              keepQuantity: true,
              omitLineAmount: true,
              allowZero: true,
            },
            {
              name: 'ITEM 2',
              quantity: 101,
              compactLine: true,
              keepQuantity: true,
              omitLineAmount: true,
              allowZero: true,
            },
            {
              name: 'ITEM 3',
              quantity: 65,
              compactLine: true,
              keepQuantity: true,
              omitLineAmount: true,
              allowZero: true,
            },
          ],
        });

        await emitCase('4842778_2', {
          documentType: 'guia_despacho',
          emitDate,
          receptor: externalReceiver,
          guia: {
            tipoTraslado: 1,
            tipoDespacho: 2,
            transporte: {
              direccionDestino: externalReceiver.direccion,
              comunaDestino: externalReceiver.comuna,
              ciudadDestino: externalReceiver.ciudad,
            },
          },
          items: [
            {name: 'ITEM 1', quantity: 260, unitPrice: 5494},
            {name: 'ITEM 2', quantity: 498, unitPrice: 1409},
          ],
        });

        await emitCase('4842778_3', {
          documentType: 'guia_despacho',
          emitDate,
          receptor: externalReceiver,
          guia: {
            tipoTraslado: 1,
            tipoDespacho: 1,
            transporte: {
              direccionDestino: externalReceiver.direccion,
              comunaDestino: externalReceiver.comuna,
              ciudadDestino: externalReceiver.ciudad,
            },
          },
          items: [
            {name: 'ITEM 1', quantity: 142, unitPrice: 1687},
            {name: 'ITEM 2', quantity: 315, unitPrice: 4312},
          ],
        });
      }

      if (shouldRunCompra) {
        await emitCase('4842780_1', {
          documentType: 'factura_compra',
          emitDate,
          receptor: externalReceiver,
          impuestoRetenido: {
            aplicar: true,
            tipoImpuesto: 15,
            tasa: 19,
            modo: 'total',
          },
          items: [
            {name: 'Producto 1', quantity: 919, unitPrice: 7075, codigoImpuestoAdicional: [15]},
            {name: 'Producto 2', quantity: 37, unitPrice: 3903, codigoImpuestoAdicional: [15]},
          ],
        });

        await emitCase('4842780_2', {
          documentType: 'nota_credito',
          emitDate,
          receptor: externalReceiver,
          impuestoRetenido: {
            aplicar: true,
            tipoImpuesto: 15,
            tasa: 19,
            modo: 'total',
          },
          references: [
            {
              tipoDocumento: '46',
              folio: String(refs['4842780_1']?.folio || ''),
              fecha: refs['4842780_1']?.date || emitDate,
              codigoReferencia: 3,
              razonReferencia: 'DEVOLUCION DE MERCADERIA ITEMS 1 Y 2',
            },
          ],
          items: [
            {name: 'Producto 1', quantity: 306, unitPrice: 7075, codigoImpuestoAdicional: [15]},
            {name: 'Producto 2', quantity: 12, unitPrice: 3903, codigoImpuestoAdicional: [15]},
          ],
        });

        await emitCase('4842780_3', {
          documentType: 'nota_debito',
          emitDate,
          receptor: externalReceiver,
          impuestoRetenido: {
            aplicar: true,
            tipoImpuesto: 15,
            tasa: 19,
            modo: 'total',
          },
          references: [
            {
              tipoDocumento: '61',
              folio: String(refs['4842780_2']?.folio || ''),
              fecha: refs['4842780_2']?.date || emitDate,
              codigoReferencia: 1,
              razonReferencia: 'ANULA NOTA DE CREDITO ELECTRONICA',
            },
          ],
          items: [
            {name: 'Producto 1', quantity: 306, unitPrice: 7075, codigoImpuestoAdicional: [15]},
            {name: 'Producto 2', quantity: 12, unitPrice: 3903, codigoImpuestoAdicional: [15]},
          ],
        });
      }

      const requireSiiSend = _readBoolean(process.env.SIMPLEAPI_REQUIRE_SII_SEND, true);
      let setEnvelope = {
        enabled: false,
        envioXmlPath: null,
        sendResponsePath: null,
        sendStatusPath: null,
        trackId: '',
        receivedAt: '',
        statusCode: '',
      };

      try {
        const outputBucketName = _readString(process.env.SIMPLEAPI_OUTPUT_BUCKET);
        const outputBucket = outputBucketName ?
          admin.storage().bucket(outputBucketName) :
          admin.storage().bucket();
        const xmlBuffers = [];
        for (const row of resultRows) {
          const xmlPath = _readString(row?.xmlPath);
          if (!xmlPath) continue;
          const [xmlBuffer] = await outputBucket.file(xmlPath).download();
          if (Buffer.isBuffer(xmlBuffer) && xmlBuffer.length > 0) {
            xmlBuffers.push(xmlBuffer);
          }
        }

        if (xmlBuffers.length > 0) {
          const apiKey = _readEnvOrThrow('SIMPLEAPI_API_KEY');
          const baseUrl = _readString(process.env.SIMPLEAPI_BASE_URL) || 'https://api.simpleapi.cl';
          const pfxPath = _readEnvOrThrow('SIMPLEAPI_PFX_STORAGE_PATH');
          const assetsBucketName = _readString(process.env.SIMPLEAPI_ASSETS_BUCKET);
          const pfxAsset = await _downloadPrivateAsset(pfxPath, assetsBucketName);
          if (!pfxAsset.buffer.length) {
            throw new Error(`Downloaded empty PFX buffer from ${pfxAsset.bucketName}/${pfxAsset.objectPath}`);
          }

          setEnvelope = await _sendDteToSiiIfEnabled({
            bucket: outputBucket,
            storagePrefix: `fiscal_certification_runs/${runId}`,
            apiKey,
            baseUrl,
            xmlPayloadBuffers: xmlBuffers,
            pfxBuffer: pfxAsset.buffer,
            certRut: _normalizeRut(_readString(process.env.SIMPLEAPI_CERT_RUT)),
            emisorRut: _normalizeRut(_readString(process.env.SIMPLEAPI_EMISOR_RUT)),
            enabledOverride: forceSiiSend,
          });
        }
      } catch (error) {
        const message = _readString(error?.message) || 'Unknown consolidated set send error';
        if (requireSiiSend) {
          throw new Error(message);
        }
        logger.error(
          'Consolidated set send failed but continuing due to SIMPLEAPI_REQUIRE_SII_SEND=false',
          {
            runId,
            message,
          },
        );
      }

      await runRef.set({
        status: 'completed',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        results: resultRows,
        setEnvelope,
      }, {merge: true});

      return {
        ok: true,
        runId,
        mode: setMode,
        documents: resultRows,
        setEnvelope,
      };
    } catch (error) {
      const message = _readString(error?.message) || 'Error ejecutando set de certificacion';
      await runRef.set({
        status: 'failed',
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        errorMessage: message.slice(0, 2000),
        results: resultRows,
      }, {merge: true});

      logger.error('runSiiCertificationSet failed', {
        runId,
        mode: setMode,
        message,
        stack: _readString(error?.stack).slice(0, 4000) || null,
      });
      throw new HttpsError('internal', message);
    }
  },
);

