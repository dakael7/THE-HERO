import '../../entities/payment.dart';
import '../../repositories/payment_repository.dart';

/// Use case for getting payment status by order ID
class GetPaymentStatusUseCase {
  final PaymentRepository _repository;

  GetPaymentStatusUseCase(this._repository);

  /// Gets the payment information for a given order
  /// Returns null if no payment exists for the order
  Future<Payment?> execute(String orderId) async {
    if (orderId.isEmpty) {
      throw ArgumentError('Order ID cannot be empty');
    }

    return await _repository.getPaymentByOrderId(orderId);
  }

  /// Watches payment status changes in real-time
  Stream<Payment?> watch(String orderId) {
    if (orderId.isEmpty) {
      throw ArgumentError('Order ID cannot be empty');
    }

    return _repository.watchPaymentByOrderId(orderId);
  }
}
