import '../../../../domain/repositories/auth_repository.dart';
import '../../../../domain/entities/user.dart';

class LoginUseCase {
  final AuthRepository _authRepository;

  LoginUseCase(this._authRepository);

  Future<User> execute(String email, String password) async {
    // Validaciones de negocio pueden ir aquí
    if (email.isEmpty || password.isEmpty) {
      throw Exception('Email y contraseña son requeridos');
    }

    return await _authRepository.signInWithEmail(email, password);
  }
}
