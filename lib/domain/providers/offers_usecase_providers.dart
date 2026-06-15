import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/providers/repository_providers.dart';
import '../usecases/offers/create_offer_usecase.dart';
import '../usecases/offers/update_offer_usecase.dart';
import '../usecases/offers/get_offers_by_hero_usecase.dart';
import '../usecases/offers/get_active_offers_usecase.dart';
import '../usecases/offers/publish_offer_usecase.dart';

part 'offers_usecase_providers.g.dart';

@Riverpod(keepAlive: true)
CreateOfferUseCase createOfferUseCase(Ref ref) {
  final repository = ref.read(offersRepositoryProvider);
  return CreateOfferUseCase(repository: repository);
}

@Riverpod(keepAlive: true)
UpdateOfferUseCase updateOfferUseCase(Ref ref) {
  final repository = ref.read(offersRepositoryProvider);
  return UpdateOfferUseCase(repository: repository);
}

@Riverpod(keepAlive: true)
GetOffersByHeroUseCase getOffersByHeroUseCase(Ref ref) {
  final repository = ref.read(offersRepositoryProvider);
  return GetOffersByHeroUseCase(repository: repository);
}

@Riverpod(keepAlive: true)
GetActiveOffersUseCase getActiveOffersUseCase(Ref ref) {
  final repository = ref.read(offersRepositoryProvider);
  return GetActiveOffersUseCase(repository: repository);
}

@Riverpod(keepAlive: true)
PublishOfferUseCase publishOfferUseCase(Ref ref) {
  final repository = ref.read(offersRepositoryProvider);
  return PublishOfferUseCase(repository: repository);
}
