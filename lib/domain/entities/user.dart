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
  final List<UserRole> roles;
  final UserStatus status;
  final HeroProfile? heroProfile;
  final RiderProfile? riderProfile;

  User({
    required this.id,
    required this.identity,
    required this.contact,
    this.address,
    required this.roles,
    required this.status,
    this.heroProfile,
    this.riderProfile,
  });

  String get fullName => identity.fullName;
  String get email => contact.email;
  String get firstName => identity.firstName;
  String get lastName => identity.lastName;
  String get documentId => identity.documentId;
  String get phoneNumber => contact.phoneNumber;
  DateTime get createdAt => status.createdAt;

  bool get isHero => roles.contains(UserRole.hero);
  bool get isRider => roles.contains(UserRole.rider);
  bool get hasMultipleRoles => roles.length > 1;

  bool get canActAsHero => isHero && heroProfile != null && heroProfile!.isActive;

  bool get canActAsRider => isRider && riderProfile != null && riderProfile!.canAcceptDeliveries;

  User copyWith({
    String? id,
    Identity? identity,
    Contact? contact,
    Address? address,
    List<UserRole>? roles,
    UserStatus? status,
    HeroProfile? heroProfile,
    RiderProfile? riderProfile,
  }) {
    return User(
      id: id ?? this.id,
      identity: identity ?? this.identity,
      contact: contact ?? this.contact,
      address: address ?? this.address,
      roles: roles ?? this.roles,
      status: status ?? this.status,
      heroProfile: heroProfile ?? this.heroProfile,
      riderProfile: riderProfile ?? this.riderProfile,
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
