import '../../domain/entities/invoice.dart';
import '../../domain/repositories/invoices_repository.dart';
import '../datasources/invoices_remote_data_source.dart';
import '../models/invoice_model.dart';

class InvoicesRepositoryImpl implements InvoicesRepository {
  final InvoicesRemoteDataSource _remote;

  InvoicesRepositoryImpl({required InvoicesRemoteDataSource remote}) : _remote = remote;

  @override
  Future<Invoice> createInvoice(Invoice invoice) async {
    final model = InvoiceModel.fromEntity(invoice);
    final created = await _remote.createInvoice(model);
    return created.toEntity();
  }

  @override
  Future<void> updateStatus({required String invoiceId, required InvoiceStatus status}) {
    return _remote.updateStatus(invoiceId: invoiceId, status: status);
  }

  @override
  Future<Invoice?> getById(String invoiceId) async {
    final model = await _remote.getById(invoiceId);
    return model?.toEntity();
  }

  @override
  Future<Invoice?> getByNumber(String number) async {
    final model = await _remote.getByNumber(number);
    return model?.toEntity();
  }

  @override
  Stream<List<Invoice>> getByCustomer(String customerId, {int limit = 50}) {
    return _remote
        .getByCustomer(customerId, limit: limit)
        .map((models) => models.map((m) => m.toEntity()).toList());
  }

  @override
  Stream<List<Invoice>> getByRider(String riderId, {int limit = 50}) {
    return _remote
        .getByRider(riderId, limit: limit)
        .map((models) => models.map((m) => m.toEntity()).toList());
  }

  @override
  Stream<List<Invoice>> getRecent({int limit = 50}) {
    return _remote
        .getRecent(limit: limit)
        .map((models) => models.map((m) => m.toEntity()).toList());
  }
}
