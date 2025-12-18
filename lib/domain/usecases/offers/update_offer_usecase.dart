import '../../entities/offer.dart';
import '../../repositories/offers_repository.dart';

class UpdateOfferUseCase {
  final OffersRepository _repository;

  UpdateOfferUseCase({required OffersRepository repository})
      : _repository = repository;

  Future<Offer> execute(Offer offer) async {
    return await _repository.updateOffer(offer);
  }
}
