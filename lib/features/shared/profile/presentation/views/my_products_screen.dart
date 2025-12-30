import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../data/providers/repository_providers.dart';
import '../../../../offers/presentation/providers/offers_provider.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../../../domain/entities/offer.dart';
import '../../../../../domain/entities/offer_status.dart';
import '../../../../hero/presentation/viewmodels/hero_home_viewmodel.dart';

class MyProductsScreen extends ConsumerStatefulWidget {
  const MyProductsScreen({super.key});

  @override
  ConsumerState<MyProductsScreen> createState() => _MyProductsScreenState();
}

class _MyProductsScreenState extends ConsumerState<MyProductsScreen> {
  final TextEditingController _searchController = TextEditingController();
  OfferStatus? _statusFilter;
  final Set<String> _busyOfferIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _statusTextColor(OfferStatus status) {
    switch (status) {
      case OfferStatus.active:
        return const Color(0xFF0F766E);
      case OfferStatus.draft:
        return const Color(0xFF7C3AED);
      case OfferStatus.paused:
        return const Color(0xFFB45309);
      case OfferStatus.soldOut:
        return const Color(0xFFDC2626);
      case OfferStatus.archived:
        return textGray600;
    }
  }

  Color _statusBgColor(OfferStatus status) {
    switch (status) {
      case OfferStatus.active:
        return const Color(0xFFCCFBF1);
      case OfferStatus.draft:
        return const Color(0xFFEDE9FE);
      case OfferStatus.paused:
        return const Color(0xFFFFEDD5);
      case OfferStatus.soldOut:
        return const Color(0xFFFEE2E2);
      case OfferStatus.archived:
        return borderGray100;
    }
  }

  List<Offer> _applyFilters(List<Offer> offers) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = offers.where((offer) {
      final matchesStatus = _statusFilter == null || offer.status == _statusFilter;
      if (!matchesStatus) return false;

      if (query.isEmpty) return true;
      return offer.title.toLowerCase().contains(query) ||
          offer.category.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  Widget _buildStatPill({
    required String label,
    required int value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: textGray900,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textGray700,
            ),
          ),
        ],
      ),
    );
  }

  void _showComingSoon(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  Future<bool> _confirmAction({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryOrange,
                foregroundColor: backgroundWhite,
              ),
              child: Text(confirmText),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<void> _setOfferStatus({
    required BuildContext context,
    required Offer offer,
    required String status,
    required String successMessage,
  }) async {
    if (_busyOfferIds.contains(offer.offerId)) return;

    setState(() => _busyOfferIds.add(offer.offerId));
    try {
      await ref
          .read(offersRepositoryProvider)
          .updateOfferStatus(offer.offerId, status);
      if (!mounted) return;

      ref.invalidate(myOffersProvider(offer.heroId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          duration: const Duration(milliseconds: 1600),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar el estado: $e'),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyOfferIds.remove(offer.offerId));
      }
    }
  }

  Widget _buildSearchBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
        boxShadow: [
          BoxShadow(
            color: textGray900.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: InputBorder.none,
          hintText: 'Buscar por nombre o categoría',
          hintStyle: TextStyle(
            color: textGray600.withOpacity(0.9),
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: const Icon(Icons.search, color: textGray600),
          suffixIcon: _searchController.text.trim().isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpiar',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close, color: textGray600),
                ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context, List<Offer> offers) {
    final activeCount = offers.where((o) => o.status == OfferStatus.active).length;
    final draftCount = offers.where((o) => o.status == OfferStatus.draft).length;
    final pausedCount = offers.where((o) => o.status == OfferStatus.paused).length;
    final soldOutCount = offers.where((o) => o.status == OfferStatus.soldOut).length;
    final archivedCount = offers.where((o) => o.status == OfferStatus.archived).length;

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onSelected,
    }) {
      return ChoiceChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => onSelected(),
        selectedColor: primaryOrange.withOpacity(0.18),
        backgroundColor: backgroundWhite,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: selected ? primaryOrange : textGray700,
        ),
        side: BorderSide(
          color: selected ? primaryOrange.withOpacity(0.35) : borderGray100,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          chip(
            label: 'Todos (${offers.length})',
            selected: _statusFilter == null,
            onSelected: () => setState(() => _statusFilter = null),
          ),
          const SizedBox(width: 8),
          chip(
            label: 'Activos ($activeCount)',
            selected: _statusFilter == OfferStatus.active,
            onSelected: () => setState(() => _statusFilter = OfferStatus.active),
          ),
          const SizedBox(width: 8),
          chip(
            label: 'Borradores ($draftCount)',
            selected: _statusFilter == OfferStatus.draft,
            onSelected: () => setState(() => _statusFilter = OfferStatus.draft),
          ),
          const SizedBox(width: 8),
          chip(
            label: 'Pausados ($pausedCount)',
            selected: _statusFilter == OfferStatus.paused,
            onSelected: () => setState(() => _statusFilter = OfferStatus.paused),
          ),
          const SizedBox(width: 8),
          chip(
            label: 'Agotados ($soldOutCount)',
            selected: _statusFilter == OfferStatus.soldOut,
            onSelected: () => setState(() => _statusFilter = OfferStatus.soldOut),
          ),
          const SizedBox(width: 8),
          chip(
            label: 'Archivados ($archivedCount)',
            selected: _statusFilter == OfferStatus.archived,
            onSelected: () => setState(() => _statusFilter = OfferStatus.archived),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildOfferCard(BuildContext context, Offer offer) {
    final statusTextColor = _statusTextColor(offer.status);
    final statusBg = _statusBgColor(offer.status);

    final isBusy = _busyOfferIds.contains(offer.offerId);

    final hasImage = offer.coverImageUrl.trim().isNotEmpty;
    final currency = offer.currency.trim().isEmpty ? 'CLP' : offer.currency.trim();

    return Material(
      color: backgroundWhite,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _showComingSoon(context, 'Detalle del producto próximamente'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderGray100),
            boxShadow: [
              BoxShadow(
                color: textGray900.withOpacity(0.05),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 78,
                  height: 78,
                  color: borderGray100,
                  child: hasImage
                      ? Image.network(
                          offer.coverImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: textGray600,
                              ),
                            );
                          },
                        )
                      : const Center(
                          child: Icon(
                            Icons.image_outlined,
                            color: textGray600,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            offer.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: textGray900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (isBusy)
                          const SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: primaryOrange,
                                ),
                              ),
                            ),
                          )
                        else
                          PopupMenuButton<String>(
                            tooltip: 'Acciones',
                            onSelected: (value) async {
                              switch (value) {
                                case 'edit':
                                  _showComingSoon(
                                    context,
                                    'Editar producto próximamente',
                                  );
                                  break;
                                case 'activate':
                                  await _setOfferStatus(
                                    context: context,
                                    offer: offer,
                                    status: 'active',
                                    successMessage: 'Publicación activada',
                                  );
                                  break;
                                case 'pause':
                                  await _setOfferStatus(
                                    context: context,
                                    offer: offer,
                                    status: 'paused',
                                    successMessage: 'Publicación pausada',
                                  );
                                  break;
                                case 'archive':
                                  final confirmed = await _confirmAction(
                                    context: context,
                                    title: 'Archivar publicación',
                                    message:
                                        'Tu producto dejará de estar visible para los clientes. Puedes reactivarlo cuando quieras.',
                                    confirmText: 'Archivar',
                                  );
                                  if (!confirmed) return;
                                  await _setOfferStatus(
                                    context: context,
                                    offer: offer,
                                    status: 'archived',
                                    successMessage: 'Publicación archivada',
                                  );
                                  break;
                              }
                            },
                            itemBuilder: (context) {
                              final items = <PopupMenuEntry<String>>[];

                              if (offer.canBeEdited) {
                                items.add(
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Editar'),
                                  ),
                                );
                              }

                              if (offer.status != OfferStatus.active) {
                                items.add(
                                  const PopupMenuItem(
                                    value: 'activate',
                                    child: Text('Activar'),
                                  ),
                                );
                              }

                              if (offer.status == OfferStatus.active) {
                                items.add(
                                  const PopupMenuItem(
                                    value: 'pause',
                                    child: Text('Pausar'),
                                  ),
                                );
                              }

                              if (offer.status != OfferStatus.archived) {
                                items.add(
                                  const PopupMenuItem(
                                    value: 'archive',
                                    child: Text('Archivar'),
                                  ),
                                );
                              }

                              return items;
                            },
                            icon: const Icon(
                              Icons.more_horiz,
                              color: textGray600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            offer.status.displayName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: statusTextColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: backgroundGray50,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            offer.category,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: textGray700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '\$${offer.price.toStringAsFixed(0)} $currency',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: primaryOrange,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 16,
                              color: textGray600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${offer.availableQty}/${offer.stock}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: textGray700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.visibility_outlined,
                          size: 16,
                          color: textGray600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${offer.viewCount}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textGray600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.shopping_bag_outlined,
                          size: 16,
                          color: textGray600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${offer.orderCount}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textGray600,
                          ),
                        ),
                      ],
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

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            ref.read(heroHomeViewModelProvider.notifier).selectNavItem(0);
          },
        ),
        title: const Text(
          'Mis productos',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: primaryOrange, size: 46),
                  const SizedBox(height: 12),
                  const Text(
                    'No pudimos cargar tu perfil',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: textGray900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    error.toString(),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: textGray600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
        data: (user) {
          if (user == null) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      color: primaryOrange,
                      size: 46,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Inicia sesión para ver tus productos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Necesitas una cuenta para administrar tus publicaciones.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textGray600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final offersAsync = ref.watch(myOffersProvider(user.id));
          return offersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.wifi_off_outlined,
                        color: primaryOrange,
                        size: 46,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No pudimos cargar tus productos',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: textGray900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        error.toString(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textGray600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: () {
                          ref.invalidate(myOffersProvider(user.id));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryOrange,
                          foregroundColor: backgroundWhite,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Reintentar',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            data: (offers) {
              final filtered = _applyFilters(offers);

              final activeCount = offers
                  .where((o) => o.status == OfferStatus.active)
                  .length;
              final draftCount = offers
                  .where((o) => o.status == OfferStatus.draft)
                  .length;
              final soldOutCount = offers
                  .where((o) => o.status == OfferStatus.soldOut)
                  .length;

              return RefreshIndicator(
                color: primaryOrange,
                onRefresh: () async {
                  ref.invalidate(myOffersProvider(user.id));
                  await Future<void>.delayed(const Duration(milliseconds: 250));
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final maxWidth = constraints.maxWidth;
                            final scale =
                                (maxWidth / 390.0).clamp(0.78, 1.20).toDouble();
                            final cardHeight = (maxWidth * 0.52)
                                .clamp(170.0, 210.0)
                                .toDouble();
                            final wheelSize = (maxWidth * 0.88)
                                .clamp(210.0, 320.0)
                                .toDouble();
                            final contentRightPadding = (maxWidth * 0.42)
                                .clamp(92.0, 165.0)
                                .toDouble();

                            final cardPadding = (24.0 * scale)
                                .clamp(14.0, 24.0)
                                .toDouble();
                            final titleSize =
                                (18.0 * scale).clamp(16.0, 22.0).toDouble();
                            final subtitleSize = (14.0 * scale)
                                .clamp(12.0, 18.0)
                                .toDouble();
                            final buttonFontSize = (14.0 * scale)
                                .clamp(12.0, 16.0)
                                .toDouble();
                            final buttonIconSize = (20.0 * scale)
                                .clamp(18.0, 22.0)
                                .toDouble();
                            final gapSmall =
                                (8.0 * scale).clamp(6.0, 10.0).toDouble();
                            final gapNormal =
                                (16.0 * scale).clamp(10.0, 16.0).toDouble();
                            final buttonHPadding = (20.0 * scale)
                                .clamp(14.0, 20.0)
                                .toDouble();
                            final buttonVPadding = (12.0 * scale)
                                .clamp(10.0, 14.0)
                                .toDouble();

                            final contentAvailableWidth = (maxWidth -
                                    (cardPadding * 2) -
                                    contentRightPadding)
                                .clamp(120.0, 520.0)
                                .toDouble();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        primaryOrange,
                                        primaryYellow.withOpacity(0.95),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primaryOrange.withOpacity(0.22),
                                        blurRadius: 18,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(22),
                                    child: SizedBox(
                                      height: cardHeight,
                                      child: Stack(
                                        clipBehavior: Clip.hardEdge,
                                        children: [
                                          Positioned(
                                            right: -wheelSize * 0.22,
                                            bottom: -wheelSize * 0.26,
                                            child: IgnorePointer(
                                              child: Opacity(
                                                opacity: 0.95,
                                                child: Transform.rotate(
                                                  angle: -0.22,
                                                  child: Image.asset(
                                                    'assets/wheel.png',
                                                    width: wheelSize,
                                                    height: wheelSize,
                                                    fit: BoxFit.contain,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: EdgeInsets.all(cardPadding),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Padding(
                                                    padding: EdgeInsets.only(
                                                      right: contentRightPadding,
                                                    ),
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment: Alignment.centerLeft,
                                                      child: SizedBox(
                                                        width: contentAvailableWidth,
                                                        child: Column(
                                                          mainAxisSize: MainAxisSize.min,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              'Tu vitrina',
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: TextStyle(
                                                                color: backgroundWhite,
                                                                fontSize: titleSize,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                            SizedBox(height: gapSmall),
                                                            Text(
                                                              'Administra stock, precios y visibilidad',
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: TextStyle(
                                                                color: backgroundWhite
                                                                    .withOpacity(0.92),
                                                                fontSize: subtitleSize,
                                                              ),
                                                            ),
                                                            SizedBox(height: gapNormal),
                                                            ElevatedButton.icon(
                                                              onPressed: () {
                                                                _showComingSoon(
                                                                  context,
                                                                  'Publicación de productos próximamente',
                                                                );
                                                              },
                                                              icon: Icon(
                                                                Icons.add_circle_outline,
                                                                color: primaryOrange,
                                                                size: buttonIconSize,
                                                              ),
                                                              label: Text(
                                                                'Publicar producto',
                                                                style: TextStyle(
                                                                  color: primaryOrange,
                                                                  fontSize: buttonFontSize,
                                                                  fontWeight: FontWeight.w700,
                                                                ),
                                                              ),
                                                              style:
                                                                  ElevatedButton.styleFrom(
                                                                backgroundColor: backgroundWhite,
                                                                padding:
                                                                    EdgeInsets.symmetric(
                                                                  horizontal: buttonHPadding,
                                                                  vertical: buttonVPadding,
                                                                ),
                                                                shape:
                                                                    RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(12),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _buildStatPill(
                                      label: 'Activos',
                                      value: activeCount,
                                      color: const Color(0xFF0F766E),
                                    ),
                                    _buildStatPill(
                                      label: 'Borradores',
                                      value: draftCount,
                                      color: const Color(0xFF7C3AED),
                                    ),
                                    _buildStatPill(
                                      label: 'Agotados',
                                      value: soldOutCount,
                                      color: const Color(0xFFDC2626),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tus publicaciones',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: textGray900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildSearchBar(context),
                            _buildFilterChips(context, offers),
                          ],
                        ),
                      ),
                    ),
                    if (offers.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: primaryOrange.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: const Icon(
                                    Icons.shopping_bag_outlined,
                                    size: 36,
                                    color: primaryOrange,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'Aún no tienes productos publicados',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: textGray900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Publica tu primer producto para empezar a vender.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textGray600,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    _showComingSoon(
                                      context,
                                      'Publicación de productos próximamente',
                                    );
                                  },
                                  icon: const Icon(Icons.add_circle_outline),
                                  label: const Text(
                                    'Publicar ahora',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryOrange,
                                    foregroundColor: backgroundWhite,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else if (filtered.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.search_off,
                                  size: 58,
                                  color: textGray600,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No encontramos resultados',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: textGray900,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Prueba cambiando el filtro o la búsqueda.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: textGray600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 14),
                                TextButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _statusFilter = null);
                                  },
                                  child: const Text(
                                    'Limpiar filtros',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final offer = filtered[index];
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: index == filtered.length - 1 ? 0 : 12,
                                ),
                                child: _buildOfferCard(context, offer),
                              );
                            },
                            childCount: filtered.length,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
