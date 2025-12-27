import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/responsive_utils.dart';
import '../../../../domain/entities/user.dart';
import '../widgets/animated_role_button.dart';
import '../providers/auth_provider.dart';
import '../../../hero/presentation/views/hero_home_screen.dart';
import 'email_verification_screen.dart';

// =========================================================
// WIDGET DE PÁGINA DE LOGIN
// =========================================================

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authNotifierProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage!.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            duration: const Duration(milliseconds: 2000),
          ),
        );
      }

      final wasAuthenticated = previous?.isAuthenticated ?? false;
      if (!wasAuthenticated && next.isAuthenticated) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HeroHomeScreen()),
        );
      }
    });

    final padding = ResponsiveUtils.responsivePadding(
      context,
      mobilePadding: 24.0,
      tabletPadding: 32.0,
      desktopPadding: 40.0,
    );
    final spacingLarge = ResponsiveUtils.responsivePadding(
      context,
      mobilePadding: 32.0,
      tabletPadding: 40.0,
      desktopPadding: 48.0,
    );
    final spacingMedium = ResponsiveUtils.responsivePadding(
      context,
      mobilePadding: 16.0,
      tabletPadding: 20.0,
      desktopPadding: 24.0,
    );

    return Scaffold(
      backgroundColor: primaryYellow,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _buildLogoSection(context),
                SizedBox(height: spacingMedium),
                _buildWelcomeSection(context),
                SizedBox(height: spacingLarge),

                // Botón de selección de rol: HERO (Consumidor)
                AnimatedRoleButton(
                  contentWidget: Image.asset(
                    'assets/wheel.png',
                    width: 40,
                    height: 40,
                  ),
                  label: 'HERO',
                  description: 'Buscar artículos que necesites',
                  color: primaryOrange,
                  textColor: Colors.white,
                  descriptionColor: Colors.white.withOpacity(0.9),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EmailVerificationScreen(
                          userRole: UserRole.hero,
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: spacingMedium),

                // Botón de selección de rol: RIDER (Repartidor)
                AnimatedRoleButton(
                  contentWidget: Icon(
                    Icons.local_shipping,
                    size: 30,
                    color: primaryOrange,
                  ),
                  label: 'RIDER',
                  description: 'Conviértete en repartidor',
                  color: Colors.white,
                  textColor: textGray900,
                  descriptionColor: textGray600,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EmailVerificationScreen(
                          userRole: UserRole.rider,
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: spacingMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------
  // MÉTODOS DE CONSTRUCCIÓN DEL LOGO Y TEXTO
  // ---------------------------------------------------------

  Widget _buildLogoSection(BuildContext context) {
    final logoHeight = ResponsiveUtils.isMobile(context) ? 100.0 : 120.0;

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/logo_1.png',
              height: logoHeight,
              fit: BoxFit.contain,
            ),
          ],
        ),
      ),
    );
  }

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
        // Título de bienvenida principal
        Text(
          '¡Bienvenido!',
          style: TextStyle(
            fontSize: titleFontSize,
            fontWeight: FontWeight.w600,
            color: textGray900,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: spacing),
        // Subtítulo descriptivo
        Text(
          'Tu plataforma de confianza para',
          style: TextStyle(
            fontSize: subtitleFontSize,
            fontWeight: FontWeight.w400,
            color: textGray600,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          'encontrar y entregar lo que necesitas',
          style: TextStyle(
            fontSize: subtitleFontSize,
            fontWeight: FontWeight.w400,
            color: textGray600,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: spacing * 1.5),
        // Texto de instrucción
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: spacing,
            vertical: spacing * 0.75,
          ),
          decoration: BoxDecoration(
            color: backgroundGray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderGray100, width: 1),
          ),
          child: Text(
            'Selecciona tu rol para comenzar',
            style: TextStyle(
              fontSize: instructionFontSize,
              fontWeight: FontWeight.w500,
              color: textGray700,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
