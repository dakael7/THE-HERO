const {onCall, HttpsError} = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const forge = require('node-forge');
const {DOMParser, XMLSerializer} = require('@xmldom/xmldom');
const {SignedXml} = require('xml-crypto');

const FISCAL_REGION = 'southamerica-west1';

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

function _readDecimal(value, fallback = 0) {
  const n = _asNumber(value);
  if (!Number.isFinite(n)) return fallback;
  return n;
}

function _readInteger(value, fallback = 0) {
  const n = Math.round(_asNumber(value));
  if (!Number.isFinite(n)) return fallback;
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
  const [body, dv] = rut.split('-');
  if (!body || !dv) return false;
  return _computeRutDv(body) === dv;
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

function _xmlEscape(value) {
  return _readString(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function _sanitizeTextForXml(value) {
  return _readString(value).replace(/[^\x20-\x7E]/g, ' ').replace(/\s+/g, ' ').trim();
}

function _sanitizeXmlDocumentForSii(xmlText) {
  const raw = _readString(xmlText)
    .replace(/^\uFEFF/, '')
    .replace(/\r\n/g, '\n')
    .replace(/\r/g, '\n');

  // Keep XML-safe chars and force a strict Latin-1-compatible subset.
  const sanitized = raw.replace(/[^\x09\x0A\x0D\x20-\x7E\xA0-\xFF]/g, ' ');
  const header = '<?xml version="1.0" encoding="ISO-8859-1"?>';
  if (sanitized.startsWith('<?xml')) {
    return sanitized.replace(/^<\?xml[\s\S]*?\?>/i, header);
  }
  return `${header}\n${sanitized}`;
}

function _formatPeriod(value) {
  const raw = _readString(value);
  if (!raw) return new Date().toISOString().slice(0, 7);
  if (!/^\d{4}-\d{2}$/.test(raw)) {
    throw new HttpsError('invalid-argument', 'period debe tener formato AAAA-MM');
  }
  const [year, month] = raw.split('-').map((part) => Number(part));
  if (!Number.isInteger(year) || !Number.isInteger(month) || month < 1 || month > 12) {
    throw new HttpsError('invalid-argument', 'period invalido');
  }
  return raw;
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

function _extractSigningMaterialFromPfx({pfxBuffer, password}) {
  if (!Buffer.isBuffer(pfxBuffer) || pfxBuffer.length === 0) {
    throw new Error('Empty PFX buffer');
  }

  let p12;
  try {
    const der = forge.util.createBuffer(pfxBuffer.toString('binary'));
    const asn1 = forge.asn1.fromDer(der);
    p12 = forge.pkcs12.pkcs12FromAsn1(asn1, false, password);
  } catch (error) {
    throw new Error(`Unable to parse PFX certificate: ${_readString(error?.message)}`);
  }

  const keyBags = [
    ...(p12.getBags({bagType: forge.pki.oids.pkcs8ShroudedKeyBag})[
      forge.pki.oids.pkcs8ShroudedKeyBag
    ] || []),
    ...(p12.getBags({bagType: forge.pki.oids.keyBag})[
      forge.pki.oids.keyBag
    ] || []),
  ];
  const certBags = p12.getBags({bagType: forge.pki.oids.certBag})[forge.pki.oids.certBag] || [];
  const key = keyBags[0]?.key || null;
  const cert = certBags[0]?.cert || null;

  if (!key || !cert) {
    throw new Error('PFX does not contain private key and certificate');
  }

  const privateKeyPem = forge.pki.privateKeyToPem(key);
  const certificatePem = forge.pki.certificateToPem(cert);
  const certificateBase64 = certificatePem
    .replace(/-----BEGIN CERTIFICATE-----/g, '')
    .replace(/-----END CERTIFICATE-----/g, '')
    .replace(/\r?\n/g, '');
  const certificateDer = forge.asn1.toDer(forge.pki.certificateToAsn1(cert)).getBytes();
  const certificateSha1 = forge.md.sha1.create().update(certificateDer).digest().toHex();
  const publicKey = cert.publicKey || null;
  const modulusHexRaw = _readString(publicKey?.n?.toString(16));
  const exponentHexRaw = _readString(publicKey?.e?.toString(16));
  const modulusHex = modulusHexRaw.length % 2 === 0 ? modulusHexRaw : `0${modulusHexRaw}`;
  const exponentHex = exponentHexRaw.length % 2 === 0 ? exponentHexRaw : `0${exponentHexRaw}`;
  const rsaModulusBase64 = modulusHex ? Buffer.from(modulusHex, 'hex').toString('base64') : '';
  const rsaExponentBase64 = exponentHex ? Buffer.from(exponentHex, 'hex').toString('base64') : '';

  return {
    privateKeyPem,
    certificatePem,
    certificateBase64,
    certificateSha1,
    rsaModulusBase64,
    rsaExponentBase64,
  };
}

function _addXmlReferenceCompat(signature, xpath, uri) {
  const transforms = [
    // For libros SII validates digest over canonicalized EnvioLibro.
    'http://www.w3.org/TR/2001/REC-xml-c14n-20010315',
  ];
  const digestAlgorithm = 'http://www.w3.org/2000/09/xmldsig#sha1';

  try {
    signature.addReference({
      xpath,
      transforms,
      digestAlgorithm,
      uri,
    });
    return;
  } catch (_) {}

  signature.addReference(xpath, transforms, digestAlgorithm, uri);
}

function _computeSignatureWithCompat(signature, xml, location) {
  try {
    const fixedLocation = {
      reference: location?.reference,
      action: 'after',
    };
    signature.computeSignature(xml, {location: fixedLocation});
    return;
  } catch (_) {}

  signature.computeSignature(xml);
  const signatureXml = signature.getSignatureXml();
  const signedXml = _readString(signature.signedXml);
  const signatureTagRegex = /<(?:\w+:)?Signature\b[\s\S]*?<\/(?:\w+:)?Signature>/i;
  const withoutSignature = signedXml.replace(signatureTagRegex, '').trim();
  const closingTagRegex = /<\/(?:\w+:)?EnvioLibro>/gi;
  let closingMatch = null;
  while (true) {
    const next = closingTagRegex.exec(withoutSignature);
    if (!next) break;
    closingMatch = next;
  }
  if (closingMatch) {
    const idx = closingMatch.index + closingMatch[0].length;
    signature.signedXml =
      withoutSignature.slice(0, idx) +
      '\n' + signatureXml + '\n' +
      withoutSignature.slice(idx);
  } else {
    signature.signedXml = signedXml;
  }
}

function _findFirstElementByLocalName(rootNode, localName) {
  if (!rootNode || !localName) return null;
  const nodes = rootNode.getElementsByTagName('*');
  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i];
    if (_readString(node?.localName) === localName || _readString(node?.nodeName).endsWith(`:${localName}`) || _readString(node?.nodeName) === localName) {
      return node;
    }
  }
  return null;
}

function _removeFirstElementByLocalName(parentNode, localName) {
  if (!parentNode || !localName) return false;
  const children = parentNode.childNodes || [];
  for (let i = 0; i < children.length; i++) {
    const child = children[i];
    if (!child || child.nodeType !== 1) continue;
    if (_readString(child.localName) === localName || _readString(child.nodeName).endsWith(`:${localName}`) || _readString(child.nodeName) === localName) {
      parentNode.removeChild(child);
      return true;
    }
  }
  return false;
}

function _rewriteSignatureForSiiSchema({
  signedXml,
  privateKeyPem,
}) {
  const xmlText = _readString(signedXml);
  if (!xmlText) return xmlText;

  const doc = new DOMParser().parseFromString(xmlText, 'text/xml');
  const signatureNode = _findFirstElementByLocalName(doc, 'Signature');
  if (!signatureNode) return xmlText;
  const signedInfoNode = _findFirstElementByLocalName(signatureNode, 'SignedInfo');
  if (!signedInfoNode) return xmlText;

  const referenceNode = _findFirstElementByLocalName(signedInfoNode, 'Reference');
  if (referenceNode) {
    _removeFirstElementByLocalName(referenceNode, 'Transforms');
  }

  const signatureValueNode = _findFirstElementByLocalName(signatureNode, 'SignatureValue');
  if (!signatureValueNode) return new XMLSerializer().serializeToString(doc);

  const signer = new SignedXml();
  signer.idAttributes = ['ID'];
  signer.privateKey = privateKeyPem;
  signer.loadSignature(signatureNode);
  signer.calculateSignatureValue(doc);
  signatureValueNode.textContent = signer.signatureValue;

  return new XMLSerializer().serializeToString(doc);
}

function _signBookXml({
  xml,
  envNodeXPath,
  envNodeId,
  privateKeyPem,
  certificateBase64,
  rsaModulusBase64,
  rsaExponentBase64,
}) {
  const signature = new SignedXml();
  signature.idAttributes = ['ID'];
  signature.signatureAlgorithm = 'http://www.w3.org/2000/09/xmldsig#rsa-sha1';
  signature.canonicalizationAlgorithm = 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315';
  signature.signingKey = privateKeyPem;
  signature.privateKey = privateKeyPem;
  const keyValueBlock =
    rsaModulusBase64 && rsaExponentBase64 ?
      `<KeyValue><RSAKeyValue><Modulus>${rsaModulusBase64}</Modulus><Exponent>${rsaExponentBase64}</Exponent></RSAKeyValue></KeyValue>` :
      '';
  const keyInfoContent =
    `${keyValueBlock}<X509Data><X509Certificate>${certificateBase64}</X509Certificate></X509Data>`;
  signature.keyInfoProvider = {
    getKeyInfo() {
      return keyInfoContent;
    },
  };
  signature.getKeyInfoContent = () => keyInfoContent;
  _addXmlReferenceCompat(signature, envNodeXPath, `#${envNodeId}`);
  _computeSignatureWithCompat(signature, xml, {
    reference: envNodeXPath,
    action: 'after',
  });
  const signedXml = signature.getSignedXml();
  return _rewriteSignatureForSiiSchema({
    signedXml,
    privateKeyPem,
  });
}

function _readTag(xmlText, tagName) {
  const regex = new RegExp(
    `<(?:\\w+:)?${tagName}\\b[^>]*>([\\s\\S]*?)<\\/(?:\\w+:)?${tagName}>`,
    'i',
  );
  const match = _readString(xmlText).match(regex);
  return _readString(match?.[1] || '');
}

function _readTagByCandidates(xmlText, candidates) {
  for (const tag of candidates) {
    const value = _readTag(xmlText, tag);
    if (value) return value;
  }
  return '';
}

function _parseIntegerFromText(value, fallback = 0) {
  const clean = _readString(value).replace(/[^\d-]/g, '');
  if (!clean) return fallback;
  const n = Number(clean);
  if (!Number.isFinite(n)) return fallback;
  return Math.round(n);
}

function _firstDateInPeriod(value, period) {
  const parsed = _safeIsoDate(value);
  if (_readString(parsed).startsWith(`${period}-`)) return parsed;
  return `${period}-01`;
}

function _parseGsUrl(gsUrl) {
  const raw = _readString(gsUrl);
  if (!raw.startsWith('gs://')) return null;
  const tail = raw.slice(5);
  const firstSlash = tail.indexOf('/');
  if (firstSlash <= 0 || firstSlash === tail.length - 1) return null;
  return {
    bucket: tail.slice(0, firstSlash),
    path: tail.slice(firstSlash + 1),
  };
}

function _decodeXmlBuffer(xmlBuffer) {
  const utf8Head = xmlBuffer.slice(0, 200).toString('utf8');
  const hasLatin1Header = /encoding\s*=\s*["'](?:ISO-8859-1|iso-8859-1|latin1|LATIN1)["']/i.test(utf8Head);
  return hasLatin1Header ? xmlBuffer.toString('latin1') : xmlBuffer.toString('utf8');
}

function _extractReferenceFromXml(xmlText) {
  const raw = _readString(xmlText);
  const refs = [];
  const regex = /<(?:\w+:)?Referencia\b[^>]*>([\s\S]*?)<\/(?:\w+:)?Referencia>/gi;
  let match;
  while ((match = regex.exec(raw)) !== null) {
    const chunk = _readString(match?.[1] || '');
    if (!chunk) continue;
    const type = _parseIntegerFromText(
      _readTagByCandidates(chunk, ['TpoDocRef', 'TipoDocRef', 'TipoDocumento']),
      0,
    );
    const folio = _parseIntegerFromText(
      _readTagByCandidates(chunk, ['FolioRef', 'FolioDocRef', 'Folio']),
      0,
    );
    const date = _readTagByCandidates(chunk, ['FchRef', 'FchDocRef', 'FechaDocRef']);
    refs.push({type, folio, date});
  }
  if (refs.length === 0) {
    return {type: 0, folio: 0, date: ''};
  }

  const validRefDocTypes = new Set([
    30, 32, 33, 34, 35, 38, 39, 41, 43, 45, 46, 50, 52, 55, 56, 60, 61, 101, 103, 106, 110, 111, 112,
  ]);
  const withPair = refs.filter((ref) => ref.type > 0 && ref.folio > 0);
  const preferred = withPair.find((ref) => validRefDocTypes.has(ref.type));
  if (preferred) return preferred;
  if (withPair.length > 0) return withPair[0];
  return {type: 0, folio: 0, date: ''};
}

function _normalizeBookEntryFromXml({
  xmlText,
  fallbackTipoDte,
  fallbackFolio,
  fallbackDate,
  fallbackRutDoc,
  fallbackRznSoc,
}) {
  const ref = _extractReferenceFromXml(xmlText);
  const tipoDte = _parseIntegerFromText(
    _readTagByCandidates(xmlText, ['TipoDTE', 'TpoDoc', 'TipoDoc']),
    fallbackTipoDte,
  );
  const folio = _parseIntegerFromText(_readTagByCandidates(xmlText, ['Folio', 'NroDoc']), fallbackFolio);
  const emitDate = _readTagByCandidates(xmlText, ['FchEmis', 'FchDoc']);
  const rutDoc = _normalizeRut(_readTagByCandidates(xmlText, ['RUTRecep', 'RUTDoc']) || fallbackRutDoc);
  const rznSoc = _sanitizeTextForXml(
    _readTagByCandidates(xmlText, ['RznSocRecep', 'RznSoc']) || fallbackRznSoc,
  );
  const mntExe = _parseIntegerFromText(_readTag(xmlText, 'MntExe'), 0);
  const mntNeto = _parseIntegerFromText(_readTag(xmlText, 'MntNeto'), 0);
  const mntIva = _parseIntegerFromText(_readTagByCandidates(xmlText, ['IVA', 'MntIVA']), 0);
  const mntTotal = _parseIntegerFromText(_readTag(xmlText, 'MntTotal'), mntExe + mntNeto + mntIva);
  const tipoTraslado = _parseIntegerFromText(_readTagByCandidates(xmlText, ['TipoTraslado', 'TpoTraslado']), 0);
  return {
    tipoDte,
    folio,
    emitDate: emitDate || fallbackDate,
    rutDoc,
    rznSoc,
    mntExe,
    mntNeto,
    mntIva,
    mntTotal,
    tipoTraslado,
    refType: ref.type,
    refFolio: ref.folio,
    refDate: ref.date,
  };
}

function _resolveXmlStorageLocation(data, defaultBucketName) {
  const gs = _parseGsUrl(data?.xmlUrl);
  if (gs?.bucket && gs?.path) return gs;
  const xmlPath = _readString(data?.xmlPath);
  if (!xmlPath) return null;
  const providerOutputBucket = _readString(data?.providerMeta?.sourceBuckets?.output);
  return {
    bucket: providerOutputBucket || defaultBucketName,
    path: xmlPath,
  };
}

async function _loadIssuedDocsForPeriod({
  db,
  period,
  onlyCertificationSource,
}) {
  const snap = await db.collection('fiscal_documents')
    .where('status', '==', 'issued')
    .get();

  const rows = [];
  snap.forEach((docSnap) => {
    const data = docSnap.data() || {};
    const emitDate = _safeIsoDate(data?.input?.emitDate || data?.issuedAt?.toDate?.() || null);
    if (!emitDate.startsWith(`${period}-`)) return;
    if (onlyCertificationSource) {
      const source = _readString(data?.source);
      const allowedSources = new Set(['certification_set', 'sii_certification']);
      if (!allowedSources.has(source)) return;
    }
    rows.push({
      id: docSnap.id,
      ...data,
      emitDate,
    });
  });
  return rows;
}

function _buildVentasEntriesFromDocs(rows, period, allowedSetNumbers = [], allowedRunIds = []) {
  const allowed = new Set((allowedSetNumbers || []).map((value) => _readString(value)));
  const allowedRuns = new Set((allowedRunIds || []).map((value) => _readString(value)));
  const filteredRows = rows.filter((row) => {
    if (allowedRuns.size > 0) {
      const runId = _extractRunIdFromDocumentId(row?.id);
      if (!allowedRuns.has(runId)) return false;
    }
    if (allowed.size === 0) return true;
    const setNumber = _extractSetNumberFromCaseCode(row?.setCaseCode);
    return allowed.has(setNumber);
  });
  const latestRows = _pickLatestRowsByCase(filteredRows);
  const byPriority = latestRows
    .filter((row) => [33, 56, 61].includes(_readInteger(row?.tipoDte, 0)))
    .sort((a, b) => _readString(a?.setCaseCode).localeCompare(_readString(b?.setCaseCode)));

  return byPriority.map((row) => ({
    documentId: row.id,
    setCaseCode: _readString(row?.setCaseCode),
    tipoDte: _readInteger(row?.tipoDte, 0),
    folio: _readInteger(row?.folio, 0),
    emitDate: _firstDateInPeriod(row.emitDate, period),
    rutDoc: _normalizeRut(row?.input?.receptor?.rut),
    rznSoc: _sanitizeTextForXml(row?.input?.receptor?.razonSocial),
    mntExe: 0,
    mntNeto: 0,
    mntIva: 0,
    mntTotal: 0,
    refType: 0,
    refFolio: 0,
    refDate: '',
  }));
}

function _buildGuiaEntriesFromDocs(rows, period, allowedSetNumbers = [], allowedRunIds = []) {
  const allowed = new Set((allowedSetNumbers || []).map((value) => _readString(value)));
  const allowedRuns = new Set((allowedRunIds || []).map((value) => _readString(value)));
  const filteredRows = rows.filter((row) => {
    if (allowedRuns.size > 0) {
      const runId = _extractRunIdFromDocumentId(row?.id);
      if (!allowedRuns.has(runId)) return false;
    }
    if (allowed.size === 0) return true;
    const setNumber = _extractSetNumberFromCaseCode(row?.setCaseCode);
    return allowed.has(setNumber);
  });
  const guides = _pickLatestRowsByCase(filteredRows)
    .filter((row) => _readInteger(row?.tipoDte, 0) === 52)
    .sort((a, b) => _readString(a?.setCaseCode).localeCompare(_readString(b?.setCaseCode)));

  return guides.map((row) => {
    const setCaseCode = _readString(row?.setCaseCode);
    let tpoOper = _readInteger(row?.input?.guia?.tipoTraslado, 0);
    if (setCaseCode.endsWith('_1')) tpoOper = 5;
    if (setCaseCode.endsWith('_2') || setCaseCode.endsWith('_3')) tpoOper = 1;
    return {
      documentId: row.id,
      setCaseCode,
      folio: _readInteger(row?.folio, 0),
      emitDate: _firstDateInPeriod(row.emitDate, period),
      rutDoc: _normalizeRut(row?.input?.receptor?.rut),
      rznSoc: _sanitizeTextForXml(row?.input?.receptor?.razonSocial),
      mntTotal: 0,
      tpoOper: [1, 2, 3, 4, 5, 6, 7].includes(tpoOper) ? tpoOper : 1,
      anulado: setCaseCode.endsWith('_3') ? 2 : 0,
      refType: 0,
      refFolio: 0,
      refDate: '',
    };
  });
}

function _buildCertificationComprasTemplate({
  period,
  rutDoc,
  rznSoc,
}) {
  const safeRutDoc = _normalizeRut(rutDoc);
  const safeRznSoc = _sanitizeTextForXml(rznSoc) || 'Proveedor Set Compras';
  const baseDate = `${period}-01`;
  return [
    {tipoDte: 30, folio: 234, mntExe: 0, mntNeto: 25461, mntIva: 4838, mntTotal: 30299},
    {tipoDte: 33, folio: 32, mntExe: 9077, mntNeto: 7172, mntIva: 1363, mntTotal: 17612},
    {
      tipoDte: 30,
      folio: 781,
      mntExe: 0,
      mntNeto: 29836,
      mntIva: 0,
      ivaUsoComun: 5669,
      fctProp: 0.6,
      credIvaUsoComun: 3401,
      mntTotal: 35505,
    },
    {tipoDte: 60, folio: 451, mntExe: 0, mntNeto: 2746, mntIva: 522, mntTotal: 3268, refType: 30, refFolio: 234},
    {
      tipoDte: 33,
      folio: 67,
      mntExe: 0,
      mntNeto: 10301,
      mntIva: 0,
      ivaNoRec: [{cod: 4, monto: 1957}],
      mntTotal: 12258,
    },
    {
      tipoDte: 46,
      folio: 9,
      mntExe: 0,
      mntNeto: 9712,
      mntIva: 1845,
      // En Factura de Compra con retencion total del IVA, el libro de compras
      // debe informar la retencion como OtrosImp cod. 15 y cuadrar MntTotal neto de retencion.
      otrosImp: [{codImp: 15, tasaImp: 19, mntImp: 1845}],
      mntTotal: 9712,
    },
    {tipoDte: 60, folio: 211, mntExe: 0, mntNeto: 5063, mntIva: 962, mntTotal: 6025, refType: 33, refFolio: 32},
  ].map((item) => ({
    ...item,
    emitDate: baseDate,
    rutDoc: safeRutDoc,
    rznSoc: safeRznSoc,
    refDate: item.refType ? baseDate : '',
  }));
}

function _normalizeSetNumberList(value, fallback = []) {
  const out = [];
  const seen = new Set();
  const push = (raw) => {
    const text = _readString(raw);
    if (!/^\d{7}$/.test(text) || seen.has(text)) return;
    seen.add(text);
    out.push(text);
  };

  if (Array.isArray(value)) {
    value.forEach((item) => push(item));
  } else if (typeof value === 'string') {
    value.split(',').forEach((item) => push(item));
  } else if (value != null) {
    push(String(value));
  }

  if (out.length > 0) return out;

  const fallbackOut = [];
  const fallbackSeen = new Set();
  for (const item of fallback || []) {
    const text = _readString(item);
    if (!/^\d{7}$/.test(text) || fallbackSeen.has(text)) continue;
    fallbackSeen.add(text);
    fallbackOut.push(text);
  }
  return fallbackOut;
}

function _normalizeRunIdList(value, fallback = []) {
  const out = [];
  const seen = new Set();
  const push = (raw) => {
    const text = _readString(raw);
    if (!text || seen.has(text)) return;
    seen.add(text);
    out.push(text);
  };

  if (Array.isArray(value)) {
    value.forEach((item) => push(item));
  } else if (typeof value === 'string') {
    value.split(',').forEach((item) => push(item));
  } else if (value != null) {
    push(String(value));
  }

  if (out.length > 0) return out;

  const fallbackOut = [];
  const fallbackSeen = new Set();
  for (const item of fallback || []) {
    const text = _readString(item);
    if (!text || fallbackSeen.has(text)) continue;
    fallbackSeen.add(text);
    fallbackOut.push(text);
  }
  return fallbackOut;
}

function _extractSetNumberFromCaseCode(caseCode) {
  const match = _readString(caseCode).match(/^(\d+)_\d+$/);
  return match?.[1] || '';
}

function _extractRunIdFromDocumentId(documentId) {
  const match = _readString(documentId).match(/^([^_]+)_\d+_\d+$/);
  return _readString(match?.[1] || '');
}

function _rowTimestampMs(row) {
  const candidates = [row?.issuedAt, row?.updatedAt, row?.createdAt];
  for (const value of candidates) {
    if (value && typeof value.toMillis === 'function') {
      return value.toMillis();
    }
  }
  return 0;
}

function _pickLatestRowsByCase(rows) {
  const byCase = new Map();
  for (const row of rows || []) {
    const key = _readString(row?.setCaseCode) || _readString(row?.id);
    if (!key) continue;
    const prev = byCase.get(key);
    if (!prev) {
      byCase.set(key, row);
      continue;
    }
    if (_rowTimestampMs(row) >= _rowTimestampMs(prev)) {
      byCase.set(key, row);
    }
  }
  return [...byCase.values()];
}

function _buildTotalesPeriodoByTipo(rows, operation = 'VENTA') {
  const isCompra = _toLower(operation) === 'compra';
  const grouped = new Map();
  for (const row of rows) {
    const key = _readInteger(row?.tipoDte, 0);
    if (key <= 0) continue;
    if (!grouped.has(key)) {
      grouped.set(key, {
        tipoDte: key,
        totDoc: 0,
        totOpExe: 0,
        totMntExe: 0,
        totMntNeto: 0,
        totOpIvaRec: 0,
        totMntIva: 0,
        ivaNoRecByCode: new Map(),
        totOpIvaUsoComun: 0,
        totIvaUsoComun: 0,
        fctProp: 0,
        totCredIvaUsoComun: 0,
        totOpIvaRetTotal: 0,
        totIvaRetTotal: 0,
        otrosImpByCode: new Map(),
        totIvaNoRetenido: 0,
        totMntTotal: 0,
      });
    }
    const agg = grouped.get(key);
    const mntExe = _readInteger(row?.mntExe, 0);
    const mntNeto = _readInteger(row?.mntNeto, 0);
    const mntIva = _readInteger(row?.mntIva, 0);
    const mntTotal = _readInteger(row?.mntTotal, 0);
    const ivaUsoComun = _readInteger(row?.ivaUsoComun, 0);
    const credIvaUsoComun = _readInteger(row?.credIvaUsoComun, 0);
    const ivaRetTotal = _readInteger(row?.ivaRetTotal, 0);
    const ivaNoRetenido = _readInteger(row?.ivaNoRetenido, 0);

    agg.totDoc += 1;
    if (mntExe !== 0) agg.totOpExe += 1;
    agg.totMntExe += mntExe;
    agg.totMntNeto += mntNeto;
    if (mntIva !== 0) agg.totOpIvaRec += 1;
    agg.totMntIva += mntIva;

    const ivaNoRecItems = Array.isArray(row?.ivaNoRec) ? row.ivaNoRec : [];
    for (const rawItem of ivaNoRecItems) {
      const cod = _readInteger(rawItem?.cod, 0);
      const monto = _readInteger(rawItem?.monto, 0);
      if (![1, 2, 3, 4, 9].includes(cod) || monto === 0) continue;
      if (!agg.ivaNoRecByCode.has(cod)) {
        agg.ivaNoRecByCode.set(cod, {cod, count: 0, amount: 0});
      }
      const bucket = agg.ivaNoRecByCode.get(cod);
      bucket.count += 1;
      bucket.amount += monto;
    }

    if (ivaUsoComun !== 0) {
      agg.totOpIvaUsoComun += 1;
      agg.totIvaUsoComun += ivaUsoComun;
      const rawFactor = _readDecimal(row?.fctProp, 0);
      if (rawFactor > 0) agg.fctProp = rawFactor;
      if (credIvaUsoComun !== 0) {
        agg.totCredIvaUsoComun += credIvaUsoComun;
      }
    }

    if (ivaRetTotal !== 0) {
      if (!isCompra) {
        agg.totOpIvaRetTotal += 1;
        agg.totIvaRetTotal += ivaRetTotal;
      } else {
        // Compatibilidad compras: si llega IVA retenido sin OtrosImp, lo mapeamos a CodImp 15.
        if (!agg.otrosImpByCode.has(15)) {
          agg.otrosImpByCode.set(15, {codImp: 15, count: 0, amount: 0, tasaImp: 19});
        }
        const bucket = agg.otrosImpByCode.get(15);
        bucket.count += 1;
        bucket.amount += ivaRetTotal;
      }
    }

    const otrosImpItems = Array.isArray(row?.otrosImp) ? row.otrosImp : [];
    for (const rawItem of otrosImpItems) {
      const codImp = _readInteger(rawItem?.codImp, 0);
      const mntImp = _readInteger(rawItem?.mntImp, 0);
      const tasaImp = _readDecimal(rawItem?.tasaImp, 0);
      if (codImp <= 0 || mntImp === 0) continue;
      if (!agg.otrosImpByCode.has(codImp)) {
        agg.otrosImpByCode.set(codImp, {codImp, count: 0, amount: 0, tasaImp});
      }
      const bucket = agg.otrosImpByCode.get(codImp);
      bucket.count += 1;
      bucket.amount += mntImp;
      if (tasaImp > 0) bucket.tasaImp = tasaImp;
    }

    if (ivaNoRetenido !== 0) {
      agg.totIvaNoRetenido += ivaNoRetenido;
    }

    agg.totMntTotal += mntTotal;
  }

  const rowsOut = Array.from(grouped.values());
  for (const agg of rowsOut) {
    if (agg.totOpIvaUsoComun > 0 && agg.totCredIvaUsoComun === 0 && agg.fctProp > 0) {
      agg.totCredIvaUsoComun = Math.round(agg.totIvaUsoComun * agg.fctProp);
    }
    agg.ivaNoRec = Array.from(agg.ivaNoRecByCode.values())
      .filter((item) => item.amount !== 0)
      .sort((a, b) => a.cod - b.cod);
    agg.otrosImp = Array.from(agg.otrosImpByCode.values())
      .filter((item) => item.amount !== 0)
      .sort((a, b) => a.codImp - b.codImp);
    delete agg.ivaNoRecByCode;
    delete agg.otrosImpByCode;
  }
  return rowsOut.sort((a, b) => a.tipoDte - b.tipoDte);
}

function _buildLibroCvXml({
  operation,
  period,
  rutEmisorLibro,
  rutEnvia,
  fechaResolucion,
  numeroResolucion,
  folioNotificacion,
  entries,
  bookId,
}) {
  const isCompra = _toLower(operation) === 'compra';
  const detailLines = entries.map((entry) => {
    const lines = [
      '    <Detalle>',
      `      <TpoDoc>${_readInteger(entry?.tipoDte, 0)}</TpoDoc>`,
      `      <NroDoc>${_readInteger(entry?.folio, 0)}</NroDoc>`,
      '      <TasaImp>0.19</TasaImp>',
      `      <FchDoc>${_xmlEscape(_safeIsoDate(entry?.emitDate))}</FchDoc>`,
    ];
    const rutDoc = _normalizeRut(entry?.rutDoc);
    if (_hasValidRutDv(rutDoc)) lines.push(`      <RUTDoc>${_xmlEscape(rutDoc)}</RUTDoc>`);
    const rznSoc = _sanitizeTextForXml(entry?.rznSoc);
    if (rznSoc) lines.push(`      <RznSoc>${_xmlEscape(rznSoc.slice(0, 50))}</RznSoc>`);
    const refType = _readInteger(entry?.refType, 0);
    const refFolio = _readInteger(entry?.refFolio, 0);
    if (refType > 0 && refFolio > 0) {
      lines.push(`      <TpoDocRef>${refType}</TpoDocRef>`);
      lines.push(`      <FolioDocRef>${refFolio}</FolioDocRef>`);
    }
    if (_readInteger(entry?.mntExe, 0) !== 0) {
      lines.push(`      <MntExe>${_readInteger(entry?.mntExe, 0)}</MntExe>`);
    }
    lines.push(`      <MntNeto>${_readInteger(entry?.mntNeto, 0)}</MntNeto>`);
    lines.push(`      <MntIVA>${_readInteger(entry?.mntIva, 0)}</MntIVA>`);
    const ivaNoRecItems = Array.isArray(entry?.ivaNoRec) ? entry.ivaNoRec : [];
    for (const rawItem of ivaNoRecItems) {
      const cod = _readInteger(rawItem?.cod, 0);
      const monto = _readInteger(rawItem?.monto, 0);
      if (![1, 2, 3, 4, 9].includes(cod) || monto === 0) continue;
      lines.push('      <IVANoRec>');
      lines.push(`        <CodIVANoRec>${cod}</CodIVANoRec>`);
      lines.push(`        <MntIVANoRec>${monto}</MntIVANoRec>`);
      lines.push('      </IVANoRec>');
    }
    if (_readInteger(entry?.ivaUsoComun, 0) !== 0) {
      lines.push(`      <IVAUsoComun>${_readInteger(entry?.ivaUsoComun, 0)}</IVAUsoComun>`);
    }
    const rawOtrosImp = Array.isArray(entry?.otrosImp) ? entry.otrosImp : [];
    const normalizedOtrosImp = rawOtrosImp.map((item) => ({
      codImp: _readInteger(item?.codImp, 0),
      tasaImp: _readDecimal(item?.tasaImp, 0),
      mntImp: _readInteger(item?.mntImp, 0),
    })).filter((item) => item.codImp > 0 && item.mntImp !== 0);
    if (isCompra && normalizedOtrosImp.length === 0 && _readInteger(entry?.ivaRetTotal, 0) !== 0) {
      normalizedOtrosImp.push({
        codImp: 15,
        tasaImp: 19,
        mntImp: _readInteger(entry?.ivaRetTotal, 0),
      });
    }
    for (const imp of normalizedOtrosImp) {
      lines.push('      <OtrosImp>');
      lines.push(`        <CodImp>${imp.codImp}</CodImp>`);
      if (imp.tasaImp > 0) {
        lines.push(`        <TasaImp>${imp.tasaImp.toFixed(2)}</TasaImp>`);
      }
      lines.push(`        <MntImp>${imp.mntImp}</MntImp>`);
      lines.push('      </OtrosImp>');
    }
    if (!isCompra && _readInteger(entry?.ivaRetTotal, 0) !== 0) {
      lines.push(`      <IVARetTotal>${_readInteger(entry?.ivaRetTotal, 0)}</IVARetTotal>`);
    }
    if (isCompra && _readInteger(entry?.ivaNoRetenido, 0) !== 0) {
      lines.push(`      <IVANoRetenido>${_readInteger(entry?.ivaNoRetenido, 0)}</IVANoRetenido>`);
    }
    lines.push(`      <MntTotal>${_readInteger(entry?.mntTotal, 0)}</MntTotal>`);
    lines.push('    </Detalle>');
    return lines.join('\n');
  });

  const totals = _buildTotalesPeriodoByTipo(entries, operation).map((row) => {
    const lines = [
      '      <TotalesPeriodo>',
      `        <TpoDoc>${row.tipoDte}</TpoDoc>`,
      `        <TotDoc>${row.totDoc}</TotDoc>`,
      `        <TotMntExe>${row.totMntExe}</TotMntExe>`,
      `        <TotMntNeto>${row.totMntNeto}</TotMntNeto>`,
      `        <TotMntIVA>${row.totMntIva}</TotMntIVA>`,
    ];
    if (row.totOpExe > 0) {
      lines.splice(3, 0, `        <TotOpExe>${row.totOpExe}</TotOpExe>`);
    }
    if (row.totOpIvaRec > 0) {
      lines.splice(row.totOpExe > 0 ? 6 : 5, 0, `        <TotOpIVARec>${row.totOpIvaRec}</TotOpIVARec>`);
    }
    for (const ivaNoRec of row.ivaNoRec || []) {
      lines.push('        <TotIVANoRec>');
      lines.push(`          <CodIVANoRec>${ivaNoRec.cod}</CodIVANoRec>`);
      lines.push(`          <TotOpIVANoRec>${ivaNoRec.count}</TotOpIVANoRec>`);
      lines.push(`          <TotMntIVANoRec>${ivaNoRec.amount}</TotMntIVANoRec>`);
      lines.push('        </TotIVANoRec>');
    }
    if (row.totOpIvaUsoComun > 0) {
      lines.push(`        <TotOpIVAUsoComun>${row.totOpIvaUsoComun}</TotOpIVAUsoComun>`);
      lines.push(`        <TotIVAUsoComun>${row.totIvaUsoComun}</TotIVAUsoComun>`);
      if (row.fctProp > 0) {
        lines.push(`        <FctProp>${row.fctProp.toFixed(3)}</FctProp>`);
      }
      lines.push(`        <TotCredIVAUsoComun>${row.totCredIvaUsoComun}</TotCredIVAUsoComun>`);
    }
    if (!isCompra && row.totOpIvaRetTotal > 0) {
      lines.push(`        <TotOpIVARetTotal>${row.totOpIvaRetTotal}</TotOpIVARetTotal>`);
      lines.push(`        <TotIVARetTotal>${row.totIvaRetTotal}</TotIVARetTotal>`);
    }
    for (const imp of row.otrosImp || []) {
      lines.push('        <TotOtrosImp>');
      lines.push(`          <CodImp>${imp.codImp}</CodImp>`);
      lines.push(`          <TotMntImp>${imp.amount}</TotMntImp>`);
      lines.push('        </TotOtrosImp>');
    }
    if (isCompra && _readInteger(row.totIvaNoRetenido, 0) !== 0) {
      lines.push(`        <TotIVANoRetenido>${_readInteger(row.totIvaNoRetenido, 0)}</TotIVANoRetenido>`);
    }
    lines.push(
      `        <TotMntTotal>${row.totMntTotal}</TotMntTotal>`,
      '      </TotalesPeriodo>',
    );
    return lines.join('\n');
  });

  const tipoOperacion = operation === 'COMPRA' ? 'COMPRA' : 'VENTA';
  const tmstFirma = new Date().toISOString().slice(0, 19);

  return [
    '<?xml version="1.0" encoding="ISO-8859-1"?>',
    '<LibroCompraVenta xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.sii.cl/SiiDte LibroCV_v10.xsd" version="1.0" xmlns="http://www.sii.cl/SiiDte">',
    `  <EnvioLibro ID="${_xmlEscape(bookId)}">`,
    '    <Caratula>',
    `      <RutEmisorLibro>${_xmlEscape(rutEmisorLibro)}</RutEmisorLibro>`,
    `      <RutEnvia>${_xmlEscape(rutEnvia)}</RutEnvia>`,
    `      <PeriodoTributario>${_xmlEscape(period)}</PeriodoTributario>`,
    `      <FchResol>${_xmlEscape(_safeIsoDate(fechaResolucion))}</FchResol>`,
    `      <NroResol>${_readInteger(numeroResolucion, 0)}</NroResol>`,
    `      <TipoOperacion>${tipoOperacion}</TipoOperacion>`,
    '      <TipoLibro>ESPECIAL</TipoLibro>',
    '      <TipoEnvio>TOTAL</TipoEnvio>',
    `      <FolioNotificacion>${_readInteger(folioNotificacion, 1)}</FolioNotificacion>`,
    '    </Caratula>',
    '    <ResumenPeriodo>',
    totals.join('\n'),
    '    </ResumenPeriodo>',
    detailLines.join('\n'),
    `    <TmstFirma>${tmstFirma}</TmstFirma>`,
    '  </EnvioLibro>',
    '</LibroCompraVenta>',
    '',
  ].join('\n');
}

function _buildLibroGuiaXml({
  period,
  rutEmisorLibro,
  rutEnvia,
  fechaResolucion,
  numeroResolucion,
  folioNotificacion,
  entries,
  bookId,
}) {
  const normalized = entries.map((row) => ({
    ...row,
    tpoOper: [1, 2, 3, 4, 5, 6, 7].includes(_readInteger(row?.tpoOper, 0)) ? _readInteger(row?.tpoOper, 1) : 1,
    anulado: _readInteger(row?.anulado, 0),
    mntTotal: _readInteger(row?.mntTotal, 0),
  }));

  let totGuiaAnulada = 0;
  let totGuiaVenta = 0;
  let totMntGuiaVta = 0;
  const trasladoMap = new Map();

  for (const row of normalized) {
    if (row.anulado > 0) {
      totGuiaAnulada += 1;
      continue;
    }
    if (row.tpoOper === 1) {
      totGuiaVenta += 1;
      totMntGuiaVta += row.mntTotal;
      continue;
    }
    if (!trasladoMap.has(row.tpoOper)) {
      trasladoMap.set(row.tpoOper, {count: 0, amount: 0});
    }
    const bucket = trasladoMap.get(row.tpoOper);
    bucket.count += 1;
    bucket.amount += row.mntTotal;
  }

  const trasladoLines = Array.from(trasladoMap.entries())
    .sort((a, b) => a[0] - b[0])
    .map(([tipo, info]) => [
      '      <TotTraslado>',
      `        <TpoTraslado>${tipo}</TpoTraslado>`,
      `        <CantGuia>${info.count}</CantGuia>`,
      `        <MntGuia>${info.amount}</MntGuia>`,
      '      </TotTraslado>',
    ].join('\n'));

  const detailLines = normalized.map((row) => {
    const lines = [
      '    <Detalle>',
      `      <Folio>${_readInteger(row?.folio, 0)}</Folio>`,
    ];
    if (_readInteger(row?.anulado, 0) > 0) {
      lines.push(`      <Anulado>${_readInteger(row?.anulado, 0)}</Anulado>`);
    }
    lines.push(`      <TpoOper>${row.tpoOper}</TpoOper>`);
    lines.push(`      <MntTotal>${row.mntTotal}</MntTotal>`);
    const refType = _readInteger(row?.refType, 0);
    const refFolio = _readInteger(row?.refFolio, 0);
    if (refType > 0 && refFolio > 0) {
      lines.push(`      <TpoDocRef>${refType}</TpoDocRef>`);
      lines.push(`      <FolioDocRef>${refFolio}</FolioDocRef>`);
    }
    if (_readString(row?.refDate)) {
      lines.push(`      <FchDocRef>${_xmlEscape(_safeIsoDate(row?.refDate))}</FchDocRef>`);
    }
    lines.push('    </Detalle>');
    return lines.join('\n');
  });

  const tmstFirma = new Date().toISOString().slice(0, 19);

  return [
    '<?xml version="1.0" encoding="ISO-8859-1"?>',
    '<LibroGuia xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.sii.cl/SiiDte LibroGuia_v10.xsd" version="1.0" xmlns="http://www.sii.cl/SiiDte">',
    `  <EnvioLibro ID="${_xmlEscape(bookId)}">`,
    '    <Caratula>',
    `      <RutEmisorLibro>${_xmlEscape(rutEmisorLibro)}</RutEmisorLibro>`,
    `      <RutEnvia>${_xmlEscape(rutEnvia)}</RutEnvia>`,
    `      <PeriodoTributario>${_xmlEscape(period)}</PeriodoTributario>`,
    `      <FchResol>${_xmlEscape(_safeIsoDate(fechaResolucion))}</FchResol>`,
    `      <NroResol>${_readInteger(numeroResolucion, 0)}</NroResol>`,
    '      <TipoLibro>ESPECIAL</TipoLibro>',
    '      <TipoEnvio>TOTAL</TipoEnvio>',
    `      <FolioNotificacion>${_readInteger(folioNotificacion, 1)}</FolioNotificacion>`,
    '    </Caratula>',
    '    <ResumenPeriodo>',
    `      <TotGuiaAnulada>${totGuiaAnulada}</TotGuiaAnulada>`,
    `      <TotGuiaVenta>${totGuiaVenta}</TotGuiaVenta>`,
    `      <TotMntGuiaVta>${totMntGuiaVta}</TotMntGuiaVta>`,
    trasladoLines.join('\n'),
    '    </ResumenPeriodo>',
    detailLines.join('\n'),
    `    <TmstFirma>${tmstFirma}</TmstFirma>`,
    '  </EnvioLibro>',
    '</LibroGuia>',
    '',
  ].join('\n');
}

exports.generateFiscalBooksDraft = onCall(
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
        'Solo usuarios support/admin pueden generar libros fiscales',
      );
    }

    const data = request.data || {};
    const period = _formatPeriod(data?.period);
    const onlyCertificationSource = _readBoolean(data?.onlyCertificationSource, true);
    const includeVentas = _readBoolean(data?.includeVentas, true);
    const includeCompras = _readBoolean(data?.includeCompras, true);
    const includeGuias = _readBoolean(data?.includeGuias, true);
    if (!includeVentas && !includeCompras && !includeGuias) {
      throw new HttpsError('invalid-argument', 'Debes habilitar al menos un libro a generar');
    }

    const rutEmisorLibro = _normalizeRut(process.env.SIMPLEAPI_EMISOR_RUT);
    const rutEnvia = _normalizeRut(
      _readString(process.env.SIMPLEAPI_CERT_RUT) ||
      _readString(process.env.SIMPLEAPI_SII_AUTH_RUT) ||
      _readString(process.env.SIMPLEAPI_EMISOR_RUT),
    );
    if (!_hasValidRutDv(rutEmisorLibro) || !_hasValidRutDv(rutEnvia)) {
      throw new HttpsError('failed-precondition', 'RUT de emisor o rut envia invalido en .env');
    }

    const fechaResolucion = _safeIsoDate(
      data?.resolutionDate || process.env.SIMPLEAPI_SII_RESOLUTION_DATE || new Date().toISOString(),
    );
    const numeroResolucion = _readInteger(
      data?.resolutionNumber ?? process.env.SIMPLEAPI_SII_RESOLUTION_NUMBER,
      0,
    );
    const folioNotificacionVentas = Math.max(1, _readInteger(
      data?.folioNotificacionVentas ?? process.env.SII_BOOK_FOLIO_NOTIF_VENTAS,
      1,
    ));
    const folioNotificacionCompras = Math.max(1, _readInteger(
      data?.folioNotificacionCompras ?? process.env.SII_BOOK_FOLIO_NOTIF_COMPRAS,
      1,
    ));
    const folioNotificacionGuias = Math.max(1, _readInteger(
      data?.folioNotificacionGuias ?? process.env.SII_BOOK_FOLIO_NOTIF_GUIAS,
      1,
    ));
    const comprasRutDoc = _normalizeRut(
      data?.comprasRutDoc ?? process.env.SII_BOOK_COMPRAS_RUTDOC ?? '17096073-4',
    );
    const comprasRznSoc = _sanitizeTextForXml(
      data?.comprasRznSoc ?? process.env.SII_BOOK_COMPRAS_RZNSOC ?? 'Razon Social',
    );
    const signXml = _readBoolean(data?.signXml, true);
    const ventasSetNumbers = _normalizeSetNumberList(
      data?.ventasSetNumbers ?? process.env.SII_BOOK_VENTAS_SET_NUMBERS ?? process.env.SII_BOOK_VENTAS_SET_NUMBER,
      ['4842775'],
    );
    const guiasSetNumbers = _normalizeSetNumberList(
      data?.guiasSetNumbers ?? process.env.SII_BOOK_GUIAS_SET_NUMBERS ?? process.env.SII_BOOK_GUIAS_SET_NUMBER,
      ['4842778'],
    );
    const ventasRunIds = _normalizeRunIdList(
      data?.ventasRunIds ?? process.env.SII_BOOK_VENTAS_RUN_IDS ?? process.env.SII_BOOK_VENTAS_RUN_ID,
      [],
    );
    const guiasRunIds = _normalizeRunIdList(
      data?.guiasRunIds ?? process.env.SII_BOOK_GUIAS_RUN_IDS ?? process.env.SII_BOOK_GUIAS_RUN_ID,
      [],
    );

    const db = admin.firestore();
    const runRef = db.collection('fiscal_book_runs').doc();
    const runId = runRef.id;

    const outputBucketName = _readString(process.env.SIMPLEAPI_OUTPUT_BUCKET);
    const bucket = outputBucketName ? admin.storage().bucket(outputBucketName) : admin.storage().bucket();
    const outputPrefix =
      _readString(data?.outputPrefix) || `fiscal_books/${period.replace('-', '')}/${runId}`;

    await runRef.set({
      runId,
      period,
      status: 'running',
      requestedByUid: _readString(request.auth?.uid) || null,
      requestedByEmail: _readString(request.auth?.token?.email) || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      includeVentas,
      includeCompras,
      includeGuias,
      onlyCertificationSource,
    }, {merge: true});

    try {
      const rawRows = await _loadIssuedDocsForPeriod({
        db,
        period,
        onlyCertificationSource,
      });

      const rows = rawRows.filter((row) => {
        const tipo = _readInteger(row?.tipoDte, 0);
        const setNumber = _extractSetNumberFromCaseCode(row?.setCaseCode);
        const runId = _extractRunIdFromDocumentId(row?.id);

        const matchesVentas = includeVentas &&
          [33, 56, 61].includes(tipo) &&
          (ventasSetNumbers.length === 0 || ventasSetNumbers.includes(setNumber)) &&
          (ventasRunIds.length === 0 || ventasRunIds.includes(runId));

        const matchesGuias = includeGuias &&
          tipo === 52 &&
          (guiasSetNumbers.length === 0 || guiasSetNumbers.includes(setNumber)) &&
          (guiasRunIds.length === 0 || guiasRunIds.includes(runId));

        return matchesVentas || matchesGuias;
      });

      const enrichedRows = [];
      for (const row of rows) {
        const storageLocation = _resolveXmlStorageLocation(row, bucket.name);
        let parsed = {
          tipoDte: _readInteger(row?.tipoDte, 0),
          folio: _readInteger(row?.folio, 0),
          emitDate: _safeIsoDate(row?.emitDate),
          rutDoc: _normalizeRut(row?.input?.receptor?.rut),
          rznSoc: _sanitizeTextForXml(row?.input?.receptor?.razonSocial),
          mntExe: 0,
          mntNeto: 0,
          mntIva: 0,
          mntTotal: 0,
          tipoTraslado: _readInteger(row?.input?.guia?.tipoTraslado, 0),
          refType: 0,
          refFolio: 0,
          refDate: '',
        };

        if (storageLocation?.bucket && storageLocation?.path) {
          try {
            const [xmlBuffer] = await admin.storage()
              .bucket(storageLocation.bucket)
              .file(storageLocation.path)
              .download();
            if (Buffer.isBuffer(xmlBuffer) && xmlBuffer.length > 0) {
              const xmlText = _decodeXmlBuffer(xmlBuffer);
              parsed = _normalizeBookEntryFromXml({
                xmlText,
                fallbackTipoDte: parsed.tipoDte,
                fallbackFolio: parsed.folio,
                fallbackDate: parsed.emitDate,
                fallbackRutDoc: parsed.rutDoc,
                fallbackRznSoc: parsed.rznSoc,
              });
            }
          } catch (error) {
            logger.warn('Unable to parse XML for fiscal book entry, using fallback values', {
              documentId: row.id,
              bucket: storageLocation.bucket,
              path: storageLocation.path,
              message: _readString(error?.message),
            });
          }
        }

        enrichedRows.push({
          ...row,
          bookData: parsed,
        });
      }

      const ventasEntries = _buildVentasEntriesFromDocs(
        enrichedRows,
        period,
        ventasSetNumbers,
        ventasRunIds,
      ).map((row) => {
        const match = enrichedRows.find((item) => item.id === row.documentId);
        return {...row, ...match?.bookData};
      });
      const guiaEntries = _buildGuiaEntriesFromDocs(
        enrichedRows,
        period,
        guiasSetNumbers,
        guiasRunIds,
      ).map((row) => {
        const match = enrichedRows.find((item) => item.id === row.documentId);
        const merged = {...row, ...match?.bookData};
        if (row.setCaseCode.endsWith('_3')) merged.anulado = 2;
        return merged;
      });
      const comprasEntries = _buildCertificationComprasTemplate({
        period,
        rutDoc: comprasRutDoc,
        rznSoc: comprasRznSoc,
      });

      let signingMaterial = null;
      let signingMeta = null;
      if (signXml) {
        const pfxPath = _readEnvOrThrow('SIMPLEAPI_PFX_STORAGE_PATH');
        const pfxPassword = _readEnvOrThrow('SIMPLEAPI_PFX_PASSWORD');
        const assetsBucketName = _readString(process.env.SIMPLEAPI_ASSETS_BUCKET);
        const pfxAsset = await _downloadPrivateAsset(pfxPath, assetsBucketName);
        signingMaterial = _extractSigningMaterialFromPfx({
          pfxBuffer: pfxAsset.buffer,
          password: pfxPassword,
        });
        signingMeta = {
          pfxPath: `${pfxAsset.bucketName}/${pfxAsset.objectPath}`,
          certRutExpected: rutEnvia,
          certificateSha1: signingMaterial.certificateSha1,
        };
      }

      const files = {};
      if (includeVentas) {
        const bookId = `ID_LIBRO_VENTAS_${period.replace('-', '')}`;
        const ventasXml = _buildLibroCvXml({
          operation: 'VENTA',
          period,
          rutEmisorLibro,
          rutEnvia,
          fechaResolucion,
          numeroResolucion,
          folioNotificacion: folioNotificacionVentas,
          entries: ventasEntries,
          bookId,
        });
        const ventasXmlSigned = signXml ?
          _signBookXml({
            xml: ventasXml,
            envNodeXPath: "/*[local-name()='LibroCompraVenta']/*[local-name()='EnvioLibro']",
            envNodeId: bookId,
            privateKeyPem: signingMaterial.privateKeyPem,
            certificateBase64: signingMaterial.certificateBase64,
            rsaModulusBase64: signingMaterial.rsaModulusBase64,
            rsaExponentBase64: signingMaterial.rsaExponentBase64,
          }) :
          ventasXml;
        const ventasXmlFinal = signXml ? ventasXmlSigned : _sanitizeXmlDocumentForSii(ventasXmlSigned);
        const path = `${outputPrefix}/libro_ventas_${period}.xml`;
        await bucket.file(path).save(Buffer.from(ventasXmlFinal, 'latin1'), {
          resumable: false,
          contentType: 'application/xml',
          metadata: {cacheControl: 'private, max-age=0, no-store'},
        });
        files.ventas = {
          path,
          gsUrl: `gs://${bucket.name}/${path}`,
          documentCount: ventasEntries.length,
          signed: signXml,
        };
      }

      if (includeCompras) {
        const bookId = `ID_LIBRO_COMPRAS_${period.replace('-', '')}`;
        const comprasXml = _buildLibroCvXml({
          operation: 'COMPRA',
          period,
          rutEmisorLibro,
          rutEnvia,
          fechaResolucion,
          numeroResolucion,
          folioNotificacion: folioNotificacionCompras,
          entries: comprasEntries,
          bookId,
        });
        const comprasXmlSigned = signXml ?
          _signBookXml({
            xml: comprasXml,
            envNodeXPath: "/*[local-name()='LibroCompraVenta']/*[local-name()='EnvioLibro']",
            envNodeId: bookId,
            privateKeyPem: signingMaterial.privateKeyPem,
            certificateBase64: signingMaterial.certificateBase64,
            rsaModulusBase64: signingMaterial.rsaModulusBase64,
            rsaExponentBase64: signingMaterial.rsaExponentBase64,
          }) :
          comprasXml;
        const comprasXmlFinal = signXml ? comprasXmlSigned : _sanitizeXmlDocumentForSii(comprasXmlSigned);
        const path = `${outputPrefix}/libro_compras_${period}.xml`;
        await bucket.file(path).save(Buffer.from(comprasXmlFinal, 'latin1'), {
          resumable: false,
          contentType: 'application/xml',
          metadata: {cacheControl: 'private, max-age=0, no-store'},
        });
        files.compras = {
          path,
          gsUrl: `gs://${bucket.name}/${path}`,
          documentCount: comprasEntries.length,
          signed: signXml,
        };
      }

      if (includeGuias) {
        const bookId = `ID_LIBRO_GUIAS_${period.replace('-', '')}`;
        const guiasXml = _buildLibroGuiaXml({
          period,
          rutEmisorLibro,
          rutEnvia,
          fechaResolucion,
          numeroResolucion,
          folioNotificacion: folioNotificacionGuias,
          entries: guiaEntries,
          bookId,
        });
        const guiasXmlSigned = signXml ?
          _signBookXml({
            xml: guiasXml,
            envNodeXPath: "/*[local-name()='LibroGuia']/*[local-name()='EnvioLibro']",
            envNodeId: bookId,
            privateKeyPem: signingMaterial.privateKeyPem,
            certificateBase64: signingMaterial.certificateBase64,
            rsaModulusBase64: signingMaterial.rsaModulusBase64,
            rsaExponentBase64: signingMaterial.rsaExponentBase64,
          }) :
          guiasXml;
        const guiasXmlFinal = signXml ? guiasXmlSigned : _sanitizeXmlDocumentForSii(guiasXmlSigned);
        const path = `${outputPrefix}/libro_guias_${period}.xml`;
        await bucket.file(path).save(Buffer.from(guiasXmlFinal, 'latin1'), {
          resumable: false,
          contentType: 'application/xml',
          metadata: {cacheControl: 'private, max-age=0, no-store'},
        });
        files.guias = {
          path,
          gsUrl: `gs://${bucket.name}/${path}`,
          documentCount: guiaEntries.length,
          signed: signXml,
        };
      }

      const summaryPath = `${outputPrefix}/summary.json`;
      const summary = {
        runId,
        period,
        generatedAt: new Date().toISOString(),
        onlyCertificationSource,
        includeVentas,
        includeCompras,
        includeGuias,
        signXml,
        rutEmisorLibro,
        rutEnvia,
        fechaResolucion,
        numeroResolucion,
        folioNotificacionVentas,
        folioNotificacionCompras,
        folioNotificacionGuias,
        ventasSetNumbers,
        guiasSetNumbers,
        ventasRunIds,
        guiasRunIds,
        signing: signingMeta,
        files,
      };
      await bucket.file(summaryPath).save(Buffer.from(JSON.stringify(summary, null, 2), 'utf8'), {
        resumable: false,
        contentType: 'application/json',
        metadata: {cacheControl: 'private, max-age=0, no-store'},
      });

      await runRef.set({
        status: 'completed',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        fileCount: Object.keys(files).length,
        files,
        summaryPath,
      }, {merge: true});

      return {
        ok: true,
        runId,
        period,
        files,
        summaryPath,
        summaryGsUrl: `gs://${bucket.name}/${summaryPath}`,
        notes: [
          signXml ?
            'Los XML fueron firmados con el certificado configurado en SIMPLEAPI_PFX_STORAGE_PATH.' :
            'Los XML fueron generados sin firma digital (signXml=false).',
        ],
      };
    } catch (error) {
      const message = _readString(error?.message) || 'Error al generar libros';
      await runRef.set({
        status: 'failed',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        errorMessage: message.slice(0, 2000),
      }, {merge: true});
      logger.error('generateFiscalBooksDraft failed', {
        runId,
        message,
        stack: _readString(error?.stack).slice(0, 4000) || null,
      });
      throw new HttpsError('internal', message);
    }
  },
);
