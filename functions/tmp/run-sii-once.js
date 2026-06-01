const fs = require("fs");
const path = require("path");

function loadEnv(filePath) {
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

function parseArgs(args) {
  const mode = (args[0] || "basic").toString().trim().toLowerCase();
  const emitDate = (args[1] || new Date().toISOString().slice(0, 10)).toString().trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(emitDate)) {
    throw new Error(`Fecha invalida "${emitDate}". Usa AAAA-MM-DD`);
  }
  const allowed = new Set(["basic", "guia", "factura_compra", "simulacion", "all"]);
  if (!allowed.has(mode)) {
    throw new Error(`Modo invalido "${mode}". Usa: basic, guia, factura_compra, simulacion o all`);
  }
  return {mode, emitDate};
}

async function main() {
  const root = process.cwd();
  const repoRoot = path.resolve(root, "..");
  const outDir = path.join(repoRoot, "docs", "Set");
  loadEnv(path.join(root, ".env"));

  const fallbackAdcPath = "C:/Users/Luisg/AppData/Roaming/firebase/luisgpetit11_gmail_com_application_default_credentials.json";
  const adcPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || fallbackAdcPath;
  if (fs.existsSync(adcPath)) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = adcPath;
  }
  process.env.GCLOUD_PROJECT = "the-hero-67d93";
  process.env.GOOGLE_CLOUD_PROJECT = "the-hero-67d93";

  const {mode, emitDate} = parseArgs(process.argv.slice(2));
  const admin = require("firebase-admin");
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: "the-hero-67d93",
      storageBucket: "the-hero-67d93.firebasestorage.app",
    });
  }

  const {runSiiCertificationSet} = require("../billing/emitFiscalDocument");
  const request = {
    auth: {
      uid: "local-runner",
      token: {
        admin: true,
        support: true,
        email: "theherov1.0@gmail.com",
      },
    },
    data: {
      setMode: mode,
      emitDate,
      receptor: {
        rut: "60803000-K",
        razonSocial: "Servicio de Impuestos Internos",
        giro: "Administracion publica",
        direccion: "Teatinos 120",
        comuna: "Santiago",
        ciudad: "Santiago",
        email: "certificacion@sii.cl",
      },
      forceSiiSend: true,
    },
  };

  const startedAt = new Date().toISOString();
  try {
    const res = await runSiiCertificationSet.run(request);
    const payload = {
      ok: true,
      mode,
      emitDate,
      startedAt,
      finishedAt: new Date().toISOString(),
      runId: res?.runId || null,
      documents: res?.documents || [],
      setEnvelope: res?.setEnvelope || null,
    };
    const outPath = path.join(outDir, `runSiiOnce-${mode}-${Date.now()}.json`);
    try {
      fs.writeFileSync(outPath, JSON.stringify(payload, null, 2), "utf8");
      console.log(JSON.stringify({...payload, outPath}, null, 2));
    } catch (persistError) {
      console.log(JSON.stringify({
        ...payload,
        outPath,
        warning: `No se pudo guardar archivo local: ${String(persistError?.message || persistError)}`,
      }, null, 2));
    }
  } catch (error) {
    const payload = {
      ok: false,
      mode,
      emitDate,
      startedAt,
      finishedAt: new Date().toISOString(),
      error: String(error?.message || error),
      stack: String(error?.stack || ""),
    };
    const outPath = path.join(outDir, `runSiiOnce-${mode}-${Date.now()}-ERROR.json`);
    try {
      fs.writeFileSync(outPath, JSON.stringify(payload, null, 2), "utf8");
      console.error(JSON.stringify({...payload, outPath}, null, 2));
    } catch (persistError) {
      console.error(JSON.stringify({
        ...payload,
        outPath,
        warning: `No se pudo guardar archivo local: ${String(persistError?.message || persistError)}`,
      }, null, 2));
    }
    process.exitCode = 1;
  }
}

main();
