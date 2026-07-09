import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CheckoutCouponType { percent, fixed }

class CheckoutCoupon {
  final String code;
  final CheckoutCouponType type;
  final double value;
  final bool active;

  const CheckoutCoupon({
    required this.code,
    required this.type,
    required this.value,
    required this.active,
  });

  factory CheckoutCoupon.fromFirestore({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final rawType = (data['type'] ?? data['discountType'] ?? data['tipo'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final type = switch (rawType) {
      'percent' ||
      'percentage' ||
      'porcentual' ||
      'porcentaje' => CheckoutCouponType.percent,
      'fixed' || 'amount' || 'fijo' || 'monto' => CheckoutCouponType.fixed,
      _ => throw const FormatException('Tipo de cupo invalido'),
    };

    final rawValue =
        data['value'] ??
        data['discountValue'] ??
        data['amount'] ??
        data['valor'];
    final value = rawValue is num
        ? rawValue.toDouble()
        : double.tryParse(rawValue?.toString() ?? '') ?? 0.0;
    if (!value.isFinite || value <= 0) {
      throw const FormatException('Valor de cupo invalido');
    }

    return CheckoutCoupon(
      code: (data['code']?.toString().trim().isNotEmpty ?? false)
          ? data['code'].toString().trim().toUpperCase()
          : id.trim().toUpperCase(),
      type: type,
      value: value,
      active: data['active'] == true || data['isActive'] == true,
    );
  }

  double discountFor(double amount) {
    if (!active || amount <= 0) return 0.0;

    final raw = switch (type) {
      CheckoutCouponType.percent => amount * math.min(value, 100) / 100,
      CheckoutCouponType.fixed => value,
    };

    return raw.clamp(0.0, amount).roundToDouble();
  }

  Map<String, dynamic> toOrderJson(double discountAmount) {
    return {
      'code': code,
      'type': type == CheckoutCouponType.percent ? 'percent' : 'fixed',
      'value': value,
      'discountAmount': discountAmount,
    };
  }
}

final checkoutCouponProvider = FutureProvider.family<CheckoutCoupon?, String>((
  ref,
  code,
) async {
  final normalized = code.trim().toUpperCase();
  if (normalized.isEmpty) return null;

  final doc = await firestore.FirebaseFirestore.instance
      .collection('cupos')
      .doc(normalized)
      .get();
  if (!doc.exists) return null;

  return CheckoutCoupon.fromFirestore(
    id: doc.id,
    data: doc.data() ?? const <String, dynamic>{},
  );
});
