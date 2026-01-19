import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/invoice.dart';
import '../models/invoice_model.dart';

abstract class InvoicesRemoteDataSource {
  Future<InvoiceModel> createInvoice(InvoiceModel invoice);
  Future<void> updateStatus({required String invoiceId, required InvoiceStatus status});
  Future<InvoiceModel?> getById(String invoiceId);
  Future<InvoiceModel?> getByNumber(String number);
  Stream<List<InvoiceModel>> getByCustomer(String customerId, {int limit = 50});
  Stream<List<InvoiceModel>> getByRider(String riderId, {int limit = 50});
  Stream<List<InvoiceModel>> getRecent({int limit = 50});
}

class InvoicesRemoteDataSourceImpl implements InvoicesRemoteDataSource {
  final FirebaseFirestore _firestore;

  InvoicesRemoteDataSourceImpl({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection => _firestore.collection('invoices');

  @override
  Future<InvoiceModel> createInvoice(InvoiceModel invoice) async {
    final data = invoice.toJson();
    await _collection.doc(invoice.id).set(data);
    return invoice;
  }

  @override
  Future<void> updateStatus({required String invoiceId, required InvoiceStatus status}) async {
    await _collection.doc(invoiceId).update({
      'status': status.name,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  @override
  Future<InvoiceModel?> getById(String invoiceId) async {
    final snap = await _collection.doc(invoiceId).get();
    if (!snap.exists) return null;
    return InvoiceModel.fromJson(snap.data()!);
  }

  @override
  Future<InvoiceModel?> getByNumber(String number) async {
    final query = await _collection.where('number', isEqualTo: number).limit(1).get();
    if (query.docs.isEmpty) return null;
    return InvoiceModel.fromJson(query.docs.first.data());
  }

  @override
  Stream<List<InvoiceModel>> getByCustomer(String customerId, {int limit = 50}) {
    return _collection
        .where('customerId', isEqualTo: customerId)
        .orderBy('issueDate', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => InvoiceModel.fromJson(d.data())).toList());
  }

  @override
  Stream<List<InvoiceModel>> getByRider(String riderId, {int limit = 50}) {
    return _collection
        .where('riderId', isEqualTo: riderId)
        .orderBy('issueDate', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => InvoiceModel.fromJson(d.data())).toList());
  }

  @override
  Stream<List<InvoiceModel>> getRecent({int limit = 50}) {
    return _collection
        .orderBy('issueDate', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => InvoiceModel.fromJson(d.data())).toList());
  }
}
