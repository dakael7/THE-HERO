abstract class FavoritesRepository {
  Future<void> addFavorite(String userId, String offerId);
  Future<void> removeFavorite(String userId, String offerId);
  Stream<List<String>> getFavoriteOfferIds(String userId);
  Future<bool> isFavorite(String userId, String offerId);
  Future<int> getFavoritesCount(String userId);
}
