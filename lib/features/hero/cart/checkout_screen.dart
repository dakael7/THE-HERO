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
import 'checkout_coupon.dart';
import 'order_builder.dart';
import 'waiting_rider_screen.dart';

part 'checkout_screen_ui.dart';
part 'checkout_screen_routes.dart';

// -----------------------------------------------------------------------------
//  EXCEPTION (unchanged)
// -----------------------------------------------------------------------------

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

// -----------------------------------------------------------------------------
//  MAIN WIDGET
// -----------------------------------------------------------------------------

class CheckoutScreen extends ConsumerStatefulWidget {
  final CartItem? item;

  const CheckoutScreen({super.key, this.item});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

// -----------------------------------------------------------------------------
//  TIP OPTION CARD — premium redesign
// -----------------------------------------------------------------------------

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
                  color: primaryOrange.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
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
                              ? primaryOrange.withValues(alpha: 0.7)
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

// -----------------------------------------------------------------------------
//  STATE
// -----------------------------------------------------------------------------

enum _CheckoutStage { delivery, document, payment }

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
  final _couponController = TextEditingController();
  static const _defaultCountryCode = '+56 ';
  bool _prefilled = false;
  bool _isSubmitting = false;
  bool _isCheckingCoupon = false;
  bool _isResolvingMapInitialLocation = false;
  bool _deliverToReception = false;
  bool _useAccountAddress = false;
  AddressSlot? _selectedAccountAddressSlot;
  double? _deliveryLatitude;
  double? _deliveryLongitude;
  String? _manualUnitIdentifier;
  String? _manualPostalCode;
  String _selectedDocumentType = 'boleta';
  CheckoutCoupon? _appliedCoupon;
  String? _couponError;
  _CheckoutStage _checkoutStage = _CheckoutStage.delivery;

  Timer? _routesDebounce;
  ({
    Map<String, firestore.GeoPoint> uniquePickups,
    firestore.GeoPoint delivery,
  })?
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

  double _couponBase(CartSummary summary) {
    final total = summary.shippingCost + summary.serviceFee + summary.tax;
    return total.isFinite ? total.clamp(0.0, double.infinity).toDouble() : 0.0;
  }

  double _couponDiscount(CartSummary summary) {
    return _appliedCoupon?.discountFor(_couponBase(summary)) ?? 0.0;
  }

  CartSummary _summaryAfterCoupon(CartSummary summary) {
    final discount = _couponDiscount(summary);
    if (discount <= 0) return summary;

    return CartSummary(
      subtotal: summary.subtotal,
      shippingCost: summary.shippingCost,
      serviceFee: summary.serviceFee,
      tax: summary.tax,
      total: (summary.total - discount).clamp(0.0, double.infinity).toDouble(),
      totalWeight: summary.totalWeight,
      shippingBreakdown: summary.shippingBreakdown,
    );
  }

  Future<void> _applyCoupon() async {
    final code = _couponController.text.trim().toUpperCase();
    if (code.isEmpty || _isCheckingCoupon) return;

    setState(() {
      _isCheckingCoupon = true;
      _couponError = null;
    });

    try {
      final coupon = await ref.read(checkoutCouponProvider(code).future);
      if (!mounted) return;

      if (coupon == null) {
        setState(() {
          _appliedCoupon = null;
          _couponError = 'Cupo no encontrado';
        });
        return;
      }

      if (!coupon.active) {
        setState(() {
          _appliedCoupon = null;
          _couponError = 'Cupo inactivo';
        });
        return;
      }

      setState(() {
        _couponController.text = coupon.code;
        _appliedCoupon = coupon;
        _couponError = null;
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _appliedCoupon = null;
        _couponError = 'Cupo mal configurado';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _appliedCoupon = null;
        _couponError = 'No se pudo validar el cupo';
      });
    } finally {
      if (mounted) {
        setState(() => _isCheckingCoupon = false);
      }
    }
  }

  void _goToCheckoutStage(_CheckoutStage stage) {
    if (stage.index > _checkoutStage.index) return;
    setState(() => _checkoutStage = stage);
  }

  void _goToPreviousCheckoutStage() {
    if (_checkoutStage == _CheckoutStage.delivery) return;
    setState(() {
      _checkoutStage = _CheckoutStage.values[_checkoutStage.index - 1];
    });
  }

  void _goToNextCheckoutStage({required bool canProceed}) {
    if (!_formKey.currentState!.validate()) return;

    if (_checkoutStage == _CheckoutStage.delivery && !canProceed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa la entrega para continuar.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_checkoutStage == _CheckoutStage.payment) return;
    setState(() {
      _checkoutStage = _CheckoutStage.values[_checkoutStage.index + 1];
    });
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

    // Normalize to a canonical RUT shape so any misplaced '-' is corrected.
    final compact = cleaned.replaceAll('-', '');
    final bounded = compact.length > 9 ? compact.substring(0, 9) : compact;
    if (bounded.isEmpty) return '';
    if (bounded.length == 1) return bounded;

    final body = bounded
        .substring(0, bounded.length - 1)
        .replaceAll(RegExp(r'[^0-9]'), '');
    final dv = bounded
        .substring(bounded.length - 1)
        .replaceAll(RegExp(r'[^0-9K]'), '');
    if (body.isEmpty) return dv;

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
    _couponController.dispose();
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

    final hasAnyMissingPickupCountry = cartItems.any(
      (e) => (e.pickupCountryCode?.trim().isEmpty ?? true),
    );

    if ((deliveryCc == null || deliveryCc.isEmpty) && pickupCcs.length == 1) {
      deliveryCc = pickupCcs.first;
    }

    if (deliveryCc == null || deliveryCc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo determinar el país de la dirección de entrega.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (hasAnyMissingPickupCountry) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo determinar el país de una o más ubicaciones de retiro.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (pickupCcs.length != 1 || pickupCcs.first != deliveryCc) {
      debugPrint(
        'ðŸŒŽ [Checkout] Country mismatch delivery=$deliveryCc pickup=${pickupCcs.join(",")} (missingPickup=$hasAnyMissingPickupCountry)',
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

    ref.read(deliveryGeoProvider.notifier).state = firestore.GeoPoint(
      addr.latitude,
      addr.longitude,
    );
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
      final cc = (result.countryCode?.trim().toUpperCase().isNotEmpty ?? false)
          ? result.countryCode!.trim().toUpperCase()
          : null;

      if (cc == null || cc.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo determinar el país de la ubicación seleccionada.',
            ),
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

      ref.read(deliveryGeoProvider.notifier).state = firestore.GeoPoint(
        result.latitude,
        result.longitude,
      );

      print(
        'ðŸ“ [Checkout] Delivery coordinates captured: ${result.latitude}, ${result.longitude}',
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
    final discountedSummary = _summaryAfterCoupon(summary);
    final couponDiscount = _couponDiscount(summary);
    final couponJson = _appliedCoupon?.toOrderJson(couponDiscount);
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
      final hasAnyMissingPickupCountry = cartItems.any(
        (e) => (e.pickupCountryCode?.trim().isEmpty ?? true),
      );

      if (deliveryCc == null || deliveryCc.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo determinar el país de la dirección de entrega.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      if (hasAnyMissingPickupCountry || pickupCcs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo determinar el país de una o más ubicaciones de retiro.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      if (pickupCcs.length != 1 || pickupCcs.first != deliveryCc) {
        debugPrint(
          'ðŸŒŽ [Checkout] Reject cross-country order: delivery=$deliveryCc pickup=${pickupCcs.join(",")}',
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
          cartSummary: discountedSummary,
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
          coupon: couponJson,
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

    final maxDistanceKm = TransportPricingConfig.getMaxDistance(
      requiredVehicle,
    );

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
      var deliveryGeo = _deliveryLatitude != null && _deliveryLongitude != null
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
        'ðŸ“¦ [Checkout] Creating order with delivery geo: ${delivery.geo.latitude}, ${delivery.geo.longitude}',
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
        cartSummary: discountedSummary,
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
        coupon: couponJson,
      );

      if (shouldUseMercadoPago) {
        debugPrint('ðŸ’³ [Checkout] Using MercadoPago payment flow');
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
        final createdOrder = await createOrderUseCase.execute(
          order,
          currentUser: user,
        );

        if (paymentState.expiresAt != null) {
          await firestore.FirebaseFirestore.instance
              .collection('orders')
              .doc(createdOrder.orderId)
              .set({
                'paymentPreferenceId': paymentState.preferenceId,
                'paymentExpiresAt': firestore.Timestamp.fromDate(
                  paymentState.expiresAt!,
                ),
                'paymentStatus': 'pending',
                'updatedAt': firestore.FieldValue.serverTimestamp(),
              }, firestore.SetOptions(merge: true));
        }

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
                  'Tienes 5 minutos para pagar; si no se completa, la orden se cancelará y el stock volverá a estar disponible.',
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
          'ðŸ’µ [Checkout] Skipping MercadoPago (${_selectedPaymentMethod == PaymentMethod.cash ? "Cash payment" : "Sandbox mode"})',
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
            metadata: <String, dynamic>{
              'flow': 'cash',
              'note': 'Pago en efectivo pendiente. Se confirma en la entrega.',
              if (createdOrder.coupon != null) 'coupon': createdOrder.coupon,
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
    final totalItems = cartItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

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
    final hasAnyMissingPickupCountry = cartItems.any(
      (e) => (e.pickupCountryCode?.trim().isEmpty ?? true),
    );
    final sameCountry =
        deliveryCc != null &&
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
        maxDistanceKm = TransportPricingConfig.getMaxDistance(requiredVehicle);
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
    final couponDiscount = _couponDiscount(summary);
    final totalWithTip =
        _summaryAfterCoupon(summary).total + effectiveTip.toDouble();
    final isDeliveryStage = _checkoutStage == _CheckoutStage.delivery;
    final isDocumentStage = _checkoutStage == _CheckoutStage.document;
    final isPaymentStage = _checkoutStage == _CheckoutStage.payment;

    if (!inPersonPickupSelected) {
      this._scheduleRoutesLoad(cartItems: cartItems, deliveryGeo: deliveryGeo);
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
                        horizontal: 12,
                        vertical: 6,
                      ),
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
            _CheckoutStageHeader(
              current: _checkoutStage,
              onStageTap: _goToCheckoutStage,
            ),
            const SizedBox(height: 16),
            if (isDeliveryStage) ...[
              // ── Route map ─────────────────────────────────────────────────
              if (!inPersonPickupSelected)
                _CheckoutItemsRouteMap(
                  cartItems: cartItems,
                  deliveryGeo: deliveryGeo,
                  isLoading: _isLoadingRoutes,
                  error: _routesError,
                  trip: _trip,
                  onRetry: this._retryRoutesIfPossible,
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
                                    .read(
                                      inPersonPickupSelectedProvider.notifier,
                                    )
                                    .state =
                                val;
                          },
                    icon: Icons.store_rounded,
                    iconColor: const Color(0xFF16A34A),
                    title: 'Retiro en persona',
                    subtitle: 'Sin costo de envío. Solo comisión e impuestos.',
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
                                  _manualPostalCode =
                                      _postalCodeController.text;
                                  _manualDeliveryLatitude = _deliveryLatitude;
                                  _manualDeliveryLongitude = _deliveryLongitude;
                                  setState(() => _useAccountAddress = true);
                                  if (user != null) {
                                    if (_selectedAccountAddressSlot == null &&
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
                                    _deliveryLatitude = _manualDeliveryLatitude;
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
                                            .state =
                                        null;
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
                            final selected = _resolveSelectedAccountAddress(u);
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
                          border: Border.all(color: const Color(0xFFECECEC)),
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
                                          setState(
                                            () =>
                                                _selectedAccountAddressSlot = t,
                                          );
                                          _setDeliveryFromAccountAddress(user);
                                        },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: sel
                                          ? primaryOrange.withOpacity(0.1)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
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
                                final slot =
                                    _selectedAccountAddressSlot ??
                                    user.primaryAddressSlot;
                                final title = _formatSavedAddressLabel(
                                  selectedAddr,
                                  fallbackSlot: slot,
                                );
                                final fullAddress = selectedAddr?.fullAddress
                                    .trim();
                                final unitLine = selectedAddr?.unitDisplayLine
                                    ?.trim();
                                if (title.trim().isEmpty &&
                                    (fullAddress == null ||
                                        fullAddress.isEmpty) &&
                                    (unitLine == null || unitLine.isEmpty)) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF2563EB,
                                          ).withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
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
                                                    color: const Color(
                                                      0xFFECECEC,
                                                    ),
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
                      validator: (v) => (v == null || v.trim().isEmpty)
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
                      validator: (v) => (v == null || v.trim().isEmpty)
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
                        onTap:
                            _useAccountAddress ||
                                _isSubmitting ||
                                _isResolvingMapInitialLocation
                            ? null
                            : _openMapPicker,
                        suffix: GestureDetector(
                          onTap:
                              _useAccountAddress ||
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
                                      valueColor: AlwaysStoppedAnimation(
                                        primaryOrange,
                                      ),
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
                          final hasGeo =
                              _deliveryLatitude != null &&
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
                        onTap:
                            _useAccountAddress ||
                                _isSubmitting ||
                                _isResolvingMapInitialLocation
                            ? null
                            : _openMapPicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
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
                                    valueColor: AlwaysStoppedAnimation(
                                      primaryOrange,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ] else ...[
                                const Icon(
                                  Icons.place_rounded,
                                  size: 16,
                                  color: primaryOrange,
                                ),
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
              _CheckoutStageActions(
                nextLabel: 'Continuar',
                canContinue: !_isSubmitting,
                onNext: () => _goToNextCheckoutStage(canProceed: canProceed),
              ),
              const SizedBox(height: 20),
            ],
            if (isDocumentStage) ...[
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
                    const SizedBox(height: 10),
                    Text(
                      _selectedDocumentType == 'factura'
                          ? 'La factura electrónica se emitirá al procesar el pedido.'
                          : 'La boleta electrónica se emitirá al procesar el pedido.',
                      style: const TextStyle(
                        color: textGray700,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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
              _CheckoutStageActions(
                backLabel: 'Atrás',
                nextLabel: 'Continuar',
                canContinue: !_isSubmitting,
                onBack: _goToPreviousCheckoutStage,
                onNext: () => _goToNextCheckoutStage(canProceed: canProceed),
              ),
              const SizedBox(height: 20),
            ],
            if (isPaymentStage) ...[
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
                              horizontal: 10,
                              vertical: 5,
                            ),
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
                                final value = await _askForCustomTip(context);
                                if (!mounted || value == null) return;
                                setState(() => _selectedTip = value);
                              },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE8E8E8)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.edit_rounded,
                                size: 14,
                                color: textGray600,
                              ),
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
                icon: Icons.confirmation_number_rounded,
                label: 'Cupo',
              ),
              const SizedBox(height: 12),
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _couponController,
                            enabled: !_isSubmitting && !_isCheckingCoupon,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: 'Ingresa tu cupo',
                              isDense: true,
                              filled: true,
                              fillColor: backgroundGray50,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE8E8E8),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE8E8E8),
                                ),
                              ),
                              prefixIcon: const Icon(
                                Icons.confirmation_number_outlined,
                                size: 18,
                              ),
                            ),
                            onChanged: (_) {
                              if (_appliedCoupon == null &&
                                  _couponError == null) {
                                return;
                              }
                              setState(() {
                                _appliedCoupon = null;
                                _couponError = null;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isSubmitting || _isCheckingCoupon
                                ? null
                                : _applyCoupon,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryOrange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isCheckingCoupon
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Aplicar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    if (_appliedCoupon != null || _couponError != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            _appliedCoupon != null
                                ? Icons.check_circle_rounded
                                : Icons.error_outline_rounded,
                            size: 15,
                            color: _appliedCoupon != null
                                ? const Color(0xFF047857)
                                : const Color(0xFFB91C1C),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _appliedCoupon != null
                                  ? 'Cupo aplicado'
                                  : _couponError!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _appliedCoupon != null
                                    ? const Color(0xFF047857)
                                    : const Color(0xFFB91C1C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

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
                            if (deliveryCc == null || deliveryCc.isEmpty) {
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
                                color: primaryOrange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
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
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: backgroundGray50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE8E8E8)),
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
                      label:
                          'Impuestos (IVA ${(pricingConfig.taxPercentage * 100).toStringAsFixed(0)}%)',
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
                    if (_appliedCoupon != null) ...[
                      const SizedBox(height: 8),
                      _SummaryRow(
                        label: 'Cupo ${_appliedCoupon!.code}',
                        value: canProceed
                            ? '-\$${formatPriceCLP(couponDiscount)}'
                            : '—',
                      ),
                    ],

                    const SizedBox(height: 14),
                    const _Hairline(),
                    const SizedBox(height: 14),

                    // Total row
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                              color: canProceed ? primaryOrange : textGray600,
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
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isSubmitting ? null : _goToPreviousCheckoutStage,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Atrás'),
                ),
              ),
              const SizedBox(height: 8),
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
                                Colors.white,
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
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
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: Color(0xFFB45309),
                      ),
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
          ],
        ),
      ),
    );
  }

  Future<int?> _askForCustomTip(BuildContext context) async {
    _customTipController.text = _selectedTip > 0 ? _selectedTip.toString() : '';

    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            child: const Text('Cancelar', style: TextStyle(color: textGray600)),
          ),
          TextButton(
            onPressed: () {
              final raw = _customTipController.text.trim();
              final sanitized = raw.replaceAll('.', '').replaceAll(',', '');
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
                color: primaryOrange,
              ),
            ),
          ),
        ],
      ),
    );

    return res;
  }
}
