import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PaymentFunctionsException implements Exception {
  final String code;
  final String? message;

  PaymentFunctionsException({required this.code, this.message});

  @override
  String toString() {
    if (message == null || message!.isEmpty) return code;
    return '$code - $message';
  }
}

class PaymentRemoteDataSource {
  final FirebaseFunctions _functions;

  PaymentRemoteDataSource({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<void> _ensureFreshAuthToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Debes iniciar sesión para continuar');
    }

    await user.getIdToken(true);
  }

  Future<Map<String, dynamic>> createPreference(
    Map<String, dynamic> orderData,
  ) async {
    try {
      await _ensureFreshAuthToken();
      final callable = _functions.httpsCallable('createPaymentPreference');
      final result = await callable.call(orderData);

      if (result.data == null) {
        throw Exception('No data received from createPaymentPreference');
      }

      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw PaymentFunctionsException(code: e.code, message: e.message);
    } catch (e) {
      throw Exception('Unexpected error creating payment preference: $e');
    }
  }

  /// Verifies payment status with MercadoPago
  /// Calls the verifyPayment Firebase Function
  Future<Map<String, dynamic>> verifyPayment(String paymentId) async {
    try {
      await _ensureFreshAuthToken();
      final callable = _functions.httpsCallable('verifyPayment');
      final result = await callable.call({'paymentId': paymentId});

      if (result.data == null) {
        throw Exception('No data received from verifyPayment');
      }

      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw PaymentFunctionsException(code: e.code, message: e.message);
    } catch (e) {
      throw Exception('Unexpected error verifying payment: $e');
    }
  }

  /// Gets payment information by order ID
  /// Calls the getPaymentByOrderId Firebase Function
  Future<Map<String, dynamic>?> getPaymentByOrderId(String orderId) async {
    try {
      await _ensureFreshAuthToken();
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
      throw PaymentFunctionsException(code: e.code, message: e.message);
    } catch (e) {
      throw Exception('Unexpected error getting payment by order ID: $e');
    }
  }
}
