/* eslint-disable require-jsdoc, new-cap */

const sharp = require('sharp');
const cvModule = require('@techstark/opencv-js');

const MIN_OCR_WIDTH = 2000;
const ALLOWED_LICENSE_CLASSES = new Set([
  'A1',
  'A2',
  'A3',
  'A4',
  'A5',
  'B',
  'C',
  'D',
  'E',
  'F',
]);

let openCvPromise = null;

function getOpenCv() {
  if (!openCvPromise) openCvPromise = Promise.resolve(cvModule);
  return openCvPromise;
}

function stripDiacritics(input) {
  return String(input || '')
      .normalize('NFD')
      .replace(/\p{Diacritic}/gu, '');
}

function normalizeText(input) {
  return stripDiacritics(input)
      .toUpperCase()
      .replace(/[^A-Z0-9K/.\-\s]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
}

function correctDigitOcr(input) {
  return String(input || '')
      .toUpperCase()
      .replace(/[OQ]/g, '0')
      .replace(/[IL|]/g, '1')
      .replace(/B/g, '8')
      .replace(/S/g, '5');
}

function normalizeRut(raw) {
  if (!raw) return null;
  const cleaned = correctDigitOcr(raw)
      .replace(/\./g, '')
      .replace(/\s+/g, '')
      .replace(/[^0-9K-]/g, '');

  const withDash = cleaned.includes('-') ?
    cleaned :
    cleaned.length >= 2 ?
      `${cleaned.slice(0, -1)}-${cleaned.slice(-1)}` :
      cleaned;

  const match = withDash.match(/^(\d{7,8})-([0-9K])$/);
  if (!match) return null;
  return `${match[1]}-${match[2]}`;
}

function computeRutDv(body) {
  let sum = 0;
  let multiplier = 2;

  for (let i = body.length - 1; i >= 0; i -= 1) {
    sum += Number(body[i]) * multiplier;
    multiplier = multiplier === 7 ? 2 : multiplier + 1;
  }

  const remainder = 11 - (sum % 11);
  if (remainder === 11) return '0';
  if (remainder === 10) return 'K';
  return String(remainder);
}

function isValidRutDv(rut) {
  const normalized = normalizeRut(rut);
  if (!normalized) return false;
  const [body, dv] = normalized.split('-');
  return computeRutDv(body) === dv;
}

function parseRutFromZone(text) {
  const normalized = normalizeText(text).replace(/\b(RUN|RUT)\b/g, ' ');
  const matches = normalized.match(/[0-9OQIL|BS.\-\s]{7,16}[0-9KOSBIL|]/g) || [];

  for (const match of matches) {
    const rut = normalizeRut(match);
    if (rut && isValidRutDv(rut)) return rut;
  }

  return null;
}

function parseDateFromZone(text) {
  const corrected = correctDigitOcr(normalizeText(text));
  const match = corrected.match(/\b(\d{1,2})[/.\-\s](\d{1,2})[/.\-\s](\d{4})\b/);
  if (!match) return null;

  const dd = Number(match[1]);
  const mm = Number(match[2]);
  const yyyy = Number(match[3]);
  if (yyyy < 1900 || yyyy > 2100 || mm < 1 || mm > 12 || dd < 1) return null;

  const date = new Date(Date.UTC(yyyy, mm - 1, dd, 23, 59, 59));
  if (
    date.getUTCFullYear() !== yyyy ||
    date.getUTCMonth() !== mm - 1 ||
    date.getUTCDate() !== dd
  ) {
    return null;
  }

  return date.toISOString();
}

function normalizeLicenseClass(raw) {
  if (!raw) return null;
  const normalized = normalizeText(raw).replace(/\b8\b/g, 'B');
  const match = normalized.match(/\b(A\s*[1-5]|[BCDEF])\b/);
  if (!match) return null;
  const licenseClass = match[1].replace(/\s+/g, '');
  return ALLOWED_LICENSE_CLASSES.has(licenseClass) ? licenseClass : null;
}

function rectFromVertices(vertices = []) {
  const xs = vertices.map((v) => v.x || 0);
  const ys = vertices.map((v) => v.y || 0);
  const left = Math.min(...xs);
  const top = Math.min(...ys);
  const right = Math.max(...xs);
  const bottom = Math.max(...ys);

  return {
    left,
    top,
    right,
    bottom,
    width: right - left,
    height: bottom - top,
    centerX: (left + right) / 2,
    centerY: (top + bottom) / 2,
  };
}

function mergeRects(rects) {
  return rectFromVertices([
    {x: Math.min(...rects.map((r) => r.left)), y: Math.min(...rects.map((r) => r.top))},
    {x: Math.max(...rects.map((r) => r.right)), y: Math.max(...rects.map((r) => r.bottom))},
  ]);
}

function wordText(word) {
  return (word.symbols || []).map((symbol) => symbol.text || '').join('');
}

function wordsFromAnnotation(annotation, side) {
  const words = [];
  const pages = annotation?.pages || [];

  pages.forEach((page, pageIndex) => {
    (page.blocks || []).forEach((block) => {
      (block.paragraphs || []).forEach((paragraph) => {
        (paragraph.words || []).forEach((word) => {
          const text = wordText(word);
          const vertices = word.boundingBox?.vertices || [];
          if (!text || vertices.length === 0) return;
          words.push({
            text,
            side,
            pageIndex,
            pageWidth: page.width || null,
            pageHeight: page.height || null,
            rect: rectFromVertices(vertices),
          });
        });
      });
    });
  });

  return words;
}

function buildLinesFromWords(words) {
  const sorted = [...words].sort((a, b) => {
    if (a.side !== b.side) return a.side.localeCompare(b.side);
    if (a.pageIndex !== b.pageIndex) return a.pageIndex - b.pageIndex;
    if (Math.abs(a.rect.centerY - b.rect.centerY) > 8) {
      return a.rect.centerY - b.rect.centerY;
    }
    return a.rect.left - b.rect.left;
  });

  const lines = [];
  for (const word of sorted) {
    const line = lines.find(
        (candidate) =>
          candidate.side === word.side &&
        candidate.pageIndex === word.pageIndex &&
        Math.abs(candidate.rect.centerY - word.rect.centerY) <=
          Math.max(12, candidate.rect.height * 0.65, word.rect.height * 0.65),
    );

    if (!line) {
      lines.push({
        side: word.side,
        pageIndex: word.pageIndex,
        words: [word],
        rect: word.rect,
      });
      continue;
    }

    line.words.push(word);
    line.rect = mergeRects(line.words.map((item) => item.rect));
  }

  return lines
      .map((line) => {
        const sortedWords = [...line.words].sort((a, b) => a.rect.left - b.rect.left);
        const text = sortedWords.map((word) => word.text).join(' ');
        return {
          side: line.side,
          pageIndex: line.pageIndex,
          text,
          normalized: normalizeText(text),
          rect: line.rect,
        };
      })
      .sort((a, b) => {
        if (a.side !== b.side) return a.side.localeCompare(b.side);
        if (a.pageIndex !== b.pageIndex) return a.pageIndex - b.pageIndex;
        if (Math.abs(a.rect.top - b.rect.top) > 8) return a.rect.top - b.rect.top;
        return a.rect.left - b.rect.left;
      });
}

function collectZones(lines, labelRegex, maxBelow = 2) {
  const zones = [];

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (!labelRegex.test(line.normalized)) continue;

    const parts = [line.normalized.replace(labelRegex, ' ').trim()].filter(Boolean);
    const boxes = [line.rect];

    for (let j = i + 1; j < lines.length && parts.length <= maxBelow; j += 1) {
      const next = lines[j];
      if (next.side !== line.side || next.pageIndex !== line.pageIndex) break;
      if (next.rect.top - line.rect.bottom > Math.max(90, line.rect.height * 3)) break;
      if (FIELD_LABEL_RE.test(next.normalized)) break;
      parts.push(next.normalized);
      boxes.push(next.rect);
    }

    zones.push({
      text: parts.join(' '),
      side: line.side,
      bbox: mergeRects(boxes),
    });
  }

  return zones;
}

function firstParsed(zones, parser) {
  for (const zone of zones) {
    const value = parser(zone.text);
    if (value) return {value, zone};
  }
  return {value: null, zone: null};
}

function cleanNameZone(text, labelRegex) {
  const cleaned = normalizeText(text)
      .replace(labelRegex, ' ')
      .replace(FIELD_LABEL_RE, ' ')
      .replace(/[^A-Z\s]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  return cleaned.length >= 2 ? cleaned : null;
}

function extractName(lines) {
  const firstName = firstParsed(collectZones(lines, /\bNOMBRES?\b/), (text) =>
    cleanNameZone(text, /\bNOMBRES?\b/),
  );
  const lastName = firstParsed(collectZones(lines, /\bAPELLIDOS?\b/), (text) =>
    cleanNameZone(text, /\bAPELLIDOS?\b/),
  );

  const parts = [firstName.value, lastName.value].filter(Boolean);
  if (parts.length === 0) return {value: null, zones: []};

  return {
    value: parts.join(' '),
    zones: [firstName.zone, lastName.zone].filter(Boolean),
  };
}

const FIELD_LABEL_RE =
  /\b(LICENCIA\s+DE(?:L)?\s+CONDUCTOR|REPUBLICA\s+DE\s+CHILE|RUN|RUT|NOMBRES?|APELLIDOS?|NACIMIENTO|NAC|VENCIMIENTO|VENC|CADUCIDAD|CLASE|EMISION)\b/; // eslint-disable-line max-len

function detectLicenseLabels(lines) {
  const allText = lines.map((line) => line.normalized).join(' ');
  const labels = new Set(
      lines
          .flatMap((line) => line.normalized.match(FIELD_LABEL_RE) || [])
          .map((label) =>
            /^LICENCIA\s+DEL?\s+CONDUCTOR$/.test(label) ?
              'LICENCIA DE CONDUCTOR' :
              label,
          )
          .map((label) => label.toUpperCase()),
  );

  if (/\bLICENCIA\s+DE(?:L)?\s+CONDUCTOR\b/.test(allText)) {
    labels.add('LICENCIA DE CONDUCTOR');
  }
  if (/\bLICENCIA\b[\sA-Z]{0,30}\bCONDUCIR\b/.test(allText)) {
    labels.add('LICENCIA DE CONDUCIR');
  }
  if (/\bREPUBLICA\s+DE\s+CHILE\b/.test(allText)) {
    labels.add('REPUBLICA DE CHILE');
  }

  return Array.from(labels);
}

function zoneSource(zone) {
  if (!zone) return null;
  return {
    side: zone.side,
    bbox: {
      left: Math.round(zone.bbox.left),
      top: Math.round(zone.bbox.top),
      right: Math.round(zone.bbox.right),
      bottom: Math.round(zone.bbox.bottom),
    },
  };
}

function extractLicenseFieldsFromVision({frontAnnotation, backAnnotation}) {
  const lines = buildLinesFromWords([
    ...wordsFromAnnotation(frontAnnotation, 'front'),
    ...wordsFromAnnotation(backAnnotation, 'back'),
  ]);

  const detectedLabels = detectLicenseLabels(lines);

  const rut = firstParsed(collectZones(lines, /\b(RUN|RUT)\b/), parseRutFromZone);
  const birthDate = firstParsed(
      collectZones(lines, /\b(NACIMIENTO|NAC)\b/),
      parseDateFromZone,
  );
  const expiryDate = firstParsed(
      collectZones(lines, /\b(VENCIMIENTO|VENC|CADUCIDAD)\b/),
      parseDateFromZone,
  );
  const licenseClass = firstParsed(
      collectZones(lines, /\bCLASE\b/, 1),
      normalizeLicenseClass,
  );
  const fullName = extractName(lines);

  const errorCodes = [];
  if (collectZones(lines, /\b(RUN|RUT)\b/).length > 0 && !rut.value) {
    errorCodes.push('rut_field_invalid');
  }
  if (collectZones(lines, /\b(NACIMIENTO|NAC)\b/).length > 0 && !birthDate.value) {
    errorCodes.push('birth_date_field_invalid');
  }
  if (collectZones(lines, /\b(VENCIMIENTO|VENC|CADUCIDAD)\b/).length > 0 && !expiryDate.value) {
    errorCodes.push('expiry_date_field_invalid');
  }
  if (collectZones(lines, /\bCLASE\b/).length > 0 && !licenseClass.value) {
    errorCodes.push('license_class_field_invalid');
  }

  const hasLicenseTitle =
    detectedLabels.includes('LICENCIA DE CONDUCTOR') ||
    detectedLabels.includes('LICENCIA DE CONDUCIR');
  const hasRutLabel =
    detectedLabels.includes('RUN') || detectedLabels.includes('RUT');

  return {
    rut: rut.value,
    fullName: fullName.value,
    birthDate: birthDate.value,
    expiryDate: expiryDate.value,
    licenseClass: licenseClass.value,
    detectedLabels,
    documentDetected:
      (hasLicenseTitle && hasRutLabel) ||
      (lines.length >= 3 && detectedLabels.length >= 2),
    errorCodes,
    sources: {
      rut: zoneSource(rut.zone),
      fullName: fullName.zones.map(zoneSource),
      birthDate: zoneSource(birthDate.zone),
      expiryDate: zoneSource(expiryDate.zone),
      licenseClass: zoneSource(licenseClass.zone),
    },
  };
}

async function enhanceForOcr(buffer) {
  const metadata = await sharp(buffer, {failOn: 'none'}).rotate().metadata();
  const width = metadata.width || 0;
  let pipeline = sharp(buffer, {failOn: 'none'}).rotate();
  if (width > 0 && width < MIN_OCR_WIDTH) {
    pipeline = pipeline.resize({width: MIN_OCR_WIDTH, kernel: 'lanczos3'});
  }

  const output = await pipeline
      .grayscale()
      .normalize()
      .modulate({brightness: 1.06})
      .median(1)
      .sharpen({sigma: 1.15})
      .png()
      .toBuffer();
  const outputMetadata = await sharp(output).metadata();

  return {
    buffer: output,
    width: outputMetadata.width || null,
    height: outputMetadata.height || null,
    enlargedToMinWidth: width > 0 && width < MIN_OCR_WIDTH,
  };
}

function distance(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function orderCorners(points) {
  const topLeft = points.reduce((best, point) =>
    point.x + point.y < best.x + best.y ? point : best,
  );
  const bottomRight = points.reduce((best, point) =>
    point.x + point.y > best.x + best.y ? point : best,
  );
  const topRight = points.reduce((best, point) =>
    point.x - point.y > best.x - best.y ? point : best,
  );
  const bottomLeft = points.reduce((best, point) =>
    point.x - point.y < best.x - best.y ? point : best,
  );
  return [topLeft, topRight, bottomRight, bottomLeft];
}

async function correctPerspectiveWithOpenCv(buffer) {
  const cv = await getOpenCv();
  const {data, info} = await sharp(buffer)
      .ensureAlpha()
      .raw()
      .toBuffer({resolveWithObject: true});

  const src = cv.matFromImageData({
    data: new Uint8ClampedArray(data),
    width: info.width,
    height: info.height,
  });
  const gray = new cv.Mat();
  const blurred = new cv.Mat();
  const edges = new cv.Mat();
  const contours = new cv.MatVector();
  const hierarchy = new cv.Mat();
  let warped = null;
  let transform = null;
  let sourcePoints = null;
  let destinationPoints = null;

  try {
    cv.cvtColor(src, gray, cv.COLOR_RGBA2GRAY);
    cv.GaussianBlur(gray, blurred, new cv.Size(5, 5), 0);
    cv.Canny(blurred, edges, 50, 150);
    cv.findContours(edges, contours, hierarchy, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

    let bestPoints = null;
    let bestArea = 0;
    const imageArea = info.width * info.height;

    for (let i = 0; i < contours.size(); i += 1) {
      const contour = contours.get(i);
      const approx = new cv.Mat();
      try {
        const perimeter = cv.arcLength(contour, true);
        cv.approxPolyDP(contour, approx, 0.02 * perimeter, true);
        const area = Math.abs(cv.contourArea(contour));
        if (approx.rows === 4 && area > bestArea && area > imageArea * 0.12) {
          const points = [];
          for (let p = 0; p < approx.data32S.length; p += 2) {
            points.push({x: approx.data32S[p], y: approx.data32S[p + 1]});
          }
          bestPoints = points;
          bestArea = area;
        }
      } finally {
        approx.delete();
        contour.delete();
      }
    }

    if (!bestPoints) return {buffer, corrected: false};

    const [tl, tr, br, bl] = orderCorners(bestPoints);
    const targetWidth = Math.max(distance(br, bl), distance(tr, tl));
    const targetHeight = Math.max(distance(tr, br), distance(tl, bl));
    if (targetWidth < 400 || targetHeight < 250) return {buffer, corrected: false};

    sourcePoints = cv.matFromArray(4, 1, cv.CV_32FC2, [
      tl.x,
      tl.y,
      tr.x,
      tr.y,
      br.x,
      br.y,
      bl.x,
      bl.y,
    ]);
    destinationPoints = cv.matFromArray(4, 1, cv.CV_32FC2, [
      0,
      0,
      targetWidth - 1,
      0,
      targetWidth - 1,
      targetHeight - 1,
      0,
      targetHeight - 1,
    ]);
    transform = cv.getPerspectiveTransform(sourcePoints, destinationPoints);
    warped = new cv.Mat();
    cv.warpPerspective(
        src,
        warped,
        transform,
        new cv.Size(Math.round(targetWidth), Math.round(targetHeight)),
        cv.INTER_LINEAR,
        cv.BORDER_CONSTANT,
        new cv.Scalar(),
    );

    const warpedBuffer = await sharp(Buffer.from(warped.data), {
      raw: {
        width: warped.cols,
        height: warped.rows,
        channels: 4,
      },
    })
        .png()
        .toBuffer();

    return {buffer: warpedBuffer, corrected: true};
  } finally {
    src.delete();
    gray.delete();
    blurred.delete();
    edges.delete();
    contours.delete();
    hierarchy.delete();
    if (warped) warped.delete();
    if (transform) transform.delete();
    if (sourcePoints) sourcePoints.delete();
    if (destinationPoints) destinationPoints.delete();
  }
}

async function preprocessLicenseImageForOcr(buffer) {
  const enhanced = await enhanceForOcr(buffer);
  const perspective = await correctPerspectiveWithOpenCv(enhanced.buffer);
  const finalImage = perspective.corrected ?
    await enhanceForOcr(perspective.buffer) :
    enhanced;

  return {
    buffer: finalImage.buffer,
    metadata: {
      width: finalImage.width,
      height: finalImage.height,
      minWidth: MIN_OCR_WIDTH,
      enlargedToMinWidth:
        enhanced.enlargedToMinWidth || Boolean(finalImage.enlargedToMinWidth),
      perspectiveCorrected: perspective.corrected,
      contrastEnhanced: true,
      denoised: true,
      sharpened: true,
      brightnessCorrected: true,
    },
  };
}

async function runVisionDocumentOcrForBuffer({visionClient, imageBuffer}) {
  const [result] = await visionClient.annotateImage({
    image: {content: imageBuffer.toString('base64')},
    features: [{type: 'DOCUMENT_TEXT_DETECTION'}],
    imageContext: {languageHints: ['es']},
  });
  return result?.fullTextAnnotation || {};
}

module.exports = {
  ALLOWED_LICENSE_CLASSES,
  MIN_OCR_WIDTH,
  extractLicenseFieldsFromVision,
  isValidRutDv,
  normalizeLicenseClass,
  normalizeRut,
  parseDateFromZone,
  parseRutFromZone,
  preprocessLicenseImageForOcr,
  runVisionDocumentOcrForBuffer,
};
