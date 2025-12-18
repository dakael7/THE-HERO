import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../domain/entities/offer.dart';
import '../../../../domain/providers/offers_usecase_providers.dart';

final myOffersProvider = StreamProvider.family<List<Offer>, String>((ref, heroId) {
  final useCase = ref.read(getOffersByHeroUseCaseProvider);
  return useCase.execute(heroId);
});

final activeOffersProvider = StreamProvider.autoDispose
    .family<List<Offer>, OffersFilter>((ref, filter) {
  final useCase = ref.read(getActiveOffersUseCaseProvider);
  return useCase.execute(
    category: filter.category,
    limit: filter.limit,
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

  Future<void> createOffer(Offer offer) async {
    state = const AsyncValue.loading();
    try {
      final useCase = ref.read(createOfferUseCaseProvider);
      final createdOffer = await useCase.execute(offer);
      state = AsyncValue.data(createdOffer);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> updateOffer(Offer offer) async {
    state = const AsyncValue.loading();
    try {
      final useCase = ref.read(updateOfferUseCaseProvider);
      final updatedOffer = await useCase.execute(offer);
      state = AsyncValue.data(updatedOffer);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> publishOffer(String offerId) async {
    state = const AsyncValue.loading();
    try {
      final useCase = ref.read(publishOfferUseCaseProvider);
      await useCase.execute(offerId);
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
