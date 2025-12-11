import '../../../../domain/entities/user.dart';
import '../../../../domain/repositories/auth_repository.dart';

class GetCurrentUserUseCase {
  final AuthRepository _repository;

  GetCurrentUserUseCase(this._repository);

  Future<User?> execute() async {
    return await _repository.getCurrentUser();
  }
}
