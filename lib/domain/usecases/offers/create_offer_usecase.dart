import '../../entities/offer.dart';
import '../../entities/user.dart';
import '../../repositories/offers_repository.dart';

class CreateOfferUseCase {
  final OffersRepository _repository;

  CreateOfferUseCase({required OffersRepository repository})
      : _repository = repository;

  Future<Offer> execute(Offer offer, {required User currentUser}) async {
    if (currentUser.isBanned) {
      throw Exception('Tu cuenta está baneada.');
    }
    if (currentUser.isSuspended) {
      throw Exception('Tu cuenta está suspendida. No puedes realizar esta acción.');
    }
    return await _repository.createOffer(offer);
  }
}
