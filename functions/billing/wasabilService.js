/* eslint-disable require-jsdoc */
const DEFAULT_BASE_URL = 'https://api.wasabil.com/api';

function _readString(value) {
  if (typeof value !== 'string') return '';
  return value.trim();
}

function _baseUrl() {
  return (_readString(process.env.WASABIL_BASE_URL) || DEFAULT_BASE_URL)
      .replace(/\/+$/, '');
}

function _apiToken() {
  const token = _readString(process.env.WASABIL_API_TOKEN);
  if (!token) {
    throw new Error('Missing required env: WASABIL_API_TOKEN');
  }
  return token;
}

function _unwrapData(payload) {
  let current = payload;
  for (let i = 0; i < 3; i++) {
    if (
      current &&
      typeof current === 'object' &&
      current.success === true &&
      current.data != null
    ) {
      current = current.data;
      continue;
    }
    break;
  }
  return current;
}

function _formatApiError(status, payload, rawText) {
  const validation = payload?.validation && typeof payload.validation === 'object' ?
    Object.entries(payload.validation)
        .map(([field, message]) => `${field}: ${message}`)
        .join(', ') :
    '';
  const message = _readString(payload?.error) ||
    _readString(payload?.message) ||
    validation ||
    _readString(rawText).slice(0, 500) ||
    `HTTP ${status}`;
  const code = _readString(payload?.errorCode);
  return `Wasabil request failed (${status}${code ? `, ${code}` : ''}): ${message}`;
}

async function _requestJson(path, {method = 'GET', body} = {}) {
  const response = await fetch(`${_baseUrl()}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${_apiToken()}`,
      ...(body == null ? {} : {'Content-Type': 'application/json'}),
    },
    body: body == null ? undefined : JSON.stringify(body),
  });
  const rawText = await response.text();
  let payload = null;
  if (rawText) {
    try {
      payload = JSON.parse(rawText);
    } catch (_) {
      payload = null;
    }
  }

  if (!response.ok || payload?.success === false) {
    throw new Error(_formatApiError(response.status, payload, rawText));
  }

  return _unwrapData(payload);
}

function _documentPath(documentId, suffix = '') {
  const id = encodeURIComponent(_readString(String(documentId || '')));
  if (!id) throw new Error('Missing Wasabil document id');
  return `/documents/${id}${suffix}`;
}

async function createDocument(payload) {
  return _requestJson('/documents', {method: 'POST', body: payload});
}

async function issueDocument(documentId) {
  return _requestJson(_documentPath(documentId, '/issue'), {method: 'POST'});
}

async function getDocumentStatus(documentId) {
  return _requestJson(_documentPath(documentId, '/status'));
}

async function downloadDocumentFile(documentId, fileType) {
  const suffixes = {
    pdf: '/pdf',
    xml: '/xml',
    origXml: '/orig-xml',
  };
  const suffix = suffixes[fileType];
  if (!suffix) throw new Error(`Unsupported Wasabil file type: ${fileType}`);

  const response = await fetch(`${_baseUrl()}${_documentPath(documentId, suffix)}`, {
    headers: {Authorization: `Bearer ${_apiToken()}`},
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(_formatApiError(response.status, null, text));
  }
  return Buffer.from(await response.arrayBuffer());
}

module.exports = {
  createDocument,
  issueDocument,
  getDocumentStatus,
  downloadDocumentFile,
  __test: {_unwrapData},
};
