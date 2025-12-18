class OrderTimestamps {
  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? queuedAt;
  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime? canceledAt;

  OrderTimestamps({
    required this.createdAt,
    this.paidAt,
    this.queuedAt,
    this.assignedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.canceledAt,
  });

  OrderTimestamps copyWith({
    DateTime? createdAt,
    DateTime? paidAt,
    DateTime? queuedAt,
    DateTime? assignedAt,
    DateTime? pickedUpAt,
    DateTime? deliveredAt,
    DateTime? canceledAt,
  }) {
    return OrderTimestamps(
      createdAt: createdAt ?? this.createdAt,
      paidAt: paidAt ?? this.paidAt,
      queuedAt: queuedAt ?? this.queuedAt,
      assignedAt: assignedAt ?? this.assignedAt,
      pickedUpAt: pickedUpAt ?? this.pickedUpAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      canceledAt: canceledAt ?? this.canceledAt,
    );
  }
}
