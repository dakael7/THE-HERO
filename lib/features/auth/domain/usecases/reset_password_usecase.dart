import '../../../../domain/repositories/auth_repository.dart';

class ResetPasswordUseCase {
  final AuthRepository _authRepository;

  ResetPasswordUseCase(this._authRepository);

  Future<void> execute(String email) async {
    if (email.trim().isEmpty) {
      throw Exception('Por favor ingresa un correo.');
    }
    return await _authRepository.resetPassword(email.trim());
  }
}
