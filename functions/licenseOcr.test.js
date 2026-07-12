/* eslint-disable require-jsdoc */

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  extractLicenseFieldsFromVision,
  normalizeLicenseClass,
  parseDateFromZone,
  parseRutFromZone,
} = require('./licenseOcr');

function visionWord(text, x, y) {
  const width = Math.max(24, text.length * 12);
  return {
    symbols: [...text].map((char) => ({text: char})),
    boundingBox: {
      vertices: [
        {x, y},
        {x: x + width, y},
        {x: x + width, y: y + 22},
        {x, y: y + 22},
      ],
    },
  };
}

function annotation(lines) {
  return {
    pages: [
      {
        width: 1000,
        height: 650,
        blocks: [
          {
            paragraphs: [
              {
                words: lines.flatMap((line, row) =>
                  line.map((text, col) => visionWord(text, 60 + col * 170, 80 + row * 48)),
                ),
              },
            ],
          },
        ],
      },
    ],
  };
}

test('corrects common OCR mistakes inside field zones', () => {
  assert.equal(parseRutFromZone('RUN 12.345.678-S'), '12345678-5');
  assert.equal(parseDateFromZone('VENCIMIENTO 31/12/2O30'), '2030-12-31T23:59:59.000Z');
  assert.equal(parseDateFromZone('NACIMIENTO 31/02/2030'), null);
  assert.equal(normalizeLicenseClass('CLASE 8'), 'B');
  assert.equal(normalizeLicenseClass('CLASE G'), null);
});

test('extracts license fields from Vision bounding boxes', () => {
  const fields = extractLicenseFieldsFromVision({
    frontAnnotation: annotation([
      ['RUN', '12.345.678-S'],
      ['APELLIDOS', 'PEREZ'],
      ['NOMBRES', 'JUAN'],
      ['FECHA', 'NACIMIENTO', '01/O1/1990'],
      ['VENCIMIENTO', '31/12/2O30'],
      ['CLASE', '8'],
    ]),
    backAnnotation: annotation([]),
  });

  assert.equal(fields.rut, '12345678-5');
  assert.equal(fields.fullName, 'JUAN PEREZ');
  assert.equal(fields.birthDate, '1990-01-01T23:59:59.000Z');
  assert.equal(fields.expiryDate, '2030-12-31T23:59:59.000Z');
  assert.equal(fields.licenseClass, 'B');
  assert.equal(fields.documentDetected, true);
  assert.deepEqual(fields.errorCodes, []);
  assert.ok(fields.sources.rut.bbox.left >= 0);
});

test('detects license when CLASE is not printed', () => {
  const fields = extractLicenseFieldsFromVision({
    frontAnnotation: annotation([
      ['LICENCIA', 'DE', 'CONDUCTOR'],
      ['RUN', '12.345.678-S'],
    ]),
    backAnnotation: annotation([]),
  });

  assert.equal(fields.documentDetected, true);
  assert.equal(fields.rut, '12345678-5');
  assert.equal(fields.licenseClass, null);
  assert.ok(fields.detectedLabels.includes('LICENCIA DE CONDUCTOR'));
  assert.deepEqual(fields.errorCodes, []);
});

test('detects sparse Chilean license with del conductor title', () => {
  const fields = extractLicenseFieldsFromVision({
    frontAnnotation: annotation([
      ['REPUBLICA', 'DE', 'CHILE'],
      ['LICENCIA', 'DEL', 'CONDUCTOR'],
      ['RUN', '12.345.678-S'],
    ]),
    backAnnotation: annotation([]),
  });

  assert.equal(fields.documentDetected, true);
  assert.equal(fields.rut, '12345678-5');
  assert.equal(fields.fullName, null);
  assert.equal(fields.licenseClass, null);
  assert.ok(fields.detectedLabels.includes('LICENCIA DE CONDUCTOR'));
  assert.ok(fields.detectedLabels.includes('REPUBLICA DE CHILE'));
  assert.deepEqual(fields.errorCodes, []);
});
