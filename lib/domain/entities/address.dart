import 'package:cloud_firestore/cloud_firestore.dart';

enum AddressUnitType {
  apartment,
  house,
  office;

  String get displayName {
    switch (this) {
      case AddressUnitType.apartment:
        return 'Departamento';
      case AddressUnitType.house:
        return 'Casa';
      case AddressUnitType.office:
        return 'Oficina';
    }
  }

  String get jsonValue => name;

  static AddressUnitType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'apartment':
      case 'departamento':
        return AddressUnitType.apartment;
      case 'house':
      case 'casa':
        return AddressUnitType.house;
      case 'office':
      case 'oficina':
        return AddressUnitType.office;
      default:
        throw ArgumentError('Tipo de unidad inválido: $value');
    }
  }
}

class Address {
  final String fullAddress; 
  final GeoPoint geopoint; 
  final bool locationCheck; 
  final String? countryCode;
  final AddressUnitType? unitType;
  final String? unitIdentifier;

  Address({
    required this.fullAddress,
    required this.geopoint,
    this.locationCheck = false,
    this.countryCode,
    this.unitType,
    this.unitIdentifier,
  });

  double get latitude => geopoint.latitude;
  double get longitude => geopoint.longitude;

  String? get unitDisplayLine {
    final type = unitType;
    final id = unitIdentifier?.trim();
    if (type == null) return null;
    if (id == null || id.isEmpty) return 'Unidad: ${type.displayName}';
    return 'Unidad: ${type.displayName} - $id';
  }

  String get displayAddressMultiline {
    final unit = unitDisplayLine;
    if (unit == null) return fullAddress;
    return '$fullAddress\n$unit';
  }

  Address copyWith({
    String? fullAddress,
    GeoPoint? geopoint,
    bool? locationCheck,
    String? countryCode,
    AddressUnitType? unitType,
    String? unitIdentifier,
  }) {
    return Address(
      fullAddress: fullAddress ?? this.fullAddress,
      geopoint: geopoint ?? this.geopoint,
      locationCheck: locationCheck ?? this.locationCheck,
      countryCode: countryCode ?? this.countryCode,
      unitType: unitType ?? this.unitType,
      unitIdentifier: unitIdentifier ?? this.unitIdentifier,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Address &&
        other.fullAddress == fullAddress &&
        other.geopoint == geopoint &&
        other.locationCheck == locationCheck &&
        other.countryCode == countryCode &&
        other.unitType == unitType &&
        other.unitIdentifier == unitIdentifier;
  }

  @override
  int get hashCode => Object.hash(
        fullAddress,
        geopoint,
        locationCheck,
        countryCode,
        unitType,
        unitIdentifier,
      );
}
