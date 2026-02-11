import '../../entities/payment.dart';
import '../../repositories/payment_repository.dart';

/// Use case for verifying payment status with MercadoPago
class VerifyPaymentUseCase {
  final PaymentRepository _repository;

  VerifyPaymentUseCase(this._repository);

  /// Verifies the payment status with MercadoPago API
  /// Returns updated payment information
  Future<Payment> execute(String paymentId) async {
    if (paymentId.isEmpty) {
      throw ArgumentError('Payment ID cannot be empty');
    }

    return await _repository.verifyPayment(paymentId);
  }
}
