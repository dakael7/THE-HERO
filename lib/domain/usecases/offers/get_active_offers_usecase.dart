import '../../entities/offer.dart';
import '../../repositories/offers_repository.dart';

class GetActiveOffersUseCase {
  final OffersRepository _repository;

  GetActiveOffersUseCase({required OffersRepository repository})
      : _repository = repository;

  Stream<List<Offer>> execute({String? category, int limit = 20}) {
    return _repository.getActiveOffers(category: category, limit: limit);
  }
}
