import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/config/env.dart';
import '../../../core/config/mercadopago_config.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/map_camera_utils.dart';
import '../../../core/utils/price_formatter.dart';
import '../../../core/utils/weight_utils.dart';
import '../../../domain/config/pricing_config_provider.dart';
import '../../../domain/config/transport_pricing_config.dart';
import '../../../domain/entities/address.dart';
import '../../../domain/entities/order_requirements.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/entities/order_status.dart';
import '../../../domain/entities/vehicle.dart';
import '../../../domain/entities/payment.dart' as domain_payment;
import '../../../domain/providers/orders_usecase_providers.dart';
import '../../shared/profile/presentation/providers/profile_provider.dart';
import '../../shared/profile/presentation/views/location_picker_screen.dart';
import '../payment/widgets/payment_method_selector.dart';
import '../payment/providers/payment_providers.dart';
import '../payment/payment_processing_screen.dart';
import 'cart_item.dart';
import 'cart_provider.dart';
import 'cart_summary_provider.dart';
import 'order_builder.dart';
import 'waiting_rider_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  EXCEPTION (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _RouteCalculationException implements Exception {
  final String userMessage;
  final String debugMessage;
  final bool isTimeout;
  final bool isNetwork;

  const _RouteCalculationException._({
    required this.userMessage,
    required this.debugMessage,
    required this.isTimeout,
    required this.isNetwork,
  });

  factory _RouteCalculationException.timeout([String? debugMessage]) {
    return _RouteCalculationException._(
      userMessage:
          'No se pudo calcular la ruta por demora de conexión. Reintenta.',
      debugMessage: debugMessage ?? 'timeout',
      isTimeout: true,
      isNetwork: false,
    );
  }

  factory _RouteCalculationException.network([String? debugMessage]) {
    return _RouteCalculationException._(
      userMessage:
          'No se pudo calcular la ruta por falta de conexión. Verifica tu internet y reintenta.',
      debugMessage: debugMessage ?? 'network',
      isTimeout: false,
      isNetwork: true,
    );
  }

  factory _RouteCalculationException.service(String debugMessage) {
    return _RouteCalculationException._(
      userMessage:
          'No se pudo calcular la ruta en este momento. Intenta nuevamente.',
      debugMessage: debugMessage,
      isTimeout: false,
      isNetwork: false,
    );
  }

  factory _RouteCalculationException.noRoute([String? debugMessage]) {
    return _RouteCalculationException._(
      userMessage:
          'No se encontró una ruta válida para estas ubicaciones. Ajusta la dirección y reintenta.',
      debugMessage: debugMessage ?? 'no_route',
      isTimeout: false,
      isNetwork: false,
    );
  }

  @override
  String toString() => debugMessage;
}

// ─────────────────────────────────────────────────────────────────────────────
//  MAIN WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class CheckoutScreen extends ConsumerStatefulWidget {
  final CartItem? item;

  const CheckoutScreen({super.key, this.item});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

// ─────────────────────────────────────────────────────────────────────────────
//  TIP OPTION CARD — premium redesign
// ─────────────────────────────────────────────────────────────────────────────

class _TipOptionCard extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _TipOptionCard({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF7ED) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? primaryOrange : const Color(0xFFE8E8E8),
          width: selected ? 2 : 1,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: primaryOrange.withOpacity(0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: selected ? primaryOrange : textGray900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (label == '\$0')
                      Text(
                        'sin propina',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? primaryOrange.withOpacity(0.7)
                              : textGray600,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: primaryOrange,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  STATE
// ─────────────────────────────────────────────────────────────────────────────

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _unitIdentifierController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _customTipController = TextEditingController();
  final _invoiceBusinessNameController = TextEditingController();
  final _invoiceRutController = TextEditingController();
  final _invoiceGiroController = TextEditingController();
  final _invoiceAddressController = TextEditingController();
  final _invoiceEmailController = TextEditingController();
  final _invoicePhoneController = TextEditingController();
  static const _defaultCountryCode = '+56 ';
  bool _prefilled = false;
  bool _isSubmitting = false;
  bool _isResolvingMapInitialLocation = false;
  bool _deliverToReception = false;
  bool _useAccountAddress = false;
  AddressSlot? _selectedAccountAddressSlot;
  double? _deliveryLatitude;
  double? _deliveryLongitude;
  String? _manualUnitIdentifier;
  String? _manualPostalCode;
  String _selectedDocumentType = 'boleta';

  Timer? _routesDebounce;
  ({Map<String, firestore.GeoPoint> uniquePickups, firestore.GeoPoint delivery})?
      _pendingRoutes;
  String? _pendingRoutesSignature;
  String? _activeRoutesSignature;

  List<CartItem> _getCheckoutItems() {
    final selected = widget.item;
    if (selected != null) return <CartItem>[selected];
    return ref.read(cartProvider);
  }

  void _removeProcessedCartItems(List<CartItem> items) {
    if (items.isEmpty) return;
    final cartNotifier = ref.read(cartProvider.notifier);
    final removedOfferIds = <String>{};

    for (final item in items) {
      final offerId = item.offerId.trim();
      if (offerId.isEmpty) continue;
      if (removedOfferIds.contains(offerId)) continue;
      removedOfferIds.add(offerId);
      cartNotifier.removeItem(item);
    }
  }

  ({firestore.GeoPoint? geo, String address}) _resolvePickupFromCart(
    List<CartItem> cartItems,
  ) {
    final firstWithGeo = cartItems.cast<CartItem?>().firstWhere(
          (it) => _isValidGeo(it?.pickupGeo),
          orElse: () => null,
        );

    final geo = firstWithGeo?.pickupGeo;
    final address =
        (firstWithGeo?.pickupAddressSnapshot ?? '').trim().isNotEmpty
            ? firstWithGeo!.pickupAddressSnapshot!.trim()
            : 'Dirección del vendedor';

    return (geo: geo, address: address);
  }

  Future<void> _createPaymentPreferenceWithBackoff(Order order) async {
    final paymentNotifier = ref.read(paymentNotifierProvider.notifier);

    const delays = <Duration>[
      Duration(milliseconds: 500),
      Duration(milliseconds: 1500),
      Duration(milliseconds: 3000),
    ];

    for (var attempt = 0; attempt < delays.length; attempt++) {
      await paymentNotifier.createPreference(order);
      final paymentState = ref.read(paymentNotifierProvider);

      final errorCode = (paymentState.errorCode ?? '').toLowerCase();
      final raw = paymentState.error ?? '';
      if (errorCode.isEmpty && raw.isEmpty) return;

      final isResourceExhausted = errorCode == 'resource-exhausted';

      if (!isResourceExhausted || attempt == delays.length - 1) {
        return;
      }

      await Future<void>.delayed(delays[attempt]);
    }
  }

  String? _deliveryCountryCode;
  String? _manualAddress;
  double? _manualDeliveryLatitude;
  double? _manualDeliveryLongitude;
  ProviderSubscription<AsyncValue<User?>>? _profileSub;
  PaymentMethod _selectedPaymentMethod = PaymentMethod.mercadopago;

  int _selectedTip = 0;

  String? _lastRoutesSignature;
  bool _isLoadingRoutes = false;
  Object? _routesError;
  _OsrmTrip? _trip;

  Map<String, firestore.GeoPoint>? _lastUniquePickups;
  firestore.GeoPoint? _lastDeliveryGeo;
  String? _lastComputedSignature;

  bool _isValidGeo(firestore.GeoPoint? geo) {
    if (geo == null) return false;
    if (geo.latitude == 0 && geo.longitude == 0) return false;
    return geo.latitude >= -90 &&
        geo.latitude <= 90 &&
        geo.longitude >= -180 &&
        geo.longitude <= 180;
  }

  String _formatRut(String input) {
    final cleaned = input
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('.', '')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll(RegExp(r'[^0-9K-]'), '');

    if (cleaned.isEmpty) return '';

    final withDash = cleaned.contains('-')
        ? cleaned
        : cleaned.length >= 2
            ? '${cleaned.substring(0, cleaned.length - 1)}-${cleaned.substring(cleaned.length - 1)}'
            : cleaned;

    final parts = withDash.split('-');
    if (parts.isEmpty) return withDash;
    final body = parts.first.replaceAll(RegExp(r'\D'), '');
    final dv = parts.length > 1 ? parts[1].toUpperCase() : '';

    final reversed = body.split('').reversed.join();
    final groupedReversed = <String>[];
    for (var i = 0; i < reversed.length; i += 3) {
      groupedReversed.add(
        reversed.substring(
          i,
          (i + 3) > reversed.length ? reversed.length : (i + 3),
        ),
      );
    }
    final grouped = groupedReversed
        .map((e) => e.split('').reversed.join())
        .toList()
        .reversed
        .join('.');

    if (dv.isEmpty) return grouped;
    return '$grouped-$dv';
  }

  @override
  void dispose() {
    _routesDebounce?.cancel();
    _profileSub?.close();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _unitIdentifierController.dispose();
    _postalCodeController.dispose();
    _instructionsController.dispose();
    _customTipController.dispose();
    _invoiceBusinessNameController.dispose();
    _invoiceRutController.dispose();
    _invoiceGiroController.dispose();
    _invoiceAddressController.dispose();
    _invoiceEmailController.dispose();
    _invoicePhoneController.dispose();
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
    void _prefillFromUser(User user) {
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = user.fullName;
      }
      if (_phoneController.text.trim().isEmpty) {
        final phone = user.phoneNumber;
        _phoneController.text = phone.isNotEmpty ? phone : _defaultCountryCode;
      }
      if (_addressController.text.trim().isEmpty && user.address != null) {
        _addressController.text = user.address!.fullAddress;
        if (_unitIdentifierController.text.trim().isEmpty) {
          _unitIdentifierController.text =
              user.address!.unitIdentifier?.trim() ?? '';
        }
        if (_postalCodeController.text.trim().isEmpty) {
          _postalCodeController.text = user.address!.postalCode?.trim() ?? '';
        }
      }

      if (_selectedAccountAddressSlot == null && user.addressSlots.isNotEmpty) {
        _selectedAccountAddressSlot =
            user.primaryAddressSlot ?? user.addressSlots.keys.first;
      }
    }

    if (user != null) {
      _prefillFromUser(user);
    }
    _prefilled = true;
  }

  Address? _resolveSelectedAccountAddress(User user) {
    final selectedSlot = _selectedAccountAddressSlot;
    if (selectedSlot != null) {
      final addr = user.addressSlots[selectedSlot];
      if (addr != null) return addr;
    }
    final primarySlot = user.primaryAddressSlot;
    if (primarySlot != null) {
      final addr = user.addressSlots[primarySlot];
      if (addr != null) return addr;
    }
    if (user.addressSlots.isNotEmpty) return user.addressSlots.values.first;
    return user.address;
  }

  String _formatSavedAddressLabel(Address? addr, {AddressSlot? fallbackSlot}) {
    if (addr == null) return 'No tienes una dirección guardada en tu cuenta.';
    final name = addr.name?.trim();
    if (name != null && name.isNotEmpty) return name;
    if (fallbackSlot != null) return fallbackSlot.displayName;
    return 'Dirección guardada';
  }

  void _setDeliveryFromAccountAddress(User user) {
    final addr = _resolveSelectedAccountAddress(user);
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

    final cartItems = ref.read(cartProvider);

    var deliveryCc =
        (addr.countryCode?.trim().toUpperCase().isNotEmpty ?? false)
            ? addr.countryCode!.trim().toUpperCase()
            : null;
    final pickupCcs = cartItems
        .map((e) => e.pickupCountryCode?.trim().toUpperCase())
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toSet();

    final hasAnyMissingPickupCountry =
        cartItems.any((e) => (e.pickupCountryCode?.trim().isEmpty ?? true));

    if ((deliveryCc == null || deliveryCc.isEmpty) &&
        pickupCcs.length == 1) {
      deliveryCc = pickupCcs.first;
    }

    if (deliveryCc == null || deliveryCc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No se pudo determinar el país de la dirección de entrega.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (hasAnyMissingPickupCountry) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No se pudo determinar el país de una o más ubicaciones de retiro.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (pickupCcs.length != 1 || pickupCcs.first != deliveryCc) {
      debugPrint(
        '🌎 [Checkout] Country mismatch delivery=$deliveryCc pickup=${pickupCcs.join(",")} (missingPickup=$hasAnyMissingPickupCountry)',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se permiten pedidos entre países distintos. Entrega: $deliveryCc | Retiro: ${pickupCcs.join(",")}',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _addressController.text = addr.fullAddress;
      _unitIdentifierController.text = addr.unitIdentifier?.trim() ?? '';
      _postalCodeController.text = addr.postalCode?.trim() ?? '';
      _deliveryLatitude = addr.latitude;
      _deliveryLongitude = addr.longitude;
      _deliveryCountryCode = deliveryCc;
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

    if (mounted) {
      setState(() => _isResolvingMapInitialLocation = true);
    }

    final result = await Navigator.of(context).push<MapLocationResult>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          apiKey: apiKey,
          initialAddress: _addressController.text.trim().isNotEmpty
              ? _addressController.text.trim()
              : null,
          onInitialLocationResolved: () {
            if (mounted) {
              setState(() => _isResolvingMapInitialLocation = false);
            }
          },
        ),
      ),
    );

    if (mounted) {
      setState(() => _isResolvingMapInitialLocation = false);
    }

    if (result != null && mounted) {
      final cc =
          (result.countryCode?.trim().toUpperCase().isNotEmpty ?? false)
              ? result.countryCode!.trim().toUpperCase()
              : null;

      if (cc == null || cc.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No se pudo determinar el país de la ubicación seleccionada.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      setState(() {
        _addressController.text = result.address;
        _unitIdentifierController.text = result.unitIdentifier?.trim() ?? '';
        _postalCodeController.text = result.postalCode?.trim() ?? '';
        _deliveryLatitude = result.latitude;
        _deliveryLongitude = result.longitude;
        _deliveryCountryCode = cc;
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

    final cartItems = _getCheckoutItems();
    final deliveryGeo = ref.read(deliveryGeoProvider);
    final routeDistanceKm = ref.read(routeDistanceKmProvider);
    final inPersonPickupSelected = ref.read(inPersonPickupSelectedProvider);
    final allItemsAllowInPersonPickup =
        cartItems.isNotEmpty && cartItems.every((e) => e.allowInPersonPickup);
    final pricingConfig = ref.read(pricingConfigProvider);
    final summary = computeCartSummary(
      cartItems: cartItems,
      deliveryGeo: deliveryGeo,
      routeDistanceKm: routeDistanceKm,
      inPersonPickupSelected: inPersonPickupSelected,
      allItemsAllowInPersonPickup: allItemsAllowInPersonPickup,
      pricingConfig: pricingConfig,
    );
    final effectiveDistanceKm = computeEffectiveDistanceKm(
      cartItems: cartItems,
      deliveryGeo: deliveryGeo,
      routeDistanceKm: routeDistanceKm,
      inPersonPickupSelected: inPersonPickupSelected,
      allItemsAllowInPersonPickup: allItemsAllowInPersonPickup,
    );
    final user = await ref.read(profileProvider.future);

    if (inPersonPickupSelected &&
        _selectedPaymentMethod == PaymentMethod.cash) {
      setState(() => _selectedPaymentMethod = PaymentMethod.mercadopago);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El pago en efectivo no está disponible para retiro en persona. Se cambió a pago en línea.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes iniciar sesión para continuar'),
          duration: Duration(milliseconds: 2000),
        ),
      );
      return;
    }

    if (user.isSuspended) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tu cuenta está suspendida. No puedes proceder al pago en este momento.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (!inPersonPickupSelected) {
      final deliveryCc = _deliveryCountryCode?.trim().toUpperCase();
      final pickupCcs = cartItems
          .map((e) => e.pickupCountryCode?.trim().toUpperCase())
          .whereType<String>()
          .where((e) => e.isNotEmpty)
          .toSet();
      final hasAnyMissingPickupCountry =
          cartItems.any((e) => (e.pickupCountryCode?.trim().isEmpty ?? true));

      if (deliveryCc == null || deliveryCc.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No se pudo determinar el país de la dirección de entrega.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      if (hasAnyMissingPickupCountry || pickupCcs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No se pudo determinar el país de una o más ubicaciones de retiro.'),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      if (pickupCcs.length != 1 || pickupCcs.first != deliveryCc) {
        debugPrint(
          '🌎 [Checkout] Reject cross-country order: delivery=$deliveryCc pickup=${pickupCcs.join(",")}',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se permiten envíos entre países distintos. Entrega: $deliveryCc | Retiro: ${pickupCcs.join(",")}',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    final totalWeightKg = cartItems.fold<double>(
      0.0,
      (sum, item) => sum + (item.weight * item.quantity),
    );

    if (inPersonPickupSelected && !allItemsAllowInPersonPickup) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Retiro en persona no disponible: uno o más productos no lo permiten.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      ref.read(inPersonPickupSelectedProvider.notifier).state = false;
      return;
    }

    if (inPersonPickupSelected && allItemsAllowInPersonPickup) {
      if (_isSubmitting) return;
      setState(() => _isSubmitting = true);

      try {
        if (_selectedPaymentMethod == PaymentMethod.cash) {
          setState(() => _selectedPaymentMethod = PaymentMethod.mercadopago);
        }

        final delivery = OrderBuilder.createDelivery(
          address: '',
          recipientName: _nameController.text.trim(),
          recipientPhone: _phoneController.text.trim(),
          instructions: '',
          deliverToReception: false,
          geo: const firestore.GeoPoint(0, 0),
        );

        final pickup = _resolvePickupFromCart(cartItems);

        if (!_isValidGeo(pickup.geo)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo determinar la ubicación de retiro. Pide al vendedor actualizar la ubicación de la publicación.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }

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
          tip: 0.0,
          estimatedDistanceKm: 0.0,
          heroId: user.id,
          documentType: _selectedDocumentType,
          invoiceBusinessName: _selectedDocumentType == 'factura'
              ? _invoiceBusinessNameController.text.trim()
              : null,
          invoiceRut: _selectedDocumentType == 'factura'
              ? _invoiceRutController.text.trim()
              : null,
          invoiceGiro: _selectedDocumentType == 'factura'
              ? _invoiceGiroController.text.trim()
              : null,
          invoiceAddress: _selectedDocumentType == 'factura'
              ? _invoiceAddressController.text.trim()
              : null,
          invoiceEmail: _selectedDocumentType == 'factura'
              ? _invoiceEmailController.text.trim()
              : null,
          invoicePhone: _selectedDocumentType == 'factura'
              ? _invoicePhoneController.text.trim()
              : null,
          delivery: delivery,
          status: shouldUseMercadoPago
              ? OrderStatus.pendingPayment
              : OrderStatus.queued,
          pickupAddress: pickup.address,
          pickupGeo: pickup.geo,
          pickupContactName: user.fullName,
          pickupContactPhone: user.phoneNumber,
          pickupSchedule: pickupSchedule,
          useConcierge: useConcierge,
          conciergeInfo: conciergeInfo,
          inPersonPickup: true,
        );

        if (shouldUseMercadoPago) {
          await _createPaymentPreferenceWithBackoff(order);
          final paymentState = ref.read(paymentNotifierProvider);

          if (paymentState.error != null) {
            final errorCode = (paymentState.errorCode ?? '').toLowerCase();
            final raw = paymentState.error ?? '';
            if (errorCode == 'resource-exhausted') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Hay mucha demanda en este momento. Espera 30 segundos y vuelve a intentar.',
                  ),
                  duration: Duration(seconds: 4),
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
          final createdOrder = await createOrderUseCase.execute(
            order,
            currentUser: user,
          );
          _removeProcessedCartItems(cartItems);

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
          final createOrderUseCase = ref.read(createOrderUseCaseProvider);
          final createdOrder = await createOrderUseCase.execute(
            order,
            currentUser: user,
          );
          _removeProcessedCartItems(cartItems);

          if (mounted) {
            await _showPaymentResult(
              success: true,
              message:
                  'Servicio solicitado (HRO-${createdOrder.orderId}). Total: \$${createdOrder.amountTotal.toStringAsFixed(0)} CLP',
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

      return;
    }

    if (effectiveDistanceKm == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo calcular la distancia de la ruta.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    VehicleType requiredVehicle;
    try {
      requiredVehicle = OrderRequirements.calculateRequiredVehicleFor(
        weightKg: totalWeightKg,
        distanceKm: effectiveDistanceKm,
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La distancia excede la cobertura disponible.'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    final maxDistanceKm =
        TransportPricingConfig.getMaxDistance(requiredVehicle);

    if (effectiveDistanceKm > maxDistanceKm) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'La distancia (${effectiveDistanceKm.toStringAsFixed(1)} km) excede el límite permitido (${maxDistanceKm.toStringAsFixed(1)} km).',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      var deliveryGeo =
          _deliveryLatitude != null && _deliveryLongitude != null
              ? firestore.GeoPoint(_deliveryLatitude!, _deliveryLongitude!)
              : null;

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

      var deliveryAddressSnapshot = _addressController.text.trim();
      final unit = _unitIdentifierController.text.trim();
      final postal = _postalCodeController.text.trim();
      final parts = <String>[
        if (deliveryAddressSnapshot.isNotEmpty) deliveryAddressSnapshot,
        if (unit.isNotEmpty) 'Dpto./Casa/Oficina/Condominio: $unit',
        if (postal.isNotEmpty) 'Código Postal: $postal',
      ];
      if (parts.isNotEmpty) {
        deliveryAddressSnapshot = parts.join('\n');
      }

      final delivery = OrderBuilder.createDelivery(
        address: deliveryAddressSnapshot,
        recipientName: _nameController.text.trim(),
        recipientPhone: _phoneController.text.trim(),
        instructions: _instructionsController.text.trim(),
        deliverToReception: _deliverToReception,
        geo: deliveryGeo,
      );

      print(
        '📦 [Checkout] Creating order with delivery geo: ${delivery.geo.latitude}, ${delivery.geo.longitude}',
      );

      final pickup = _resolvePickupFromCart(cartItems);

      if (!_isValidGeo(pickup.geo)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo determinar la ubicación de retiro. Pide al vendedor actualizar la ubicación de la publicación.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

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
        tip: _selectedTip.toDouble(),
        estimatedDistanceKm: effectiveDistanceKm,
        heroId: user.id,
        documentType: _selectedDocumentType,
        invoiceBusinessName: _selectedDocumentType == 'factura'
            ? _invoiceBusinessNameController.text.trim()
            : null,
        invoiceRut: _selectedDocumentType == 'factura'
            ? _invoiceRutController.text.trim()
            : null,
        invoiceGiro: _selectedDocumentType == 'factura'
            ? _invoiceGiroController.text.trim()
            : null,
        invoiceAddress: _selectedDocumentType == 'factura'
            ? _invoiceAddressController.text.trim()
            : null,
        invoiceEmail: _selectedDocumentType == 'factura'
            ? _invoiceEmailController.text.trim()
            : null,
        invoicePhone: _selectedDocumentType == 'factura'
            ? _invoicePhoneController.text.trim()
            : null,
        delivery: delivery,
        status: shouldUseMercadoPago
            ? OrderStatus.pendingPayment
            : OrderStatus.queued,
        pickupAddress: pickup.address,
        pickupGeo: pickup.geo,
        pickupContactName: user.fullName,
        pickupContactPhone: user.phoneNumber,
        pickupSchedule: pickupSchedule,
        useConcierge: useConcierge,
        conciergeInfo: conciergeInfo,
        inPersonPickup: false,
      );

      if (shouldUseMercadoPago) {
        debugPrint('💳 [Checkout] Using MercadoPago payment flow');
        await _createPaymentPreferenceWithBackoff(order);

        final paymentState = ref.read(paymentNotifierProvider);

        if (paymentState.error != null) {
          final errorCode = (paymentState.errorCode ?? '').toLowerCase();
          final raw = paymentState.error ?? '';
          final message = raw.toLowerCase();

          if (errorCode == 'resource-exhausted') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Hay mucha demanda en este momento. Espera 30 segundos y vuelve a intentar.',
                ),
                duration: Duration(seconds: 4),
              ),
            );
            return;
          }

          if (message.contains('stock insuficiente') ||
              message.contains('failed-precondition')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Este servicio ya no está disponible. Intenta con otro.',
                ),
                duration: Duration(seconds: 3),
              ),
            );
            return;
          }

          if (message.contains('unit_price') &&
              message.contains('integer')) {
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
        final createdOrder = await createOrderUseCase.execute(
          order,
          currentUser: user,
        );

        _removeProcessedCartItems(cartItems);

        if (mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => _PremiumAlertDialog(
              icon: Icons.info_outline_rounded,
              iconColor: primaryOrange,
              title: 'Solicitud creada',
              message:
                  'Tu solicitud de servicio ha sido creada y está pendiente de pago. '
                  'Serás redirigido a MercadoPago para completar el pago del servicio. '
                  'Si no completas el pago ahora, podrás hacerlo más tarde desde "Mis pedidos".',
              actionLabel: 'Pagar servicio',
              onAction: () => Navigator.of(context).pop(),
            ),
          );
        }

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
        debugPrint(
          '💵 [Checkout] Skipping MercadoPago (${_selectedPaymentMethod == PaymentMethod.cash ? "Cash payment" : "Sandbox mode"})',
        );

        final createOrderUseCase = ref.read(createOrderUseCaseProvider);
        final createdOrder = await createOrderUseCase.execute(
          order,
          currentUser: user,
        );

        if (_selectedPaymentMethod == PaymentMethod.cash) {
          final paymentRepo = ref.read(paymentRepositoryProvider);
          final cashPayment = domain_payment.Payment(
            id: 'cash-${createdOrder.orderId}',
            orderId: createdOrder.orderId,
            preferenceId: 'cash-${createdOrder.orderId}',
            paymentId: null,
            status: domain_payment.PaymentStatus.pending,
            amount: createdOrder.amountTotal,
            currency: createdOrder.currency,
            paymentMethod: domain_payment.PaymentMethod.cash,
            paymentMethodId: 'cash',
            statusDetail: 'cash_on_delivery',
            createdAt: DateTime.now(),
            approvedAt: null,
            updatedAt: DateTime.now(),
            metadata: const <String, dynamic>{
              'flow': 'cash',
              'note':
                  'Pago en efectivo pendiente. Se confirma en la entrega.',
            },
          );

          await paymentRepo.savePayment(cashPayment);
        }

        _removeProcessedCartItems(cartItems);
        if (mounted) {
          await _showPaymentResult(
            success: true,
            message:
                'Servicio solicitado (HRO-${createdOrder.orderId}). Total: \$${createdOrder.amountTotal.toStringAsFixed(0)} CLP',
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

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PremiumResultDialog(
        success: success,
        message: message,
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  // ─── BUILD ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cartItems = widget.item != null
        ? <CartItem>[widget.item!]
        : ref.watch(cartProvider);
    final deliveryGeo = ref.watch(deliveryGeoProvider);
    final routeDistanceKm = ref.watch(routeDistanceKmProvider);
    final allItemsAllowInPersonPickup =
        cartItems.isNotEmpty && cartItems.every((e) => e.allowInPersonPickup);
    final inPersonPickupSelected = ref.watch(inPersonPickupSelectedProvider);
    final pricingConfig = ref.watch(pricingConfigProvider);

    final summary = computeCartSummary(
      cartItems: cartItems,
      deliveryGeo: deliveryGeo,
      routeDistanceKm: routeDistanceKm,
      inPersonPickupSelected: inPersonPickupSelected,
      allItemsAllowInPersonPickup: allItemsAllowInPersonPickup,
      pricingConfig: pricingConfig,
    );
    final effectiveDistanceKm = computeEffectiveDistanceKm(
      cartItems: cartItems,
      deliveryGeo: deliveryGeo,
      routeDistanceKm: routeDistanceKm,
      inPersonPickupSelected: inPersonPickupSelected,
      allItemsAllowInPersonPickup: allItemsAllowInPersonPickup,
    );
    final profile = ref.watch(profileProvider);
    final user = profile.value;
    final totalItems =
        cartItems.fold<int>(0, (sum, item) => sum + item.quantity);

    if (inPersonPickupSelected && !allItemsAllowInPersonPickup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(inPersonPickupSelectedProvider.notifier).state = false;
      });
    }

    if (inPersonPickupSelected &&
        _selectedPaymentMethod == PaymentMethod.cash) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedPaymentMethod = PaymentMethod.mercadopago);
      });
    }

    final hasValidDelivery = inPersonPickupSelected
        ? true
        : (_deliveryLatitude != null && _deliveryLongitude != null);

    final hasDeliveryGeo = deliveryGeo != null;
    final hasCalculatedShipping = inPersonPickupSelected
        ? true
        : (hasDeliveryGeo && summary.shippingBreakdown != null);

    final deliveryCc = _deliveryCountryCode?.trim().toUpperCase();
    final pickupCcs = cartItems
        .map((e) => e.pickupCountryCode?.trim().toUpperCase())
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toSet();
    final hasAnyMissingPickupCountry =
        cartItems.any((e) => (e.pickupCountryCode?.trim().isEmpty ?? true));
    final sameCountry = deliveryCc != null &&
        deliveryCc.isNotEmpty &&
        !hasAnyMissingPickupCountry &&
        pickupCcs.length == 1 &&
        pickupCcs.first == deliveryCc;

    final totalWeightKg = cartItems.fold<double>(
      0.0,
      (sum, item) => sum + (item.weight * item.quantity),
    );

    VehicleType? requiredVehicle;
    double? maxDistanceKm;
    if (effectiveDistanceKm != null) {
      try {
        requiredVehicle = OrderRequirements.calculateRequiredVehicleFor(
          weightKg: totalWeightKg,
          distanceKm: effectiveDistanceKm,
        );
        maxDistanceKm =
            TransportPricingConfig.getMaxDistance(requiredVehicle);
      } catch (_) {
        requiredVehicle = null;
        maxDistanceKm = null;
      }
    }

    final withinDistanceLimit = inPersonPickupSelected
        ? true
        : (effectiveDistanceKm != null &&
            requiredVehicle != null &&
            maxDistanceKm != null &&
            (effectiveDistanceKm <= maxDistanceKm));

    final canProceed = inPersonPickupSelected
        ? allItemsAllowInPersonPickup
        : (hasValidDelivery &&
            hasCalculatedShipping &&
            withinDistanceLimit &&
            sameCountry);

    final canProceedWithAccount = user != null && !user.isSuspended;

    final effectiveTip = inPersonPickupSelected ? 0 : _selectedTip;
    final totalWithTip = summary.total + effectiveTip.toDouble();

    if (!inPersonPickupSelected) {
      _scheduleRoutesLoad(cartItems: cartItems, deliveryGeo: deliveryGeo);
    }

    return Scaffold(
      backgroundColor: backgroundGray50,
      // ── APPBAR ────────────────────────────────────────────────────────────
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: BoxDecoration(
            color: primaryYellow,
            boxShadow: [
              BoxShadow(
                color: primaryYellow.withOpacity(0.5),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Back button
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 18,
                        color: textGray900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Icon container
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: primaryOrange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.shopping_cart_checkout_rounded,
                      size: 18,
                      color: primaryOrange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Checkout',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                            color: textGray900,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          '$totalItems artículo${totalItems == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: textGray900.withOpacity(0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Total pill
                  if (canProceed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: primaryOrange,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: primaryOrange.withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        '\$${formatPriceCLP(totalWithTip)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      // ── BODY ──────────────────────────────────────────────────────────────
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // ── Route map ─────────────────────────────────────────────────
            if (!inPersonPickupSelected)
              _CheckoutItemsRouteMap(
                cartItems: cartItems,
                deliveryGeo: deliveryGeo,
                isLoading: _isLoadingRoutes,
                error: _routesError,
                trip: _trip,
                onRetry: _retryRoutesIfPossible,
              ),

            if (!inPersonPickupSelected) const SizedBox(height: 16),

            // ── In-person pickup toggle ────────────────────────────────────
            if (allItemsAllowInPersonPickup) ...[
              _SectionCard(
                child: _ToggleRow(
                  value: inPersonPickupSelected,
                  onChanged: _isSubmitting
                      ? null
                      : (val) {
                          if (val) setState(() => _selectedTip = 0);
                          ref
                              .read(inPersonPickupSelectedProvider.notifier)
                              .state = val;
                        },
                  icon: Icons.store_rounded,
                  iconColor: const Color(0xFF16A34A),
                  title: 'Retiro en persona',
                  subtitle:
                      'Sin costo de envío. Solo comisión e impuestos.',
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Delivery address section header ────────────────────────────
            if (!inPersonPickupSelected) ...[
              _SectionLabel(
                icon: Icons.local_shipping_rounded,
                label: 'Dirección de entrega',
              ),
              const SizedBox(height: 12),
            ],

            // ── Contact + address form card ────────────────────────────────
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Account address toggle
                  if (!inPersonPickupSelected) ...[
                    _ToggleRow(
                      value: _useAccountAddress,
                      onChanged: _isSubmitting
                          ? null
                          : (val) {
                              if (val) {
                                _manualAddress = _addressController.text;
                                _manualUnitIdentifier =
                                    _unitIdentifierController.text;
                                _manualPostalCode = _postalCodeController.text;
                                _manualDeliveryLatitude = _deliveryLatitude;
                                _manualDeliveryLongitude = _deliveryLongitude;
                                setState(() => _useAccountAddress = true);
                                if (user != null) {
                                  if (_selectedAccountAddressSlot ==
                                          null &&
                                      user.addressSlots.isNotEmpty) {
                                    _selectedAccountAddressSlot =
                                        user.primaryAddressSlot ??
                                            user.addressSlots.keys.first;
                                  }
                                  _setDeliveryFromAccountAddress(user);
                                } else {
                                  setState(() => _useAccountAddress = false);
                                }
                              } else {
                                setState(() {
                                  _useAccountAddress = false;
                                  _addressController.text =
                                      _manualAddress ?? '';
                                  _unitIdentifierController.text =
                                      _manualUnitIdentifier ?? '';
                                  _postalCodeController.text =
                                      _manualPostalCode ?? '';
                                  _deliveryLatitude =
                                      _manualDeliveryLatitude;
                                  _deliveryLongitude =
                                      _manualDeliveryLongitude;
                                });
                                if (_deliveryLatitude != null &&
                                    _deliveryLongitude != null) {
                                  ref
                                      .read(deliveryGeoProvider.notifier)
                                      .state = firestore.GeoPoint(
                                    _deliveryLatitude!,
                                    _deliveryLongitude!,
                                  );
                                } else {
                                  ref
                                      .read(deliveryGeoProvider.notifier)
                                      .state = null;
                                }
                              }
                            },
                      icon: Icons.bookmark_rounded,
                      iconColor: const Color(0xFF2563EB),
                      title: 'Usar dirección de la cuenta',
                      subtitle: (() {
                        final u = user;
                        if (u == null) {
                          return 'No tienes una dirección guardada en tu cuenta.';
                        }
                        if (_useAccountAddress) {
                          final selected =
                              _resolveSelectedAccountAddress(u);
                          return _formatSavedAddressLabel(
                            selected,
                            fallbackSlot: _selectedAccountAddressSlot,
                          );
                        }
                        if (u.address != null) {
                          return _formatSavedAddressLabel(u.address);
                        }
                        if (u.addressSlots.isNotEmpty) {
                          final firstSlot = u.addressSlots.keys.first;
                          final first = u.addressSlots.values.first;
                          return _formatSavedAddressLabel(
                            first,
                            fallbackSlot: firstSlot,
                          );
                        }
                        return 'No tienes una dirección guardada en tu cuenta.';
                      })(),
                    ),
                    const SizedBox(height: 12),
                    const _Hairline(),
                    const SizedBox(height: 12),
                  ],

                  // Saved address unit type selector
                  if (!inPersonPickupSelected &&
                      _useAccountAddress &&
                      (user?.addressSlots.isNotEmpty ?? false)) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: backgroundGray50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFECECEC),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: primaryOrange.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.home_rounded,
                                  size: 12,
                                  color: primaryOrange,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Elegir dirección guardada',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: textGray900,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: user!.addressSlots.keys.map((t) {
                              final sel = _selectedAccountAddressSlot == t;
                              return GestureDetector(
                                onTap: _isSubmitting
                                    ? null
                                    : () {
                                        setState(() =>
                                            _selectedAccountAddressSlot = t);
                                        _setDeliveryFromAccountAddress(
                                            user);
                                      },
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: sel
                                        ? primaryOrange.withOpacity(0.1)
                                        : Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    border: Border.all(
                                      color: sel
                                          ? primaryOrange
                                          : const Color(0xFFE0E0E0),
                                      width: sel ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    t.displayName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: sel
                                          ? primaryOrange
                                          : textGray900,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 10),
                          Builder(
                            builder: (context) {
                              final selectedAddr =
                                  _resolveSelectedAccountAddress(user);
                              final slot = _selectedAccountAddressSlot ??
                                  user.primaryAddressSlot;
                              final title = _formatSavedAddressLabel(
                                selectedAddr,
                                fallbackSlot: slot,
                              );
                              final fullAddress =
                                  selectedAddr?.fullAddress.trim();
                              final unitLine =
                                  selectedAddr?.unitDisplayLine?.trim();
                              if (title.trim().isEmpty &&
                                  (fullAddress == null ||
                                      fullAddress.isEmpty) &&
                                  (unitLine == null || unitLine.isEmpty)) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2563EB)
                                            .withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.location_on_rounded,
                                        size: 16,
                                        color: Color(0xFF2563EB),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: textGray900,
                                              fontSize: 13,
                                              height: 1.15,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.2,
                                            ),
                                          ),
                                          if (fullAddress != null &&
                                              fullAddress.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              fullAddress,
                                              style: const TextStyle(
                                                color: textGray600,
                                                fontSize: 12,
                                                height: 1.3,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                          if (unitLine != null &&
                                              unitLine.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: backgroundGray50,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: const Color(0xFFECECEC),
                                                ),
                                              ),
                                              child: Text(
                                                unitLine,
                                                style: const TextStyle(
                                                  color: textGray900,
                                                  fontSize: 12,
                                                  height: 1.2,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const _Hairline(),
                    const SizedBox(height: 14),
                  ],

                  // Name field
                  _StyledField(
                    controller: _nameController,
                    label: 'Nombre completo',
                    icon: Icons.person_rounded,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Ingresa tu nombre'
                            : null,
                  ),
                  const SizedBox(height: 12),
                  // Phone field
                  _StyledField(
                    controller: _phoneController,
                    label: 'Teléfono',
                    hint: 'Incluye código país',
                    icon: Icons.phone_rounded,
                    keyboardType: TextInputType.phone,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty)
                            ? 'Ingresa tu teléfono'
                            : null,
                  ),

                  // Delivery fields
                  if (!inPersonPickupSelected) ...[
                    const SizedBox(height: 12),
                    // Address field (read-only → opens map)
                    _StyledField(
                      controller: _addressController,
                      label: 'Dirección de entrega',
                      hint: 'Elige en el mapa',
                      icon: Icons.location_on_rounded,
                      readOnly: true,
                      maxLines: 2,
                      onTap: _useAccountAddress ||
                              _isSubmitting ||
                              _isResolvingMapInitialLocation
                          ? null
                          : _openMapPicker,
                      suffix: GestureDetector(
                        onTap: _useAccountAddress ||
                                _isSubmitting ||
                                _isResolvingMapInitialLocation
                            ? null
                            : _openMapPicker,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: primaryOrange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: _isResolvingMapInitialLocation
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation(primaryOrange),
                                  ),
                                )
                              : const Icon(
                                  Icons.map_rounded,
                                  size: 18,
                                  color: primaryOrange,
                                ),
                        ),
                      ),
                      validator: (v) {
                        final hasGeo = _deliveryLatitude != null &&
                            _deliveryLongitude != null;
                        if (!hasGeo) {
                          return 'Selecciona tu dirección en el mapa';
                        }
                        if (v == null || v.trim().isEmpty) {
                          return 'Selecciona tu dirección en el mapa';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _StyledField(
                      controller: _unitIdentifierController,
                      label: 'Dpto./Casa/Oficina/Condominio',
                      hint: 'Ej: Dpto 1204, Casa 3',
                      icon: Icons.door_front_door_outlined,
                      keyboardType: TextInputType.text,
                      validator: (v) {
                        if (inPersonPickupSelected) return null;
                        if (v == null || v.trim().isEmpty) {
                          return 'Requerido';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _StyledField(
                      controller: _postalCodeController,
                      label: 'Código Postal',
                      hint: 'Opcional',
                      icon: Icons.local_post_office_outlined,
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 8),
                    // Map button
                    GestureDetector(
                      onTap: _useAccountAddress ||
                              _isSubmitting ||
                              _isResolvingMapInitialLocation
                          ? null
                          : _openMapPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: primaryOrange.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: primaryOrange.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isResolvingMapInitialLocation) ...[
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation(primaryOrange),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ] else ...[
                              const Icon(Icons.place_rounded,
                                  size: 16, color: primaryOrange),
                              const SizedBox(width: 8),
                            ],
                            const Text(
                              'Elegir dirección con Google Maps',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: primaryOrange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Instructions field
                    _StyledField(
                      controller: _instructionsController,
                      label: 'Instrucciones (opcional)',
                      hint: 'Ej: Tocar el timbre 2 veces',
                      icon: Icons.notes_rounded,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    const _Hairline(),
                    const SizedBox(height: 4),
                    // Deliver to reception
                    _ToggleRow(
                      value: _deliverToReception,
                      onChanged: _isSubmitting
                          ? null
                          : (val) =>
                              setState(() => _deliverToReception = val),
                      icon: Icons.apartment_rounded,
                      iconColor: const Color(0xFF7C3AED),
                      title: 'Recibir en portería',
                      subtitle:
                          'El repartidor entregará en recepción/portería.',
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Document type selector ────────────────────────────────────────
            _SectionLabel(
              icon: Icons.description_rounded,
              label: 'Tipo de documento',
            ),
            const SizedBox(height: 12),
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _isSubmitting
                              ? null
                              : () => setState(
                                    () => _selectedDocumentType = 'boleta',
                                  ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: _selectedDocumentType == 'boleta'
                                  ? const Color(0xFFFFF7ED)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _selectedDocumentType == 'boleta'
                                    ? primaryOrange
                                    : const Color(0xFFE8E8E8),
                                width: _selectedDocumentType == 'boleta'
                                    ? 2
                                    : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: primaryOrange.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.receipt_rounded,
                                    size: 18,
                                    color: primaryOrange,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Boleta',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      color: textGray900,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                if (_selectedDocumentType == 'boleta')
                                  Container(
                                    width: 18,
                                    height: 18,
                                    decoration: const BoxDecoration(
                                      color: primaryOrange,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _isSubmitting
                              ? null
                              : () => setState(
                                    () => _selectedDocumentType = 'factura',
                                  ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: _selectedDocumentType == 'factura'
                                  ? const Color(0xFFFFF7ED)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _selectedDocumentType == 'factura'
                                    ? primaryOrange
                                    : const Color(0xFFE8E8E8),
                                width: _selectedDocumentType == 'factura'
                                    ? 2
                                    : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: primaryOrange.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.description_outlined,
                                    size: 18,
                                    color: primaryOrange,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Factura',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      color: textGray900,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                if (_selectedDocumentType == 'factura')
                                  Container(
                                    width: 18,
                                    height: 18,
                                    decoration: const BoxDecoration(
                                      color: primaryOrange,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedDocumentType == 'factura') ...[
                    const SizedBox(height: 14),
                    const _Hairline(),
                    const SizedBox(height: 14),
                    _StyledField(
                      controller: _invoiceBusinessNameController,
                      label: 'Razón social',
                      icon: Icons.business_rounded,
                      validator: (v) {
                        if (_selectedDocumentType != 'factura') return null;
                        return (v == null || v.trim().isEmpty)
                            ? 'Ingresa la razón social'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _StyledField(
                      controller: _invoiceRutController,
                      label: 'RUT',
                      hint: 'Ej: 19.123.456-K',
                      icon: Icons.badge_rounded,
                      keyboardType: TextInputType.text,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9kK\.\-]'),
                        ),
                      ],
                      onChanged: (value) {
                        if (_selectedDocumentType != 'factura') return;
                        final formatted = _formatRut(value);
                        if (formatted == value) return;
                        _invoiceRutController.value = TextEditingValue(
                          text: formatted,
                          selection: TextSelection.collapsed(
                            offset: formatted.length,
                          ),
                        );
                      },
                      validator: (v) {
                        if (_selectedDocumentType != 'factura') return null;
                        return Validators.rut(v);
                      },
                    ),
                    const SizedBox(height: 12),
                    _StyledField(
                      controller: _invoiceGiroController,
                      label: 'Giro',
                      icon: Icons.work_rounded,
                      validator: (v) {
                        if (_selectedDocumentType != 'factura') return null;
                        return (v == null || v.trim().isEmpty)
                            ? 'Ingresa el giro'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _StyledField(
                      controller: _invoiceAddressController,
                      label: 'Dirección',
                      icon: Icons.location_city_rounded,
                      maxLines: 2,
                      validator: (v) {
                        if (_selectedDocumentType != 'factura') return null;
                        return (v == null || v.trim().isEmpty)
                            ? 'Ingresa la dirección'
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _StyledField(
                      controller: _invoiceEmailController,
                      label: 'Correo (opcional)',
                      icon: Icons.email_rounded,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (_selectedDocumentType != 'factura') return null;
                        final value = v?.trim() ?? '';
                        if (value.isEmpty) return null;
                        return Validators.email(value);
                      },
                    ),
                    const SizedBox(height: 12),
                    _StyledField(
                      controller: _invoicePhoneController,
                      label: 'Teléfono (opcional)',
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                      validator: (v) {
                        if (_selectedDocumentType != 'factura') return null;
                        return null;
                      },
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Tip section ───────────────────────────────────────────────
            if (!inPersonPickupSelected) ...[
              _SectionLabel(
                icon: Icons.favorite_rounded,
                label: 'Propina para el rider',
              ),
              const SizedBox(height: 12),
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '100% para el rider',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF065F46),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.3,
                      children: [
                        _TipOptionCard(
                          label: '\$0',
                          selected: _selectedTip == 0,
                          onTap: _isSubmitting
                              ? null
                              : () => setState(() => _selectedTip = 0),
                        ),
                        _TipOptionCard(
                          label: '\$500',
                          selected: _selectedTip == 500,
                          onTap: _isSubmitting
                              ? null
                              : () => setState(() => _selectedTip = 500),
                        ),
                        _TipOptionCard(
                          label: '\$1.000',
                          selected: _selectedTip == 1000,
                          onTap: _isSubmitting
                              ? null
                              : () => setState(() => _selectedTip = 1000),
                        ),
                        _TipOptionCard(
                          label: '\$1.500',
                          selected: _selectedTip == 1500,
                          onTap: _isSubmitting
                              ? null
                              : () => setState(() => _selectedTip = 1500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _isSubmitting
                          ? null
                          : () async {
                              final value =
                                  await _askForCustomTip(context);
                              if (!mounted || value == null) return;
                              setState(() => _selectedTip = value);
                            },
                      child: Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFE8E8E8),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_rounded,
                                size: 14, color: textGray600),
                            SizedBox(width: 6),
                            Text(
                              'Otro monto',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: textGray700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Order summary ──────────────────────────────────────────────
            _SectionLabel(
              icon: Icons.receipt_long_rounded,
              label: 'Resumen del pedido',
            ),
            const SizedBox(height: 12),
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Warning banner
                  if (!canProceed) ...[
                    _WarningBanner(
                      message: () {
                        if (!hasValidDelivery) {
                          return 'Selecciona una ubicación en el mapa para calcular el envío y el total.';
                        }
                        if (effectiveDistanceKm == null) {
                          return 'No se pudo calcular la distancia de la ruta. Intenta seleccionar la ubicación nuevamente.';
                        }
                        if (!sameCountry) {
                          if (deliveryCc == null ||
                              deliveryCc.isEmpty) {
                            return 'No se pudo determinar el país de la dirección de entrega. Selecciona la dirección con el mapa.';
                          }
                          if (hasAnyMissingPickupCountry) {
                            return 'Uno o más productos no tienen país de retiro configurado. Pide al vendedor actualizar la publicación.';
                          }
                          return 'No se permiten pedidos entre países distintos. Cambia la dirección de entrega o los productos.';
                        }
                        if (requiredVehicle == null ||
                            maxDistanceKm == null) {
                          return 'Fuera de cobertura: la distancia excede la cobertura disponible.';
                        }
                        if (effectiveDistanceKm > maxDistanceKm) {
                          return 'Fuera de cobertura: la distancia (${effectiveDistanceKm.toStringAsFixed(1)} km) excede el límite (${maxDistanceKm.toStringAsFixed(1)} km).';
                        }
                        return 'Completa los datos requeridos para continuar.';
                      }(),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Items count + weight
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color:
                                  primaryOrange.withOpacity(0.1),
                              borderRadius:
                                  BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.shopping_bag_rounded,
                              size: 14,
                              color: primaryOrange,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$totalItems artículo${totalItems == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: textGray700,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: backgroundGray50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFE8E8E8),
                          ),
                        ),
                        child: Text(
                          formatWeightKg(summary.totalWeight),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textGray700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  const _Hairline(),
                  const SizedBox(height: 14),

                  // Summary rows
                  _SummaryRow(
                    label: 'Subtotal (Donación)',
                    value: '\$${formatPriceCLP(summary.subtotal)}',
                  ),
                  const SizedBox(height: 8),
                  _SummaryRow(
                    label: 'Envío',
                    value: canProceed
                        ? '\$${formatPriceCLP(summary.shippingCost)}'
                        : '—',
                    sub: summary.shippingBreakdown,
                  ),
                  const SizedBox(height: 8),
                  _SummaryRow(
                    label: 'Comisión de servicio',
                    value: canProceed
                        ? '\$${formatPriceCLP(summary.serviceFee)}'
                        : '—',
                  ),
                  const SizedBox(height: 8),
                  _SummaryRow(
                    label: 'Impuestos (IVA ${(pricingConfig.taxPercentage * 100).toStringAsFixed(0)}%)',
                    value: canProceed
                        ? '\$${formatPriceCLP(summary.tax)}'
                        : '—',
                  ),
                  if (!inPersonPickupSelected) ...[
                    const SizedBox(height: 8),
                    _SummaryRow(
                      label: 'Propina',
                      value: canProceed
                          ? '\$${formatPriceCLP(_selectedTip.toDouble())}'
                          : '—',
                    ),
                  ],

                  const SizedBox(height: 14),
                  const _Hairline(),
                  const SizedBox(height: 14),

                  // Total row
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: canProceed
                          ? const Color(0xFFFFF7ED)
                          : backgroundGray50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: canProceed
                            ? primaryOrange.withOpacity(0.3)
                            : const Color(0xFFE8E8E8),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: textGray900,
                          ),
                        ),
                        Text(
                          canProceed
                              ? '\$${formatPriceCLP(totalWithTip)} CLP'
                              : '—',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: canProceed
                                ? primaryOrange
                                : textGray600,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Payment method ─────────────────────────────────────────────
            _SectionLabel(
              icon: Icons.credit_card_rounded,
              label: 'Método de pago',
            ),
            const SizedBox(height: 12),
            _SectionCard(
              padding: EdgeInsets.zero,
              child: PaymentMethodSelector(
                selectedMethod: _selectedPaymentMethod,
                cashEnabled: !inPersonPickupSelected,
                onMethodChanged: (method) {
                  setState(() => _selectedPaymentMethod = method);
                },
              ),
            ),

            const SizedBox(height: 24),

            // ── CTA button ─────────────────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: (canProceed && !_isSubmitting)
                    ? [
                        BoxShadow(
                          color: primaryOrange.withOpacity(0.4),
                          blurRadius: 18,
                          offset: const Offset(0, 7),
                        ),
                      ]
                    : [],
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed:
                      _isSubmitting || !canProceed || !canProceedWithAccount
                          ? null
                          : _proceedToPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canProceed
                        ? primaryOrange
                        : const Color(0xFFD1D5DB),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFD1D5DB),
                    disabledForegroundColor: Colors.white54,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white),
                          ),
                        )
                      : Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.lock_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Proceder al pago',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: 0.2,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),

            if (!MercadoPagoConfig.isProduction) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFFDE68A),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 14, color: Color(0xFFB45309)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Modo Sandbox: MercadoPago deshabilitado',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<int?> _askForCustomTip(BuildContext context) async {
    _customTipController.text =
        _selectedTip > 0 ? _selectedTip.toString() : '';

    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Propina personalizada',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: _customTipController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Monto (CLP)',
            prefixText: '\$ ',
            filled: true,
            fillColor: backgroundGray50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar',
                style: TextStyle(color: textGray600)),
          ),
          TextButton(
            onPressed: () {
              final raw =
                  _customTipController.text.trim();
              final sanitized =
                  raw.replaceAll('.', '').replaceAll(',', '');
              final parsed = int.tryParse(sanitized);
              if (parsed == null || parsed < 0) {
                Navigator.of(ctx).pop();
                return;
              }
              Navigator.of(ctx).pop(parsed);
            },
            child: const Text(
              'Guardar',
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: primaryOrange),
            ),
          ),
        ],
      ),
    );

    return res;
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
      final key =
          '${geo.latitude.toStringAsFixed(6)},${geo.longitude.toStringAsFixed(6)}';
      uniquePickups[key] = geo;
    }

    final signature = [
      '${delivery!.latitude.toStringAsFixed(6)},${delivery.longitude.toStringAsFixed(6)}',
      ...uniquePickups.keys.toList()..sort(),
    ].join('|');

    _lastUniquePickups = uniquePickups;
    _lastDeliveryGeo = delivery;
    _lastComputedSignature = signature;

    if (signature == _lastRoutesSignature) return;
    _lastRoutesSignature = signature;

    _routesDebounce?.cancel();
    _routesDebounce =
        Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;

      if (_isLoadingRoutes) {
        _pendingRoutes =
            (uniquePickups: uniquePickups, delivery: delivery);
        _pendingRoutesSignature = signature;
        return;
      }

      _loadRoutes(
        uniquePickups: uniquePickups,
        delivery: delivery,
        signature: signature,
      );
    });
  }

  Future<void> _loadRoutes({
    required Map<String, firestore.GeoPoint> uniquePickups,
    required firestore.GeoPoint delivery,
    required String signature,
  }) async {
    if (_isLoadingRoutes) return;

    _activeRoutesSignature = signature;

    setState(() {
      _isLoadingRoutes = true;
      _routesError = null;
    });

    ref.read(routeDistanceKmProvider.notifier).state = null;

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
      if (e is _RouteCalculationException) {
        debugPrint(
            '🧭 [Checkout] Route calculation failed: ${e.debugMessage}');
      } else {
        debugPrint('🧭 [Checkout] Route calculation failed: $e');
      }
      setState(() => _routesError = e);
      ref.read(routeDistanceKmProvider.notifier).state = null;
    } finally {
      if (mounted) {
        setState(() => _isLoadingRoutes = false);

        final pending = _pendingRoutes;
        final pendingSig = _pendingRoutesSignature;
        _pendingRoutes = null;
        _pendingRoutesSignature = null;

        final activeSig = _activeRoutesSignature;
        _activeRoutesSignature = null;

        if (pending != null &&
            pendingSig != null &&
            pendingSig != activeSig) {
          _loadRoutes(
            uniquePickups: pending.uniquePickups,
            delivery: pending.delivery,
            signature: pendingSig,
          );
        }
      }
    }
  }

  Future<_OsrmTrip> _fetchOsrmTrip({
    required Map<String, firestore.GeoPoint> pickupKeysToGeo,
    required LatLng delivery,
  }) async {
    final apiKey = Env.placesApiKey;
    if (apiKey.trim().isEmpty) {
      throw _RouteCalculationException.service(
          'Missing PLACES_API_KEY');
    }

    final pickupKeys = pickupKeysToGeo.keys.toList()..sort();
    if (pickupKeys.isEmpty) {
      throw _RouteCalculationException.noRoute('No pickup keys');
    }

    final originGeo = pickupKeysToGeo[pickupKeys.first]!;
    final origin =
        '${originGeo.latitude},${originGeo.longitude}';
    final destination =
        '${delivery.latitude},${delivery.longitude}';

    final intermediateKeys = pickupKeys.length > 1
        ? pickupKeys.sublist(1)
        : const <String>[];

    final waypointsParam = <String>[
      if (intermediateKeys.isNotEmpty) 'optimize:true',
      for (final key in intermediateKeys)
        '${pickupKeysToGeo[key]!.latitude},${pickupKeysToGeo[key]!.longitude}',
    ].join('|');

    final url = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      <String, String>{
        'origin': origin,
        'destination': destination,
        if (intermediateKeys.isNotEmpty) 'waypoints': waypointsParam,
        'mode': 'driving',
        'key': apiKey,
      },
    );

    Future<http.Response> getRequest() {
      return http.get(url).timeout(const Duration(seconds: 15));
    }

    http.Response res;
    try {
      res = await getRequest();
    } on TimeoutException {
      try {
        res = await getRequest();
      } on TimeoutException catch (e) {
        throw _RouteCalculationException.timeout(e.toString());
      } on http.ClientException catch (e) {
        throw _RouteCalculationException.network(e.toString());
      } on PlatformException catch (e) {
        throw _RouteCalculationException.network(e.toString());
      } catch (e) {
        throw _RouteCalculationException.service(e.toString());
      }
    } on http.ClientException catch (e) {
      throw _RouteCalculationException.network(e.toString());
    } on PlatformException catch (e) {
      throw _RouteCalculationException.network(e.toString());
    } catch (e) {
      throw _RouteCalculationException.service(e.toString());
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _RouteCalculationException.service(
        'Directions statusCode=${res.statusCode}',
      );
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final status = (json['status'] as String?) ?? '';
    if (status != 'OK') {
      if (status == 'ZERO_RESULTS') {
        throw _RouteCalculationException.noRoute(
            'Directions status=ZERO_RESULTS');
      }
      throw _RouteCalculationException.service(
          'Directions status=$status');
    }

    final routes =
        (json['routes'] as List?)?.cast<Map<String, dynamic>>();
    if (routes == null || routes.isEmpty) {
      throw _RouteCalculationException.noRoute(
          'Directions: no routes');
    }

    final firstRoute = routes.first;
    final legsJson =
        (firstRoute['legs'] as List?)?.cast<Map<String, dynamic>>();
    if (legsJson == null || legsJson.isEmpty) {
      throw _RouteCalculationException.noRoute(
          'Directions: no legs');
    }

    var distanceMeters = 0.0;
    var durationSeconds = 0.0;
    final legs = <_OsrmLeg>[];
    for (final leg in legsJson) {
      final dist =
          (leg['distance'] as Map?)?['value'] as num?;
      final dur =
          (leg['duration'] as Map?)?['value'] as num?;
      final d = dist?.toDouble() ?? 0.0;
      final s = dur?.toDouble() ?? 0.0;
      distanceMeters += d;
      durationSeconds += s;
      legs.add(_OsrmLeg(distanceMeters: d, durationSeconds: s));
    }

    final polyStr =
        (firstRoute['overview_polyline'] as Map?)?['points']
            as String?;
    if (polyStr == null || polyStr.trim().isEmpty) {
      throw _RouteCalculationException.noRoute(
          'Directions: missing polyline');
    }

    final polylinePoints = _decodePolyline(polyStr);
    if (polylinePoints.isEmpty) {
      throw _RouteCalculationException.noRoute(
          'Directions: empty polyline');
    }

    final waypointOrder =
        (firstRoute['waypoint_order'] as List?)
                ?.cast<num>()
                .map((e) => e.toInt())
                .toList() ??
            const <int>[];

    final orderedPickupKeys = <String>[pickupKeys.first];
    if (intermediateKeys.isNotEmpty) {
      if (waypointOrder.length == intermediateKeys.length) {
        for (final idx in waypointOrder) {
          if (idx >= 0 && idx < intermediateKeys.length) {
            orderedPickupKeys.add(intermediateKeys[idx]);
          }
        }
      } else {
        orderedPickupKeys.addAll(intermediateKeys);
      }
    }

    return _OsrmTrip(
      points: polylinePoints,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      orderedPickupKeys: orderedPickupKeys,
      legs: legs,
    );
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      var result = 0;
      var shift = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat =
          (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      result = 0;
      shift = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng =
          (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  void _retryRoutesIfPossible() {
    final uniquePickups = _lastUniquePickups;
    final delivery = _lastDeliveryGeo;
    final signature = _lastComputedSignature;
    if (uniquePickups == null ||
        delivery == null ||
        signature == null) return;
    if (_isLoadingRoutes) return;

    _lastRoutesSignature = null;
    _loadRoutes(
      uniquePickups: uniquePickups,
      delivery: delivery,
      signature: signature,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED DESIGN PRIMITIVES
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: primaryOrange,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: primaryOrange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: primaryOrange),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 15,
            color: textGray900,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const _SectionCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECECEC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: const Color(0xFFF2F2F2),
    );
  }
}

/// Styled input field matching the design system
class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final bool readOnly;
  final int? maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final VoidCallback? onTap;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;

  const _StyledField({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.readOnly = false,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    this.onTap,
    this.suffix,
    this.onChanged,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onTap: onTap,
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        prefixIcon: Container(
          margin: const EdgeInsets.all(10),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: primaryOrange.withOpacity(0.09),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 15, color: primaryOrange),
        ),
        suffixIcon: suffix != null
            ? Padding(
                padding: const EdgeInsets.only(right: 8),
                child: suffix,
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide:
              const BorderSide(color: primaryOrange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide:
              const BorderSide(color: Color(0xFFDC2626), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide:
              const BorderSide(color: Color(0xFFDC2626), width: 1.5),
        ),
        labelStyle: const TextStyle(
          color: textGray600,
          fontWeight: FontWeight.w600,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

/// Toggle row (replaces SwitchListTile)
class _ToggleRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _ToggleRow({
    required this.value,
    required this.onChanged,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: textGray900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: textGray600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: primaryOrange,
          activeTrackColor: primaryOrange.withOpacity(0.2),
        ),
      ],
    );
  }
}

/// Warning banner
class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFFEA580C).withOpacity(0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.info_rounded,
              size: 13,
              color: Color(0xFFEA580C),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9A3412),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Summary row
class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: textGray700,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textGray900,
              ),
            ),
          ],
        ),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              sub!,
              style: const TextStyle(
                fontSize: 11,
                color: textGray600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PREMIUM DIALOGS
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumAlertDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _PremiumAlertDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: textGray900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: textGray700,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryOrange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumResultDialog extends StatelessWidget {
  final bool success;
  final String? message;
  final VoidCallback onClose;

  const _PremiumResultDialog({
    required this.success,
    this.message,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final color = success
        ? const Color(0xFF10B981)
        : const Color(0xFFDC2626);
    final icon = success
        ? Icons.check_circle_rounded
        : Icons.error_rounded;
    final title = success ? 'Solicitud enviada' : 'Pago fallido';

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child:
                      Opacity(opacity: value.clamp(0, 1), child: child),
                );
              },
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 36),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: textGray900,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: const TextStyle(
                    fontSize: 13, color: textGray700, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  success ? 'Continuar' : 'Entendido',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ROUTE MAP (unchanged logic, refined visuals)
// ─────────────────────────────────────────────────────────────────────────────

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
  final VoidCallback? onRetry;

  const _CheckoutItemsRouteMap({
    required this.cartItems,
    required this.deliveryGeo,
    required this.isLoading,
    required this.error,
    required this.trip,
    required this.onRetry,
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
    return '$min min';
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
      final key =
          '${geo.latitude.toStringAsFixed(6)},${geo.longitude.toStringAsFixed(6)}';
      uniquePickups[key] = geo;
    }

    final hasPickups = uniquePickups.isNotEmpty;
    final canShowMap = hasDelivery && hasPickups;

    if (!canShowMap) return const SizedBox.shrink();

    final deliveryLatLng =
        gmap.LatLng(delivery!.latitude, delivery.longitude);

    final pickupEntries = uniquePickups.entries.toList();
    pickupEntries.sort((a, b) => a.key.compareTo(b.key));

    final orderedKeys = trip?.orderedPickupKeys ?? <String>[];

    String keyForGeo(firestore.GeoPoint geo) {
      return '${geo.latitude.toStringAsFixed(6)},${geo.longitude.toStringAsFixed(6)}';
    }

    final itemsByPickupKey = <String, List<CartItem>>{};
    for (final item in cartItems) {
      final geo = item.pickupGeo;
      if (!_isValidGeo(geo)) continue;
      final key = keyForGeo(geo!);
      (itemsByPickupKey[key] ??= <CartItem>[]).add(item);
    }

    final colors = <Color>[
      const Color(0xFF2563EB),
      const Color(0xFF16A34A),
      const Color(0xFFDC2626),
      const Color(0xFF7C3AED),
    ];

    final polylines = <gmap.Polyline>{
      if (trip != null)
        gmap.Polyline(
          polylineId: const gmap.PolylineId('checkout_route'),
          points: trip!.points
              .map((p) => gmap.LatLng(p.latitude, p.longitude))
              .toList(growable: false),
          width: 5,
          color:
              const Color(0xFF0F172A).withValues(alpha: 0.85),
          geodesic: true,
          zIndex: 5,
        ),
    };

    final markers = <gmap.Marker>{
      for (var i = 0; i < orderedKeys.length; i++)
        if (uniquePickups[orderedKeys[i]] != null)
          gmap.Marker(
            markerId: gmap.MarkerId('pickup_${i + 1}'),
            position: gmap.LatLng(
              uniquePickups[orderedKeys[i]]!.latitude,
              uniquePickups[orderedKeys[i]]!.longitude,
            ),
            icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
              <double>[
                gmap.BitmapDescriptor.hueAzure,
                gmap.BitmapDescriptor.hueGreen,
                gmap.BitmapDescriptor.hueRed,
                gmap.BitmapDescriptor.hueViolet,
              ][i % 4],
            ),
            infoWindow: gmap.InfoWindow(
              title: 'Retiro ${i + 1}',
              snippet:
                  '${itemsByPickupKey[orderedKeys[i]]?.length ?? 0} item(s)',
            ),
          ),
      gmap.Marker(
        markerId: const gmap.MarkerId('delivery'),
        position: deliveryLatLng,
        icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
          gmap.BitmapDescriptor.hueOrange,
        ),
        infoWindow: const gmap.InfoWindow(title: 'Entrega'),
      ),
    };

    gmap.LatLngBounds boundsFromPoints(
        List<gmap.LatLng> points) {
      var minLat = points.first.latitude;
      var maxLat = points.first.latitude;
      var minLng = points.first.longitude;
      var maxLng = points.first.longitude;
      for (final p in points.skip(1)) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      return gmap.LatLngBounds(
        southwest: gmap.LatLng(minLat, minLng),
        northeast: gmap.LatLng(maxLat, maxLng),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFECECEC)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: primaryOrange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.map_rounded,
                      size: 14, color: primaryOrange),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Ruta de entrega',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: textGray900,
                    ),
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryOrange,
                    ),
                  ),
              ],
            ),
          ),
          ClipRRect(
            borderRadius:
                const BorderRadius.all(Radius.zero),
            child: SizedBox(
              height: 220,
              child: gmap.GoogleMap(
                initialCameraPosition: gmap.CameraPosition(
                  target: deliveryLatLng,
                  zoom: 12,
                ),
                markers: markers,
                polylines: polylines,
                gestureRecognizers: <Factory<
                    OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
                zoomGesturesEnabled: true,
                scrollGesturesEnabled: true,
                rotateGesturesEnabled: true,
                tiltGesturesEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                liteModeEnabled: Env.mapsLiteMode,
                onMapCreated: (controller) {
                  final boundsPoints = <gmap.LatLng>[
                    deliveryLatLng,
                    for (final geo
                        in uniquePickups.values)
                      gmap.LatLng(
                          geo.latitude, geo.longitude),
                    if (trip != null)
                      ...trip!.points.map((p) =>
                          gmap.LatLng(
                              p.latitude, p.longitude)),
                  ];
                  if (boundsPoints.length < 2) return;
                  final b = boundsFromPoints(boundsPoints);
                  unawaited(() async {
                    final moved = await animateCameraWhenMapReady(
                      controller: controller,
                      cameraUpdateBuilder: () =>
                          gmap.CameraUpdate.newLatLngBounds(b, 42),
                    );
                    if (!moved) {
                      debugPrint('[Checkout] Could not fit map bounds');
                    }
                  }());
                },
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626)
                              .withOpacity(0.1),
                          borderRadius:
                              BorderRadius.circular(7),
                        ),
                        child: const Icon(
                          Icons.error_rounded,
                          size: 13,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          () {
                            final err = error;
                            if (err
                                is _RouteCalculationException) {
                              return err.userMessage;
                            }
                            return 'No se pudo calcular la ruta. Reintenta.';
                          }(),
                          style: const TextStyle(
                            color: Color(0xFF991B1B),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: isLoading ? null : onRetry,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: backgroundGray50,
                        borderRadius:
                            BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFE0E0E0),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded,
                              size: 14, color: textGray700),
                          SizedBox(width: 6),
                          Text(
                            'Reintentar',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: textGray700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (trip != null)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  // Total route summary
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: backgroundGray50,
                      borderRadius:
                          BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFE8E8E8),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: primaryOrange
                                .withOpacity(0.1),
                            borderRadius:
                                BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.route_rounded,
                            size: 13,
                            color: primaryOrange,
                          ),
                        ),
                        const SizedBox(width: 10),
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
                          padding:
                              const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.circular(20),
                            border: Border.all(
                              color:
                                  const Color(0xFFE0E0E0),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                  Icons.schedule_rounded,
                                  size: 11,
                                  color: textGray600),
                              const SizedBox(width: 4),
                              Text(
                                _formatMin(
                                    trip!.durationSeconds),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: textGray900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var stopIndex = 0;
                      stopIndex < orderedKeys.length;
                      stopIndex++) ...[
                    _RouteStopCard(
                      index: stopIndex + 1,
                      color: colors[stopIndex % colors.length],
                      title: 'Punto ${stopIndex + 1}',
                      subtitle: () {
                        final items = itemsByPickupKey[
                                orderedKeys[stopIndex]] ??
                            const <CartItem>[];
                        final qty = items.fold<int>(
                            0, (sum, e) => sum + e.quantity);
                        final names = items
                            .map((e) => e.name)
                            .where(
                                (e) => e.trim().isNotEmpty)
                            .toList();
                        final firstTwo =
                            names.take(2).join(' · ');
                        if (firstTwo.isEmpty) {
                          return '$qty artículo${qty == 1 ? '' : 's'}';
                        }
                        return '$qty artículo${qty == 1 ? '' : 's'} · $firstTwo${names.length > 2 ? '…' : ''}';
                      }(),
                      trailing: stopIndex <
                              trip!.legs.length
                          ? _LegChips(
                              leg: trip!.legs[stopIndex],
                              formatKm: _formatKm,
                              formatMin: _formatMin,
                            )
                          : null,
                    ),
                    if (stopIndex < orderedKeys.length - 1)
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 22),
                        child: Container(
                          width: 2,
                          height: 8,
                          color: const Color(0xFFE8E8E8),
                        ),
                      ),
                  ],
                  const SizedBox(height: 6),
                  _RouteStopCard(
                    index: orderedKeys.length + 1,
                    color: const Color(0xFF111827),
                    title: 'Entrega',
                    subtitle: 'Destino final',
                    trailing:
                        orderedKeys.length < trip!.legs.length
                            ? _LegChips(
                                leg: trip!.legs[
                                    orderedKeys.length],
                                formatKm: _formatKm,
                                formatMin: _formatMin,
                              )
                            : null,
                    icon: Icons.flag_circle_rounded,
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
          icon: Icons.straighten_rounded,
          label: formatKm(leg.distanceMeters),
        ),
        _PillChip(
          icon: Icons.schedule_rounded,
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
    this.icon = Icons.location_on_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 420;

        final indexBadge = Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              '$index',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: color,
                fontSize: 13,
              ),
            ),
          ),
        );

        final titleRow = Row(
          children: [
            Icon(icon, size: 15, color: textGray900),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textGray900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        );

        final subtitleText = Text(
          subtitle,
          maxLines: isNarrow ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textGray600,
            height: 1.3,
          ),
        );

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleRow,
            const SizedBox(height: 3),
            subtitleText,
            if (isNarrow && trailing != null) ...[
              const SizedBox(height: 8),
              Align(
                  alignment: Alignment.centerRight,
                  child: trailing!),
            ],
          ],
        );

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFECECEC),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              indexBadge,
              const SizedBox(width: 10),
              Expanded(child: content),
              if (!isNarrow && trailing != null) ...[
                const SizedBox(width: 8),
                Flexible(
                    fit: FlexFit.loose, child: trailing!),
              ],
            ],
          ),
        );
      },
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
      padding:
          const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundGray50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: textGray600),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: textGray900,
            ),
          ),
        ],
      ),
    );
  }
}
