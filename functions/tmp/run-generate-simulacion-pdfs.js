const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

function _readString(value) {
  return typeof value === "string" ? value.trim() : "";
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

function _resolveNormalPdfEndpoint(baseUrl, explicitUrl) {
  const resolved = _resolveSimpleApiEndpoint(
    baseUrl,
    explicitUrl,
    "/api/v1/impresion/pdf/carta/v2",
  ).replace(/\/+$/, "");
  return resolved.replace(/\/cedible$/i, "");
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

function _extractPdfBuffer(contentType, bodyBuffer, bodyText) {
  const normalizedContentType = _readString(contentType).toLowerCase();
  if (normalizedContentType.includes("application/pdf")) {
    return bodyBuffer;
  }
  if (Buffer.isBuffer(bodyBuffer) && bodyBuffer.length >= 4) {
    const signature = bodyBuffer.subarray(0, 4).toString("utf8");
    if (signature === "%PDF") return bodyBuffer;
  }
  try {
    const json = JSON.parse(_readString(bodyText));
    const candidates = [
      json?.pdf,
      json?.archivoPdf,
      json?.data?.pdf,
      json?.data?.archivoPdf,
      json?.result?.pdf,
    ];
    for (const raw of candidates) {
      if (typeof raw !== "string" || !raw.trim()) continue;
      const candidate = Buffer.from(raw, "base64");
      if (candidate.length >= 4 && candidate.subarray(0, 4).toString("utf8") === "%PDF") {
        return candidate;
      }
    }
  } catch (_) {}
  return null;
}

async function _downloadPrivateAsset(storagePath, fallbackBucketName = "") {
  const raw = _readString(storagePath);
  if (!raw) throw new Error("Missing storage path");

  let bucketName = _readString(fallbackBucketName);
  let objectPath = raw.replace(/^\/+/, "");
  if (raw.startsWith("gs://")) {
    const tail = raw.slice(5);
    const slashIndex = tail.indexOf("/");
    if (slashIndex <= 0 || slashIndex === tail.length - 1) {
      throw new Error(`Invalid gs path: ${raw}`);
    }
    bucketName = tail.slice(0, slashIndex);
    objectPath = tail.slice(slashIndex + 1);
  }

  const bucket = bucketName ? admin.storage().bucket(bucketName) : admin.storage().bucket();
  const [buffer] = await bucket.file(objectPath).download();
  return {
    bucketName: bucket.name,
    objectPath,
    buffer,
  };
}

async function _fetchPdfFromSimpleApi({
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
    throw new Error(`SimpleAPI PDF failed (${response.status}): ${bodyText.slice(0, 350)}`);
  }

  const pdfBuffer = _extractPdfBuffer(response.headers.get("content-type"), bodyBuffer, bodyText);
  if (!pdfBuffer) {
    throw new Error("SimpleAPI response did not include a valid PDF payload");
  }
  return pdfBuffer;
}

async function _tryDownloadStoragePdf(bucket, objectPath) {
  try {
    const [buffer] = await bucket.file(objectPath).download();
    if (buffer.length >= 4 && buffer.subarray(0, 4).toString("utf8") === "%PDF") {
      return buffer;
    }
    return null;
  } catch (_) {
    return null;
  }
}

async function main() {
  const root = process.cwd();
  const repoRoot = path.resolve(root, "..");
  const envPath = path.join(root, ".env");
  const resultsPath = path.join(repoRoot, "docs", "Set", "runSiiSimulation-results.json");
  const outBase = path.join(repoRoot, "docs", "Set", "Simulacion");
  const outPdfDir = path.join(outBase, "SET_SIMULACION");
  const outCedDir = path.join(outBase, "CEDIBLES", "SET_SIMULACION");
  const manifestPath = path.join(outBase, "manifest.json");
  const cedibleReportPath = path.join(outBase, "manifest.cedible.json");

  _loadEnv(envPath);

  const fallbackAdcPath = "C:/Users/Luisg/AppData/Roaming/firebase/luisgpetit11_gmail_com_application_default_credentials.json";
  const adcPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || fallbackAdcPath;
  if (fs.existsSync(adcPath)) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = adcPath;
  }
  process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || "the-hero-67d93";
  process.env.GOOGLE_CLOUD_PROJECT = process.env.GOOGLE_CLOUD_PROJECT || "the-hero-67d93";

  const projectId = _readString(process.env.GOOGLE_CLOUD_PROJECT) ||
    _readString(process.env.GCLOUD_PROJECT) ||
    "the-hero-67d93";
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId,
      storageBucket: "the-hero-67d93.firebasestorage.app",
    });
  }

  const runs = JSON.parse(fs.readFileSync(resultsPath, "utf8"));
  const run = Array.isArray(runs) && runs.length ? runs[0] : null;
  if (!run || !Array.isArray(run.documents) || !run.documents.length) {
    throw new Error("No hay documentos de simulacion en runSiiSimulation-results.json");
  }

  const apiKey = _readString(process.env.SIMPLEAPI_API_KEY);
  if (!apiKey) throw new Error("Missing SIMPLEAPI_API_KEY in .env");

  const baseUrl = _readString(process.env.SIMPLEAPI_BASE_URL) || "https://api.simpleapi.cl";
  const normalEndpoint = _resolveNormalPdfEndpoint(baseUrl, process.env.SIMPLEAPI_PDF_GENERATE_URL);
  const cedibleEndpoint = _resolveCediblePdfEndpoint(baseUrl, process.env.SIMPLEAPI_PDF_GENERATE_URL);
  const pdfInput = _buildPdfInput();

  const bucketName = "the-hero-67d93.firebasestorage.app";
  const bucket = admin.storage().bucket(bucketName);
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

  fs.mkdirSync(outPdfDir, {recursive: true});
  fs.mkdirSync(outCedDir, {recursive: true});

  const manifest = {
    generatedAt: new Date().toISOString(),
    bucketName,
    outputsDir: outBase,
    sourceRunFile: resultsPath,
    sets: [
      {
        name: "SET_SIMULACION",
        runId: _readString(run.runId),
        trackId: _readString(run.trackId),
        files: [],
      },
    ],
    summary: {
      downloadedOrGenerated: 0,
      cediblesGenerated: 0,
      skippedCedibles: 0,
      errors: 0,
    },
  };

  const cedibleReport = {
    generatedAt: new Date().toISOString(),
    sourceManifest: manifestPath,
    normalEndpoint,
    cedibleEndpoint,
    totals: {
      eligible: 0,
      generated: 0,
      skipped: 0,
      errors: 0,
    },
    files: [],
  };

  for (const doc of run.documents) {
    const documentId = _readString(doc.documentId);
    const caseCode = _readString(doc.caseCode);
    const tipoDte = Math.round(Number(doc.tipoDte || 0));
    if (!documentId || !caseCode || !tipoDte) continue;

    const prefix = `fiscal_documents/${documentId}`;
    const xmlStoragePath = `${prefix}/dte.xml`;
    const normalStoragePath = `${prefix}/document.pdf`;
    const cedStoragePath = `${prefix}/document_cedible.pdf`;
    const localName = `${caseCode}_${documentId}.pdf`;
    const localPdfPath = path.join(outPdfDir, localName);
    const localCedPath = path.join(outCedDir, `${caseCode}_${documentId}_CEDIBLE.pdf`);

    const setFileEntry = {
      caseCode,
      documentId,
      tipoDte,
      storagePath: normalStoragePath,
      localPath: localPdfPath,
      status: "pending",
      size: 0,
    };

    try {
      let normalPdf = await _tryDownloadStoragePdf(bucket, normalStoragePath);
      if (!normalPdf) {
        const [xmlBuffer] = await bucket.file(xmlStoragePath).download();
        normalPdf = await _fetchPdfFromSimpleApi({
          endpoint: normalEndpoint,
          apiKey,
          pdfInput,
          xmlBuffer,
          logoBuffer,
        });
        await bucket.file(normalStoragePath).save(normalPdf, {
          resumable: false,
          contentType: "application/pdf",
          metadata: {cacheControl: "private, max-age=0, no-store"},
        });
      }

      fs.writeFileSync(localPdfPath, normalPdf);
      setFileEntry.status = "downloaded";
      setFileEntry.size = normalPdf.length;
      manifest.summary.downloadedOrGenerated += 1;

      if (cedibleTypes.has(tipoDte)) {
        cedibleReport.totals.eligible += 1;
        let cediblePdf = await _tryDownloadStoragePdf(bucket, cedStoragePath);
        if (!cediblePdf) {
          const [xmlBuffer] = await bucket.file(xmlStoragePath).download();
          cediblePdf = await _fetchPdfFromSimpleApi({
            endpoint: cedibleEndpoint,
            apiKey,
            pdfInput,
            xmlBuffer,
            logoBuffer,
          });
          await bucket.file(cedStoragePath).save(cediblePdf, {
            resumable: false,
            contentType: "application/pdf",
            metadata: {cacheControl: "private, max-age=0, no-store"},
          });
        }

        fs.writeFileSync(localCedPath, cediblePdf);
        manifest.summary.cediblesGenerated += 1;
        cedibleReport.totals.generated += 1;
        cedibleReport.files.push({
          documentId,
          caseCode,
          tipoDte,
          status: "generated",
          sourceXml: xmlStoragePath,
          localCediblePath: localCedPath,
          storageCediblePath: cedStoragePath,
          bytes: cediblePdf.length,
        });
      } else {
        manifest.summary.skippedCedibles += 1;
        cedibleReport.totals.skipped += 1;
        cedibleReport.files.push({
          documentId,
          caseCode,
          tipoDte,
          status: "skipped",
          reason: "tipoDte does not require cedible",
        });
      }
    } catch (error) {
      const reason = _readString(error?.message) || "unknown error";
      setFileEntry.status = "error";
      setFileEntry.error = reason;
      manifest.summary.errors += 1;
      cedibleReport.totals.errors += 1;
      cedibleReport.files.push({
        documentId,
        caseCode,
        tipoDte,
        status: "error",
        reason,
      });
    }

    manifest.sets[0].files.push(setFileEntry);
  }

  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2), "utf8");
  fs.writeFileSync(cedibleReportPath, JSON.stringify(cedibleReport, null, 2), "utf8");

  console.log(JSON.stringify({
    ok: manifest.summary.errors === 0 && cedibleReport.totals.errors === 0,
    manifestPath,
    cedibleReportPath,
    summary: manifest.summary,
    cedibleTotals: cedibleReport.totals,
  }, null, 2));
}

main().catch((error) => {
  console.error("FATAL", error?.stack || String(error));
  process.exitCode = 1;
});
