import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/offer.dart';
import '../../../../../domain/entities/offer_status.dart';
import '../../../../../domain/entities/offer_condition.dart';
import '../../../../../features/offers/presentation/providers/offers_provider.dart';
import '../../../../../features/shared/profile/presentation/providers/profile_provider.dart';

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

  static const _currency = 'CLP';
  String _category = 'Electrónicos';
  String _coverAsset = 'assets/logo_hero.png';
  OfferCondition _condition = OfferCondition.newProduct;
  bool _isSaving = false;
  bool _publishNow = false;

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

  static const _coverAssets = <String>[
    'assets/logo_hero.png',
    'assets/logo_1.png',
    'assets/the.png',
    'assets/PAQUETE CAJA THE HERO.png',
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
      _category = offer.category;
      _condition = offer.condition;
      if (offer.coverImageUrl.isNotEmpty) {
        _coverAsset = offer.coverImageUrl;
      }
      _publishNow = offer.status == OfferStatus.active;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  String _buildKeywords(String title, String category) {
    final parts = <String>[
      title.toLowerCase(),
      category.toLowerCase(),
    ];
    return parts.join('|');
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

    if (!_formKey.currentState!.validate()) return;

    final isEdit = widget.initialOffer != null;
    final now = DateTime.now();
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final stock = int.tryParse(_stockController.text.trim()) ?? 0;

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

    final offer = Offer(
      offerId: widget.initialOffer?.offerId ?? '',
      heroId: user.id,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      category: _category,
      condition: _condition,
      price: price,
      currency: _currency,
      stock: stock,
      availableQty: availableQty,
      coverImageUrl: _coverAsset,
      imageUrls: [_coverAsset],
      status: selectedStatus,
      searchKeywords: _buildKeywords(
        _titleController.text.trim(),
        _category,
      ).split('|'),
      createdAt: widget.initialOffer?.createdAt ?? now,
      updatedAt: now,
      publishedAt: publishedAt,
      viewCount: widget.initialOffer?.viewCount ?? 0,
      orderCount: widget.initialOffer?.orderCount ?? 0,
    );

    setState(() => _isSaving = true);
    try {
      final notifier = ref.read(offerNotifierProvider.notifier);
      if (isEdit) {
        await notifier.updateOffer(offer);
      } else {
        await notifier.createOffer(offer);
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
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _FormFieldWrapper(
                label: 'Título',
                child: TextFormField(
                  controller: _titleController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    hintText: 'Ej: iPhone 13 Pro',
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
                  decoration: const InputDecoration(
                    hintText: 'Cuenta el estado y detalles relevantes',
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
              Row(
                children: [
                  Expanded(
                    child: _FormFieldWrapper(
                      label: 'Precio (CLP)',
                      child: TextFormField(
                        controller: _priceController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          prefixText: '\$',
                          hintText: '0',
                        ),
                        validator: (value) {
                          final parsed = double.tryParse(value ?? '');
                          if (parsed == null || parsed <= 0) {
                            return 'Ingresa un precio válido';
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
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: false),
                        decoration: const InputDecoration(
                          hintText: '0',
                        ),
                        validator: (value) {
                          final parsed = int.tryParse(value ?? '');
                          if (parsed == null || parsed < 0) {
                            return 'Stock inválido';
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
                      label: 'Categoría',
                      child: DropdownButtonFormField<String>(
                        value: _category,
                        isExpanded: true,
                        items: _categories
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _category = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FormFieldWrapper(
                      label: 'Estado del producto',
                      child: DropdownButtonFormField<OfferCondition>(
                        value: _condition,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: OfferCondition.newProduct,
                            child: Text('Nuevo'),
                          ),
                          DropdownMenuItem(
                            value: OfferCondition.excellent,
                            child: Text('Excelente estado'),
                          ),
                          DropdownMenuItem(
                            value: OfferCondition.good,
                            child: Text('Buen estado'),
                          ),
                          DropdownMenuItem(
                            value: OfferCondition.used,
                            child: Text('Usado'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _condition = val);
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
                      label: 'Moneda',
                      child: Text('CLP'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FormFieldWrapper(
                      label: 'Imagen (placeholder)',
                      child: DropdownButtonFormField<String>(
                        value: _coverAsset,
                        isExpanded: true,
                        items: _coverAssets
                            .map(
                              (asset) => DropdownMenuItem(
                                value: asset,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      margin: const EdgeInsets.only(right: 10),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: borderGray100,
                                      ),
                                      child: Image.asset(asset, fit: BoxFit.contain),
                                    ),
                                    Text(
                                      asset.split('/').last,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _coverAsset = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
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
                subtitle: const Text(
                  'Si está activado, la oferta quedará visible (estado activo).',
                  style: TextStyle(color: textGray700, fontSize: 12),
                ),
                activeColor: primaryOrange,
                contentPadding: EdgeInsets.zero,
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
                          isEdit ? 'Guardar cambios' : 'Crear oferta',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Las imágenes reales se habilitarán cuando Storage esté disponible (plan Blaze).',
                style: TextStyle(
                  fontSize: 12,
                  color: textGray600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormFieldWrapper extends StatelessWidget {
  final String label;
  final Widget child;

  const _FormFieldWrapper({
    required this.label,
    required this.child,
  });

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
