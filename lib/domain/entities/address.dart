import 'package:cloud_firestore/cloud_firestore.dart';

class Address {
  final String fullAddress; 
  final GeoPoint geopoint; 
  final bool locationCheck; 
  final String? countryCode;

  Address({
    required this.fullAddress,
    required this.geopoint,
    this.locationCheck = false,
    this.countryCode,
  });

  double get latitude => geopoint.latitude;
  double get longitude => geopoint.longitude;

  Address copyWith({
    String? fullAddress,
    GeoPoint? geopoint,
    bool? locationCheck,
    String? countryCode,
  }) {
    return Address(
      fullAddress: fullAddress ?? this.fullAddress,
      geopoint: geopoint ?? this.geopoint,
      locationCheck: locationCheck ?? this.locationCheck,
      countryCode: countryCode ?? this.countryCode,
    );
  }
}
