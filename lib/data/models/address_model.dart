import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/address.dart';

class AddressModel {
  final String fullAddress;
  final GeoPoint geopoint;
  final bool locationCheck;

  AddressModel({
    required this.fullAddress,
    required this.geopoint,
    this.locationCheck = false,
  });

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    return AddressModel(
      fullAddress: json['fullAddress'] as String? ?? '',
      geopoint: json['geopoint'] as GeoPoint? ?? const GeoPoint(0, 0),
      locationCheck: json['locationCheck'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fullAddress': fullAddress,
      'geopoint': geopoint,
      'locationCheck': locationCheck,
    };
  }

  Address toEntity() {
    return Address(
      fullAddress: fullAddress,
      geopoint: geopoint,
      locationCheck: locationCheck,
    );
  }

  factory AddressModel.fromEntity(Address entity) {
    return AddressModel(
      fullAddress: entity.fullAddress,
      geopoint: entity.geopoint,
      locationCheck: entity.locationCheck,
    );
  }
}
