import '../../domain/entities/user.dart';
import '../models/user_model.dart';

class UserMapper {
  /// Convierte UserModel (Data) a User (Domain)
  static User toEntity(UserModel model) {
    DateTime? parsedDate;
    if (model.createdAt != null && model.createdAt!.isNotEmpty) {
      try {
        parsedDate = DateTime.parse(model.createdAt!);
      } catch (e) {
        parsedDate = null;
      }
    }
    
    return User(
      id: model.id,
      email: model.email,
      firstName: model.firstName,
      lastName: model.lastName,
      rut: model.rut,
      phone: model.phone,
      role: _stringToUserRole(model.role),
      createdAt: parsedDate,
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
