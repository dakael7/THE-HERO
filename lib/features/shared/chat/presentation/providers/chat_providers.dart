import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../data/providers/network_providers.dart';
import '../../../../../data/providers/repository_providers.dart';
import '../../../../../domain/entities/chat.dart';
import '../../../../../domain/entities/chat_message.dart';
import '../../../../../domain/repositories/chat_repository.dart';

final userChatsProvider = StreamProvider<List<Chat>>((ref) {
  final auth = ref.read(firebaseAuthProvider);
  final user = auth.currentUser;
  if (user == null) {
    return Stream.value([]);
  }

  final repo = ref.read(chatRepositoryProvider);
  return repo.watchUserChats(user.uid);
});

final chatMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, chatId) {
  final auth = ref.read(firebaseAuthProvider);
  final user = auth.currentUser;
  if (user == null) {
    return Stream.error(Exception('Usuario no autenticado'));
  }
  final repo = ref.read(chatRepositoryProvider);
  return repo.watchChatMessages(chatId, limit: 100);
});

final chatActionsProvider = Provider<ChatActions>((ref) {
  final repo = ref.read(chatRepositoryProvider);
  final auth = ref.read(firebaseAuthProvider);
  final uid = auth.currentUser?.uid;
  return ChatActions(repo: repo, currentUserId: uid);
});

class ChatActions {
  final ChatRepository repo;
  final String? currentUserId;

  ChatActions({required this.repo, required this.currentUserId});

  Future<void> ensureChatExists(Chat chat) async {
    final uid = currentUserId;
    if (uid == null) {
      throw Exception('Usuario no autenticado');
    }
    await repo.ensureChatExists(chat);
  }

  Future<void> sendTextMessage({
    required String chatId,
    required String text,
  }) async {
    final uid = currentUserId;
    if (uid == null) {
      throw Exception('Usuario no autenticado');
    }

    await repo.sendTextMessage(chatId: chatId, senderId: uid, text: text);
  }
}
