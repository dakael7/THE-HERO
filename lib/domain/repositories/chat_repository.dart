import '../entities/chat.dart';
import '../entities/chat_message.dart';

abstract class ChatRepository {
  Stream<List<Chat>> watchUserChats(String userId);
  Stream<List<ChatMessage>> watchChatMessages(String chatId, {int limit = 50});
  Future<void> sendTextMessage({
    required String chatId,
    required String senderId,
    required String text,
  });

  Future<void> ensureChatExists(Chat chat);
}
