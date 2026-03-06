import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../providers/rider_cumulative_stats_provider.dart';

class RiderStatsScreen extends ConsumerWidget {
  const RiderStatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Mis Estadísticas',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Usuario no encontrado'));
          }

          final statsAsync = ref.watch(riderCumulativeStatsProvider(user.id));

          return statsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: primaryOrange),
            ),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (stats) {
              if (stats == null) {
                return const Center(child: Text('No hay datos para mostrar'));
              }

              final pending = stats.pendingBalance;
              final pendingLabel = pending < 0
                  ? 'Debes dinero a la plataforma'
                  : 'Pendiente por pagar';

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _StatCard(
                    title: 'Total Earnings',
                    value: '\$${stats.totalEarnings.toStringAsFixed(0)}',
                  ),
                  const SizedBox(height: 12),
                  _StatCard(
                    title: 'Total Tips',
                    value: '\$${stats.totalTips.toStringAsFixed(0)}',
                  ),
                  const SizedBox(height: 12),
                  _StatCard(
                    title: 'Completed Trips',
                    value: stats.completedTrips.toString(),
                  ),
                  const SizedBox(height: 12),
                  _StatCard(
                    title: 'Canceled Trips',
                    value: stats.canceledTrips.toString(),
                  ),
                  const SizedBox(height: 12),
                  _StatCard(
                    title: 'Pending Balance',
                    value: '\$${pending.abs().toStringAsFixed(0)}',
                    subtitle: pendingLabel,
                    valueColor: pending < 0 ? Colors.red : Colors.green,
                  ),
                ],
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final Color? valueColor;

  const _StatCard({
    required this.title,
    required this.value,
    this.subtitle,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: textGray900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: valueColor ?? textGray900,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textGray600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
