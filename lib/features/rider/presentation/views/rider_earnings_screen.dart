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
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
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
              final totalDeliveryFees = summary['totalDeliveryFees'] ?? 0.0;
              final totalServiceFees = summary['totalServiceFees'] ?? 0.0;
              final totalTaxDeductions = summary['totalTaxDeductions'] ?? 0.0;
              final deliveryCount = summary['deliveryCount']?.toInt() ?? 0;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Total Earnings Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [primaryOrange, Color(0xFFFF8C42)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: primaryOrange.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Ganancias Netas',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: backgroundWhite,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '\$${totalNetEarnings.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            color: backgroundWhite,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$deliveryCount entrega${deliveryCount == 1 ? '' : 's'} completada${deliveryCount == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: backgroundWhite.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Breakdown Section
                  const Text(
                    'Desglose de Comisiones',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: textGray900,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: backgroundWhite,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: textGray900.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildBreakdownRow(
                          'Total facturado',
                          totalDeliveryFees,
                          color: textGray900,
                          isBold: true,
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: borderGray100),
                        const SizedBox(height: 16),
                        _buildBreakdownRow(
                          'Comisión de servicio',
                          -totalServiceFees,
                          color: Colors.red,
                          subtitle: '\$2,000 por entrega',
                        ),
                        const SizedBox(height: 12),
                        _buildBreakdownRow(
                          'Descuento (7%)',
                          -totalTaxDeductions,
                          color: Colors.red,
                          subtitle: 'Descuento sobre envío neto',
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1, color: borderGray100),
                        const SizedBox(height: 16),
                        _buildBreakdownRow(
                          'Ganancia neta',
                          totalNetEarnings,
                          color: Colors.green,
                          isBold: true,
                          isLarge: true,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Info Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF9E6),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primaryYellow),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: primaryOrange,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Estructura de Comisiones',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: textGray900,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Se aplica una comisión fija de \$2,000 por entrega más un 7% de descuento sobre el envío neto (envío menos comisión).',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textGray700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Recent Deliveries
                  if (completedOrders.isNotEmpty) ...[
                    const Text(
                      'Entregas Recientes',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: textGray900,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...completedOrders.take(10).map((order) {
                      final commission =
                          RiderCommissionCalculator.calculateCommission(
                            deliveryFee: order.deliveryFee,
                          );

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: backgroundWhite,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: textGray900.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Orden #${order.orderId.substring(0, 8)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: textGray900,
                                  ),
                                ),
                                Text(
                                  '\$${commission.netEarnings.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tarifa: \$${order.deliveryFee.toStringAsFixed(0)} - Comisión: \$${commission.serviceFee.toStringAsFixed(0)} - Impuestos: \$${commission.taxDeduction.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: textGray600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildBreakdownRow(
    String label,
    double amount, {
    Color? color,
    String? subtitle,
    bool isBold = false,
    bool isLarge = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: isLarge ? 16 : 14,
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                  color: color ?? textGray900,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 11, color: textGray600),
                ),
              ],
            ],
          ),
        ),
        Text(
          '\$${amount.abs().toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: isLarge ? 20 : 14,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            color: color ?? textGray900,
          ),
        ),
      ],
    );
  }
}
