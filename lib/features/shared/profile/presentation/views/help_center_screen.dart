import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../hero/presentation/viewmodels/hero_home_viewmodel.dart';

class HelpCenterScreen extends ConsumerWidget {
  final bool isRiderProfile;

  const HelpCenterScreen({super.key, this.isRiderProfile = false});

  static final Uri _termsAndConditionsUri = Uri.parse(
    'https://theheroprojects.com/privacy-policy',
  );

  static final Uri _riderSiiManualUri = Uri.parse(
    'https://firebasestorage.googleapis.com/v0/b/the-hero-67d93.firebasestorage.app/o/Docs%2FManual_SII_Rider_THE_HERO_SpA.pdf?alt=media&token=b553a420-4041-4bfe-89ef-a02824cb01e3',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            ref.read(heroHomeViewModelProvider.notifier).selectNavItem(0);
          },
        ),
        title: const Text(
          'Centro de ayuda',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderGray100, width: 1),
              boxShadow: [
                BoxShadow(
                  color: textGray900.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primaryOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.support_agent, color: primaryOrange),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '¿Necesitas ayuda?',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: textGray900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Encuentra respuestas rápidas o contáctanos.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: textGray600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _HelpTile(
            icon: Icons.local_shipping_outlined,
            title: 'Envíos y entregas',
            subtitle: 'Tiempos, estados y seguimiento.',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ayuda sobre envíos próximamente'),
                  duration: Duration(milliseconds: 1500),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          if (isRiderProfile) ...[
            _HelpTile(
              icon: Icons.payments_outlined,
              title: 'Pagos',
              subtitle: 'Métodos, cobros y reembolsos.',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ayuda sobre pagos próximamente'),
                    duration: Duration(milliseconds: 1500),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
          _HelpTile(
            icon: Icons.verified_user_outlined,
            title: 'Cuenta',
            subtitle: 'Acceso, verificación y datos.',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ayuda sobre cuenta próximamente'),
                  duration: Duration(milliseconds: 1500),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _HelpTile(
            icon: Icons.gavel_outlined,
            title: 'Términos y condiciones',
            subtitle: 'Lee las condiciones de uso.',
            onTap: () async {
              await launchUrl(
                _termsAndConditionsUri,
                mode: LaunchMode.externalApplication,
              );
            },
          ),
          const SizedBox(height: 8),
          if (isRiderProfile)
            _HelpTile(
              icon: Icons.description_outlined,
              title: 'Manual Paso a Paso SII',
              subtitle: 'Guía para Riders (SII).',
              onTap: () async {
                await launchUrl(
                  _riderSiiManualUri,
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _HelpTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HelpTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundWhite,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderGray100, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primaryOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: primaryOrange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: textGray900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: textGray600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: textGray600),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
