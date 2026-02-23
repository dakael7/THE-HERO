import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/config/env.dart';
import '../../../core/config/mercadopago_config.dart';
import '../../../core/utils/weight_utils.dart';
import '../../../features/shared/profile/presentation/providers/profile_provider.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/entities/order_status.dart';
import '../../../domain/providers/orders_usecase_providers.dart';
import '../../shared/profile/presentation/views/location_picker_screen.dart';
import '../payment/widgets/payment_method_selector.dart';
import '../payment/providers/payment_providers.dart';
import '../payment/payment_processing_screen.dart';
import 'cart_item.dart';
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
  bool _useAccountAddress = false;
  double? _deliveryLatitude;
  double? _deliveryLongitude;
  String? _manualAddress;
  double? _manualDeliveryLatitude;
  double? _manualDeliveryLongitude;
  ProviderSubscription<AsyncValue<User?>>? _profileSub;
  PaymentMethod _selectedPaymentMethod = PaymentMethod.mercadopago;

  String? _lastRoutesSignature;
  bool _isLoadingRoutes = false;
  Object? _routesError;
  _OsrmTrip? _trip;

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

  void _setDeliveryFromAccountAddress(User user) {
    final addr = user.address;
    if (addr == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tu cuenta no tiene dirección guardada.'),
          duration: Duration(seconds: 2),
        ),
      );
      setState(() => _useAccountAddress = false);
      return;
    }

    setState(() {
      _addressController.text = addr.fullAddress;
      _deliveryLatitude = addr.latitude;
      _deliveryLongitude = addr.longitude;
    });

    ref.read(deliveryGeoProvider.notifier).state =
        firestore.GeoPoint(addr.latitude, addr.longitude);
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

      ref.read(deliveryGeoProvider.notifier).state =
          firestore.GeoPoint(result.latitude, result.longitude);

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
    final user = ref.read(profileStreamProvider).value;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes iniciar sesión para continuar'),
          duration: Duration(milliseconds: 2000),
        ),
      );
      return;
    }

    if (!user.isRutVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes verificar tu RUT para hacer pedidos.'),
          duration: Duration(seconds: 3),
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

      final shouldUseMercadoPago =
          _selectedPaymentMethod == PaymentMethod.mercadopago;

      final preGeneratedOrderId = firestore.FirebaseFirestore.instance
          .collection('orders')
          .doc()
          .id;

      final order = OrderBuilder.buildOrderFromCart(
        orderId: shouldUseMercadoPago ? preGeneratedOrderId : '',
        cartItems: cartItems,
        cartSummary: summary,
        heroId: user.id,
        delivery: delivery,
        status:
            shouldUseMercadoPago ? OrderStatus.pendingPayment : OrderStatus.queued,
        pickupAddress: pickupAddress,
        pickupGeo: resolvedPickupGeo,
        pickupContactName: user.fullName,
        pickupContactPhone: user.phoneNumber,
        pickupSchedule: pickupSchedule,
        useConcierge: useConcierge,
        conciergeInfo: conciergeInfo,
      );

      if (shouldUseMercadoPago) {
        // Production flow with MercadoPago
        debugPrint('💳 [Checkout] Using MercadoPago payment flow');

        // Create payment preference
        final paymentNotifier = ref.read(paymentNotifierProvider.notifier);
        await paymentNotifier.createPreference(order);

        final paymentState = ref.read(paymentNotifierProvider);

        if (paymentState.error != null) {
          final raw = paymentState.error ?? '';
          final message = raw.toLowerCase();

          if (message.contains('stock insuficiente') ||
              message.contains('failed-precondition')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Este artículo ya fue reservado/comprado por otro usuario. Intenta con otro.',
                ),
                duration: Duration(seconds: 3),
              ),
            );
            return;
          }

          if (message.contains('unit_price') && message.contains('integer')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Error de monto en MercadoPago. Actualiza la app y vuelve a intentar.',
                ),
                duration: Duration(seconds: 3),
              ),
            );
            return;
          }

          throw Exception('Error al crear preferencia de pago: $raw');
        }

        if (paymentState.initPoint == null) {
          throw Exception('No se pudo obtener el link de pago');
        }

        final createOrderUseCase = ref.read(createOrderUseCaseProvider);
        final createdOrder = await createOrderUseCase.execute(order);

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

        final createOrderUseCase = ref.read(createOrderUseCaseProvider);
        final createdOrder = await createOrderUseCase.execute(order);

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
    final deliveryGeo = ref.watch(deliveryGeoProvider);
    final profile = ref.watch(profileProvider);
    final user = profile.value;
    final totalItems = cartItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    final hasValidDelivery =
        _deliveryLatitude != null && _deliveryLongitude != null;

    final hasDeliveryGeo = deliveryGeo != null;
    final hasCalculatedShipping =
        hasDeliveryGeo && summary.shippingBreakdown != null;
    final canProceed = hasValidDelivery && hasCalculatedShipping;

    _scheduleRoutesLoad(cartItems: cartItems, deliveryGeo: deliveryGeo);

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
            _CheckoutItemsRouteMap(
              cartItems: cartItems,
              deliveryGeo: deliveryGeo,
              isLoading: _isLoadingRoutes,
              error: _routesError,
              trip: _trip,
            ),
            const SizedBox(height: 16),
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
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _useAccountAddress,
                    onChanged: _isSubmitting
                        ? null
                        : (val) {
                            if (val) {
                              _manualAddress = _addressController.text;
                              _manualDeliveryLatitude = _deliveryLatitude;
                              _manualDeliveryLongitude = _deliveryLongitude;

                              setState(() => _useAccountAddress = true);
                              if (user != null) {
                                _setDeliveryFromAccountAddress(user);
                              } else {
                                setState(() => _useAccountAddress = false);
                              }
                            } else {
                              setState(() {
                                _useAccountAddress = false;
                                _addressController.text = _manualAddress ?? '';
                                _deliveryLatitude = _manualDeliveryLatitude;
                                _deliveryLongitude = _manualDeliveryLongitude;
                              });

                              if (_deliveryLatitude != null &&
                                  _deliveryLongitude != null) {
                                ref.read(deliveryGeoProvider.notifier).state =
                                    firestore.GeoPoint(
                                  _deliveryLatitude!,
                                  _deliveryLongitude!,
                                );
                              } else {
                                ref.read(deliveryGeoProvider.notifier).state =
                                    null;
                              }
                            }
                          },
                    title: const Text(
                      'Usar dirección de la cuenta',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: textGray900,
                      ),
                    ),
                    subtitle: Text(
                      (user?.address?.fullAddress.isNotEmpty ?? false)
                          ? user!.address!.fullAddress
                          : 'No tienes una dirección guardada en tu cuenta.',
                      style: const TextStyle(color: textGray600, fontSize: 12),
                    ),
                    activeThumbColor: primaryOrange,
                    activeTrackColor: primaryOrange.withValues(alpha: 0.12),
                  ),
                  const SizedBox(height: 16),
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
                    enabled: !_useAccountAddress && !_isSubmitting,
                    decoration: InputDecoration(
                      labelText: 'Dirección',
                      hintText: 'Escribe o elige en el mapa',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      suffixIcon: IconButton(
                        onPressed:
                            _useAccountAddress || _isSubmitting ? null : _openMapPicker,
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
                      onPressed:
                          _useAccountAddress || _isSubmitting ? null : _openMapPicker,
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
                  if (!canProceed) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFED7AA)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(
                            Icons.location_on_outlined,
                            size: 18,
                            color: Color(0xFFEA580C),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Selecciona una ubicación en el mapa para calcular el envío y el total.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9A3412),
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
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
                    'Subtotal (Donación):',
                    '\$${summary.subtotal.toStringAsFixed(0)}',
                  ),
                  const SizedBox(height: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryRow(
                        'Envío:',
                        canProceed
                            ? '\$${summary.shippingCost.toStringAsFixed(0)}'
                            : '—',
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
                    'Comisión de servicio:',
                    canProceed
                        ? '\$${summary.serviceFee.toStringAsFixed(0)}'
                        : '—',
                  ),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                    'Impuestos (IVA 19%):',
                    canProceed ? '\$${summary.tax.toStringAsFixed(0)}' : '—',
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
                        canProceed
                            ? '\$${summary.total.toStringAsFixed(0)} CLP'
                            : '—',
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
                onPressed: _isSubmitting || !canProceed ? null : _proceedToPayment,
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

  void _scheduleRoutesLoad({
    required List<CartItem> cartItems,
    required firestore.GeoPoint? deliveryGeo,
  }) {
    final delivery = deliveryGeo;
    if (!_isValidGeo(delivery)) return;

    final pickupGeos = cartItems
        .map((e) => e.pickupGeo)
        .where(_isValidGeo)
        .cast<firestore.GeoPoint>()
        .toList();
    if (pickupGeos.isEmpty) return;

    final uniquePickups = <String, firestore.GeoPoint>{};
    for (final geo in pickupGeos) {
      final key = '${geo.latitude.toStringAsFixed(6)},${geo.longitude.toStringAsFixed(6)}';
      uniquePickups[key] = geo;
    }

    final signature = [
      '${delivery!.latitude.toStringAsFixed(6)},${delivery.longitude.toStringAsFixed(6)}',
      ...uniquePickups.keys.toList()..sort(),
    ].join('|');

    if (signature == _lastRoutesSignature) return;
    _lastRoutesSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadRoutes(uniquePickups: uniquePickups, delivery: delivery);
    });
  }

  Future<void> _loadRoutes({
    required Map<String, firestore.GeoPoint> uniquePickups,
    required firestore.GeoPoint delivery,
  }) async {
    if (_isLoadingRoutes) return;

    setState(() {
      _isLoadingRoutes = true;
      _routesError = null;
      _trip = null;
    });

    try {
      final trip = await _fetchOsrmTrip(
        pickupKeysToGeo: uniquePickups,
        delivery: LatLng(delivery.latitude, delivery.longitude),
      );
      if (!mounted) return;
      setState(() => _trip = trip);
      ref.read(routeDistanceKmProvider.notifier).state =
          (trip.distanceMeters / 1000.0);
    } catch (e) {
      if (!mounted) return;
      setState(() => _routesError = e);
    } finally {
      if (!mounted) return;
      setState(() => _isLoadingRoutes = false);
    }
  }

  Future<_OsrmTrip> _fetchOsrmTrip({
    required Map<String, firestore.GeoPoint> pickupKeysToGeo,
    required LatLng delivery,
  }) async {
    final pickupKeys = pickupKeysToGeo.keys.toList()..sort();
    final coords = <LatLng>[
      for (final key in pickupKeys)
        LatLng(
          pickupKeysToGeo[key]!.latitude,
          pickupKeysToGeo[key]!.longitude,
        ),
      delivery,
    ];

    final coordStr = coords
        .map((p) => '${p.longitude},${p.latitude}')
        .join(';');

    final url = Uri.parse(
      'https://router.project-osrm.org/trip/v1/driving/$coordStr'
      '?overview=full&geometries=geojson&roundtrip=false&source=any&destination=last',
    );

    final res = await http.get(url);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('OSRM error: ${res.statusCode}');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final trips = (json['trips'] as List?)?.cast<Map<String, dynamic>>();
    if (trips == null || trips.isEmpty) {
      throw Exception('OSRM: no trips');
    }

    final firstTrip = trips.first;
    final distanceMeters = (firstTrip['distance'] as num?)?.toDouble() ?? 0.0;
    final durationSeconds = (firstTrip['duration'] as num?)?.toDouble() ?? 0.0;

    final geometry = firstTrip['geometry'] as Map<String, dynamic>?;
    final tripCoords = (geometry?['coordinates'] as List?)?.cast<List>();
    if (tripCoords == null || tripCoords.isEmpty) {
      throw Exception('OSRM: missing trip geometry');
    }

    final polylinePoints = tripCoords
        .map((e) {
          final lng = (e[0] as num).toDouble();
          final lat = (e[1] as num).toDouble();
          return LatLng(lat, lng);
        })
        .toList(growable: false);

    final legsRaw = (firstTrip['legs'] as List?)?.cast<Map<String, dynamic>>();
    final legs = <_OsrmLeg>[];
    if (legsRaw != null) {
      for (final leg in legsRaw) {
        legs.add(
          _OsrmLeg(
            distanceMeters: (leg['distance'] as num?)?.toDouble() ?? 0.0,
            durationSeconds: (leg['duration'] as num?)?.toDouble() ?? 0.0,
          ),
        );
      }
    }

    final waypoints =
        (json['waypoints'] as List?)?.cast<Map<String, dynamic>>() ??
            <Map<String, dynamic>>[];

    // OSRM returns `waypoints` in the SAME order as the input coordinates.
    // Each waypoint contains `waypoint_index` which indicates its position
    // in the optimized trip. We want the optimized order of pickup points
    // (excluding the last input coord which is delivery).
    final indexed = <({int inputIndex, int waypointIndex})>[];
    for (var inputIndex = 0; inputIndex < waypoints.length; inputIndex++) {
      final w = waypoints[inputIndex];
      final wi = (w['waypoint_index'] as num?)?.toInt();
      if (wi == null) continue;
      indexed.add((inputIndex: inputIndex, waypointIndex: wi));
    }

    indexed.sort((a, b) => a.waypointIndex.compareTo(b.waypointIndex));

    final deliveryInputIndex = pickupKeys.length; // last coord in `coords`
    final orderedPickupKeys = <String>[];
    for (final entry in indexed) {
      if (entry.inputIndex == deliveryInputIndex) continue;
      if (entry.inputIndex >= 0 && entry.inputIndex < pickupKeys.length) {
        orderedPickupKeys.add(pickupKeys[entry.inputIndex]);
      }
    }

    // De-duplicate defensively
    final seen = <String>{};
    final orderedUnique = <String>[];
    for (final k in orderedPickupKeys) {
      if (seen.add(k)) orderedUnique.add(k);
    }

    return _OsrmTrip(
      points: polylinePoints,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      orderedPickupKeys: orderedUnique,
      legs: legs,
    );
  }
}

class _OsrmLeg {
  final double distanceMeters;
  final double durationSeconds;

  const _OsrmLeg({
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

class _OsrmTrip {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final List<String> orderedPickupKeys;
  final List<_OsrmLeg> legs;

  const _OsrmTrip({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.orderedPickupKeys,
    required this.legs,
  });
}

class _CheckoutItemsRouteMap extends StatelessWidget {
  final List<CartItem> cartItems;
  final firestore.GeoPoint? deliveryGeo;
  final bool isLoading;
  final Object? error;
  final _OsrmTrip? trip;

  const _CheckoutItemsRouteMap({
    required this.cartItems,
    required this.deliveryGeo,
    required this.isLoading,
    required this.error,
    required this.trip,
  });

  bool _isValidGeo(firestore.GeoPoint? geo) {
    if (geo == null) return false;
    if (geo.latitude == 0 && geo.longitude == 0) return false;
    return geo.latitude >= -90 &&
        geo.latitude <= 90 &&
        geo.longitude >= -180 &&
        geo.longitude <= 180;
  }

  String _formatKm(double meters) {
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  String _formatMin(double seconds) {
    final min = (seconds / 60.0).round();
    return '${min} min';
  }

  @override
  Widget build(BuildContext context) {
    final delivery = deliveryGeo;
    final hasDelivery = _isValidGeo(delivery);

    final pickupGeos = cartItems
        .map((e) => e.pickupGeo)
        .where(_isValidGeo)
        .cast<firestore.GeoPoint>()
        .toList();

    final uniquePickups = <String, firestore.GeoPoint>{};
    for (final geo in pickupGeos) {
      final key = '${geo.latitude.toStringAsFixed(6)},${geo.longitude.toStringAsFixed(6)}';
      uniquePickups[key] = geo;
    }

    final hasPickups = uniquePickups.isNotEmpty;
    final canShowMap = hasDelivery && hasPickups;

    if (!canShowMap) {
      return const SizedBox.shrink();
    }

    final deliveryLatLng = LatLng(delivery!.latitude, delivery.longitude);

    final pickupEntries = uniquePickups.entries.toList();
    pickupEntries.sort((a, b) => a.key.compareTo(b.key));

    final orderedKeys = trip?.orderedPickupKeys ?? <String>[];

    String _keyForGeo(firestore.GeoPoint geo) {
      return '${geo.latitude.toStringAsFixed(6)},${geo.longitude.toStringAsFixed(6)}';
    }

    final itemsByPickupKey = <String, List<CartItem>>{};
    for (final item in cartItems) {
      final geo = item.pickupGeo;
      if (!_isValidGeo(geo)) continue;
      final key = _keyForGeo(geo!);
      (itemsByPickupKey[key] ??= <CartItem>[]).add(item);
    }

    final colors = <Color>[
      const Color(0xFF2563EB),
      const Color(0xFF16A34A),
      const Color(0xFFDC2626),
      const Color(0xFF7C3AED),
    ];

    final polylines = <Polyline>[
      if (trip != null)
        Polyline(
          points: trip!.points,
          strokeWidth: 5,
          color: const Color(0xFF0F172A).withValues(alpha: 0.85),
        ),
    ];

    final markers = <Marker>[
      for (var i = 0; i < orderedKeys.length; i++)
        if (uniquePickups[orderedKeys[i]] != null)
          Marker(
            point: LatLng(
              uniquePickups[orderedKeys[i]]!.latitude,
              uniquePickups[orderedKeys[i]]!.longitude,
            ),
            width: 50,
            height: 50,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.location_on,
                  size: 44,
                  color: colors[i % colors.length],
                ),
                Positioned(
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      Marker(
        point: deliveryLatLng,
        width: 46,
        height: 46,
        child: const Icon(
          Icons.flag_circle,
          size: 42,
          color: Color(0xFF111827),
        ),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: textGray900.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 14, top: 14),
            child: Row(
              children: [
                const Icon(Icons.map_outlined, color: textGray900),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Ubicación de los items y distancia por ruta',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textGray900,
                    ),
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.zero,
              bottom: Radius.circular(16),
            ),
            child: SizedBox(
              height: 240,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: deliveryLatLng,
                  initialZoom: 12,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'the_hero',
                  ),
                  if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No se pudo calcular la ruta: $error',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else if (trip != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: borderGray100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.route, size: 18, color: textGray900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ruta total: ${_formatKm(trip!.distanceMeters)}',
                            style: const TextStyle(
                              color: textGray900,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: backgroundWhite,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _formatMin(trip!.durationSeconds),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: textGray900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (var stopIndex = 0; stopIndex < orderedKeys.length; stopIndex++) ...[
                    _RouteStopCard(
                      index: stopIndex + 1,
                      color: colors[stopIndex % colors.length],
                      title: 'Punto ${stopIndex + 1}',
                      subtitle: () {
                        final items = itemsByPickupKey[orderedKeys[stopIndex]] ?? const <CartItem>[];
                        final qty = items.fold<int>(0, (sum, e) => sum + e.quantity);
                        final names = items.map((e) => e.name).where((e) => e.trim().isNotEmpty).toList();
                        final firstTwo = names.take(2).join(' · ');
                        if (firstTwo.isEmpty) {
                          return '$qty artículo${qty == 1 ? '' : 's'}';
                        }
                        return '$qty artículo${qty == 1 ? '' : 's'} · $firstTwo${names.length > 2 ? '…' : ''}';
                      }(),
                      trailing: stopIndex < trip!.legs.length
                          ? _LegChips(leg: trip!.legs[stopIndex], formatKm: _formatKm, formatMin: _formatMin)
                          : null,
                    ),
                    if (stopIndex < orderedKeys.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 22),
                        child: Container(
                          width: 2,
                          height: 10,
                          color: borderGray100,
                        ),
                      ),
                  ],
                  const SizedBox(height: 8),
                  _RouteStopCard(
                    index: orderedKeys.length + 1,
                    color: const Color(0xFF111827),
                    title: 'Entrega',
                    subtitle: 'Destino final',
                    trailing: orderedKeys.length < trip!.legs.length
                        ? _LegChips(
                            leg: trip!.legs[orderedKeys.length],
                            formatKm: _formatKm,
                            formatMin: _formatMin,
                          )
                        : null,
                    icon: Icons.flag_circle,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LegChips extends StatelessWidget {
  final _OsrmLeg leg;
  final String Function(double meters) formatKm;
  final String Function(double seconds) formatMin;

  const _LegChips({
    required this.leg,
    required this.formatKm,
    required this.formatMin,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        _PillChip(
          icon: Icons.straighten,
          label: formatKm(leg.distanceMeters),
        ),
        _PillChip(
          icon: Icons.schedule,
          label: formatMin(leg.durationSeconds),
        ),
      ],
    );
  }
}

class _RouteStopCard extends StatelessWidget {
  final int index;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final IconData icon;

  const _RouteStopCard({
    required this.index,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.icon = Icons.location_on,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderGray100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                '$index',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: textGray900),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: textGray900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textGray600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PillChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: borderGray100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textGray700),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: textGray900,
            ),
          ),
        ],
      ),
    );
  }
}

extension _CheckoutSummaryRow on _CheckoutScreenState {
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
