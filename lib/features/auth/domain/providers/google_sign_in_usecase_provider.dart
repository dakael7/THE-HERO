import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../usecases/google_sign_in_usecase.dart';
import '../../../../data/providers/network_providers.dart';

final googleSignInUseCaseProvider = Provider<GoogleSignInUseCase>((ref) {
  final firebaseAuth = ref.read(firebaseAuthProvider);
  final googleSignIn = GoogleSignIn.instance;
  
  return GoogleSignInUseCase(
    firebaseAuth: firebaseAuth,
    googleSignIn: googleSignIn,
  );
});