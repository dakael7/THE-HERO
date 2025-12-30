import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/user.dart';
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
  bool _checking = false;
  bool _navigated = false;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: textGray900),
          onPressed: () => Navigator.of(context).pop(),
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
                  color: primaryOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.mark_email_unread, color: primaryOrange, size: 28),
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
    );
  }
}
