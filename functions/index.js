const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

/**
 * Asigna un pedido a un rider de forma segura
 * Valida: rider verificado, compatibilidad de vehículo, estado del pedido
 * 
 * @param {Object} data - { orderId: string }
 * @param {Object} context - Firebase auth context
 * @returns {Promise<Object>} - { success: boolean, orderId: string, message: string }
 */
exports.claimOrder = functions.https.onCall(async (data, context) => {
  // ==========================================
  // 1. VALIDAR AUTENTICACIÓN
  // ==========================================
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Usuario no autenticado'
    );
  }

  const riderId = context.auth.uid;
  const orderId = data.orderId;

  if (!orderId) {
    throw new functions.https.HttpsError(
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
    throw new functions.https.HttpsError(
      'not-found',
      'Rider no encontrado'
    );
  }

  const riderData = riderDoc.data();
  const riderProfile = riderData.riderProfile;

  // Validar que el usuario tenga rol de rider
  if (!riderData.roles || !riderData.roles.includes('rider')) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'No tienes permisos de rider'
    );
  }

  // ==========================================
  // 3. VALIDAR RIDER VERIFICADO (CRÍTICO)
  // ==========================================
  if (!riderProfile || !riderProfile.isVerified) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Tu cuenta debe estar verificada para tomar pedidos'
    );
  }

  if (!riderProfile.isActive) {
    throw new functions.https.HttpsError(
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
      throw new functions.https.HttpsError(
        'not-found',
        'Pedido no encontrado'
      );
    }

    const order = orderDoc.data();

    // Validar estado
    if (order.status !== 'queued') {
      throw new functions.https.HttpsError(
        'failed-precondition',
        `Pedido ya no está disponible (estado: ${order.status})`
      );
    }

    if (order.rider && order.rider.assignedRiderId) {
      throw new functions.https.HttpsError(
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
      throw new functions.https.HttpsError(
        'failed-precondition',
        `Tu vehículo (${riderVehicle}) no es compatible con este pedido (requiere ${requiredVehicle})`
      );
    }

    // Validar peso (si existe límite en el perfil)
    if (riderProfile.limits && riderProfile.limits.maxWeightKg) {
      if (order.requirements.weightKg > riderProfile.limits.maxWeightKg) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          `El peso del pedido (${order.requirements.weightKg}kg) excede tu capacidad (${riderProfile.limits.maxWeightKg}kg)`
        );
      }
    }

    // Validar distancia (si existe límite en el perfil)
    if (riderProfile.limits && riderProfile.limits.maxDistanceKm) {
      if (order.requirements.estimatedDistanceKm > riderProfile.limits.maxDistanceKm) {
        throw new functions.https.HttpsError(
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
exports.updateOrderStatus = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Usuario no autenticado');
  }

  const { orderId, newStatus } = data;
  const riderId = context.auth.uid;

  if (!orderId || !newStatus) {
    throw new functions.https.HttpsError('invalid-argument', 'orderId y newStatus son requeridos');
  }

  // Estados válidos para actualización por rider
  const validStatuses = ['picked_up', 'in_transit', 'delivered'];
  if (!validStatuses.includes(newStatus)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `Estado inválido. Debe ser uno de: ${validStatuses.join(', ')}`
    );
  }

  const orderRef = admin.firestore().collection('orders').doc(orderId);
  const orderDoc = await orderRef.get();

  if (!orderDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Pedido no encontrado');
  }

  const order = orderDoc.data();

  // Validar que el rider sea el asignado
  if (!order.rider || order.rider.assignedRiderId !== riderId) {
    throw new functions.https.HttpsError(
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
    throw new functions.https.HttpsError(
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
