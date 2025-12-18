class OrderRider {
  final String? assignedRiderId;
  final DateTime? assignedAt;
  final String? vehicleTypeSnapshot;
  final String? riderNameSnapshot;
  final String? riderPhoneSnapshot;

  OrderRider({
    this.assignedRiderId,
    this.assignedAt,
    this.vehicleTypeSnapshot,
    this.riderNameSnapshot,
    this.riderPhoneSnapshot,
  });

  bool get isAssigned => assignedRiderId != null;

  OrderRider copyWith({
    String? assignedRiderId,
    DateTime? assignedAt,
    String? vehicleTypeSnapshot,
    String? riderNameSnapshot,
    String? riderPhoneSnapshot,
  }) {
    return OrderRider(
      assignedRiderId: assignedRiderId ?? this.assignedRiderId,
      assignedAt: assignedAt ?? this.assignedAt,
      vehicleTypeSnapshot: vehicleTypeSnapshot ?? this.vehicleTypeSnapshot,
      riderNameSnapshot: riderNameSnapshot ?? this.riderNameSnapshot,
      riderPhoneSnapshot: riderPhoneSnapshot ?? this.riderPhoneSnapshot,
    );
  }
}
