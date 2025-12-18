import '../../entities/offer.dart';
import '../../repositories/offers_repository.dart';

class GetOffersByHeroUseCase {
  final OffersRepository _repository;

  GetOffersByHeroUseCase({required OffersRepository repository})
      : _repository = repository;

  Stream<List<Offer>> execute(String heroId) {
    return _repository.getOffersByHero(heroId);
  }
}
