import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../domain/entities/offer.dart';
import '../../../../domain/entities/offer_condition.dart';
import '../../../../domain/entities/user.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../cart/cart_provider.dart';
import '../../../offers/presentation/providers/offers_provider.dart';
import '../../../offers/presentation/providers/offer_comments_provider.dart';
import '../providers/catalog_filters_provider.dart';
import '../widgets/catalog_filter_widgets.dart';
import '../widgets/product_card.dart';

class BuyerCatalogScreen extends ConsumerWidget {
  const BuyerCatalogScreen({super.key});

  Color _conditionColor(OfferCondition condition) {
    switch (condition) {
      case OfferCondition.newProduct:
        return const Color(0xFF0EA5E9);
      case OfferCondition.excellent:
        return const Color(0xFF10B981);
      case OfferCondition.good:
        return const Color(0xFFF59E0B);
      case OfferCondition.used:
        return const Color(0xFFDC2626);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offersAsync = ref.watch(filteredOffersProvider);

    return Scaffold(
      backgroundColor: backgroundWhite,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        title: const Text(
          'Catálogo',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: offersAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: primaryOrange),
        ),
        error: (error, _) => _ErrorState(
          message: 'No se pudo cargar el catálogo',
          onRetry: () => ref.invalidate(activeOffersProvider(OffersFilter())),
        ),
        data: (offers) {
          if (offers.isEmpty) {
            return const _EmptyState();
          }
          return Column(
            children: [
              // Search bar
              Container(
                padding: const EdgeInsets.all(16),
                color: backgroundWhite,
                child: const CatalogSearchBar(),
              ),

              // Category chips
              const SizedBox(height: 12),
              const CategoryFilterChips(),
              const SizedBox(height: 12),

              // Sort and price filter
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: const [
                    SortOptionsButton(),
                    SizedBox(width: 8),
                    PriceRangeFilter(),
                  ],
                ),
              ),

              // Active filters indicator
              const ActiveFiltersIndicator(),

              // Results count
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  '${offers.length} producto${offers.length != 1 ? 's' : ''} encontrado${offers.length != 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: textGray600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Products list
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: backgroundWhite,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderGray100),
                        boxShadow: [
                          BoxShadow(
                            color: textGray900.withOpacity(0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          ...offers.asMap().entries.map((entry) {
                            final index = entry.key;
                            final offer = entry.value;
                            final isLast = index == offers.length - 1;
                            return Column(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            OfferDetailScreen(offer: offer),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 0,
                                    ),
                                    child: ProductCard(
                                      offerId: offer.offerId,
                                      name: offer.title,
                                      condition: offer.condition.displayName,
                                      colorCondition: _conditionColor(
                                        offer.condition,
                                      ),
                                      price: offer.price,
                                      weight: offer.weight,
                                      showShadow: false,
                                      imageUrl: offer.coverImageUrl,
                                      avgRating: offer.avgRating,
                                      ratingCount: offer.ratingCount,
                                      sellerName: _sellerNameFor(
                                        ref.watch(
                                          userByIdProvider(offer.heroId),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (!isLast)
                                  const Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: borderGray100,
                                    indent: 16,
                                    endIndent: 16,
                                  ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _sellerNameFor(AsyncValue<User?> sellerAsync) {
    return sellerAsync.maybeWhen(
      data: (user) => user?.fullName ?? 'Vendedor',
      orElse: () => 'Vendedor',
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: borderGray100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: textGray700),
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
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.search_off, size: 56, color: textGray600),
            SizedBox(height: 12),
            Text(
              'No hay productos activos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Cuando se publiquen ofertas activas aparecerán aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: textGray700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 56,
              color: primaryOrange,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryOrange,
                foregroundColor: backgroundWhite,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text(
                'Reintentar',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OfferDetailScreen extends ConsumerWidget {
  const OfferDetailScreen({super.key, required this.offer});

  final Offer offer;

  Color _conditionColor(OfferCondition condition) {
    switch (condition) {
      case OfferCondition.newProduct:
        return const Color(0xFF0EA5E9);
      case OfferCondition.excellent:
        return const Color(0xFF10B981);
      case OfferCondition.good:
        return const Color(0xFFF59E0B);
      case OfferCondition.used:
        return const Color(0xFFDC2626);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeColor = _conditionColor(offer.condition);
    final priceText = '\$${offer.price.toStringAsFixed(0)} CLP';
    final coverUrl = offer.coverImageUrl.trim();
    final hasCover = coverUrl.isNotEmpty;
    final isAsset = hasCover && coverUrl.startsWith('assets/');
    final galleryImages = <String>{
      if (coverUrl.isNotEmpty) coverUrl,
      ...offer.imageUrls,
    }.toList();
    final soldCount = offer.orderCount;
    final viewsCount = offer.viewCount;
    final location = offer.itemLocationSnapshot;
    final Widget? locationWidget = location == null
        ? null
        : Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.place_outlined,
                    size: 18,
                    color: textGray600,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ubicación del producto',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: textGray900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          location.fullAddress,
                          style: const TextStyle(
                            fontSize: 13,
                            color: textGray600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Lat: ${location.latitude.toStringAsFixed(5)}, Lng: ${location.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: textGray600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 180,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(location.latitude, location.longitude),
                      zoom: 15,
                    ),
                    markers: {
                      Marker(
                        markerId: const MarkerId('offer_location'),
                        position: LatLng(location.latitude, location.longitude),
                      ),
                    },
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                    myLocationEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    zoomGesturesEnabled: false,
                    scrollGesturesEnabled: false,
                    liteModeEnabled: true,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
    final sellerProfileAsync = ref.watch(userByIdProvider(offer.heroId));
    final sellerName = sellerProfileAsync.maybeWhen(
      data: (user) => user?.fullName ?? 'Vendedor',
      orElse: () => 'Vendedor',
    );

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        title: const Text(
          'Detalle del producto',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: borderGray100,
              height: 220,
              child: !hasCover
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: primaryOrange,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            'Procesando imagen...',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: textGray700,
                            ),
                          ),
                        ],
                      ),
                    )
                  : isAsset
                  ? Image.asset(coverUrl, fit: BoxFit.cover)
                  : Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) {
                        return Image.asset(
                          'assets/logo_hero.png',
                          fit: BoxFit.contain,
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 16),
          if (galleryImages.length > 1) ...[
            const Text(
              'Imágenes',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: textGray900,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: galleryImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final imageUrl = galleryImages[index];
                  final isAssetThumb = imageUrl.startsWith('assets/');
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 140,
                      color: borderGray100,
                      child: isAssetThumb
                          ? Image.asset(imageUrl, fit: BoxFit.cover)
                          : Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Image.asset(
                                  'assets/logo_hero.png',
                                  fit: BoxFit.contain,
                                );
                              },
                            ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  offer.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: badgeColor.withOpacity(0.25)),
                ),
                child: Text(
                  offer.condition.displayName,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 18, color: textGray600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Publicado por: $sellerName',
                  style: const TextStyle(fontSize: 13, color: textGray600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            priceText,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: textGray900,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (offer.ratingCount > 0) ...[
                const Icon(Icons.star, size: 18, color: Color(0xFFFFB800)),
                const SizedBox(width: 6),
                Text(
                  offer.avgRating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textGray900,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                '(${soldCount > 0 ? '$soldCount vendidos' : 'Sin ventas aún'})',
                style: const TextStyle(fontSize: 13, color: textGray600),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.remove_red_eye_outlined,
                size: 16,
                color: textGray600,
              ),
              const SizedBox(width: 4),
              Text(
                '${viewsCount > 0 ? viewsCount : 0} vistas',
                style: const TextStyle(fontSize: 13, color: textGray600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _Pill(icon: Icons.category_outlined, label: offer.category),
              _Pill(
                icon: Icons.visibility_outlined,
                label: 'Estado: ${offer.status.displayName}',
              ),
              _Pill(
                icon: Icons.inventory_2_outlined,
                label: offer.stock > 0
                    ? 'Stock: ${offer.availableQty}/${offer.stock}'
                    : 'Sin stock',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Descripción',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: textGray900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            offer.description,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: textGray700,
            ),
          ),
          const SizedBox(height: 16),
          if (locationWidget != null) ...[locationWidget],
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                size: 18,
                color: textGray600,
              ),
              const SizedBox(width: 6),
              Text(
                'Peso: ${offer.weight} kg',
                style: const TextStyle(fontSize: 13, color: textGray600),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Questions Section
          const SizedBox(height: 24),
          const Text(
            'Preguntas y respuestas',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: textGray900,
            ),
          ),
          const SizedBox(height: 12),

          // Questions List
          Consumer(
            builder: (context, ref, _) {
              final commentsAsync = ref.watch(
                offerCommentsProvider(offer.offerId),
              );
              final currentUser = ref.watch(profileProvider).value;
              final isOwner = currentUser?.id == offer.heroId;

              return commentsAsync.when(
                data: (comments) {
                  if (comments.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: backgroundWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderGray100),
                      ),
                      child: const Center(
                        child: Text(
                          'No hay preguntas aún. ¡Sé el primero en preguntar!',
                          style: TextStyle(color: textGray600, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: comments.map((comment) {
                      final hasReply =
                          comment.reply != null && comment.reply!.isNotEmpty;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: backgroundWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderGray100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Question
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.help_outline,
                                  size: 20,
                                  color: primaryOrange,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        comment.userName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: textGray900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        comment.text,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: textGray700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatDate(comment.createdAt),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: textGray600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // Reply
                            if (hasReply) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: backgroundGray50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.reply,
                                      size: 18,
                                      color: textGray600,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            comment.replyBy ?? 'Vendedor',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: textGray900,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            comment.reply!,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: textGray700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // Reply button (only for owner)
                            if (isOwner && !hasReply) ...[
                              const SizedBox(height: 12),
                              TextButton.icon(
                                onPressed: () => _showReplyDialog(
                                  context,
                                  ref,
                                  comment.commentId,
                                  offer.offerId,
                                ),
                                icon: const Icon(Icons.reply, size: 18),
                                label: const Text('Responder'),
                                style: TextButton.styleFrom(
                                  foregroundColor: primaryOrange,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
              );
            },
          ),

          // Add Question Button
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  _showAddQuestionDialog(context, ref, offer.offerId),
              icon: const Icon(Icons.question_answer),
              label: const Text('Hacer una pregunta'),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryOrange,
                side: const BorderSide(color: primaryOrange),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Add to Cart Button
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: () {
                ref
                    .read(cartProvider.notifier)
                    .addItem(
                      offerId: offer.offerId,
                      name: offer.title,
                      condition: offer.condition.displayName,
                      price: offer.price,
                      weight: offer.weight,
                      imageUrl: offer.coverImageUrl,
                    );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: primaryOrange,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: primaryOrange.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'Agregar al carrito',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: backgroundWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 7) {
      return '${date.day}/${date.month}/${date.year}';
    } else if (difference.inDays > 0) {
      return 'Hace ${difference.inDays} día${difference.inDays > 1 ? 's' : ''}';
    } else if (difference.inHours > 0) {
      return 'Hace ${difference.inHours} hora${difference.inHours > 1 ? 's' : ''}';
    } else if (difference.inMinutes > 0) {
      return 'Hace ${difference.inMinutes} minuto${difference.inMinutes > 1 ? 's' : ''}';
    } else {
      return 'Ahora';
    }
  }

  void _showAddQuestionDialog(
    BuildContext context,
    WidgetRef ref,
    String offerId,
  ) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hacer una pregunta'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: '¿Cuál es tu pregunta?',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = textController.text.trim();
              if (text.isEmpty) return;

              final user = ref.read(profileProvider).value;
              if (user == null) return;

              await ref
                  .read(addCommentProvider.notifier)
                  .addComment(
                    offerId: offerId,
                    userId: user.id,
                    userName: user.fullName,
                    userAvatarUrl: null,
                    text: text,
                  );

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Pregunta enviada')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryOrange),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  void _showReplyDialog(
    BuildContext context,
    WidgetRef ref,
    String commentId,
    String offerId,
  ) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Responder pregunta'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: 'Escribe tu respuesta',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = textController.text.trim();
              if (text.isEmpty) return;

              final user = ref.read(profileProvider).value;
              if (user == null) return;

              await ref
                  .read(addCommentProvider.notifier)
                  .replyToComment(
                    offerId: offerId,
                    commentId: commentId,
                    reply: text,
                    replyBy: user.fullName,
                  );

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Respuesta enviada')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: primaryOrange),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }
}
