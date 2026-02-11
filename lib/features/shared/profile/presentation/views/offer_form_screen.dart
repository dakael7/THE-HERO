import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../data/providers/repository_providers.dart';
import '../../../../../domain/entities/address.dart';
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

  const OfferFormScreen({super.key, this.initialOffer});

  @override
  ConsumerState<OfferFormScreen> createState() => _OfferFormScreenState();
}

class _OfferFormScreenState extends ConsumerState<OfferFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _weightController = TextEditingController();
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  static const _currency = 'CLP';
  String _category = 'Electrónicos';
  String _coverAsset = 'assets/logo_hero.png';
  Uint8List? _coverImageBytes;
  String? _coverImageFileName;
  final List<Uint8List> _additionalImageBytes = [];
  final List<String> _additionalImageFileNames = [];
  OfferCondition _condition = OfferCondition.newProduct;
  bool? _isInGoodState;
  bool? _worksCorrectly;
  bool _isSaving = false;
  bool _publishNow = false;
  String _weightUnit = 'kg';
  final String _placesApiKey = Env.placesApiKey;
  PickupSchedule? _pickupSchedule;
  bool _submitted = false;

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

  @override
  void initState() {
    super.initState();
    final offer = widget.initialOffer;
    if (offer != null) {
      _titleController.text = offer.title;
      _descriptionController.text = offer.description;
      _priceController.text = offer.price.toStringAsFixed(0);
      _stockController.text = offer.stock.toString();
      _weightController.text = offer.weight.toStringAsFixed(2);
      _category = offer.category;
      _condition = offer.condition;
      _isInGoodState = offer.isInGoodState;
      _worksCorrectly = offer.worksCorrectly;
      if (offer.coverImageUrl.isNotEmpty) {
        _coverAsset = offer.coverImageUrl;
      }
      _publishNow = offer.status == OfferStatus.active;

      _pickupSchedule = offer.pickupSchedule;

      // Prefill ubicación desde la oferta si existe snapshot
      final snapshot = offer.itemLocationSnapshot;
      if (snapshot != null) {
        _addressController.text = snapshot.fullAddress;
        _latController.text = snapshot.geopoint.latitude.toStringAsFixed(6);
        _lngController.text = snapshot.geopoint.longitude.toStringAsFixed(6);
      }
    }
  }

  Future<void> _pickAdditionalImages() async {
    try {
      final picked = await _imagePicker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked.isEmpty) return;

      final bytesList = <Uint8List>[];
      final namesList = <String>[];
      for (final file in picked) {
        bytesList.add(await file.readAsBytes());
        namesList.add(file.name);
      }

      if (!mounted) return;
      setState(() {
        _additionalImageBytes.addAll(bytesList);
        _additionalImageFileNames.addAll(namesList);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudieron seleccionar imágenes: $e'),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    }
  }

  Widget _buildAdditionalImagesPreview() {
    if (_additionalImageBytes.isEmpty) {
      return const Text(
        'Puedes agregar imágenes adicionales (opcional).',
        style: TextStyle(fontSize: 12, color: textGray600),
      );
    }

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _additionalImageBytes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 110,
                  height: 92,
                  color: borderGray100,
                  child: Image.memory(
                    _additionalImageBytes[index],
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: InkWell(
                  onTap: _isSaving
                      ? null
                      : () {
                          setState(() {
                            _additionalImageBytes.removeAt(index);
                            _additionalImageFileNames.removeAt(index);
                          });
                        },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCoverPreview() {
    if (_coverImageBytes != null) {
      return Image.memory(_coverImageBytes!, fit: BoxFit.cover);
    }

    final cover = _coverAsset.trim();
    if (cover.isEmpty) {
      return const Center(
        child: Icon(Icons.image, color: textGray600, size: 44),
      );
    }

    final isAsset = cover.startsWith('assets/');
    if (isAsset) {
      return Image.asset(cover, fit: BoxFit.cover);
    }

    return Image.network(
      cover,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return Image.asset('assets/logo_hero.png', fit: BoxFit.contain);
      },
    );
  }

  Future<void> _pickCoverImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
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
        SnackBar(
          content: Text('No se pudo seleccionar la imagen: $e'),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _weightController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

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
        _latController.text = result.latitude.toStringAsFixed(6);
        _lngController.text = result.longitude.toStringAsFixed(6);
      });
    }
  }

  List<String> _buildKeywords(String title, String category) {
    final parts = <String>[title.toLowerCase(), category.toLowerCase()];
    return parts;
  }

  Widget _buildYesNoOption({
    required String label,
    required bool selected,
    required bool yes,
    required VoidCallback onTap,
  }) {
    final borderColor = selected ? primaryOrange : borderGray100;
    final icon = yes ? Icons.check_circle_outline : Icons.cancel_outlined;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: backgroundWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 34, color: textGray600),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final userAsync = ref.read(profileProvider);
    if (!userAsync.hasValue || userAsync.value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes iniciar sesión para crear o editar ofertas'),
        ),
      );
      return;
    }
    final user = userAsync.value!;

    Address? _buildLocationSnapshot() {
      final addressText = _addressController.text.trim();
      if (addressText.isNotEmpty) {
        final lat = double.tryParse(_latController.text.trim());
        final lng = double.tryParse(_lngController.text.trim());

        if (_publishNow && (lat == null || lng == null)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ingresa latitud y longitud válidas para publicar'),
              backgroundColor: Color(0xFFDC2626),
              duration: Duration(seconds: 3),
            ),
          );
          return null;
        }

        if (lat != null && lng != null) {
          return Address(
            fullAddress: addressText,
            geopoint: GeoPoint(lat, lng),
            locationCheck: true,
          );
        }

        // Permitir guardar en borrador con geos vacíos (0,0)
        return Address(
          fullAddress: addressText,
          geopoint: const GeoPoint(0, 0),
          locationCheck: false,
        );
      }

      // fallback: dirección del usuario
      return user.address;
    }

    // Validar imagen de portada si se intenta publicar
    if (_publishNow) {
      if (_isInGoodState == null || _worksCorrectly == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Responde si está en buen estado y si funciona correctamente',
            ),
            backgroundColor: Color(0xFFDC2626),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      final hasCoverImage =
          _coverImageBytes != null ||
          (_coverAsset.trim().isNotEmpty &&
              _coverAsset != 'assets/logo_hero.png');

      if (!hasCoverImage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Debes agregar una imagen de portada para publicar la oferta',
            ),
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
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final stock = int.tryParse(_stockController.text.trim()) ?? 0;
    final weightInput = double.tryParse(_weightController.text.trim()) ?? 0.5;
    final weight = _weightUnit == 'g' ? (weightInput / 1000) : weightInput;

    // Mantener cantidad vendida al editar: reserved = stockInicial - disponible
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

    setState(() => _isSaving = true);
    try {
      final notifier = ref.read(offerNotifierProvider.notifier);

      final hasNewCover = _coverImageBytes != null;
      final hasNewAdditional = _additionalImageBytes.isNotEmpty;
      final coverImageUrl = hasNewCover ? '' : _coverAsset;
      final existingImageUrls = widget.initialOffer?.imageUrls ?? const <String>[];
      final initialImageUrls = isEdit
          ? <String>[...existingImageUrls]
          : (coverImageUrl.trim().isNotEmpty ? <String>[coverImageUrl] : <String>[]);

      final locationSnapshot = _buildLocationSnapshot();
      if (_publishNow && locationSnapshot == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Agrega una ubicación válida para publicar'),
            backgroundColor: Color(0xFFDC2626),
            duration: Duration(seconds: 3),
          ),
        );
        setState(() => _isSaving = false);
        return;
      }

      final offer = Offer(
        offerId: widget.initialOffer?.offerId ?? '',
        heroId: user.id,
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
        imageUrls: initialImageUrls,
        status: selectedStatus,
        searchKeywords: _buildKeywords(
          _titleController.text.trim(),
          _category,
        ),
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
      );

      if (isEdit) {
        final updated = await notifier.updateOffer(offer);
        if (hasNewCover) {
          final repo = ref.read(offersRepositoryProvider);
          final url = await repo.uploadOfferImage(
            heroId: user.id,
            offerId: updated.offerId,
            bytes: _coverImageBytes!,
            fileName: _coverImageFileName ?? 'cover.jpg',
          );

          final normalized = url.trim();
          final nextImageUrls = <String>{
            ...updated.imageUrls,
            ...existingImageUrls,
            if (normalized.isNotEmpty) normalized,
          }.toList();

          final oldCover = widget.initialOffer?.coverImageUrl.trim() ?? '';
          if (oldCover.isNotEmpty) {
            nextImageUrls.removeWhere((e) => e.trim() == oldCover);
          }

          await notifier.updateOffer(
            updated.copyWith(
              coverImageUrl: normalized,
              imageUrls: nextImageUrls,
            ),
          );
        }

        if (hasNewAdditional) {
          final repo = ref.read(offersRepositoryProvider);
          final urls = <String>[];
          for (var i = 0; i < _additionalImageBytes.length; i++) {
            final url = await repo.uploadOfferImage(
              heroId: user.id,
              offerId: updated.offerId,
              bytes: _additionalImageBytes[i],
              fileName: _additionalImageFileNames.elementAt(i),
            );
            urls.add(url);
          }

          await notifier.updateOffer(
            updated.copyWith(
              imageUrls: [...updated.imageUrls, ...urls],
            ),
          );
        }
      } else {
        final created = await notifier.createOffer(offer);
        if (hasNewCover) {
          final repo = ref.read(offersRepositoryProvider);
          final url = await repo.uploadOfferImage(
            heroId: user.id,
            offerId: created.offerId,
            bytes: _coverImageBytes!,
            fileName: _coverImageFileName ?? 'cover.jpg',
          );

          final normalized = url.trim();
          final nextImageUrls = <String>{
            ...created.imageUrls,
            if (normalized.isNotEmpty) normalized,
          }.toList();

          await notifier.updateOffer(
            created.copyWith(
              coverImageUrl: normalized,
              imageUrls: nextImageUrls,
            ),
          );
        }

        if (hasNewAdditional) {
          final repo = ref.read(offersRepositoryProvider);
          final urls = <String>[];
          for (var i = 0; i < _additionalImageBytes.length; i++) {
            final url = await repo.uploadOfferImage(
              heroId: user.id,
              offerId: created.offerId,
              bytes: _additionalImageBytes[i],
              fileName: _additionalImageFileNames.elementAt(i),
            );
            urls.add(url);
          }

          await notifier.updateOffer(
            created.copyWith(
              imageUrls: [...created.imageUrls, ...urls],
            ),
          );
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEdit ? 'Oferta actualizada' : 'Oferta creada'),
          duration: const Duration(milliseconds: 1500),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar: $e'),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialOffer != null;

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        title: Text(isEdit ? 'Editar oferta' : 'Crear oferta'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            autovalidateMode:
                _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle(title: 'Información básica'),
                _FormFieldWrapper(
                  label: 'Título',
                  child: TextFormField(
                    controller: _titleController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'Título del producto',
                      helperText: 'Sé claro y específico (mín. 4 caracteres)',
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
                _FormFieldWrapper(
                  label: 'Descripción',
                  child: TextFormField(
                    controller: _descriptionController,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Cuenta el estado y detalles relevantes',
                      helperText:
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
                const SizedBox(height: 4),
                const _SectionTitle(title: 'Inventario y estado'),
                Row(
                  children: [
                    Expanded(
                      child: _FormFieldWrapper(
                        label: 'Precio (CLP)',
                        child: TextFormField(
                          controller: _priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            prefixText: '\$',
                            hintText: '0',
                            helperText: 'Solo números, usa CLP',
                          ),
                          validator: (value) {
                            final parsed = double.tryParse(value ?? '');
                            if (parsed == null || parsed <= 0) {
                              return 'El precio debe ser mayor a 0';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FormFieldWrapper(
                        label: 'Stock',
                        child: TextFormField(
                          controller: _stockController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: false,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            hintText: '0',
                            helperText: 'Disponibles para la venta',
                          ),
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
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: _FormFieldWrapper(
                        label: 'Peso',
                        child: TextFormField(
                          controller: _weightController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            hintText: '0.5',
                            helperText: 'Peso del producto',
                          ),
                          validator: (value) {
                            final parsed = double.tryParse(value ?? '');
                            if (parsed == null || parsed <= 0) {
                              return 'Ingresa un peso válido';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 90,
                      child: _FormFieldWrapper(
                        label: 'Unidad',
                        child: DropdownButtonFormField<String>(
                          initialValue: _weightUnit,
                          items: const [
                            DropdownMenuItem(value: 'kg', child: Text('kg')),
                            DropdownMenuItem(value: 'g', child: Text('g')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _weightUnit = v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),

                const _SectionTitle(title: 'Ubicación del producto'),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: backgroundGray50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderGray100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Usaremos esta ubicación para calcular la tarifa y el retiro/envío.',
                        style: TextStyle(color: textGray700, fontSize: 12),
                      ),
                      if (_publishNow) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Requerido para publicar: dirección + latitud/longitud válidas.',
                          style: TextStyle(
                            color: Color(0xFFB45309),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isSaving ? null : _openMapPicker,
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('Elegir en mapa'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryOrange,
                              foregroundColor: backgroundWhite,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _isSaving
                                ? null
                                : () {
                                    final userAsync = ref.read(profileProvider);
                                    final user = userAsync.value;
                                    if (user?.address != null) {
                                      final addr = user!.address!;
                                      setState(() {
                                        _addressController.text =
                                            addr.fullAddress;
                                        _latController.text = addr
                                            .geopoint
                                            .latitude
                                            .toStringAsFixed(6);
                                        _lngController.text = addr
                                            .geopoint
                                            .longitude
                                            .toStringAsFixed(6);
                                      });
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'No tienes una dirección guardada en tu perfil',
                                          ),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                            icon: const Icon(Icons.home_outlined),
                            label: const Text('Usar dirección del perfil'),
                          ),
                          TextButton.icon(
                            onPressed: _isSaving
                                ? null
                                : () {
                                    setState(() {
                                      _addressController.clear();
                                      _latController.clear();
                                      _lngController.clear();
                                    });
                                  },
                            icon: const Icon(Icons.clear),
                            label: const Text('Limpiar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _FormFieldWrapper(
                        label: 'Dirección de retiro/envío',
                        child: TextFormField(
                          controller: _addressController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Dirección de retiro/envío',
                            helperText:
                                'Elige en el mapa o usa tu dirección guardada',
                          ),
                          validator: (value) {
                            if (_publishNow &&
                                (value == null || value.trim().isEmpty)) {
                              return 'Requerido para publicar';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                _FormFieldWrapper(
                  label: 'Categoría',
                  child: DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    items: _categories
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _category = val);
                    },
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '¿Está en buen estado?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textGray900,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildYesNoOption(
                      label: 'Sí',
                      selected: _isInGoodState == true,
                      yes: true,
                      onTap: _isSaving
                          ? () {}
                          : () {
                              setState(() => _isInGoodState = true);
                            },
                    ),
                    const SizedBox(width: 12),
                    _buildYesNoOption(
                      label: 'No',
                      selected: _isInGoodState == false,
                      yes: false,
                      onTap: _isSaving
                          ? () {}
                          : () {
                              setState(() => _isInGoodState = false);
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  '¿Funciona correctamente?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: textGray900,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildYesNoOption(
                      label: 'Sí',
                      selected: _worksCorrectly == true,
                      yes: true,
                      onTap: _isSaving
                          ? () {}
                          : () {
                              setState(() => _worksCorrectly = true);
                            },
                    ),
                    const SizedBox(width: 12),
                    _buildYesNoOption(
                      label: 'No',
                      selected: _worksCorrectly == false,
                      yes: false,
                      onTap: _isSaving
                          ? () {}
                          : () {
                              setState(() => _worksCorrectly = false);
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Pickup Schedule Section
                const _SectionTitle(title: 'Horarios de retiro'),
                if (_publishNow)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Recomendado: define horarios para evitar coordinaciones por chat.',
                      style: TextStyle(color: textGray700, fontSize: 12),
                    ),
                  ),
                PickupScheduleSelector(
                  initialSchedule: _pickupSchedule,
                  onChanged: (schedule) {
                    setState(() => _pickupSchedule = schedule);
                  },
                ),
                const SizedBox(height: 4),

                const _SectionTitle(title: 'Publicación'),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: backgroundWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderGray100),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile.adaptive(
                        value: _publishNow,
                        onChanged: (val) {
                          setState(() => _publishNow = val);
                        },
                        title: const Text(
                          'Publicar al guardar',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: textGray900,
                          ),
                        ),
                        subtitle: Text(
                          _publishNow
                              ? 'La oferta quedará visible (estado activo).'
                              : 'Se guardará como borrador (no visible).',
                          style: const TextStyle(color: textGray700, fontSize: 12),
                        ),
                        activeThumbColor: primaryOrange,
                        activeTrackColor: primaryOrange.withValues(alpha: 0.12),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_publishNow) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Para publicar necesitas:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: textGray900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 16, color: textGray600),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Imagen de portada',
                                style: TextStyle(color: textGray700, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 16, color: textGray600),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Ubicación válida (mapa o perfil)',
                                style: TextStyle(color: textGray700, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                size: 16, color: textGray600),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Confirmar estado y funcionamiento',
                                style: TextStyle(color: textGray700, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const _SectionTitle(title: 'Imágenes'),
                Row(
                  children: [
                    Expanded(
                      child: _FormFieldWrapper(
                        label: 'Moneda',
                        child: const Text('CLP'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _FormFieldWrapper(
                        label: 'Imagen',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: 110,
                                width: double.infinity,
                                color: borderGray100,
                                child: _buildCoverPreview(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _isSaving
                                        ? null
                                        : _pickCoverImage,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryOrange,
                                      foregroundColor: backgroundWhite,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      'Elegir',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_coverImageBytes != null) ...[
                                  const SizedBox(width: 10),
                                  TextButton(
                                    onPressed: _isSaving
                                        ? null
                                        : () {
                                            setState(() {
                                              _coverImageBytes = null;
                                              _coverImageFileName = null;
                                            });
                                          },
                                    child: const Text('Quitar'),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Imágenes adicionales',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: textGray900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildAdditionalImagesPreview(),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed:
                                    _isSaving ? null : _pickAdditionalImages,
                                icon: const Icon(Icons.add_photo_alternate),
                                label: const Text('Agregar imágenes'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryOrange,
                      foregroundColor: backgroundWhite,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: backgroundWhite,
                            ),
                          )
                        : Text(
                            _publishNow
                                ? (isEdit
                                    ? 'Guardar y publicar'
                                    : 'Crear y publicar')
                                : (isEdit ? 'Guardar cambios' : 'Guardar borrador'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w900,
          color: textGray900,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

class _FormFieldWrapper extends StatelessWidget {
  final String label;
  final Widget child;

  const _FormFieldWrapper({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
