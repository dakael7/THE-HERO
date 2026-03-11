import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/utils/weight_utils.dart';
import '../../../../../data/providers/repository_providers.dart';
import '../../../../../domain/entities/offer.dart';
import '../../../../../domain/entities/offer_status.dart';
import '../../../../../domain/entities/offer_condition.dart';
import '../../../../offers/presentation/providers/offer_comments_provider.dart';
import '../providers/profile_provider.dart';
import 'donation_questions_screen.dart';

class SellerOfferDetailScreen extends ConsumerWidget {
  const SellerOfferDetailScreen({super.key, required this.offer});

  final Offer offer;

  String _formatBool(bool? value) {
    if (value == null) return '—';
    return value ? 'Sí' : 'No';
  }

  Color _conditionColor(OfferCondition condition) {
    switch (condition) {
      case OfferCondition.newProduct:
        return categoryTextBlue;
      case OfferCondition.excellent:
        return categoryTextGreen;
      case OfferCondition.good:
        return categoryTextYellow;
      case OfferCondition.used:
        return categoryTextRed;
    }
  }

  Color _statusColor(OfferStatus status) {
    switch (status) {
      case OfferStatus.active:
        return categoryTextGreen;
      case OfferStatus.draft:
        return textGray600;
      case OfferStatus.paused:
        return categoryTextYellow;
      case OfferStatus.soldOut:
        return categoryTextRed;
      case OfferStatus.archived:
        return textGray600;
    }
  }

  String _statusText(OfferStatus status) {
    switch (status) {
      case OfferStatus.active:
        return 'Activa';
      case OfferStatus.draft:
        return 'Borrador';
      case OfferStatus.paused:
        return 'Pausada';
      case OfferStatus.soldOut:
        return 'Agotada';
      case OfferStatus.archived:
        return 'Archivada';
    }
  }

  IconData _statusIcon(OfferStatus status) {
    switch (status) {
      case OfferStatus.active:
        return Icons.check_circle_rounded;
      case OfferStatus.draft:
        return Icons.edit_note_rounded;
      case OfferStatus.paused:
        return Icons.pause_circle_rounded;
      case OfferStatus.soldOut:
        return Icons.remove_shopping_cart_rounded;
      case OfferStatus.archived:
        return Icons.archive_rounded;
    }
  }

  Widget _buildImage(String url, {BoxFit fit = BoxFit.cover}) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return _PlaceholderImage();
    }
    if (trimmed.startsWith('assets/')) {
      return Image.asset(trimmed, fit: fit);
    }
    return Image.network(
      trimmed,
      fit: fit,
      errorBuilder: (_, _, _) => _PlaceholderImage(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeColor = _conditionColor(offer.condition);
    final statusColor = _statusColor(offer.status);
    const priceText = 'Donación';
    final coverUrl = offer.coverImageUrl.trim();
    final hasCover = coverUrl.isNotEmpty;

    String normalizeImageKey(String raw) {
      final value = raw.trim();
      if (value.isEmpty) return '';
      if (value.startsWith('assets/')) return value;
      final uri = Uri.tryParse(value);
      if (uri == null) return value;
      return uri
          .replace(queryParameters: const <String, String>{}, fragment: '')
          .toString();
    }

    final extraGalleryImages = <String>[];
    final seen = <String>{};
    for (final raw in offer.imageUrls) {
      final url = raw.trim();
      if (url.isEmpty) continue;
      if (hasCover &&
          normalizeImageKey(url) == normalizeImageKey(coverUrl)) continue;
      final key = normalizeImageKey(url);
      if (key.isEmpty) continue;
      if (seen.add(key)) extraGalleryImages.add(url);
    }

    final showConditionChip = offer.condition != OfferCondition.newProduct;
    final location = offer.itemLocationSnapshot;

    final commentsAsync = ref.watch(offerCommentsProvider(offer.offerId));
    final unansweredCount = commentsAsync.maybeWhen(
      data: (comments) =>
          comments.where((c) => c.reply == null || c.reply!.isEmpty).length,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: backgroundGray50,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── SLIVER APP BAR ──
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            elevation: 0,
            backgroundColor: primaryOrangeLight,
            foregroundColor: Colors.white,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.edit_rounded, color: Colors.white),
                    tooltip: 'Editar',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              DonationQuestionsScreen(initialOffer: offer),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Cover image
                  hasCover
                      ? _buildImage(coverUrl)
                      : Container(
                          color: primaryOrangeLight,
                          child: const Center(
                            child: Icon(
                              Icons.card_giftcard_rounded,
                              size: 72,
                              color: primaryOrange,
                            ),
                          ),
                        ),

                  // Gradient overlay
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                          stops: const [0.5, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Status badge — bottom left
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_statusIcon(offer.status),
                              size: 14, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(
                            _statusText(offer.status),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Condition badge — bottom right
                  if (showConditionChip)
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: badgeColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          offer.condition.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),

                  // Unanswered questions badge
                  if (unansweredCount > 0)
                    Positioned(
                      top: 90,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: primaryYellow,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.help_outline_rounded,
                                size: 14, color: textGray900),
                            const SizedBox(width: 4),
                            Text(
                              '$unansweredCount sin responder',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: textGray900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── CONTENT ──
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── TITLE CARD ──
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: backgroundWhite,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: textGray900,
                          letterSpacing: -0.5,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: primaryYellow,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              priceText,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: textGray900,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: primaryOrangeLight,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: primaryYellow),
                            ),
                            child: Text(
                              offer.category,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: backgroundWhite,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── STATS GRID ──
                _SectionHeader(
                  label: 'Estadísticas',
                  icon: Icons.bar_chart_rounded,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = constraints.maxWidth < 360 ? 1 : 2;
                      final ratio = crossAxisCount == 1 ? 3.2 : 1.8;
                      return GridView.count(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: ratio,
                        children: [
                          _StatCard(
                            icon: Icons.visibility_outlined,
                            label: 'Vistas totales',
                            value: '${offer.viewCount}',
                            color: categoryTextBlue,
                          ),
                          _StatCard(
                            icon: Icons.help_outline_rounded,
                            label: 'Sin responder',
                            value: '$unansweredCount',
                            color: unansweredCount > 0
                                ? primaryYellow
                                : categoryTextGreen,
                          ),
                          _StatCard(
                            icon: Icons.inventory_2_outlined,
                            label: 'Disponibles',
                            value: '${offer.availableQty}',
                            color: categoryTextGreen,
                          ),
                          _StatCard(
                            icon: Icons.shopping_bag_outlined,
                            label: 'Entregas',
                            value: '${offer.orderCount}',
                            color: primaryOrange,
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // ── EXTRA GALLERY ──
                if (extraGalleryImages.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'Galería',
                    icon: Icons.photo_library_outlined,
                  ),
                  SizedBox(
                    height: 110,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: extraGalleryImages.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 140,
                            child: _buildImage(extraGalleryImages[index]),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                // ── DESCRIPTION ──
                _SectionHeader(
                  label: 'Descripción',
                  icon: Icons.notes_rounded,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: backgroundWhite,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderGray100),
                    ),
                    child: Text(
                      offer.description,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.65,
                        color: textGray700,
                      ),
                    ),
                  ),
                ),

                // ── LOCATION ──
                if (location != null) ...[
                  _SectionHeader(
                    label: 'Ubicación de retiro',
                    icon: Icons.place_outlined,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
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
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: primaryOrangeLight,
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.place_outlined,
                                    size: 18,
                                    color: backgroundWhite,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        location.fullAddress,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: textGray900,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Lat: ${location.latitude.toStringAsFixed(5)}, Lng: ${location.longitude.toStringAsFixed(5)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: textGray600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ClipRRect(
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(16),
                            ),
                            child: SizedBox(
                              height: 180,
                              child: GoogleMap(
                                initialCameraPosition: CameraPosition(
                                  target: LatLng(
                                    location.latitude,
                                    location.longitude,
                                  ),
                                  zoom: 15,
                                ),
                                markers: {
                                  Marker(
                                    markerId:
                                        const MarkerId('offer_location'),
                                    position: LatLng(
                                      location.latitude,
                                      location.longitude,
                                    ),
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
                        ],
                      ),
                    ),
                  ),
                ],

                // ── DONATION DETAILS ──
                _SectionHeader(
                  label: 'Detalles de la donación',
                  icon: Icons.info_outline_rounded,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: backgroundWhite,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderGray100),
                    ),
                    child: Column(
                      children: [
                        _DetailTile(
                          icon: Icons.sell_outlined,
                          label: 'Moneda',
                          value: offer.currency,
                          isFirst: true,
                        ),
                        _DetailTile(
                          icon: Icons.inventory_2_outlined,
                          label: 'Unidades',
                          value: '${offer.availableQty}/${offer.stock}',
                        ),
                        _DetailTile(
                          icon: Icons.scale_outlined,
                          label: 'Peso',
                          value: formatWeightKg(offer.weight),
                        ),
                        _DetailTile(
                          icon: Icons.visibility_outlined,
                          label: 'Estado',
                          value: offer.status.displayName,
                        ),
                        _DetailTile(
                          icon: Icons.inventory_outlined,
                          label: 'Disponible',
                          value: offer.isAvailable ? 'Sí' : 'No',
                          valueColor: offer.isAvailable
                              ? categoryTextGreen
                              : categoryTextRed,
                        ),
                        _DetailTile(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'Buen estado',
                          value: _formatBool(offer.isInGoodState),
                          valueColor: offer.isInGoodState == true
                              ? categoryTextGreen
                              : null,
                        ),
                        _DetailTile(
                          icon: Icons.build_outlined,
                          label: 'Funciona correctamente',
                          value: _formatBool(offer.worksCorrectly),
                          valueColor: offer.worksCorrectly == true
                              ? categoryTextGreen
                              : null,
                        ),
                        if (offer.pickupSchedule != null)
                          _DetailTile(
                            icon: Icons.schedule_outlined,
                            label: 'Horario de retiro',
                            value: offer.pickupSchedule!
                                .getScheduleDescription(),
                            isLast: true,
                          )
                        else
                          const SizedBox(height: 0),
                      ],
                    ),
                  ),
                ),

                if (offer.price > 0) ...[
                  // ── Q&A ──
                  _SectionHeader(
                    label: 'Preguntas y respuestas',
                    icon: Icons.forum_outlined,
                    iconColor: backgroundWhite,
                    iconBackgroundColor: primaryOrange,
                  ),

                  Consumer(
                    builder: (context, ref, _) {
                      final commentsAsync = ref.watch(
                        offerCommentsProvider(offer.offerId),
                      );

                      return commentsAsync.when(
                        data: (comments) {
                          if (comments.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(28),
                                decoration: BoxDecoration(
                                  color: backgroundWhite,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: borderGray100),
                                ),
                                child: const Column(
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      size: 36,
                                      color: textGray600,
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      'Sin preguntas aún',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: textGray700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              children: comments.map((comment) {
                                final hasReply = comment.reply != null &&
                                    comment.reply!.isNotEmpty;

                                return Container(
                                  margin:
                                      const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: backgroundWhite,
                                    borderRadius:
                                        BorderRadius.circular(16),
                                    border: Border.all(
                                      color: !hasReply
                                          ? primaryYellow
                                          : borderGray100,
                                    ),
                                    boxShadow: !hasReply
                                        ? [
                                            BoxShadow(
                                              color: primaryYellow
                                                  .withValues(alpha: 0.15),
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Column(
                                    children: [
                                      // Question
                                      Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration:
                                                  const BoxDecoration(
                                                color: primaryOrange,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.help_outline_rounded,
                                                size: 18,
                                                color: backgroundWhite,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          comment.userName,
                                                          style:
                                                              const TextStyle(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            fontSize: 13,
                                                            color: textGray900,
                                                          ),
                                                          maxLines: 1,
                                                          overflow:
                                                              TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      if (!hasReply)
                                                        Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 8,
                                                            vertical: 3,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: primaryOrange,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(6),
                                                          ),
                                                          child: const Text(
                                                            'Sin respuesta',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: backgroundWhite,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    comment.text,
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: textGray700,
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Reply
                                      if (hasReply)
                                        Container(
                                          margin: const EdgeInsets.fromLTRB(
                                              16, 0, 16, 16),
                                          padding:
                                              const EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color:
                                                backgroundGray50,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color:
                                                  borderGray100,
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration:
                                                    const BoxDecoration(
                                                  color: primaryOrange,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.reply_rounded,
                                                  size: 16,
                                                  color: backgroundWhite,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .start,
                                                  children: [
                                                    Text(
                                                      comment.replyBy ??
                                                          'Tú',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 12,
                                                        color: textGray900,
                                                      ),
                                                    ),
                                                    const SizedBox(
                                                        height: 4),
                                                    Text(
                                                      comment.reply!,
                                                      style: const TextStyle(
                                                        fontSize: 13,
                                                        color: textGray700,
                                                        height: 1.4,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      // Reply button
                                      if (!hasReply)
                                        Padding(
                                          padding:
                                              const EdgeInsets.fromLTRB(
                                                  16, 0, 16, 14),
                                          child: GestureDetector(
                                            onTap: () => _showReplyDialog(
                                              context,
                                              ref,
                                              comment.commentId,
                                              offer.offerId,
                                            ),
                                            child: Container(
                                              width: double.infinity,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 12),
                                              decoration: BoxDecoration(
                                                color: primaryOrange,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: primaryOrange
                                                        .withValues(alpha: 0.3),
                                                    blurRadius: 8,
                                                    offset: const Offset(
                                                        0, 3),
                                                  ),
                                                ],
                                              ),
                                              child: const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .center,
                                                children: [
                                                  Icon(
                                                    Icons.reply_rounded,
                                                    size: 16,
                                                    color: backgroundWhite,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'Responder',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: backgroundWhite,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: primaryOrange,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                        error: (e, _) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Error: $e',
                            style: const TextStyle(color: textGray900),
                          ),
                        ),
                      );
                    },
                  ),
                ],

                const SizedBox(height: 26),

                // ── ACTIONS ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  child: Column(
                    children: [
                      // Pause / Activate
                      GestureDetector(
                        onTap: offer.status == OfferStatus.active
                            ? () => _pauseOffer(context, ref)
                            : () => _activateOffer(context, ref),
                        child: Container(
                          width: double.infinity,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: offer.status == OfferStatus.active
                                ? primaryOrange
                                : categoryBgGreen,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: offer.status == OfferStatus.active
                                  ? primaryOrange
                                  : categoryTextGreen,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                offer.status == OfferStatus.active
                                    ? Icons.pause_circle_outline_rounded
                                    : Icons.play_circle_outline_rounded,
                                color:
                                    offer.status == OfferStatus.active
                                        ? backgroundWhite
                                        : categoryTextGreen,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                offer.status == OfferStatus.active
                                    ? 'Pausar donación'
                                    : 'Activar donación',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: offer.status ==
                                          OfferStatus.active
                                      ? backgroundWhite
                                      : categoryTextGreen,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Delete
                      GestureDetector(
                        onTap: () => _deleteOffer(context, ref),
                        child: Container(
                          width: double.infinity,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: categoryBgRed,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: categoryTextRed),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.delete_outline_rounded,
                                color: categoryTextRed,
                                size: 20,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Eliminar donación',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: categoryTextRed,
                                ),
                              ),
                            ],
                          ),
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Responder pregunta',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: textController,
          decoration: InputDecoration(
            hintText: 'Escribe tu respuesta',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: primaryOrange),
            ),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: textGray600)),
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
                  const SnackBar(
                      content: Text('Respuesta enviada')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Enviar',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _pauseOffer(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(offersRepositoryProvider)
          .updateOfferStatus(offer.offerId, 'paused');
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Donación pausada exitosamente')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al pausar donación: $e')),
        );
      }
    }
  }

  void _activateOffer(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(offersRepositoryProvider)
          .updateOfferStatus(offer.offerId, 'active');
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Donación activada exitosamente')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al activar donación: $e')),
        );
      }
    }
  }

  void _deleteOffer(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Eliminar donación',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          '¿Estás seguro de que quieres eliminar esta donación? Esta acción no se puede deshacer.',
          style: TextStyle(color: textGray700, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: textGray600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Funcionalidad de eliminar próximamente'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: categoryTextRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Eliminar',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  PLACEHOLDER IMAGE
// ─────────────────────────────────────────────
class _PlaceholderImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: borderGray100,
      child: const Center(
        child: Icon(
          Icons.image_not_supported_outlined,
          color: textGray600,
          size: 36,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  SECTION HEADER
// ─────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.icon,
    this.iconColor,
    this.iconBackgroundColor,
  });
  final String label;
  final IconData icon;
  final Color? iconColor;
  final Color? iconBackgroundColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
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
          if (iconBackgroundColor != null)
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconBackgroundColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  icon,
                  size: 18,
                  color: iconColor ?? backgroundWhite,
                ),
              ),
            )
          else
            Icon(icon, size: 18, color: iconColor ?? textGray900),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: textGray900,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  STAT CARD  (grid tile)
// ─────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: textGray600,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  DETAIL TILE  (list row inside card)
// ─────────────────────────────────────────────
class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.isFirst = false,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: isNarrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: borderGray100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(icon, size: 16, color: textGray600),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: textGray600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            value,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: valueColor ?? textGray900,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: borderGray100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, size: 16, color: textGray600),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 13,
                              color: textGray600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: valueColor ?? textGray900,
                          ),
                        ),
                      ],
                    ),
            ),
            if (!isLast)
              const Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: borderGray100,
              ),
          ],
        );
      },
    );
  }
}