import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/order_timestamps.dart';

class OrderTimestampsModel {
  final Timestamp createdAt;
  final Timestamp? paidAt;
  final Timestamp? queuedAt;
  final Timestamp? assignedAt;
  final Timestamp? pickedUpAt;
  final Timestamp? deliveredAt;
  final Timestamp? canceledAt;

  OrderTimestampsModel({
    required this.createdAt,
    this.paidAt,
    this.queuedAt,
    this.assignedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.canceledAt,
  });

  factory OrderTimestampsModel.fromJson(Map<String, dynamic> json) {
    return OrderTimestampsModel(
      createdAt: json['createdAt'] as Timestamp? ?? Timestamp.now(),
      paidAt: json['paidAt'] as Timestamp?,
      queuedAt: json['queuedAt'] as Timestamp?,
      assignedAt: json['assignedAt'] as Timestamp?,
      pickedUpAt: json['pickedUpAt'] as Timestamp?,
      deliveredAt: json['deliveredAt'] as Timestamp?,
      canceledAt: json['canceledAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'createdAt': createdAt,
      'paidAt': paidAt,
      'queuedAt': queuedAt,
      'assignedAt': assignedAt,
      'pickedUpAt': pickedUpAt,
      'deliveredAt': deliveredAt,
      'canceledAt': canceledAt,
    };
  }

  OrderTimestamps toEntity() {
    return OrderTimestamps(
      createdAt: createdAt.toDate(),
      paidAt: paidAt?.toDate(),
      queuedAt: queuedAt?.toDate(),
      assignedAt: assignedAt?.toDate(),
      pickedUpAt: pickedUpAt?.toDate(),
      deliveredAt: deliveredAt?.toDate(),
      canceledAt: canceledAt?.toDate(),
    );
  }

  factory OrderTimestampsModel.fromEntity(OrderTimestamps entity) {
    return OrderTimestampsModel(
      createdAt: Timestamp.fromDate(entity.createdAt),
      paidAt: entity.paidAt != null ? Timestamp.fromDate(entity.paidAt!) : null,
      queuedAt: entity.queuedAt != null ? Timestamp.fromDate(entity.queuedAt!) : null,
      assignedAt: entity.assignedAt != null ? Timestamp.fromDate(entity.assignedAt!) : null,
      pickedUpAt: entity.pickedUpAt != null ? Timestamp.fromDate(entity.pickedUpAt!) : null,
      deliveredAt: entity.deliveredAt != null ? Timestamp.fromDate(entity.deliveredAt!) : null,
      canceledAt: entity.canceledAt != null ? Timestamp.fromDate(entity.canceledAt!) : null,
    );
  }
}
