import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/order_status.dart';
import '../../orders/presentation/providers/orders_provider.dart';
import '../../shared/profile/presentation/providers/profile_provider.dart';
import '../../hero/orders/presentation/views/hero_order_status_screen.dart';

class WaitingRiderScreen extends ConsumerWidget {
  final String orderId;
  const WaitingRiderScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        title: const Text('Buscando repartidor'),
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: primaryOrange)),
        error: (err, _) => _StatusMessage(
          title: 'No pudimos cargar tu perfil',
          subtitle: err.toString(),
          showBack: true,
        ),
        data: (user) {
          if (user == null) {
            return const _StatusMessage(
              title: 'Inicia sesión',
              subtitle: 'Necesitas iniciar sesión para seguir el pedido.',
              showBack: true,
            );
          }

          final ordersAsync = ref.watch(myOrdersProvider(user.id));

          return ordersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: primaryOrange)),
            error: (err, _) => _StatusMessage(
              title: 'No pudimos obtener el pedido',
              subtitle: err.toString(),
              showBack: true,
            ),
            data: (orders) {
              final order = orders.where((o) => o.orderId == orderId).firstOrNull;

              if (order == null) {
                return const _StatusMessage(
                  title: 'Publicando pedido...',
                  subtitle: 'Estamos esperando la confirmación del servidor.',
                );
              }

              return _WaitingContent(order: order);
            },
          );
        },
      ),
    );
  }
}

class _WaitingContent extends StatelessWidget {
  final Order order;
  const _WaitingContent({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order.status;
    final isQueued = status == OrderStatus.queued || status == OrderStatus.created;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 12),
          CircleAvatar(
            radius: 48,
            backgroundColor: primaryOrange.withValues(alpha: 0.12),
            child: const Icon(Icons.delivery_dining, color: primaryOrange, size: 48),
          ),
          const SizedBox(height: 16),
          Text(
            isQueued ? 'Tu pedido está publicado' : status.displayName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textGray900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isQueued
                ? 'Los repartidores cercanos ya pueden ver tu pedido. Te avisaremos cuando alguien lo acepte.'
                : 'Estado actual: ${status.displayName}',
            style: const TextStyle(fontSize: 14, color: textGray700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _InfoCard(order: order),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HeroOrderStatusScreen(orderId: order.orderId),
                  ),
                );
              },
              icon: const Icon(Icons.receipt_long),
              label: const Text(
                'Ver estado del pedido',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryOrange,
                side: const BorderSide(color: primaryOrange),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const _PillStatus(),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Order order;
  const _InfoCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Pedido', order.orderId),
          const SizedBox(height: 8),
          _row('Total', '\$${order.amountTotal.toStringAsFixed(0)} CLP'),
          const SizedBox(height: 8),
          _row('Vehículo requerido', order.requirements.requiredVehicle.displayName),
          const SizedBox(height: 8),
          _row('Peso', '${order.requirements.weightKg.toStringAsFixed(2)} kg'),
          const SizedBox(height: 8),
          _row('Entrega', order.delivery.addressSnapshot),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, color: textGray700),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, color: textGray900),
          ),
        ),
      ],
    );
  }
}

class _PillStatus extends StatelessWidget {
  const _PillStatus();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: primaryYellow.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(width: 6),
          _BlinkingDot(),
          SizedBox(width: 8),
          Text(
            'Esperando repartidor...',
            style: TextStyle(fontWeight: FontWeight.w700, color: textGray900),
          ),
          SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.4,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: const CircleAvatar(
        radius: 6,
        backgroundColor: primaryOrange,
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showBack;

  const _StatusMessage({
    required this.title,
    this.subtitle,
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_top, size: 48, color: primaryOrange),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textGray900),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: const TextStyle(fontSize: 14, color: textGray700),
                textAlign: TextAlign.center,
              ),
            ],
            if (showBack) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryOrange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Volver'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
