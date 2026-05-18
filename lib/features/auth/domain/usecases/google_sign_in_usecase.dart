import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInUseCase {
  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  void _logGsi(String message) {
    final ts = DateTime.now().toIso8601String();
    print('[AUTH][GSI][$ts] $message');
  }

  Future<UserCredential> _signInWithFirebase(
    OAuthCredential credential,
    Stopwatch sw,
  ) async {
    for (int attempt = 1; attempt <= 2; attempt++) {
      _logGsi(
        'stage=firebase_signInWithCredential attempt=$attempt begin elapsedMs=${sw.elapsedMilliseconds}',
      );
      try {
        final res = await _firebaseAuth
            .signInWithCredential(credential)
            .timeout(const Duration(seconds: 45), onTimeout: () {
          _logGsi(
            'stage=firebase_signInWithCredential attempt=$attempt timeout elapsedMs=${sw.elapsedMilliseconds}',
          );
          throw TimeoutException(
            'timeout_stage=firebase_signInWithCredential attempt=$attempt',
          );
        });
        _logGsi(
          'stage=firebase_signInWithCredential attempt=$attempt end elapsedMs=${sw.elapsedMilliseconds} uid=${res.user?.uid}',
        );
        return res;
      } on TimeoutException catch (e) {
        if (attempt >= 2) {
          rethrow;
        }
        _logGsi(
          'stage=firebase_signInWithCredential retry_scheduled attempt=$attempt elapsedMs=${sw.elapsedMilliseconds} reason=${e.message}',
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    }
    throw TimeoutException('timeout_stage=firebase_signInWithCredential');
  }

  bool _isStaleGoogleCredentialError(FirebaseAuthException e) {
    final code = e.code.toLowerCase();
    final message = (e.message ?? '').toLowerCase();
    return (message.contains('id token issued at') &&
            message.contains('stale')) ||
        (message.contains('credential') && message.contains('expired')) ||
        (code == 'invalid-credential' && message.contains('token'));
  }

  GoogleSignInUseCase({
    required FirebaseAuth firebaseAuth,
    required GoogleSignIn googleSignIn,
  }) : _firebaseAuth = firebaseAuth,
       _googleSignIn = googleSignIn;

  Future<UserCredential> execute() async {
    final sw = Stopwatch()..start();
    try {
      _logGsi('stage=preflight begin elapsedMs=${sw.elapsedMilliseconds}');

      // Force credential manager to avoid reusing old local state.
      try {
        await _googleSignIn.signOut().timeout(const Duration(seconds: 6));
      } catch (_) {}

      _logGsi('stage=google_authenticate begin');
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate(
        scopeHint: const ['email', 'profile'],
      );
      _logGsi(
        'stage=google_authenticate end elapsedMs=${sw.elapsedMilliseconds} email=${googleUser.email}',
      );

      _logGsi('stage=google_tokens begin');
      final GoogleSignInAuthentication googleAuth =
          await Future<GoogleSignInAuthentication>.sync(
            () => googleUser.authentication,
          ).timeout(const Duration(seconds: 20), onTimeout: () {
            throw TimeoutException('timeout_stage=google_tokens');
          });
      _logGsi(
        'stage=google_tokens end elapsedMs=${sw.elapsedMilliseconds} hasIdToken=${googleAuth.idToken != null}',
      );

      final String? idToken = googleAuth.idToken;
      if (idToken == null) {
        throw Exception('No se pudo obtener el idToken de Google');
      }

      String? accessToken;
      try {
        final authz = await googleUser.authorizationClient
            .authorizationForScopes(const ['email', 'profile'])
            .timeout(const Duration(seconds: 10));
        accessToken = authz?.accessToken;
      } catch (_) {
        accessToken = null;
      }

      _logGsi('stage=firebase_credential_create begin');
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: idToken,
        accessToken: accessToken,
      );
      _logGsi(
        'stage=firebase_credential_create end elapsedMs=${sw.elapsedMilliseconds}',
      );

      return await _signInWithFirebase(credential, sw);
    } on TimeoutException catch (e) {
      throw Exception(
        'Tiempo de espera agotado en Google Sign-In (${e.message ?? 'timeout'}) - revisa conectividad y Google Play Services',
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        _logGsi(
          'stage=google_canceled elapsedMs=${sw.elapsedMilliseconds} description=${e.description}',
        );
        throw Exception(
          'Google Sign-In cancelado (usuario o sistema/Credential Manager). Si no tocaste nada, puede ser cierre automatico del selector o un problema de Google Play Services.',
        );
      }
      _logGsi(
        'stage=google_exception elapsedMs=${sw.elapsedMilliseconds} code=${e.code} description=${e.description}',
      );
      throw Exception('Google Sign-In Error: ${e.description}');
    } on FirebaseAuthException catch (e) {
      _logGsi(
        'stage=firebase_auth_exception elapsedMs=${sw.elapsedMilliseconds} code=${e.code} message=${e.message}',
      );
      if (_isStaleGoogleCredentialError(e)) {
        throw Exception(
          'Firebase Auth Error: token de Google vencido. Vuelve a intentar iniciar sesion.',
        );
      }
      throw Exception('Firebase Auth Error: ${e.message}');
    } catch (e) {
      _logGsi(
        'stage=unexpected_exception elapsedMs=${sw.elapsedMilliseconds} error=$e',
      );
      throw Exception('Google Sign-In Error: $e');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }
}
