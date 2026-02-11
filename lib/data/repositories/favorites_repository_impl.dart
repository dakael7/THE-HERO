import '../../domain/repositories/favorites_repository.dart';
import '../datasources/favorites_remote_data_source.dart';

class FavoritesRepositoryImpl implements FavoritesRepository {
  final FavoritesRemoteDataSource _remoteDataSource;

  FavoritesRepositoryImpl({required FavoritesRemoteDataSource remoteDataSource})
    : _remoteDataSource = remoteDataSource;

  @override
  Future<void> addFavorite(String userId, String offerId) async {
    try {
      await _remoteDataSource.addFavorite(userId, offerId);
    } catch (e) {
      throw Exception('Error al agregar favorito: $e');
    }
  }

  @override
  Future<void> removeFavorite(String userId, String offerId) async {
    try {
      await _remoteDataSource.removeFavorite(userId, offerId);
    } catch (e) {
      throw Exception('Error al eliminar favorito: $e');
    }
  }

  @override
  Stream<List<String>> getFavoriteOfferIds(String userId) {
    try {
      return _remoteDataSource.getFavoriteOfferIds(userId);
    } catch (e) {
      throw Exception('Error al obtener favoritos: $e');
    }
  }

  @override
  Future<bool> isFavorite(String userId, String offerId) async {
    try {
      return await _remoteDataSource.isFavorite(userId, offerId);
    } catch (e) {
      throw Exception('Error al verificar favorito: $e');
    }
  }

  @override
  Future<int> getFavoritesCount(String userId) async {
    try {
      return await _remoteDataSource.getFavoritesCount(userId);
    } catch (e) {
      throw Exception('Error al contar favoritos: $e');
    }
  }
}
