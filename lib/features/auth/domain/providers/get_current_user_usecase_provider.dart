import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../usecases/get_current_user_usecase.dart';
import '../../../../data/providers/repository_providers.dart';

final getCurrentUserUseCaseProvider = Provider<GetCurrentUserUseCase>((ref) {
  final authRepository = ref.read(authRepositoryProvider);
  return GetCurrentUserUseCase(authRepository);
});
