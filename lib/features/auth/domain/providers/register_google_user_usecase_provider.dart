import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../usecases/register_google_user_usecase.dart';
import '../../../../data/providers/repository_providers.dart';

final registerGoogleUserUseCaseProvider = Provider<RegisterGoogleUserUseCase>((ref) {
  final authRepository = ref.read(authRepositoryProvider);
  return RegisterGoogleUserUseCase(authRepository);
});
