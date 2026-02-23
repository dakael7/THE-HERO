import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/favorites_remote_data_source.dart';
import '../../data/repositories/favorites_repository_impl.dart';
import '../../data/providers/network_providers.dart';
import '../repositories/favorites_repository.dart';

// Data Source Provider
final favoritesRemoteDataSourceProvider = Provider<FavoritesRemoteDataSource>((
  ref,
) {
  final firestore = ref.watch(firebaseFirestoreProvider);
  return FavoritesRemoteDataSourceImpl(firestore: firestore);
});

// Repository Provider
final favoritesRepositoryProvider = Provider<FavoritesRepository>((ref) {
  final dataSource = ref.watch(favoritesRemoteDataSourceProvider);
  return FavoritesRepositoryImpl(remoteDataSource: dataSource);
});

// Favorite Offer IDs Stream Provider
final favoriteOfferIdsProvider = StreamProvider.family<List<String>, String>((
  ref,
  userId,
) {
  final repository = ref.watch(favoritesRepositoryProvider);
  return repository.getFavoriteOfferIds(userId);
});

// Favorites Count Provider
final favoritesCountProvider = FutureProvider.family<int, String>((
  ref,
  userId,
) async {
  final repository = ref.watch(favoritesRepositoryProvider);
  return repository.getFavoritesCount(userId);
});

// Is Favorite Provider
final isFavoriteProvider = FutureProvider.family<bool, FavoriteParams>((
  ref,
  params,
) async {
  final repository = ref.watch(favoritesRepositoryProvider);
  return repository.isFavorite(params.userId, params.offerId);
});

class FavoriteParams {
  final String userId;
  final String offerId;

  FavoriteParams({required this.userId, required this.offerId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteParams &&
          runtimeType == other.runtimeType &&
          userId == other.userId &&
          offerId == other.offerId;

  @override
  int get hashCode => userId.hashCode ^ offerId.hashCode;
}

// Favorites Notifier for actions
class FavoritesNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() {
    return const AsyncValue.data(null);
  }

  Future<void> toggleFavorite(String userId, String offerId) async {
    state = const AsyncValue.loading();
    try {
      final repository = ref.read(favoritesRepositoryProvider);
      final isFav = await repository.isFavorite(userId, offerId);

      if (isFav) {
        await repository.removeFavorite(userId, offerId);
      } else {
        await repository.addFavorite(userId, offerId);
      }

      // Invalidate providers to refresh data
      ref.invalidate(favoriteOfferIdsProvider(userId));
      ref.invalidate(favoritesCountProvider(userId));
      ref.invalidate(isFavoriteProvider(FavoriteParams(userId: userId, offerId: offerId)));

      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }
}

final favoritesNotifierProvider =
    NotifierProvider<FavoritesNotifier, AsyncValue<void>>(() {
      return FavoritesNotifier();
    });
