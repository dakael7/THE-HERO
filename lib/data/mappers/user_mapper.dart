import '../../domain/entities/user.dart';
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
    return User(
      id: model.id,
      identity: model.identity.toEntity(),
      contact: model.contact.toEntity(),
      address: model.address?.toEntity(),
      roles: model.roles.map((r) => UserRole.fromString(r)).toList(),
      status: model.status.toEntity(),
      heroProfile: model.heroProfile?.toEntity(),
      riderProfile: model.riderProfile?.toEntity(),
    );
  }

  /// Convierte User (Domain) a UserModel (Data)
  static UserModel toModel(User entity) {
    return UserModel(
      id: entity.id,
      identity: IdentityModel.fromEntity(entity.identity),
      contact: ContactModel.fromEntity(entity.contact),
      address: entity.address != null ? AddressModel.fromEntity(entity.address!) : null,
      roles: entity.roles.map((r) => r.name).toList(),
      status: UserStatusModel.fromEntity(entity.status),
      heroProfile: entity.heroProfile != null ? HeroProfileModel.fromEntity(entity.heroProfile!) : null,
      riderProfile: entity.riderProfile != null ? RiderProfileModel.fromEntity(entity.riderProfile!) : null,
    );
  }
}
