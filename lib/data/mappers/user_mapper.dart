import '../../domain/entities/user.dart';
import '../../domain/entities/address.dart';
import '../models/user_model.dart';
import '../models/identity_model.dart';
import '../models/contact_model.dart';
import '../models/address_model.dart';
import '../models/hero_profile_model.dart';
import '../models/rider_profile_model.dart';
import '../models/user_status_model.dart';

class UserMapper {
  /// Convierte UserModel (Data) a User (Domain)
  static User toEntity(UserModel model) {
    final addressUnits = <AddressUnitType, Address>{};
    for (final entry in model.addressUnits.entries) {
      try {
        final t = AddressUnitType.fromString(entry.key);
        addressUnits[t] = entry.value.toEntity();
      } catch (_) {
        // Ignore invalid keys
      }
    }

    AddressUnitType? primaryType;
    final rawPrimary = model.primaryAddressUnitType;
    if (rawPrimary != null && rawPrimary.trim().isNotEmpty) {
      try {
        primaryType = AddressUnitType.fromString(rawPrimary);
      } catch (_) {
        primaryType = null;
      }
    }

    return User(
      id: model.id,
      identity: model.identity.toEntity(),
      contact: model.contact.toEntity(),
      address: model.address?.toEntity(),
      addressUnits: addressUnits,
      primaryAddressUnitType: primaryType,
      roles: model.roles.map((r) => UserRole.fromString(r)).toList(),
      status: model.status.toEntity(),
      heroProfile: model.heroProfile?.toEntity(),
      riderProfile: model.riderProfile?.toEntity(),
      profilePhotoUrl: model.profilePhotoUrl,
      verificationStatus: model.verificationStatus,
      rutVerificationStatus: model.rutVerificationStatus,
      licenseVerificationStatus: model.licenseVerificationStatus,
    );
  }

  /// Convierte User (Domain) a UserModel (Data)
  static UserModel toModel(User entity) {
    return UserModel(
      id: entity.id,
      identity: IdentityModel.fromEntity(entity.identity),
      contact: ContactModel.fromEntity(entity.contact),
      address: entity.address != null ? AddressModel.fromEntity(entity.address!) : null,
      addressUnits: {
        for (final e in entity.addressUnits.entries)
          e.key.jsonValue: AddressModel.fromEntity(e.value),
      },
      primaryAddressUnitType: entity.primaryAddressUnitType?.jsonValue,
      roles: entity.roles.map((r) => r.name).toList(),
      status: UserStatusModel.fromEntity(entity.status),
      heroProfile: entity.heroProfile != null ? HeroProfileModel.fromEntity(entity.heroProfile!) : null,
      riderProfile: entity.riderProfile != null ? RiderProfileModel.fromEntity(entity.riderProfile!) : null,
      profilePhotoUrl: entity.profilePhotoUrl,
      verificationStatus: entity.verificationStatus,
      rutVerificationStatus: entity.rutVerificationStatus,
      licenseVerificationStatus: entity.licenseVerificationStatus,
    );
  }
}
