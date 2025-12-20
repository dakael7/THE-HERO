import '../../domain/entities/chat.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_remote_data_source.dart';
import '../mappers/chat_mapper.dart';
import '../mappers/chat_message_mapper.dart';
import '../models/chat_model.dart';

class ChatRepositoryImpl implements ChatRepository {
  final ChatRemoteDataSource _remoteDataSource;

  ChatRepositoryImpl({required ChatRemoteDataSource remoteDataSource})
      : _remoteDataSource = remoteDataSource;

  @override
  Stream<List<Chat>> watchUserChats(String userId) {
    try {
      return _remoteDataSource
          .watchUserChats(userId)
          .map((models) => ChatMapper.toEntityList(models));
    } catch (e) {
      throw Exception('Error al obtener chats del usuario: $e');
    }
  }

  @override
  Stream<List<ChatMessage>> watchChatMessages(String chatId, {int limit = 50}) {
    try {
      return _remoteDataSource
          .watchChatMessages(chatId, limit: limit)
          .map((models) => ChatMessageMapper.toEntityList(models));
    } catch (e) {
      throw Exception('Error al obtener mensajes del chat: $e');
    }
  }

  @override
  Future<void> sendTextMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    try {
      await _remoteDataSource.sendTextMessage(
        chatId: chatId,
        senderId: senderId,
        text: text,
      );
    } catch (e) {
      throw Exception('Error al enviar mensaje: $e');
    }
  }

  @override
  Future<void> ensureChatExists(Chat chat) async {
    try {
      final model = ChatModel.fromEntity(chat);
      await _remoteDataSource.ensureChatExists(model);
    } catch (e) {
      throw Exception('Error al crear chat: $e');
    }
  }
}
