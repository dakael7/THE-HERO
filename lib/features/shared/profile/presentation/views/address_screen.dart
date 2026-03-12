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
  final Map<AddressSlot, TextEditingController> _descriptionControllers = {};
  final Map<AddressSlot, TextEditingController> _unitControllers = {};

  late final AnimationController _fadeController;
  late final AnimationController _saveButtonController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _saveButtonScale;

  AddressSlot _primarySlot = AddressSlot.one;
  bool _isSaving = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _saveButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
    _saveButtonScale = _saveButtonController;

    for (final s in AddressSlot.values) {
      _nameControllers[s] = TextEditingController();
      _descriptionControllers[s] = TextEditingController();
      _unitControllers[s] = TextEditingController();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExistingAddresses();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _saveButtonController.dispose();
    for (final c in _nameControllers.values) {
      c.dispose();
    }
    for (final c in _descriptionControllers.values) {
      c.dispose();
    }
    for (final c in _unitControllers.values) {
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
          _descriptionControllers[s]?.text =
              (m['description']?.toString() ?? '').trim();
          _unitControllers[s]?.text =
              (m['unitIdentifier']?.toString() ?? '').trim();
          updated = true;
        }

        final primary = data['primaryAddressSlot']?.toString();
        if (primary != null && primary.trim().isNotEmpty) {
          try {
            _primarySlot = AddressSlot.fromString(primary);
          } catch (_) {}
        }

        if (updated && mounted) setState(() {});
        _fadeController.forward();
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
          _descriptionControllers[s]?.text =
              (m['description']?.toString() ?? '').trim();
          _unitControllers[s]?.text =
              (m['unitIdentifier']?.toString() ?? '').trim();
          updated = true;
        }

        if (updated && mounted) setState(() {});
        _fadeController.forward();
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
        _descriptionControllers[AddressSlot.one]?.text =
            (m['description']?.toString() ?? '').trim();
        _unitControllers[AddressSlot.one]?.text =
            (m['unitIdentifier']?.toString() ?? '').trim();

        if (mounted) setState(() {});
      }

      _fadeController.forward();
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  bool _isComplete(AddressSlot s) {
    final loc = _slotLocations[s];
    final name = (_nameControllers[s]?.text ?? '').trim();
    final desc = (_descriptionControllers[s]?.text ?? '').trim();
    final unit = (_unitControllers[s]?.text ?? '').trim();
    return (loc?.address ?? '').trim().isNotEmpty &&
        loc?.lat != null &&
        loc?.lng != null &&
        name.isNotEmpty &&
        desc.isNotEmpty &&
        unit.isNotEmpty;
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
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;

    final allComplete = AddressSlot.values.every(_isComplete);
    if (!allComplete) {
      _showSnackBar(
        message: 'Completa las 3 direcciones para continuar',
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
          'name': (_nameControllers[s]?.text ?? '').trim(),
          'description': (_descriptionControllers[s]?.text ?? '').trim(),
        };
      }

      final addressSlots = <String, dynamic>{
        for (final s in AddressSlot.values) s.jsonValue: slotToJson(s),
      };

      final primaryLoc = _slotLocations[_primarySlot]!;
      final primaryUnit = (_unitControllers[_primarySlot]?.text ?? '').trim();
      final primaryName = (_nameControllers[_primarySlot]?.text ?? '').trim();
      final primaryDesc =
          (_descriptionControllers[_primarySlot]?.text ?? '').trim();

      await FirebaseFirestore.instance.collection('users').doc(user.id).set({
        'addressSlots': addressSlots,
        'primaryAddressSlot': _primarySlot.jsonValue,
        'address': {
          'fullAddress': primaryLoc.address,
          'latitude': primaryLoc.lat,
          'longitude': primaryLoc.lng,
          'countryCode': primaryLoc.countryCode,
          'unitIdentifier': primaryUnit,
          'name': primaryName,
          'description': primaryDesc,
        },
      }, SetOptions(merge: true));

      ref.invalidate(profileProvider);

      if (mounted) {
        _showSnackBar(
          message: 'Direcciones guardadas exitosamente',
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
    final primaryEntry = _slotLocations[_primarySlot];
    final hasPrimary = (primaryEntry?.address ?? '').trim().isNotEmpty;
    final completedCount = AddressSlot.values.where(_isComplete).length;
    final progress = completedCount / AddressSlot.values.length;

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: HeroHeaderAppBar(
        title: 'Mi Dirección',
        icon: Icons.location_on_rounded,
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
        actions: [
          if (completedCount > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: textGray900,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$completedCount/3',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: primaryYellow,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // ── Banner informativo ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _InfoBanner(
                  completedCount: completedCount,
                  progress: progress,
                ),
              ),

              const SizedBox(height: 24),

              // ── Sección header ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
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
                    const Icon(
                      Icons.location_on_rounded,
                      size: 18,
                      color: primaryOrange,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Mis Direcciones',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$completedCount de 3 completadas',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: textGray600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Cards de dirección ──────────────────────────────────────
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: _LoadingIndicator(),
                  ),
                )
              else
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (final slot in AddressSlot.values) ...[
                          _SlotAddressCard(
                            slot: slot,
                            location: _slotLocations[slot],
                            nameController: _nameControllers[slot]!,
                            descriptionController:
                                _descriptionControllers[slot]!,
                            unitController: _unitControllers[slot]!,
                            isPrimary: _primarySlot == slot,
                            isLoading: _isLoading,
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

              // ── Dirección principal ─────────────────────────────────────
              if (hasPrimary && !_isLoading) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _PrimaryAddressCard(
                    primarySlot: _primarySlot,
                    address: primaryEntry?.address ?? '',
                  ),
                ),
              ],

              // ── Botón guardar ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                child: ScaleTransition(
                  scale: _saveButtonScale,
                  child: _SaveButton(
                    isSaving: _isSaving,
                    isLoading: _isLoading,
                    onTap: (_isSaving || _isLoading) ? null : _saveAddress,
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

// ────────────────────────────────────────────────────────────────────────────
// Widgets auxiliares privados
// ────────────────────────────────────────────────────────────────────────────

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            color: primaryOrange,
            strokeWidth: 2.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Cargando tus direcciones...',
          style: TextStyle(
            fontSize: 13,
            color: textGray600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.completedCount,
    required this.progress,
  });

  final int completedCount;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: primaryYellow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: textGray900,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Configura tu dirección',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Completa las 3 direcciones. Marca una como principal para usarla por defecto.',
                      style: TextStyle(
                        fontSize: 12,
                        color: textGray600,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (completedCount > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: completedCount / 3,
                      minHeight: 6,
                      backgroundColor: borderGray100,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        completedCount == 3
                            ? categoryTextGreen
                            : primaryOrange,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$completedCount/3',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: completedCount == 3
                        ? categoryTextGreen
                        : primaryOrange,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PrimaryAddressCard extends StatelessWidget {
  const _PrimaryAddressCard({
    required this.primarySlot,
    required this.address,
  });

  final AddressSlot primarySlot;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryOrange.withValues(alpha: 0.08),
            categoryBgYellow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: primaryOrange.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: primaryOrange.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: primaryOrange,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.star_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Dirección principal',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: textGray600,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: primaryOrange,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        primarySlot.displayName,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 13,
                    color: textGray900,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.isSaving,
    required this.isLoading,
    required this.onTap,
  });

  final bool isSaving;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = isSaving || isLoading;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: disabled
              ? primaryOrange.withValues(alpha: 0.55)
              : primaryOrange,
          borderRadius: BorderRadius.circular(16),
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: primaryOrange.withValues(alpha: 0.38),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                    spreadRadius: -2,
                  ),
                ],
        ),
        child: isSaving
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.save_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Guardar Direcciones',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// _SlotAddressCard
// ────────────────────────────────────────────────────────────────────────────

class _SlotAddressCard extends StatelessWidget {
  const _SlotAddressCard({
    required this.slot,
    required this.location,
    required this.nameController,
    required this.descriptionController,
    required this.unitController,
    required this.isPrimary,
    required this.isLoading,
    required this.onTapMap,
    required this.onSelectPrimary,
  });

  final AddressSlot slot;
  final ({
    String? address,
    double? lat,
    double? lng,
    String? countryCode,
  })? location;
  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController unitController;
  final bool isPrimary;
  final bool isLoading;
  final VoidCallback onTapMap;
  final VoidCallback onSelectPrimary;

  bool get _hasAddress => (location?.address ?? '').trim().isNotEmpty;
  bool get _hasCoords =>
      location?.lat != null && location?.lng != null;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isPrimary ? categoryBgYellow : backgroundWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPrimary ? primaryOrange : borderGray100,
          width: isPrimary ? 2 : 1,
        ),
        boxShadow: isPrimary
            ? [
                BoxShadow(
                  color: primaryOrange.withValues(alpha: 0.14),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header de la card ────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isPrimary
                        ? primaryOrange
                        : primaryOrange.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.location_on_rounded,
                    color: isPrimary ? Colors.white : primaryOrange,
                    size: 20,
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
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (_hasAddress)
                        Text(
                          location!.address!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: textGray600,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Badge de estado
                _StatusBadge(
                  isPrimary: isPrimary,
                  hasAddress: _hasAddress,
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(height: 1, color: borderGray100),
            const SizedBox(height: 14),

            // ── Campos del formulario ────────────────────────────────────
            _FormField(
              controller: nameController,
              label: 'Nombre',
              icon: Icons.label_outline_rounded,
              enabled: !isLoading,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresa un nombre' : null,
            ),
            const SizedBox(height: 10),
            _FormField(
              controller: descriptionController,
              label: 'Descripción',
              icon: Icons.notes_rounded,
              enabled: !isLoading,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Ingresa una descripción'
                  : null,
            ),
            const SizedBox(height: 10),
            _FormField(
              controller: unitController,
              label: 'Dpto. / Casa / Oficina / Condominio',
              hint: 'Ejm. Casa 3, Dpto 101',
              icon: Icons.door_front_door_outlined,
              enabled: !isLoading,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Completa este campo' : null,
            ),

            const SizedBox(height: 12),

            // ── Selector de mapa ─────────────────────────────────────────
            GestureDetector(
              onTap: isLoading ? null : onTapMap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _hasAddress
                      ? backgroundGray50
                      : primaryOrange.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hasAddress ? borderGray100 : primaryOrange,
                    width: _hasAddress ? 1 : 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _hasAddress
                            ? borderGray100
                            : primaryOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _hasAddress
                            ? Icons.edit_location_alt_rounded
                            : Icons.map_rounded,
                        size: 16,
                        color: primaryOrange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _hasAddress
                            ? (location!.address ?? '')
                            : 'Seleccionar ubicación en el mapa',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _hasAddress ? textGray900 : primaryOrange,
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: _hasAddress ? textGray600 : primaryOrange,
                    ),
                  ],
                ),
              ),
            ),

            // ── Aviso si falta ubicación ─────────────────────────────────
            if (!_hasAddress || !_hasCoords)
              const Padding(
                padding: EdgeInsets.only(top: 7),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 13,
                      color: categoryTextRed,
                    ),
                    SizedBox(width: 5),
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

            const SizedBox(height: 14),
            const Divider(height: 1, color: borderGray100),
            const SizedBox(height: 12),

            // ── Selector de principal ────────────────────────────────────
            GestureDetector(
              onTap: isLoading ? null : onSelectPrimary,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isPrimary ? primaryOrange : textGray600,
                        width: 2,
                      ),
                      color: isPrimary
                          ? primaryOrange.withValues(alpha: 0.08)
                          : Colors.transparent,
                    ),
                    child: isPrimary
                        ? const Center(
                            child: CircleAvatar(
                              radius: 5,
                              backgroundColor: primaryOrange,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isPrimary ? FontWeight.w800 : FontWeight.w600,
                      color: isPrimary ? primaryOrange : textGray600,
                    ),
                    child: const Text('Usar como dirección principal'),
                  ),
                  if (isPrimary) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.star_rounded,
                      size: 15,
                      color: primaryOrange,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Micro-widgets reutilizables
// ────────────────────────────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: primaryOrange,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Principal',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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
            hasAddress ? 'Ubicación OK' : 'Sin ubicación',
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
        prefixIcon: Icon(icon, size: 18, color: textGray600),
        labelStyle: const TextStyle(
          fontSize: 13,
          color: textGray600,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: backgroundGray50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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