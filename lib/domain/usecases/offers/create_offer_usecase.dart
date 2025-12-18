import '../../entities/offer.dart';
import '../../repositories/offers_repository.dart';

class CreateOfferUseCase {
  final OffersRepository _repository;

  CreateOfferUseCase({required OffersRepository repository})
      : _repository = repository;

  Future<Offer> execute(Offer offer) async {
    return await _repository.createOffer(offer);
  }
}
