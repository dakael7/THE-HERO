import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/order.dart';
import '../../../../../domain/entities/user.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../../shared/profile/presentation/providers/profile_provider.dart';

class InPersonPickupRatingScreen extends ConsumerStatefulWidget {
  final Order order;

  const InPersonPickupRatingScreen({super.key, required this.order});

  @override
  ConsumerState<InPersonPickupRatingScreen> createState() =>
      _InPersonPickupRatingScreenState();
}

class _InPersonPickupRatingScreenState
    extends ConsumerState<InPersonPickupRatingScreen> {
  int _rating = 5;
  bool _isSubmitting = false;
  final _commentController = TextEditingController();

  String? get _sellerId {
    for (final raw in widget.order.sellerHeroIds) {
      final sellerId = raw.trim();
      if (sellerId.isNotEmpty) return sellerId;
    }
    for (final item in widget.order.items) {
      final sellerId = item.sellerHeroIdSnapshot.trim();
      if (sellerId.isNotEmpty) return sellerId;
    }
    return null;
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final sellerId = _sellerId;
    if (sellerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo identificar al donador')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(orderActionsProvider).confirmInPersonPickupAndRateSeller(
            orderId: widget.order.orderId,
            sellerHeroId: sellerId,
            sellerRating: _rating.toDouble(),
            sellerComment: _commentController.text.trim().isEmpty
                ? null
                : _commentController.text.trim(),
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gracias por tu calificacion'),
          backgroundColor: categoryTextGreen,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la calificacion: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sellerId = _sellerId;
    final sellerAsync = sellerId == null
        ? const AsyncValue<User?>.data(null)
        : ref.watch(userByIdStreamProvider(sellerId));
    final sellerName = sellerAsync.maybeWhen(
      data: (user) => (user?.fullName.trim().isNotEmpty ?? false)
          ? user!.fullName
          : 'Hero Donador',
      orElse: () => 'Hero Donador',
    );
    final sellerPhotoUrl = sellerAsync.maybeWhen(
      data: (user) => user?.profilePhotoUrl,
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        title: const Text(
          'Calificar retiro',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SuccessCard(
            title: 'Retiro completado',
            message: 'Califica tu experiencia con el donador.',
          ),
          const SizedBox(height: 16),
          _RatingCard(
            roleLabel: 'Hero Donador',
            name: sellerName,
            photoUrl: sellerPhotoUrl,
            rating: _rating,
            onRatingChanged: (value) => setState(() => _rating = value),
            commentController: _commentController,
          ),
          const SizedBox(height: 24),
          _SubmitButton(
            isSubmitting: _isSubmitting,
            label: 'Enviar calificacion',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  final String title;
  final String message;

  const _SuccessCard({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: textGray900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: textGray700),
          ),
        ],
      ),
    );
  }
}

class _RatingCard extends StatelessWidget {
  final String roleLabel;
  final String name;
  final String? photoUrl;
  final int rating;
  final ValueChanged<int> onRatingChanged;
  final TextEditingController commentController;

  const _RatingCard({
    required this.roleLabel,
    required this.name,
    required this.photoUrl,
    required this.rating,
    required this.onRatingChanged,
    required this.commentController,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedUrl = photoUrl?.trim();
    final hasPhoto = resolvedUrl != null && resolvedUrl.isNotEmpty;

    return Container(
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
          Row(
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
          ),
          const SizedBox(height: 16),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                return GestureDetector(
                  onTap: () => onRatingChanged(starIndex),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      starIndex <= rating ? Icons.star : Icons.star_border,
                      size: 48,
                      color: starIndex <= rating ? primaryYellow : textGray600,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _ratingText(rating),
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
            controller: commentController,
            maxLines: 4,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: 'Cuentanos sobre tu experiencia...',
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
    );
  }

  static String _ratingText(int rating) {
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

class _SubmitButton extends StatelessWidget {
  final bool isSubmitting;
  final String label;
  final VoidCallback onPressed;

  const _SubmitButton({
    required this.isSubmitting,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isSubmitting ? null : onPressed,
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
        child: isSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}
