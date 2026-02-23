import 'package:flutter/material.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/user.dart';

class RutVerificationCtaBanner extends StatelessWidget {
  final User user;
  final VoidCallback onTap;

  const RutVerificationCtaBanner({
    super.key,
    required this.user,
    required this.onTap,
  });

  String _statusText(String? status) {
    switch (status) {
      case 'approved':
        return 'Verificado';
      case 'submitted':
        return 'En revisión';
      case 'processing':
        return 'Analizando…';
      case 'needs_review':
        return 'Revisión requerida';
      case 'rejected':
        return 'No aprobado';
      case 'failed':
        return 'Error';
      case 'pending':
      case null:
        return 'Pendiente';
      default:
        return 'Pendiente';
    }
  }

  String _subtitle(String? status) {
    switch (status) {
      case 'processing':
      case 'submitted':
        return 'Estamos revisando tus documentos.';
      case 'needs_review':
        return 'Sube mejores fotos para acelerar la aprobación.';
      case 'rejected':
      case 'failed':
        return 'Reintenta con fotos claras y sin reflejos.';
      case 'approved':
        return 'Listo. Acceso completo habilitado.';
      case 'pending':
      case null:
      default:
        return 'Verifica tu identidad para usar todas las funciones.';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user.isRutVerified) return const SizedBox.shrink();

    final statusText = _statusText(user.rutVerificationStatus);
    final subtitle = _subtitle(user.rutVerificationStatus);

    final borderColor = switch (user.rutVerificationStatus) {
      'rejected' || 'failed' => const Color(0xFFDC2626),
      'processing' || 'submitted' => const Color(0xFF2563EB),
      _ => primaryOrange,
    };

    final bgColor = switch (user.rutVerificationStatus) {
      'rejected' || 'failed' => const Color(0xFFFEF2F2),
      'processing' || 'submitted' => const Color(0xFFEFF6FF),
      _ => const Color(0xFFFFF7ED),
    };

    final icon = switch (user.rutVerificationStatus) {
      'rejected' || 'failed' => Icons.error_outline,
      'processing' || 'submitted' => Icons.hourglass_top,
      _ => Icons.verified_user_outlined,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: textGray900.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: Row(
          key: ValueKey<String>(user.rutVerificationStatus ?? 'pending'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: borderColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (user.rutVerificationStatus == 'processing')
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: borderColor,
                      ),
                    ),
                  Icon(
                    icon,
                    color: user.rutVerificationStatus == 'processing'
                        ? Colors.transparent
                        : borderColor,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verificación de RUT',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: textGray900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    statusText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: textGray900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: textGray700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryOrange,
                        foregroundColor: backgroundWhite,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        (user.rutVerificationStatus == 'needs_review' ||
                                user.rutVerificationStatus == 'failed' ||
                                user.rutVerificationStatus == 'rejected')
                            ? 'Reintentar'
                            : 'Verificar ahora',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
