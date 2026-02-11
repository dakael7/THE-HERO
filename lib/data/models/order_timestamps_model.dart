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
      createdAt: _parseTimestamp(json['createdAt']) ?? Timestamp.now(),
      paidAt: _parseTimestamp(json['paidAt']),
      queuedAt: _parseTimestamp(json['queuedAt']),
      assignedAt: _parseTimestamp(json['assignedAt']),
      pickedUpAt: _parseTimestamp(json['pickedUpAt']),
      deliveredAt: _parseTimestamp(json['deliveredAt']),
      canceledAt: _parseTimestamp(json['canceledAt']),
    );
  }

  /// Helper to parse both Timestamp and ISO string formats
  static Timestamp? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value;
    if (value is String) {
      try {
        return Timestamp.fromDate(DateTime.parse(value));
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'createdAt': createdAt.toDate().toIso8601String(),
      'paidAt': paidAt?.toDate().toIso8601String(),
      'queuedAt': queuedAt?.toDate().toIso8601String(),
      'assignedAt': assignedAt?.toDate().toIso8601String(),
      'pickedUpAt': pickedUpAt?.toDate().toIso8601String(),
      'deliveredAt': deliveredAt?.toDate().toIso8601String(),
      'canceledAt': canceledAt?.toDate().toIso8601String(),
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
      queuedAt: entity.queuedAt != null
          ? Timestamp.fromDate(entity.queuedAt!)
          : null,
      assignedAt: entity.assignedAt != null
          ? Timestamp.fromDate(entity.assignedAt!)
          : null,
      pickedUpAt: entity.pickedUpAt != null
          ? Timestamp.fromDate(entity.pickedUpAt!)
          : null,
      deliveredAt: entity.deliveredAt != null
          ? Timestamp.fromDate(entity.deliveredAt!)
          : null,
      canceledAt: entity.canceledAt != null
          ? Timestamp.fromDate(entity.canceledAt!)
          : null,
    );
  }
}
