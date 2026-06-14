// Runner for LibreDTE variant: node tmp/run-sii-sequential-bg.js factura_compra
const path = require('path');
const modPath = path.resolve(__dirname, '..', 'functions', 'billing', 'emitFiscalDocument.libredte.js');
const mod = require(modPath);

async function main() {
  const arg = process.argv[2];
  if (!arg) {
    console.error('Usage: node tmp/run-sii-sequential-bg.js <documentType>');
    process.exit(2);
  }

  try {
    if (typeof mod.runLocalEmitFiscal !== 'function') {
      console.error('runLocalEmitFiscal not available in module');
      process.exit(3);
    }
    console.log('Starting local emission for', arg);
    const result = await mod.runLocalEmitFiscal(arg);
    console.log('Result:', JSON.stringify(result, null, 2));
  } catch (e) {
    console.error('Emission failed:', e && e.message ? e.message : e);
    process.exit(1);
  }
}

main();
