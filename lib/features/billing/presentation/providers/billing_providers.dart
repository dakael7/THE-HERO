import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/billing_firestore_datasource.dart';
import '../../data/datasources/billing_functions_datasource.dart';
import '../../data/repositories/billing_repository_impl.dart';
import '../../domain/entities/invoice_entity.dart';
import '../../domain/repositories/billing_repository.dart';
import '../../domain/usecases/get_invoice_by_order_usecase.dart';
import '../../domain/usecases/get_invoice_pdf_url_usecase.dart';
import '../../domain/usecases/retry_invoice_emission_usecase.dart';

final billingFirestoreDataSourceProvider = Provider<BillingFirestoreDataSource>(
  (ref) => BillingFirestoreDataSource(),
);

final billingFunctionsDataSourceProvider = Provider<BillingFunctionsDataSource>(
  (ref) => BillingFunctionsDataSource(),
);

final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  return BillingRepositoryImpl(
    firestoreDataSource: ref.watch(billingFirestoreDataSourceProvider),
    functionsDataSource: ref.watch(billingFunctionsDataSourceProvider),
  );
});

final getInvoiceByOrderUseCaseProvider = Provider<GetInvoiceByOrderUseCase>((
  ref,
) {
  return GetInvoiceByOrderUseCase(ref.watch(billingRepositoryProvider));
});

final getInvoicePdfUrlUseCaseProvider = Provider<GetInvoicePdfUrlUseCase>((
  ref,
) {
  return GetInvoicePdfUrlUseCase(ref.watch(billingRepositoryProvider));
});

final retryInvoiceEmissionUseCaseProvider =
    Provider<RetryInvoiceEmissionUseCase>((ref) {
      return RetryInvoiceEmissionUseCase(ref.watch(billingRepositoryProvider));
    });

final invoiceByOrderIdProvider =
    StreamProvider.family<BillingInvoiceEntity?, String>((ref, orderId) {
      final useCase = ref.watch(getInvoiceByOrderUseCaseProvider);
      return useCase.watch(orderId);
    });

class BillingDownloadState {
  final bool isLoading;
  final String? url;
  final String? error;

  const BillingDownloadState({
    this.isLoading = false,
    this.url,
    this.error,
  });

  BillingDownloadState copyWith({
    bool? isLoading,
    String? url,
    String? error,
  }) {
    return BillingDownloadState(
      isLoading: isLoading ?? this.isLoading,
      url: url ?? this.url,
      error: error,
    );
  }
}

class BillingDownloadNotifier extends Notifier<BillingDownloadState> {
  @override
  BillingDownloadState build() => const BillingDownloadState();

  Future<String?> requestDownloadUrl(String invoiceId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final url =
          await ref.read(getInvoicePdfUrlUseCaseProvider).execute(invoiceId);
      state = state.copyWith(isLoading: false, url: url, error: null);
      return url;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  void reset() {
    state = const BillingDownloadState();
  }
}

final billingDownloadNotifierProvider =
    NotifierProvider<BillingDownloadNotifier, BillingDownloadState>(
      BillingDownloadNotifier.new,
    );
