import 'package:cloud_functions/cloud_functions.dart';

/// Remote data source for payment operations via Firebase Functions
class PaymentRemoteDataSource {
  final FirebaseFunctions _functions;

  PaymentRemoteDataSource({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  /// Creates a payment preference in MercadoPago
  /// Calls the createPaymentPreference Firebase Function
  Future<Map<String, dynamic>> createPreference(
    Map<String, dynamic> orderData,
  ) async {
    try {
      final callable = _functions.httpsCallable('createPaymentPreference');
      final result = await callable.call(orderData);

      if (result.data == null) {
        throw Exception('No data received from createPaymentPreference');
      }

      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw Exception(
        'Error creating payment preference: ${e.code} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Unexpected error creating payment preference: $e');
    }
  }

  /// Verifies payment status with MercadoPago
  /// Calls the verifyPayment Firebase Function
  Future<Map<String, dynamic>> verifyPayment(String paymentId) async {
    try {
      final callable = _functions.httpsCallable('verifyPayment');
      final result = await callable.call({'paymentId': paymentId});

      if (result.data == null) {
        throw Exception('No data received from verifyPayment');
      }

      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw Exception('Error verifying payment: ${e.code} - ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error verifying payment: $e');
    }
  }

  /// Gets payment information by order ID
  /// Calls the getPaymentByOrderId Firebase Function
  Future<Map<String, dynamic>?> getPaymentByOrderId(String orderId) async {
    try {
      final callable = _functions.httpsCallable('getPaymentByOrderId');
      final result = await callable.call({'orderId': orderId});

      if (result.data == null) {
        return null;
      }

      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') {
        return null;
      }
      throw Exception(
        'Error getting payment by order ID: ${e.code} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Unexpected error getting payment by order ID: $e');
    }
  }
}
