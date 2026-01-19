import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/config/env.dart';
import '../../../features/shared/profile/presentation/providers/profile_provider.dart';
import '../../../features/shared/profile/presentation/views/location_picker_screen.dart';
import '../../../domain/entities/user.dart';
import 'cart_provider.dart';
import 'cart_summary_provider.dart';
import 'order_builder.dart';

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
  ProviderSubscription<AsyncValue<User?>>? _profileSub;

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
    _profileSub = ref.listenManual<AsyncValue<User?>>(profileProvider, (previous, next) {
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
      });
    }
  }

  void _proceedToPayment() {
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

    try {
      // Create delivery info
      final delivery = OrderBuilder.createDelivery(
        address: _addressController.text.trim(),
        recipientName: _nameController.text.trim(),
        recipientPhone: _phoneController.text.trim(),
        instructions: _instructionsController.text.trim(),
      );

      // Build order locally
      final order = OrderBuilder.buildOrderFromCart(
        cartItems: cartItems,
        cartSummary: summary,
        heroId: user.id,
        delivery: delivery,
        pickupAddress:
            'Dirección del vendedor', // TODO: Get from seller profile
        pickupContactName: user.fullName,
        pickupContactPhone: '', // TODO: Add phone field to User entity
      );

      // TODO: In future, this will create payment intent and navigate to payment screen
      // For now, just show a success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Orden creada localmente. Total: \$${order.amountTotal.toStringAsFixed(0)} CLP',
          ),
          duration: const Duration(milliseconds: 2500),
          backgroundColor: Colors.green,
        ),
      );

      // Debug: Print order details
      debugPrint('=== ORDER PREVIEW ===');
      debugPrint('Order ID: ${order.orderId}');
      debugPrint('Hero ID: ${order.heroId}');
      debugPrint('Items: ${order.items.length}');
      debugPrint('Subtotal: \$${order.subtotal}');
      debugPrint('Delivery Fee: \$${order.deliveryFee}');
      debugPrint('Service Fee: \$${order.serviceFee}');
      debugPrint('Tax: \$${order.tax}');
      debugPrint('Total: \$${order.amountTotal}');
      debugPrint('Weight: ${order.requirements.weightKg} kg');
      debugPrint('Required Vehicle: ${order.requirements.requiredVehicle}');
      debugPrint('Delivery Address: ${order.delivery.addressSnapshot}');
      debugPrint('Recipient: ${order.delivery.recipientName}');
      debugPrint('====================');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear orden: $e'),
          duration: const Duration(milliseconds: 2500),
          backgroundColor: Colors.red,
        ),
      );
    }
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
                        '${summary.totalWeight.toStringAsFixed(2)} kg',
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
                  _buildSummaryRow(
                    'Envío:',
                    '\$${summary.shippingCost.toStringAsFixed(0)}',
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

            // Payment Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _proceedToPayment,
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
                child: const Text(
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
            const Text(
              '* El pago aún no está implementado. Esta es una vista previa.',
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
