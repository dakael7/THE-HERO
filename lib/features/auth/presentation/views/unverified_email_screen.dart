import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/user.dart';
import '../providers/auth_provider.dart';
import 'login_page.dart';
import '../../../hero/presentation/views/hero_home_screen.dart';
import '../../../rider/presentation/views/rider_home_screen.dart';

class UnverifiedEmailScreen extends ConsumerStatefulWidget {
  final UserRole userRole;
  final String email;

  const UnverifiedEmailScreen({
    super.key,
    required this.userRole,
    required this.email,
  });

  @override
  ConsumerState<UnverifiedEmailScreen> createState() =>
      _UnverifiedEmailScreenState();
}

class _UnverifiedEmailScreenState extends ConsumerState<UnverifiedEmailScreen> {
  Timer? _pollTimer;
  Timer? _resendTimer;
  bool _checking = false;
  bool _navigated = false;
  bool _resending = false;
  int _resendSecondsRemaining = 0;

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 2500),
      ),
    );
  }

  void _startResendCooldown({int seconds = 60}) {
    _resendTimer?.cancel();
    setState(() {
      _resendSecondsRemaining = seconds;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSecondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _resendSecondsRemaining = 0;
        });
        return;
      }
      setState(() {
        _resendSecondsRemaining -= 1;
      });
    });
  }

  Future<void> _handleResendEmail() async {
    if (_resending) return;
    if (_resendSecondsRemaining > 0) return;

    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar('Sesión no válida. Vuelve a iniciar sesión.');
      return;
    }

    setState(() {
      _resending = true;
    });

    try {
      await user.sendEmailVerification();
      _showSnackBar('Te enviamos un nuevo correo de verificación.');
      _startResendCooldown(seconds: 60);
    } on fb_auth.FirebaseAuthException catch (e) {
      final msg = (e.message == null || e.message!.isEmpty)
          ? 'No se pudo reenviar el correo. Intenta más tarde.'
          : e.message!;
      _showSnackBar(msg);
    } catch (_) {
      _showSnackBar('No se pudo reenviar el correo. Intenta más tarde.');
    } finally {
      if (!mounted) return;
      setState(() {
        _resending = false;
      });
    }
  }

  Future<void> _handleBackToLogin() async {
    if (_navigated) return;
    _navigated = true;
    _pollTimer?.cancel();
    try {
      await ref.read(authNotifierProvider.notifier).signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  Future<void> _syncEmailVerified(fb_auth.User user) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'contact.emailVerified': true});
    } catch (_) {
    }
  }

  Future<void> _checkVerified() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_checking) return;
    if (_navigated) return;
    _checking = true;
    try {
      await user.reload();
      final refreshed = fb_auth.FirebaseAuth.instance.currentUser;
      final verified = refreshed?.emailVerified ?? false;
      if (!verified) return;

      await _syncEmailVerified(refreshed!);

      if (!mounted) return;
      _navigated = true;
      _pollTimer?.cancel();
      if (widget.userRole == UserRole.hero) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HeroHomeScreen()),
          (_) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const RiderHomeScreen()),
          (_) => false,
        );
      }
    } catch (_) {
    } finally {
      _checking = false;
    }
  }

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_checkVerified);
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkVerified());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
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
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primaryOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.mark_email_unread,
                    color: primaryOrange,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Verifica tu correo',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: textGray900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enviamos un link de verificación a:\n${widget.email}',
                  style: const TextStyle(
                    fontSize: 15,
                    color: textGray700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Abre el enlace desde tu correo. Cuando se verifique, te enviaremos automáticamente al inicio.',
                  style: TextStyle(fontSize: 13, color: textGray600),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_resending || _resendSecondsRemaining > 0)
                        ? null
                        : _handleResendEmail,
                    icon: _resending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      _resendSecondsRemaining > 0
                          ? 'Reenviar en ${_resendSecondsRemaining}s'
                          : 'Reenviar correo',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryOrange,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          primaryOrange.withValues(alpha: 0.5),
                      disabledForegroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: primaryOrange,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
