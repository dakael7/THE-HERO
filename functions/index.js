const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onObjectFinalized} = require('firebase-functions/v2/storage');
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const sharp = require('sharp');
const path = require('path');
const os = require('os');
const fs = require('fs');
const vision = require('@google-cloud/vision');
admin.initializeApp();

// MercadoPago Functions
const {createPaymentPreference} = require('./mercadopago/createPaymentPreference');
const {mercadopagoWebhook} = require('./mercadopago/webhook');
const {verifyPayment} = require('./mercadopago/verifyPayment');
const {simulatePaymentApproved} = require('./mercadopago/simulatePaymentApproved');

// Export MercadoPago functions
exports.createPaymentPreference = createPaymentPreference;
exports.mercadopagoWebhook = mercadopagoWebhook;
exports.verifyPayment = verifyPayment;
exports.simulatePaymentApproved = simulatePaymentApproved;

const STORAGE_REGION = 'southamerica-west1';

const visionClient = new vision.ImageAnnotatorClient();

function isSupportUser(auth) {
  const allowlistRaw = process.env.SUPPORT_EMAIL_ALLOWLIST || '';
  const allowlist = allowlistRaw
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);

  const email = auth?.token?.email ? String(auth.token.email).toLowerCase() : null;
  if (email && allowlist.includes(email)) return true;

  if (auth?.token?.support === true) return true;
  if (auth?.token?.admin === true) return true;

  return false;
}

/**
 * Asigna un pedido a un rider de forma segura
 * Valida: rider verificado, compatibilidad de vehículo, estado del pedido
 * 
 * @param {Object} data - { orderId: string }
 * @param {Object} context - Firebase auth context
 * @returns {Promise<Object>} - { success: boolean, orderId: string, message: string }
 */
exports.claimOrder = onCall(async (request) => {
  // ==========================================
  // 1. VALIDAR AUTENTICACIÓN
  // ==========================================
  if (!request.auth) {
    throw new HttpsError(
      'unauthenticated',
      'Usuario no autenticado'
    );
  }

  const riderId = request.auth.uid;
  const orderId = request.data.orderId;

  if (!orderId) {
    throw new HttpsError(
      'invalid-argument',
      'orderId es requerido'
    );
  }

  console.log(`[claimOrder] Rider ${riderId} intentando tomar pedido ${orderId}`);

  // ==========================================
  // 2. OBTENER PERFIL DEL RIDER
  // ==========================================
  const riderDoc = await admin.firestore()
    .collection('users')
    .doc(riderId)
    .get();

  if (!riderDoc.exists) {
    throw new HttpsError(
      'not-found',
      'Rider no encontrado'
    );
  }

  const riderData = riderDoc.data();
  const riderProfile = riderData.riderProfile;

  // Validar que el usuario tenga rol de rider
  if (!riderData.roles || !riderData.roles.includes('rider')) {
    throw new HttpsError(
      'permission-denied',
      'No tienes permisos de rider'
    );
  }

  // ==========================================
  // 3. VALIDAR RIDER VERIFICADO (CRÍTICO)
  // ==========================================
  if (!riderProfile || !riderProfile.isVerified) {
    throw new HttpsError(
      'failed-precondition',
      'Tu cuenta debe estar verificada para tomar pedidos'
    );
  }

  if (!riderProfile.isActive) {
    throw new HttpsError(
      'failed-precondition',
      'Tu cuenta no está activa'
    );
  }

  console.log(`[claimOrder] Rider verificado: ${riderData.identity.firstName}`);

  // ==========================================
  // 4. TRANSACCIÓN ATÓMICA
  // ==========================================
  const orderRef = admin.firestore().collection('orders').doc(orderId);

  return admin.firestore().runTransaction(async (transaction) => {
    const orderDoc = await transaction.get(orderRef);

    if (!orderDoc.exists) {
      throw new HttpsError(
        'not-found',
        'Pedido no encontrado'
      );
    }

    const order = orderDoc.data();

    // Validar estado
    if (order.status !== 'queued') {
      throw new HttpsError(
        'failed-precondition',
        `Pedido ya no está disponible (estado: ${order.status})`
      );
    }

    if (order.rider && order.rider.assignedRiderId) {
      throw new HttpsError(
        'failed-precondition',
        'Pedido ya tiene rider asignado'
      );
    }

    // ==========================================
    // 5. VALIDAR COMPATIBILIDAD DE VEHÍCULO
    // ==========================================
    const requiredVehicle = order.requirements.requiredVehicle;
    const riderVehicle = riderProfile.vehicle.type;
    const compatibleVehicles = getCompatibleVehicles(riderVehicle);

    console.log(`[claimOrder] Vehículo rider: ${riderVehicle}, Requerido: ${requiredVehicle}`);

    if (!compatibleVehicles.includes(requiredVehicle)) {
      throw new HttpsError(
        'failed-precondition',
        `Tu vehículo (${riderVehicle}) no es compatible con este pedido (requiere ${requiredVehicle})`
      );
    }

    // Validar peso (si existe límite en el perfil)
    if (riderProfile.limits && riderProfile.limits.maxWeightKg) {
      if (order.requirements.weightKg > riderProfile.limits.maxWeightKg) {
        throw new HttpsError(
          'failed-precondition',
          `El peso del pedido (${order.requirements.weightKg}kg) excede tu capacidad (${riderProfile.limits.maxWeightKg}kg)`
        );
      }
    }

    // Validar distancia (si existe límite en el perfil)
    if (riderProfile.limits && riderProfile.limits.maxDistanceKm) {
      if (order.requirements.estimatedDistanceKm > riderProfile.limits.maxDistanceKm) {
        throw new HttpsError(
          'failed-precondition',
          `La distancia del pedido (${order.requirements.estimatedDistanceKm}km) excede tu rango (${riderProfile.limits.maxDistanceKm}km)`
        );
      }
    }

    // ==========================================
    // 6. ASIGNAR PEDIDO
    // ==========================================
    const now = admin.firestore.FieldValue.serverTimestamp();
    
    transaction.update(orderRef, {
      'status': 'assigned',
      'rider.assignedRiderId': riderId,
      'rider.assignedAt': now,
      'rider.vehicleTypeSnapshot': riderProfile.vehicle.type,
      'rider.riderNameSnapshot': riderData.identity.firstName + ' ' + (riderData.identity.lastName || ''),
      'rider.riderPhoneSnapshot': riderData.contact.phoneNumber || '',
      'timestamps.assignedAt': now,
      'updatedAt': now,
    });

    console.log(`[claimOrder] Pedido ${orderId} asignado exitosamente a ${riderId}`);

    return {
      success: true,
      orderId: orderId,
      message: 'Pedido asignado exitosamente'
    };
  });
});

/**
 * Helper: Obtiene vehículos compatibles según el tipo de vehículo del rider
 * 
 * Lógica:
 * - Camión puede tomar: bicycle, motorcycle, car, truck (todos)
 * - Auto puede tomar: bicycle, motorcycle, car
 * - Moto puede tomar: bicycle, motorcycle
 * - Bicicleta puede tomar: bicycle
 * 
 * @param {string} riderVehicleType - Tipo de vehículo del rider
 * @returns {string[]} - Array de tipos de vehículos compatibles
 */
function getCompatibleVehicles(riderVehicleType) {
  switch (riderVehicleType) {
    case 'bicycle':
      return ['bicycle'];
    case 'motorcycle':
      return ['bicycle', 'motorcycle'];
    case 'car':
      return ['bicycle', 'motorcycle', 'car'];
    case 'truck':
      return ['bicycle', 'motorcycle', 'car', 'truck'];
    default:
      console.warn(`[getCompatibleVehicles] Tipo de vehículo desconocido: ${riderVehicleType}`);
      return [];
  }
}

/**
 * Aprueba o rechaza una solicitud de verificación de vehículo.
 *
 * Seguridad:
 * - Solo usuarios soporte/admin (allowlist por email o custom claim) pueden ejecutar.
 *
 * Entrada:
 * - { userId: string, requestId: string, decision: 'approved'|'rejected', reason?: string }
 */
exports.reviewVehicleVerificationRequest = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Usuario no autenticado');
  }

  if (!isSupportUser(request.auth)) {
    throw new HttpsError('permission-denied', 'No autorizado');
  }

  const userId = request.data?.userId;
  const requestId = request.data?.requestId;
  const decision = request.data?.decision;
  const reason = request.data?.reason;

  if (!userId || !requestId || !decision) {
    throw new HttpsError('invalid-argument', 'userId, requestId y decision son requeridos');
  }

  if (!['approved', 'rejected'].includes(decision)) {
    throw new HttpsError('invalid-argument', 'decision inválida');
  }

  const reqRef = admin
    .firestore()
    .collection('users')
    .doc(userId)
    .collection('vehicle_verification_requests')
    .doc(requestId);

  const userRef = admin.firestore().collection('users').doc(userId);
  const reviewerId = request.auth.uid;

  await admin.firestore().runTransaction(async (tx) => {
    const reqSnap = await tx.get(reqRef);
    if (!reqSnap.exists) {
      throw new HttpsError('not-found', 'Solicitud no encontrada');
    }

    const reqData = reqSnap.data() || {};
    const vehicleType = reqData.vehicleType;
    if (!vehicleType || typeof vehicleType !== 'string') {
      throw new HttpsError('failed-precondition', 'vehicleType faltante en solicitud');
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    tx.update(reqRef, {
      status: decision,
      updatedAt: now,
      verification: {
        verifiedAt: now,
        verificationMode: 'manual',
        reason: reason || null,
        reviewerId,
      },
    });

    tx.set(
      userRef,
      {
        riderProfile: {
          vehicles: {
            [vehicleType]: {
              verification: {
                status: decision,
                verifiedAt: now,
                reviewerId,
                reason: reason || null,
                requestId,
              },
            },
          },
        },
      },
      { merge: true }
    );
  });

  return { success: true };
});

/**
 * Aprueba o rechaza una solicitud de verificación de RUT.
 *
 * Seguridad:
 * - Solo usuarios soporte/admin (allowlist por email o custom claim) pueden ejecutar.
 *
 * Entrada:
 * - { userId: string, requestId: string, decision: 'approved'|'rejected', reason?: string }
 */
exports.reviewRutVerificationRequest = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Usuario no autenticado');
  }

  if (!isSupportUser(request.auth)) {
    throw new HttpsError('permission-denied', 'No autorizado');
  }

  const userId = request.data?.userId;
  const requestId = request.data?.requestId;
  const decision = request.data?.decision;
  const reason = request.data?.reason;

  if (!userId || !requestId || !decision) {
    throw new HttpsError('invalid-argument', 'userId, requestId y decision son requeridos');
  }

  if (!['approved', 'rejected'].includes(decision)) {
    throw new HttpsError('invalid-argument', 'decision inválida');
  }

  const userRef = admin.firestore().collection('users').doc(userId);
  const reqRef = userRef.collection('rut_verification_requests').doc(requestId);
  const reviewerId = request.auth.uid;

  await admin.firestore().runTransaction(async (tx) => {
    const reqSnap = await tx.get(reqRef);
    if (!reqSnap.exists) {
      throw new HttpsError('not-found', 'Solicitud no encontrada');
    }

    const now = admin.firestore.FieldValue.serverTimestamp();

    tx.set(
      reqRef,
      {
        status: decision,
        updatedAt: now,
        verification: {
          verifiedAt: now,
          verificationMode: 'manual',
          reason: reason || null,
          reviewerId,
        },
      },
      { merge: true }
    );

    tx.set(
      userRef,
      {
        rutVerification: {
          status: decision,
          verifiedAt: decision === 'approved' ? now : now,
          reviewerId,
          reason: reason || null,
          requestId,
          mode: 'manual',
        },
      },
      { merge: true }
    );
  });

  return { success: true };
});

/**
 * Función para actualizar el estado de un pedido
 * Solo el rider asignado puede actualizar el estado
 * 
 * @param {Object} data - { orderId: string, newStatus: string }
 * @param {Object} context - Firebase auth context
 */
exports.updateOrderStatus = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Usuario no autenticado');
  }

  const { orderId, newStatus } = request.data;
  const riderId = request.auth.uid;

  if (!orderId || !newStatus) {
    throw new HttpsError('invalid-argument', 'orderId y newStatus son requeridos');
  }

  // Estados válidos para actualización por rider
  const validStatuses = ['picked_up', 'in_transit', 'delivered'];
  if (!validStatuses.includes(newStatus)) {
    throw new HttpsError(
      'invalid-argument',
      `Estado inválido. Debe ser uno de: ${validStatuses.join(', ')}`
    );
  }

  const orderRef = admin.firestore().collection('orders').doc(orderId);
  const orderDoc = await orderRef.get();

  if (!orderDoc.exists) {
    throw new HttpsError('not-found', 'Pedido no encontrado');
  }

  const order = orderDoc.data();

  // Validar que el rider sea el asignado
  if (!order.rider || order.rider.assignedRiderId !== riderId) {
    throw new HttpsError(
      'permission-denied',
      'No tienes permiso para actualizar este pedido'
    );
  }

  // Validar transición de estado
  const validTransitions = {
    'assigned': ['picked_up'],
    'picked_up': ['in_transit'],
    'in_transit': ['delivered']
  };

  if (!validTransitions[order.status] || !validTransitions[order.status].includes(newStatus)) {
    throw new HttpsError(
      'failed-precondition',
      `No se puede cambiar de ${order.status} a ${newStatus}`
    );
  }

  // Actualizar estado
  const now = admin.firestore.FieldValue.serverTimestamp();
  const updates = {
    status: newStatus,
    updatedAt: now
  };

  // Actualizar timestamp específico
  if (newStatus === 'picked_up') {
    updates['timestamps.pickedUpAt'] = now;
  } else if (newStatus === 'in_transit') {
    updates['timestamps.inTransitAt'] = now;
  } else if (newStatus === 'delivered') {
    updates['timestamps.deliveredAt'] = now;
  }

  await orderRef.update(updates);

  console.log(`[updateOrderStatus] Pedido ${orderId} actualizado a ${newStatus}`);

  return {
    success: true,
    orderId: orderId,
    newStatus: newStatus,
    message: `Pedido actualizado a ${newStatus}`
  };
});

/**
 * Procesa imágenes subidas a Storage:
 * - Solo archivos de imagen
 * - Evita re-procesar imágenes ya convertidas o en carpeta processed/
 * - Genera versión 1200x1200 en WebP y la guarda en processed/<ruta>/*_1200.webp
 */
exports.processImage1200Webp = onObjectFinalized(
  {region: STORAGE_REGION},
  async (event) => {
  const object = event.data;
  const filePath = object.name;
  const contentType = object.contentType || '';

  if (!filePath) return null;
  if (!contentType.startsWith('image/')) return null;
  if (filePath.endsWith('_1200.webp')) return null;
  if (filePath.startsWith('processed/')) return null;

  const bucket = admin.storage().bucket(object.bucket);
  const fileName = path.basename(filePath);
  const dirName = path.dirname(filePath);
  const tempLocalFile = path.join(os.tmpdir(), fileName);

  const isAd = filePath.startsWith('ads/');
  const isOffer = filePath.startsWith('offers/');
  const metadata = object.metadata || {};

  const baseName = fileName.replace(/\.[^.]+$/, '');
  const processedFileName = isAd ? `${baseName}.webp` : `${baseName}_1200.webp`;
  const processedDir = path.join('processed', dirName === '.' ? '' : dirName);
  const processedPath = path.join(processedDir, processedFileName);
  const tempProcessedFile = path.join(os.tmpdir(), processedFileName);

  try {
    // Descargar original
    await bucket.file(filePath).download({ destination: tempLocalFile });

    const transformer = sharp(tempLocalFile).rotate();

    if (isAd) {
      // Banners: sin resize, solo convertir a WebP
      await transformer
        .toFormat('webp', { quality: 85 })
        .toFile(tempProcessedFile);
    } else {
      // Productos y resto: estandarizar a 1200x1200 WebP (recorte centrado)
      await transformer
        .resize(1200, 1200, { fit: 'cover', position: 'centre' })
        .toFormat('webp', { quality: 80 })
        .toFile(tempProcessedFile);
    }

    // Subir procesado
    await bucket.upload(tempProcessedFile, {
      destination: processedPath,
      contentType: 'image/webp',
      metadata: {
        metadata: {
          processed: 'true',
          original: filePath,
        },
      },
    });

    if (isAd) {
      // Crear/actualizar documento en colección de lectura
      const downloadUrl = buildDownloadUrl(bucket.name, processedPath);
      const docId = processedPath
        .replace(/^processed\//, '')
        .replace(/[^\w\-\/.]/g, '_')
        .replace(/\//g, '__');

      const rawOrder = metadata.order;
      const rawActive = metadata.active;
      const order = typeof rawOrder === 'string' ? parseInt(rawOrder, 10) || 0 : 0;
      const active = typeof rawActive === 'string'
        ? ['true', '1', 'yes'].includes(rawActive.toLowerCase())
        : true;

      await admin.firestore().collection('promo_banners').doc(docId).set(
        {
          imageUrl: downloadUrl,
          order,
          active,
          cacheBuster: admin.firestore.FieldValue.serverTimestamp(),
          storagePath: processedPath,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    if (isOffer) {
      // Crear/actualizar documento de oferta usando el ID del path: offers/{userId}/{offerId}/file
      const segments = filePath.split('/').filter(Boolean);
      const offerId = segments.length >= 3 ? segments[2] : null;
      if (offerId) {
        const downloadUrl = buildDownloadUrl(bucket.name, processedPath);
        const offersCol = admin.firestore().collection('offers');
        await offersCol.doc(offerId).set(
          {
            coverImageUrl: downloadUrl,
            imageUrls: admin.firestore.FieldValue.arrayUnion(downloadUrl),
            storagePath: processedPath,
            cacheBuster: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      }
    }

    logger.info('Imagen procesada', {
      original: filePath,
      processed: processedPath,
    });
  } catch (error) {
    logger.error('Error procesando imagen', { filePath, error });
    throw error;
  } finally {
    // Limpieza local
    if (fs.existsSync(tempLocalFile)) {
      fs.unlinkSync(tempLocalFile);
    }
    if (fs.existsSync(tempProcessedFile)) {
      fs.unlinkSync(tempProcessedFile);
    }
  }

  return null;
});

function normalizeRut(raw) {
  if (!raw) return null;
  const cleaned = String(raw)
    .toUpperCase()
    .replace(/\s+/g, '')
    .replace(/\./g, '')
    .replace(/–|—/g, '-')
    .replace(/[^0-9K-]/g, '');

  const withDash = cleaned.includes('-')
    ? cleaned
    : cleaned.length >= 2
      ? `${cleaned.slice(0, -1)}-${cleaned.slice(-1)}`
      : cleaned;

  const match = withDash.match(/^(\d{7,8})-([0-9K])$/);
  if (!match) return null;
  return `${match[1]}-${match[2]}`;
}

function computeRutDv(body) {
  let sum = 0;
  let multiplier = 2;

  for (let i = body.length - 1; i >= 0; i -= 1) {
    sum += parseInt(body[i], 10) * multiplier;
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

function extractRutCandidates(text) {
  if (!text) return [];
  const normalizedText = String(text)
    .toUpperCase()
    .replace(/\./g, '')
    .replace(/\s+/g, ' ');

  const candidates = new Set();

  const patterns = [
    /\b\d{1,2}(?:\.?\d{3}){2}-[0-9K]\b/g,
    /\b\d{7,8}-[0-9K]\b/g,
    /\b\d{7,8}[0-9K]\b/g,
  ];

  for (const re of patterns) {
    const matches = normalizedText.match(re) || [];
    for (const m of matches) {
      const n = normalizeRut(m);
      if (n) candidates.add(n);
    }
  }

  return Array.from(candidates);
}

async function runVisionOcrForGcsUri({gcsUri, mimeType}) {
  if (mimeType === 'application/pdf') {
    const [result] = await visionClient.documentTextDetection({
      image: {source: {imageUri: gcsUri}},
    });
    return result?.fullTextAnnotation?.text || '';
  }

  const [result] = await visionClient.documentTextDetection({
    image: {source: {imageUri: gcsUri}},
  });
  return result?.fullTextAnnotation?.text || '';
}

exports.ocrVehicleVerificationLicenseOnUpload = onObjectFinalized(
  {region: STORAGE_REGION},
  async (event) => {
    const object = event.data;
    const filePath = object.name;
    const contentType = object.contentType || '';

    if (!filePath) return null;
    if (!filePath.startsWith('riders/')) return null;

    // Expected path:
    // riders/{uid}/documents/vehicle_verification/{vehicleType}/{requestId}/...license_front.*
    const segments = filePath.split('/').filter(Boolean);
    // 0 riders, 1 uid, 2 documents, 3 vehicle_verification, 4 vehicleType, 5 requestId, ... filename
    if (segments.length < 7) return null;
    if (segments[0] !== 'riders') return null;
    if (segments[2] !== 'documents') return null;
    if (segments[3] !== 'vehicle_verification') return null;

    const riderId = segments[1];
    const vehicleType = segments[4];
    const requestId = segments[5];
    const fileName = segments[segments.length - 1];

    const isLicenseFront = fileName.toLowerCase().includes('license_front');
    if (!isLicenseFront) return null;

    const isPdf = contentType === 'application/pdf' || fileName.toLowerCase().endsWith('.pdf');
    const isImage = contentType.startsWith('image/');
    if (!isPdf && !isImage) return null;

    logger.info('[ocrVehicleVerification] Start', {
      riderId,
      vehicleType,
      requestId,
      filePath,
      contentType,
    });

    const userRef = admin.firestore().collection('users').doc(riderId);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      logger.warn('[ocrVehicleVerification] user not found', { riderId });
      return null;
    }

    const userData = userSnap.data() || {};
    const declaredRut = userData?.identity?.documentId;
    const declaredNormalized = normalizeRut(declaredRut);

    const reqRef = userRef
      .collection('vehicle_verification_requests')
      .doc(requestId);

    const gcsUri = `gs://${object.bucket}/${filePath}`;
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Mark processing
    await userRef.set(
      {
        riderProfile: {
          vehicles: {
            [vehicleType]: {
              ocr: {
                status: 'processing',
                filePath,
                contentType,
                processedAt: now,
              },
            },
          },
        },
      },
      { merge: true }
    );

    try {
      const text = await runVisionOcrForGcsUri({
        gcsUri,
        mimeType: isPdf ? 'application/pdf' : contentType,
      });

      const candidates = extractRutCandidates(text);
      const extractedRut = candidates.length > 0 ? candidates[0] : null;
      const extractedNormalized = normalizeRut(extractedRut);
      const dvValid = extractedRut ? isValidRutDv(extractedRut) : false;
      const matchDeclared =
        extractedNormalized && declaredNormalized
          ? extractedNormalized === declaredNormalized
          : false;

      const errors = [];
      let verificationStatus = 'needs_review';

      if (!declaredRut) {
        errors.push('missing_declared_rut');
      }

      if (!extractedRut) {
        errors.push('rut_not_found');
        verificationStatus = 'rejected';
      } else if (!dvValid) {
        errors.push('rut_dv_invalid');
        verificationStatus = 'rejected';
      } else if (declaredRut && !matchDeclared) {
        errors.push('rut_mismatch_declared');
        verificationStatus = 'needs_review';
      } else if (declaredRut && matchDeclared && dvValid) {
        verificationStatus = 'approved';
      }

      await userRef.set(
        {
          riderProfile: {
            vehicles: {
              [vehicleType]: {
                ocr: {
                  status: verificationStatus,
                  filePath,
                  contentType,
                  processedAt: now,
                  extractedRut,
                  dvValid,
                  matchDeclared,
                  rutCandidates: candidates.slice(0, 5),
                  errorCodes: errors,
                },
                verification: {
                  status: verificationStatus,
                  verifiedAt: verificationStatus === 'approved' ? now : null,
                  requestId,
                  mode: 'ocr',
                },
              },
            },
          },
        },
        { merge: true }
      );

      // Update request doc if exists
      await reqRef.set(
        {
          updatedAt: now,
          status: verificationStatus,
          ocr: {
            extractedRut,
            dvValid,
            matchDeclared,
            errorCodes: errors,
            processedAt: now,
          },
        },
        { merge: true }
      );

      logger.info('[ocrVehicleVerification] Done', {
        riderId,
        vehicleType,
        requestId,
        verificationStatus,
      });
    } catch (error) {
      logger.error('[ocrVehicleVerification] OCR failed', {
        riderId,
        vehicleType,
        requestId,
        filePath,
        error,
      });

      await userRef.set(
        {
          riderProfile: {
            vehicles: {
              [vehicleType]: {
                ocr: {
                  status: 'failed',
                  filePath,
                  contentType,
                  processedAt: now,
                  errorCodes: ['ocr_error'],
                },
              },
            },
          },
        },
        { merge: true }
      );

      await reqRef.set(
        {
          updatedAt: now,
          status: 'failed',
          ocr: {
            errorCodes: ['ocr_error'],
            processedAt: now,
          },
        },
        { merge: true }
      );
    }

    return null;
  }
);

exports.ocrRutVerificationOnUpload = onObjectFinalized(
  {region: STORAGE_REGION},
  async (event) => {
    const object = event.data;
    const filePath = object.name;
    const contentType = object.contentType || '';

    if (!filePath) return null;

    // Expected path:
    // users/{uid}/documents/rut_verification/{requestId}/...id_front.*
    const segments = filePath.split('/').filter(Boolean);
    // 0 users, 1 uid, 2 documents, 3 rut_verification, 4 requestId, ... filename
    if (segments.length < 6) return null;
    if (segments[0] !== 'users') return null;
    if (segments[2] !== 'documents') return null;
    if (segments[3] !== 'rut_verification') return null;

    const userId = segments[1];
    const requestId = segments[4];
    const fileName = segments[segments.length - 1];

    const isFront = fileName.toLowerCase().includes('id_front');
    if (!isFront) return null;

    const isPdf = contentType === 'application/pdf' || fileName.toLowerCase().endsWith('.pdf');
    const isImage = contentType.startsWith('image/');
    if (!isPdf && !isImage) return null;

    logger.info('[ocrRutVerification] Start', {
      userId,
      requestId,
      filePath,
      contentType,
    });

    const userRef = admin.firestore().collection('users').doc(userId);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      logger.warn('[ocrRutVerification] user not found', { userId });
      return null;
    }

    const userData = userSnap.data() || {};
    const declaredRut = userData?.identity?.documentId;
    const declaredNormalized = normalizeRut(declaredRut);

    const reqRef = userRef.collection('rut_verification_requests').doc(requestId);
    const gcsUri = `gs://${object.bucket}/${filePath}`;
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Mark processing
    await userRef.set(
      {
        rutVerification: {
          status: 'processing',
          requestId,
          mode: 'ocr',
          updatedAt: now,
        },
      },
      { merge: true }
    );

    await reqRef.set(
      {
        updatedAt: now,
        status: 'processing',
      },
      { merge: true }
    );

    try {
      const text = await runVisionOcrForGcsUri({
        gcsUri,
        mimeType: isPdf ? 'application/pdf' : contentType,
      });

      const candidates = extractRutCandidates(text);
      const extractedRut = candidates.length > 0 ? candidates[0] : null;
      const extractedNormalized = normalizeRut(extractedRut);
      const dvValid = extractedRut ? isValidRutDv(extractedRut) : false;
      const matchDeclared =
        extractedNormalized && declaredNormalized
          ? extractedNormalized === declaredNormalized
          : false;

      const errors = [];
      let verificationStatus = 'needs_review';

      if (!declaredRut) {
        errors.push('missing_declared_rut');
      }

      if (!extractedRut) {
        errors.push('rut_not_found');
        verificationStatus = 'needs_review';
      } else if (!dvValid) {
        errors.push('rut_dv_invalid');
        verificationStatus = 'needs_review';
      } else if (declaredRut && !matchDeclared) {
        errors.push('rut_mismatch_declared');
        verificationStatus = 'needs_review';
      } else if (declaredRut && matchDeclared && dvValid) {
        verificationStatus = 'approved';
      }

      await userRef.set(
        {
          rutVerification: {
            status: verificationStatus,
            requestId,
            mode: 'ocr',
            verifiedAt: verificationStatus === 'approved' ? now : null,
            ocr: {
              filePath,
              contentType,
              processedAt: now,
              extractedRut,
              dvValid,
              matchDeclared,
              rutCandidates: candidates.slice(0, 5),
              errorCodes: errors,
            },
          },
        },
        { merge: true }
      );

      await reqRef.set(
        {
          updatedAt: now,
          status: verificationStatus,
          ocr: {
            extractedRut,
            dvValid,
            matchDeclared,
            errorCodes: errors,
            processedAt: now,
          },
        },
        { merge: true }
      );

      logger.info('[ocrRutVerification] Done', {
        userId,
        requestId,
        verificationStatus,
      });
    } catch (error) {
      logger.error('[ocrRutVerification] OCR failed', {
        userId,
        requestId,
        filePath,
        error,
      });

      await userRef.set(
        {
          rutVerification: {
            status: 'failed',
            requestId,
            mode: 'ocr',
            ocr: {
              filePath,
              contentType,
              processedAt: now,
              errorCodes: ['ocr_error'],
            },
          },
        },
        { merge: true }
      );

      await reqRef.set(
        {
          updatedAt: now,
          status: 'failed',
          ocr: {
            errorCodes: ['ocr_error'],
            processedAt: now,
          },
        },
        { merge: true }
      );
    }

    return null;
  }
);

/**
 * Trigger: Notify hero when rider completes a pickup stop
 * Uses orders/{orderId}.pickupProgress.currentStopIndex (0-based) changes.
 */
exports.notifyPickupStopProgress = onDocumentWritten(
  {document: 'orders/{orderId}', region: STORAGE_REGION},
  async (event) => {
    const before = event.data && event.data.before.exists ? event.data.before.data() : null;
    const after = event.data && event.data.after.exists ? event.data.after.data() : null;

    if (!after || !before) {
      return;
    }

    const orderId = event.params.orderId;
    const heroId = after.heroId;

    const beforeIndexRaw = before.pickupProgress && typeof before.pickupProgress.currentStopIndex !== 'undefined'
      ? before.pickupProgress.currentStopIndex
      : null;
    const afterIndexRaw = after.pickupProgress && typeof after.pickupProgress.currentStopIndex !== 'undefined'
      ? after.pickupProgress.currentStopIndex
      : null;

    if (afterIndexRaw === null || typeof afterIndexRaw === 'undefined') {
      return;
    }

    // Convert to number and ensure it's a progress forward.
    const beforeIndex = (beforeIndexRaw === null || typeof beforeIndexRaw === 'undefined')
      ? -1
      : Number(beforeIndexRaw);
    const afterIndex = Number(afterIndexRaw);

    if (!Number.isFinite(afterIndex)) {
      return;
    }

    // Only notify when index increases.
    if (afterIndex <= beforeIndex) {
      return;
    }

    const totalStops = Array.isArray(after.pickupStops) ? after.pickupStops.length : 0;
    if (totalStops <= 0) {
      return;
    }

    const humanIndex = Math.min(Math.max(afterIndex + 1, 1), totalStops);

    console.log(
      `Order ${orderId} pickup progress: ${beforeIndex} -> ${afterIndex} (stop ${humanIndex}/${totalStops})`
    );

    const isLastStop = humanIndex >= totalStops;
    const ordinal = humanIndex === 1
      ? 'primer'
      : humanIndex === 2
        ? 'segundo'
        : humanIndex === 3
          ? 'tercer'
          : `${humanIndex}°`;
    const body = isLastStop
      ? 'El rider ya está en el último punto de recogida. Te avisaremos cuando vaya en camino a la entrega.'
      : `El rider ya está en el ${ordinal} punto de recogida. Te avisaremos cuando vaya en camino.`;

    await sendNotificationToUsers(
      heroId,
      {
        title: '📦 Tu pedido avanza',
        body,
      },
      {
        type: 'pickup_progress',
        action: 'open_order',
        orderId,
        pickupStopIndex: String(afterIndex),
        pickupStopsCount: String(totalStops),
        priority: 'high',
      }
    );
  }
);

function getIsoWeekKey(date) {
  const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNo = Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
  const year = d.getUTCFullYear();
  const week = String(weekNo).padStart(2, '0');
  return `${year}-W${week}`;
}

exports.syncRiderStatsOnOrderWrite = onDocumentWritten(
  {document: 'orders/{orderId}', region: STORAGE_REGION},
  async (event) => {
    const before = event.data && event.data.before.exists ? event.data.before.data() : null;
    const after = event.data && event.data.after.exists ? event.data.after.data() : null;

    if (!after) {
      return;
    }

    const beforeStatus = before && typeof before.status === 'string' ? before.status : null;
    const afterStatus = typeof after.status === 'string' ? after.status : null;

    if (beforeStatus === afterStatus) {
      return;
    }

    const riderId =
      (after.rider && after.rider.assignedRiderId) ||
      (before && before.rider && before.rider.assignedRiderId) ||
      null;

    if (!riderId) {
      return;
    }

    const deliveryFee = typeof after.deliveryFee === 'number' ? after.deliveryFee : 0;
    const statsRef = admin.firestore().collection('rider_stats').doc(riderId);
    const inc = admin.firestore.FieldValue.increment;

    const currentWeekKey = getIsoWeekKey(new Date());

    const toCounters = (status) => {
      switch ((status || '').toLowerCase()) {
        case 'delivered':
          return {deliveredTrips: 1, canceledTrips: 0, failedTrips: 0};
        case 'canceled':
          return {deliveredTrips: 0, canceledTrips: 1, failedTrips: 0};
        case 'failed':
          return {deliveredTrips: 0, canceledTrips: 0, failedTrips: 1};
        default:
          return {deliveredTrips: 0, canceledTrips: 0, failedTrips: 0};
      }
    };

    const beforeC = toCounters(beforeStatus);
    const afterC = toCounters(afterStatus);

    const deltaDelivered = afterC.deliveredTrips - beforeC.deliveredTrips;
    const deltaCanceled = afterC.canceledTrips - beforeC.canceledTrips;
    const deltaFailed = afterC.failedTrips - beforeC.failedTrips;

    const updates = {
      riderId,
      deliveredTrips: inc(deltaDelivered),
      canceledTrips: inc(deltaCanceled),
      failedTrips: inc(deltaFailed),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (deltaDelivered !== 0) {
      updates.totalEarnings = inc(deltaDelivered * deliveryFee);
      updates.totalTrips = inc(deltaDelivered);

      const deliveredAt =
        after.timestamps && after.timestamps.deliveredAt && typeof after.timestamps.deliveredAt.toDate === 'function'
          ? after.timestamps.deliveredAt.toDate()
          : new Date();
      const deliveredWeekKey = getIsoWeekKey(deliveredAt);

      updates.weekKey = currentWeekKey;

      if (deliveredWeekKey === currentWeekKey) {
        updates.weeklyEarnings = inc(deltaDelivered * deliveryFee);
        updates.weeklyTrips = inc(deltaDelivered);
      }
    }

    const deltaCompleted = deltaDelivered + deltaCanceled + deltaFailed;
    if (deltaCompleted !== 0) {
      updates.completedTrips = inc(deltaCompleted);
    }

    await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(statsRef);
      const existingWeekKey = snap.exists && snap.data() && typeof snap.data().weekKey === 'string'
        ? snap.data().weekKey
        : null;

      if (existingWeekKey !== currentWeekKey) {
        tx.set(
          statsRef,
          {
            weekKey: currentWeekKey,
            weeklyEarnings: 0,
            weeklyTrips: 0,
          },
          {merge: true}
        );
      }

      tx.set(statsRef, updates, {merge: true});
    });
  }
);

function buildDownloadUrl(bucketName, filePath) {
  const encodedPath = encodeURIComponent(filePath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedPath}?alt=media`;
}

// ==========================================
// PUSH NOTIFICATIONS (FCM)
// ==========================================

/**
 * Helper: Send FCM notification to user(s)
 * @param {string|string[]} userIds - Single user ID or array of user IDs
 * @param {Object} notification - { title, body, imageUrl? }
 * @param {Object} data - Custom data payload
 * @returns {Promise<void>}
 */
async function sendNotificationToUsers(userIds, notification, data = {}) {
  try {
    const ids = Array.isArray(userIds) ? userIds : [userIds];
    const userTokensMap = new Map(); // Map userId -> tokens[]

    // Get FCM tokens for all users
    for (const userId of ids) {
      const userDoc = await admin.firestore().collection('users').doc(userId).get();
      if (userDoc.exists) {
        const userData = userDoc.data();
        const tokens = [];

        if (userData.fcmTokens && Array.isArray(userData.fcmTokens)) {
          tokens.push(...userData.fcmTokens);
        }

        if (userData.fcmToken && typeof userData.fcmToken === 'string') {
          const t = userData.fcmToken.trim();
          if (t) tokens.push(t);
        }

        const uniqueTokens = [...new Set(tokens.filter(Boolean))];
        if (uniqueTokens.length > 0) {
          userTokensMap.set(userId, uniqueTokens);
        }
      }
    }

    if (userTokensMap.size === 0) {
      console.log('No FCM tokens found for users:', ids);
      return;
    }

    // Collect all tokens
    const allTokens = [];
    userTokensMap.forEach((tokens) => {
      allTokens.push(...tokens);
    });

    if (allTokens.length === 0) {
      console.log('No FCM tokens to send to');
      return;
    }

    // Build FCM message
    const message = {
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: {
        ...data,
        // Ensure all data values are strings
        ...Object.fromEntries(
          Object.entries(data).map(([k, v]) => [k, String(v)])
        ),
      },
    };

    if (notification.imageUrl) {
      message.notification.imageUrl = notification.imageUrl;
    }

    // Send to all tokens
    const results = await admin.messaging().sendEachForMulticast({
      tokens: allTokens,
      ...message,
      android: {
        priority: data.priority === 'high' ? 'high' : 'normal',
      },
      apns: {
        payload: {
          aps: {
            contentAvailable: true,
          },
        },
      },
    });

    console.log(`Sent ${results.successCount} notifications, ${results.failureCount} failed`);

    // Clean up invalid tokens
    if (results.failureCount > 0) {
      const invalidTokens = [];
      results.responses.forEach((response, idx) => {
        if (!response.success) {
          const errorCode = response.error?.code;
          // Remove tokens that are invalid, not registered, or unregistered
          if (
            errorCode === 'messaging/invalid-registration-token' ||
            errorCode === 'messaging/registration-token-not-registered'
          ) {
            invalidTokens.push(allTokens[idx]);
          }
        }
      });

      // Remove invalid tokens from user documents
      if (invalidTokens.length > 0) {
        console.log(`Cleaning up ${invalidTokens.length} invalid tokens`);
        
        for (const [userId, userTokens] of userTokensMap.entries()) {
          const tokensToRemove = userTokens.filter(token => invalidTokens.includes(token));
          
          if (tokensToRemove.length > 0) {
            await admin.firestore().collection('users').doc(userId).update({
              fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokensToRemove),
            });
            console.log(`Removed ${tokensToRemove.length} invalid tokens from user ${userId}`);
          }
        }
      }
    }

    // Save notification to Firestore for each user
    const batch = admin.firestore().batch();
    for (const userId of ids) {
      const notificationRef = admin.firestore().collection('notifications').doc();
      batch.set(notificationRef, {
        userId,
        type: data.type || 'system',
        title: notification.title,
        body: notification.body,
        data,
        action: data.action,
        imageUrl: notification.imageUrl || null,
        priority: data.priority || 'normal',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        read: false,
      });
    }
    await batch.commit();
  } catch (error) {
    console.error('Error sending notification:', error);
    throw error;
  }
}

/**
 * Trigger: Send notification when order status changes
 * Notifies hero and rider about order status updates
 */
exports.notifyOrderStatusChange = onDocumentWritten(
  {document: 'orders/{orderId}', region: STORAGE_REGION},
  async (event) => {
    const before = event.data && event.data.before.exists ? event.data.before.data() : null;
    const after = event.data && event.data.after.exists ? event.data.after.data() : null;

    // Only proceed if status changed
    if (!after || !before || before.status === after.status) {
      return;
    }

    const orderId = event.params.orderId;
    const heroId = after.heroId;
    const riderId = after.rider?.assignedRiderId;
    const newStatus = after.status;
    const oldStatus = before.status;

    console.log(`Order ${orderId} status changed: ${oldStatus} -> ${newStatus}`);

    // Define notification messages for each status
    const statusMessages = {
      // Hero notifications
      hero: {
        assigned: {
          title: '🚴 Rider Asignado',
          body: 'Un rider ha sido asignado a tu pedido',
        },
        picked_up: {
          title: '📦 Pedido Recogido',
          body: 'Tu pedido ha sido recogido por el rider',
        },
        in_transit: {
          title: '🚚 En Camino',
          body: 'Tu pedido está en camino',
        },
        delivered: {
          title: '✅ Pedido Entregado',
          body: 'Tu pedido ha sido entregado',
        },
        canceled: {
          title: '❌ Pedido Cancelado',
          body: 'Tu pedido ha sido cancelado',
        },
      },
      // Rider notifications
      rider: {
        canceled: {
          title: '❌ Pedido Cancelado',
          body: 'El pedido ha sido cancelado',
        },
      },
    };

    // Send notification to hero
    if (statusMessages.hero[newStatus]) {
      await sendNotificationToUsers(
        heroId,
        statusMessages.hero[newStatus],
        {
          type: 'order_status',
          action: 'open_order',
          orderId,
          status: newStatus,
          priority: 'high',
        }
      );
    }

    // Send notification to rider if assigned
    if (riderId && statusMessages.rider[newStatus]) {
      await sendNotificationToUsers(
        riderId,
        statusMessages.rider[newStatus],
        {
          type: 'order_status',
          action: 'open_order',
          orderId,
          status: newStatus,
          priority: 'high',
        }
      );
    }
  }
);

/**
 * Trigger: Notify nearby riders when order is queued
 * Sends notification to riders within a certain radius
 */
exports.notifyNearbyRiders = onDocumentWritten(
  {document: 'orders/{orderId}', region: STORAGE_REGION},
  async (event) => {
    const before = event.data && event.data.before.exists ? event.data.before.data() : null;
    const after = event.data && event.data.after.exists ? event.data.after.data() : null;

    // Only proceed if order just became queued
    if (!after || after.status !== 'queued' || before?.status === 'queued') {
      return;
    }

    const orderId = event.params.orderId;
    const pickupLocation = after.pickup?.location;

    if (!pickupLocation || !pickupLocation.latitude || !pickupLocation.longitude) {
      console.log('Order has no pickup location, skipping nearby rider notification');
      return;
    }

    // Get all active riders
    const ridersSnapshot = await admin.firestore()
      .collection('users')
      .where('roles', 'array-contains', 'rider')
      .where('riderProfile.isActive', '==', true)
      .where('riderProfile.isVerified', '==', true)
      .get();

    if (ridersSnapshot.empty) {
      console.log('No active riders found');
      return;
    }

    // Calculate distance and filter nearby riders (within 10km)
    const RADIUS_KM = 10;
    const nearbyRiders = [];

    for (const riderDoc of ridersSnapshot.docs) {
      const riderData = riderDoc.data();
      const riderLocation = riderData.riderProfile?.currentLocation;

      if (!riderLocation || !riderLocation.latitude || !riderLocation.longitude) {
        continue;
      }

      // Simple distance calculation (Haversine formula)
      const distance = calculateDistance(
        pickupLocation.latitude,
        pickupLocation.longitude,
        riderLocation.latitude,
        riderLocation.longitude
      );

      if (distance <= RADIUS_KM) {
        nearbyRiders.push({
          riderId: riderDoc.id,
          distance,
        });
      }
    }

    if (nearbyRiders.length === 0) {
      console.log('No nearby riders found');
      return;
    }

    console.log(`Found ${nearbyRiders.length} nearby riders for order ${orderId}`);

    // Sort by distance
    nearbyRiders.sort((a, b) => a.distance - b.distance);

    // Send notification to nearby riders
    const riderIds = nearbyRiders.map(r => r.riderId);
    await sendNotificationToUsers(
      riderIds,
      {
        title: '🎯 Nuevo Pedido Cercano',
        body: `Hay un pedido disponible a ${nearbyRiders[0].distance.toFixed(1)} km de ti`,
      },
      {
        type: 'nearby_order',
        action: 'open_order',
        orderId,
        distance: String(nearbyRiders[0].distance),
        priority: 'high',
      }
    );
  }
);

/**
 * Helper: Calculate distance between two coordinates (Haversine formula)
 * @param {number} lat1 - Latitude 1
 * @param {number} lon1 - Longitude 1
 * @param {number} lat2 - Latitude 2
 * @param {number} lon2 - Longitude 2
 * @returns {number} Distance in kilometers
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth's radius in km
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(degrees) {
  return degrees * (Math.PI / 180);
}

/**
 * Callable: Send notification from system operator
 * Allows authorized users to send notifications to specific users or broadcast
 * 
 * @param {Object} data - { targetUserIds?: string[], title: string, body: string, type?: string, imageUrl?: string, useTopic?: boolean }
 */
exports.sendOperatorNotification = onCall(async (request) => {
  // Verify user is authorized (support/admin)
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Usuario no autenticado');
  }

  if (!isSupportUser(request.auth)) {
    throw new HttpsError('permission-denied', 'No autorizado');
  }

  const {targetUserIds, title, body, type, imageUrl, targetScreen, useTopic} = request.data;

  if (!title || !body) {
    throw new HttpsError('invalid-argument', 'title y body son requeridos');
  }

  let recipients = targetUserIds;

  // If no specific users, broadcast to all users
  if (!recipients || recipients.length === 0) {
    if (useTopic) {
      // Use FCM topic for efficient broadcast
      const message = {
        notification: {
          title,
          body,
        },
        data: {
          type: type || 'system',
          action: targetScreen ? 'open_screen' : 'open_notifications',
          targetScreen: targetScreen || '',
        },
        topic: 'all_users',
      };

      if (imageUrl) {
        message.notification.imageUrl = imageUrl;
      }

      await admin.messaging().send(message);

      return {
        success: true,
        method: 'topic',
        message: 'Notificación enviada a todos los usuarios vía topic',
      };
    } else {
      // Paginated broadcast to all users
      const BATCH_SIZE = 500; // FCM limit is 500 tokens per request
      let totalSent = 0;
      let lastDoc = null;

      while (true) {
        let query = admin.firestore()
          .collection('users')
          .limit(BATCH_SIZE);

        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }

        const usersSnapshot = await query.get();

        if (usersSnapshot.empty) {
          break;
        }

        const batchUserIds = usersSnapshot.docs.map(doc => doc.id);
        
        await sendNotificationToUsers(
          batchUserIds,
          {title, body, imageUrl},
          {
            type: type || 'system',
            action: targetScreen ? 'open_screen' : 'open_notifications',
            targetScreen,
            priority: 'normal',
          }
        );

        totalSent += batchUserIds.length;
        lastDoc = usersSnapshot.docs[usersSnapshot.docs.length - 1];

        if (usersSnapshot.docs.length < BATCH_SIZE) {
          break;
        }
      }

      return {
        success: true,
        method: 'paginated',
        recipientCount: totalSent,
        message: `Notificación enviada a ${totalSent} usuario(s)`,
      };
    }
  }

  // Send to specific users
  await sendNotificationToUsers(
    recipients,
    {title, body, imageUrl},
    {
      type: type || 'system',
      action: targetScreen ? 'open_screen' : 'open_notifications',
      targetScreen,
      priority: 'normal',
    }
  );

  return {
    success: true,
    method: 'direct',
    recipientCount: recipients.length,
    message: `Notificación enviada a ${recipients.length} usuario(s)`,
  };
});

/**
 * Callable: Send broadcast notification using FCM topics
 * More efficient for mass notifications
 * 
 * @param {Object} data - { title: string, body: string, topic?: string, imageUrl?: string }
 */
exports.sendBroadcastNotification = onCall(async (request) => {
  // Verify user is authorized (support/admin)
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Usuario no autenticado');
  }

  if (!isSupportUser(request.auth)) {
    throw new HttpsError('permission-denied', 'No autorizado');
  }

  const {title, body, topic, imageUrl, type, targetScreen} = request.data;

  if (!title || !body) {
    throw new HttpsError('invalid-argument', 'title y body son requeridos');
  }

  const targetTopic = topic || 'all_users';

  const message = {
    notification: {
      title,
      body,
    },
    data: {
      type: type || 'system',
      action: targetScreen ? 'open_screen' : 'open_notifications',
      targetScreen: targetScreen || '',
    },
    topic: targetTopic,
    android: {
      priority: 'normal',
    },
    apns: {
      payload: {
        aps: {
          contentAvailable: true,
        },
      },
    },
  };

  if (imageUrl) {
    message.notification.imageUrl = imageUrl;
  }

  await admin.messaging().send(message);

  return {
    success: true,
    topic: targetTopic,
    message: `Notificación broadcast enviada al topic '${targetTopic}'`,
  };
});
