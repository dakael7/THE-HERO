import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/repository_providers.dart';
import '../usecases/check_email_exists_usecase.dart';

final checkEmailExistsUseCaseProvider = Provider<CheckEmailExistsUseCase>((ref) {
  final repository = ref.read(authRepositoryProvider);
  return CheckEmailExistsUseCase(repository);
});
