import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/user.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';

class DriverRatingScreen extends ConsumerStatefulWidget {
  final Order order;

  const DriverRatingScreen({super.key, required this.order});

  @override
  ConsumerState<DriverRatingScreen> createState() => _DriverRatingScreenState();
}

class _DriverRatingScreenState extends ConsumerState<DriverRatingScreen> {
  int _rating = 5;
  int _sellerRating = 5;
  final _commentController = TextEditingController();
  final _sellerCommentController = TextEditingController();
  bool _isSubmitting = false;

  Widget _participantHeader({
    required String roleLabel,
    required String name,
    String? photoUrl,
  }) {
    final resolvedUrl = photoUrl?.trim();
    final hasPhoto = resolvedUrl != null && resolvedUrl.isNotEmpty;

    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: primaryOrange.withValues(alpha: 0.10),
          foregroundImage: hasPhoto ? NetworkImage(resolvedUrl) : null,
          child: const Icon(Icons.person, color: primaryOrange),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                roleLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: textGray600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: textGray900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _sellerCommentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final sellerId = (() {
        if (widget.order.sellerHeroIds.isNotEmpty) {
          final first = widget.order.sellerHeroIds.first.trim();
          return first.isNotEmpty ? first : null;
        }
        if (widget.order.items.isNotEmpty) {
          final first = widget.order.items.first.sellerHeroIdSnapshot.trim();
          return first.isNotEmpty ? first : null;
        }
        return null;
      })();

      // Update order with confirmation and rating
      await ref
          .read(orderActionsProvider)
          .confirmDeliveryAndRate(
            orderId: widget.order.orderId,
            rating: _rating.toDouble(),
            comment: _commentController.text.trim().isEmpty
                ? null
                : _commentController.text.trim(),
            sellerRating: _sellerRating.toDouble(),
            sellerHeroId: sellerId,
            sellerComment: _sellerCommentController.text.trim().isEmpty
                ? null
                : _sellerCommentController.text.trim(),
          );

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('¡Gracias por tu calificación!'),
            ],
          ),
          backgroundColor: categoryTextGreen,
          duration: Duration(seconds: 2),
        ),
      );

      // Navigate back
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSubmitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Error: ${e.toString()}')),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final riderId = widget.order.rider.assignedRiderId?.trim();
    final riderAsync = (riderId == null || riderId.isEmpty)
        ? const AsyncValue<User?>.data(null)
        : ref.watch(userByIdStreamProvider(riderId));
    final riderName = riderAsync.maybeWhen(
      data: (u) => (u?.fullName.trim().isNotEmpty ?? false)
          ? u!.fullName
          : (widget.order.rider.riderNameSnapshot ?? 'Rider'),
      orElse: () => widget.order.rider.riderNameSnapshot ?? 'Rider',
    );
    final riderPhotoUrl = riderAsync.maybeWhen(
      data: (u) => u?.profilePhotoUrl,
      orElse: () => null,
    );

    final sellerId = (() {
      if (widget.order.sellerHeroIds.isNotEmpty) {
        final first = widget.order.sellerHeroIds.first.trim();
        return first.isNotEmpty ? first : null;
      }
      if (widget.order.items.isNotEmpty) {
        final first = widget.order.items.first.sellerHeroIdSnapshot.trim();
        return first.isNotEmpty ? first : null;
      }
      return null;
    })();

    final sellerAsync = sellerId == null
        ? const AsyncValue<User?>.data(null)
        : ref.watch(userByIdStreamProvider(sellerId));
    final sellerName = sellerAsync.maybeWhen(
      data: (u) => (u?.fullName.trim().isNotEmpty ?? false)
          ? u!.fullName
          : 'Hero Donador',
      orElse: () => 'Hero Donador',
    );
    final sellerPhotoUrl = sellerAsync.maybeWhen(
      data: (u) => u?.profilePhotoUrl,
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Calificar pedido',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Success card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: categoryTextGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    size: 40,
                    color: categoryTextGreen,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '¡Pedido entregado!',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Califica tu experiencia con el Rider y el Hero Donador',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: textGray700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Rating card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _participantHeader(
                  roleLabel: 'Rider',
                  name: riderName,
                  photoUrl: riderPhotoUrl,
                ),
                const SizedBox(height: 16),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (index) {
                      final starIndex = index + 1;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _rating = starIndex;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            starIndex <= _rating
                                ? Icons.star
                                : Icons.star_border,
                            size: 48,
                            color: starIndex <= _rating
                                ? primaryYellow
                                : textGray600,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _getRatingText(_rating),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textGray700,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Comentario (opcional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textGray900,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentController,
                  maxLines: 4,
                  maxLength: 200,
                  decoration: InputDecoration(
                    hintText: 'Cuéntanos sobre tu experiencia...',
                    hintStyle: const TextStyle(color: textGray600),
                    filled: true,
                    fillColor: backgroundGray50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _participantHeader(
                  roleLabel: 'Hero Donador',
                  name: sellerName,
                  photoUrl: sellerPhotoUrl,
                ),
                const SizedBox(height: 16),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (index) {
                      final starIndex = index + 1;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _sellerRating = starIndex;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            starIndex <= _sellerRating
                                ? Icons.star
                                : Icons.star_border,
                            size: 48,
                            color: starIndex <= _sellerRating
                                ? primaryYellow
                                : textGray600,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    _getRatingText(_sellerRating),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textGray700,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Comentario (opcional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textGray900,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _sellerCommentController,
                  maxLines: 4,
                  maxLength: 200,
                  decoration: InputDecoration(
                    hintText: 'Cuéntanos sobre tu experiencia...',
                    hintStyle: const TextStyle(color: textGray600),
                    filled: true,
                    fillColor: backgroundGray50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitRating,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryOrange,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: borderGray100,
                disabledForegroundColor: textGray600,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Enviar calificación',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return 'Muy malo';
      case 2:
        return 'Malo';
      case 3:
        return 'Regular';
      case 4:
        return 'Bueno';
      case 5:
        return 'Excelente';
      default:
        return '';
    }
  }
}
