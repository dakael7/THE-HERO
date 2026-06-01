const fs = require('fs');
const path = require('path');

function loadEnv(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx <= 0) continue;
    const key = trimmed.slice(0, idx).trim();
    const value = trimmed.slice(idx + 1);
    if (!(key in process.env)) process.env[key] = value;
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function resolveModesFromArgs(args) {
  const ordered = ['basic', 'guia', 'factura_compra', 'simulacion'];
  const allowed = new Set(['all', ...ordered]);
  const raw = (args[0] || 'simulacion').toString().trim().toLowerCase();

  // Shorthand por fraccion de 3 modos.
  // 1/3 => basic | 2/3 => basic,guia | 3/3 => basic,guia,factura_compra
  if (raw === '1/3') return ordered.slice(0, 1);
  if (raw === '2/3') return ordered.slice(0, 2);
  if (raw === '3/3') return ordered.slice(0, 3);

  // Lista explicita separada por coma: "basic,factura_compra"
  if (raw.includes(',')) {
    const parts = raw
      .split(',')
      .map((v) => v.trim())
      .filter(Boolean);
    if (!parts.length) {
      throw new Error('Modo invalido: lista vacia');
    }
    for (const mode of parts) {
      if (!allowed.has(mode) || mode === 'all') {
        throw new Error(`Modo invalido "${mode}" en lista. Usa: basic, guia, factura_compra, simulacion`);
      }
    }
    return [...new Set(parts)];
  }

  if (!allowed.has(raw)) {
    throw new Error(
      `Modo invalido "${raw}". Usa: all, basic, guia, factura_compra, simulacion o lista separada por comas`,
    );
  }
  if (raw === 'all') return ordered;
  return [raw];
}

function resolveEmitDateFromArgs(args) {
  const explicit = (args[1] || '').toString().trim();
  if (explicit) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(explicit)) {
      throw new Error(`Fecha invalida "${explicit}". Usa formato AAAA-MM-DD`);
    }
    return explicit;
  }
  return new Date().toISOString().slice(0, 10);
}

function buildRequest(mode, emitDate) {
  return {
    auth: {
      uid: 'local-runner',
      token: { admin: true, support: true, email: 'theherov1.0@gmail.com' },
    },
    data: {
      setMode: mode,
      emitDate,
      receptor: {
        rut: '60803000-K',
        razonSocial: 'Servicio de Impuestos Internos',
        giro: 'Administracion publica',
        direccion: 'Teatinos 120',
        comuna: 'Santiago',
        ciudad: 'Santiago',
        email: 'certificacion@sii.cl',
      },
      forceSiiSend: true,
    },
  };
}

async function runModeUntilOk(runSiiCertificationSet, mode, emitDate) {
  let attempt = 0;
  while (true) {
    attempt += 1;
    console.log(`[${new Date().toISOString()}] ATTEMPT mode=${mode} n=${attempt}`);
    try {
      const res = await runSiiCertificationSet.run(buildRequest(mode, emitDate));
      const env = res?.setEnvelope || {};
      console.log(`[${new Date().toISOString()}] OK mode=${mode} runId=${res?.runId || ''} trackId=${env.trackId || ''} status=${env.statusCode || ''} receivedAt=${env.receivedAt || ''}`);
      return {
        ok: true,
        mode,
        attempt,
        runId: res?.runId || null,
        trackId: env.trackId || null,
        receivedAt: env.receivedAt || null,
        statusCode: env.statusCode || null,
        setEnvelope: env,
        documents: res?.documents || [],
      };
    } catch (e) {
      console.log(`[${new Date().toISOString()}] RETRY mode=${mode} n=${attempt} error=${e?.message || e}`);
      await sleep(Math.min(45000, 4000 + attempt * 1500));
    }
  }
}

(async () => {
  const root = process.cwd();
  const outDir = path.join(root, '..', 'docs', 'Set');
  const progressPath = path.join(outDir, 'runSiiCertificationSet-bg-progress.json');
  const resultPath = path.join(outDir, 'runSiiCertificationSet-bg-results.json');

  process.env.GOOGLE_APPLICATION_CREDENTIALS = 'C:/Users/Luisg/AppData/Roaming/firebase/luisgpetit11_gmail_com_application_default_credentials.json';
  process.env.GCLOUD_PROJECT = 'the-hero-67d93';
  process.env.GOOGLE_CLOUD_PROJECT = 'the-hero-67d93';
  loadEnv(path.join(root, '.env'));

  const admin = require('firebase-admin');
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: 'the-hero-67d93',
      storageBucket: 'the-hero-67d93.firebasestorage.app',
    });
  }
  const { runSiiCertificationSet } = require('../billing/emitFiscalDocument');

  const cliArgs = process.argv.slice(2);
  const emitDate = resolveEmitDateFromArgs(cliArgs);
  const modes = resolveModesFromArgs(cliArgs);
  const all = [];

  for (const mode of modes) {
    const one = await runModeUntilOk(runSiiCertificationSet, mode, emitDate);
    all.push(one);
    fs.writeFileSync(progressPath, JSON.stringify(all, null, 2), 'utf8');
  }

  fs.writeFileSync(resultPath, JSON.stringify(all, null, 2), 'utf8');
  console.log(`[${new Date().toISOString()}] DONE resultFile=${resultPath}`);
})().catch((err) => {
  console.error('FATAL', err?.stack || String(err));
  process.exitCode = 1;
});
