import '../../../../domain/repositories/auth_repository.dart';
import '../../../../domain/entities/user.dart';

/// Caso de uso para registrar un usuario con Google
/// Crea un usuario con datos mínimos (email y rol)
/// Los demás campos (firstName, lastName, etc.) quedan null
class RegisterGoogleUserUseCase {
  final AuthRepository _authRepository;

  RegisterGoogleUserUseCase(this._authRepository);

  Future<User> execute({
    required String email,
    required UserRole role,
  }) async {
    if (email.isEmpty) {
      throw Exception('Email es requerido');
    }

    return await _authRepository.registerGoogleUser(
      email: email,
      role: role,
    );
  }
}
