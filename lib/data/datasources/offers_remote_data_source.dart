import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/offer_model.dart';

abstract class OffersRemoteDataSource {
  Future<OfferModel> createOffer(OfferModel offer);
  Future<OfferModel> updateOffer(OfferModel offer);
  Future<void> deleteOffer(String offerId);
  Future<OfferModel?> getOfferById(String offerId);
  Stream<List<OfferModel>> getOffersByHero(String heroId);
  Stream<List<OfferModel>> getActiveOffers({String? category, int limit = 20});
  Future<void> updateOfferStatus(String offerId, String status);
  Future<void> decrementStock(String offerId, int qty);
}

class OffersRemoteDataSourceImpl implements OffersRemoteDataSource {
  final FirebaseFirestore _firestore;

  OffersRemoteDataSourceImpl({required FirebaseFirestore firestore})
      : _firestore = firestore;

  @override
  Future<OfferModel> createOffer(OfferModel offer) async {
    try {
      final docRef = await _firestore.collection('offers').add(offer.toJson());
      final createdOffer = offer.toJson();
      createdOffer['offerId'] = docRef.id;
      await docRef.update({'offerId': docRef.id});
      return OfferModel.fromJson(createdOffer);
    } catch (e) {
      throw Exception('Error al crear oferta: $e');
    }
  }

  @override
  Future<OfferModel> updateOffer(OfferModel offer) async {
    try {
      await _firestore
          .collection('offers')
          .doc(offer.offerId)
          .update(offer.toJson());
      return offer;
    } catch (e) {
      throw Exception('Error al actualizar oferta: $e');
    }
  }

  @override
  Future<void> deleteOffer(String offerId) async {
    try {
      await _firestore.collection('offers').doc(offerId).delete();
    } catch (e) {
      throw Exception('Error al eliminar oferta: $e');
    }
  }

  @override
  Future<OfferModel?> getOfferById(String offerId) async {
    try {
      final doc = await _firestore.collection('offers').doc(offerId).get();
      if (!doc.exists) return null;
      return OfferModel.fromJson(doc.data()!);
    } catch (e) {
      throw Exception('Error al obtener oferta: $e');
    }
  }

  @override
  Stream<List<OfferModel>> getOffersByHero(String heroId) {
    try {
      return _firestore
          .collection('offers')
          .where('heroId', isEqualTo: heroId)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => OfferModel.fromJson(doc.data()))
              .toList());
    } catch (e) {
      throw Exception('Error al obtener ofertas del hero: $e');
    }
  }

  @override
  Stream<List<OfferModel>> getActiveOffers({String? category, int limit = 20}) {
    try {
      Query query = _firestore
          .collection('offers')
          .where('status', isEqualTo: 'active');

      if (category != null && category.isNotEmpty) {
        query = query.where('category', isEqualTo: category);
      }

      return query
          .orderBy('publishedAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => OfferModel.fromJson(doc.data() as Map<String, dynamic>))
              .toList());
    } catch (e) {
      throw Exception('Error al obtener ofertas activas: $e');
    }
  }

  @override
  Future<void> updateOfferStatus(String offerId, String status) async {
    try {
      final updateData = {
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (status == 'active') {
        updateData['publishedAt'] = FieldValue.serverTimestamp();
      }

      await _firestore.collection('offers').doc(offerId).update(updateData);
    } catch (e) {
      throw Exception('Error al actualizar estado de oferta: $e');
    }
  }

  @override
  Future<void> decrementStock(String offerId, int qty) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final offerRef = _firestore.collection('offers').doc(offerId);
        final offerDoc = await transaction.get(offerRef);

        if (!offerDoc.exists) {
          throw Exception('Oferta no encontrada');
        }

        final currentQty = offerDoc.data()!['availableQty'] as int;
        final newQty = currentQty - qty;

        if (newQty < 0) {
          throw Exception('Stock insuficiente');
        }

        final updateData = {
          'availableQty': newQty,
          'orderCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (newQty == 0) {
          updateData['status'] = 'sold_out';
        }

        transaction.update(offerRef, updateData);
      });
    } catch (e) {
      throw Exception('Error al decrementar stock: $e');
    }
  }
}
