import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../domain/entities/user.dart';
import '../widgets/animated_role_button.dart';
import 'email_verification_screen.dart';

// =========================================================
// WIDGET DE PÁGINA DE LOGIN
// =========================================================

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with TickerProviderStateMixin {
  // Only background animation controller
  AnimationController? _bgPatternController;

  @override
  void initState() {
    super.initState();

    _bgPatternController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _bgPatternController?.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────

  void _navigateToRole(UserRole role) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmailVerificationScreen(userRole: role),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final padding = ResponsiveUtils.responsivePadding(
      context,
      mobilePadding: 24.0,
      tabletPadding: 32.0,
      desktopPadding: 40.0,
    );

    return Scaffold(
      backgroundColor: primaryYellow,
      body: Stack(
        children: [
          // ── Animated background ───────────────────────
          if (_bgPatternController != null)
            _AnimatedBackground(controller: _bgPatternController!),

          // ── Content ───────────────────────────────────
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padding, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildLogoSection(context),
                  _buildWelcomeSection(context),

                  // Role cards
                  Column(
                    children: [
                      // Hero role card
                      AnimatedRoleButton(
                        contentWidget: Image.asset(
                          'assets/wheel.png',
                          width: 36,
                          height: 36,
                        ),
                        label: 'HERO',
                        description: 'Buscar artículos que necesites',
                        color: primaryOrange,
                        textColor: Colors.white,
                        descriptionColor:
                            Colors.white.withValues(alpha: 0.9),
                        onTap: () => _navigateToRole(UserRole.hero),
                      ),
                      const SizedBox(height: 12),

                      // Rider role card
                      AnimatedRoleButton(
                        contentWidget: Icon(
                          Icons.local_shipping,
                          size: 28,
                          color: primaryOrange,
                        ),
                        label: 'RIDER',
                        description: 'Conviértete en repartidor',
                        color: Colors.white,
                        textColor: textGray900,
                        descriptionColor: textGray600,
                        onTap: () => _navigateToRole(UserRole.rider),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Logo section ───────────────────────────────────────

  Widget _buildLogoSection(BuildContext context) {
    final logoHeight = ResponsiveUtils.isMobile(context) ? 140.0 : 160.0;

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Static glow ring
            Container(
              width: logoHeight * 1.35,
              height: logoHeight * 1.35,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primaryOrange.withValues(alpha: 0.18),
                    primaryOrange.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),

            // Logo container with subtle white card
            Container(
              width: logoHeight * 1.1,
              height: logoHeight * 1.1,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.45),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primaryOrange.withValues(alpha: 0.18),
                    blurRadius: 24,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.6),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Center(
                child: Image.asset(
                  'assets/logo_1.png',
                  height: logoHeight * 0.72,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Welcome section ────────────────────────────────────

  Widget _buildWelcomeSection(BuildContext context) {
    final titleFontSize = ResponsiveUtils.responsiveFontSize(
      context,
      mobileSize: 28,
      tabletSize: 32,
      desktopSize: 36,
    );
    final subtitleFontSize = ResponsiveUtils.responsiveFontSize(
      context,
      mobileSize: 16,
      tabletSize: 17,
      desktopSize: 18,
    );
    final instructionFontSize = ResponsiveUtils.responsiveFontSize(
      context,
      mobileSize: 15,
      tabletSize: 16,
      desktopSize: 17,
    );
    final spacing = ResponsiveUtils.responsivePadding(
      context,
      mobilePadding: 16.0,
      tabletPadding: 20.0,
      desktopPadding: 24.0,
    );

    return Column(
      children: [
        // ── Greeting badge ──────────────────────────
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.waving_hand_rounded,
                size: 16,
                color: primaryOrange,
              ),
              const SizedBox(width: 6),
              Text(
                '¡Hola! Nos alegra verte',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textGray900,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing * 0.7),

        // ── Main title ──────────────────────────────
        Text(
          '¡Bienvenido!',
          style: TextStyle(
            fontSize: titleFontSize,
            fontWeight: FontWeight.w800,
            color: textGray900,
            letterSpacing: -0.8,
            height: 1.1,
          ),
        ),
        SizedBox(height: spacing * 0.55),

        // ── Subtitle ────────────────────────────────
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontSize: subtitleFontSize,
              fontWeight: FontWeight.w400,
              color: textGray600,
              height: 1.5,
            ),
            children: const [
              TextSpan(text: 'Tu plataforma de confianza para '),
              TextSpan(
                text: 'encontrar y entregar',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: textGray900,
                ),
              ),
              TextSpan(text: ' lo que necesitas'),
            ],
          ),
        ),
        SizedBox(height: spacing * 1.4),

        // ── Role selector pill ──────────────────────
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: spacing,
            vertical: spacing * 0.75,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.8),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: primaryOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.touch_app_rounded,
                  size: 16,
                  color: primaryOrange,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Selecciona tu rol para comenzar',
                style: TextStyle(
                  fontSize: instructionFontSize,
                  fontWeight: FontWeight.w600,
                  color: textGray700,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Animated Background
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedBackground extends StatelessWidget {
  const _AnimatedBackground({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        final t = controller.value;
        return SizedBox.expand(
          child: CustomPaint(
            painter: _BgPatternPainter(t: t, size: size),
          ),
        );
      },
    );
  }
}

class _BgPatternPainter extends CustomPainter {
  const _BgPatternPainter({required this.t, required this.size});

  final double t;
  final Size size;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Large soft blobs
    final blobs = [
      (
        dx: 0.15 + 0.06 * _sin(t * 2),
        dy: 0.12 + 0.05 * _cos(t * 1.7),
        r: 0.38,
        alpha: 0.10,
        color: primaryOrange,
      ),
      (
        dx: 0.88 + 0.05 * _cos(t * 2.3),
        dy: 0.22 + 0.06 * _sin(t * 1.5),
        r: 0.28,
        alpha: 0.08,
        color: Colors.white,
      ),
      (
        dx: 0.70 + 0.04 * _sin(t * 3.1),
        dy: 0.75 + 0.05 * _cos(t * 2.0),
        r: 0.34,
        alpha: 0.09,
        color: primaryOrange,
      ),
      (
        dx: 0.10 + 0.05 * _cos(t * 1.9),
        dy: 0.80 + 0.04 * _sin(t * 2.5),
        r: 0.22,
        alpha: 0.07,
        color: Colors.white,
      ),
    ];

    for (final b in blobs) {
      paint.color = b.color.withValues(alpha: b.alpha);
      canvas.drawCircle(
        Offset(canvasSize.width * b.dx, canvasSize.height * b.dy),
        canvasSize.shortestSide * b.r,
        paint,
      );
    }

    // Small decorative dots
    final dotPaint = Paint()
      ..color = primaryOrange.withValues(alpha: 0.13)
      ..style = PaintingStyle.fill;

    final dotPositions = [
      Offset(canvasSize.width * 0.82, canvasSize.height * 0.08),
      Offset(canvasSize.width * 0.92, canvasSize.height * 0.35),
      Offset(canvasSize.width * 0.06, canvasSize.height * 0.48),
      Offset(canvasSize.width * 0.55, canvasSize.height * 0.94),
      Offset(canvasSize.width * 0.28, canvasSize.height * 0.96),
    ];

    for (final pos in dotPositions) {
      canvas.drawCircle(pos, 5, dotPaint);
    }
  }

  double _sin(double v) => (v * 3.14159265).abs() % 2 < 1
      ? (v * 3.14159265) % 1
      : 1 - ((v * 3.14159265) % 1);
  double _cos(double v) => _sin(v + 0.5);

  @override
  bool shouldRepaint(_BgPatternPainter old) => old.t != t;
}