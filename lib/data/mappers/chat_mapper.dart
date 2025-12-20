import '../../domain/entities/chat.dart';
import '../models/chat_model.dart';

class ChatMapper {
  static Chat toEntity(ChatModel model) {
    return model.toEntity();
  }

  static ChatModel toModel(Chat entity) {
    return ChatModel.fromEntity(entity);
  }

  static List<Chat> toEntityList(List<ChatModel> models) {
    return models.map((model) => toEntity(model)).toList();
  }

  static List<ChatModel> toModelList(List<Chat> entities) {
    return entities.map((entity) => toModel(entity)).toList();
  }
}
