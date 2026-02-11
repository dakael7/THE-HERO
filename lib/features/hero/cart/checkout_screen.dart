import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

import '../../../core/constants/app_colors.dart';
import '../../../core/config/env.dart';
import '../../../core/config/mercadopago_config.dart';
import '../../../core/utils/weight_utils.dart';
import '../../../features/shared/profile/presentation/providers/profile_provider.dart';
import '../../../features/shared/profile/presentation/views/location_picker_screen.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/providers/orders_usecase_providers.dart';
import '../payment/widgets/payment_method_selector.dart';
import '../payment/providers/payment_providers.dart';
import '../payment/payment_processing_screen.dart';
import 'cart_provider.dart';
import 'cart_summary_provider.dart';
import 'order_builder.dart';
import 'waiting_rider_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _instructionsController = TextEditingController();
  static const _defaultCountryCode = '+56 ';
  bool _prefilled = false;
  bool _isSubmitting = false;
  bool _deliverToReception = false;
  double? _deliveryLatitude;
  double? _deliveryLongitude;
  ProviderSubscription<AsyncValue<User?>>? _profileSub;
  PaymentMethod _selectedPaymentMethod = PaymentMethod.mercadopago;

  firestore.GeoPoint? _tryParseGeoFromText(String text) {
    final input = text.trim();
    if (input.isEmpty) return null;

    final latLngMatch = RegExp(
      r'lat\s*[:=]?\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*lng\s*[:=]?\s*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(input);

    if (latLngMatch != null) {
      final lat = double.tryParse(latLngMatch.group(1) ?? '');
      final lng = double.tryParse(latLngMatch.group(2) ?? '');
      if (lat != null && lng != null) {
        return firestore.GeoPoint(lat, lng);
      }
    }

    final pairMatch = RegExp(
      r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(input);

    if (pairMatch != null) {
      final lat = double.tryParse(pairMatch.group(1) ?? '');
      final lng = double.tryParse(pairMatch.group(2) ?? '');
      if (lat != null && lng != null) {
        return firestore.GeoPoint(lat, lng);
      }
    }

    return null;
  }

  bool _isValidGeo(firestore.GeoPoint? geo) {
    if (geo == null) return false;
    if (geo.latitude == 0 && geo.longitude == 0) return false;
    return geo.latitude >= -90 &&
        geo.latitude <= 90 &&
        geo.longitude >= -180 &&
        geo.longitude <= 180;
  }

  @override
  void dispose() {
    _profileSub?.close();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillFromProfile());
    _profileSub = ref.listenManual<AsyncValue<User?>>(profileProvider, (
      previous,
      next,
    ) {
      if (next.hasValue && !_prefilled) {
        _prefillFromProfile(next.value);
      }
    });
  }

  void _prefillFromProfile([User? provided]) {
    final user = provided ?? ref.read(profileProvider).value;
    if (user == null) return;

    if (_nameController.text.trim().isEmpty) {
      _nameController.text = user.fullName;
    }
    if (_phoneController.text.trim().isEmpty) {
      final phone = user.phoneNumber;
      _phoneController.text = phone.isNotEmpty ? phone : _defaultCountryCode;
    }
    if (_addressController.text.trim().isEmpty && user.address != null) {
      _addressController.text = user.address!.fullAddress;
    }
    _prefilled = true;
  }

  Future<void> _openMapPicker() async {
    final apiKey = Env.placesApiKey;
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falta configurar PLACES_API_KEY'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final result = await Navigator.of(context).push<MapLocationResult>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          apiKey: apiKey,
          initialAddress: _addressController.text.trim().isNotEmpty
              ? _addressController.text.trim()
              : null,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _addressController.text = result.address;
        _deliveryLatitude = result.latitude;
        _deliveryLongitude = result.longitude;
      });

      print(
        '📍 [Checkout] Delivery coordinates captured: ${result.latitude}, ${result.longitude}',
      );
    }
  }

  Future<void> _proceedToPayment() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final cartItems = ref.read(cartProvider);
    final summary = ref.read(cartSummaryProvider);
    final user = ref.read(profileProvider).value;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes iniciar sesión para continuar'),
          duration: Duration(milliseconds: 2000),
        ),
      );
      return;
    }

    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      var deliveryGeo = _deliveryLatitude != null && _deliveryLongitude != null
          ? firestore.GeoPoint(_deliveryLatitude!, _deliveryLongitude!)
          : null;

      deliveryGeo ??= _tryParseGeoFromText(_addressController.text);

      if (!_isValidGeo(deliveryGeo)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Selecciona una ubicación válida en el mapa para la entrega.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Create delivery info with coordinates
      final delivery = OrderBuilder.createDelivery(
        address: _addressController.text.trim(),
        recipientName: _nameController.text.trim(),
        recipientPhone: _phoneController.text.trim(),
        instructions: _instructionsController.text.trim(),
        deliverToReception: _deliverToReception,
        geo: deliveryGeo,
      );

      print(
        '📦 [Checkout] Creating order with delivery geo: ${delivery.geo.latitude}, ${delivery.geo.longitude}',
      );

      final pickupGeo =
          user.address?.latitude != null && user.address?.longitude != null
          ? firestore.GeoPoint(user.address!.latitude, user.address!.longitude)
          : null;

      final pickupAddress =
          user.address?.fullAddress ?? 'Dirección del vendedor';

      final resolvedPickupGeo =
          pickupGeo ?? _tryParseGeoFromText(pickupAddress);

      print(
        '📍 [Checkout] Pickup geo from profile: ${pickupGeo?.latitude}, ${pickupGeo?.longitude}',
      );

      final firstItem = cartItems.first;
      final pickupSchedule = firstItem.pickupSchedule;
      final useConcierge = firstItem.useConcierge;
      final conciergeInfo = firstItem.conciergeInfo;

      final order = OrderBuilder.buildOrderFromCart(
        cartItems: cartItems,
        cartSummary: summary,
        heroId: user.id,
        delivery: delivery,
        pickupAddress: pickupAddress,
        pickupGeo: resolvedPickupGeo,
        pickupContactName: user.fullName,
        pickupContactPhone: user.phoneNumber,
        pickupSchedule: pickupSchedule,
        useConcierge: useConcierge,
        conciergeInfo: conciergeInfo,
      );

      final createOrderUseCase = ref.read(createOrderUseCaseProvider);
      final createdOrder = await createOrderUseCase.execute(order);

      // Determine payment flow based on method and environment
      final shouldUseMercadoPago =
          _selectedPaymentMethod == PaymentMethod.mercadopago &&
          MercadoPagoConfig.isProduction;

      if (shouldUseMercadoPago) {
        // Production flow with MercadoPago
        debugPrint('💳 [Checkout] Using MercadoPago payment flow');

        // Set order status to pending_payment
        final updateStatusUseCase = ref.read(updateOrderStatusUseCaseProvider);
        await updateStatusUseCase.execute(
          createdOrder.orderId,
          'pending_payment',
        );

        // Create payment preference
        final paymentNotifier = ref.read(paymentNotifierProvider.notifier);
        await paymentNotifier.createPreference(createdOrder);

        final paymentState = ref.read(paymentNotifierProvider);

        if (paymentState.error != null) {
          throw Exception(
            'Error al crear preferencia de pago: ${paymentState.error}',
          );
        }

        if (paymentState.initPoint == null) {
          throw Exception('No se pudo obtener el link de pago');
        }

        // Clear cart before navigating to payment
        ref.read(cartProvider.notifier).clear();

        // Show informative dialog before payment
        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              icon: const Icon(
                Icons.info_outline,
                color: primaryOrange,
                size: 48,
              ),
              title: const Text(
                'Orden creada',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              content: const Text(
                'Tu orden ha sido creada y está pendiente de pago. '
                'Serás redirigido a MercadoPago para completar el pago. '
                'Si no completas el pago ahora, podrás hacerlo más tarde desde "Mis pedidos".',
                textAlign: TextAlign.center,
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    'Continuar al pago',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: primaryOrange,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Navigate to payment processing screen
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => PaymentProcessingScreen(
                initPoint: paymentState.initPoint!,
                orderId: createdOrder.orderId,
                preferenceId: paymentState.preferenceId ?? '',
              ),
            ),
          );
        }
      } else {
        // Sandbox/Development flow OR Cash payment - skip MercadoPago
        debugPrint(
          '💵 [Checkout] Skipping MercadoPago (${_selectedPaymentMethod == PaymentMethod.cash ? "Cash payment" : "Sandbox mode"})',
        );

        final updateStatusUseCase = ref.read(updateOrderStatusUseCaseProvider);
        await updateStatusUseCase.execute(createdOrder.orderId, 'queued');

        // Clear cart after successful order creation
        ref.read(cartProvider.notifier).clear();

        if (mounted) {
          await _showPaymentResult(
            success: true,
            message:
                'Pedido HRO-${createdOrder.orderId} creado y publicado. Total: \$${createdOrder.amountTotal.toStringAsFixed(0)} CLP',
          );

          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) =>
                    WaitingRiderScreen(orderId: createdOrder.orderId),
              ),
            );
          }
        }
      }

      debugPrint('=== ORDER CREATED ===');
      debugPrint('Order ID: ${createdOrder.orderId}');
      debugPrint('Hero ID: ${createdOrder.heroId}');
      debugPrint('Items: ${createdOrder.items.length}');
      debugPrint('Subtotal: \$${createdOrder.subtotal}');
      debugPrint('Delivery Fee: \$${createdOrder.deliveryFee}');
      debugPrint('Service Fee: \$${createdOrder.serviceFee}');
      debugPrint('Tax: \$${createdOrder.tax}');
      debugPrint('Total: \$${createdOrder.amountTotal}');
      debugPrint('Weight: ${createdOrder.requirements.weightKg} kg');
      debugPrint(
        'Required Vehicle: ${createdOrder.requirements.requiredVehicle}',
      );
      debugPrint('Delivery Address: ${createdOrder.delivery.addressSnapshot}');
      debugPrint(
        'Delivery Geo: ${createdOrder.delivery.geo.latitude}, ${createdOrder.delivery.geo.longitude}',
      );
      debugPrint('Pickup Address: ${createdOrder.pickup.addressSnapshot}');
      debugPrint(
        'Pickup Geo: ${createdOrder.pickup.geo.latitude}, ${createdOrder.pickup.geo.longitude}',
      );
      debugPrint('Recipient: ${createdOrder.delivery.recipientName}');
      debugPrint('Payment Method: ${_selectedPaymentMethod.name}');
      debugPrint('Using MercadoPago: $shouldUseMercadoPago');
      debugPrint('====================');
    } catch (e) {
      await _showPaymentResult(
        success: false,
        message: 'Error al crear orden: $e',
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _showPaymentResult({
    required bool success,
    String? message,
  }) async {
    if (!mounted) return;

    final color = success ? Colors.green : Colors.red;
    final icon = success ? Icons.check_circle : Icons.error_rounded;
    final title = success ? 'Compra exitosa' : 'Pago fallido';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.7, end: 1.0),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Opacity(opacity: value.clamp(0, 1), child: child),
                    );
                  },
                  child: CircleAvatar(
                    radius: 38,
                    backgroundColor: color.withOpacity(0.12),
                    child: Icon(icon, color: color, size: 48),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: textGray900,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                if (message != null)
                  Text(
                    message,
                    style: const TextStyle(fontSize: 14, color: textGray700),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(success ? 'Continuar' : 'Entendido'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartItems = ref.watch(cartProvider);
    final summary = ref.watch(cartSummaryProvider);
    final totalItems = cartItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        title: const Text(
          'Checkout',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Delivery Address Section
            const Text(
              'Dirección de entrega',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: backgroundWhite,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: textGray900.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingresa tu nombre';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono',
                      hintText: 'Incluye código país',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingresa tu teléfono';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: 'Dirección',
                      hintText: 'Escribe o elige en el mapa',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      suffixIcon: IconButton(
                        onPressed: _openMapPicker,
                        icon: const Icon(Icons.map_outlined),
                        tooltip: 'Elegir en mapa',
                      ),
                    ),
                    maxLines: 2,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingresa tu dirección';
                      }
                      if (value.trim().length < 10) {
                        return 'Ingresa una dirección más detallada';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _openMapPicker,
                      icon: const Icon(Icons.place_outlined),
                      label: const Text('Elegir dirección con Google Maps'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _instructionsController,
                    decoration: const InputDecoration(
                      labelText: 'Instrucciones de entrega (opcional)',
                      hintText: 'Ej: Tocar el timbre 2 veces',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _deliverToReception,
                    onChanged: _isSubmitting
                        ? null
                        : (val) {
                            setState(() => _deliverToReception = val);
                          },
                    title: const Text(
                      'Recibir en portería',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textGray900,
                      ),
                    ),
                    subtitle: const Text(
                      'Actívalo si quieres que el repartidor entregue en recepción/portería.',
                      style: TextStyle(color: textGray600, fontSize: 12),
                    ),
                    activeThumbColor: primaryOrange,
                    activeTrackColor: primaryOrange.withValues(alpha: 0.12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Order Summary Section
            const Text(
              'Resumen del pedido',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: backgroundWhite,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: textGray900.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
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
                        '$totalItems artículo${totalItems == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textGray700,
                        ),
                      ),
                      Text(
                        formatWeightKg(summary.totalWeight),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textGray700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: borderGray100),
                  const SizedBox(height: 12),
                  _buildSummaryRow(
                    'Subtotal:',
                    '\$${summary.subtotal.toStringAsFixed(0)}',
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryRow(
                        'Envío:',
                        '\$${summary.shippingCost.toStringAsFixed(0)}',
                      ),
                      if (summary.shippingBreakdown != null) ...[
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            summary.shippingBreakdown!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: textGray600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'Comisión:',
                    '\$${summary.serviceFee.toStringAsFixed(0)}',
                  ),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'IVA (19%):',
                    '\$${summary.tax.toStringAsFixed(0)}',
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: borderGray100),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: textGray900,
                        ),
                      ),
                      Text(
                        '\$${summary.total.toStringAsFixed(0)} CLP',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: primaryOrange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Payment Method Section
            const Text(
              'Método de pago',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 16),
            PaymentMethodSelector(
              selectedMethod: _selectedPaymentMethod,
              onMethodChanged: (method) {
                setState(() => _selectedPaymentMethod = method);
              },
            ),
            const SizedBox(height: 24),

            // Payment Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _proceedToPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryOrange,
                  foregroundColor: backgroundWhite,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 4,
                  shadowColor: primaryOrange.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            backgroundWhite,
                          ),
                        ),
                      )
                    : const Text(
                        'Proceder al pago',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: 0.3,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            if (!MercadoPagoConfig.isProduction)
              const Text(
                '⚠️ Modo Sandbox: El pago con MercadoPago está deshabilitado',
                style: TextStyle(
                  fontSize: 12,
                  color: textGray600,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: textGray700,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textGray900,
          ),
        ),
      ],
    );
  }
}
