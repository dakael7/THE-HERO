import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/models/offer_question_model.dart';
import '../../../../data/providers/network_providers.dart';
import '../../../../domain/entities/offer_question.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';

final offerQuestionsProvider = StreamProvider.family<List<OfferQuestion>, String>(
  (ref, offerId) {
    final firestore = ref.read(firebaseFirestoreProvider);

    return firestore
        .collection('offers')
        .doc(offerId)
        .collection('questions')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => OfferQuestionModel.fromJson({
                  ...doc.data(),
                  'questionId': doc.id,
                }).toEntity(),
              )
              .toList(),
        );
  },
);

final offerQuestionsActionsProvider = Provider<OfferQuestionsActions>((ref) {
  final firestore = ref.read(firebaseFirestoreProvider);
  final auth = ref.read(firebaseAuthProvider);
  return OfferQuestionsActions(ref: ref, firestore: firestore, auth: auth);
});

class OfferQuestionsActions {
  final Ref ref;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  OfferQuestionsActions({
    required this.ref,
    required this.firestore,
    required this.auth,
  });

  Future<void> askQuestion({
    required String offerId,
    required String question,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw Exception('Usuario no autenticado');
    }

    final trimmed = question.trim();
    if (trimmed.isEmpty) return;

    final profile = ref.read(profileProvider).value;
    final askerName = (profile?.fullName.trim().isNotEmpty ?? false)
        ? profile!.fullName
        : 'Usuario';

    final collectionRef =
        firestore.collection('offers').doc(offerId).collection('questions');

    final docRef = await collectionRef.add({
      'offerId': offerId,
      'askerId': user.uid,
      'askerName': askerName,
      'question': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
      'answer': null,
      'answeredById': null,
      'answeredAt': null,
      'questionId': '',
    });

    await docRef.update({'questionId': docRef.id});
  }

  Future<void> answerQuestion({
    required String offerId,
    required String questionId,
    required String answer,
    required String sellerId,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw Exception('Usuario no autenticado');
    }

    if (user.uid != sellerId) {
      throw Exception('Solo el dueño del producto puede responder');
    }

    final trimmed = answer.trim();
    if (trimmed.isEmpty) return;

    final questionRef = firestore
        .collection('offers')
        .doc(offerId)
        .collection('questions')
        .doc(questionId);

    await questionRef.update({
      'answer': trimmed,
      'answeredById': user.uid,
      'answeredAt': FieldValue.serverTimestamp(),
    });
  }
}
