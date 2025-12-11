import '../../../../domain/repositories/auth_repository.dart';

class CheckEmailExistsUseCase {
  final AuthRepository _authRepository;

  CheckEmailExistsUseCase(this._authRepository);

  Future<bool> execute(String email) async {
    // Validaciones de negocio
    if (email.isEmpty) {
      throw Exception('El correo electrónico es requerido');
    }
    
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(email)) {
      throw Exception('El correo electrónico no es válido');
    }

    return await _authRepository.checkEmailExists(email);
  }
}
