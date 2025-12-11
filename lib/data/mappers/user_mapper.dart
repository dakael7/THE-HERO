import '../../domain/entities/user.dart';
import '../models/user_model.dart';

class UserMapper {
  /// Convierte UserModel (Data) a User (Domain)
  static User toEntity(UserModel model) {
    return User(
      id: model.id,
      email: model.email,
      firstName: model.firstName,
      lastName: model.lastName,
      rut: model.rut,
      phone: model.phone,
      role: _stringToUserRole(model.role),
      createdAt: model.createdAt != null
          ? DateTime.parse(model.createdAt!)
          : null,
    );
  }

  /// Convierte User (Domain) a UserModel (Data)

  static UserModel toModel(User entity) {
    return UserModel(
      id: entity.id,
      email: entity.email,
      firstName: entity.firstName,
      lastName: entity.lastName,
      rut: entity.rut,
      phone: entity.phone,
      role: entity.role.name, // Convertir enum a string
      createdAt: entity.createdAt?.toIso8601String(),
    );
  }

  static UserRole _stringToUserRole(String role) {
    switch (role.toLowerCase()) {
      case 'hero':
        return UserRole.hero;
      case 'rider':
        return UserRole.rider;
      default:
        return UserRole.hero;
    }
  }
}
