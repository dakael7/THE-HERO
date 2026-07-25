import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class RegistrationMissingDataNotice extends StatelessWidget {
  const RegistrationMissingDataNotice({
    super.key,
    required this.isLoading,
    required this.missingItems,
    required this.readyText,
  });

  final bool isLoading;
  final List<String> missingItems;
  final String readyText;

  @override
  Widget build(BuildContext context) {
    final isReady = !isLoading && missingItems.isEmpty;
    final color = isReady ? const Color(0xFF10B981) : primaryOrange;
    final title = isLoading
        ? 'Cargando datos guardados'
        : isReady
        ? 'Datos listos'
        : 'Falta completar';
    final subtitle = isLoading
        ? 'Estamos buscando tu perfil actual.'
        : isReady
        ? readyText
        : 'Solo pediremos estos datos.';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isLoading
                ? Icons.sync_rounded
                : isReady
                ? Icons.check_circle_rounded
                : Icons.info_outline_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: textGray900,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: textGray600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                if (!isLoading && missingItems.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final item in missingItems)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: color.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            item,
                            style: const TextStyle(
                              color: textGray900,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
