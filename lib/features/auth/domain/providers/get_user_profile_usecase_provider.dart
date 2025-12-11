import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../usecases/get_user_profile_usecase.dart';
import '../../../../data/providers/repository_providers.dart';

final getUserProfileUseCaseProvider = Provider<GetUserProfileUseCase>((ref) {
  final authRepository = ref.read(authRepositoryProvider);
  return GetUserProfileUseCase(authRepository);
});
