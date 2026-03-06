import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../../data/providers/network_providers.dart';
import '../../../../../data/providers/repository_providers.dart';
import '../../../../../data/models/chat_model.dart';
import '../../../../../domain/entities/chat.dart';
import '../../../../../domain/entities/chat_message.dart';
import '../../../../../domain/repositories/chat_repository.dart';

final userChatsProvider = StreamProvider<List<Chat>>((ref) {
  final user = ref.watch(firebaseAuthUserProvider).value;
  if (user == null) {
    return Stream.value([]);
  }

  final repo = ref.read(chatRepositoryProvider);
  return repo.watchUserChats(user.uid);
});

final chatByIdProvider = StreamProvider.family<Chat?, String>((ref, chatId) {
  final user = ref.watch(firebaseAuthUserProvider).value;
  if (user == null) {
    return Stream.value(null);
  }

  final firestore = ref.read(firebaseFirestoreProvider);
  return firestore
      .collection('chats')
      .doc(chatId)
      .snapshots()
      .map((snap) {
        final data = snap.data();
        if (!snap.exists || data == null) return null;
        return ChatModel.fromJson({'chatId': snap.id, ...data}).toEntity();
      });
});

final chatMessagesProvider = StreamProvider.family<List<ChatMessage>, String>((ref, chatId) {
  final user = ref.watch(firebaseAuthUserProvider).value;
  if (user == null) {
    return Stream.value([]);
  }
  final repo = ref.read(chatRepositoryProvider);
  return repo.watchChatMessages(chatId, limit: 100);
});

final chatTypingProvider = StreamProvider.family<Map<String, DateTime>, String>((
  ref,
  chatId,
) {
  final user = ref.watch(firebaseAuthUserProvider).value;
  if (user == null) {
    return Stream.value(<String, DateTime>{});
  }

  final firestore = ref.read(firebaseFirestoreProvider);
  return firestore.collection('chats').doc(chatId).snapshots().map((snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return <String, DateTime>{};
    final raw = data['typing'];
    if (raw is! Map) return <String, DateTime>{};

    final result = <String, DateTime>{};
    for (final entry in raw.entries) {
      final key = entry.key?.toString();
      final value = entry.value;
      if (key == null || key.trim().isEmpty) continue;

      if (value is Timestamp) {
        result[key] = value.toDate();
      }
    }
    return result;
  });
});

final chatActionsProvider = Provider<ChatActions>((ref) {
  final repo = ref.read(chatRepositoryProvider);
  final uid = ref.watch(firebaseAuthUserProvider).value?.uid;
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

  Future<void> setTyping({
    required String chatId,
    required bool isTyping,
  }) async {
    final uid = currentUserId;
    if (uid == null) {
      throw Exception('Usuario no autenticado');
    }

    await repo.setTyping(chatId: chatId, userId: uid, isTyping: isTyping);
  }

  Future<void> markMessagesAsRead(String chatId) async {
    final uid = currentUserId;
    if (uid == null) {
      throw Exception('Usuario no autenticado');
    }

    try {
      await repo.markMessagesAsRead(chatId: chatId, userId: uid);
    } catch (_) {
      return;
    }
  }
}
