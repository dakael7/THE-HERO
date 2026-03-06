import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/entities/user.dart';
import '../../domain/providers/get_current_user_usecase_provider.dart';
import 'auth_provider.dart';
import '../../../../data/providers/network_providers.dart';

final sessionCheckProvider = FutureProvider<bool>((ref) async {
  final authNotifier = ref.read(authNotifierProvider.notifier);
  await authNotifier.loadSavedSession();
  return ref.read(authNotifierProvider).isAuthenticated;
});

final emailVerifiedCheckProvider = FutureProvider<bool>((ref) async {
  final auth = ref.read(firebaseAuthProvider);
  final user = auth.currentUser;
  if (user == null) return false;

  await user.reload();
  final refreshed = auth.currentUser;
  return refreshed?.emailVerified ?? false;
});

final currentUserProvider = FutureProvider<User?>((ref) async {
  final getCurrentUserUseCase = ref.read(getCurrentUserUseCaseProvider);
  return await getCurrentUserUseCase.execute();
});
