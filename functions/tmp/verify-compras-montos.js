process.env.FISCAL_BOOKS_TEST = '1';
const {
  _buildCertificationComprasTemplate,
  _buildLibroCvXml,
  _normalizeEntryTotalsForLibro,
} = require('../billing/generateFiscalBooks').__fiscalBooksTest;

const period = '2026-05';
const entries = _buildCertificationComprasTemplate({
  period,
  rutDoc: '11111111-1',
  rznSoc: 'Proveedor Test',
});
const normalized = entries.map((e) => _normalizeEntryTotalsForLibro(e, true));

const xml = _buildLibroCvXml({
  operation: 'COMPRA',
  period,
  rutEmisorLibro: '78330103-2',
  rutEnvia: '27948403-7',
  fechaResolucion: '2026-01-01',
  numeroResolucion: 0,
  folioNotificacion: 1,
  entries: normalized,
  bookId: 'ID_TEST',
  tipoEnvio: 'TOTAL',
  tipoLibro: 'ESPECIAL',
  certLibroCompras: true,
});

function parseDetalleBlocks(xmlText) {
  const blocks = [];
  const re = /<Detalle>([\s\S]*?)<\/Detalle>/g;
  let m;
  while ((m = re.exec(xmlText)) !== null) {
    const b = m[1];
    const tag = (name) => {
      const hit = b.match(new RegExp(`<${name}>(\\d+)</${name}>`));
      return hit ? parseInt(hit[1], 10) : 0;
    };
    const ivaNoRec = [...b.matchAll(/<MntIVANoRec>(\d+)<\/MntIVANoRec>/g)]
      .reduce((s, x) => s + parseInt(x[1], 10), 0);
    const otrosImp15 = [...b.matchAll(/<OtrosImp>[\s\S]*?<CodImp>15<\/CodImp>[\s\S]*?<MntImp>(\d+)<\/MntImp>/g)]
      .reduce((s, x) => s + parseInt(x[1], 10), 0);
    blocks.push({
      tpoDoc: tag('TpoDoc'),
      mntExe: tag('MntExe'),
      mntNeto: tag('MntNeto'),
      mntIva: tag('MntIVA'),
      ivaUsoComun: tag('IVAUsoComun'),
      ivaNoRec,
      otrosImp15,
      mntTotal: tag('MntTotal'),
      hasOtrosImp15: otrosImp15 > 0,
    });
  }
  return blocks;
}

function sumByTpo(blocks, tpo, field) {
  return blocks
    .filter((b) => b.tpoDoc === tpo)
    .reduce((s, b) => s + (b[field] || 0), 0);
}

const detalle = parseDetalleBlocks(xml);
const detalleCount = detalle.length;
const periodoLines = (xml.match(/<TotalesPeriodo>/g) || []).length;
const segmento = xml.includes('<ResumenSegmento>');

console.log('Detalle:', detalleCount, '(esperado 7)');
console.log('TotalesPeriodo:', periodoLines, '(esperado 4: T30, T33, T46, T60)');
console.log('ResumenSegmento presente:', segmento, '(debe ser false con TOTAL)');
console.assert(detalleCount === 7);
console.assert(periodoLines === 4);
console.assert(!segmento);

let sumTotDoc = 0;
let okAll = true;

for (const block of xml.matchAll(/<TotalesPeriodo>[\s\S]*?<\/TotalesPeriodo>/g)) {
  const b = block[0];
  const tpo = parseInt(b.match(/<TpoDoc>(\d+)<\/TpoDoc>/)?.[1] || '0', 10);
  const g = (k) => parseInt(b.match(new RegExp(`<${k}>(\\d+)<\\/${k}>`))?.[1] || '0', 10);
  const totDoc = g('TotDoc');
  sumTotDoc += totDoc;

  const checks = [
    ['TotMntExe', g('TotMntExe'), sumByTpo(detalle, tpo, 'mntExe')],
    ['TotMntNeto', g('TotMntNeto'), sumByTpo(detalle, tpo, 'mntNeto')],
    ['TotMntIVA', g('TotMntIVA'), sumByTpo(detalle, tpo, 'mntIva')],
    ['TotMntTotal', g('TotMntTotal'), sumByTpo(detalle, tpo, 'mntTotal')],
  ];
  const ivaUso = g('TotIVAUsoComun');
  if (ivaUso) checks.push(['TotIVAUsoComun', ivaUso, sumByTpo(detalle, tpo, 'ivaUsoComun')]);
  const totOtros15 = [...b.matchAll(/<TotOtrosImp>[\s\S]*?<CodImp>15<\/CodImp>[\s\S]*?<TotMntImp>(\d+)<\/TotMntImp>/g)]
    .reduce((s, m) => s + parseInt(m[1], 10), 0);
  if (totOtros15) {
    const sumOtros15 = detalle
      .filter((d) => d.tpoDoc === tpo)
      .reduce((s, d) => s + (d.otrosImp15 || 0), 0);
    checks.push(['TotOtrosImp15', totOtros15, sumOtros15]);
  }
  const ivaNoRec = [...b.matchAll(/<TotMntIVANoRec>(\d+)<\/TotMntIVANoRec>/g)]
    .reduce((s, x) => s + parseInt(x[1], 10), 0);
  if (ivaNoRec) checks.push(['TotMntIVANoRec', ivaNoRec, sumByTpo(detalle, tpo, 'ivaNoRec')]);

  const failed = checks.filter(([, res, det]) => res !== det);
  const ok = failed.length === 0;
  if (!ok) okAll = false;
  console.log(
    `T${tpo}: TotDoc=${totDoc} ${ok ? 'CUADRA con detalle' : 'NO CUADRA -> ' + failed.map((f) => `${f[0]} res=${f[1]} det=${f[2]}`).join(', ')}`,
  );
  if (tpo === 46) {
    const t46 = detalle.find((d) => d.tpoDoc === 46);
    const calcTotal = (t46?.mntNeto || 0) + (t46?.mntIva || 0) - (t46?.otrosImp15 || 0);
    const hasIvaRetTag = /<IVARetTotal>/.test(xml);
    console.log(
      `  T46 OtrosImp15=${t46?.otrosImp15} MntTotal=${t46?.mntTotal} ` +
      `calc(Neto+IVA-OtrosImp15)=${calcTotal} IVARetTotal tag=${hasIvaRetTag}`,
    );
    if (t46 && t46.mntTotal !== calcTotal) {
      okAll = false;
      console.log('  T46 MntTotal no cumple Neto+MntIVA-OtrosImp(15)');
    }
    if (!t46?.hasOtrosImp15 || hasIvaRetTag) {
      okAll = false;
      console.log('  T46 debe usar OtrosImp cod 15 y no IVARetTotal en detalle');
    }
  }
}

console.log('Suma TotDoc:', sumTotDoc, '(esperado 7)');
console.assert(sumTotDoc === 7);
if (!okAll) process.exit(1);
console.log('OK: resumen cuadra campo a campo con detalle (validación estilo SII).');
