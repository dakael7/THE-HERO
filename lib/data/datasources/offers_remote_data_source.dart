import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';
import 'dart:typed_data';
import '../models/offer_model.dart';
import '../../domain/entities/offer.dart';

abstract class OffersRemoteDataSource {
  Future<OfferModel> createOffer(OfferModel offer);
  Future<OfferModel> updateOffer(OfferModel offer);
  Future<void> deleteOffer(String offerId);
  Future<OfferModel?> getOfferById(String offerId);
  Stream<List<OfferModel>> getOffersByHero(String heroId);
  Stream<List<OfferModel>> getActiveOffers({String? category, int limit = 20});
  Future<void> updateOfferStatus(String offerId, String status);
  Future<void> decrementStock(String offerId, int qty);
  Future<void> incrementStock(String offerId, int qty);
  Future<String> uploadOfferImage({
    required String heroId,
    required String offerId,
    required Uint8List bytes,
    required String fileName,
  });
}

class OffersRemoteDataSourceImpl implements OffersRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  OffersRemoteDataSourceImpl({
    required FirebaseFirestore firestore,
    required FirebaseStorage storage,
  }) : _firestore = firestore,
       _storage = storage;

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
  Future<String> uploadOfferImage({
    required String heroId,
    required String offerId,
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      if (bytes.isEmpty) {
        throw Exception('Archivo vacío');
      }

      final trimmedName = fileName.trim();
      final safeName = trimmedName.isEmpty ? 'image.jpg' : trimmedName;
      final ext = safeName.contains('.')
          ? safeName.split('.').last.toLowerCase()
          : 'jpg';

      final contentType = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'application/octet-stream',
      };

      final ref = _storage
          .ref()
          .child('offers')
          .child(heroId)
          .child(offerId)
          .child('${DateTime.now().millisecondsSinceEpoch}.$ext');

      final uploadTask = ref.putData(
        bytes,
        SettableMetadata(
          contentType: contentType,
          cacheControl: 'public,max-age=604800',
        ),
      );

      TaskSnapshot snapshot;
      try {
        snapshot = await uploadTask.timeout(const Duration(seconds: 45));
      } catch (e) {
        if (uploadTask.snapshot.state == TaskState.running) {
          await uploadTask.cancel();
        }
        rethrow;
      }

      if (snapshot.state != TaskState.success) {
        throw Exception('Subida incompleta: ${snapshot.state}');
      }

      final url = await ref.getDownloadURL().timeout(const Duration(seconds: 15));
      if (url.trim().isEmpty) {
        throw Exception('URL de descarga vacía');
      }
      return url;
    } catch (e) {
      throw Exception('Error al subir imagen: $e');
    }
  }

  @override
  Future<OfferModel> updateOffer(OfferModel offer) async {
    try {
      final data = offer.toJson();
      data.remove('moderationStatus');
      data.remove('reportCount');
      data.remove('lastReportedAt');
      await _firestore
          .collection('offers')
          .doc(offer.offerId)
          .update(data);
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
  Stream<List<OfferModel>> getOffersByHero(String heroId) async* {
    final query = _firestore
        .collection('offers')
        .where('heroId', isEqualTo: heroId)
        .orderBy('createdAt', descending: true);

    try {
      await for (final snapshot in query.snapshots()) {
        yield snapshot.docs
            .map((doc) => OfferModel.fromJson(doc.data()))
            .toList();
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        yield <OfferModel>[];
        return;
      }
      throw Exception('Error al obtener ofertas del hero: $e');
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

      final int fetchLimit = (limit * 3) > 100 ? 100 : (limit * 3);

      return query
          .orderBy('createdAt', descending: true)
          .limit(fetchLimit)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (doc) =>
                      OfferModel.fromJson(doc.data() as Map<String, dynamic>),
                )
                .where((offer) => offer.moderationStatus == ModerationStatus.visible)
                .take(limit)
                .toList(),
          );
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

        final data = offerDoc.data()!;
        final currentAvailableQty = data['availableQty'] as int;
        final currentStock = (data['stock'] as int?) ?? currentAvailableQty;
        final currentQty =
            currentAvailableQty < currentStock ? currentAvailableQty : currentStock;
        final newQty = currentQty - qty;

        if (newQty < 0) {
          throw Exception('Stock insuficiente');
        }

        final updateData = {
          'stock': newQty,
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

  @override
  Future<void> incrementStock(String offerId, int qty) async {
    try {
      await _firestore.runTransaction((transaction) async {
        final offerRef = _firestore.collection('offers').doc(offerId);
        final offerDoc = await transaction.get(offerRef);

        if (!offerDoc.exists) {
          throw Exception('Oferta no encontrada');
        }

        final currentQty = offerDoc.data()!['availableQty'] as int;
        final newQty = currentQty + qty;

        final updateData = {
          'availableQty': newQty,
          'orderCount': FieldValue.increment(-1),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // If was sold_out and now has stock, reactivate
        final currentStatus = offerDoc.data()!['status'] as String?;
        if (currentStatus == 'sold_out' && newQty > 0) {
          updateData['status'] = 'active';
        }

        transaction.update(offerRef, updateData);
      });
    } catch (e) {
      throw Exception('Error al incrementar stock: $e');
    }
  }
}
