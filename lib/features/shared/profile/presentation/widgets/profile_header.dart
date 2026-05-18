import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/user.dart';
import '../../../../offers/presentation/widgets/star_rating_widget.dart';

class ProfileHeader extends StatelessWidget {
  final User user;
  final bool isRiderProfile;
  final VoidCallback? onPhotoTap;
  final bool isPhotoUpdating;

  const ProfileHeader({
    super.key,
    required this.user,
    this.isRiderProfile = false,
    this.onPhotoTap,
    this.isPhotoUpdating = false,
  });

  @override
  Widget build(BuildContext context) {
    final isVerified = user.isRutVerified;
    final photoUrl = user.profilePhotoUrl?.trim();
    final hasPhoto = photoUrl != null && photoUrl.isNotEmpty;

    final ratingValue = isRiderProfile
        ? (user.riderProfile?.rating ?? 0.0)
        : (user.heroProfile?.rating ?? 0.0);
    final ratingCount = isRiderProfile
        ? (user.riderProfile?.totalRatings ?? 0)
        : (user.heroProfile?.totalRatings ?? 0);
    final hasRating = ratingCount > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: backgroundWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderGray100, width: 1),
          boxShadow: [
            BoxShadow(
              color: textGray900.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: onPhotoTap,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          primaryOrange.withValues(alpha: 0.25),
                          primaryYellow.withValues(alpha: 0.55),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: primaryOrange.withValues(alpha: 0.55),
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: hasPhoto
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              width: 64,
                              height: 64,
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Icon(
                                    Icons.person,
                                    size: 30,
                                    color: primaryOrange,
                                  ),
                                );
                              },
                            )
                          : const Center(
                              child: Icon(
                                Icons.person,
                                size: 30,
                                color: primaryOrange,
                              ),
                            ),
                    ),
                  ),
                  if (onPhotoTap != null)
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: primaryOrange,
                          shape: BoxShape.circle,
                          border: Border.all(color: backgroundWhite, width: 2),
                        ),
                        child: isPhotoUpdating
                            ? const Padding(
                                padding: EdgeInsets.all(5),
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    backgroundWhite,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.edit_rounded,
                                size: 12,
                                color: backgroundWhite,
                              ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: textGray900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: textGray600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      StarRatingWidget(
                        rating: ratingValue.clamp(0.0, 5.0),
                        size: 18,
                        readonly: true,
                        activeColor: categoryTextYellow,
                        inactiveColor: textGray600.withValues(alpha: 0.45),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hasRating
                            ? '${ratingValue.toStringAsFixed(1)} ($ratingCount)'
                            : '0.0 (0)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: textGray900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (isVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: primaryOrange.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: primaryOrange.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Text(
                        isRiderProfile ? 'Rider Verificado' : 'Héroe Verificado',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: primaryOrange,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
