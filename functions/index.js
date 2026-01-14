const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onObjectFinalized} = require('firebase-functions/v2/storage');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const sharp = require('sharp');
const path = require('path');
const os = require('os');
const fs = require('fs');
admin.initializeApp();

const STORAGE_REGION = 'southamerica-west1';

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

function buildDownloadUrl(bucketName, filePath) {
  const encodedPath = encodeURIComponent(filePath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedPath}?alt=media`;
}
