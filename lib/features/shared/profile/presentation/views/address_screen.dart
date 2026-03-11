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

class _AddressScreenState extends ConsumerState<AddressScreen> {
  final Map<
      AddressUnitType,
      ({
        String? address,
        double? lat,
        double? lng,
        String? countryCode,
        String? plusCode,
      })> _unitAddresses = {
    AddressUnitType.apartment:
        (address: null, lat: null, lng: null, countryCode: null, plusCode: null),
    AddressUnitType.house:
        (address: null, lat: null, lng: null, countryCode: null, plusCode: null),
    AddressUnitType.office:
        (address: null, lat: null, lng: null, countryCode: null, plusCode: null),
  };

  AddressUnitType _primaryUnitType = AddressUnitType.apartment;
  bool _isSaving = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExistingAddresses();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  String? _extractPlusCode(String address) {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return null;
    final idx = trimmed.indexOf(',');
    final firstPart =
        (idx >= 0 ? trimmed.substring(0, idx) : trimmed).trim();
    if (firstPart.contains('+')) return firstPart;
    return null;
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

      final rawUnits = data['addressUnits'];
      if (rawUnits is Map) {
        final units = Map<String, dynamic>.from(rawUnits);
        for (final t in AddressUnitType.values) {
          final raw = units[t.jsonValue];
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          final fullAddress = m['fullAddress']?.toString();

          final lat = m['latitude'];
          final lng = m['longitude'];
          final cc = m['countryCode']?.toString();
          final plusCode = m['unitIdentifier']?.toString() ??
              (fullAddress != null ? _extractPlusCode(fullAddress) : null);
          _unitAddresses[t] = (
            address: fullAddress,
            lat: lat is num ? lat.toDouble() : null,
            lng: lng is num ? lng.toDouble() : null,
            countryCode: cc,
            plusCode: plusCode,
          );
        }
        final primary = data['primaryAddressUnitType']?.toString();
        if (primary != null && primary.trim().isNotEmpty) {
          try {
            _primaryUnitType = AddressUnitType.fromString(primary);
          } catch (_) {}
        }
        if (mounted) setState(() {});
        return;
      }

      final legacy = data['address'];
      if (legacy is Map) {
        final m = Map<String, dynamic>.from(legacy);
        final fullAddress = m['fullAddress']?.toString();

        final lat = m['latitude'];
        final lng = m['longitude'];
        final cc = m['countryCode']?.toString();
        final plusCode = m['unitIdentifier']?.toString() ??
            (fullAddress != null ? _extractPlusCode(fullAddress) : null);
        _primaryUnitType = AddressUnitType.apartment;
        _unitAddresses[AddressUnitType.apartment] = (
          address: fullAddress,
          lat: lat is num ? lat.toDouble() : null,
          lng: lng is num ? lng.toDouble() : null,
          countryCode: cc,
          plusCode: plusCode,
        );
        if (mounted) setState(() {});
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openMapPickerForUnit(AddressUnitType type) async {
    final apiKey = Env.placesApiKey;
    if (apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Falta configurar PLACES_API_KEY'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final current = _unitAddresses[type];
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
        _unitAddresses[type] = (
          address: result.address,
          lat: result.latitude,
          lng: result.longitude,
          countryCode: result.countryCode,
          plusCode: _extractPlusCode(result.address),
        );
      });
    }
  }

  bool _isComplete(AddressUnitType t) {
    final e = _unitAddresses[t];
    return (e?.address ?? '').trim().isNotEmpty &&
        e?.lat != null &&
        e?.lng != null &&
        (e?.plusCode ?? '').trim().isNotEmpty;
  }

  Future<void> _saveAddress() async {
    if (!_isComplete(_primaryUnitType)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Debes configurar la dirección principal (${_primaryUnitType.displayName})',
                ),
              ),
            ],
          ),
          backgroundColor: categoryTextYellow,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = await ref.read(profileProvider.future);
      if (user == null) throw Exception('Usuario no encontrado');

      Map<String, dynamic> unitToJson(AddressUnitType t) {
        final e = _unitAddresses[t]!;
        return {
          'fullAddress': e.address,
          'latitude': e.lat,
          'longitude': e.lng,
          'countryCode': e.countryCode,
          'unitType': t.jsonValue,
          'unitIdentifier': e.plusCode,
        };
      }

      final addressUnits = <String, dynamic>{
        for (final t in AddressUnitType.values)
          if (_isComplete(t)) t.jsonValue: unitToJson(t),
      };

      final primaryEntry = _unitAddresses[_primaryUnitType]!;

      await FirebaseFirestore.instance.collection('users').doc(user.id).set({
        'addressUnits': addressUnits,
        'primaryAddressUnitType': _primaryUnitType.jsonValue,
        'address': {
          'fullAddress': primaryEntry.address,
          'latitude': primaryEntry.lat,
          'longitude': primaryEntry.lng,
          'countryCode': primaryEntry.countryCode,
          'unitType': _primaryUnitType.jsonValue,
          'unitIdentifier': primaryEntry.plusCode,
        },
      }, SetOptions(merge: true));

      ref.invalidate(profileProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('Dirección guardada exitosamente'),
              ],
            ),
            backgroundColor: categoryTextGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar dirección: $e'),
            backgroundColor: categoryTextRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Icon per unit type ──
  IconData _iconForType(AddressUnitType type) {
    switch (type) {
      case AddressUnitType.apartment:
        return Icons.apartment_rounded;
      case AddressUnitType.house:
        return Icons.home_rounded;
      case AddressUnitType.office:
        return Icons.business_center_rounded;
    }
  }

  Color _colorForType(AddressUnitType type) {
    switch (type) {
      case AddressUnitType.apartment:
        return primaryOrange;
      case AddressUnitType.house:
        return primaryOrange;
      case AddressUnitType.office:
        return primaryOrange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryEntry = _unitAddresses[_primaryUnitType];
    final hasPrimary = (primaryEntry?.address ?? '').trim().isNotEmpty;
    final completedCount = AddressUnitType.values
        .where(_isComplete)
        .length;

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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: textGray900,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$completedCount configurada${completedCount != 1 ? 's' : ''}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: primaryYellow,
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
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
                child: Row(
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Configura tu dirección',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: textGray900,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Esta dirección se usará como punto de recogida en tus pedidos. Puedes configurar una dirección por tipo de unidad.',
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
              ),
            ),

            const SizedBox(height: 24),

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
                    'Direcciones por unidad',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: textGray900,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(
                    color: primaryOrange,
                    strokeWidth: 2.5,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _UnitAddressCard(
                      type: AddressUnitType.apartment,
                      entry: _unitAddresses[AddressUnitType.apartment],
                      isPrimary:
                          _primaryUnitType == AddressUnitType.apartment,
                      typeIcon: _iconForType(AddressUnitType.apartment),
                      typeColor: _colorForType(AddressUnitType.apartment),
                      onTap: () =>
                          _openMapPickerForUnit(AddressUnitType.apartment),
                      onSelectPrimary: () => setState(
                        () => _primaryUnitType = AddressUnitType.apartment,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _UnitAddressCard(
                      type: AddressUnitType.house,
                      entry: _unitAddresses[AddressUnitType.house],
                      isPrimary: _primaryUnitType == AddressUnitType.house,
                      typeIcon: _iconForType(AddressUnitType.house),
                      typeColor: _colorForType(AddressUnitType.house),
                      onTap: () =>
                          _openMapPickerForUnit(AddressUnitType.house),
                      onSelectPrimary: () => setState(
                        () => _primaryUnitType = AddressUnitType.house,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _UnitAddressCard(
                      type: AddressUnitType.office,
                      entry: _unitAddresses[AddressUnitType.office],
                      isPrimary: _primaryUnitType == AddressUnitType.office,
                      typeIcon: _iconForType(AddressUnitType.office),
                      typeColor: _colorForType(AddressUnitType.office),
                      onTap: () =>
                          _openMapPickerForUnit(AddressUnitType.office),
                      onSelectPrimary: () => setState(
                        () => _primaryUnitType = AddressUnitType.office,
                      ),
                    ),
                  ],
                ),
              ),

            if (hasPrimary && !_isLoading) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
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
                  child: Row(
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Dirección principal',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: textGray600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: categoryBgYellow,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _primaryUnitType.displayName,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: primaryOrange,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              primaryEntry?.address ?? '',
                              style: const TextStyle(
                                fontSize: 13,
                                color: textGray900,
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if ((primaryEntry?.plusCode ?? '')
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.pin_drop_outlined,
                                    size: 13,
                                    color: primaryOrange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    primaryEntry!.plusCode!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: textGray600,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          // ── SAVE BUTTON ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            child: GestureDetector(
              onTap: (_isSaving || _isLoading) ? null : _saveAddress,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                height: 56,
                decoration: BoxDecoration(
                  color: (_isSaving || _isLoading)
                      ? primaryOrange.withValues(alpha: 0.6)
                      : primaryOrange,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: (_isSaving || _isLoading)
                      ? []
                      : [
                          BoxShadow(
                            color: primaryOrange.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 7),
                          ),
                        ],
                ),
                child: _isSaving
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save_rounded,
                              color: Colors.white, size: 20),
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
            ),
          ),
        
        ],
        
      ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  UNIT ADDRESS CARD
// ─────────────────────────────────────────────
class _UnitAddressCard extends StatelessWidget {
  const _UnitAddressCard({
    required this.type,
    required this.entry,
    required this.isPrimary,
    required this.typeIcon,
    required this.typeColor,
    required this.onTap,
    required this.onSelectPrimary,
  });

  final AddressUnitType type;
  final ({
    String? address,
    double? lat,
    double? lng,
    String? countryCode,
    String? plusCode,
  })? entry;
  final bool isPrimary;
  final IconData typeIcon;
  final Color typeColor;
  final VoidCallback onTap;
  final VoidCallback onSelectPrimary;

  bool get _hasAddress => (entry?.address ?? '').trim().isNotEmpty;
  bool get _hasPlusCode => (entry?.plusCode ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isPrimary ? categoryBgYellow : backgroundWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isPrimary
                ? primaryOrange
                : borderGray100,
            width: isPrimary ? 2 : 1,
          ),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: primaryOrange.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── TYPE ICON ──
              Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(typeIcon, color: typeColor, size: 22),
                  ),
                  const SizedBox(height: 10),

                  // ── RADIO ──
                  GestureDetector(
                    onTap: onSelectPrimary,
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isPrimary
                              ? primaryOrange
                              : textGray600,
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
                  ),
                ],
              ),
              const SizedBox(width: 14),

              // ── CONTENT ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Text(
                          type.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: textGray900,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const Spacer(),
                        if (isPrimary)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
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
                          )
                        else if (_hasAddress)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: categoryBgGreen,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Configurada',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: categoryTextGreen,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: backgroundGray50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Sin configurar',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: textGray600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Address text
                    if (_hasAddress) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 14, color: primaryOrange),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              entry!.address!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: textGray600,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (_hasPlusCode) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.pin_drop_outlined,
                                size: 13, color: primaryOrange),
                            const SizedBox(width: 4),
                            Text(
                              entry!.plusCode!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: textGray600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ] else
                      Row(
                        children: [
                          const Icon(Icons.add_location_alt_outlined,
                              size: 14, color: primaryOrange),
                          const SizedBox(width: 6),
                          const Text(
                            'Toca para seleccionar en el mapa',
                            style: TextStyle(
                              fontSize: 12,
                              color: textGray600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),

                    // Edit button
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: _hasAddress
                            ? backgroundGray50
                            : categoryBgYellow,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _hasAddress
                              ? borderGray100
                              : primaryYellow,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _hasAddress
                                ? Icons.edit_location_alt_outlined
                                : Icons.map_outlined,
                            size: 14,
                            color: primaryOrange,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _hasAddress
                                ? 'Cambiar en el mapa'
                                : 'Abrir mapa',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: primaryOrange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}