import 'identity.dart';
import 'contact.dart';
import 'address.dart';
import 'hero_profile.dart';
import 'rider_profile.dart';
import 'user_status.dart';

enum AccountStatus { active, suspended, banned }

class User {
  final String id;
  final Identity identity;
  final Contact contact;
  final Address? address;
  final Map<AddressSlot, Address> addressSlots;
  final AddressSlot? primaryAddressSlot;
  final List<UserRole> roles;
  final UserStatus status;
  final HeroProfile? heroProfile;
  final RiderProfile? riderProfile;
  final String? profilePhotoUrl;
  final String? verificationStatus;
  final String? rutVerificationStatus;
  final String? licenseVerificationStatus;

  final AccountStatus accountStatus;
  final DateTime? suspendedUntil;
  final String? suspensionReason;
  final int reportCount;
  final DateTime? lastReportedAt;

  User({
    required this.id,
    required this.identity,
    required this.contact,
    this.address,
    this.addressSlots = const <AddressSlot, Address>{},
    this.primaryAddressSlot,
    required this.roles,
    required this.status,
    this.heroProfile,
    this.riderProfile,
    this.profilePhotoUrl,
    this.verificationStatus,
    this.rutVerificationStatus,
    this.licenseVerificationStatus,
    this.accountStatus = AccountStatus.active,
    this.suspendedUntil,
    this.suspensionReason,
    this.reportCount = 0,
    this.lastReportedAt,
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
    if (isRider) {
      final v = (rutVerificationStatus ?? verificationStatus)?.trim().toLowerCase();
      return v == 'verified' || v == 'aprobado' || v == 'approved';
    }
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

  bool get isSuspended =>
      accountStatus == AccountStatus.suspended &&
      (suspendedUntil == null || suspendedUntil!.isAfter(DateTime.now()));

  bool get isBanned => accountStatus == AccountStatus.banned;

  bool get canOperate => accountStatus == AccountStatus.active || !isSuspended;

  User copyWith({
    String? id,
    Identity? identity,
    Contact? contact,
    Address? address,
    Map<AddressSlot, Address>? addressSlots,
    AddressSlot? primaryAddressSlot,
    List<UserRole>? roles,
    UserStatus? status,
    HeroProfile? heroProfile,
    RiderProfile? riderProfile,
    String? profilePhotoUrl,
    String? verificationStatus,
    String? rutVerificationStatus,
    String? licenseVerificationStatus,
    AccountStatus? accountStatus,
    DateTime? suspendedUntil,
    String? suspensionReason,
    int? reportCount,
    DateTime? lastReportedAt,
  }) {
    return User(
      id: id ?? this.id,
      identity: identity ?? this.identity,
      contact: contact ?? this.contact,
      address: address ?? this.address,
      addressSlots: addressSlots ?? this.addressSlots,
      primaryAddressSlot: primaryAddressSlot ?? this.primaryAddressSlot,
      roles: roles ?? this.roles,
      status: status ?? this.status,
      heroProfile: heroProfile ?? this.heroProfile,
      riderProfile: riderProfile ?? this.riderProfile,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      rutVerificationStatus: rutVerificationStatus ?? this.rutVerificationStatus,
      licenseVerificationStatus:
          licenseVerificationStatus ?? this.licenseVerificationStatus,
      accountStatus: accountStatus ?? this.accountStatus,
      suspendedUntil: suspendedUntil ?? this.suspendedUntil,
      suspensionReason: suspensionReason ?? this.suspensionReason,
      reportCount: reportCount ?? this.reportCount,
      lastReportedAt: lastReportedAt ?? this.lastReportedAt,
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
