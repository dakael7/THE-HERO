import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/order_rider.dart';

class OrderRiderModel {
  final String? assignedRiderId;
  final Timestamp? assignedAt;
  final String? vehicleTypeSnapshot;
  final String? riderNameSnapshot;
  final String? riderPhoneSnapshot;

  OrderRiderModel({
    this.assignedRiderId,
    this.assignedAt,
    this.vehicleTypeSnapshot,
    this.riderNameSnapshot,
    this.riderPhoneSnapshot,
  });

  factory OrderRiderModel.fromJson(Map<String, dynamic> json) {
    return OrderRiderModel(
      assignedRiderId: json['assignedRiderId'] as String?,
      assignedAt: json['assignedAt'] as Timestamp?,
      vehicleTypeSnapshot: json['vehicleTypeSnapshot'] as String?,
      riderNameSnapshot: json['riderNameSnapshot'] as String?,
      riderPhoneSnapshot: json['riderPhoneSnapshot'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'assignedRiderId': assignedRiderId,
      'assignedAt': assignedAt,
      'vehicleTypeSnapshot': vehicleTypeSnapshot,
      'riderNameSnapshot': riderNameSnapshot,
      'riderPhoneSnapshot': riderPhoneSnapshot,
    };
  }

  OrderRider toEntity() {
    return OrderRider(
      assignedRiderId: assignedRiderId,
      assignedAt: assignedAt?.toDate(),
      vehicleTypeSnapshot: vehicleTypeSnapshot,
      riderNameSnapshot: riderNameSnapshot,
      riderPhoneSnapshot: riderPhoneSnapshot,
    );
  }

  factory OrderRiderModel.fromEntity(OrderRider entity) {
    return OrderRiderModel(
      assignedRiderId: entity.assignedRiderId,
      assignedAt: entity.assignedAt != null ? Timestamp.fromDate(entity.assignedAt!) : null,
      vehicleTypeSnapshot: entity.vehicleTypeSnapshot,
      riderNameSnapshot: entity.riderNameSnapshot,
      riderPhoneSnapshot: entity.riderPhoneSnapshot,
    );
  }
}
