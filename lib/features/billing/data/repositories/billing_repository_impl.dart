import '../../domain/entities/invoice_entity.dart';
import '../../domain/repositories/billing_repository.dart';
import '../datasources/billing_firestore_datasource.dart';
import '../datasources/billing_functions_datasource.dart';

class BillingRepositoryImpl implements BillingRepository {
  final BillingFirestoreDataSource _firestoreDataSource;
  final BillingFunctionsDataSource _functionsDataSource;

  BillingRepositoryImpl({
    required BillingFirestoreDataSource firestoreDataSource,
    required BillingFunctionsDataSource functionsDataSource,
  }) : _firestoreDataSource = firestoreDataSource,
       _functionsDataSource = functionsDataSource;

  @override
  Stream<BillingInvoiceEntity?> watchInvoiceByOrderId(String orderId) {
    return _firestoreDataSource
        .watchByOrderId(orderId)
        .map((dto) => dto?.toEntity());
  }

  @override
  Future<BillingInvoiceEntity?> getInvoiceByOrderId(String orderId) async {
    final dto = await _firestoreDataSource.getByOrderId(orderId);
    return dto?.toEntity();
  }

  @override
  Future<String> getInvoiceDownloadLink(String invoiceId) {
    return _functionsDataSource.getInvoiceDownloadLink(invoiceId);
  }

  @override
  Future<void> retryInvoiceEmission(String invoiceId) {
    return _functionsDataSource.retryInvoiceEmission(invoiceId);
  }
}
