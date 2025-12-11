import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
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
    ref.listen(
      authNotifierProvider,
      (previous, next) {
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
            MaterialPageRoute(
              builder: (context) => const HeroHomeScreen(),
            ),
          );
        }
      },
    );
    return Scaffold(
      backgroundColor: backgroundWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                _buildLogoSection(),
                const SizedBox(height: 24),
                _buildWelcomeSection(),
                const SizedBox(height: 32),

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
                const SizedBox(height: 16),

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
                const SizedBox(height: 16),
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

  Widget _buildLogoSection() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo_1.png', height: 100, fit: BoxFit.contain),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Column(
      children: [
        // Título de bienvenida principal
        Text(
          '¡Bienvenido!',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: textGray900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 16),
        // Subtítulo descriptivo
        Text(
          'Tu plataforma de confianza para',
          style: TextStyle(
            fontSize: 16,
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
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: textGray600,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        // Texto de instrucción
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundGray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderGray100, width: 1),
          ),
          child: Text(
            'Selecciona tu rol para comenzar',
            style: TextStyle(
              fontSize: 15,
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
