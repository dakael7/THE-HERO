import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/providers/repository_providers.dart';
import '../usecases/register_hero_usecase.dart';
import '../usecases/register_rider_usecase.dart';

final registerHeroUseCaseProvider = Provider<RegisterHeroUseCase>((ref) {
  final repository = ref.read(authRepositoryProvider);
  return RegisterHeroUseCase(repository);
});

final registerRiderUseCaseProvider = Provider<RegisterRiderUseCase>((ref) {
  final repository = ref.read(authRepositoryProvider);
  return RegisterRiderUseCase(repository);
});
