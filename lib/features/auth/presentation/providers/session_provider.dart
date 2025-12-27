import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/entities/user.dart';
import '../../domain/providers/get_current_user_usecase_provider.dart';
import 'auth_provider.dart';

final sessionCheckProvider = FutureProvider<bool>((ref) async {
  final authNotifier = ref.read(authNotifierProvider.notifier);
  await authNotifier.loadSavedSession();
  return ref.read(authNotifierProvider).isAuthenticated;
});

final currentUserProvider = FutureProvider<User?>((ref) async {
  final getCurrentUserUseCase = ref.read(getCurrentUserUseCaseProvider);
  return await getCurrentUserUseCase.execute();
});

final lastRoleProvider = FutureProvider<String?>((ref) async {
  final authNotifier = ref.read(authNotifierProvider.notifier);
  return await authNotifier.getLastRole();
});
