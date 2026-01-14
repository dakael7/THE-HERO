import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/offer.dart';
import '../../../../../domain/entities/offer_condition.dart';
import '../../../../../domain/entities/offer_status.dart';
import '../../../../offers/presentation/providers/offer_comments_provider.dart';
import '../providers/profile_provider.dart';
import '../../../../../data/providers/repository_providers.dart';
import './offer_form_screen.dart';

class SellerOfferDetailScreen extends ConsumerWidget {
  const SellerOfferDetailScreen({super.key, required this.offer});

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

  Color _statusColor(OfferStatus status) {
    switch (status) {
      case OfferStatus.active:
        return const Color(0xFF10B981);
      case OfferStatus.draft:
        return const Color(0xFF6B7280);
      case OfferStatus.paused:
        return const Color(0xFFF59E0B);
      case OfferStatus.soldOut:
        return const Color(0xFFDC2626);
      case OfferStatus.archived:
        return const Color(0xFF9CA3AF);
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeColor = _conditionColor(offer.condition);
    final statusColor = _statusColor(offer.status);
    final priceText = '\$${offer.price.toStringAsFixed(0)} CLP';
    final coverUrl = offer.coverImageUrl.trim();
    final hasCover = coverUrl.isNotEmpty;
    final isAsset = hasCover && coverUrl.startsWith('assets/');
    final galleryImages = <String>{
      if (coverUrl.isNotEmpty) coverUrl,
      ...offer.imageUrls,
    }.toList();

    // Calcular ingresos (precio * cantidad vendida)
    final revenue = offer.price * offer.orderCount;

    // Obtener preguntas sin responder
    final commentsAsync = ref.watch(offerCommentsProvider(offer.offerId));
    final unansweredCount = commentsAsync.maybeWhen(
      data: (comments) =>
          comments.where((c) => c.reply == null || c.reply!.isEmpty).length,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        title: const Text(
          'Detalle de mi oferta',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OfferFormScreen(initialOffer: offer),
                ),
              );
            },
            tooltip: 'Editar',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Imagen principal
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: borderGray100,
              height: 280,
              child: hasCover
                  ? (isAsset
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
                          ))
                  : Image.asset('assets/logo_hero.png', fit: BoxFit.contain),
            ),
          ),

          // Galería de imágenes
          if (galleryImages.length > 1) ...[
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

          // Título y estado
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
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  _statusText(offer.status),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Precio
          Text(
            priceText,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: primaryOrange,
            ),
          ),
          const SizedBox(height: 8),

          // Condición
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: badgeColor),
            ),
            child: Text(
              offer.condition.displayName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: badgeColor,
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Estadísticas del vendedor
          const Text(
            'Estadísticas',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: textGray900,
            ),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderGray100),
            ),
            child: Column(
              children: [
                _StatRow(
                  icon: Icons.visibility_outlined,
                  label: 'Vistas totales',
                  value: '${offer.viewCount}',
                  color: const Color(0xFF3B82F6),
                ),
                const Divider(height: 24),
                _StatRow(
                  icon: Icons.question_answer_outlined,
                  label: 'Preguntas sin responder',
                  value: '$unansweredCount',
                  color: const Color(0xFFF59E0B),
                ),
                const Divider(height: 24),
                _StatRow(
                  icon: Icons.inventory_2_outlined,
                  label: 'Stock disponible',
                  value: '${offer.availableQty}',
                  color: const Color(0xFF10B981),
                ),
                const Divider(height: 24),
                _StatRow(
                  icon: Icons.shopping_cart_outlined,
                  label: 'Cantidad vendida',
                  value: '${offer.orderCount}',
                  color: const Color(0xFF8B5CF6),
                ),
                const Divider(height: 24),
                _StatRow(
                  icon: Icons.attach_money,
                  label: 'Ingresos generados',
                  value: '\$${revenue.toStringAsFixed(0)} CLP',
                  color: const Color(0xFF10B981),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Descripción
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

          // Detalles adicionales
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

          const SizedBox(height: 24),

          // Preguntas y respuestas
          const Text(
            'Preguntas y respuestas',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: textGray900,
            ),
          ),
          const SizedBox(height: 12),

          Consumer(
            builder: (context, ref, _) {
              final commentsAsync = ref.watch(
                offerCommentsProvider(offer.offerId),
              );

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
                          'No hay preguntas aún',
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
                                    ],
                                  ),
                                ),
                              ],
                            ),

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
                                            comment.replyBy ?? 'Tú',
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

                            if (!hasReply) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _showReplyDialog(
                                    context,
                                    ref,
                                    comment.commentId,
                                    offer.offerId,
                                  ),
                                  icon: const Icon(Icons.reply, size: 18),
                                  label: const Text('Responder'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryOrange,
                                    foregroundColor: backgroundWhite,
                                  ),
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

          const SizedBox(height: 24),

          // Botones de acción
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: offer.status == OfferStatus.active
                      ? () => _pauseOffer(context, ref)
                      : () => _activateOffer(context, ref),
                  icon: Icon(
                    offer.status == OfferStatus.active
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  label: Text(
                    offer.status == OfferStatus.active ? 'Pausar' : 'Activar',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryOrange,
                    side: const BorderSide(color: primaryOrange),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _deleteOffer(context, ref),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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

  void _pauseOffer(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(offersRepositoryProvider)
          .updateOfferStatus(offer.offerId, 'paused');

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Oferta pausada exitosamente')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al pausar oferta: $e')));
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
          const SnackBar(content: Text('Oferta activada exitosamente')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al activar oferta: $e')));
      }
    }
  }

  void _deleteOffer(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar oferta'),
        content: const Text(
          '¿Estás seguro de que quieres eliminar esta oferta? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Implementar lógica para eliminar oferta
              Navigator.pop(context);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Funcionalidad de eliminar próximamente'),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
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
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, color: textGray700),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}
