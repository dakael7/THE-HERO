import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/models/offer_comment_model.dart';
import '../../../../domain/entities/offer_comment.dart';

// Provider to fetch comments (questions) for a specific offer
final offerCommentsProvider = StreamProvider.family<List<OfferComment>, String>(
  (ref, offerId) {
    final firestore = FirebaseFirestore.instance;

    return firestore
        .collection('offers')
        .doc(offerId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map(
                (doc) => OfferCommentModel.fromJson({
                  ...doc.data(),
                  'commentId': doc.id,
                }).toEntity(),
              )
              .toList();
        });
  },
);

// Notifier for adding comments (questions)
class AddCommentNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() {
    return const AsyncValue.data(null);
  }

  Future<void> addComment({
    required String offerId,
    required String userId,
    required String userName,
    String? userAvatarUrl,
    required String text,
  }) async {
    state = const AsyncValue.loading();

    try {
      final firestore = FirebaseFirestore.instance;
      final now = Timestamp.now();

      // Create comment document
      final commentRef = firestore
          .collection('offers')
          .doc(offerId)
          .collection('comments')
          .doc();

      final comment = OfferCommentModel(
        commentId: commentRef.id,
        offerId: offerId,
        userId: userId,
        userName: userName,
        userAvatarUrl: userAvatarUrl,
        text: text,
        createdAt: now,
        updatedAt: now,
      );

      await commentRef.set(comment.toJson());

      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  // Reply to a comment (only offer owner)
  Future<void> replyToComment({
    required String offerId,
    required String commentId,
    required String reply,
    required String replyBy,
  }) async {
    state = const AsyncValue.loading();

    try {
      final firestore = FirebaseFirestore.instance;

      await firestore
          .collection('offers')
          .doc(offerId)
          .collection('comments')
          .doc(commentId)
          .update({
            'reply': reply,
            'replyBy': replyBy,
            'repliedAt': Timestamp.now(),
            'updatedAt': Timestamp.now(),
          });

      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }
}

final addCommentProvider =
    NotifierProvider<AddCommentNotifier, AsyncValue<void>>(() {
      return AddCommentNotifier();
    });

// Provider to increment view count
final incrementViewCountProvider = FutureProvider.family<void, String>((
  ref,
  offerId,
) async {
  final firestore = FirebaseFirestore.instance;

  final docRef = firestore.collection('offers').doc(offerId);

  await firestore.runTransaction((tx) async {
    final snap = await tx.get(docRef);
    if (!snap.exists) return;

    final data = snap.data();
    final current = (data == null) ? 0 : (data['viewCount'] as int?) ?? 0;
    tx.update(docRef, {'viewCount': current + 1});
  });
});
