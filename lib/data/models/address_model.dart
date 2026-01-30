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
    GeoPoint geopoint;

    // Check if we have the new format (latitude/longitude as separate fields)
    if (json.containsKey('latitude') && json.containsKey('longitude')) {
      final lat = json['latitude'];
      final lng = json['longitude'];
      geopoint = GeoPoint(
        lat is double ? lat : (lat as num).toDouble(),
        lng is double ? lng : (lng as num).toDouble(),
      );
    }
    // Otherwise use the old format (geopoint field)
    else if (json.containsKey('geopoint')) {
      geopoint = json['geopoint'] as GeoPoint? ?? const GeoPoint(0, 0);
    }
    // Fallback to default
    else {
      geopoint = const GeoPoint(0, 0);
    }

    return AddressModel(
      fullAddress: json['fullAddress'] as String? ?? '',
      geopoint: geopoint,
      locationCheck: json['locationCheck'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    // Serialize GeoPoint as separate latitude/longitude for local storage
    return {
      'fullAddress': fullAddress,
      'latitude': geopoint.latitude,
      'longitude': geopoint.longitude,
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
