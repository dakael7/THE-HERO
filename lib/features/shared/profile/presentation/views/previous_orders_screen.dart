import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/common/hero_header_app_bar.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../hero/presentation/viewmodels/hero_home_viewmodel.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../providers/profile_provider.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/order_status.dart';
import '../../../../hero/orders/presentation/views/hero_order_status_screen.dart';

class PreviousOrdersScreen extends ConsumerWidget {
  const PreviousOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: HeroHeaderAppBar(
        title: 'Pedidos anteriores',
        icon: Icons.history_rounded,
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
          ref.read(heroHomeViewModelProvider.notifier).selectNavItem(0);
        },
      ),
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: primaryOrange),
        ),
        error: (err, _) => _EmptyState(
          icon: Icons.error_outline,
          title: 'No pudimos cargar tu perfil',
          message: err.toString(),
        ),
        data: (user) {
          if (user == null) {
            return const _EmptyState(
              icon: Icons.login,
              title: 'Inicia sesión',
              message: 'Necesitas iniciar sesión para ver tus pedidos.',
            );
          }

          final ordersAsync = ref.watch(myOrdersProvider(user.id));
          return ordersAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: primaryOrange),
            ),
            error: (err, _) => _EmptyState(
              icon: Icons.error_outline,
              title: 'No pudimos cargar tus pedidos',
              message: err.toString(),
            ),
            data: (orders) {
              final completed = [...orders]
                ..removeWhere((o) => !o.status.isCompleted)
                ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

              if (completed.isEmpty) {
                return const _EmptyState(
                  icon: Icons.receipt_long,
                  title: 'No tienes pedidos anteriores',
                  message:
                      'Cuando finalices un pedido, podrás ver el historial aquí.',
                );
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: completed.map((o) => _OrderTile(order: o)).toList(),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: primaryOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 34, color: primaryOrange),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: textGray600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderTile extends ConsumerWidget {
  final Order order;

  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusColor = _statusColor(order.status);
    final statusBg = _statusBg(order.status);
    final shortId = order.orderId.length > 8
        ? order.orderId.substring(0, 8)
        : order.orderId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => HeroOrderStatusScreen(orderId: order.orderId),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Colored header band ─────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _statusIcon(order.status),
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.status.displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: statusColor,
                          ),
                        ),
                        Text(
                          'HRO-$shortId',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '\$${order.amountTotal.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
            // ── Body ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (order.delivery.addressSnapshot.isNotEmpty)
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          size: 14,
                          color: textGray600.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            order.delivery.addressSnapshot,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textGray600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (order.delivery.addressSnapshot.isNotEmpty)
                    const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        size: 14,
                        color: textGray600.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${order.totalItems} producto${order.totalItems == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textGray600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDate(
                          order.timestamps.deliveredAt ?? order.updatedAt,
                        ),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: textGray600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _statusBg(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return const Color(0xFFD1FAE5);
      case OrderStatus.canceled:
      case OrderStatus.failed:
        return const Color(0xFFFEE2E2);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  static IconData _statusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return Icons.task_alt;
      case OrderStatus.canceled:
        return Icons.cancel_outlined;
      case OrderStatus.failed:
        return Icons.error_outline;
      default:
        return Icons.receipt_long;
    }
  }

  static Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return Colors.green.shade700;
      case OrderStatus.canceled:
        return Colors.red.shade600;
      case OrderStatus.failed:
        return Colors.red.shade700;
      default:
        return primaryOrange;
    }
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day/$month/$year';
  }
}
