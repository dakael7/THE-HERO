import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';

class ProfileStatsSection extends StatelessWidget {
  final int publications;
  final int favorites;
  final int purchases;

  const ProfileStatsSection({
    super.key,
    required this.publications,
    required this.favorites,
    required this.purchases,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: backgroundWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderGray100,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: textGray900.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ProfileStatItem(
              label: 'Publicaciones',
              value: publications.toString(),
            ),
            _ProfileStatItem(
              label: 'Favoritos',
              value: favorites.toString(),
            ),
            _ProfileStatItem(
              label: 'Compras',
              value: purchases.toString(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStatItem extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileStatItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: textGray900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: textGray600,
          ),
        ),
      ],
    );
  }
}
