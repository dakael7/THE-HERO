import '../../entities/order.dart';
import '../../entities/payment_preference.dart';
import '../../repositories/payment_repository.dart';

/// Use case for creating a MercadoPago payment preference
class CreatePaymentPreferenceUseCase {
  final PaymentRepository _repository;

  CreatePaymentPreferenceUseCase(this._repository);

  /// Creates a payment preference for the given order
  /// Returns the preference with the init_point URL to redirect the user
  Future<PaymentPreference> execute(Order order) async {
    if (order.amountTotal <= 0) {
      throw ArgumentError('Order total must be greater than 0');
    }

    return await _repository.createPreference(order);
  }
}
