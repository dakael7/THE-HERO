import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/repository_providers.dart';
import '../usecases/reset_password_usecase.dart';

final resetPasswordUseCaseProvider = Provider<ResetPasswordUseCase>((ref) {
  final repository = ref.read(authRepositoryProvider);
  return ResetPasswordUseCase(repository);
});
