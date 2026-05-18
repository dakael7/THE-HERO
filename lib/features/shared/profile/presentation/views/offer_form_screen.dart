import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../../core/common/hero_header_app_bar.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/currency_input_formatter.dart';
import '../../../../../core/utils/price_parser.dart';
import '../../../../../data/providers/repository_providers.dart';
import '../../../../../domain/entities/address.dart';
import '../../../../../domain/entities/user.dart';
import '../../../../auth/presentation/views/unverified_email_screen.dart';
import '../../../../../domain/entities/offer.dart';
import '../../../../../domain/entities/offer_status.dart';
import '../../../../../domain/entities/offer_condition.dart';
import '../../../../../domain/entities/pickup_schedule.dart';
import '../../../../../features/offers/presentation/providers/offers_provider.dart';
import '../../../../../features/shared/profile/presentation/providers/profile_provider.dart';
import '../../../../../core/config/env.dart';
import 'location_picker_screen.dart';
import '../widgets/pickup_schedule_selector.dart';

class OfferFormScreen extends ConsumerStatefulWidget {
  final Offer? initialOffer;
  final bool? initialIsInGoodState;
  final bool? initialWorksCorrectly;
  final bool hideConditionQuestions;

  const OfferFormScreen({
    super.key,
    this.initialOffer,
    this.initialIsInGoodState,
    this.initialWorksCorrectly,
    this.hideConditionQuestions = false,
  });

  @override
  ConsumerState<OfferFormScreen> createState() => _OfferFormScreenState();
}

class _OfferFormScreenState extends ConsumerState<OfferFormScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _weightController = TextEditingController();
  final _addressController = TextEditingController();
  final _unitIdentifierController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  String? _countryCode;
  final ImagePicker _imagePicker = ImagePicker();

  bool _useAccountAddress = false;
  AddressSlot? _selectedAccountAddressSlot;
  String? _manualAddress;
  String? _manualUnitIdentifier;
  String? _manualPostalCode;
  String? _manualLat;
  String? _manualLng;
  String? _manualCountryCode;

  static const _currency = 'CLP';
  static final Uri _termsAndConditionsUri = Uri.parse(
    'https://theheroprojects.com/privacy-policy',
  );
  String _category = 'Electrónicos';
  String _coverAsset = '';
  Uint8List? _coverImageBytes;
  String? _coverImageFileName;
  final List<Uint8List> _additionalImageBytes = [];
  final List<String> _additionalImageFileNames = [];
  final List<String> _existingAdditionalImageUrls = [];
  int? _hoveredAdditionalIndex;
  OfferCondition _condition = OfferCondition.newProduct;
  bool? _isInGoodState;
  bool? _worksCorrectly;
  bool _isSaving = false;
  bool _publishNow = false;
  bool _acceptedTerms = false;
  String _weightUnit = 'kg';
  final String _placesApiKey = Env.placesApiKey;
  PickupSchedule? _pickupSchedule;
  bool _allowInPersonPickup = true;
  bool _submitted = false;

  // Animation controller for save button
  late AnimationController _saveButtonController;

  static const _categories = <String>[
    'Electrónicos',
    'Hogar',
    'Computación',
    'Ropa',
    'Deportes',
    'Libros y Cómics',
    'Herramientas y Bricolaje',
    'Mascotas',
    'Muebles',
    'Instrumentos',
    'Juguetes',
  ];

  String _normalizeImageKey(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('assets/')) return trimmed;
    Uri? uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return trimmed;
    }
    if (uri.scheme.isEmpty || uri.host.isEmpty) return trimmed;
    return uri.replace(query: '', fragment: '').toString();
  }

  @override
  void initState() {
    super.initState();
    _saveButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    final offer = widget.initialOffer;
    if (offer != null) {
      _titleController.text = offer.title;
      _descriptionController.text = offer.description;
      final cents = (offer.price * 100).round();
      _priceController.text = CurrencyInputFormatter().formatEditUpdate(
        const TextEditingValue(text: ''),
        TextEditingValue(text: cents.toString()),
      ).text;
      _stockController.text = offer.stock.toString();
      _weightController.text = offer.weight.toStringAsFixed(2);
      _category = offer.category;
      _condition = offer.condition;
      _isInGoodState = offer.isInGoodState;
      _worksCorrectly = offer.worksCorrectly;

      if (widget.initialIsInGoodState != null) {
        _isInGoodState = widget.initialIsInGoodState;
      }
      if (widget.initialWorksCorrectly != null) {
        _worksCorrectly = widget.initialWorksCorrectly;
      }
      if (offer.coverImageUrl.isNotEmpty) {
        _coverAsset = offer.coverImageUrl;
      }

      final coverTrimmed = offer.coverImageUrl.trim();
      final extras = <String>[];
      for (final raw in offer.imageUrls) {
        final url = raw.trim();
        if (url.isEmpty) continue;
        if (coverTrimmed.isNotEmpty && url == coverTrimmed) continue;
        extras.add(url);
      }
      _existingAdditionalImageUrls
        ..clear()
        ..addAll(extras);
      _publishNow = offer.status == OfferStatus.active;

      _pickupSchedule = offer.pickupSchedule;
      _allowInPersonPickup = offer.allowInPersonPickup;

      final snapshot = offer.itemLocationSnapshot;
      if (snapshot != null) {
        _addressController.text = snapshot.fullAddress;
        _unitIdentifierController.text = snapshot.unitIdentifier?.trim() ?? '';
        _postalCodeController.text = snapshot.postalCode?.trim() ?? '';
        _latController.text = snapshot.geopoint.latitude.toStringAsFixed(6);
        _lngController.text = snapshot.geopoint.longitude.toStringAsFixed(6);
        _countryCode = snapshot.countryCode;
      }
    } else {
      _priceController.text = '0,00';
      _isInGoodState = widget.initialIsInGoodState;
      _worksCorrectly = widget.initialWorksCorrectly;
      _allowInPersonPickup = true;
    }
  }

  @override
  void dispose() {
    _saveButtonController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _weightController.dispose();
    _addressController.dispose();
    _unitIdentifierController.dispose();
    _postalCodeController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  // ── IMAGE HELPERS ──────────────────────────────────────────────

  Widget _buildMainImagePreview() {
    final hoveredIndex = _hoveredAdditionalIndex;
    if (hoveredIndex != null &&
        hoveredIndex >= 0 &&
        hoveredIndex <
            (_additionalImageBytes.length +
                _existingAdditionalImageUrls.length)) {
      if (hoveredIndex < _additionalImageBytes.length) {
        return Image.memory(_additionalImageBytes[hoveredIndex],
            fit: BoxFit.cover);
      }
      final existingIndex = hoveredIndex - _additionalImageBytes.length;
      if (existingIndex >= 0 &&
          existingIndex < _existingAdditionalImageUrls.length) {
        final url = _existingAdditionalImageUrls[existingIndex].trim();
        if (url.isEmpty) return _buildCoverPreview();
        if (url.startsWith('assets/')) {
          return Image.asset(url, fit: BoxFit.cover);
        }
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Center(child: Icon(Icons.image, color: textGray600, size: 44)),
        );
      }
    }
    return _buildCoverPreview();
  }

  Widget _buildCoverPreview() {
    if (_coverImageBytes != null) {
      return Image.memory(_coverImageBytes!, fit: BoxFit.cover);
    }
    final cover = _coverAsset.trim();
    if (cover.isEmpty) {
      return Container(color: backgroundGray50);
    }
    if (cover.startsWith('assets/')) {
      return Image.asset(cover, fit: BoxFit.cover);
    }
    return Image.network(
      cover,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const Center(child: Icon(Icons.image, color: textGray600, size: 44)),
    );
  }

  Widget _buildGalleryThumb({required int index}) {
    final hasImage = index <
        (_additionalImageBytes.length + _existingAdditionalImageUrls.length);
    final selected = _hoveredAdditionalIndex == index;

    Widget imageContent;
    if (!hasImage) {
      imageContent = Container(
        decoration: BoxDecoration(
          color: backgroundGray50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderGray100),
        ),
        child: const Center(
          child: Icon(Icons.add_rounded, size: 22, color: textGray600),
        ),
      );
    } else if (index < _additionalImageBytes.length) {
      imageContent = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(_additionalImageBytes[index], fit: BoxFit.cover),
      );
    } else {
      final existingIndex = index - _additionalImageBytes.length;
      final url = _existingAdditionalImageUrls[existingIndex].trim();
      imageContent = ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: url.startsWith('assets/')
            ? Image.asset(url, fit: BoxFit.cover)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.image, color: textGray600, size: 44)),
              ),
      );
    }

    return MouseRegion(
      onEnter: (_) {
        if (!hasImage) return;
        setState(() => _hoveredAdditionalIndex = index);
      },
      onExit: (_) {
        if (!mounted) return;
        if (_hoveredAdditionalIndex == index) {
          setState(() => _hoveredAdditionalIndex = null);
        }
      },
      child: InkWell(
        onTap: _isSaving
            ? null
            : () {
                if (!hasImage) {
                  _pickAdditionalImages();
                  return;
                }
                setState(() => _hoveredAdditionalIndex = index);
              },
        onLongPress: (!_isSaving && hasImage)
            ? () {
                setState(() {
                  if (index < _additionalImageBytes.length) {
                    _additionalImageBytes.removeAt(index);
                    _additionalImageFileNames.removeAt(index);
                  } else {
                    final existingIndex = index - _additionalImageBytes.length;
                    if (existingIndex >= 0 &&
                        existingIndex < _existingAdditionalImageUrls.length) {
                      _existingAdditionalImageUrls.removeAt(existingIndex);
                    }
                  }
                  if (_hoveredAdditionalIndex == index) {
                    _hoveredAdditionalIndex = null;
                  }
                });
              }
            : null,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? primaryOrange : borderGray100,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: imageContent,
        ),
      ),
    );
  }

  Future<void> _pickAdditionalImages() async {
    try {
      final remaining = 4 - _additionalImageBytes.length;
      if (remaining <= 0) return;
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _additionalImageBytes.add(bytes);
        _additionalImageFileNames.add(picked.name);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron seleccionar imágenes: $e')),
      );
    }
  }

  Future<void> _pickCoverImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _coverImageBytes = bytes;
        _coverImageFileName = picked.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo seleccionar la imagen: $e')),
      );
    }
  }

  // ── MAP ────────────────────────────────────────────────────────

  Future<void> _openMapPicker() async {
    if (_placesApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falta configurar PLACES_API_KEY'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }
    final currentLat = double.tryParse(_latController.text.trim());
    final currentLng = double.tryParse(_lngController.text.trim());
    final result = await Navigator.of(context).push<MapLocationResult>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          apiKey: _placesApiKey,
          initialLatitude: currentLat,
          initialLongitude: currentLng,
          initialAddress: _addressController.text.trim().isNotEmpty
              ? _addressController.text.trim()
              : null,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _addressController.text = result.address;
        _unitIdentifierController.text = result.unitIdentifier?.trim() ?? '';
        _postalCodeController.text = result.postalCode?.trim() ?? '';
        _latController.text = result.latitude.toStringAsFixed(6);
        _lngController.text = result.longitude.toStringAsFixed(6);
        _countryCode = result.countryCode;
      });
    }
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

  void _setLocationFromAccountAddress(User user) {
    final addr = _resolveSelectedAccountAddress(user);
    if (addr == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tienes una dirección guardada en tu perfil'),
          duration: Duration(seconds: 2),
        ),
      );
      setState(() => _useAccountAddress = false);
      return;
    }

    setState(() {
      _addressController.text = addr.fullAddress;
      _unitIdentifierController.text = addr.unitIdentifier?.trim() ?? '';
      _postalCodeController.text = addr.postalCode?.trim() ?? '';
      _latController.text = addr.geopoint.latitude.toStringAsFixed(6);
      _lngController.text = addr.geopoint.longitude.toStringAsFixed(6);
      _countryCode = addr.countryCode;
    });
  }

  // ── SAVE ───────────────────────────────────────────────────────

  List<String> _buildKeywords(String title, String category) {
    return [title.toLowerCase(), category.toLowerCase()];
  }

  Address? _buildLocationSnapshot(User user) {
    final addressText = _addressController.text.trim();
    final unitId = _unitIdentifierController.text.trim();
    final postalCode = _postalCodeController.text.trim();

    if (addressText.isNotEmpty) {
      final lat = double.tryParse(_latController.text.trim());
      final lng = double.tryParse(_lngController.text.trim());
      final normalizedCountry = _countryCode?.trim();

      if (lat == null || lng == null) return null;
      if (normalizedCountry == null || normalizedCountry.isEmpty) return null;
      if (unitId.isEmpty) return null;
      if (postalCode.isEmpty) return null;

      return Address(
        fullAddress: addressText,
        geopoint: GeoPoint(lat, lng),
        locationCheck: true,
        countryCode: normalizedCountry,
        unitIdentifier: unitId.isNotEmpty ? unitId : null,
        postalCode: postalCode.isNotEmpty ? postalCode : null,
      );
    }

    final profileCountry = user.address?.countryCode?.trim();
    if (profileCountry == null || profileCountry.isEmpty) return null;
    return user.address;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      if (!_acceptedTerms) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Debes aceptar los Términos y Condiciones para guardar la oferta'),
            backgroundColor: Color(0xFFDC2626),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final userCached = ref.read(profileStreamProvider).value;
      final user = userCached ??
          await ref
              .read(profileStreamProvider.future)
              .timeout(const Duration(seconds: 3), onTimeout: () => null);

      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Debes iniciar sesión para crear o editar ofertas')),
        );
        return;
      }

      if (user.isSuspended) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tu cuenta está suspendida. No puedes crear o publicar ofertas en este momento.',
            ),
            backgroundColor: Color(0xFFDC2626),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      if (_publishNow) {
        final authUser = fb_auth.FirebaseAuth.instance.currentUser;
        final isEmailVerified = authUser?.emailVerified ?? false;
        if (!isEmailVerified || !user.contact.emailVerified) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Debes verificar tu correo para publicar una oferta'),
              duration: Duration(seconds: 3),
            ),
          );
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => UnverifiedEmailScreen(
                userRole: UserRole.hero,
                email: user.email,
              ),
            ),
          );
          return;
        }

        if (_isInGoodState == null || _worksCorrectly == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Responde si está en buen estado y si funciona correctamente'),
              backgroundColor: Color(0xFFDC2626),
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
        final hasCoverImage =
            _coverImageBytes != null || _coverAsset.trim().isNotEmpty;
        if (!hasCoverImage) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Debes agregar una imagen de portada para publicar la oferta'),
              backgroundColor: Color(0xFFDC2626),
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
      }

      setState(() => _submitted = true);
      if (!_formKey.currentState!.validate()) return;

      final isEdit = widget.initialOffer != null;
      final now = DateTime.now();
      final authUid = fb_auth.FirebaseAuth.instance.currentUser?.uid;
      final heroUid = (authUid != null && authUid.trim().isNotEmpty)
          ? authUid
          : user.id;
      const price = 0.0;
      final stock = int.tryParse(_stockController.text.trim()) ?? 0;
      final weightInput = parseLocalizedPrice(_weightController.text) ?? 0.5;
      final weight = _weightUnit == 'g' ? (weightInput / 1000) : weightInput;

      int availableQty = stock;
      if (isEdit) {
        final reserved =
            widget.initialOffer!.stock - widget.initialOffer!.availableQty;
        availableQty = stock - reserved;
        if (availableQty < 0) availableQty = 0;
      }

      final selectedStatus = isEdit
          ? (_publishNow ? OfferStatus.active : widget.initialOffer!.status)
          : (_publishNow ? OfferStatus.active : OfferStatus.draft);

      final publishedAt = selectedStatus == OfferStatus.active
          ? (widget.initialOffer?.publishedAt ?? now)
          : widget.initialOffer?.publishedAt;

      final notifier = ref.read(offerNotifierProvider.notifier);

      final hasNewCover = _coverImageBytes != null;
      final hasNewAdditional = _additionalImageBytes.isNotEmpty;
      final coverImageUrl = hasNewCover ? '' : _coverAsset;
      final preservedByKey = <String, String>{};
      final coverTrimmed = coverImageUrl.trim();
      if (coverTrimmed.isNotEmpty) {
        final key = _normalizeImageKey(coverTrimmed);
        if (key.isNotEmpty) preservedByKey[key] = coverTrimmed;
      }
      for (final raw in _existingAdditionalImageUrls) {
        final url = raw.trim();
        if (url.isEmpty) continue;
        final key = _normalizeImageKey(url);
        if (key.isEmpty) continue;
        preservedByKey.putIfAbsent(key, () => url);
      }
      final preservedImageUrls = preservedByKey.values.toList();

      final locationSnapshot = _buildLocationSnapshot(user);
      if (_publishNow && locationSnapshot == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Agrega una ubicación válida para publicar'),
            backgroundColor: Color(0xFFDC2626),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final offer = Offer(
        offerId: widget.initialOffer?.offerId ?? '',
        heroId: heroUid,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _category,
        condition: _condition,
        isInGoodState: _isInGoodState,
        worksCorrectly: _worksCorrectly,
        price: price,
        currency: _currency,
        stock: stock,
        availableQty: availableQty,
        weight: weight,
        coverImageUrl: coverImageUrl,
        imageUrls: preservedImageUrls,
        status: selectedStatus,
        searchKeywords: _buildKeywords(_titleController.text.trim(), _category),
        createdAt: widget.initialOffer?.createdAt ?? now,
        updatedAt: now,
        publishedAt: publishedAt,
        viewCount: widget.initialOffer?.viewCount ?? 0,
        orderCount: widget.initialOffer?.orderCount ?? 0,
        avgRating: widget.initialOffer?.avgRating ?? 0.0,
        ratingCount: widget.initialOffer?.ratingCount ?? 0,
        itemLocationId: widget.initialOffer?.itemLocationId,
        itemLocationSnapshot: locationSnapshot,
        pickupSchedule: _pickupSchedule,
        allowInPersonPickup: _allowInPersonPickup,
      );

      if (isEdit) {
        final updated = await notifier.updateOffer(offer);
        if (hasNewCover) {
          final repo = ref.read(offersRepositoryProvider);
          final url = await repo.uploadOfferImage(
            heroId: heroUid,
            offerId: updated.offerId,
            bytes: _coverImageBytes!,
            fileName: _coverImageFileName ?? 'cover.jpg',
          );
          final normalized = url.trim();
          final nextByKey = <String, String>{};
          for (final raw in updated.imageUrls) {
            final u = raw.trim();
            if (u.isEmpty) continue;
            final k = _normalizeImageKey(u);
            if (k.isEmpty) continue;
            nextByKey.putIfAbsent(k, () => u);
          }
          if (normalized.isNotEmpty) {
            final k = _normalizeImageKey(normalized);
            if (k.isNotEmpty) nextByKey[k] = normalized;
          }
          final nextImageUrls = nextByKey.values.toList();
          final oldCover = widget.initialOffer?.coverImageUrl.trim() ?? '';
          if (oldCover.isNotEmpty) {
            nextImageUrls.removeWhere((e) => e.trim() == oldCover);
          }
          await notifier.updateOffer(
            updated.copyWith(
                coverImageUrl: normalized, imageUrls: nextImageUrls),
          );
        }
        if (hasNewAdditional) {
          final repo = ref.read(offersRepositoryProvider);
          final urls = <String>[];
          for (var i = 0; i < _additionalImageBytes.length; i++) {
            final url = await repo.uploadOfferImage(
              heroId: heroUid,
              offerId: updated.offerId,
              bytes: _additionalImageBytes[i],
              fileName: _additionalImageFileNames.elementAt(i),
            );
            urls.add(url);
          }
          final nextByKey = <String, String>{};
          for (final raw in updated.imageUrls) {
            final u = raw.trim();
            if (u.isEmpty) continue;
            final k = _normalizeImageKey(u);
            if (k.isEmpty) continue;
            nextByKey.putIfAbsent(k, () => u);
          }
          for (final raw in urls) {
            final u = raw.trim();
            if (u.isEmpty) continue;
            final k = _normalizeImageKey(u);
            if (k.isEmpty) continue;
            nextByKey.putIfAbsent(k, () => u);
          }
          await notifier.updateOffer(
              updated.copyWith(imageUrls: nextByKey.values.toList()));
        }
      } else {
        final created = await notifier.createOffer(offer);
        var currentImageUrls = <String>[...preservedImageUrls];
        if (hasNewCover) {
          final repo = ref.read(offersRepositoryProvider);
          final url = await repo.uploadOfferImage(
            heroId: heroUid,
            offerId: created.offerId,
            bytes: _coverImageBytes!,
            fileName: _coverImageFileName ?? 'cover.jpg',
          );
          final normalized = url.trim();
          final nextByKey = <String, String>{};
          for (final raw in currentImageUrls) {
            final u = raw.trim();
            if (u.isEmpty) continue;
            final k = _normalizeImageKey(u);
            if (k.isEmpty) continue;
            nextByKey.putIfAbsent(k, () => u);
          }
          if (normalized.isNotEmpty) {
            final k = _normalizeImageKey(normalized);
            if (k.isNotEmpty) nextByKey[k] = normalized;
          }
          currentImageUrls = nextByKey.values.toList();
          await notifier.updateOffer(created.copyWith(
            coverImageUrl: normalized,
            imageUrls: currentImageUrls,
          ));
        }
        if (hasNewAdditional) {
          final repo = ref.read(offersRepositoryProvider);
          final urls = <String>[];
          for (var i = 0; i < _additionalImageBytes.length; i++) {
            final url = await repo.uploadOfferImage(
              heroId: heroUid,
              offerId: created.offerId,
              bytes: _additionalImageBytes[i],
              fileName: _additionalImageFileNames.elementAt(i),
            );
            urls.add(url);
          }
          final nextByKey = <String, String>{};
          for (final raw in currentImageUrls) {
            final u = raw.trim();
            if (u.isEmpty) continue;
            final k = _normalizeImageKey(u);
            if (k.isEmpty) continue;
            nextByKey.putIfAbsent(k, () => u);
          }
          for (final raw in urls) {
            final u = raw.trim();
            if (u.isEmpty) continue;
            final k = _normalizeImageKey(u);
            if (k.isEmpty) continue;
            nextByKey.putIfAbsent(k, () => u);
          }
          currentImageUrls = nextByKey.values.toList();
          await notifier.updateOffer(
              created.copyWith(imageUrls: currentImageUrls));
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Text(isEdit ? 'Oferta actualizada' : 'Oferta creada'),
            ],
          ),
          backgroundColor: const Color(0xFF16A34A),
          duration: const Duration(milliseconds: 1500),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: $e'),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialOffer != null;
    final hasCover =
        _coverImageBytes != null || _coverAsset.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: HeroHeaderAppBar(
        title: isEdit ? 'Editar oferta' : 'Nueva oferta',
        icon: Icons.add_box_rounded,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Form(
            key: _formKey,
            autovalidateMode: _submitted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── SECTION: IMÁGENES ──────────────────────
                _SectionHeader(
                    label: 'Imágenes', icon: Icons.photo_library_rounded),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: _buildImagesSection(hasCover),
                ),

                const SizedBox(height: 8),

                // ── SECTION: INFORMACIÓN BÁSICA ────────────
                _SectionHeader(
                    label: 'Información básica',
                    icon: Icons.info_rounded),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _FieldCard(
                        label: 'Título',
                        child: TextFormField(
                          controller: _titleController,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A)),
                          decoration: _inputDeco(
                            hint: 'Nombre del producto',
                            helper: 'Sé claro y específico (mín. 4 caracteres)',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'El título es obligatorio';
                            }
                            if (value.trim().length < 4) {
                              return 'Usa al menos 4 caracteres';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _FieldCard(
                        label: 'Descripción',
                        child: TextFormField(
                          controller: _descriptionController,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF333333),
                              height: 1.5),
                          decoration: _inputDeco(
                            hint: 'Describe el estado y detalles del artículo...',
                            helper:
                                'Incluye accesorios, fallas o uso (mín. 10 caracteres)',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'La descripción es obligatoria';
                            }
                            if (value.trim().length < 10) {
                              return 'Usa al menos 10 caracteres';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _FieldCard(
                        label: 'Categoría',
                        child: DropdownButtonFormField<String>(
                          value: _category,
                          isExpanded: true,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A)),
                          decoration: _inputDeco(hint: 'Selecciona una categoría'),
                          items: _categories
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c,
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _category = val);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ── SECTION: INVENTARIO ────────────────────
                _SectionHeader(
                    label: 'Inventario y estado',
                    icon: Icons.inventory_2_rounded),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _FieldCard(
                              label: 'Cantidad disponible',
                              child: TextFormField(
                                controller: _stockController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: false),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly
                                ],
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1A1A1A)),
                                decoration: _inputDeco(hint: '1'),
                                validator: (value) {
                                  final parsed = int.tryParse(value ?? '');
                                  if (parsed == null || parsed < 0) {
                                    return 'El stock debe ser 0 o mayor';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _FieldCard(
                              label: 'Peso',
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _weightController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      inputFormatters: [
                                        CurrencyInputFormatter()
                                      ],
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1A1A1A)),
                                      decoration:
                                          _inputDeco(hint: '0.5'),
                                      validator: (value) {
                                        final parsed =
                                            parseLocalizedPrice(value);
                                        if (parsed == null ||
                                            parsed <= 0) {
                                          return 'Peso inválido';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Weight unit toggle
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _weightUnit =
                                            _weightUnit == 'kg'
                                                ? 'g'
                                                : 'kg';
                                      });
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                          milliseconds: 200),
                                      padding: const EdgeInsets
                                          .symmetric(
                                          horizontal: 10,
                                          vertical: 6),
                                      decoration: BoxDecoration(
                                        color: primaryOrange,
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        _weightUnit,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Stock info card
                      _InfoCard(
                        color: primaryYellow.withOpacity(0.25),
                        borderColor: primaryYellow.withOpacity(0.55),
                        icon: Icons.info_outline_rounded,
                        iconColor: textGray900,
                        text:
                            '¿Tienes varios del mismo artículo?\n• Si quieres entregarlos todos juntos, deja la cantidad en 1\n• Si quieres ayudar a más personas, pon la cantidad que desees publicar (cada uno se entregará por separado)',
                        textColor: textGray600,
                      ),
                      const SizedBox(height: 10),
                      // Packaging warning
                      _InfoCard(
                        color: primaryOrangeLight.withOpacity(0.10),
                        borderColor: primaryOrange.withOpacity(0.35),
                        icon: Icons.inventory_2_outlined,
                        iconColor: textGray900,
                        title: '¡Importante!',
                        titleColor: textGray900,
                        text:
                            'Asegúrate de cubrir y proteger bien tu artículo con plástico de burbujas, papel o cartón para evitar que se rompa durante el envío. El rider solo transporta, no embala.',
                        textColor: textGray600,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ── SECTION: ESTADO ────────────────────────
                if (!widget.hideConditionQuestions) ...[
                  _SectionHeader(
                      label: 'Estado del artículo',
                      icon: Icons.checklist_rounded),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _ConditionQuestion(
                          question: '¿Está en buen estado?',
                          value: _isInGoodState,
                          onChanged: _isSaving
                              ? null
                              : (v) =>
                                  setState(() => _isInGoodState = v),
                        ),
                        const SizedBox(height: 12),
                        _ConditionQuestion(
                          question: '¿Funciona correctamente?',
                          value: _worksCorrectly,
                          onChanged: _isSaving
                              ? null
                              : (v) =>
                                  setState(() => _worksCorrectly = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // ── SECTION: UBICACIÓN ─────────────────────
                _SectionHeader(
                    label: 'Ubicación del producto',
                    icon: Icons.location_on_rounded),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildLocationSection(),
                ),

                const SizedBox(height: 8),

                // ── SECTION: HORARIOS ──────────────────────
                _SectionHeader(
                    label: 'Horarios de retiro',
                    icon: Icons.schedule_rounded),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (_publishNow)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _InfoCard(
                            color: primaryYellow.withOpacity(0.18),
                            borderColor: primaryYellow.withOpacity(0.50),
                            icon: Icons.tips_and_updates_outlined,
                            iconColor: textGray900,
                            text:
                                'Recomendado: define horarios para evitar coordinaciones por chat.',
                            textColor: textGray600,
                          ),
                        ),
                      PickupScheduleSelector(
                        initialSchedule: _pickupSchedule,
                        onChanged: (schedule) {
                          setState(() => _pickupSchedule = schedule);
                        },
                      ),
                      const SizedBox(height: 12),
                      // Allow in-person pickup toggle
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: backgroundWhite,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: borderGray100),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: SwitchListTile.adaptive(
                          value: _allowInPersonPickup,
                          onChanged: _isSaving
                              ? null
                              : (val) => setState(
                                  () => _allowInPersonPickup = val),
                          title: const Text(
                            'Permitir retiro en persona',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: textGray900,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            _allowInPersonPickup
                                ? 'Los compradores podrán coordinar retiro presencial.'
                                : 'Solo envío o retiro vía concierge (si aplica).',
                            style: const TextStyle(
                                color: textGray600, fontSize: 12),
                          ),
                          activeColor: primaryOrange,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // ── SECTION: PUBLICACIÓN ───────────────────
                _SectionHeader(
                    label: 'Publicación', icon: Icons.rocket_launch_rounded),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildPublicationSection(),
                ),

                const SizedBox(height: 12),

                // ── TERMS ──────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildTermsSection(),
                ),

                const SizedBox(height: 20),

                // ── SAVE BUTTON ────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  child: GestureDetector(
                    onTap: (_isSaving) ? null : _save,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: double.infinity,
                      height: 58,
                      decoration: BoxDecoration(
                        color: _isSaving
                            ? primaryOrange.withOpacity(0.6)
                            : _publishNow
                                ? primaryOrange
                                : textGray900,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: _isSaving
                            ? []
                            : [
                                BoxShadow(
                                  color: (_publishNow
                                          ? primaryOrange
                                          : textGray900)
                                      .withOpacity(0.30),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
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
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _publishNow
                                      ? Icons.rocket_launch_rounded
                                      : Icons.save_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _publishNow
                                      ? (isEdit
                                          ? 'Guardar y publicar'
                                          : 'Crear y publicar')
                                      : (isEdit
                                          ? 'Guardar cambios'
                                          : 'Guardar borrador'),
                                  style: const TextStyle(
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
        ),
      ),
    );
  }

  // ── SUBSECTION BUILDERS ────────────────────────────────────────

  Widget _buildImagesSection(bool hasCover) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: hasCover
                ? primaryOrange.withOpacity(0.4)
                : borderGray100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
              // Main cover preview
              Expanded(
                child: GestureDetector(
                  onTap: _isSaving ? null : _pickCoverImage,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 180,
                      color: backgroundGray50,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildMainImagePreview(),
                          if (!hasCover)
                            Container(
                              decoration: BoxDecoration(
                                color: textGray900.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: borderGray100,
                                    style: BorderStyle.solid),
                              ),
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_a_photo_rounded,
                                        size: 36,
                                        color: textGray600),
                                    SizedBox(height: 8),
                                    Text(
                                      'Toca para agregar\nportada',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: textGray600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (hasCover)
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: primaryOrange,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_rounded,
                                        color: Colors.white, size: 12),
                                    SizedBox(width: 4),
                                    Text(
                                      'Portada',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Gallery thumbnails 2x2
              SizedBox(
                width: 120,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: AspectRatio(
                                aspectRatio: 1,
                                child: _buildGalleryThumb(index: 0))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: AspectRatio(
                                aspectRatio: 1,
                                child: _buildGalleryThumb(index: 1))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                            child: AspectRatio(
                                aspectRatio: 1,
                                child: _buildGalleryThumb(index: 2))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: AspectRatio(
                                aspectRatio: 1,
                                child: _buildGalleryThumb(index: 3))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _isSaving ? null : _pickCoverImage,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: primaryOrange,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: primaryOrange.withOpacity(0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_rounded,
                            color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Tomar portada',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_coverImageBytes != null) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _isSaving
                      ? null
                      : () {
                          setState(() {
                            _coverImageBytes = null;
                            _coverImageFileName = null;
                          });
                        },
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: backgroundGray50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderGray100),
                    ),
                    child: const Center(
                      child: Text(
                        'Quitar',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: textGray600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Mantén presionado una imagen adicional para eliminarla',
            style: TextStyle(
                fontSize: 11,
                color: textGray600,
                fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection() {
    final hasAddress = _addressController.text.trim().isNotEmpty;
    final user = ref.watch(profileStreamProvider).value;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: hasAddress
                ? primaryOrange.withOpacity(0.4)
                : borderGray100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            value: _useAccountAddress,
            onChanged: _isSaving
                ? null
                : (val) {
                    if (val) {
                      _manualAddress = _addressController.text;
                      _manualUnitIdentifier = _unitIdentifierController.text;
                      _manualPostalCode = _postalCodeController.text;
                      _manualLat = _latController.text;
                      _manualLng = _lngController.text;
                      _manualCountryCode = _countryCode;

                      setState(() => _useAccountAddress = true);

                      if (user != null) {
                        if (_selectedAccountAddressSlot == null &&
                            user.addressSlots.isNotEmpty) {
                          _selectedAccountAddressSlot =
                              user.primaryAddressSlot ??
                                  user.addressSlots.keys.first;
                        }
                        _setLocationFromAccountAddress(user);
                      } else {
                        setState(() => _useAccountAddress = false);
                      }
                      return;
                    }

                    setState(() {
                      _useAccountAddress = false;
                      _addressController.text = _manualAddress ?? '';
                      _unitIdentifierController.text =
                          _manualUnitIdentifier ?? '';
                      _postalCodeController.text = _manualPostalCode ?? '';
                      _latController.text = _manualLat ?? '';
                      _lngController.text = _manualLng ?? '';
                      _countryCode = _manualCountryCode;
                    });
                  },
            contentPadding: EdgeInsets.zero,
            activeColor: primaryOrange,
            title: const Text(
              'Usar dirección de la cuenta',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: textGray900,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              (() {
                if (user == null) {
                  return 'No tienes una dirección guardada en tu cuenta.';
                }
                if (_useAccountAddress) {
                  final selected = _resolveSelectedAccountAddress(user);
                  return _formatSavedAddressLabel(
                    selected,
                    fallbackSlot: _selectedAccountAddressSlot,
                  );
                }
                if (user.address != null) {
                  return _formatSavedAddressLabel(user.address);
                }
                if (user.addressSlots.isNotEmpty) {
                  final firstSlot = user.addressSlots.keys.first;
                  final first = user.addressSlots.values.first;
                  return _formatSavedAddressLabel(
                    first,
                    fallbackSlot: firstSlot,
                  );
                }
                return 'No tienes una dirección guardada en tu cuenta.';
              })(),
              style: const TextStyle(
                fontSize: 12,
                color: textGray600,
                height: 1.25,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          if (_useAccountAddress &&
              (user?.addressSlots.isNotEmpty ?? false)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: user!.addressSlots.keys.map((slot) {
                final sel = _selectedAccountAddressSlot == slot;
                return GestureDetector(
                  onTap: _isSaving
                      ? null
                      : () {
                          setState(() => _selectedAccountAddressSlot = slot);
                          _setLocationFromAccountAddress(user);
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel
                          ? primaryOrange.withOpacity(0.10)
                          : backgroundWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: sel ? primaryOrange : const Color(0xFFE0E0E0),
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      slot.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: sel ? primaryOrange : textGray900,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          if (_useAccountAddress && user != null) ...[
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final selectedAddr = _resolveSelectedAccountAddress(user);
                final slot = _selectedAccountAddressSlot ??
                    user.primaryAddressSlot;
                final title = _formatSavedAddressLabel(
                  selectedAddr,
                  fallbackSlot: slot,
                );
                final fullAddress = selectedAddr?.fullAddress.trim();
                final unitLine = selectedAddr?.unitIdentifier?.trim();

                if (title.trim().isEmpty &&
                    (fullAddress == null || fullAddress.isEmpty) &&
                    (unitLine == null || unitLine.isEmpty)) {
                  return const SizedBox.shrink();
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: primaryOrange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        size: 16,
                        color: primaryOrange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                          if (unitLine != null && unitLine.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: backgroundGray50,
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0xFFECECEC)),
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
                );
              },
            ),
          ],

          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  fit: FlexFit.loose,
                  child: _ActionButton(
                    label: 'Elegir en mapa',
                    icon: Icons.map_rounded,
                    color: primaryOrange,
                    onTap:
                        (_isSaving || _useAccountAddress) ? null : _openMapPicker,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  fit: FlexFit.loose,
                  child: _ActionButton(
                    label: 'Usar mi dirección',
                    icon: Icons.home_rounded,
                    color: primaryOrange,
                    onTap: _isSaving
                        ? null
                        : () {
                            final userAsync = ref.read(profileStreamProvider);
                            final user = userAsync.value;
                            if (user == null) return;

                            _manualAddress = _addressController.text;
                            _manualUnitIdentifier = _unitIdentifierController.text;
                            _manualPostalCode = _postalCodeController.text;
                            _manualLat = _latController.text;
                            _manualLng = _lngController.text;
                            _manualCountryCode = _countryCode;

                            setState(() => _useAccountAddress = true);
                            if (_selectedAccountAddressSlot == null &&
                                user.addressSlots.isNotEmpty) {
                              _selectedAccountAddressSlot =
                                  user.primaryAddressSlot ??
                                      user.addressSlots.keys.first;
                            }
                            _setLocationFromAccountAddress(user);
                          },
                  ),
                ),
              ],
            ),
          ),

          if (hasAddress) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _isSaving
                  ? null
                  : () {
                      setState(() {
                        _addressController.clear();
                        _unitIdentifierController.clear();
                        _postalCodeController.clear();
                        _latController.clear();
                        _lngController.clear();
                        _countryCode = null;
                      });
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: backgroundGray50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderGray100),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.clear_rounded,
                        size: 14, color: textGray600),
                    SizedBox(width: 6),
                    Text(
                      'Limpiar ubicación',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: textGray600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Address field (hidden but functional)
          TextFormField(
            controller: _addressController,
            textInputAction: TextInputAction.next,
            readOnly: true,
            showCursor: false,
            enableInteractiveSelection: false,
            onTap: _isSaving ? null : _openMapPicker,
            style: const TextStyle(fontSize: 13, color: textGray600),
            decoration: _inputDeco(
              hint: 'Dirección de retiro/envío',
              helper: 'Elige en el mapa o usa tu dirección guardada',
            ),
            validator: (value) {
              if (_publishNow && (value == null || value.trim().isEmpty)) {
                return 'Requerido para publicar';
              }
              return null;
            },
          ),

          const SizedBox(height: 10),
          TextFormField(
            controller: _unitIdentifierController,
            textInputAction: TextInputAction.next,
            enabled: !_isSaving,
            style: const TextStyle(fontSize: 13, color: textGray600),
            decoration: _inputDeco(
              hint: 'Dpto./Casa/Oficina/Condominio',
              helper: 'Requerido',
            ),
            validator: (value) {
              final needs = _addressController.text.trim().isNotEmpty;
              if (!needs) return null;
              if (value == null || value.trim().isEmpty) {
                return 'Requerido';
              }
              return null;
            },
          ),

          const SizedBox(height: 10),
          TextFormField(
            controller: _postalCodeController,
            textInputAction: TextInputAction.done,
            enabled: !_isSaving,
            keyboardType: TextInputType.text,
            style: const TextStyle(fontSize: 13, color: textGray600),
            decoration: _inputDeco(
              hint: 'Código Postal',
              helper: 'Requerido',
            ),
            validator: (value) {
              final needs = _addressController.text.trim().isNotEmpty;
              if (!needs) return null;
              if (value == null || value.trim().isEmpty) {
                return 'Requerido';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPublicationSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: _publishNow
                ? primaryOrange.withOpacity(0.4)
                : borderGray100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            value: _publishNow,
            onChanged: (val) {
              setState(() {
                _publishNow = val;
                if (_publishNow) _acceptedTerms = false;
              });
            },
            title: const Text(
              'Publicar al guardar',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: textGray900,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              _publishNow
                  ? 'La oferta quedará visible (estado activo).'
                  : 'Se guardará como borrador (no visible).',
              style: const TextStyle(color: textGray600, fontSize: 12),
            ),
            activeColor: primaryOrange,
            contentPadding: EdgeInsets.zero,
          ),
          if (_publishNow) ...[
            const Divider(height: 1, color: borderGray100),
            const SizedBox(height: 14),
            const Text(
              'Para publicar necesitas:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 10),
            ...[
              ('Imagen de portada',
                  _coverImageBytes != null || _coverAsset.trim().isNotEmpty),
              ('Ubicación válida (mapa o perfil)',
                  _addressController.text.trim().isNotEmpty),
              ('Estado y funcionamiento confirmados',
                  _isInGoodState != null && _worksCorrectly != null),
            ].map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: item.$2
                            ? primaryOrange
                            : backgroundGray50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item.$2
                            ? Icons.check_rounded
                            : Icons.remove_rounded,
                        color: item.$2
                            ? Colors.white
                            : textGray600,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      item.$1,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: item.$2
                            ? textGray900
                            : textGray600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTermsSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            value: _acceptedTerms,
            onChanged: _isSaving
                ? null
                : (value) =>
                    setState(() => _acceptedTerms = value ?? false),
            activeColor: primaryOrange,
            checkColor: Colors.white,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Acepto los ',
                  style: TextStyle(
                    color: textGray600,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                GestureDetector(
                  onTap: _isSaving
                      ? null
                      : () async {
                          await launchUrl(
                            _termsAndConditionsUri,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                  child: const Text(
                    'Términos y Condiciones',
                    style: TextStyle(
                      color: primaryOrange,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_acceptedTerms)
            Padding(
              padding: const EdgeInsets.only(left: 40, bottom: 8),
              child: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded,
                      size: 14, color: textGray600),
                  SizedBox(width: 6),
                  Text(
                    'Requerido para guardar.',
                    style: TextStyle(
                      color: textGray600,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco({String? hint, String? helper}) {
    return InputDecoration(
      hintText: hint,
      helperText: helper,
      hintStyle: TextStyle(
        color: textGray600.withOpacity(0.45),
        fontSize: 14,
      ),
      helperStyle:
          TextStyle(color: textGray600.withOpacity(0.7), fontSize: 11, height: 1.3),
      filled: true,
      fillColor: backgroundWhite,
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
        borderSide: const BorderSide(color: primaryOrange, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: Color(0xFFDC2626), width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: Color(0xFFDC2626), width: 2),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  SHARED WIDGETS
// ─────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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
          Icon(icon, size: 18, color: textGray900),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1A1A1A),
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldCard extends StatelessWidget {
  final String label;
  final Widget child;

  const _FieldCard({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String? title;
  final Color? titleColor;
  final String text;
  final Color textColor;

  const _InfoCard({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    this.title,
    this.titleColor,
    required this.text,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  text,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
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

class _ConditionQuestion extends StatelessWidget {
  final String question;
  final bool? value;
  final ValueChanged<bool?>? onChanged;

  const _ConditionQuestion({
    required this.question,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _YesNoTile(
                  label: 'Sí',
                  yes: true,
                  selected: value == true,
                  onTap: onChanged == null ? null : () => onChanged!(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _YesNoTile(
                  label: 'No',
                  yes: false,
                  selected: value == false,
                  onTap: onChanged == null ? null : () => onChanged!(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _YesNoTile extends StatelessWidget {
  final String label;
  final bool yes;
  final bool selected;
  final VoidCallback? onTap;

  const _YesNoTile({
    required this.label,
    required this.yes,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor =
        yes ? const Color(0xFF10B981) : const Color(0xFFDC2626);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withOpacity(0.08)
              : const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accentColor : const Color(0xFFE0E0E0),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              yes ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 30,
              color: selected ? accentColor : const Color(0xFFCCCCCC),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: selected ? accentColor : const Color(0xFF999999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 17),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
