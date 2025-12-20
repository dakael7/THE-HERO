import '../../domain/entities/chat_message.dart';
import '../models/chat_message_model.dart';

class ChatMessageMapper {
  static ChatMessage toEntity(ChatMessageModel model) {
    return model.toEntity();
  }

  static ChatMessageModel toModel(ChatMessage entity) {
    return ChatMessageModel.fromEntity(entity);
  }

  static List<ChatMessage> toEntityList(List<ChatMessageModel> models) {
    return models.map((model) => toEntity(model)).toList();
  }

  static List<ChatMessageModel> toModelList(List<ChatMessage> entities) {
    return entities.map((entity) => toModel(entity)).toList();
  }
}
