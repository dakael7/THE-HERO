import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/common/hero_header_app_bar.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../hero/presentation/viewmodels/hero_home_viewmodel.dart';
import '../providers/account_deletion_provider.dart';

class HelpCenterScreen extends ConsumerWidget {
  final bool isRiderProfile;

  const HelpCenterScreen({super.key, this.isRiderProfile = false});

  static final Uri _termsAndConditionsUri = Uri.parse(
    'https://theheroprojects.com/privacy-policy',
  );

  static final Uri _helpCenterUri = Uri.parse(
    'https://theheroprojects.com/',
  );

  static final Uri _riderSiiManualUri = Uri.parse(
    'https://firebasestorage.googleapis.com/v0/b/the-hero-67d93.firebasestorage.app/o/Docs%2FManual_SII_Rider_THE_HERO_SpA.pdf?alt=media&token=b553a420-4041-4bfe-89ef-a02824cb01e3',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountDeletionState = ref.watch(accountDeletionNotifierProvider);
    final isDeletingAccount = accountDeletionState is AsyncLoading<void>;

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: HeroHeaderAppBar(
        title: 'Centro de ayuda',
        icon: Icons.help_outline_rounded,
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
          ref.read(heroHomeViewModelProvider.notifier).selectNavItem(0);
        },
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Material(
            color: backgroundWhite,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                await launchUrl(
                  _helpCenterUri,
                  mode: LaunchMode.externalApplication,
                );
              },
              child: Ink(
                decoration: BoxDecoration(
                  color: backgroundWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: backgroundWhite, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: textGray900.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    children: [
                      _HelpCardIcon(),
                      SizedBox(width: 12),
                      Expanded(
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
                      Icon(Icons.open_in_new_rounded, color: textGray600, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 16),
          _HelpTile(
            icon: Icons.delete_forever_outlined,
            title: 'Eliminar cuenta',
            subtitle: isDeletingAccount
                ? 'Eliminando tu cuenta...'
                : 'Borra tu cuenta y archivos asociados.',
            iconColor: categoryTextRed,
            onTap: isDeletingAccount
                ? () {}
                : () => _requestAccountDeletion(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _requestAccountDeletion(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('¿Eliminar cuenta?'),
          content: const Text(
            'Esta accion eliminara tu cuenta, tu perfil, tus publicaciones, '
            'tus fotos y documentos asociados. Esta accion no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: categoryTextRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Eliminar cuenta'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeletingAccountDialog(),
    );

    try {
      await ref
          .read(accountDeletionNotifierProvider.notifier)
          .deleteCurrentAccount();

      if (!context.mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Cuenta eliminada correctamente')),
      );
    } catch (error) {
      if (!context.mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}

class _DeletingAccountDialog extends StatelessWidget {
  const _DeletingAccountDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(color: primaryOrange),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              'Eliminando cuenta y archivos asociados...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textGray900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpCardIcon extends StatelessWidget {
  const _HelpCardIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: primaryOrange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.support_agent, color: primaryOrange),
    );
  }
}

class _HelpTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color iconColor;

  const _HelpTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = primaryOrange,
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
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: iconColor),
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
