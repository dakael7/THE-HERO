import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/repository_providers.dart';
import '../usecases/sign_out_usecase.dart';

final signOutUseCaseProvider = Provider<SignOutUseCase>((ref) {
  final repository = ref.read(authRepositoryProvider);
  return SignOutUseCase(repository);
});
