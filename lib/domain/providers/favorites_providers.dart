import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/favorites_remote_data_source.dart';
import '../../data/repositories/favorites_repository_impl.dart';
import '../../data/providers/network_providers.dart';
import '../repositories/favorites_repository.dart';
import '../../core/utils/stream_first_event_timeout.dart';

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
  return withFirstEventTimeout(
    repository.getFavoriteOfferIds(userId),
    message:
        'No pudimos cargar tus favoritos a tiempo. Revisa tu conexion e intentalo nuevamente.',
  );
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
class FavoritesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    return <String>{};
  }

  String _pendingKey(String userId, String offerId) => '$userId::$offerId';

  bool isPending(String userId, String offerId) {
    return state.contains(_pendingKey(userId, offerId));
  }

  Future<void> setFavorite({
    required String userId,
    required String offerId,
    required bool shouldBeFavorite,
  }) async {
    final pendingKey = _pendingKey(userId, offerId);
    if (state.contains(pendingKey)) {
      return;
    }

    state = {...state, pendingKey};

    try {
      final repository = ref.read(favoritesRepositoryProvider);
      if (shouldBeFavorite) {
        await repository.addFavorite(userId, offerId);
      } else {
        await repository.removeFavorite(userId, offerId);
      }

      // Invalidate providers to refresh data
      ref.invalidate(favoriteOfferIdsProvider(userId));
      ref.invalidate(favoritesCountProvider(userId));
      ref.invalidate(
        isFavoriteProvider(FavoriteParams(userId: userId, offerId: offerId)),
      );
    } catch (e, stack) {
      Error.throwWithStackTrace(e, stack);
    } finally {
      final updated = {...state};
      updated.remove(pendingKey);
      state = updated;
    }
  }

  Future<void> toggleFavorite(
    String userId,
    String offerId, {
    required bool isCurrentlyFavorite,
  }) {
    return setFavorite(
      userId: userId,
      offerId: offerId,
      shouldBeFavorite: !isCurrentlyFavorite,
    );
  }
}

final favoritesNotifierProvider =
    NotifierProvider<FavoritesNotifier, Set<String>>(() {
      return FavoritesNotifier();
    });
