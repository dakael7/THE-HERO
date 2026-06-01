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

function resolvePeriod(args) {
  const value = (args[0] || '').trim();
  if (!value) return new Date().toISOString().slice(0, 7);
  if (!/^\d{4}-\d{2}$/.test(value)) {
    throw new Error('Periodo invalido. Usa formato AAAA-MM');
  }
  return value;
}

function parseBoolFlag(args, name, fallback) {
  const flag = args.find((v) => v.startsWith(`--${name}=`));
  if (!flag) return fallback;
  const raw = flag.slice(name.length + 3).toLowerCase();
  return ['1', 'true', 'yes', 'si', 'on'].includes(raw);
}

function parseStringFlag(args, name, fallback = '') {
  const flag = args.find((v) => v.startsWith(`--${name}=`));
  if (!flag) return fallback;
  return flag.slice(name.length + 3).trim();
}

(async () => {
  const root = process.cwd();
  const outDir = path.join(root, '..', 'docs', 'Set');
  const args = process.argv.slice(2);
  const period = resolvePeriod(args);
  const includeVentas = parseBoolFlag(args, 'ventas', true);
  const includeCompras = parseBoolFlag(args, 'compras', true);
  const includeGuias = parseBoolFlag(args, 'guias', true);
  const onlyCertificationSource = parseBoolFlag(args, 'cert_only', true);
  const signXml = parseBoolFlag(args, 'sign', true);
  const tipoEnvio = parseStringFlag(args, 'tipo_envio', 'TOTAL').toUpperCase();
  const comprasTipoLibro = parseStringFlag(args, 'compras_tipo_libro', 'MENSUAL').toUpperCase();
  const comprasFolioNotif = parseStringFlag(args, 'compras_folio', '') || '';
  const comprasCodReemplazo = parseStringFlag(args, 'compras_cod_reemplazo', '') || '';
  const ventasRunIds = parseStringFlag(args, 'ventas_run_ids', '');
  const guiasRunIds = parseStringFlag(args, 'guias_run_ids', '');
  const ventasSetNumbers = parseStringFlag(args, 'ventas_set_numbers', '');
  const guiasSetNumbers = parseStringFlag(args, 'guias_set_numbers', '');
  const guiasTipoEnvio = parseStringFlag(args, 'guias_tipo_envio', '');
  const guiasFolioNotif = parseStringFlag(args, 'guias_folio_notif', '');
  const ventasTipoLibro = parseStringFlag(args, 'ventas_tipo_libro', '');
  const ventasFolioNotif = parseStringFlag(args, 'ventas_folio_notif', '');

  const fallbackAdcPath = 'C:/Users/Luisg/AppData/Roaming/firebase/luisgpetit11_gmail_com_application_default_credentials.json';
  const adcPath = process.env.GOOGLE_APPLICATION_CREDENTIALS || fallbackAdcPath;
  if (fs.existsSync(adcPath)) {
    process.env.GOOGLE_APPLICATION_CREDENTIALS = adcPath;
  } else {
    console.warn(`WARN: GOOGLE_APPLICATION_CREDENTIALS no encontrado en ${adcPath}. Se usara credencial por defecto del entorno.`);
  }
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

  const {generateFiscalBooksDraft} = require('../billing/generateFiscalBooks');
  const request = {
    auth: {
      uid: 'local-runner',
      token: {
        admin: true,
        support: true,
        email: 'theherov1.0@gmail.com',
      },
    },
    data: {
      period,
      includeVentas,
      includeCompras,
      includeGuias,
      onlyCertificationSource,
      signXml,
      tipoEnvio,
      comprasTipoLibro: comprasTipoLibro,
      comprasFolioNotificacion: comprasFolioNotif,
      comprasCodReemplazo: comprasCodReemplazo,
      ventasRunIds,
      guiasRunIds,
      ventasSetNumbers,
      guiasSetNumbers,
      ...(guiasTipoEnvio ? {guiasTipoEnvio} : {}),
      ...(guiasFolioNotif ? {folioNotificacionGuias: guiasFolioNotif} : {}),
      ...(ventasTipoLibro ? {ventasTipoLibro} : {}),
      ...(ventasFolioNotif ? {folioNotificacionVentas: ventasFolioNotif} : {}),
    },
  };

  const result = await generateFiscalBooksDraft.run(request);
  const outputPath = path.join(outDir, `books-draft-${period}.json`);
  fs.writeFileSync(outputPath, JSON.stringify(result, null, 2), 'utf8');
  console.log(JSON.stringify({
    ok: result?.ok === true,
    period,
    includeVentas,
    includeCompras,
    includeGuias,
    onlyCertificationSource,
    signXml,
    ventasRunIds,
    guiasRunIds,
    ventasSetNumbers,
    guiasSetNumbers,
    guiasTipoEnvio: guiasTipoEnvio || null,
    guiasFolioNotif: guiasFolioNotif || null,
    outputPath,
    files: result?.files || null,
  }, null, 2));
})().catch((error) => {
  console.error('FATAL', error?.stack || String(error));
  process.exitCode = 1;
});
