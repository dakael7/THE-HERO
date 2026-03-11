import 'identity.dart';
import 'contact.dart';
import 'address.dart';
import 'hero_profile.dart';
import 'rider_profile.dart';
import 'user_status.dart';

class User {
  final String id;
  final Identity identity;
  final Contact contact;
  final Address? address;
  final Map<AddressUnitType, Address> addressUnits;
  final AddressUnitType? primaryAddressUnitType;
  final List<UserRole> roles;
  final UserStatus status;
  final HeroProfile? heroProfile;
  final RiderProfile? riderProfile;
  final String? profilePhotoUrl;
  final String? verificationStatus;
  final String? rutVerificationStatus;
  final String? licenseVerificationStatus;

  User({
    required this.id,
    required this.identity,
    required this.contact,
    this.address,
    this.addressUnits = const <AddressUnitType, Address>{},
    this.primaryAddressUnitType,
    required this.roles,
    required this.status,
    this.heroProfile,
    this.riderProfile,
    this.profilePhotoUrl,
    this.verificationStatus,
    this.rutVerificationStatus,
    this.licenseVerificationStatus,
  });

  String get fullName => identity.fullName;
  String get email => contact.email;
  String get firstName => identity.firstName;
  String get lastName => identity.lastName;
  String get documentType => identity.documentType;
  String get documentId => identity.documentId;
  String get phoneNumber => contact.phoneNumber;
  DateTime get createdAt => status.createdAt;

  bool get isHero => roles.contains(UserRole.hero);
  bool get isRider => roles.contains(UserRole.rider);
  bool get hasMultipleRoles => roles.length > 1;

  bool get isRutVerified {
    if (identity.documentType.trim().toLowerCase() != 'rut') return true;
    final v = (rutVerificationStatus ?? verificationStatus)?.trim().toLowerCase();
    return v == 'verified' || v == 'aprobado' || v == 'approved';
  }

  bool get isLicenseVerified {
    final v = licenseVerificationStatus?.trim().toLowerCase();
    return v == 'approved';
  }

  bool get canActAsHero => isHero && heroProfile != null && heroProfile!.isActive;

  bool get canActAsRider => isRider && riderProfile != null && riderProfile!.canAcceptDeliveries;

  User copyWith({
    String? id,
    Identity? identity,
    Contact? contact,
    Address? address,
    Map<AddressUnitType, Address>? addressUnits,
    AddressUnitType? primaryAddressUnitType,
    List<UserRole>? roles,
    UserStatus? status,
    HeroProfile? heroProfile,
    RiderProfile? riderProfile,
    String? profilePhotoUrl,
    String? verificationStatus,
    String? rutVerificationStatus,
    String? licenseVerificationStatus,
  }) {
    return User(
      id: id ?? this.id,
      identity: identity ?? this.identity,
      contact: contact ?? this.contact,
      address: address ?? this.address,
      addressUnits: addressUnits ?? this.addressUnits,
      primaryAddressUnitType:
          primaryAddressUnitType ?? this.primaryAddressUnitType,
      roles: roles ?? this.roles,
      status: status ?? this.status,
      heroProfile: heroProfile ?? this.heroProfile,
      riderProfile: riderProfile ?? this.riderProfile,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      rutVerificationStatus: rutVerificationStatus ?? this.rutVerificationStatus,
      licenseVerificationStatus:
          licenseVerificationStatus ?? this.licenseVerificationStatus,
    );
  }
}

enum UserRole {
  hero,
  rider;

  String get displayName {
    switch (this) {
      case UserRole.hero:
        return 'Hero';
      case UserRole.rider:
        return 'Rider';
    }
  }

  static UserRole fromString(String value) {
    switch (value.toLowerCase()) {
      case 'hero':
        return UserRole.hero;
      case 'rider':
        return UserRole.rider;
      default:
        throw ArgumentError('Rol inválido: $value');
    }
  }
}
