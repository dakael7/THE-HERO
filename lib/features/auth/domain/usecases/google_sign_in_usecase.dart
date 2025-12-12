import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleSignInUseCase {
  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;

  GoogleSignInUseCase({
    required FirebaseAuth firebaseAuth,
    required GoogleSignIn googleSignIn,
  })  : _firebaseAuth = firebaseAuth,
        _googleSignIn = googleSignIn;

  Future<UserCredential> execute() async {
    try {
      // 1. Iniciar el flujo de autenticación interactivo (API 7.2.0)
      // authenticate() reemplaza a signIn() y siempre devuelve una cuenta válida
      // o lanza una GoogleSignInException si falla o el usuario cancela.
      // scopeHint ayuda a la plataforma a combinar autenticación + autorización
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate(
        scopeHint: const ['email', 'profile'],
      );

      // 2. Obtener los tokens de autenticación asociados a la cuenta
      final GoogleSignInAuthentication googleAuth = googleUser.authentication;

      // 3. Obtener el idToken
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('No se pudo obtener el idToken de Google');
      }

      // 4. Crear credencial para Firebase
      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );

      // 5. Autenticarse con Firebase
      final UserCredential userCredential =
          await _firebaseAuth.signInWithCredential(credential);

      return userCredential;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw Exception('Google Sign-In cancelado por el usuario');
      }
      throw Exception('Google Sign-In Error: ${e.description}');
    } on FirebaseAuthException catch (e) {
      throw Exception('Firebase Auth Error: ${e.message}');
    } catch (e) {
      throw Exception('Google Sign-In Error: $e');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }
}