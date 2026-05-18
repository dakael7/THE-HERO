import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;

import '../../../../domain/entities/user.dart';
import '../../../../data/providers/repository_providers.dart';
import '../../domain/providers/get_current_user_usecase_provider.dart';
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
  final auth = ref.read(firebaseAuthProvider);
  final firebaseUser = await auth.authStateChanges().first;
  return firebaseUser != null;
});

Future<AppBootstrapState> _resolveBootstrapState({
  required firebase_auth.User? firebaseUser,
  required Ref ref,
}) async {
  if (firebaseUser == null) {
    return const AppBootstrapState.unauthenticated();
  }

  final authRepository = ref.read(authRepositoryProvider);
  final getCurrentUserUseCase = ref.read(getCurrentUserUseCaseProvider);

  final cachedUserFuture = authRepository.getCachedUser();
  final lastRoleFuture = authRepository.getLastRole();

  final cachedUser = await cachedUserFuture;
  final lastRole = await lastRoleFuture;

  if (cachedUser != null && cachedUser.id == firebaseUser.uid) {
    return AppBootstrapState(
      isAuthenticated: true,
      user: cachedUser,
      isEmailVerified: firebaseUser.emailVerified,
      lastRole: lastRole,
    );
  }

  final remoteUser = await getCurrentUserUseCase.execute();
  if (remoteUser == null) {
    return const AppBootstrapState.unauthenticated();
  }

  return AppBootstrapState(
    isAuthenticated: true,
    user: remoteUser,
    isEmailVerified: firebaseUser.emailVerified,
    lastRole: lastRole,
  );
}

final appBootstrapProvider = StreamProvider<AppBootstrapState>((ref) async* {
  final auth = ref.read(firebaseAuthProvider);

  // Emit current snapshot immediately, then react to auth changes.
  yield await _resolveBootstrapState(firebaseUser: auth.currentUser, ref: ref);

  await for (final firebaseUser in auth.authStateChanges()) {
    yield await _resolveBootstrapState(firebaseUser: firebaseUser, ref: ref);
  }
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
