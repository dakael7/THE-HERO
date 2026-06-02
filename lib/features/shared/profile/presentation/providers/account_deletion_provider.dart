import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../../../core/services/fcm_service.dart';

class AccountDeletionNotifier extends Notifier<AsyncValue<void>> {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  @override
  AsyncValue<void> build() {
    return const AsyncValue.data(null);
  }

  Future<void> deleteCurrentAccount() async {
    state = const AsyncValue.loading();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Debes iniciar sesion para eliminar tu cuenta');
      }

      try {
        await FCMService()
            .cleanupBeforeSignOut()
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Best-effort: account deletion must not be blocked by FCM cleanup.
      }

      await user.getIdToken(true);
      final callable = _functions.httpsCallable('deleteMyAccount');
      await callable.call(<String, dynamic>{'confirm': true});

      try {
        await GoogleSignIn.instance.signOut().timeout(
          const Duration(seconds: 6),
        );
      } catch (_) {
        // Firebase signOut below is the important local cleanup.
      }

      await FirebaseAuth.instance.signOut();
      state = const AsyncValue.data(null);
    } on FirebaseFunctionsException catch (error, stackTrace) {
      final message = _messageFromFunctionsError(error);
      state = AsyncValue.error(Exception(message), stackTrace);
      throw Exception(message);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      rethrow;
    }
  }

  String _messageFromFunctionsError(FirebaseFunctionsException error) {
    final details = error.details;
    if (details is String && details.trim().isNotEmpty) {
      return details.trim();
    }

    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }

    return 'No pudimos eliminar la cuenta (${error.code})';
  }
}

final accountDeletionNotifierProvider =
    NotifierProvider<AccountDeletionNotifier, AsyncValue<void>>(
      AccountDeletionNotifier.new,
    );
