import 'package:cloud_firestore/cloud_firestore.dart';

enum AddressSlot {
  one,
  two,
  three;

  String get displayName {
    switch (this) {
      case AddressSlot.one:
        return 'Dirección 1';
      case AddressSlot.two:
        return 'Dirección 2';
      case AddressSlot.three:
        return 'Dirección 3';
    }
  }

  String get jsonValue {
    switch (this) {
      case AddressSlot.one:
        return '1';
      case AddressSlot.two:
        return '2';
      case AddressSlot.three:
        return '3';
    }
  }

  static AddressSlot fromString(String value) {
    switch (value.trim().toLowerCase()) {
      case '1':
      case 'one':
      case 'direccion 1':
      case 'dirección 1':
        return AddressSlot.one;
      case '2':
      case 'two':
      case 'direccion 2':
      case 'dirección 2':
        return AddressSlot.two;
      case '3':
      case 'three':
      case 'direccion 3':
      case 'dirección 3':
        return AddressSlot.three;
      default:
        throw ArgumentError('Slot de dirección inválido: $value');
    }
  }
}

class Address {
  final String fullAddress; 
  final GeoPoint geopoint; 
  final bool locationCheck; 
  final String? countryCode;
  final String? unitIdentifier;
  final String? postalCode;
  final String? name;
  final String? description;

  Address({
    required this.fullAddress,
    required this.geopoint,
    this.locationCheck = false,
    this.countryCode,
    this.unitIdentifier,
    this.postalCode,
    this.name,
    this.description,
  });

  double get latitude => geopoint.latitude;
  double get longitude => geopoint.longitude;

  String? get unitDisplayLine {
    final id = unitIdentifier?.trim();
    if (id == null || id.isEmpty) return null;
    return 'Dpto./Casa/Oficina/Condominio: $id';
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
    String? unitIdentifier,
    String? postalCode,
    String? name,
    String? description,
  }) {
    return Address(
      fullAddress: fullAddress ?? this.fullAddress,
      geopoint: geopoint ?? this.geopoint,
      locationCheck: locationCheck ?? this.locationCheck,
      countryCode: countryCode ?? this.countryCode,
      unitIdentifier: unitIdentifier ?? this.unitIdentifier,
      postalCode: postalCode ?? this.postalCode,
      name: name ?? this.name,
      description: description ?? this.description,
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
        other.unitIdentifier == unitIdentifier &&
        other.postalCode == postalCode &&
        other.name == name &&
        other.description == description;
  }

  @override
  int get hashCode => Object.hash(
        fullAddress,
        geopoint,
        locationCheck,
        countryCode,
        unitIdentifier,
        postalCode,
        name,
        description,
      );
}
