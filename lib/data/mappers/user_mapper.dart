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
    final addressSlots = <AddressSlot, Address>{};
    for (final entry in model.addressSlots.entries) {
      try {
        final t = AddressSlot.fromString(entry.key);
        addressSlots[t] = entry.value.toEntity();
      } catch (_) {
        // Ignore invalid keys
      }
    }

    AddressSlot? primarySlot;
    final rawPrimary = model.primaryAddressSlot;
    if (rawPrimary != null && rawPrimary.trim().isNotEmpty) {
      try {
        primarySlot = AddressSlot.fromString(rawPrimary);
      } catch (_) {
        primarySlot = null;
      }
    }

    return User(
      id: model.id,
      identity: model.identity.toEntity(),
      contact: model.contact.toEntity(),
      address: model.address?.toEntity(),
      addressSlots: addressSlots,
      primaryAddressSlot: primarySlot,
      roles: model.roles.map((r) => UserRole.fromString(r)).toList(),
      status: model.status.toEntity(),
      heroProfile: model.heroProfile?.toEntity(),
      riderProfile: model.riderProfile?.toEntity(),
      profilePhotoUrl: model.profilePhotoUrl,
      verificationStatus: model.verificationStatus,
      rutVerificationStatus: model.rutVerificationStatus,
      licenseVerificationStatus: model.licenseVerificationStatus,
      accountStatus: model.accountStatus,
      suspendedUntil: model.suspendedUntil,
      suspensionReason: model.suspensionReason,
      reportCount: model.reportCount,
      lastReportedAt: model.lastReportedAt,
    );
  }

  /// Convierte User (Domain) a UserModel (Data)
  static UserModel toModel(User entity) {
    return UserModel(
      id: entity.id,
      identity: IdentityModel.fromEntity(entity.identity),
      contact: ContactModel.fromEntity(entity.contact),
      address: entity.address != null ? AddressModel.fromEntity(entity.address!) : null,
      addressSlots: {
        for (final e in entity.addressSlots.entries)
          e.key.jsonValue: AddressModel.fromEntity(e.value),
      },
      primaryAddressSlot: entity.primaryAddressSlot?.jsonValue,
      roles: entity.roles.map((r) => r.name).toList(),
      status: UserStatusModel.fromEntity(entity.status),
      heroProfile: entity.heroProfile != null ? HeroProfileModel.fromEntity(entity.heroProfile!) : null,
      riderProfile: entity.riderProfile != null ? RiderProfileModel.fromEntity(entity.riderProfile!) : null,
      profilePhotoUrl: entity.profilePhotoUrl,
      verificationStatus: entity.verificationStatus,
      rutVerificationStatus: entity.rutVerificationStatus,
      licenseVerificationStatus: entity.licenseVerificationStatus,
      accountStatus: entity.accountStatus,
      suspendedUntil: entity.suspendedUntil,
      suspensionReason: entity.suspensionReason,
      reportCount: entity.reportCount,
      lastReportedAt: entity.lastReportedAt,
    );
  }
}
