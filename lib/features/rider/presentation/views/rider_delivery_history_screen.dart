import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../domain/services/rider_commission_calculator.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';

class RiderDeliveryHistoryScreen extends ConsumerWidget {
  const RiderDeliveryHistoryScreen({super.key});

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
          'Historial de Entregas',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: userAsync.when(
        data: (user) {
          final riderId = user?.id;
          if (riderId == null || riderId.isEmpty) {
            return const Center(child: Text('Usuario no encontrado'));
          }

          final ordersAsync = ref.watch(riderOrdersProvider(riderId));
          return ordersAsync.when(
            data: (orders) {
              final delivered = orders
                  .where((o) => o.status.name == 'delivered')
                  .toList();

              if (delivered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: 96,
                          color: primaryOrange.withValues(alpha: 0.45),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Sin entregas aún',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: textGray900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Aquí verás tu historial de entregas completadas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: textGray600),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: delivered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final order = delivered[index];
                  final orderId = order.orderId;
                  final earnings = RiderCommissionCalculator.calculateCommission(
                    deliveryFee: order.deliveryFee,
                  );

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: backgroundWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderGray100, width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: textGray900.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pedido #$orderId',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: textGray900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Estado: ${order.status.displayName}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: textGray600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '\$${earnings.netEarnings.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: primaryOrange,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: primaryOrange),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error cargando historial: $e'),
              ),
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: primaryOrange),
        ),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error cargando perfil: $e'),
          ),
        ),
      ),
    );
  }
}
