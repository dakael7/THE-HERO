import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../../core/common/hero_header_app_bar.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/config/env.dart';
import '../../../../../domain/entities/address.dart';
import '../providers/profile_provider.dart';
import 'location_picker_screen.dart';

class AddressScreen extends ConsumerStatefulWidget {
  final Address? currentAddress;

  const AddressScreen({super.key, this.currentAddress});

  @override
  ConsumerState<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends ConsumerState<AddressScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final Map<
      AddressSlot,
      ({
        String? address,
        double? lat,
        double? lng,
        String? countryCode,
      })> _slotLocations = {
    AddressSlot.one: (address: null, lat: null, lng: null, countryCode: null),
    AddressSlot.two: (address: null, lat: null, lng: null, countryCode: null),
    AddressSlot.three:
        (address: null, lat: null, lng: null, countryCode: null),
  };

  final Map<AddressSlot, TextEditingController> _nameControllers = {};
  final Map<AddressSlot, TextEditingController> _unitControllers = {};
  final Map<AddressSlot, TextEditingController> _postalCodeControllers = {};

  late final AnimationController _saveButtonController;
  AnimationController? _fadeInController;

  AddressSlot _primarySlot = AddressSlot.one;
  bool _isSaving = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _saveButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );

    _fadeInController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..value = 1.0;

    for (final s in AddressSlot.values) {
      _nameControllers[s] = TextEditingController();
      _unitControllers[s] = TextEditingController();
      _postalCodeControllers[s] = TextEditingController();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExistingAddresses();
    });
  }

  @override
  void dispose() {
    _saveButtonController.dispose();
    _fadeInController?.dispose();
    for (final c in _nameControllers.values) {
      c.dispose();
    }
    for (final c in _unitControllers.values) {
      c.dispose();
    }
    for (final c in _postalCodeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExistingAddresses() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final user = await ref.read(profileProvider.future);
      if (user == null) return;

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.id)
          .get();
      final data = snap.data();
      if (data == null) return;

      bool updated = false;

      final rawSlots = data['addressSlots'];
      if (rawSlots is Map) {
        final slots = Map<String, dynamic>.from(rawSlots);
        for (final s in AddressSlot.values) {
          final raw = slots[s.jsonValue];
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          final fullAddress = m['fullAddress']?.toString();
          final lat = m['latitude'];
          final lng = m['longitude'];
          final cc = m['countryCode']?.toString();

          _slotLocations[s] = (
            address: fullAddress,
            lat: lat is num ? lat.toDouble() : null,
            lng: lng is num ? lng.toDouble() : null,
            countryCode: cc,
          );
          _nameControllers[s]?.text = (m['name']?.toString() ?? '').trim();
          _unitControllers[s]?.text =
              (m['unitIdentifier']?.toString() ?? '').trim();
          _postalCodeControllers[s]?.text =
              (m['postalCode']?.toString() ?? '').trim();
          updated = true;
        }

        final primary = data['primaryAddressSlot']?.toString();
        if (primary != null && primary.trim().isNotEmpty) {
          try {
            _primarySlot = AddressSlot.fromString(primary);
          } catch (_) {}
        }

        if (updated && mounted) setState(() {});
        return;
      }

      // Legacy: addressUnits
      final rawUnits = data['addressUnits'];
      if (rawUnits is Map) {
        final units = Map<String, dynamic>.from(rawUnits);
        for (final s in AddressSlot.values) {
          final raw = units[s.jsonValue];
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          final fullAddress = m['fullAddress']?.toString();
          final lat = m['latitude'];
          final lng = m['longitude'];
          final cc = m['countryCode']?.toString();

          _slotLocations[s] = (
            address: fullAddress,
            lat: lat is num ? lat.toDouble() : null,
            lng: lng is num ? lng.toDouble() : null,
            countryCode: cc,
          );
          _nameControllers[s]?.text = (m['name']?.toString() ?? '').trim();
          _unitControllers[s]?.text =
              (m['unitIdentifier']?.toString() ?? '').trim();
          _postalCodeControllers[s]?.text =
              (m['postalCode']?.toString() ?? '').trim();
          updated = true;
        }

        if (updated && mounted) setState(() {});
        return;
      }

      // Legacy: single address
      final legacy = data['address'];
      if (legacy is Map) {
        final m = Map<String, dynamic>.from(legacy);
        final fullAddress = m['fullAddress']?.toString();
        final lat = m['latitude'];
        final lng = m['longitude'];
        final cc = m['countryCode']?.toString();

        _primarySlot = AddressSlot.one;
        _slotLocations[AddressSlot.one] = (
          address: fullAddress,
          lat: lat is num ? lat.toDouble() : null,
          lng: lng is num ? lng.toDouble() : null,
          countryCode: cc,
        );
        _nameControllers[AddressSlot.one]?.text =
            (m['name']?.toString() ?? '').trim();
        _unitControllers[AddressSlot.one]?.text =
            (m['unitIdentifier']?.toString() ?? '').trim();
        _postalCodeControllers[AddressSlot.one]?.text =
            (m['postalCode']?.toString() ?? '').trim();

        if (mounted) setState(() {});
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _fadeInController?.forward(from: 0.0);
      }
    }
  }

  Future<void> _openMapPickerForSlot(AddressSlot slot) async {
    final apiKey = Env.placesApiKey;
    if (apiKey.isEmpty) {
      if (mounted) {
        _showSnackBar(
          message: 'Falta configurar PLACES_API_KEY',
          icon: Icons.error_rounded,
          color: Colors.red.shade700,
        );
      }
      return;
    }

    final current = _slotLocations[slot];
    final result = await Navigator.of(context).push<MapLocationResult>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          apiKey: apiKey,
          initialLatitude: current?.lat,
          initialLongitude: current?.lng,
          initialAddress: current?.address,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _slotLocations[slot] = (
          address: result.address,
          lat: result.latitude,
          lng: result.longitude,
          countryCode: result.countryCode,
        );
      });
    }
  }

  bool _isSlotEmpty(AddressSlot s) {
    final loc = _slotLocations[s];
    final name = (_nameControllers[s]?.text ?? '').trim();
    final unit = (_unitControllers[s]?.text ?? '').trim();
    final postal = (_postalCodeControllers[s]?.text ?? '').trim();
    final hasAddress = (loc?.address ?? '').trim().isNotEmpty;
    final hasCoords = loc?.lat != null && loc?.lng != null;
    return !hasAddress && !hasCoords && name.isEmpty && unit.isEmpty && postal.isEmpty;
  }

  bool _isComplete(AddressSlot s) {
    final loc = _slotLocations[s];
    final name = (_nameControllers[s]?.text ?? '').trim();
    final unit = (_unitControllers[s]?.text ?? '').trim();
    final postal = (_postalCodeControllers[s]?.text ?? '').trim();
    return (loc?.address ?? '').trim().isNotEmpty &&
        loc?.lat != null &&
        loc?.lng != null &&
        name.isNotEmpty &&
        unit.isNotEmpty &&
        postal.isNotEmpty;
  }

  void _showSnackBar({
    required String message,
    required IconData icon,
    required Color color,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        elevation: 8,
      ),
    );
  }

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;

    final startedSlots = AddressSlot.values.where((s) => !_isSlotEmpty(s));
    if (startedSlots.isEmpty) {
      _showSnackBar(
        message: 'No hay direcciones para guardar',
        icon: Icons.warning_amber_rounded,
        color: categoryTextYellow,
      );
      return;
    }

    final firstIncomplete = startedSlots.cast<AddressSlot?>().firstWhere(
          (s) => s != null && !_isComplete(s),
          orElse: () => null,
        );
    if (firstIncomplete != null) {
      _showSnackBar(
        message: 'Completa ${firstIncomplete.displayName} para guardar',
        icon: Icons.warning_amber_rounded,
        color: categoryTextYellow,
      );
      return;
    }

    await _saveButtonController.reverse();
    await _saveButtonController.forward();

    setState(() => _isSaving = true);

    try {
      final user = await ref.read(profileProvider.future);
      if (user == null) throw Exception('Usuario no encontrado');

      Map<String, dynamic> slotToJson(AddressSlot s) {
        final loc = _slotLocations[s]!;
        return {
          'fullAddress': loc.address,
          'latitude': loc.lat,
          'longitude': loc.lng,
          'countryCode': loc.countryCode,
          'unitIdentifier': (_unitControllers[s]?.text ?? '').trim(),
          'postalCode': (_postalCodeControllers[s]?.text ?? '').trim(),
          'name': (_nameControllers[s]?.text ?? '').trim(),
        };
      }

      final completeSlots = startedSlots.toList();
      AddressSlot primarySlot = _primarySlot;
      if (!completeSlots.contains(primarySlot)) {
        primarySlot = completeSlots.first;
      }

      final addressSlots = <String, dynamic>{
        for (final s in completeSlots) s.jsonValue: slotToJson(s),
      };

      final primaryLoc = _slotLocations[primarySlot]!;
      final primaryUnit = (_unitControllers[primarySlot]?.text ?? '').trim();
      final primaryPostal =
          (_postalCodeControllers[primarySlot]?.text ?? '').trim();
      final primaryName = (_nameControllers[primarySlot]?.text ?? '').trim();

      await FirebaseFirestore.instance.collection('users').doc(user.id).set({
        'addressSlots': addressSlots,
        'primaryAddressSlot': primarySlot.jsonValue,
        'address': {
          'fullAddress': primaryLoc.address,
          'latitude': primaryLoc.lat,
          'longitude': primaryLoc.lng,
          'countryCode': primaryLoc.countryCode,
          'unitIdentifier': primaryUnit,
          'postalCode': primaryPostal,
          'name': primaryName,
        },
      }, SetOptions(merge: true));

      ref.invalidate(profileProvider);

      if (mounted) {
        _showSnackBar(
          message: 'Dirección guardada exitosamente',
          icon: Icons.check_circle_rounded,
          color: categoryTextGreen,
        );
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = AddressSlot.values.where(_isComplete).length;
    final totalSlots = AddressSlot.values.length;

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: HeroHeaderAppBar(
        title: 'Mis Direcciones',
        icon: Icons.location_on_rounded,
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
        actions: [
          if (completedCount > 0)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: textGray900,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 11,
                    color: primaryYellow,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$completedCount/$totalSlots',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: primaryYellow,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (!_isLoading) _ProgressHeader(completedCount: completedCount),
              Expanded(
                child: _isLoading
                    ? const _LoadingState()
                    : FadeTransition(
                        opacity: _fadeInController ?? const AlwaysStoppedAnimation(1.0),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          children: [
                            for (final slot in AddressSlot.values) ...[
                              _SlotAddressCard(
                                slot: slot,
                                slotIndex: AddressSlot.values.indexOf(slot),
                                location: _slotLocations[slot],
                                nameController: _nameControllers[slot]!,
                                unitController: _unitControllers[slot]!,
                                postalCodeController: _postalCodeControllers[slot]!,
                                isPrimary: _primarySlot == slot,
                                isLoading: _isLoading,
                                isComplete: _isComplete(slot),
                                onTapMap: () => _openMapPickerForSlot(slot),
                                onSelectPrimary: () =>
                                    setState(() => _primarySlot = slot),
                              ),
                              if (slot != AddressSlot.values.last)
                                const SizedBox(height: 12),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _isLoading
          ? null
          : _SaveButton(
              isSaving: _isSaving,
              onPressed:
                  (_isSaving || _isLoading) ? null : () => _saveAddress(),
            ),
    );
  }
}

// ─── Progress Header ──────────────────────────────────────────────────────────

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.completedCount});

  final int completedCount;

  @override
  Widget build(BuildContext context) {
    final progress = completedCount / 3.0;
    final labels = ['Sin guardar', '1 guardada', '2 guardadas', 'Completo'];

    return Container(
      color: backgroundWhite,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                labels[completedCount.clamp(0, 3)],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: completedCount == 3 ? categoryTextGreen : textGray600,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                '$completedCount de 3 direcciones',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textGray600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: borderGray100,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    completedCount == 3 ? categoryTextGreen : primaryOrange,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Loading State ────────────────────────────────────────────────────────────

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: primaryOrange.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: primaryOrange,
                strokeWidth: 2.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Cargando tus direcciones...',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textGray600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Save Button ──────────────────────────────────────────────────────────────

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.isSaving, required this.onPressed});

  final bool isSaving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryOrange,
          foregroundColor: Colors.white,
          disabledBackgroundColor: primaryOrange.withValues(alpha: 0.5),
          minimumSize: const Size.fromHeight(56),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isSaving
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : const Row(
                  key: ValueKey('idle'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.save_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Guardar Direcciones',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── Slot Address Card ────────────────────────────────────────────────────────

class _SlotAddressCard extends StatelessWidget {
  const _SlotAddressCard({
    required this.slot,
    required this.slotIndex,
    required this.location,
    required this.nameController,
    required this.unitController,
    required this.postalCodeController,
    required this.isPrimary,
    required this.isLoading,
    required this.isComplete,
    required this.onTapMap,
    required this.onSelectPrimary,
  });

  final AddressSlot slot;
  final int slotIndex;
  final ({
    String? address,
    double? lat,
    double? lng,
    String? countryCode,
  })? location;
  final TextEditingController nameController;
  final TextEditingController unitController;
  final TextEditingController postalCodeController;
  final bool isPrimary;
  final bool isLoading;
  final bool isComplete;
  final VoidCallback onTapMap;
  final VoidCallback onSelectPrimary;

  bool get _hasAddress => (location?.address ?? '').trim().isNotEmpty;
  bool get _hasCoords => location?.lat != null && location?.lng != null;

  bool get _isStarted =>
      nameController.text.trim().isNotEmpty ||
      unitController.text.trim().isNotEmpty ||
      postalCodeController.text.trim().isNotEmpty ||
      _hasAddress ||
      _hasCoords;

  @override
  Widget build(BuildContext context) {
    const accentColor = primaryOrange;
    const slotIcon = Icons.location_on_rounded;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPrimary
              ? primaryOrange
              : isComplete
                  ? categoryTextGreen.withValues(alpha: 0.4)
                  : borderGray100,
          width: isPrimary ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isPrimary
                ? primaryOrange.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: isPrimary ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _CardHeader(
            slot: slot,
            slotIcon: slotIcon,
            accentColor: accentColor,
            isPrimary: isPrimary,
            isComplete: isComplete,
            hasAddress: _hasAddress,
            onSelectPrimary: onSelectPrimary,
            isLoading: isLoading,
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: borderGray100,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _FormField(
                  controller: nameController,
                  label: 'Nombre de la dirección',
                  icon: Icons.label_outline_rounded,
                  enabled: !isLoading,
                  validator: (v) {
                    if (!_isStarted) return null;
                    if (v == null || v.trim().isEmpty)
                      return 'Ingresa un nombre';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                _FormField(
                  controller: unitController,
                  label: 'Dpto. / Casa / Oficina / Condominio',
                  hint: 'Ejm. Casa 3, Dpto 101',
                  icon: Icons.door_front_door_outlined,
                  enabled: !isLoading,
                  validator: (v) {
                    if (!_isStarted) return null;
                    if (v == null || v.trim().isEmpty)
                      return 'Completa este campo';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                _FormField(
                  controller: postalCodeController,
                  label: 'Código Postal',
                  hint: 'Ej: 7500000',
                  icon: Icons.local_post_office_outlined,
                  enabled: !isLoading,
                  validator: (v) {
                    if (!_isStarted) return null;
                    if (v == null || v.trim().isEmpty)
                      return 'Completa este campo';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _MapPickerButton(
                  hasAddress: _hasAddress,
                  address: location?.address,
                  hasCoords: _hasCoords,
                  isStarted: _isStarted,
                  isLoading: isLoading,
                  onTap: onTapMap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Card Header ──────────────────────────────────────────────────────────────

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.slot,
    required this.slotIcon,
    required this.accentColor,
    required this.isPrimary,
    required this.isComplete,
    required this.hasAddress,
    required this.onSelectPrimary,
    required this.isLoading,
  });

  final AddressSlot slot;
  final IconData slotIcon;
  final Color accentColor;
  final bool isPrimary;
  final bool isComplete;
  final bool hasAddress;
  final VoidCallback onSelectPrimary;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isPrimary
                  ? primaryOrange.withValues(alpha: 0.12)
                  : accentColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              slotIcon,
              size: 20,
              color: isPrimary ? primaryOrange : accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slot.displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: textGray900,
                    letterSpacing: -0.3,
                  ),
                ),
                if (isPrimary)
                  const Text(
                    'Dirección principal activa',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: primaryOrange,
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              _StatusBadge(isPrimary: isPrimary, hasAddress: hasAddress),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: isLoading ? null : onSelectPrimary,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isPrimary
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      key: ValueKey(isPrimary),
                      color: isPrimary ? primaryOrange : textGray600,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Map Picker Button ────────────────────────────────────────────────────────

class _MapPickerButton extends StatelessWidget {
  const _MapPickerButton({
    required this.hasAddress,
    required this.address,
    required this.hasCoords,
    required this.isStarted,
    required this.isLoading,
    required this.onTap,
  });

  final bool hasAddress;
  final String? address;
  final bool hasCoords;
  final bool isStarted;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: isLoading ? null : onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: hasAddress
                  ? backgroundGray50
                  : primaryOrange.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasAddress ? borderGray100 : primaryOrange,
                width: hasAddress ? 1 : 1.5,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: hasAddress
                        ? borderGray100
                        : primaryOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    hasAddress
                        ? Icons.place_rounded
                        : Icons.add_location_alt_rounded,
                    size: 16,
                    color: hasAddress ? textGray600 : primaryOrange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasAddress
                        ? (address ?? '')
                        : 'Seleccionar ubicación en el mapa',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: hasAddress ? textGray900 : primaryOrange,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: hasAddress ? textGray600 : primaryOrange,
                ),
              ],
            ),
          ),
        ),
        if (isStarted && (!hasAddress || !hasCoords))
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: const [
                Icon(
                  Icons.info_outline_rounded,
                  size: 12,
                  color: categoryTextRed,
                ),
                SizedBox(width: 4),
                Text(
                  'Selecciona la ubicación en el mapa',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: categoryTextRed,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── Status Badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.isPrimary,
    required this.hasAddress,
  });

  final bool isPrimary;
  final bool hasAddress;

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [primaryOrange, Color(0xFFFF8C42)],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 11, color: Colors.white),
            SizedBox(width: 3),
            Text(
              'Principal',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: hasAddress ? categoryBgGreen : backgroundGray50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasAddress
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 11,
            color: hasAddress ? categoryTextGreen : textGray600,
          ),
          const SizedBox(width: 4),
          Text(
            hasAddress ? 'OK' : 'Vacío',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: hasAddress ? categoryTextGreen : textGray600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Form Field ───────────────────────────────────────────────────────────────

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.validator,
    this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final bool enabled;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textGray900,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Icon(icon, size: 18, color: textGray600),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 44),
        labelStyle: const TextStyle(
          fontSize: 13,
          color: textGray600,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          fontSize: 12,
          color: textGray600.withValues(alpha: 0.6),
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: backgroundGray50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderGray100),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderGray100),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryOrange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: categoryTextRed),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: categoryTextRed, width: 1.5),
        ),
      ),
      validator: validator,
    );
  }
}