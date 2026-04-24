import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/entities/user.dart';
import '../../../../data/providers/repository_providers.dart';
import '../../domain/providers/get_current_user_usecase_provider.dart';
import 'auth_provider.dart';
import '../../../../data/providers/network_providers.dart';

class AppBootstrapState {
  final bool isAuthenticated;
  final User? user;
  final bool isEmailVerified;
  final String? lastRole;

  const AppBootstrapState({
    required this.isAuthenticated,
    required this.user,
    required this.isEmailVerified,
    required this.lastRole,
  });

  const AppBootstrapState.unauthenticated()
    : isAuthenticated = false,
      user = null,
      isEmailVerified = false,
      lastRole = null;
}

final sessionCheckProvider = FutureProvider<bool>((ref) async {
  final authNotifier = ref.read(authNotifierProvider.notifier);
  await authNotifier.loadSavedSession();
  final auth = ref.read(firebaseAuthProvider);
  return auth.currentUser != null ||
      ref.read(authNotifierProvider).isAuthenticated;
});

final appBootstrapProvider = FutureProvider<AppBootstrapState>((ref) async {
  final auth = ref.read(firebaseAuthProvider);
  final firebaseUser = auth.currentUser;
  if (firebaseUser == null) {
    return const AppBootstrapState.unauthenticated();
  }

  final authRepository = ref.read(authRepositoryProvider);
  final cachedUserFuture = authRepository.getCachedUser();
  final lastRoleFuture = authRepository.getLastRole();

  final cachedUser = await cachedUserFuture;
  final lastRole = await lastRoleFuture;

  if (cachedUser != null) {
    return AppBootstrapState(
      isAuthenticated: true,
      user: cachedUser,
      isEmailVerified: firebaseUser.emailVerified,
      lastRole: lastRole,
    );
  }

  final getCurrentUserUseCase = ref.read(getCurrentUserUseCaseProvider);
  final remoteUser = await getCurrentUserUseCase.execute();

  return AppBootstrapState(
    isAuthenticated: remoteUser != null,
    user: remoteUser,
    isEmailVerified: firebaseUser.emailVerified,
    lastRole: lastRole,
  );
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
