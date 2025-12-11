import '../../../../domain/repositories/auth_repository.dart';
import '../../../../domain/entities/user.dart';

class GetUserProfileUseCase {
  final AuthRepository _authRepository;

  GetUserProfileUseCase(this._authRepository);

  Future<User?> execute() async {
    return await _authRepository.getCurrentUser();
  }
}
