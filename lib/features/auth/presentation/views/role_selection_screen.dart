import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/user.dart';
import '../../../hero/presentation/views/hero_home_screen.dart';
import '../../../rider/presentation/views/rider_home_screen.dart';
import '../providers/auth_provider.dart';

class RoleSelectionScreen extends ConsumerWidget {
  final User user;

  const RoleSelectionScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: primaryYellow,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.person_outline, size: 80, color: primaryOrange),
              const SizedBox(height: 24),
              Text(
                '¡Hola, ${user.firstName}!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: primaryOrange,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Selecciona cómo quieres continuar',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.black54),
              ),
              const SizedBox(height: 48),
              _buildRoleCard(
                context: context,
                icon: Icons.volunteer_activism,
                title: 'Continuar como Hero',
                description: 'Publica productos y ayuda a tu comunidad',
                color: primaryOrange,
                onTap: () async {
                  await ref
                      .read(authNotifierProvider.notifier)
                      .saveLastRole('hero');
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => const HeroHomeScreen(),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 24),
              _buildRoleCard(
                context: context,
                icon: Icons.delivery_dining,
                title: 'Continuar como Rider',
                description: 'Realiza entregas y gana dinero',
                color: const Color(0xFF2196F3),
                onTap: () async {
                  await ref
                      .read(authNotifierProvider.notifier)
                      .saveLastRole('rider');
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => const RiderHomeScreen(),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 60, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
