import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/favorite_model.dart';

abstract class FavoritesRemoteDataSource {
  Future<void> addFavorite(String userId, String offerId);
  Future<void> removeFavorite(String userId, String offerId);
  Stream<List<String>> getFavoriteOfferIds(String userId);
  Future<bool> isFavorite(String userId, String offerId);
  Future<int> getFavoritesCount(String userId);
}

class FavoritesRemoteDataSourceImpl implements FavoritesRemoteDataSource {
  final FirebaseFirestore _firestore;

  FavoritesRemoteDataSourceImpl({required FirebaseFirestore firestore})
    : _firestore = firestore;

  @override
  Future<void> addFavorite(String userId, String offerId) async {
    try {
      final favoriteModel = FavoriteModel(
        userId: userId,
        offerId: offerId,
        createdAt: Timestamp.now(),
      );

      await _firestore
          .collection('favorites')
          .doc(userId)
          .collection('offers')
          .doc(offerId)
          .set(favoriteModel.toJson());
    } catch (e) {
      throw Exception('Error al agregar favorito: $e');
    }
  }

  @override
  Future<void> removeFavorite(String userId, String offerId) async {
    try {
      await _firestore
          .collection('favorites')
          .doc(userId)
          .collection('offers')
          .doc(offerId)
          .delete();
    } catch (e) {
      throw Exception('Error al eliminar favorito: $e');
    }
  }

  @override
  Stream<List<String>> getFavoriteOfferIds(String userId) async* {
    final query = _firestore
        .collection('favorites')
        .doc(userId)
        .collection('offers')
        .orderBy('createdAt', descending: true);

    try {
      await for (final snapshot in query.snapshots()) {
        yield snapshot.docs.map((doc) => doc.id).toList();
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        yield <String>[];
        return;
      }
      throw Exception('Error al obtener favoritos: $e');
    } catch (e) {
      throw Exception('Error al obtener favoritos: $e');
    }
  }

  @override
  Future<bool> isFavorite(String userId, String offerId) async {
    try {
      final doc = await _firestore
          .collection('favorites')
          .doc(userId)
          .collection('offers')
          .doc(offerId)
          .get();
      return doc.exists;
    } catch (e) {
      throw Exception('Error al verificar favorito: $e');
    }
  }

  @override
  Future<int> getFavoritesCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('favorites')
          .doc(userId)
          .collection('offers')
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      throw Exception('Error al contar favoritos: $e');
    }
  }
}
