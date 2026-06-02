import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

import '../../domain/entities/order.dart';
import '../../domain/entities/payment.dart';
import '../../domain/entities/payment_preference.dart';
import '../../domain/repositories/payment_repository.dart';
import '../datasources/payment_remote_datasource.dart';
import '../models/payment_model.dart';
import '../models/payment_preference_model.dart';
import '../models/order_model.dart';

class PaymentRepositoryImpl implements PaymentRepository {
  final PaymentRemoteDataSource _remoteDataSource;
  final firestore.FirebaseFirestore _firestore;

  PaymentRepositoryImpl({
    required PaymentRemoteDataSource remoteDataSource,
    firestore.FirebaseFirestore? firestoreInstance,
  }) : _remoteDataSource = remoteDataSource,
       _firestore = firestoreInstance ?? firestore.FirebaseFirestore.instance;

  firestore.CollectionReference get _paymentsCollection =>
      _firestore.collection('payments');

  @override
  Future<PaymentPreference> createPreference(Order order) async {
    try {
      // Convert order to JSON for Firebase Function
      final orderModel = OrderModel.fromEntity(order);
      final orderData = orderModel.toJson();

      // Call Firebase Function to create preference
      final response = await _remoteDataSource.createPreference(orderData);

      // Parse response
      final preferenceModel = PaymentPreferenceModel.fromJson(response);

      return preferenceModel.toEntity();
    } on PaymentFunctionsException {
      rethrow;
    } catch (e) {
      throw Exception('Failed to create payment preference: $e');
    }
  }

  @override
  Future<Payment> verifyPayment(String paymentId) async {
    try {
      final response = await _remoteDataSource.verifyPayment(paymentId);
      final paymentModel = PaymentModel.fromJson(response);

      return paymentModel.toEntity();
    } catch (e) {
      throw Exception('Failed to verify payment: $e');
    }
  }

  @override
  Future<Payment?> getPaymentByOrderId(String orderId) async {
    try {
      final querySnapshot = await _paymentsCollection
          .where('orderId', isEqualTo: orderId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      final doc = querySnapshot.docs.first;
      final paymentModel = PaymentModel.fromFirestore(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );

      return paymentModel.toEntity();
    } catch (e) {
      throw Exception('Failed to get payment by order ID: $e');
    }
  }

  @override
  Future<Payment?> getPaymentByPreferenceId(String preferenceId) async {
    try {
      final doc = await _paymentsCollection.doc(preferenceId).get();

      if (!doc.exists) {
        return null;
      }

      final paymentModel = PaymentModel.fromFirestore(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );

      return paymentModel.toEntity();
    } catch (e) {
      throw Exception('Failed to get payment by preference ID: $e');
    }
  }

  @override
  Stream<Payment?> watchPayment(String paymentId) {
    return _paymentsCollection.doc(paymentId).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }

      final paymentModel = PaymentModel.fromFirestore(
        snapshot.data() as Map<String, dynamic>,
        snapshot.id,
      );

      return paymentModel.toEntity();
    });
  }

  @override
  Stream<Payment?> watchPaymentByOrderId(String orderId) {
    return _paymentsCollection
        .where('orderId', isEqualTo: orderId)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return null;
          }

          final doc = snapshot.docs.first;
          final paymentModel = PaymentModel.fromFirestore(
            doc.data() as Map<String, dynamic>,
            doc.id,
          );

          return paymentModel.toEntity();
        });
  }

  @override
  Future<void> savePayment(Payment payment) async {
    try {
      final paymentModel = PaymentModel.fromEntity(payment);
      await _paymentsCollection
          .doc(payment.id)
          .set(paymentModel.toFirestore(), firestore.SetOptions(merge: true));
    } catch (e) {
      throw Exception('Failed to save payment: $e');
    }
  }

  @override
  Future<void> updatePaymentStatus({
    required String paymentId,
    required PaymentStatus status,
    String? statusDetail,
  }) async {
    try {
      final updateData = {
        'status': status.toMercadoPagoString(),
        'updatedAt': firestore.Timestamp.fromDate(DateTime.now()),
      };

      if (statusDetail != null) {
        updateData['statusDetail'] = statusDetail;
      }

      if (status == PaymentStatus.approved) {
        updateData['approvedAt'] = firestore.Timestamp.fromDate(DateTime.now());
      }

      await _paymentsCollection.doc(paymentId).update(updateData);
    } catch (e) {
      throw Exception('Failed to update payment status: $e');
    }
  }
}
