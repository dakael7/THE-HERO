import '../entities/order.dart';
import '../entities/payment.dart';
import '../entities/payment_preference.dart';

/// Repository interface for payment operations
abstract class PaymentRepository {
  /// Creates a payment preference in MercadoPago for the given order
  /// Returns the preference with initPoint URL to redirect user
  Future<PaymentPreference> createPreference(Order order);

  /// Verifies the payment status with MercadoPago
  /// Returns the updated payment information
  Future<Payment> verifyPayment(String paymentId);

  /// Gets payment information by order ID
  /// Returns null if no payment exists for the order
  Future<Payment?> getPaymentByOrderId(String orderId);

  /// Gets payment information by preference ID
  /// Returns null if no payment exists for the preference
  Future<Payment?> getPaymentByPreferenceId(String preferenceId);

  /// Watches payment changes in real-time
  /// Useful for monitoring payment status updates from webhooks
  Stream<Payment?> watchPayment(String paymentId);

  /// Watches payment changes by order ID
  Stream<Payment?> watchPaymentByOrderId(String orderId);

  /// Saves or updates payment information in Firestore
  Future<void> savePayment(Payment payment);

  /// Updates payment status
  Future<void> updatePaymentStatus({
    required String paymentId,
    required PaymentStatus status,
    String? statusDetail,
  });
}
