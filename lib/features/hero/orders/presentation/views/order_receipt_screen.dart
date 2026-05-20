import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/payment.dart';
import '../../../../billing/domain/entities/invoice_entity.dart';
import '../../../../billing/presentation/providers/billing_providers.dart';
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
    final receiptTitle = orderAsync.maybeWhen(
      data: (order) => (order?.isFactura ?? false) ? 'Factura' : 'Boleta',
      orElse: () => 'Comprobante',
    );

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: Text(
          receiptTitle,
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

class _ReceiptBody extends ConsumerWidget {
  final Order order;
  final Payment? payment;
  final bool isRiderView;

  const _ReceiptBody({
    required this.order,
    required this.payment,
    required this.isRiderView,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPaid = payment?.status == PaymentStatus.approved;
    final isCashPayment = payment?.paymentMethod == PaymentMethod.cash ||
        (payment?.paymentMethodId?.toLowerCase() == 'cash') ||
        (payment?.statusDetail?.toLowerCase() == 'cash_on_delivery');
    final hideTotalsForRider = isRiderView && !isCashPayment;
    final isFactura = order.isFactura;
    final invoiceAsync = isFactura
        ? ref.watch(invoiceByOrderIdProvider(order.orderId))
        : const AsyncValue<BillingInvoiceEntity?>.data(null);

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
                  color: isFactura
                      ? const Color(0xFFFFF7ED)
                      : (isPaid
                          ? categoryTextGreen.withValues(alpha: 0.08)
                          : const Color(0xFFFFF7ED)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isFactura
                        ? const Color(0xFFFDE68A)
                        : (isPaid
                            ? categoryTextGreen.withValues(alpha: 0.25)
                            : const Color(0xFFFDE68A)),
                  ),
                ),
                child: Text(
                  isFactura
                      ? 'Este pedido se emite como factura. Puedes descargarla cuando este disponible.'
                      : (isPaid
                          ? 'Pago confirmado.'
                          : 'Esta boleta esta disponible, pero el pago aun no esta confirmado.'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isFactura
                        ? const Color(0xFF92400E)
                        : (isPaid
                            ? categoryTextGreen
                            : const Color(0xFF92400E)),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (isFactura) ...[
          const SizedBox(height: 12),
          _Card(
            child: _InvoiceSection(
              invoiceAsync: invoiceAsync,
            ),
          ),
        ],
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

class _InvoiceSection extends ConsumerWidget {
  final AsyncValue<BillingInvoiceEntity?> invoiceAsync;

  const _InvoiceSection({
    required this.invoiceAsync,
  });

  String _statusLabel(BillingInvoiceStatus status) {
    switch (status) {
      case BillingInvoiceStatus.pending:
        return 'Factura en proceso de emision.';
      case BillingInvoiceStatus.issued:
        return 'Factura emitida.';
      case BillingInvoiceStatus.failed:
        return 'No se pudo emitir la factura.';
      case BillingInvoiceStatus.canceled:
        return 'Factura anulada.';
      case BillingInvoiceStatus.unknown:
        return 'Factura pendiente de emision.';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Factura',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: textGray900,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 10),
        invoiceAsync.when(
          loading: () => const _InvoiceInfoBanner(
            icon: Icons.hourglass_top_rounded,
            text: 'Buscando factura de este pedido...',
          ),
          error: (_, _) => const _InvoiceInfoBanner(
            icon: Icons.receipt_long_rounded,
            text: 'Factura pendiente de emision.',
          ),
          data: (invoice) {
            if (invoice == null) {
              return const _InvoiceInfoBanner(
                icon: Icons.receipt_long_rounded,
                text: 'Factura pendiente de emision.',
              );
            }

            if (!invoice.isIssued || !invoice.hasPdf) {
              return _InvoiceInfoBanner(
                icon: invoice.status == BillingInvoiceStatus.failed
                    ? Icons.error_outline_rounded
                    : Icons.receipt_long_rounded,
                text: _statusLabel(invoice.status),
                color: invoice.status == BillingInvoiceStatus.failed
                    ? const Color(0xFFB91C1C)
                    : textGray700,
              );
            }

            return _InvoiceDownloadButton(invoiceId: invoice.invoiceId);
          },
        ),
      ],
    );
  }
}

class _InvoiceInfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InvoiceInfoBanner({
    required this.icon,
    required this.text,
    this.color = textGray700,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundGray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderGray100),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceDownloadButton extends ConsumerStatefulWidget {
  final String invoiceId;

  const _InvoiceDownloadButton({required this.invoiceId});

  @override
  ConsumerState<_InvoiceDownloadButton> createState() =>
      _InvoiceDownloadButtonState();
}

class _InvoiceDownloadButtonState extends ConsumerState<_InvoiceDownloadButton> {
  bool _isLoading = false;

  Future<void> _openInvoice() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    String? url;
    String? errorMessage;
    try {
      final useCase = ref.read(getInvoicePdfUrlUseCaseProvider);
      url = await useCase.execute(widget.invoiceId);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    if (!mounted) return;
    if (url == null || url.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessage?.trim().isNotEmpty == true
                ? 'No se pudo abrir la factura: $errorMessage'
                : 'No se pudo abrir la factura',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL de factura invalida'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el PDF de factura'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _isLoading;

    return GestureDetector(
      onTap: isLoading ? null : _openInvoice,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: backgroundGray50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: primaryOrange.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: primaryOrange,
                ),
              ),
              const SizedBox(width: 8),
            ] else ...[
              const Icon(
                Icons.picture_as_pdf_rounded,
                size: 15,
                color: primaryOrange,
              ),
              const SizedBox(width: 7),
            ],
            Text(
              isLoading ? 'Abriendo factura...' : 'Descargar factura',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: primaryOrange,
              ),
            ),
          ],
        ),
      ),
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
              'No pudimos cargar el comprobante',
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
