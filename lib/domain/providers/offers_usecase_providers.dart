import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/repository_providers.dart';
import '../usecases/offers/create_offer_usecase.dart';
import '../usecases/offers/update_offer_usecase.dart';
import '../usecases/offers/get_offers_by_hero_usecase.dart';
import '../usecases/offers/get_active_offers_usecase.dart';
import '../usecases/offers/publish_offer_usecase.dart';

final createOfferUseCaseProvider = Provider<CreateOfferUseCase>((ref) {
  final repository = ref.read(offersRepositoryProvider);
  return CreateOfferUseCase(repository: repository);
});

final updateOfferUseCaseProvider = Provider<UpdateOfferUseCase>((ref) {
  final repository = ref.read(offersRepositoryProvider);
  return UpdateOfferUseCase(repository: repository);
});

final getOffersByHeroUseCaseProvider = Provider<GetOffersByHeroUseCase>((ref) {
  final repository = ref.read(offersRepositoryProvider);
  return GetOffersByHeroUseCase(repository: repository);
});

final getActiveOffersUseCaseProvider = Provider<GetActiveOffersUseCase>((ref) {
  final repository = ref.read(offersRepositoryProvider);
  return GetActiveOffersUseCase(repository: repository);
});

final publishOfferUseCaseProvider = Provider<PublishOfferUseCase>((ref) {
  final repository = ref.read(offersRepositoryProvider);
  return PublishOfferUseCase(repository: repository);
});
