import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/user.dart';
import '../../../../data/models/user_model.dart';
import '../../../../data/mappers/user_mapper.dart';
import '../providers/auth_provider.dart';
import 'registro_hero.dart';
import 'registro_rider.dart';
import '../../../hero/presentation/views/hero_home_screen.dart';
import '../../../rider/presentation/views/rider_home_screen.dart';
import 'unverified_email_screen.dart';
import 'login_page.dart';
import '../../domain/providers/get_current_user_usecase_provider.dart';
import '../../../../data/providers/network_providers.dart';

class EmailVerificationScreen extends ConsumerStatefulWidget {
  final UserRole userRole;

  const EmailVerificationScreen({super.key, required this.userRole});

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _ResolvedGoogleRoutingUser {
  final User user;
  final bool hasFirebaseSnapshot;

  const _ResolvedGoogleRoutingUser({
    required this.user,
    required this.hasFirebaseSnapshot,
  });
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _accountExists = false;
  bool _requiresGoogleSignIn = false;
  bool _obscurePassword = true;
  bool _navigated = false;

  Future<_ResolvedGoogleRoutingUser> _resolveFreshGoogleUser(
    User fallback,
  ) async {
    final uid = fallback.id.trim();
    if (uid.isEmpty) {
      return _ResolvedGoogleRoutingUser(
        user: fallback,
        hasFirebaseSnapshot: false,
      );
    }

    final firestore = ref.read(firebaseFirestoreProvider);
    final authPhotoUrl =
        (fb_auth.FirebaseAuth.instance.currentUser?.photoURL ?? '').trim();

    User withAuthPhoto(User user) {
      if ((user.profilePhotoUrl ?? '').trim().isNotEmpty ||
          authPhotoUrl.isEmpty) {
        return user;
      }
      return user.copyWith(profilePhotoUrl: authPhotoUrl);
    }

    int scoreByKeyFields(User user) {
      var score = 0;
      final requiredDocumentId = widget.userRole == UserRole.rider
          ? user.rutDocumentId
          : user.profileDocumentId;
      if (requiredDocumentId.trim().isNotEmpty) score += 3;
      if (user.contact.phoneNumber.trim().isNotEmpty) score += 3;
      if (widget.userRole == UserRole.hero ? user.isHero : user.isRider) {
        score += 3;
      }
      if (user.identity.firstName.trim().isNotEmpty) score += 1;
      if (user.identity.lastName.trim().isNotEmpty) score += 1;
      return score;
    }

    Future<User?> readUserDoc({
      GetOptions? options,
      Duration timeout = const Duration(milliseconds: 1500),
    }) async {
      try {
        final docRef = firestore.collection('users').doc(uid);
        final future = options == null ? docRef.get() : docRef.get(options);
        final doc = await future.timeout(timeout);
        final data = doc.data();
        if (!doc.exists || data == null) return null;
        return UserMapper.toEntity(UserModel.fromJson({'id': uid, ...data}));
      } catch (_) {
        return null;
      }
    }

    var bestUser = withAuthPhoto(fallback);
    var bestScore = scoreByKeyFields(bestUser);
    var hasFirebaseSnapshot = false;

    void consider(User? candidate) {
      if (candidate == null) return;
      final fixed = withAuthPhoto(candidate);
      final score = scoreByKeyFields(fixed);
      if (score > bestScore) {
        bestUser = fixed;
        bestScore = score;
      }
    }

    // 1) Fast local/cache read first.
    consider(
      await readUserDoc(
        options: const GetOptions(source: Source.cache),
        timeout: const Duration(milliseconds: 300),
      ),
    );
    if (bestScore >= 9) {
      return _ResolvedGoogleRoutingUser(
        user: bestUser,
        hasFirebaseSnapshot: hasFirebaseSnapshot,
      );
    }

    // 2) Fast server read with bounded timeout.
    final serverUser = await readUserDoc(
      options: const GetOptions(source: Source.server),
      timeout: const Duration(milliseconds: 2200),
    );
    if (serverUser != null) {
      hasFirebaseSnapshot = true;
      consider(serverUser);
    }
    if (bestScore >= 9) {
      return _ResolvedGoogleRoutingUser(
        user: bestUser,
        hasFirebaseSnapshot: hasFirebaseSnapshot,
      );
    }

    // 3) Default read as a short fallback.
    consider(await readUserDoc(timeout: const Duration(milliseconds: 1200)));

    if ((bestUser.profilePhotoUrl ?? '').trim().isEmpty &&
        authPhotoUrl.isNotEmpty) {
      bestUser = bestUser.copyWith(profilePhotoUrl: authPhotoUrl);
      unawaited(() async {
        try {
          await firestore.collection('users').doc(uid).set({
            'profilePhotoUrl': authPhotoUrl,
            'status': {'lastUpdated': DateTime.now().toIso8601String()},
          }, SetOptions(merge: true));
        } catch (_) {}
      }());
    }

    return _ResolvedGoogleRoutingUser(
      user: bestUser,
      hasFirebaseSnapshot: hasFirebaseSnapshot,
    );
  }

  static final Uri _termsAndConditionsUri = Uri.parse(
    'https://theheroprojects.com/privacy-policy',
  );

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleBackToLogin() async {
    if (_navigated) return;
    _navigated = true;
    try {
      await ref.read(authNotifierProvider.notifier).signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void _showErrorDialog(String errorMessage) {
    final isGoogleFallback = errorMessage.toLowerCase().contains('google');
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isGoogleFallback ? Icons.g_mobiledata : Icons.lock_outline,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isGoogleFallback
                      ? 'Inicia sesión con Google'
                      : 'Error de Autenticación',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textGray900,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                errorMessage,
                style: const TextStyle(
                  fontSize: 14,
                  color: textGray700,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: primaryOrange,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isGoogleFallback
                            ? 'Usa el botón "Continuar con Google" para entrar.'
                            : 'Verifica tus credenciales',
                        style: const TextStyle(
                          fontSize: 12,
                          color: primaryOrange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Intentar de nuevo',
                style: TextStyle(
                  color: primaryOrange,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
          actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
        );
      },
    );
  }

  Future<bool> _tryActivateExistingRole(
    User user,
    void Function(String message) logRoute,
  ) async {
    final uid = (fb_auth.FirebaseAuth.instance.currentUser?.uid ?? user.id)
        .trim();
    final firstName = user.identity.firstName.trim();
    final lastName = user.identity.lastName.trim();
    final phone = user.contact.phoneNumber.trim();

    if (uid.isEmpty || firstName.isEmpty || lastName.isEmpty || phone.isEmpty) {
      return false;
    }

    final authNotifier = ref.read(authNotifierProvider.notifier);
    if (widget.userRole == UserRole.hero) {
      final documentId = user.profileDocumentId.trim();
      if (documentId.isEmpty) return false;
      await authNotifier.upgradeToHero(
        uid: uid,
        firstName: firstName,
        lastName: lastName,
        documentType: user.profileDocumentType,
        documentId: documentId,
        phone: phone,
      );
      final state = ref.read(authNotifierProvider);
      if (state.errorMessage != null) {
        logRoute('auto_upgrade_hero failed error=${state.errorMessage}');
        return false;
      }
      await authNotifier.saveLastRole('hero');
      if (!mounted) return true;
      logRoute('route=hero_home auto_upgrade=true');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HeroHomeScreen()),
      );
      return true;
    }

    final rut = user.rutDocumentId.trim();
    if (rut.isEmpty) return false;
    await authNotifier.upgradeToRider(
      uid: uid,
      firstName: firstName,
      lastName: lastName,
      rut: rut,
      phone: phone,
    );
    final state = ref.read(authNotifierProvider);
    if (state.errorMessage != null) {
      logRoute('auto_upgrade_rider failed error=${state.errorMessage}');
      return false;
    }
    await authNotifier.saveLastRole('rider');
    if (!mounted) return true;
    logRoute('route=rider_home auto_upgrade=true');
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
    );
    return true;
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    await Future<void>.delayed(const Duration(milliseconds: 16));

    void logRoute(String message) {
      final ts = DateTime.now().toIso8601String();
      debugPrint('[AUTH][ROUTE][$ts] $message');
    }

    try {
      final authNotifier = ref.read(authNotifierProvider.notifier);
      logRoute('google_sign_in:start role=${widget.userRole}');
      final currentUser = await authNotifier.signInWithGoogleAndCreateUser(
        widget.userRole,
      );
      if (!mounted) return;

      final authUser = fb_auth.FirebaseAuth.instance.currentUser;
      final isEmailVerified = authUser?.emailVerified ?? false;

      if (!isEmailVerified) {
        logRoute('route=unverified_email isEmailVerified=$isEmailVerified');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => UnverifiedEmailScreen(
              userRole: widget.userRole,
              email: currentUser.email,
            ),
          ),
        );
        return;
      }

      final resolvedUser = await _resolveFreshGoogleUser(currentUser).timeout(
        const Duration(milliseconds: 1800),
        onTimeout: () => _ResolvedGoogleRoutingUser(
          user: currentUser,
          hasFirebaseSnapshot: false,
        ),
      );
      final routedUser = resolvedUser.user;
      final hasFirebaseSnapshot = resolvedUser.hasFirebaseSnapshot;
      final missingDocId = widget.userRole == UserRole.rider
          ? routedUser.rutDocumentId.trim().isEmpty
          : routedUser.profileDocumentId.trim().isEmpty;
      final missingPhone = routedUser.contact.phoneNumber.trim().isEmpty;
      final needsCriticalData =
          hasFirebaseSnapshot && (missingDocId || missingPhone);

      final missingPhoto = (routedUser.profilePhotoUrl ?? '').trim().isEmpty;

      logRoute(
        'profile_check uid=${routedUser.id} roleWanted=${widget.userRole} roles=${routedUser.roles} hasFirebaseSnapshot=$hasFirebaseSnapshot missingDocId=$missingDocId missingPhone=$missingPhone missingPhoto=$missingPhoto isHero=${routedUser.isHero} isRider=${routedUser.isRider}',
      );

      if (widget.userRole == UserRole.hero) {
        final needsRoleUpgrade = hasFirebaseSnapshot && !routedUser.isHero;
        if (needsRoleUpgrade &&
            !needsCriticalData &&
            await _tryActivateExistingRole(routedUser, logRoute)) {
          return;
        }
        if (needsCriticalData || needsRoleUpgrade) {
          logRoute(
            'route=register_hero reason needsCriticalData=$needsCriticalData needsRoleUpgrade=$needsRoleUpgrade isHero=${routedUser.isHero} missingPhoto=$missingPhoto',
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => RegisterHeroScreen(
                email: routedUser.email,
                existingUser: routedUser,
              ),
            ),
          );
          return;
        }

        await ref.read(authNotifierProvider.notifier).saveLastRole('hero');
        if (!mounted) return;
        logRoute('route=hero_home');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HeroHomeScreen()),
        );
        return;
      }

      final needsRoleUpgrade = hasFirebaseSnapshot && !routedUser.isRider;
      if (needsRoleUpgrade &&
          !needsCriticalData &&
          await _tryActivateExistingRole(routedUser, logRoute)) {
        return;
      }
      if (needsCriticalData || needsRoleUpgrade) {
        logRoute(
          'route=register_rider reason needsCriticalData=$needsCriticalData needsRoleUpgrade=$needsRoleUpgrade isRider=${routedUser.isRider} missingPhoto=$missingPhoto',
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RegisterRiderScreen(
              email: routedUser.email,
              existingUser: routedUser,
            ),
          ),
        );
        return;
      }

      await ref.read(authNotifierProvider.notifier).saveLastRole('rider');
      if (!mounted) return;
      logRoute('route=rider_home');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      final authState = ref.read(authNotifierProvider);
      final rawMessage = authState.errorMessage ?? e.toString();
      final message = rawMessage.startsWith('Exception: ')
          ? rawMessage.substring('Exception: '.length)
          : rawMessage;
      logRoute('google_sign_in:exception error=$e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 3000),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkEmail() async {
    if (_emailController.text.trim().isEmpty) {
      return;
    }

    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(_emailController.text.trim())) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final normalizedEmail = email.trim().toLowerCase();
      final querySnapshot = await ref
          .read(firebaseFirestoreProvider)
          .collection('users')
          .where('contact.email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();

      final exists = querySnapshot.docs.isNotEmpty;
      final authProvider = exists
          ? (querySnapshot.docs.first.data()['authProvider']?.toString() ?? '')
          : '';

      final requiresGoogle = exists && authProvider == 'google';
      final accountExists = exists && !requiresGoogle;

      if (mounted) {
        setState(() {
          _accountExists = accountExists;
          _requiresGoogleSignIn = requiresGoogle;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _accountExists = false;
          _requiresGoogleSignIn = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final email = _emailController.text.trim();

        if (_accountExists) {
          final password = _passwordController.text;

          await ref
              .read(authNotifierProvider.notifier)
              .signInWithEmail(email, password);

          if (mounted) {
            final authState = ref.read(authNotifierProvider);

            if (authState.isAuthenticated && authState.errorMessage == null) {
              final currentUser = await ref
                  .read(getCurrentUserUseCaseProvider)
                  .execute();

              if (currentUser == null) {
                _showErrorDialog('Error al obtener datos del usuario');
                return;
              }

              final authUser = fb_auth.FirebaseAuth.instance.currentUser;
              final isEmailVerified = authUser?.emailVerified ?? false;

              if (!isEmailVerified || !currentUser.contact.emailVerified) {
                if (!context.mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UnverifiedEmailScreen(
                      userRole: widget.userRole,
                      email: currentUser.email,
                    ),
                  ),
                );
                return;
              }

              if (widget.userRole == UserRole.hero) {
                if (!currentUser.isHero) {
                  if (await _tryActivateExistingRole(
                    currentUser,
                    (message) => debugPrint('[AUTH][ROUTE] $message'),
                  )) {
                    return;
                  }
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RegisterHeroScreen(
                          email: currentUser.email,
                          existingUser: currentUser,
                        ),
                      ),
                    );
                  }
                  return;
                }
                await ref
                    .read(authNotifierProvider.notifier)
                    .saveLastRole('hero');
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HeroHomeScreen(),
                  ),
                );
              } else {
                if (!currentUser.isRider) {
                  if (await _tryActivateExistingRole(
                    currentUser,
                    (message) => debugPrint('[AUTH][ROUTE] $message'),
                  )) {
                    return;
                  }
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RegisterRiderScreen(
                          email: currentUser.email,
                          existingUser: currentUser,
                        ),
                      ),
                    );
                  }
                  return;
                }

                await ref
                    .read(authNotifierProvider.notifier)
                    .saveLastRole('rider');

                final uid = (await ref.read(
                  firebaseAuthUserProvider.future,
                ))?.uid;
                if (uid != null && currentUser.riderProfile?.isActive != true) {
                  try {
                    await ref
                        .read(firebaseFirestoreProvider)
                        .collection('users')
                        .doc(uid)
                        .update({'riderProfile.isActive': true});
                  } catch (_) {}
                }

                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RiderHomeScreen(),
                  ),
                );
              }
            } else {
              if (authState.errorMessage != null) {
                _showErrorDialog(authState.errorMessage!);
              }
            }
          }
        } else {
          if (widget.userRole == UserRole.hero) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RegisterHeroScreen(email: email),
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => RegisterRiderScreen(email: email),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          _showErrorDialog('Error inesperado: ${e.toString()}');
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  String _getRoleBadgeLabel() {
    return widget.userRole == UserRole.hero ? 'Cuenta Hero' : 'Cuenta Rider';
  }

  String _getRoleDescription() {
    return 'Introduce tu correo electrónico para continuar';
  }

  InputDecoration _getEmailInputDecoration() {
    return InputDecoration(
      hintText: 'email@domain.com',
      hintStyle: TextStyle(color: textGray600.withValues(alpha: 0.5)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey, width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryOrange, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackToLogin();
      },
      child: Scaffold(
        backgroundColor: backgroundGray50,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: textGray900),
            onPressed: _handleBackToLogin,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildLogoSection(),

                  const SizedBox(height: 30),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: primaryOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _getRoleBadgeLabel(),
                      style: TextStyle(
                        color: primaryOrange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Verifica tu correo',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: textGray900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _getRoleDescription(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: textGray600),
                  ),

                  const SizedBox(height: 40),

                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_isLoading,
                    onChanged: (value) {
                      if (_accountExists || _requiresGoogleSignIn) {
                        setState(() {
                          _accountExists = false;
                          _requiresGoogleSignIn = false;
                          _passwordController.clear();
                        });
                      }
                    },
                    style: const TextStyle(
                      color: textGray900,
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                    ),
                    decoration: _getEmailInputDecoration(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor ingresa un correo';
                      }
                      final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                      if (!emailRegex.hasMatch(value)) {
                        return 'Ingresa un correo válido';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 20),

                  if (_accountExists) ...[
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      enabled: !_isLoading,
                      style: const TextStyle(color: textGray900, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'Contraseña',
                        hintStyle: TextStyle(
                          color: textGray600.withValues(alpha: 0.5),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Colors.grey,
                            width: 1.0,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.grey.shade300,
                            width: 1.0,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: primaryOrange,
                            width: 2,
                          ),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: textGray600,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (_accountExists) {
                          if (value == null || value.isEmpty) {
                            return 'Por favor ingresa tu contraseña';
                          }
                          if (value.length < 6) {
                            return 'La contraseña debe tener al menos 6 caracteres';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () async {
                                final email = _emailController.text.trim();
                                if (email.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Por favor ingresa tu correo para recuperar tu contraseña.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                try {
                                  await ref
                                      .read(authNotifierProvider.notifier)
                                      .resetPassword(email);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Te enviamos un correo para recuperar tu contraseña.',
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.toString())),
                                  );
                                }
                              },
                        child: const Text(
                          '¿Olvidaste tu contraseña?',
                          style: TextStyle(
                            color: primaryOrange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () async {
                              if (!_accountExists &&
                                  _emailController.text.trim().isNotEmpty) {
                                await _checkEmail();
                                if (_requiresGoogleSignIn) {
                                  _showErrorDialog(
                                    'Esta cuenta está registrada con Google. Inicia sesión con Google.',
                                  );
                                  return;
                                }
                                if (_accountExists) {
                                  return;
                                }
                              }
                              _submitForm();
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryOrange,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2.0,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              _accountExists
                                  ? 'Ingresar'
                                  : (_requiresGoogleSignIn
                                        ? 'Continuar con Google'
                                        : 'Continuar'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Center(
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              final email = _emailController.text.trim();
                              if (widget.userRole == UserRole.hero) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => RegisterHeroScreen(
                                      email: email.isNotEmpty ? email : null,
                                    ),
                                  ),
                                );
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => RegisterRiderScreen(
                                      email: email.isNotEmpty ? email : null,
                                    ),
                                  ),
                                );
                              }
                            },
                      child: RichText(
                        text: const TextSpan(
                          text: '¿No tienes cuenta? ',
                          style: TextStyle(color: textGray600, fontSize: 14),
                          children: [
                            TextSpan(
                              text: 'Regístrate',
                              style: TextStyle(
                                color: primaryOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('o', style: TextStyle(color: textGray600)),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),

                  const SizedBox(height: 30),

                  _buildSocialButton(
                    iconWidget: SvgPicture.asset(
                      'assets/icono-google.svg',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      placeholderBuilder: (context) {
                        return Icon(
                          Icons.g_mobiledata,
                          color: Colors.blue.shade700,
                          size: 28,
                        );
                      },
                    ),
                    label: 'Continuar con Google',
                    isApple: false,
                    onTap: _isLoading
                        ? null
                        : () async {
                            await _handleGoogleSignIn();
                          },
                  ),

                  const SizedBox(height: 40),

                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Al hacer clic en continuar, aceptas nuestros ',
                          style: TextStyle(
                            fontSize: 12,
                            color: textGray600.withValues(alpha: 0.7),
                          ),
                        ),
                        InkWell(
                          onTap: () async {
                            await launchUrl(
                              _termsAndConditionsUri,
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          child: const Text(
                            'Términos y Condiciones',
                            style: TextStyle(
                              fontSize: 12,
                              color: primaryOrange,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        Text(
                          '.',
                          style: TextStyle(
                            fontSize: 12,
                            color: textGray600.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    // Optimización: RepaintBoundary para logo
    return RepaintBoundary(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/logo_1.png', height: 80, fit: BoxFit.contain),
        ],
      ),
    );
  }

  Widget _buildSocialButton({
    IconData? icon,
    Widget? iconWidget,
    required String label,
    required VoidCallback? onTap,
    required bool isApple,
  }) {
    // Optimización: RepaintBoundary para botones sociales
    return RepaintBoundary(
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon:
              iconWidget ??
              Icon(
                icon,
                color: isApple ? Colors.black : Colors.blue.shade700,
                size: 28,
              ),
          label: Text(
            label,
            style: const TextStyle(
              color: textGray900,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.blue.shade50.withValues(alpha: 0.5),
            side: BorderSide.none,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}
