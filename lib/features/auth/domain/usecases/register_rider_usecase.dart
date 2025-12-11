import '../../../../domain/repositories/auth_repository.dart';
import '../../../../domain/entities/user.dart';

/// Caso de uso para registrar un usuario Rider
class RegisterRiderUseCase {
  final AuthRepository _authRepository;

  RegisterRiderUseCase(this._authRepository);

  /// Ejecuta el caso de uso de registro Rider
  Future<User> execute({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String rut,
    required String phone,
  }) async {
    // Validaciones de negocio pueden ir aquí
    if (email.isEmpty || password.isEmpty) {
      throw Exception('Email y contraseña son requeridos');
    }

    return await _authRepository.registerRider(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      rut: rut,
      phone: phone,
    );
  }
}
