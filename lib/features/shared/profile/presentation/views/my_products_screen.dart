import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/common/hero_header_app_bar.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/offer.dart';
import '../../../../../domain/entities/offer_status.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../data/providers/repository_providers.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../../offers/presentation/providers/offers_provider.dart';
import '../../../../hero/presentation/viewmodels/hero_home_viewmodel.dart';
import 'donation_questions_screen.dart';
import 'my_donation_orders_screen.dart';
import 'seller_offer_detail_screen.dart';

class MyProductsScreen extends ConsumerStatefulWidget {
  const MyProductsScreen({super.key});

  @override
  ConsumerState<MyProductsScreen> createState() => _MyProductsScreenState();
}

class _MyProductsScreenState extends ConsumerState<MyProductsScreen> {
  OfferStatus? _statusFilter;
  final Set<String> _busyOfferIds = <String>{};

  Future<void> _openOfferForm({Offer? offer}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DonationQuestionsScreen(initialOffer: offer),
      ),
    );
    if (result == true && mounted) {
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) {
        ref.invalidate(myOffersProvider(userId));
      }
    }
  }

  List<Offer> _applyFilters(List<Offer> offers) {
    final filtered = offers.where((offer) {
      final matchesStatus =
          _statusFilter == null || offer.status == _statusFilter;
      return matchesStatus;
    }).toList();

    filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  Map<String, int> _orderCountsByOfferId(List<Order> orders) {
    final counts = <String, int>{};
    for (final order in orders) {
      final seenInOrder = <String>{};
      for (final item in order.items) {
        final offerId = item.offerId.trim();
        if (offerId.isEmpty || !seenInOrder.add(offerId)) continue;
        counts[offerId] = (counts[offerId] ?? 0) + 1;
      }
    }
    return counts;
  }

  Widget _buildStatPill({
    required String label,
    required int value,
    required Color color,
    double scale = 1.0,
  }) {
    final paddingH = (12.0 * scale).clamp(10.0, 16.0);
    final paddingV = (10.0 * scale).clamp(8.0, 12.0);
    final dotSize = (8.0 * scale).clamp(6.0, 10.0);
    final valueFontSize = (13.0 * scale).clamp(11.0, 15.0);
    final labelFontSize = (12.0 * scale).clamp(10.0, 14.0);
    final spacing1 = (8.0 * scale).clamp(6.0, 10.0);
    final spacing2 = (6.0 * scale).clamp(4.0, 8.0);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: spacing1),
          Text(
            '$value',
            style: TextStyle(
              fontSize: valueFontSize,
              fontWeight: FontWeight.w900,
              color: textGray900,
            ),
          ),
          SizedBox(width: spacing2),
          Text(
            label,
            style: TextStyle(
              fontSize: labelFontSize,
              fontWeight: FontWeight.w700,
              color: textGray700,
            ),
          ),
        ],
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

  Widget _buildFilterChips(BuildContext context, List<Offer> offers) {
    final activeCount = offers
        .where((o) => o.status == OfferStatus.active)
        .length;
    final draftCount = offers
        .where((o) => o.status == OfferStatus.draft)
        .length;
    final pausedCount = offers
        .where((o) => o.status == OfferStatus.paused)
        .length;
    final soldOutCount = offers
        .where((o) => o.status == OfferStatus.soldOut)
        .length;
    final archivedCount = offers
        .where((o) => o.status == OfferStatus.archived)
        .length;

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onSelected,
    }) {
      return ChoiceChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => onSelected(),
        selectedColor: primaryOrange.withValues(alpha: 0.18),
        backgroundColor: backgroundWhite,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: selected ? primaryOrange : textGray700,
        ),
        side: BorderSide(
          color: selected
              ? primaryOrange.withValues(alpha: 0.35)
              : borderGray100,
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
            onSelected: () =>
                setState(() => _statusFilter = OfferStatus.active),
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
            onSelected: () =>
                setState(() => _statusFilter = OfferStatus.paused),
          ),
          const SizedBox(width: 8),
          chip(
            label: 'Agotados ($soldOutCount)',
            selected: _statusFilter == OfferStatus.soldOut,
            onSelected: () =>
                setState(() => _statusFilter = OfferStatus.soldOut),
          ),
          const SizedBox(width: 8),
          chip(
            label: 'Archivados ($archivedCount)',
            selected: _statusFilter == OfferStatus.archived,
            onSelected: () =>
                setState(() => _statusFilter = OfferStatus.archived),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildOfferCard(
    BuildContext context,
    Offer offer, {
    required int orderCount,
  }) {
    final isBusy = _busyOfferIds.contains(offer.offerId);

    final cover = offer.coverImageUrl.trim();
    final hasImage = cover.isNotEmpty;
    final isAsset = cover.startsWith('assets/');

    String formatDate(DateTime dt) {
      const months = [
        'ene',
        'feb',
        'mar',
        'abr',
        'may',
        'jun',
        'jul',
        'ago',
        'sep',
        'oct',
        'nov',
        'dic',
      ];
      final m = months[dt.month - 1];
      return '${dt.day.toString().padLeft(2, '0')} $m ${dt.year}';
    }

    Future<void> handleDelete() async {
      final confirmed = await _confirmAction(
        context: context,
        title: 'Eliminar publicación',
        message: 'Esta acción es permanente. ¿Eliminar esta donación?',
        confirmText: 'Eliminar',
      );
      if (!confirmed) return;
      if (orderCount > 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No puedes eliminar una donacion con pedidos. Pausala para ocultarla.',
            ),
            duration: Duration(milliseconds: 2400),
          ),
        );
        return;
      }
      if (_busyOfferIds.contains(offer.offerId)) return;
      setState(() => _busyOfferIds.add(offer.offerId));
      try {
        await ref.read(offersRepositoryProvider).deleteOffer(offer.offerId);
        ref.invalidate(myOffersProvider(offer.heroId));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Donación eliminada'),
            duration: Duration(milliseconds: 1500),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo eliminar: $e'),
            duration: const Duration(milliseconds: 2200),
          ),
        );
      } finally {
        if (mounted) {
          setState(() => _busyOfferIds.remove(offer.offerId));
        }
      }
    }

    Widget imageWidget() {
      if (!hasImage) {
        return Container(
          color: borderGray100,
          child: const Center(
            child: Icon(Icons.image_outlined, color: textGray600),
          ),
        );
      }

      if (isAsset) {
        return Image.asset(cover, fit: BoxFit.cover);
      }

      return Image.network(
        cover,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: borderGray100,
            child: const Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: textGray600,
              ),
            ),
          );
        },
      );
    }

    final date = offer.publishedAt ?? offer.updatedAt;

    ({Color fg, Color bg}) statusColors(OfferStatus status) {
      switch (status) {
        case OfferStatus.active:
          return (fg: const Color(0xFF15803D), bg: const Color(0xFFDCFCE7));
        case OfferStatus.draft:
          return (fg: const Color(0xFF7C3AED), bg: const Color(0xFFEDE9FE));
        case OfferStatus.paused:
          return (fg: const Color(0xFFB45309), bg: const Color(0xFFFFEDD5));
        case OfferStatus.soldOut:
          return (fg: const Color(0xFFDC2626), bg: const Color(0xFFFEE2E2));
        case OfferStatus.archived:
          return (fg: textGray600, bg: borderGray100);
      }
    }

    final statusPalette = statusColors(offer.status);

    return Container(
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderGray100),
        boxShadow: [
          BoxShadow(
            color: textGray900.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SellerOfferDetailScreen(offer: offer),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 74,
                      height: 74,
                      child: imageWidget(),
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: textGray900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isBusy)
                              const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: primaryOrange,
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: statusPalette.bg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  offer.status.displayName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: statusPalette.fg,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.remove_red_eye_outlined,
                              size: 14,
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
                              size: 14,
                              color: textGray600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$orderCount',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: textGray600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.star_outline_rounded,
                              size: 14,
                              color: textGray600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              offer.ratingCount > 0
                                  ? '${offer.avgRating.toStringAsFixed(1)} (${offer.ratingCount})'
                                  : '0.0 (0)',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: textGray600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 14,
                              color: textGray600,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Disponibles: ${offer.availableQty}/${offer.stock}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: textGray600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Actualizado: ${formatDate(date)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: textGray600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: borderGray100),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: offer.canBeEdited && !isBusy
                      ? () => _openOfferForm(offer: offer)
                      : null,
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: textGray700,
                  ),
                  label: const Text(
                    'Editar',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textGray700,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 44, color: borderGray100),
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SellerOfferDetailScreen(offer: offer),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.remove_red_eye_outlined,
                    size: 18,
                    color: textGray700,
                  ),
                  label: const Text(
                    'Ver',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textGray700,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 44, color: borderGray100),
              Expanded(
                child: TextButton.icon(
                  onPressed: !isBusy ? handleDelete : null,
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Colors.red,
                  ),
                  label: const Text(
                    'Eliminar',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.red,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
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

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileStreamProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: HeroHeaderAppBar(
        title: 'Mis donaciones',
        icon: Icons.volunteer_activism_rounded,
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
            return;
          }
          ref.read(heroHomeViewModelProvider.notifier).selectNavItem(0);
        },
        actions: [
          IconButton(
            tooltip: 'Pedidos recibidos',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MyDonationOrdersScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
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
                  const Icon(
                    Icons.error_outline,
                    color: primaryOrange,
                    size: 46,
                  ),
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
                      'Inicia sesión para ver tus donaciones',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Necesitas una cuenta para administrar tus donaciones.',
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
          final orderCountsByOfferId = ref
              .watch(myDonationOrdersProvider(user.id))
              .maybeWhen(
                data: _orderCountsByOfferId,
                orElse: () => const <String, int>{},
              );

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
                        'No pudimos cargar tus donaciones',
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
                            final scale = (maxWidth / 390.0)
                                .clamp(0.78, 1.20)
                                .toDouble();
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
                            final titleSize = (18.0 * scale)
                                .clamp(16.0, 22.0)
                                .toDouble();
                            final subtitleSize = (14.0 * scale)
                                .clamp(12.0, 18.0)
                                .toDouble();
                            final buttonFontSize = (14.0 * scale)
                                .clamp(12.0, 16.0)
                                .toDouble();
                            final buttonIconSize = (20.0 * scale)
                                .clamp(18.0, 22.0)
                                .toDouble();
                            final gapSmall = (8.0 * scale)
                                .clamp(6.0, 10.0)
                                .toDouble();
                            final gapNormal = (16.0 * scale)
                                .clamp(10.0, 16.0)
                                .toDouble();
                            final buttonHPadding = (20.0 * scale)
                                .clamp(14.0, 20.0)
                                .toDouble();
                            final buttonVPadding = (12.0 * scale)
                                .clamp(10.0, 14.0)
                                .toDouble();

                            final contentAvailableWidth =
                                (maxWidth -
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
                                        primaryYellow.withValues(alpha: 0.95),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primaryOrange.withValues(
                                          alpha: 0.22,
                                        ),
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
                                            padding: EdgeInsets.all(
                                              cardPadding,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Padding(
                                                    padding: EdgeInsets.only(
                                                      right:
                                                          contentRightPadding,
                                                    ),
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment:
                                                          Alignment.centerLeft,
                                                      child: SizedBox(
                                                        width:
                                                            contentAvailableWidth,
                                                        child: Column(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              'Tu vitrina',
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                color:
                                                                    backgroundWhite,
                                                                fontSize:
                                                                    titleSize,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                            SizedBox(
                                                              height: gapSmall,
                                                            ),
                                                            Text(
                                                              'Administra stock y visibilidad',
                                                              maxLines: 2,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: TextStyle(
                                                                color: backgroundWhite
                                                                    .withValues(
                                                                      alpha:
                                                                          0.92,
                                                                    ),
                                                                fontSize:
                                                                    subtitleSize,
                                                              ),
                                                            ),
                                                            SizedBox(
                                                              height: gapNormal,
                                                            ),
                                                            ElevatedButton.icon(
                                                              onPressed: () {
                                                                _openOfferForm();
                                                              },
                                                              icon: Icon(
                                                                Icons
                                                                    .add_circle_outline,
                                                                color:
                                                                    primaryOrange,
                                                                size:
                                                                    buttonIconSize,
                                                              ),
                                                              label: Column(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(
                                                                    'Sé un Hero',
                                                                    style: TextStyle(
                                                                      color:
                                                                          primaryOrange,
                                                                      fontSize:
                                                                          buttonFontSize,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w800,
                                                                    ),
                                                                  ),
                                                                  Text(
                                                                    'Dona tus productos',
                                                                    style: TextStyle(
                                                                      color:
                                                                          primaryOrange,
                                                                      fontSize:
                                                                          buttonFontSize -
                                                                          2,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                              style: ElevatedButton.styleFrom(
                                                                backgroundColor:
                                                                    backgroundWhite,
                                                                padding: EdgeInsets.symmetric(
                                                                  horizontal:
                                                                      buttonHPadding,
                                                                  vertical:
                                                                      buttonVPadding,
                                                                ),
                                                                shape: RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        12,
                                                                      ),
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
                                  spacing: (10.0 * scale).clamp(8.0, 12.0),
                                  runSpacing: (10.0 * scale).clamp(8.0, 12.0),
                                  alignment: WrapAlignment.center,
                                  children: [
                                    _buildStatPill(
                                      label: 'Activos',
                                      value: activeCount,
                                      color: const Color(0xFF0F766E),
                                      scale: scale,
                                    ),
                                    _buildStatPill(
                                      label: 'Borradores',
                                      value: draftCount,
                                      color: const Color(0xFF7C3AED),
                                      scale: scale,
                                    ),
                                    _buildStatPill(
                                      label: 'Agotados',
                                      value: soldOutCount,
                                      color: const Color(0xFFDC2626),
                                      scale: scale,
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
                              'Tus donaciones',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: textGray900,
                              ),
                            ),
                            _buildFilterChips(context, offers),
                          ],
                        ),
                      ),
                    ),
                    if (offers.isEmpty) ...[
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
                                    color: primaryOrange.withValues(
                                      alpha: 0.12,
                                    ),
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
                                  'Aún no tienes donaciones publicadas',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: textGray900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Publica tu primera donación para empezar a ayudar.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textGray600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ] else if (filtered.isEmpty) ...[
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.filter_alt_off,
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
                                  'Prueba cambiando el filtro.',
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
                                    setState(() => _statusFilter = null);
                                  },
                                  child: const Text(
                                    'Limpiar filtros',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final offer = filtered[index];
                            final orderCount =
                                orderCountsByOfferId[offer.offerId] ?? 0;
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: index == filtered.length - 1 ? 0 : 12,
                              ),
                              child: _buildOfferCard(
                                context,
                                offer,
                                orderCount: orderCount > offer.orderCount
                                    ? orderCount
                                    : offer.orderCount,
                              ),
                            );
                          }, childCount: filtered.length),
                        ),
                      ),
                    ],
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
