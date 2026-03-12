import 'identity_model.dart';
import 'contact_model.dart';
import 'address_model.dart';
import 'hero_profile_model.dart';
import 'rider_profile_model.dart';
import 'user_status_model.dart';

class UserModel {
  final String id;
  final IdentityModel identity;
  final ContactModel contact;
  final AddressModel? address;
  final Map<String, AddressModel> addressSlots;
  final String? primaryAddressSlot;
  final List<String> roles;
  final UserStatusModel status;
  final HeroProfileModel? heroProfile;
  final RiderProfileModel? riderProfile;
  final String? profilePhotoUrl;
  final String? verificationStatus;
  final String? rutVerificationStatus;
  final String? licenseVerificationStatus;

  UserModel({
    required this.id,
    required this.identity,
    required this.contact,
    this.address,
    this.addressSlots = const <String, AddressModel>{},
    this.primaryAddressSlot,
    required this.roles,
    required this.status,
    this.heroProfile,
    this.riderProfile,
    this.profilePhotoUrl,
    this.verificationStatus,
    this.rutVerificationStatus,
    this.licenseVerificationStatus,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    Set<String> rolesSet = {};

    // 1. Cargar roles existentes si los hay
    if (json['roles'] != null) {
      rolesSet.addAll(
        (json['roles'] as List<dynamic>).map((e) => e.toString()),
      );
    }

    // 2. FORZAR inferencia basada en perfiles (fuente de verdad)
    // Esto corrige datos corruptos donde existe perfil pero falta el rol en la lista
    if (json['riderProfile'] != null) {
      rolesSet.add('rider');
    }
    if (json['heroProfile'] != null) {
      rolesSet.add('hero');
    }

    // 3. Fallback por defecto
    if (rolesSet.isEmpty) {
      rolesSet.add('hero');
    }

    return UserModel(
      id: json['id'] as String? ?? '',
      identity: IdentityModel.fromJson(
        json['identity'] as Map<String, dynamic>? ?? {},
      ),
      contact: ContactModel.fromJson(
        json['contact'] as Map<String, dynamic>? ?? {},
      ),
      address: json['address'] != null
          ? AddressModel.fromJson(json['address'] as Map<String, dynamic>)
          : null,
      addressSlots: (() {
        Map? raw = json['addressSlots'] as Map?;
        raw ??= json['addressUnits'] as Map?;
        if (raw is! Map) return <String, AddressModel>{};
        final out = <String, AddressModel>{};
        for (final entry in raw.entries) {
          final key = entry.key?.toString();
          final value = entry.value;
          if (key == null || key.trim().isEmpty) continue;
          if (value is Map<String, dynamic>) {
            out[key] = AddressModel.fromJson(value);
          } else if (value is Map) {
            out[key] = AddressModel.fromJson(value.cast<String, dynamic>());
          }
        }
        return out;
      })(),
      primaryAddressSlot:
          (json['primaryAddressSlot'] ?? json['primaryAddressUnitType'])
              ?.toString(),
      roles: rolesSet.toList(),
      status: UserStatusModel.fromJson(
        json['status'] as Map<String, dynamic>? ?? {},
      ),
      heroProfile: json['heroProfile'] != null
          ? HeroProfileModel.fromJson(
              json['heroProfile'] as Map<String, dynamic>,
            )
          : null,
      riderProfile: json['riderProfile'] != null
          ? RiderProfileModel.fromJson(
              json['riderProfile'] as Map<String, dynamic>,
            )
          : null,
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
      verificationStatus: json['verificationStatus'] as String?,
      rutVerificationStatus: (json['rutVerification'] is Map)
          ? (json['rutVerification'] as Map)['status']?.toString()
          : null,
      licenseVerificationStatus: (json['licenseVerification'] is Map)
          ? (json['licenseVerification'] as Map)['status']?.toString()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'identity': identity.toJson(),
      'contact': contact.toJson(),
      'address': address?.toJson(),
      'addressSlots': {
        for (final e in addressSlots.entries) e.key: e.value.toJson(),
      },
      'primaryAddressSlot': primaryAddressSlot,
      'roles': roles,
      'status': status.toJson(),
      'heroProfile': heroProfile?.toJson(),
      'riderProfile': riderProfile?.toJson(),
      'profilePhotoUrl': profilePhotoUrl,
      'verificationStatus': verificationStatus,
      if (rutVerificationStatus != null)
        'rutVerification': {
          'status': rutVerificationStatus,
        },
      if (licenseVerificationStatus != null)
        'licenseVerification': {
          'status': licenseVerificationStatus,
        },
    };
  }
}
