import 'package:cloud_firestore/cloud_firestore.dart';

import '../dtos/invoice_dto.dart';

class BillingFirestoreDataSource {
  final FirebaseFirestore _firestore;

  BillingFirestoreDataSource({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('invoices');

  Stream<InvoiceDto?> watchByOrderId(String orderId) {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) {
      return Stream.value(null);
    }

    // Invoices are stored with documentId == orderId, which allows `get`
    // access under current security rules without requiring a list query.
    return _collection
        .doc(normalizedOrderId)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          if (!snapshot.exists || data == null) return null;
          return InvoiceDto.fromFirestore(data, docId: snapshot.id);
        });
  }

  Future<InvoiceDto?> getByOrderId(String orderId) async {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return null;

    final snapshot = await _collection.doc(normalizedOrderId).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return InvoiceDto.fromFirestore(data, docId: snapshot.id);
  }
}
