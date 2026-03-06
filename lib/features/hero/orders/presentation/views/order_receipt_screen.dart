import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/payment.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../payment/providers/payment_providers.dart';

class OrderReceiptScreen extends ConsumerWidget {
  final String orderId;
  final bool isRiderView;

  const OrderReceiptScreen({
    super.key,
    required this.orderId,
    this.isRiderView = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderByIdProvider(orderId));
    final paymentAsync = ref.watch(watchPaymentByOrderIdProvider(orderId));

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Boleta',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: orderAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: primaryOrange),
        ),
        error: (err, _) => _ErrorState(message: err.toString()),
        data: (order) {
          if (order == null) {
            return const _ErrorState(message: 'Pedido no encontrado');
          }

          return paymentAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: primaryOrange),
            ),
            error: (err, _) => _ErrorState(message: err.toString()),
            data: (payment) {
              return _ReceiptBody(
                order: order,
                payment: payment,
                isRiderView: isRiderView,
              );
            },
          );
        },
      ),
    );
  }
}

class _ReceiptBody extends StatelessWidget {
  final Order order;
  final Payment? payment;
  final bool isRiderView;

  const _ReceiptBody({
    required this.order,
    required this.payment,
    required this.isRiderView,
  });

  @override
  Widget build(BuildContext context) {
    final isPaid = payment?.status == PaymentStatus.approved;
    final isCashPayment = payment?.paymentMethod == PaymentMethod.cash ||
        (payment?.paymentMethodId?.toLowerCase() == 'cash') ||
        (payment?.statusDetail?.toLowerCase() == 'cash_on_delivery');
    final hideTotalsForRider = isRiderView && !isCashPayment;

    final shortOrderId = order.orderId.length > 8
        ? order.orderId.substring(0, 8)
        : order.orderId;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Detalle del pedido',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textGray900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              _kv('Orden', 'HRO-$shortOrderId'),
              const SizedBox(height: 8),
              _kv('Estado', order.status.displayName),
              if (!hideTotalsForRider) ...[
                const SizedBox(height: 8),
                _kv(
                  'Total',
                  '\$${order.amountTotal.toStringAsFixed(0)} ${order.currency}',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Entrega',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textGray900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              _kv('Dirección', order.delivery.addressSnapshot),
              const SizedBox(height: 8),
              _kv('Recibe', order.delivery.recipientName),
              const SizedBox(height: 8),
              _kv('Teléfono', order.delivery.recipientPhone),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pago',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textGray900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              if (payment == null) ...[
                _kv('Método', 'No disponible'),
                const SizedBox(height: 8),
                _kv('Estado', 'No disponible'),
              ] else ...[
                _kv(
                  'Método',
                  _formatPaymentMethod(payment!),
                ),
                const SizedBox(height: 8),
                _kv('Estado', payment!.status.toMercadoPagoString()),
                if ((payment!.paymentId ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _kv('Payment ID', payment!.paymentId!),
                ] else ...[
                  const SizedBox(height: 8),
                  _kv('Preference ID', payment!.preferenceId),
                ],
              ],
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isPaid
                      ? categoryTextGreen.withValues(alpha: 0.08)
                      : const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isPaid
                        ? categoryTextGreen.withValues(alpha: 0.25)
                        : const Color(0xFFFDE68A),
                  ),
                ),
                child: Text(
                  isPaid
                      ? 'Pago confirmado.'
                      : 'Esta boleta está disponible, pero el pago aún no está confirmado.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isPaid ? categoryTextGreen : const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ítems',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textGray900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              ...order.items.map(
                (it) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${it.qty} x ${it.titleSnapshot}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: textGray900,
                          ),
                        ),
                      ),
                      if (!hideTotalsForRider) ...[
                        const SizedBox(width: 12),
                        Text(
                          '\$${(it.unitPriceSnapshot * it.qty).toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: textGray900,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (!hideTotalsForRider) ...[
                const Divider(height: 22),
                _kv('Subtotal', '\$${order.subtotal.toStringAsFixed(0)}'),
                const SizedBox(height: 8),
                _kv('Envío', '\$${order.deliveryFee.toStringAsFixed(0)}'),
                const SizedBox(height: 8),
                _kv('Servicio', '\$${order.serviceFee.toStringAsFixed(0)}'),
                const SizedBox(height: 8),
                _kv('Impuestos', '\$${order.tax.toStringAsFixed(0)}'),
                if (order.tip > 0) ...[
                  const SizedBox(height: 8),
                  _kv('Propina', '\$${order.tip.toStringAsFixed(0)}'),
                ],
                const Divider(height: 22),
                _kv(
                  'Total',
                  '\$${order.amountTotal.toStringAsFixed(0)} ${order.currency}',
                  valueStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                    fontSize: 16,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _formatPaymentMethod(Payment payment) {
    final rawMethodId = payment.paymentMethodId?.trim().toLowerCase();
    final rawStatusDetail = payment.statusDetail?.trim().toLowerCase();

    final isCash = payment.paymentMethod == PaymentMethod.cash ||
        rawMethodId == 'cash' ||
        rawStatusDetail == 'cash_on_delivery';

    if (isCash) {
      return 'Efectivo';
    }

    final methodId = payment.paymentMethodId;
    if (methodId != null && methodId.trim().isNotEmpty) {
      return 'Mercado Pago (${methodId.toUpperCase()})';
    }

    final method = payment.paymentMethod;
    if (method == null) return 'Mercado Pago';

    switch (method) {
      case PaymentMethod.creditCard:
        return 'Tarjeta de crédito';
      case PaymentMethod.debitCard:
        return 'Tarjeta de débito';
      case PaymentMethod.mercadoPago:
        return 'Mercado Pago';
      case PaymentMethod.bankTransfer:
        return 'Transferencia';
      case PaymentMethod.cash:
        return 'Efectivo';
      case PaymentMethod.pix:
        return 'Pix';
      case PaymentMethod.other:
        return 'Otro';
    }
  }

  Widget _kv(
    String k,
    String v, {
    TextStyle? valueStyle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: textGray600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            v,
            textAlign: TextAlign.right,
            style: valueStyle ??
                const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: textGray900.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;

  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 54, color: Colors.red),
            const SizedBox(height: 10),
            const Text(
              'No pudimos cargar la boleta',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: textGray900,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(color: textGray600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
