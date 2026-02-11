import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../data/datasources/payment_remote_datasource.dart';
import '../../../../data/repositories/payment_repository_impl.dart';
import '../../../../domain/repositories/payment_repository.dart';
import '../../../../domain/usecases/payment/create_payment_preference_usecase.dart';
import '../../../../domain/usecases/payment/verify_payment_usecase.dart';
import '../../../../domain/usecases/payment/get_payment_status_usecase.dart';
import '../../../../domain/entities/payment.dart';
import '../../../../core/config/mercadopago_config.dart';

// ============================================================================
// Data Sources & Repository
// ============================================================================

/// Provider for payment remote data source
final paymentRemoteDataSourceProvider = Provider<PaymentRemoteDataSource>((
  ref,
) {
  return PaymentRemoteDataSource();
});

/// Provider for payment repository
final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final remoteDataSource = ref.watch(paymentRemoteDataSourceProvider);
  return PaymentRepositoryImpl(
    remoteDataSource: remoteDataSource,
    firestoreInstance: FirebaseFirestore.instance,
  );
});

// ============================================================================
// Use Cases
// ============================================================================

/// Provider for create payment preference use case
final createPaymentPreferenceUseCaseProvider =
    Provider<CreatePaymentPreferenceUseCase>((ref) {
      final repository = ref.watch(paymentRepositoryProvider);
      return CreatePaymentPreferenceUseCase(repository);
    });

/// Provider for verify payment use case
final verifyPaymentUseCaseProvider = Provider<VerifyPaymentUseCase>((ref) {
  final repository = ref.watch(paymentRepositoryProvider);
  return VerifyPaymentUseCase(repository);
});

/// Provider for get payment status use case
final getPaymentStatusUseCaseProvider = Provider<GetPaymentStatusUseCase>((
  ref,
) {
  final repository = ref.watch(paymentRepositoryProvider);
  return GetPaymentStatusUseCase(repository);
});

// ============================================================================
// State Providers
// ============================================================================

/// Provider to watch payment by order ID
final watchPaymentByOrderIdProvider = StreamProvider.family<Payment?, String>((
  ref,
  orderId,
) {
  final useCase = ref.watch(getPaymentStatusUseCaseProvider);
  return useCase.watch(orderId);
});

/// Provider to get payment by order ID
final getPaymentByOrderIdProvider = FutureProvider.family<Payment?, String>((
  ref,
  orderId,
) async {
  final useCase = ref.watch(getPaymentStatusUseCaseProvider);
  return await useCase.execute(orderId);
});

// ============================================================================
// Payment State Notifier
// ============================================================================

/// State for payment processing
class PaymentState {
  final bool isProcessing;
  final Payment? payment;
  final String? error;
  final String? preferenceId;
  final String? initPoint;

  const PaymentState({
    this.isProcessing = false,
    this.payment,
    this.error,
    this.preferenceId,
    this.initPoint,
  });

  PaymentState copyWith({
    bool? isProcessing,
    Payment? payment,
    String? error,
    String? preferenceId,
    String? initPoint,
  }) {
    return PaymentState(
      isProcessing: isProcessing ?? this.isProcessing,
      payment: payment ?? this.payment,
      error: error ?? this.error,
      preferenceId: preferenceId ?? this.preferenceId,
      initPoint: initPoint ?? this.initPoint,
    );
  }
}

/// Notifier for payment state
class PaymentNotifier extends Notifier<PaymentState> {
  @override
  PaymentState build() => const PaymentState();

  /// Creates a payment preference for an order
  Future<void> createPreference(dynamic order) async {
    state = state.copyWith(isProcessing: true, error: null);

    try {
      final createPreferenceUseCase = ref.read(
        createPaymentPreferenceUseCaseProvider,
      );
      final preference = await createPreferenceUseCase.execute(order);

      state = state.copyWith(
        isProcessing: false,
        preferenceId: preference.preferenceId,
        initPoint: MercadoPagoConfig.isProduction
            ? preference.initPoint
            : preference.sandboxInitPoint,
      );
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
    }
  }

  /// Verifies a payment by payment ID
  Future<void> verifyPayment(String paymentId) async {
    state = state.copyWith(isProcessing: true, error: null);

    try {
      final verifyPaymentUseCase = ref.read(verifyPaymentUseCaseProvider);
      final payment = await verifyPaymentUseCase.execute(paymentId);

      state = state.copyWith(isProcessing: false, payment: payment);
    } catch (e) {
      state = state.copyWith(isProcessing: false, error: e.toString());
    }
  }

  /// Resets the payment state
  void reset() {
    state = const PaymentState();
  }
}

/// Provider for payment notifier
final paymentNotifierProvider = NotifierProvider<PaymentNotifier, PaymentState>(
  () {
    return PaymentNotifier();
  },
);
