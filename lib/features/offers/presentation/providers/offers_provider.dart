import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/entities/offer.dart';
import '../../../../domain/providers/offers_usecase_providers.dart';
import '../../../shared/profile/presentation/providers/profile_provider.dart';
import '../../../../core/utils/stream_first_event_timeout.dart';

final myOffersProvider = StreamProvider.family<List<Offer>, String>((ref, heroId) {
  final useCase = ref.read(getOffersByHeroUseCaseProvider);
  return withFirstEventTimeout(
    useCase.execute(heroId),
    message:
        'No pudimos cargar tus donaciones a tiempo. Revisa tu conexion e intentalo nuevamente.',
  );
});

final activeOffersProvider =
    StreamProvider.family<List<Offer>, OffersFilter>((ref, filter) {
  final useCase = ref.read(getActiveOffersUseCaseProvider);
  return withFirstEventTimeout(
    useCase.execute(
      category: filter.category,
      limit: filter.limit,
    ),
    message:
        'No pudimos cargar las ofertas activas a tiempo. Revisa tu conexion e intentalo nuevamente.',
  );
});

class OffersFilter {
  final String? category;
  final int limit;

  OffersFilter({this.category, this.limit = 20});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OffersFilter &&
          runtimeType == other.runtimeType &&
          category == other.category &&
          limit == other.limit;

  @override
  int get hashCode => category.hashCode ^ limit.hashCode;
}

class OfferNotifier extends Notifier<AsyncValue<Offer?>> {
  @override
  AsyncValue<Offer?> build() {
    return const AsyncValue.data(null);
  }

  Future<Offer> createOffer(Offer offer) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(profileStreamProvider).value ??
          await ref.read(profileProvider.future);
      if (user == null) {
        throw Exception('Debes iniciar sesión para crear una oferta.');
      }
      final useCase = ref.read(createOfferUseCaseProvider);
      final createdOffer = await useCase.execute(offer, currentUser: user);
      state = AsyncValue.data(createdOffer);
      return createdOffer;
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<Offer> updateOffer(Offer offer) async {
    state = const AsyncValue.loading();
    try {
      final useCase = ref.read(updateOfferUseCaseProvider);
      final updatedOffer = await useCase.execute(offer);
      state = AsyncValue.data(updatedOffer);
      return updatedOffer;
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
      rethrow;
    }
  }

  Future<void> publishOffer(String offerId) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(profileStreamProvider).value ??
          await ref.read(profileProvider.future);
      if (user == null) {
        throw Exception('Debes iniciar sesión para publicar una oferta.');
      }
      final useCase = ref.read(publishOfferUseCaseProvider);
      await useCase.execute(offerId, currentUser: user);
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}

final offerNotifierProvider =
    NotifierProvider<OfferNotifier, AsyncValue<Offer?>>(() {
  return OfferNotifier();
});
