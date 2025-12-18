import 'package:cloud_firestore/cloud_firestore.dart';

class Address {
  final String fullAddress; 
  final GeoPoint geopoint; 
  final bool locationCheck; 

  Address({
    required this.fullAddress,
    required this.geopoint,
    this.locationCheck = false,
  });

  double get latitude => geopoint.latitude;
  double get longitude => geopoint.longitude;

  Address copyWith({
    String? fullAddress,
    GeoPoint? geopoint,
    bool? locationCheck,
  }) {
    return Address(
      fullAddress: fullAddress ?? this.fullAddress,
      geopoint: geopoint ?? this.geopoint,
      locationCheck: locationCheck ?? this.locationCheck,
    );
  }
}
