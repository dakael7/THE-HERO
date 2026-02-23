import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../domain/services/rider_commission_calculator.dart';
import '../../../../domain/providers/orders_usecase_providers.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';

class RiderEarningsScreen extends ConsumerWidget {
  const RiderEarningsScreen({super.key});

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
          'Mis Ganancias',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(child: Text('Usuario no encontrado'));
          }

          final useCase = ref.read(getOrdersByRiderUseCaseProvider);

          return StreamBuilder(
            stream: useCase.execute(user.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: primaryOrange),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: textGray600.withValues(alpha: 0.55),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No pudimos cargar tus ganancias',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: textGray900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: textGray600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final orders = snapshot.data ?? [];

              // Filter only delivered orders
              final completedOrders = orders
                  .where((order) => order.status.name == 'delivered')
                  .toList();

              // Calculate earnings - explicitly cast to double
              final deliveryFees = completedOrders
                  .map((order) => order.deliveryFee)
                  .toList();

              final summary = RiderCommissionCalculator.getSummary(
                deliveryFees,
              );
              final totalNetEarnings = summary['totalNetEarnings'] ?? 0.0;
              final deliveryCount = summary['deliveryCount']?.toInt() ?? 0;
              final avgPerDelivery =
                  deliveryCount <= 0 ? 0.0 : (totalNetEarnings / deliveryCount);

              final completedCountText =
                  '$deliveryCount entrega${deliveryCount == 1 ? '' : 's'} completada${deliveryCount == 1 ? '' : 's'}';

              return RefreshIndicator(
                color: primaryOrange,
                onRefresh: () async {
                  ref.invalidate(profileProvider);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [primaryOrange, Color(0xFFFF8C42)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: primaryOrange.withValues(alpha: 0.28),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.account_balance_wallet_outlined,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Ganancias netas',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '\$${totalNetEarnings.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            completedCountText,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _MetricChip(
                                  icon: Icons.local_shipping_outlined,
                                  label: 'Entregas',
                                  value: '$deliveryCount',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MetricChip(
                                  icon: Icons.trending_up,
                                  label: 'Promedio',
                                  value: '\$${avgPerDelivery.toStringAsFixed(0)}',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (completedOrders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: backgroundWhite,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: borderGray100),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.history,
                                size: 56,
                                color: textGray600.withValues(alpha: 0.55),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Aún no tienes entregas completadas',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: textGray900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Cuando completes una entrega, aquí verás el resumen de tus ganancias.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textGray600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      const Padding(
                        padding: EdgeInsets.only(left: 4, top: 4, bottom: 10),
                        child: Text(
                          'Entregas recientes',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: textGray900,
                          ),
                        ),
                      ),
                      ...completedOrders.take(10).map((order) {
                        final earnings = RiderCommissionCalculator.calculateCommission(
                          deliveryFee: order.deliveryFee,
                        );
                        final shortId = order.orderId.length <= 8
                            ? order.orderId
                            : order.orderId.substring(0, 8);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: backgroundWhite,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderGray100),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: primaryOrange.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.check_circle_outline,
                                color: primaryOrange,
                              ),
                            ),
                            title: Text(
                              'Orden #$shortId',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: textGray900,
                              ),
                            ),
                            subtitle: const Text(
                              'Entregada',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textGray600,
                              ),
                            ),
                            trailing: Text(
                              '\$${earnings.netEarnings.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: Colors.green,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.90),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
