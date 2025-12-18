import '../../domain/entities/offer.dart';
import '../models/offer_model.dart';

class OfferMapper {
  static Offer toEntity(OfferModel model) {
    return model.toEntity();
  }

  static OfferModel toModel(Offer entity) {
    return OfferModel.fromEntity(entity);
  }

  static List<Offer> toEntityList(List<OfferModel> models) {
    return models.map((model) => toEntity(model)).toList();
  }

  static List<OfferModel> toModelList(List<Offer> entities) {
    return entities.map((entity) => toModel(entity)).toList();
  }
}
