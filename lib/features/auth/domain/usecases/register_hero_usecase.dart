import '../../../../domain/repositories/auth_repository.dart';
import '../../../../domain/entities/user.dart';

/// Caso de uso para registrar un usuario Hero
class RegisterHeroUseCase {
  final AuthRepository _authRepository;

  RegisterHeroUseCase(this._authRepository);

  Future<User> execute({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String documentType,
    required String documentId,
    required String phone,
  }) async {
    if (email.isEmpty || password.isEmpty) {
      throw Exception('Email y contraseña son requeridos');
    }

    return await _authRepository.registerHero(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      documentType: documentType,
      documentId: documentId,
      phone: phone,
    );
  }
}
