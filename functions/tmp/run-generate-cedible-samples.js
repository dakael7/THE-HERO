const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

function _readString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function _readBoolean(value, fallback = false) {
  if (typeof value === "boolean") return value;
  if (typeof value === "number") return value === 1;
  const normalized = _readString(value).toLowerCase();
  if (!normalized) return fallback;
  if (["1", "true", "yes", "y", "si", "on"].includes(normalized)) return true;
  if (["0", "false", "no", "n", "off"].includes(normalized)) return false;
  return fallback;
}

function _loadEnv(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx <= 0) continue;
    const key = trimmed.slice(0, idx).trim();
    const value = trimmed.slice(idx + 1);
    if (!(key in process.env)) process.env[key] = value;
  }
}

function _resolveStorageObject(storagePath, fallbackBucketName = "") {
  const raw = _readString(storagePath);
  if (!raw) throw new Error("Missing storage path");

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

  return {
    bucketName: _readString(fallbackBucketName),
    objectPath: raw.replace(/^\/+/, ""),
  };
}

async function _downloadPrivateAsset(storagePath, fallbackBucketName = "") {
  const resolved = _resolveStorageObject(storagePath, fallbackBucketName);
  const bucket = resolved.bucketName ? admin.storage().bucket(resolved.bucketName) : admin.storage().bucket();
  const [buffer] = await bucket.file(resolved.objectPath).download();
  return {
    buffer,
    bucketName: bucket.name,
    objectPath: resolved.objectPath,
  };
}

function _resolveSimpleApiEndpoint(baseUrl, explicitUrl, fallbackPath) {
  const explicit = _readString(explicitUrl);
  if (explicit) return explicit;
  return `${baseUrl.replace(/\/+$/, "")}${fallbackPath}`;
}

function _resolveCediblePdfEndpoint(baseUrl, explicitUrl) {
  const resolved = _resolveSimpleApiEndpoint(
    baseUrl,
    explicitUrl,
    "/api/v1/impresion/pdf/carta/v2/cedible",
  ).replace(/\/+$/, "");

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

function _tryParseJson(rawText) {
  const text = _readString(rawText);
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    return null;
  }
}

function _extractPdfBuffer(contentType, bodyBuffer, bodyText) {
  const normalizedContentType = _readString(contentType).toLowerCase();
  if (normalizedContentType.includes("application/pdf")) {
    return bodyBuffer;
  }
  if (Buffer.isBuffer(bodyBuffer) && bodyBuffer.length >= 4) {
    const signature = bodyBuffer.subarray(0, 4).toString("utf8");
    if (signature === "%PDF") return bodyBuffer;
  }

  const json = _tryParseJson(bodyText);
  if (!json) return null;
  const candidates = [
    json?.pdf,
    json?.archivoPdf,
    json?.data?.pdf,
    json?.data?.archivoPdf,
    json?.result?.pdf,
  ];
  for (const raw of candidates) {
    if (typeof raw !== "string" || !raw.trim()) continue;
    try {
      const buffer = Buffer.from(raw, "base64");
      if (buffer.length >= 4 && buffer.subarray(0, 4).toString("utf8") === "%PDF") {
        return buffer;
      }
    } catch (_) {}
  }
  return null;
}

function _buildPdfInput() {
  return {
    NumeroResolucion: _readString(process.env.SIMPLEAPI_SII_RESOLUTION_NUMBER) || "",
    UnidadSII: _readString(process.env.SIMPLEAPI_SII_UNIT) || "",
    FechaResolucion: _readString(process.env.SIMPLEAPI_SII_RESOLUTION_DATE) || "",
    Vendedor: _readString(process.env.SIMPLEAPI_DEFAULT_VENDEDOR) || "",
    FormaPago: _readString(process.env.SIMPLEAPI_DEFAULT_FORMA_PAGO) || "Contado",
    CondicionVenta: _readString(process.env.SIMPLEAPI_DEFAULT_CONDICION_VENTA) || "Contado",
    PropiedadLogo: _readString(process.env.SIMPLEAPI_LOGO_FIT) || "contain",
  };
}

function _toLocalCediblePath(localPath) {
  const normalized = _readString(localPath);
  if (!normalized) return "";
  if (normalized.toLowerCase().endsWith(".pdf")) {
    return normalized.slice(0, -4) + "_cedible.pdf";
  }
  return `${normalized}_cedible.pdf`;
}

function _toStorageCediblePath(storagePath) {
  const normalized = _readString(storagePath);
  if (!normalized) return "";
  if (normalized.endsWith("/document.pdf")) {
    return normalized.replace(/\/document\.pdf$/i, "/document_cedible.pdf");
  }
  if (normalized.toLowerCase().endsWith(".pdf")) {
    return normalized.slice(0, -4) + "_cedible.pdf";
  }
  return `${normalized}_cedible.pdf`;
}

function _toXmlStoragePath(storagePdfPath) {
  const normalized = _readString(storagePdfPath);
  if (!normalized) return "";
  if (normalized.endsWith("/document.pdf")) {
    return normalized.replace(/\/document\.pdf$/i, "/dte.xml");
  }
  return normalized.replace(/\.pdf$/i, ".xml");
}

async function _buildCediblePdfFromXml({
  endpoint,
  apiKey,
  pdfInput,
  xmlBuffer,
  logoBuffer = null,
}) {
  const form = new FormData();
  form.append("input", JSON.stringify(pdfInput));
  form.append("fileEnvio", new Blob([xmlBuffer]), "dte.xml");
  if (logoBuffer && logoBuffer.length > 0) {
    form.append("logo", new Blob([logoBuffer]), "logo.png");
  }

  const basicAuth = `Basic ${Buffer.from(`api:${apiKey}`, "utf8").toString("base64")}`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "Authorization": basicAuth,
    },
    body: form,
  });

  const bodyBuffer = Buffer.from(await response.arrayBuffer());
  const bodyText = bodyBuffer.toString("utf8");
  if (!response.ok) {
    throw new Error(`PDF cedible failed (${response.status}): ${bodyText.slice(0, 400)}`);
  }

  const pdfBuffer = _extractPdfBuffer(response.headers.get("content-type"), bodyBuffer, bodyText);
  if (!pdfBuffer) {
    throw new Error("Cedible response did not include a valid PDF payload");
  }
  return pdfBuffer;
}

async function main() {
  const root = process.cwd();
  const repoRoot = path.resolve(root, "..");
  const envPath = path.join(root, ".env");
  const manifestPath = path.join(repoRoot, "docs", "Set", "MuestrasImpresas", "manifest.json");
  const reportPath = path.join(repoRoot, "docs", "Set", "MuestrasImpresas", "manifest.cedible.json");

  _loadEnv(envPath);

  const projectId = _readString(process.env.GOOGLE_CLOUD_PROJECT) ||
    _readString(process.env.GCLOUD_PROJECT) ||
    "the-hero-67d93";
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId,
      storageBucket: "the-hero-67d93.firebasestorage.app",
    });
  }

  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const bucketName = _readString(manifest?.bucketName) || "the-hero-67d93.firebasestorage.app";
  const apiKey = _readString(process.env.SIMPLEAPI_API_KEY);
  if (!apiKey) throw new Error("Missing SIMPLEAPI_API_KEY in .env");

  const baseUrl = _readString(process.env.SIMPLEAPI_BASE_URL) || "https://api.simpleapi.cl";
  const pdfEndpoint = _resolveCediblePdfEndpoint(baseUrl, process.env.SIMPLEAPI_PDF_GENERATE_URL);
  const pdfInput = _buildPdfInput();
  const cedibleTypes = new Set([33, 34, 43, 46, 52]);

  let logoBuffer = null;
  const logoPath = _readString(process.env.SIMPLEAPI_LOGO_STORAGE_PATH);
  const assetsBucketName = _readString(process.env.SIMPLEAPI_ASSETS_BUCKET);
  if (logoPath) {
    try {
      const logoAsset = await _downloadPrivateAsset(logoPath, assetsBucketName);
      if (logoAsset.buffer.length > 0) logoBuffer = logoAsset.buffer;
    } catch (_) {}
  }

  const report = {
    generatedAt: new Date().toISOString(),
    sourceManifest: manifestPath,
    cedibleEndpoint: pdfEndpoint,
    totals: {
      eligible: 0,
      generated: 0,
      skipped: 0,
      errors: 0,
    },
    files: [],
  };

  const db = admin.firestore();

  for (const setEntry of manifest?.sets || []) {
    for (const fileEntry of setEntry?.files || []) {
      const documentId = _readString(fileEntry?.documentId);
      const storagePdfPath = _readString(fileEntry?.storagePath);
      const localPdfPath = _readString(fileEntry?.localPath);
      if (!documentId || !storagePdfPath || !localPdfPath) {
        report.totals.skipped += 1;
        report.files.push({
          documentId,
          status: "skipped",
          reason: "missing documentId/storagePath/localPath",
        });
        continue;
      }

      try {
        const docSnap = await db.collection("fiscal_documents").doc(documentId).get();
        const tipoDte = Math.round(Number(docSnap.data()?.tipoDte || 0));
        if (!cedibleTypes.has(tipoDte)) {
          report.totals.skipped += 1;
          report.files.push({
            documentId,
            tipoDte,
            status: "skipped",
            reason: "tipoDte does not require cedible",
          });
          continue;
        }

        report.totals.eligible += 1;
        const xmlStoragePath = _toXmlStoragePath(storagePdfPath);
        const [xmlBuffer] = await admin.storage().bucket(bucketName).file(xmlStoragePath).download();
        const pdfBuffer = await _buildCediblePdfFromXml({
          endpoint: pdfEndpoint,
          apiKey,
          pdfInput,
          xmlBuffer,
          logoBuffer,
        });

        const localCediblePath = _toLocalCediblePath(localPdfPath);
        fs.mkdirSync(path.dirname(localCediblePath), {recursive: true});
        fs.writeFileSync(localCediblePath, pdfBuffer);

        const storageCediblePath = _toStorageCediblePath(storagePdfPath);
        await admin.storage().bucket(bucketName).file(storageCediblePath).save(pdfBuffer, {
          resumable: false,
          contentType: "application/pdf",
          metadata: {cacheControl: "private, max-age=0, no-store"},
        });

        report.totals.generated += 1;
        report.files.push({
          documentId,
          tipoDte,
          status: "generated",
          sourceXml: xmlStoragePath,
          localCediblePath,
          storageCediblePath,
          bytes: pdfBuffer.length,
        });
      } catch (error) {
        report.totals.errors += 1;
        report.files.push({
          documentId,
          status: "error",
          reason: _readString(error?.message) || "unknown error",
        });
      }
    }
  }

  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2), "utf8");
  console.log(JSON.stringify({
    ok: report.totals.errors === 0,
    endpoint: pdfEndpoint,
    reportPath,
    totals: report.totals,
  }, null, 2));
}

main().catch((error) => {
  console.error("FATAL", error?.stack || String(error));
  process.exitCode = 1;
});
