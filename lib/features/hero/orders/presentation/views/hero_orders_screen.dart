import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/common/hero_header_app_bar.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../data/providers/repository_providers.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/order_status.dart';
import '../../../../billing/domain/entities/invoice_entity.dart';
import '../../../../billing/presentation/providers/billing_providers.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../payment/payment_processing_screen.dart';
import '../../../payment/providers/payment_providers.dart';
import '../../../presentation/views/hero_home_screen.dart';
import 'hero_order_status_screen.dart';

const _pendingPaymentTimeout = Duration(minutes: 5);

final _pendingPaymentTickerProvider = StreamProvider.autoDispose<int>((ref) {
  return Stream<int>.periodic(const Duration(seconds: 1), (tick) => tick);
});

class HeroOrdersScreen extends ConsumerWidget {
  const HeroOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: HeroHeaderAppBar(
        title: 'Mis pedidos',
        icon: Icons.receipt_long_rounded,
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HeroHomeScreen()),
            (route) => false,
          );
        },
      ),
      body: userId == null
          ? const _EmptyState(
              icon: Icons.login,
              title: 'Inicia sesión',
              message: 'Necesitas iniciar sesión para ver tus pedidos.',
            )
          : Builder(
              builder: (context) {
                final uid = userId;
                final ordersAsync = ref.watch(myOrdersProvider(uid));
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
                    if (orders.isEmpty) {
                      return const _EmptyState(
                        icon: Icons.receipt_long,
                        title: 'Aún no tienes pedidos',
                        message: 'Cuando compres, podrás seguirlos desde aquí.',
                      );
                    }

                    final sorted = [...orders]
                      ..sort((a, b) {
                        final byDate = b.timestamps.createdAt.compareTo(
                          a.timestamps.createdAt,
                        );
                        if (byDate != 0) return byDate;
                        return b.orderId.compareTo(a.orderId);
                      });

                    return RefreshIndicator(
                      color: primaryOrange,
                      onRefresh: () async {
                        ref.invalidate(myOrdersProvider(uid));
                        await Future<void>.delayed(
                          const Duration(milliseconds: 250),
                        );
                      },
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        itemCount: sorted.length,
                        itemBuilder: (context, index) {
                          return _OrderTile(order: sorted[index], uid: uid);
                        },
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _OrderTile extends ConsumerWidget {
  final Order order;
  final String uid;

  const _OrderTile({required this.order, required this.uid});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentState = ref.watch(paymentNotifierProvider);
    final isPayingOrder = paymentState.isProcessing;
    final isPendingPayment = order.status == OrderStatus.pendingPayment;
    if (isPendingPayment) {
      ref.watch(_pendingPaymentTickerProvider);
    }
    final paymentExpiresAt =
        order.paymentExpiresAt ??
        order.timestamps.createdAt.add(_pendingPaymentTimeout);
    final paymentRemaining = paymentExpiresAt.difference(DateTime.now());
    final isPaymentExpired =
        isPendingPayment && paymentRemaining.inSeconds <= 0;
    final canShowReceipt =
        order.status != OrderStatus.created &&
        order.status != OrderStatus.pendingPayment &&
        order.status != OrderStatus.canceled &&
        order.status != OrderStatus.failed;

    final statusColor = _statusColorForOrder(order);
    final statusBg = _statusBgForOrder(order);
    final shortId = order.orderId.length > 8
        ? order.orderId.substring(0, 8)
        : order.orderId;
    final createdAtText = _formatCreatedAt(order.timestamps.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
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
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TileHeader(
              order: order,
              statusBg: statusBg,
              statusColor: statusColor,
              shortId: shortId,
            ),
            Container(height: 1, color: borderGray100),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    icon: Icons.calendar_today_rounded,
                    iconColor: textGray600,
                    text: 'Fecha: $createdAtText',
                  ),
                  const SizedBox(height: 6),
                  if (order.delivery.addressSnapshot.isNotEmpty) ...[
                    _InfoRow(
                      icon: Icons.location_on_rounded,
                      iconColor: const Color(0xFF2563EB),
                      text: order.delivery.addressSnapshot,
                    ),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: [
                      _InfoRow(
                        icon: Icons.shopping_bag_outlined,
                        iconColor: textGray600,
                        text:
                            '${order.totalItems} producto${order.totalItems == 1 ? '' : 's'}',
                      ),
                      if (order.rider.isAssigned &&
                          (order.rider.riderNameSnapshot?.isNotEmpty ??
                              false)) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _InfoRow(
                            icon: Icons.delivery_dining_rounded,
                            iconColor: primaryOrange,
                            text: '${order.rider.riderNameSnapshot!} (Rider)',
                            textColor: primaryOrange,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (order.isFulfillmentBlocked) ...[
                    const SizedBox(height: 8),
                    const _InfoRow(
                      icon: Icons.support_agent_rounded,
                      iconColor: Color(0xFFB45309),
                      text: 'Pago recibido; soporte revisara este pedido',
                      textColor: Color(0xFF92400E),
                      fontWeight: FontWeight.w800,
                    ),
                  ],
                  // Show payment and delete buttons for pending payment orders
                  if (isPendingPayment) ...[
                    const SizedBox(height: 6),
                    _InfoRow(
                      icon: Icons.timer_rounded,
                      iconColor: isPaymentExpired ? Colors.red : primaryOrange,
                      text: isPaymentExpired
                          ? 'Reserva expirada; se cancelará automáticamente'
                          : 'Reserva expira en ${_formatPaymentRemaining(paymentRemaining)}',
                      textColor: isPaymentExpired ? Colors.red : primaryOrange,
                      fontWeight: FontWeight.w800,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: isPayingOrder || isPaymentExpired
                                ? null
                                : () async {
                                    try {
                                      // Create payment preference
                                      final paymentNotifier = ref.read(
                                        paymentNotifierProvider.notifier,
                                      );
                                      await paymentNotifier.createPreference(
                                        order,
                                      );

                                      final paymentState = ref.read(
                                        paymentNotifierProvider,
                                      );

                                      if (paymentState.error != null) {
                                        final errorCode =
                                            (paymentState.errorCode ?? '')
                                                .toLowerCase();
                                        final raw = paymentState.error ?? '';
                                        final message = raw.toLowerCase();
                                        String userMessage = 'Error: $raw';

                                        if (errorCode == 'resource-exhausted') {
                                          userMessage =
                                              'Hay mucha demanda en este momento. Espera 30 segundos y vuelve a intentar.';
                                        } else if (errorCode ==
                                                'deadline-exceeded' ||
                                            message.contains('expir')) {
                                          userMessage =
                                              'La reserva expiró. Crea una nueva solicitud para volver a pagar.';
                                        } else if (message.contains(
                                              'stock insuficiente',
                                            ) ||
                                            message.contains(
                                              'failed-precondition',
                                            )) {
                                          userMessage =
                                              'Este servicio ya no está disponible. Intenta con otro.';
                                        }

                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(userMessage),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                        return;
                                      }

                                      if (paymentState.initPoint != null &&
                                          context.mounted) {
                                        // Navigate to payment processing screen
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                PaymentProcessingScreen(
                                                  initPoint:
                                                      paymentState.initPoint!,
                                                  orderId: order.orderId,
                                                  preferenceId:
                                                      paymentState
                                                          .preferenceId ??
                                                      '',
                                                ),
                                          ),
                                        );
                                      } else if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'No se pudo obtener el link de pago',
                                            ),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Error al procesar pago: $e',
                                            ),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.payment, size: 18),
                            label: Text(
                              isPaymentExpired
                                  ? 'Expirado'
                                  : isPayingOrder
                                  ? 'Procesando...'
                                  : 'Pagar',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              // Show confirmation dialog
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  icon: const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.red,
                                    size: 48,
                                  ),
                                  title: const Text(
                                    'Cancelar orden',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  content: const Text(
                                    '¿Cancelar esta orden pendiente? El stock volverá a estar disponible.',
                                    textAlign: TextAlign.center,
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancelar'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                      child: const Text(
                                        'Cancelar orden',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true && context.mounted) {
                                try {
                                  await ref
                                      .read(ordersRepositoryProvider)
                                      .cancelOrder(
                                        order.orderId,
                                        'Cancelado por el usuario',
                                        uid,
                                      );

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Orden cancelada'),
                                        backgroundColor: categoryTextGreen,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text(
                              'Cancelar',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  if (canShowReceipt) ...[
                    const SizedBox(height: 12),
                    _InvoiceAction(order: order),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatCreatedAt(DateTime createdAt) {
    final local = createdAt.toLocal();
    return DateFormat('dd/MM/yyyy HH:mm').format(local);
  }

  static String _formatPaymentRemaining(Duration duration) {
    final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static IconData _statusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.created:
      case OrderStatus.queued:
      case OrderStatus.pendingPayment:
      case OrderStatus.paid:
        return Icons.schedule;
      case OrderStatus.assigned:
        return Icons.check_circle_outline;
      case OrderStatus.pickedUp:
      case OrderStatus.inTransit:
        return Icons.local_shipping_outlined;
      case OrderStatus.delivered:
        return Icons.task_alt;
      case OrderStatus.canceled:
        return Icons.cancel_outlined;
      case OrderStatus.failed:
        return Icons.error_outline;
    }
  }

  static IconData _statusIconForOrder(Order order) {
    if (order.isFulfillmentBlocked) {
      return Icons.support_agent_rounded;
    }
    return _statusIcon(order.status);
  }

  static Color _statusBgForOrder(Order order) {
    if (order.isFulfillmentBlocked) {
      return const Color(0xFFFEF3C7);
    }
    return _statusBg(order.status);
  }

  static Color _statusColorForOrder(Order order) {
    if (order.isFulfillmentBlocked) {
      return const Color(0xFFB45309);
    }
    return _statusColor(order.status);
  }

  static Color _statusBg(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return const Color(0xFFD1FAE5);
      case OrderStatus.canceled:
      case OrderStatus.failed:
        return const Color(0xFFFEE2E2);
      case OrderStatus.assigned:
      case OrderStatus.pickedUp:
      case OrderStatus.inTransit:
        return const Color(0xFFFFEDD5);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  static Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.delivered:
        return categoryTextGreen;
      case OrderStatus.canceled:
      case OrderStatus.failed:
        return const Color(0xFFDC2626);
      case OrderStatus.assigned:
      case OrderStatus.pickedUp:
      case OrderStatus.inTransit:
        return primaryOrange;
      default:
        return textGray600;
    }
  }
}

class _TileHeader extends StatelessWidget {
  final Order order;
  final Color statusBg;
  final Color statusColor;
  final String shortId;

  const _TileHeader({
    required this.order,
    required this.statusBg,
    required this.statusColor,
    required this.shortId,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Stack(
        children: [
          Container(width: double.infinity, color: statusBg),
          Positioned(
            top: -4,
            right: 10,
            child: Text(
              'HERO',
              style: TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.w900,
                letterSpacing: -2,
                height: 1,
                color: statusColor.withValues(alpha: 0.08),
                fontFamily: 'Arial',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _OrderTile._statusIconForOrder(order),
                    color: statusColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.isFulfillmentBlocked
                            ? 'Pago en revision'
                            : order.status.displayName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'HRO-$shortId',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: statusColor.withValues(alpha: 0.75),
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _PriceTag(amount: order.amountTotal, statusColor: statusColor),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceTag extends StatelessWidget {
  final double amount;
  final Color statusColor;

  const _PriceTag({required this.amount, required this.statusColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '\$${amount.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: statusColor,
            letterSpacing: -0.5,
            height: 1,
          ),
        ),
        Text(
          'CLP',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: statusColor.withValues(alpha: 0.6),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final Color? textColor;
  final FontWeight? fontWeight;

  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.text,
    this.textColor,
    this.fontWeight,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 12, color: iconColor),
        ),
        const SizedBox(width: 6),
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: fontWeight ?? FontWeight.w600,
              color: textColor ?? textGray600,
            ),
          ),
        ),
      ],
    );
  }
}

class _InvoiceAction extends ConsumerWidget {
  final Order order;

  const _InvoiceAction({required this.order});

  String get _documentLabel => order.isFactura ? 'Factura' : 'Boleta';

  String _statusLabel(BillingInvoiceStatus status) {
    switch (status) {
      case BillingInvoiceStatus.pending:
        return '$_documentLabel en proceso';
      case BillingInvoiceStatus.issued:
        return '$_documentLabel emitida';
      case BillingInvoiceStatus.failed:
        return 'Error al emitir ${_documentLabel.toLowerCase()}';
      case BillingInvoiceStatus.canceled:
        return '$_documentLabel anulada';
      case BillingInvoiceStatus.unknown:
        return '$_documentLabel pendiente';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoiceAsync = ref.watch(invoiceByOrderIdProvider(order.orderId));

    return invoiceAsync.when(
      loading: () => _InfoInvoiceBanner(
        icon: Icons.hourglass_top_rounded,
        text: 'Buscando ${_documentLabel.toLowerCase()} de este pedido...',
      ),
      error: (_, _) => _InfoInvoiceBanner(
        icon: Icons.receipt_long_rounded,
        text: '$_documentLabel pendiente de emisión',
      ),
      data: (invoice) {
        if (invoice == null) {
          return _InfoInvoiceBanner(
            icon: Icons.receipt_long_rounded,
            text: '$_documentLabel pendiente de emisión',
          );
        }

        if (!invoice.isIssued || !invoice.hasPdf) {
          final banner = _InfoInvoiceBanner(
            icon: invoice.status == BillingInvoiceStatus.failed
                ? Icons.error_outline_rounded
                : Icons.receipt_long_rounded,
            text: _statusLabel(invoice.status),
            color: invoice.status == BillingInvoiceStatus.failed
                ? const Color(0xFFB91C1C)
                : textGray700,
          );

          if (invoice.status == BillingInvoiceStatus.failed) {
            return Column(
              children: [
                banner,
                const SizedBox(height: 8),
                _RetryInvoiceButton(
                  invoiceId: invoice.invoiceId,
                  documentLabel: _documentLabel,
                ),
              ],
            );
          }

          return banner;
        }

        return _InvoiceButton(
          invoiceId: invoice.invoiceId,
          documentLabel: _documentLabel,
        );
      },
    );
  }
}

class _InfoInvoiceBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoInvoiceBanner({
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

class _InvoiceButton extends ConsumerStatefulWidget {
  final String invoiceId;
  final String documentLabel;

  const _InvoiceButton({required this.invoiceId, required this.documentLabel});

  @override
  ConsumerState<_InvoiceButton> createState() => _InvoiceButtonState();
}

class _InvoiceButtonState extends ConsumerState<_InvoiceButton> {
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
                ? 'No se pudo abrir ${widget.documentLabel.toLowerCase()}: $errorMessage'
                : 'No se pudo abrir ${widget.documentLabel.toLowerCase()}',
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
          content: Text('URL del documento inválida'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el PDF'),
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
              isLoading
                  ? 'Abriendo ${widget.documentLabel.toLowerCase()}...'
                  : 'Ver ${widget.documentLabel.toLowerCase()}',
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

class _RetryInvoiceButton extends ConsumerStatefulWidget {
  final String invoiceId;
  final String documentLabel;

  const _RetryInvoiceButton({
    required this.invoiceId,
    required this.documentLabel,
  });

  @override
  ConsumerState<_RetryInvoiceButton> createState() =>
      _RetryInvoiceButtonState();
}

class _RetryInvoiceButtonState extends ConsumerState<_RetryInvoiceButton> {
  bool _isRetrying = false;

  Future<void> _retry() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);

    String? errorMessage;
    try {
      final useCase = ref.read(retryInvoiceEmissionUseCaseProvider);
      await useCase.execute(widget.invoiceId);
    } catch (e) {
      errorMessage = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }

    if (!mounted) return;
    if (errorMessage != null && errorMessage.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo reintentar: $errorMessage'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Reintento solicitado. Estamos generando ${widget.documentLabel.toLowerCase()}.',
        ),
        backgroundColor: categoryTextGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isRetrying ? null : _retry,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isRetrying) ...[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 8),
            ] else ...[
              const Icon(
                Icons.refresh_rounded,
                size: 15,
                color: Color(0xFFB45309),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              _isRetrying ? 'Reintentando...' : 'Reintentar generar',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: Color(0xFFB45309),
              ),
            ),
          ],
        ),
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
