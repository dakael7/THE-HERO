import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/network_providers.dart';

const staleVerificationProcessingTimeout = Duration(minutes: 5);

class RiderVerificationRequestKey {
  final String userId;
  final String requestId;

  const RiderVerificationRequestKey({
    required this.userId,
    required this.requestId,
  });

  @override
  bool operator ==(Object other) {
    return other is RiderVerificationRequestKey &&
        other.userId == userId &&
        other.requestId == requestId;
  }

  @override
  int get hashCode => Object.hash(userId, requestId);
}

class RiderVerificationVehicleKey {
  final String userId;
  final String vehicleType;

  const RiderVerificationVehicleKey({
    required this.userId,
    required this.vehicleType,
  });

  @override
  bool operator ==(Object other) {
    return other is RiderVerificationVehicleKey &&
        other.userId == userId &&
        other.vehicleType == vehicleType;
  }

  @override
  int get hashCode => Object.hash(userId, vehicleType);
}

Map<String, dynamic>? _withRequestId(Map<String, dynamic>? data, String id) {
  if (data == null) return null;
  return {...data, 'requestId': id};
}

String? _licenseVehicleType(Map<String, dynamic> data) {
  final declared = data['declared'];
  if (declared is Map) return declared['vehicleType']?.toString();
  final ocr = data['ocr'];
  if (ocr is Map) return ocr['vehicleType']?.toString();
  return data['vehicleType']?.toString();
}

DateTime? _dateFromValue(Object? value) {
  if (value is firestore.Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

DateTime? _verificationUpdatedAt(Map<String, dynamic>? data) {
  if (data == null) return null;
  return _dateFromValue(data['updatedAt']) ??
      _dateFromValue(data['createdAt']) ??
      _dateFromValue(data['submittedAt']);
}

bool _isStaleVerificationStatus(String? status, Map<String, dynamic>? data) {
  if (status != 'processing' && status != 'submitted') return false;
  final updatedAt = _verificationUpdatedAt(data);
  if (updatedAt == null) return false;
  return DateTime.now().difference(updatedAt) >
      staleVerificationProcessingTimeout;
}

String? resolveVerificationStatus({
  Map<String, dynamic>? requestData,
  Map<String, dynamic>? profileData,
  String? fallbackStatus,
}) {
  final requestStatus = requestData?['status']?.toString();
  if (requestStatus != null && requestStatus != 'superseded') {
    if (_isStaleVerificationStatus(requestStatus, requestData)) return 'failed';
    return requestStatus;
  }

  final profileStatus = profileData?['status']?.toString() ?? fallbackStatus;
  if (_isStaleVerificationStatus(profileStatus, profileData)) return 'failed';
  return profileStatus;
}

final licenseVerificationRequestProvider =
    StreamProvider.family<Map<String, dynamic>?, RiderVerificationRequestKey>((
      ref,
      key,
    ) {
      if (key.userId.trim().isEmpty || key.requestId.trim().isEmpty) {
        return Stream.value(null);
      }

      final firestore = ref.watch(firebaseFirestoreProvider);
      return firestore
          .collection('users')
          .doc(key.userId)
          .collection('license_verification_requests')
          .doc(key.requestId)
          .snapshots()
          .map((snap) => _withRequestId(snap.data(), snap.id));
    });

final vehicleVerificationRequestProvider =
    StreamProvider.family<Map<String, dynamic>?, RiderVerificationRequestKey>((
      ref,
      key,
    ) {
      if (key.userId.trim().isEmpty || key.requestId.trim().isEmpty) {
        return Stream.value(null);
      }

      final firestore = ref.watch(firebaseFirestoreProvider);
      return firestore
          .collection('users')
          .doc(key.userId)
          .collection('vehicle_verification_requests')
          .doc(key.requestId)
          .snapshots()
          .map((snap) => _withRequestId(snap.data(), snap.id));
    });

final latestLicenseVerificationRequestProvider =
    StreamProvider.family<Map<String, dynamic>?, RiderVerificationVehicleKey>((
      ref,
      key,
    ) {
      if (key.userId.trim().isEmpty || key.vehicleType.trim().isEmpty) {
        return Stream.value(null);
      }

      final firestore = ref.watch(firebaseFirestoreProvider);
      return firestore
          .collection('users')
          .doc(key.userId)
          .collection('license_verification_requests')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .snapshots()
          .map((snap) {
            for (final doc in snap.docs) {
              final data = doc.data();
              if (_licenseVehicleType(data) == key.vehicleType) {
                return _withRequestId(data, doc.id);
              }
            }
            return null;
          });
    });

final latestVehicleVerificationRequestProvider =
    StreamProvider.family<Map<String, dynamic>?, RiderVerificationVehicleKey>((
      ref,
      key,
    ) {
      if (key.userId.trim().isEmpty || key.vehicleType.trim().isEmpty) {
        return Stream.value(null);
      }

      final firestore = ref.watch(firebaseFirestoreProvider);
      return firestore
          .collection('users')
          .doc(key.userId)
          .collection('vehicle_verification_requests')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .snapshots()
          .map((snap) {
            for (final doc in snap.docs) {
              final data = doc.data();
              if (data['status'] == 'superseded') continue;
              if (data['vehicleType']?.toString() == key.vehicleType) {
                return _withRequestId(data, doc.id);
              }
            }
            return null;
          });
    });
