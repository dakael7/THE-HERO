class OrderRider {
  final String? assignedRiderId;
  final DateTime? assignedAt;
  final String? vehicleTypeSnapshot;
  final String? riderNameSnapshot;
  final String? riderPhoneSnapshot;
  /// Monto en efectivo retenido al asignar el pedido. null = no es pedido en efectivo.
  final double? cashHoldAmount;

  OrderRider({
    this.assignedRiderId,
    this.assignedAt,
    this.vehicleTypeSnapshot,
    this.riderNameSnapshot,
    this.riderPhoneSnapshot,
    this.cashHoldAmount,
  });

  bool get isAssigned =>
      assignedRiderId != null && assignedRiderId!.trim().isNotEmpty;

  bool get isCashOrder => cashHoldAmount != null && cashHoldAmount! > 0;

  OrderRider copyWith({
    String? assignedRiderId,
    DateTime? assignedAt,
    String? vehicleTypeSnapshot,
    String? riderNameSnapshot,
    String? riderPhoneSnapshot,
    double? cashHoldAmount,
  }) {
    return OrderRider(
      assignedRiderId: assignedRiderId ?? this.assignedRiderId,
      assignedAt: assignedAt ?? this.assignedAt,
      vehicleTypeSnapshot: vehicleTypeSnapshot ?? this.vehicleTypeSnapshot,
      riderNameSnapshot: riderNameSnapshot ?? this.riderNameSnapshot,
      riderPhoneSnapshot: riderPhoneSnapshot ?? this.riderPhoneSnapshot,
      cashHoldAmount: cashHoldAmount ?? this.cashHoldAmount,
    );
  }
}
