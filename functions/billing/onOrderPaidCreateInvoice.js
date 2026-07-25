/* eslint-disable require-jsdoc */
const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');
const crypto = require('crypto');
const {
  createDocument,
  issueDocument,
  getDocumentStatus,
  downloadDocumentFile,
} = require('./wasabilService');
const {isDevCheckoutBypassEnabled} = require('../devMode');

const BILLING_REGION = 'southamerica-west1';
const WASABIL_STATUS = {
  processing: 2,
  issued: 3,
  failed: 4,
  pending: 6,
};

function _readString(value) {
  if (typeof value !== 'string') return '';
  return value.trim();
}

function _toLower(value) {
  return _readString(value).toLowerCase();
}

function _asNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

function _toMoneyInt(value) {
  return Math.max(0, Math.round(_asNumber(value)));
}

function _firstNonEmpty(...values) {
  for (const value of values) {
    const normalized = _readString(value);
    if (normalized) return normalized;
  }
  return '';
}

function _firstFiniteNumber(...values) {
  for (const value of values) {
    const number = Number(value);
    if (Number.isFinite(number)) return number;
  }
  return 0;
}

function _normalizeDocumentType(order) {
  return _toLower(order?.billing?.documentType) ||
    _toLower(order?.documentType) ||
    'boleta';
}

function _isSupportedDocumentType(value) {
  return value === 'factura' || value === 'boleta';
}

function _isPaidByPaymentStatus(order) {
  const status = _toLower(order?.paymentStatus);
  return status === 'approved' || status === 'paid';
}

function _isPaidTransition(before, after) {
  if (!after) return false;
  if (!_isPaidByPaymentStatus(before) && _isPaidByPaymentStatus(after)) {
    return true;
  }

  const beforeStatus = _toLower(before?.status);
  const afterStatus = _toLower(after?.status);
  if (beforeStatus === 'pending_payment' && afterStatus === 'queued') {
    return true;
  }
  return afterStatus === 'queued' && (!before || beforeStatus === 'created');
}

function _safeIsoDate(value) {
  if (value?.toDate instanceof Function) {
    return value.toDate().toISOString().slice(0, 10);
  }
  const date = value ? new Date(value) : new Date();
  return Number.isNaN(date.getTime()) ?
    new Date().toISOString().slice(0, 10) :
    date.toISOString().slice(0, 10);
}

function _normalizeRut(value) {
  const raw = _readString(value)
      .toUpperCase()
      .replace(/\s+/g, '')
      .replace(/\./g, '')
      .replace(/[^0-9K-]/g, '');
  if (!raw) return '';
  if (raw.includes('-')) {
    const [body, dv] = raw.split('-');
    return body && dv ? `${body}-${dv}` : '';
  }
  return raw.length >= 2 ? `${raw.slice(0, -1)}-${raw.slice(-1)}` : '';
}

function _computeRutDv(body) {
  let sum = 0;
  let multiplier = 2;
  for (let i = body.length - 1; i >= 0; i--) {
    sum += Number(body[i]) * multiplier;
    multiplier = multiplier === 7 ? 2 : multiplier + 1;
  }
  const remainder = 11 - (sum % 11);
  if (remainder === 11) return '0';
  if (remainder === 10) return 'K';
  return String(remainder);
}

function _hasValidRut(rut) {
  if (!/^\d{7,8}-[0-9K]$/.test(rut)) return false;
  const [body, dv] = rut.split('-');
  return _computeRutDv(body) === dv;
}

function _requireFacturaField(order, key, label) {
  const value = _readString(order?.[key]);
  if (!value) throw new Error(`Missing required factura field: ${label}`);
  return value;
}

function _toMaxLength(value, maxLength) {
  return _readString(value).slice(0, maxLength);
}

function _inferReceiverLocation(order, address, type) {
  const isComuna = type === 'comuna';
  const explicit = _firstNonEmpty(
    isComuna ? order?.invoiceComuna : order?.invoiceCity,
    order?.invoiceCommune,
    order?.invoiceDistrict,
    process.env[isComuna ?
      'WASABIL_DEFAULT_RECEPTOR_COMUNA' :
      'WASABIL_DEFAULT_RECEPTOR_CIUDAD'],
    process.env[isComuna ?
      'SIMPLEAPI_DEFAULT_RECEPTOR_COMUNA' :
      'SIMPLEAPI_DEFAULT_RECEPTOR_CIUDAD'],
  );
  if (explicit) return explicit;

  const parts = _readString(address)
      .split(',')
      .map((part) => part.trim())
      .filter(Boolean);
  return parts.length >= 2 ? parts[parts.length - 1] : 'Santiago';
}

function _resolvePaymentMethod(order) {
  const explicit = Math.round(_asNumber(
      order?.invoiceFormaPago || order?.billing?.formaPago,
  ));
  if (explicit === 2) return 'credito';

  const description = _toLower(_firstNonEmpty(
      order?.paymentMethodLabel,
      order?.paymentMethodName,
      order?.paymentMethodId,
      order?.paymentMethod,
      order?.payment?.paymentMethodLabel,
      order?.payment?.paymentMethodName,
      order?.payment?.paymentMethodId,
      order?.payment?.paymentMethod,
      order?.payment?.method,
  ));
  return description.includes('credito') || description.includes('credit') ?
    'credito' :
    'contado';
}

function _buildProductDetails(order) {
  const items = Array.isArray(order?.items) ? order.items : [];
  const productDetails = [];

  for (let index = 0; index < items.length; index++) {
    const item = items[index] || {};
    const quantity = Math.max(0, _firstFiniteNumber(
        item?.qty,
        item?.quantity,
        item?.cantidad,
    ));
    let price = Math.max(0, _firstFiniteNumber(
        item?.unitPriceSnapshot,
        item?.unitPrice,
        item?.unit_price,
        item?.price,
        item?.valorUnitario,
    ));
    const lineTotal = Math.max(0, _firstFiniteNumber(
        item?.lineTotalSnapshot,
        item?.lineTotal,
        item?.totalPriceSnapshot,
        item?.totalPrice,
        item?.total,
        item?.amount,
    ));
    if (quantity <= 0) continue;
    if (price <= 0 && lineTotal > 0) price = lineTotal / quantity;
    if (price <= 0) continue;

    const name = _toMaxLength(_firstNonEmpty(
        item?.titleSnapshot,
        item?.title,
        item?.name,
        item?.description,
        `Item ${index + 1}`,
    ), 80);
    productDetails.push({
      name,
      description: name,
      quantity,
      price,
      discount: 0,
    });
  }

  return productDetails;
}

function _buildWasabilDetails(order) {
  const productDetails = _buildProductDetails(order);
  const deliveryFee = _toMoneyInt(_firstFiniteNumber(
      order?.deliveryFee,
      order?.shippingCost,
      order?.shippingFee,
  ));
  const serviceFee = _toMoneyInt(_firstFiniteNumber(
      order?.serviceFee,
      order?.platformFee,
  ));
  const productNet = Math.round(productDetails.reduce(
      (total, detail) => total + (detail.price * detail.quantity),
      0,
  ));
  const feeNet = deliveryFee + serviceFee;
  const totalNet = productNet + feeNet;
  if (totalNet <= 0) throw new Error('Order has no billable items');

  const configuredSubtotal = _toMoneyInt(order?.subtotal);
  if (configuredSubtotal > 0 && Math.abs(configuredSubtotal - productNet) > 1) {
    throw new Error(
        `Invoice subtotal mismatch: order=${configuredSubtotal}, details=${productNet}`,
    );
  }

  const tax = _toMoneyInt(order?.tax);
  const feeTax = Math.round(feeNet * 0.19);
  const allTax = Math.round(totalNet * 0.19);
  let productsAreExempt;
  if (tax === feeTax) {
    productsAreExempt = true;
  } else if (tax === allTax) {
    productsAreExempt = false;
  } else {
    throw new Error(
        `Invoice IVA mismatch: order=${tax}, fees=${feeTax}, all=${allTax}`,
    );
  }

  const details = productDetails.map((detail) => ({
    ...detail,
    exempt: productsAreExempt,
  }));
  if (deliveryFee > 0) {
    details.push({
      name: 'Costo de envio',
      description: 'Tarifa de entrega',
      quantity: 1,
      price: deliveryFee,
      discount: 0,
    });
  }
  if (serviceFee > 0) {
    details.push({
      name: 'Tarifa de servicio',
      description: 'Comision de plataforma',
      quantity: 1,
      price: serviceFee,
      discount: 0,
    });
  }

  const totalWithoutTip = Math.max(
      0,
      _toMoneyInt(order?.amountTotal) - _toMoneyInt(order?.tip),
  );
  const expectedTotal = totalNet + tax;
  if (totalWithoutTip > 0 && Math.abs(totalWithoutTip - expectedTotal) > 1) {
    throw new Error(
        `Invoice total mismatch: order=${totalWithoutTip}, details=${expectedTotal}`,
    );
  }

  return details;
}

function _buildWasabilReceiptDetails(order) {
  const details = _buildProductDetails(order);
  const deliveryFee = _toMoneyInt(_firstFiniteNumber(
      order?.deliveryFee,
      order?.shippingCost,
      order?.shippingFee,
  ));
  const serviceFee = _toMoneyInt(_firstFiniteNumber(
      order?.serviceFee,
      order?.platformFee,
  ));
  const tax = _toMoneyInt(order?.tax);
  const feeNet = deliveryFee + serviceFee;
  const deliveryTax = feeNet > 0 ?
    Math.round(tax * deliveryFee / feeNet) :
    0;
  const serviceTax = tax - deliveryTax;

  if (deliveryFee > 0) {
    details.push({
      name: 'Costo de envio',
      description: 'Tarifa de entrega',
      quantity: 1,
      price: deliveryFee + deliveryTax,
      discount: 0,
    });
  }
  if (serviceFee > 0) {
    details.push({
      name: 'Tarifa de servicio',
      description: 'Comision de plataforma',
      quantity: 1,
      price: serviceFee + serviceTax,
      discount: 0,
    });
  }
  if (details.length === 0) throw new Error('Order has no billable items');

  const totalWithoutTip = Math.max(
      0,
      _toMoneyInt(order?.amountTotal) - _toMoneyInt(order?.tip),
  );
  const detailsTotal = details.reduce(
      (total, detail) => total + (detail.price * detail.quantity),
      0,
  );
  const adjustment = totalWithoutTip - detailsTotal;
  if (Math.abs(adjustment) > 1) {
    const last = details[details.length - 1];
    last.price += adjustment / last.quantity;
  }

  const finalTotal = details.reduce(
      (total, detail) => total + (detail.price * detail.quantity),
      0,
  );
  if (Math.abs(finalTotal - totalWithoutTip) > 1) {
    throw new Error(
        `Receipt total mismatch: order=${totalWithoutTip}, details=${finalTotal}`,
    );
  }
  return details;
}

function _buildWasabilPayload({order, invoiceId}) {
  const documentType = _normalizeDocumentType(order);
  if (!_isSupportedDocumentType(documentType)) {
    throw new Error(`Unsupported document type: ${documentType}`);
  }
  const currency = (_readString(order?.currency) || 'CLP').toUpperCase();
  if (!['CLP', 'USD', 'UF'].includes(currency)) {
    throw new Error(`Unsupported invoice currency: ${currency}`);
  }
  const common = {
    currency_symbol: currency,
    invoice_reference: invoiceId,
    issue: false,
    origin: _readString(process.env.WASABIL_ORIGIN) || 'THE HERO',
  };

  if (documentType === 'boleta') {
    return {
      ...common,
      sii_document_type_id: 39,
      price_includes_iva: true,
      receiver_input: 'none',
      details: _buildWasabilReceiptDetails(order),
    };
  }

  const rut = _normalizeRut(_requireFacturaField(order, 'invoiceRut', 'RUT'));
  if (!_hasValidRut(rut)) throw new Error('Invalid RUT for factura receptor');
  const address = _requireFacturaField(order, 'invoiceAddress', 'Direccion');

  return {
    ...common,
    sii_document_type_id: 33,
    payment_method: _resolvePaymentMethod(order),
    price_includes_iva: false,
    receiver_rut: rut,
    receiver_name: _requireFacturaField(
        order,
        'invoiceBusinessName',
        'Razon social',
    ),
    receiver_address: address,
    receiver_comuna: _inferReceiverLocation(order, address, 'comuna'),
    receiver_city: _inferReceiverLocation(order, address, 'city'),
    receiver_giro: _requireFacturaField(order, 'invoiceGiro', 'Giro'),
    ...(_readString(order?.invoiceEmail) ?
      {receiver_email: _readString(order.invoiceEmail)} :
      {}),
    details: _buildWasabilDetails(order),
    document_date: _safeIsoDate(
        order?.timestamps?.paidAt || order?.updatedAt,
    ),
  };
}

function _canAccessInvoice(auth, invoiceData) {
  if (!auth) return false;
  if (auth.token?.admin === true || auth.token?.support === true) return true;
  const uid = _readString(auth.uid);
  return uid && [
    _readString(invoiceData?.payerUserId),
    _readString(invoiceData?.sellerUserId),
  ].includes(uid);
}

function _providerFields(document) {
  return {
    provider: 'wasabil',
    providerDocumentId: _readString(document?.uuid),
    providerTrackId: _readString(document?.issuer_reference) || null,
    providerReceivedAt: _readString(document?.status_updated_at) || null,
    providerStatusCode: document?.status_id == null ?
      null :
      String(document.status_id),
    providerMeta: {
      wasabilDocument: document?.document || null,
      wasabilStatusName: _readString(document?.status_name) || null,
    },
  };
}

function _outputBucket() {
  const bucketName = _readString(process.env.WASABIL_OUTPUT_BUCKET) ||
    _readString(process.env.SIMPLEAPI_OUTPUT_BUCKET);
  return bucketName ? admin.storage().bucket(bucketName) : admin.storage().bucket();
}

async function _saveIssuedFiles(invoiceId, providerDocumentId) {
  const [pdf, xml] = await Promise.all([
    downloadDocumentFile(providerDocumentId, 'pdf'),
    downloadDocumentFile(providerDocumentId, 'origXml'),
  ]);
  const bucket = _outputBucket();
  const pdfPath = `invoices/${invoiceId}/invoice.pdf`;
  const xmlPath = `invoices/${invoiceId}/dte.xml`;
  await Promise.all([
    bucket.file(pdfPath).save(pdf, {
      resumable: false,
      contentType: 'application/pdf',
      metadata: {cacheControl: 'private, max-age=0, no-store'},
    }),
    bucket.file(xmlPath).save(xml, {
      resumable: false,
      contentType: 'application/xml',
      metadata: {cacheControl: 'private, max-age=0, no-store'},
    }),
  ]);
  return {
    pdfPath,
    xmlPath,
    pdfUrl: `gs://${bucket.name}/${pdfPath}`,
    xmlUrl: `gs://${bucket.name}/${xmlPath}`,
  };
}

async function _syncWasabilDocument({invoiceRef, orderRef, invoiceData, document}) {
  const status = Math.round(_asNumber(document?.status_id));
  const documentType = _isSupportedDocumentType(_toLower(invoiceData?.documentType)) ?
    _toLower(invoiceData.documentType) :
    (Math.round(_asNumber(document?.sii_document_type_id)) === 39 ?
      'boleta' :
      'factura');
  const providerDocumentId = _readString(document?.uuid) ||
    _readString(invoiceData?.providerDocumentId);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const providerFields = _providerFields({...document, uuid: providerDocumentId});

  if (status === WASABIL_STATUS.issued) {
    const files = await _saveIssuedFiles(invoiceRef.id, providerDocumentId);
    const folioNumber = Number(document?.folio);
    const folio = Number.isFinite(folioNumber) ? folioNumber : document?.folio || null;
    await invoiceRef.set({
      status: 'issued',
      ...providerFields,
      folio,
      folioRangeFrom: null,
      folioRangeTo: null,
      ...files,
      issuedAt: now,
      updatedAt: now,
      errorCode: null,
      errorMessage: null,
    }, {merge: true});
    await orderRef.set({
      billing: {
        documentType,
        requestedByUserId: _readString(invoiceData?.payerUserId) || null,
        invoiceId: invoiceRef.id,
        invoiceFolio: folio,
        invoiceStatus: 'issued',
        updatedAt: now,
      },
    }, {merge: true});
    return 'issued';
  }

  if (status === WASABIL_STATUS.failed) {
    const message = _firstNonEmpty(
        document?.display_error,
        document?.error,
        'Wasabil no pudo emitir el documento',
    );
    await invoiceRef.set({
      status: 'failed',
      ...providerFields,
      errorCode: _readString(document?.error_code) || 'emission_failed',
      errorMessage: message.slice(0, 2000),
      updatedAt: now,
    }, {merge: true});
    await orderRef.set({
      billing: {
        documentType,
        requestedByUserId: _readString(invoiceData?.payerUserId) || null,
        invoiceId: invoiceRef.id,
        invoiceStatus: 'failed',
        updatedAt: now,
      },
    }, {merge: true});
    return 'failed';
  }

  await invoiceRef.set({
    status: 'pending',
    ...providerFields,
    updatedAt: now,
    errorCode: null,
    errorMessage: null,
  }, {merge: true});
  await orderRef.set({
    billing: {
      documentType,
      requestedByUserId: _readString(invoiceData?.payerUserId) || null,
      invoiceId: invoiceRef.id,
      invoiceStatus: 'pending',
      updatedAt: now,
    },
  }, {merge: true});
  return 'pending';
}

async function _startOrResumeEmission({invoiceRef, orderRef, invoiceData, order}) {
  let providerDocumentId = _toLower(invoiceData?.provider) === 'wasabil' ?
    _readString(invoiceData?.providerDocumentId) :
    '';
  let document;

  if (providerDocumentId) {
    document = await getDocumentStatus(providerDocumentId);
    const status = Math.round(_asNumber(document?.status_id));
    if ([WASABIL_STATUS.processing, WASABIL_STATUS.issued].includes(status)) {
      return _syncWasabilDocument({
        invoiceRef,
        orderRef,
        invoiceData,
        document: {...document, uuid: providerDocumentId},
      });
    }
  } else {
    document = await createDocument(_buildWasabilPayload({
      order,
      invoiceId: invoiceRef.id,
    }));
    providerDocumentId = _readString(document?.uuid);
    if (!providerDocumentId) {
      throw new Error('Wasabil create response did not include uuid');
    }
    await invoiceRef.set({
      ..._providerFields(document),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  const issuedDocument = await issueDocument(providerDocumentId);
  return _syncWasabilDocument({
    invoiceRef,
    orderRef,
    invoiceData: {...invoiceData, providerDocumentId},
    document: {...issuedDocument, uuid: providerDocumentId},
  });
}

async function _markLocalFailure({invoiceRef, orderRef, invoiceData, error}) {
  const message = _readString(error?.message) || 'Unknown billing error';
  const documentType = _isSupportedDocumentType(_toLower(invoiceData?.documentType)) ?
    _toLower(invoiceData.documentType) :
    'boleta';
  const now = admin.firestore.FieldValue.serverTimestamp();
  await invoiceRef.set({
    status: 'failed',
    errorCode: 'emission_failed',
    errorMessage: message.slice(0, 2000),
    retryCount: admin.firestore.FieldValue.increment(1),
    updatedAt: now,
  }, {merge: true});
  await orderRef.set({
    billing: {
      documentType,
      requestedByUserId: _readString(invoiceData?.payerUserId) || null,
      invoiceId: invoiceRef.id,
      invoiceStatus: 'failed',
      updatedAt: now,
    },
  }, {merge: true});
  return message;
}

function _secureEqual(left, right) {
  const leftBuffer = Buffer.from(_readString(left));
  const rightBuffer = Buffer.from(_readString(right));
  return leftBuffer.length === rightBuffer.length &&
    crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function _webhookSecret(authorization) {
  const value = _readString(authorization);
  return value.toLowerCase().startsWith('bearer ') ? value.slice(7).trim() : value;
}

exports.wasabilInvoiceWebhook = onRequest(
    {
      region: BILLING_REGION,
      cors: false,
      secrets: [],
    },
    async (request, response) => {
      if (request.method !== 'POST') {
        return response.status(405).send('Method not allowed');
      }

      const expectedSecret = _readString(process.env.WASABIL_WEBHOOK_SECRET);
      const providedSecret = _webhookSecret(request.get('authorization'));
      if (!expectedSecret) {
        logger.error('WASABIL_WEBHOOK_SECRET is not configured');
        return response.status(503).send('Webhook not configured');
      }
      if (!_secureEqual(expectedSecret, providedSecret)) {
        return response.status(401).send('Unauthorized');
      }

      try {
        const document = request.body?.data || request.body || {};
        if (![33, 39].includes(
            Math.round(_asNumber(document?.sii_document_type_id)),
        )) {
          return response.status(204).send();
        }

        const db = admin.firestore();
        const invoiceId = _readString(document?.invoice_reference);
        let invoiceRef = invoiceId ? db.collection('invoices').doc(invoiceId) : null;
        let invoiceSnap = invoiceRef ? await invoiceRef.get() : null;
        if (!invoiceSnap?.exists) {
          const uuid = _readString(document?.uuid);
          if (!uuid) return response.status(204).send();
          const matches = await db.collection('invoices')
              .where('providerDocumentId', '==', uuid)
              .limit(1)
              .get();
          if (matches.empty) return response.status(204).send();
          invoiceSnap = matches.docs[0];
          invoiceRef = invoiceSnap.ref;
        }

        const invoiceData = invoiceSnap.data() || {};
        const providerDocumentId = _readString(invoiceData?.providerDocumentId);
        if (
          providerDocumentId &&
        providerDocumentId !== _readString(document?.uuid)
        ) {
          return response.status(409).send('Document mismatch');
        }
        const orderId = _readString(invoiceData?.orderId);
        if (!orderId) return response.status(409).send('Missing orderId');

        await _syncWasabilDocument({
          invoiceRef,
          orderRef: db.collection('orders').doc(orderId),
          invoiceData,
          document,
        });
        return response.status(204).send();
      } catch (error) {
        logger.error('Wasabil invoice webhook failed', {
          message: _readString(error?.message),
          stack: _readString(error?.stack).slice(0, 4000),
        });
        return response.status(500).send('Internal error');
      }
    },
);

exports.retryInvoiceEmission = onCall(
    {region: 'us-central1', secrets: []},
    async (request) => {
      if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Debes iniciar sesion para continuar');
      }

      const invoiceId = _readString(request.data?.invoiceId);
      if (!invoiceId) {
        throw new HttpsError('invalid-argument', 'invoiceId es requerido');
      }

      const db = admin.firestore();
      const invoiceRef = db.collection('invoices').doc(invoiceId);
      const invoiceSnap = await invoiceRef.get();
      if (!invoiceSnap.exists) {
        throw new HttpsError('not-found', 'Documento tributario no encontrado');
      }

      const invoiceData = invoiceSnap.data() || {};
      if (!_canAccessInvoice(request.auth, invoiceData)) {
        throw new HttpsError(
            'permission-denied',
            'No tienes permisos para reintentar este documento',
        );
      }

      const orderId = _readString(invoiceData?.orderId);
      const orderRef = db.collection('orders').doc(orderId);
      const orderSnap = await orderRef.get();
      if (!orderSnap.exists) {
        throw new HttpsError('not-found', 'Pedido asociado no encontrado');
      }
      const order = orderSnap.data() || {};
      if (!_isSupportedDocumentType(_normalizeDocumentType(order))) {
        throw new HttpsError(
            'failed-precondition',
            'El pedido no esta configurado para un documento tributario',
        );
      }

      const currentStatus = _toLower(invoiceData?.status);
      if (currentStatus === 'issued' && _readString(invoiceData?.pdfPath)) {
        return {invoiceId, orderId, status: 'issued', alreadyIssued: true};
      }
      if (currentStatus !== 'failed') {
        throw new HttpsError(
            'failed-precondition',
            `Solo se puede reintentar documentos en failed. Estado actual: ${currentStatus || 'unknown'}`,
        );
      }

      await invoiceRef.set({
        status: 'pending',
        errorCode: null,
        errorMessage: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});

      try {
        const status = await _startOrResumeEmission({
          invoiceRef,
          orderRef,
          invoiceData,
          order,
        });
        return {invoiceId, orderId, status};
      } catch (error) {
        const message = await _markLocalFailure({
          invoiceRef,
          orderRef,
          invoiceData,
          error,
        });
        logger.error('Retry invoice emission failed', {
          orderId,
          invoiceId,
          message,
        });
        throw new HttpsError('internal', message);
      }
    },
);

exports.onOrderPaidCreateInvoice = onDocumentWritten(
    {
      document: 'orders/{orderId}',
      region: BILLING_REGION,
      secrets: [],
    },
    async (event) => {
      const before = event.data?.before?.exists ? event.data.before.data() : null;
      const after = event.data?.after?.exists ? event.data.after.data() : null;
      if (!after || !_isPaidTransition(before, after)) {
        return;
      }
      const orderId = _readString(event.params?.orderId) ||
      _readString(after?.orderId);
      if (!orderId) return;

      if (isDevCheckoutBypassEnabled()) {
        logger.info('DEV_CHECKOUT_BYPASS enabled; skipping invoice emission', {
          orderId,
        });
        return;
      }

      const documentType = _normalizeDocumentType(after);
      if (!_isSupportedDocumentType(documentType)) {
        return;
      }

      const db = admin.firestore();
      const invoiceRef = db.collection('invoices').doc(orderId);
      const existing = await invoiceRef.get();
      if (existing.exists) {
        logger.info('Invoice already exists for order', {orderId});
        return;
      }

      const now = admin.firestore.FieldValue.serverTimestamp();
      const payerUserId = _readString(after?.heroId);
      const sellerUserId = Array.isArray(after?.sellerHeroIds) ?
      _readString(after.sellerHeroIds[0]) :
      '';
      const invoiceData = {
        invoiceId: invoiceRef.id,
        orderId,
        payerUserId,
        sellerUserId: sellerUserId || null,
        documentType,
        currency: _readString(after?.currency) || 'CLP',
        subtotal: _asNumber(after?.subtotal),
        taxAmount: _asNumber(after?.tax),
        total: _asNumber(after?.amountTotal),
        status: 'pending',
        provider: 'wasabil',
        providerDocumentId: null,
        providerTrackId: null,
        providerReceivedAt: null,
        providerStatusCode: null,
        folio: null,
        folioRangeFrom: null,
        folioRangeTo: null,
        pdfPath: null,
        pdfUrl: null,
        xmlPath: null,
        xmlUrl: null,
        errorCode: null,
        errorMessage: null,
        retryCount: 0,
        issuedAt: null,
        createdAt: now,
        updatedAt: now,
      };

      try {
        await invoiceRef.create(invoiceData);
      } catch (error) {
        if (Number(error?.code) === 6 || _readString(error?.code) === 'already-exists') {
          logger.info('Invoice was created by another trigger invocation', {orderId});
          return;
        }
        throw error;
      }
      const orderRef = db.collection('orders').doc(orderId);
      await orderRef.set({
        billing: {
          documentType,
          requestedByUserId: payerUserId || null,
          invoiceId: invoiceRef.id,
          invoiceStatus: 'pending',
          updatedAt: now,
        },
      }, {merge: true});

      try {
        const status = await _startOrResumeEmission({
          invoiceRef,
          orderRef,
          invoiceData,
          order: after,
        });
        logger.info('Wasabil fiscal document submitted', {
          orderId,
          invoiceId: invoiceRef.id,
          status,
        });
      } catch (error) {
        const message = await _markLocalFailure({
          invoiceRef,
          orderRef,
          invoiceData,
          error,
        });
        logger.error('Fiscal document emission failed', {
          orderId,
          invoiceId: invoiceRef.id,
          message,
          stack: _readString(error?.stack).slice(0, 4000),
        });
      }
    },
);

module.exports.__test = {
  _buildWasabilPayload,
  _buildWasabilDetails,
  _buildWasabilReceiptDetails,
  _webhookSecret,
};
