import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../../data/providers/network_providers.dart';
import '../../../../../data/providers/repository_providers.dart';
import '../../../../../data/models/chat_model.dart';
import '../../../../../data/models/order_model.dart';
import '../../../../../domain/entities/chat.dart';
import '../../../../../domain/entities/chat_message.dart';
import '../../../../../domain/repositories/chat_repository.dart';

String? _visibleOrderId(String docId, Map<String, dynamic>? data) {
  if (data == null) return null;
  final hasOrderId = data['orderId']?.toString().trim().isNotEmpty ?? false;
  final order = OrderModel.fromJson({
    ...data,
    if (!hasOrderId) 'orderId': docId,
  }).toEntity();
  if (!order.canShowAssociatedChats) return null;
  final orderId = order.orderId.trim();
  return orderId.isNotEmpty ? orderId : docId;
}

Future<bool> _canShowChatForOrderPayment(
  FirebaseFirestore firestore,
  Chat chat,
) async {
  final orderId = chat.orderId?.trim() ?? '';
  if (orderId.isEmpty) return true;

  final doc = await firestore.collection('orders').doc(orderId).get();
  return _visibleOrderId(doc.id, doc.data()) != null;
}

Future<List<Chat>> _filterUnpaidOrderChats(
  FirebaseFirestore firestore,
  List<Chat> chats,
) async {
  final orderIds = chats
      .map((chat) => chat.orderId?.trim() ?? '')
      .where((orderId) => orderId.isNotEmpty)
      .toSet();
  if (orderIds.isEmpty) return chats;

  // ponytail: per-order reads are fine for small chat lists; batch/mirror if chat volume grows.
  final snapshots = await Future.wait(
    orderIds.map(
      (orderId) => firestore.collection('orders').doc(orderId).get(),
    ),
  );
  final visibleOrderIds = <String>{};

  for (final doc in snapshots) {
    final visibleOrderId = _visibleOrderId(doc.id, doc.data());
    if (visibleOrderId != null) visibleOrderIds.add(visibleOrderId);
  }

  return chats.where((chat) {
    final orderId = chat.orderId?.trim() ?? '';
    return orderId.isEmpty || visibleOrderIds.contains(orderId);
  }).toList();
}

final userChatsProvider = StreamProvider<List<Chat>>((ref) {
  final user = ref.watch(firebaseAuthUserProvider).value;
  if (user == null) {
    return Stream.value([]);
  }

  final repo = ref.read(chatRepositoryProvider);
  final firestore = ref.read(firebaseFirestoreProvider);
  return repo
      .watchUserChats(user.uid)
      .asyncMap((chats) => _filterUnpaidOrderChats(firestore, chats));
});

final chatByIdProvider = StreamProvider.family<Chat?, String>((ref, chatId) {
  final user = ref.watch(firebaseAuthUserProvider).value;
  if (user == null) {
    return Stream.value(null);
  }

  final firestore = ref.read(firebaseFirestoreProvider);
  return firestore.collection('chats').doc(chatId).snapshots().asyncMap((
    snap,
  ) async {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    final chat = ChatModel.fromJson({'chatId': snap.id, ...data}).toEntity();
    if (!await _canShowChatForOrderPayment(firestore, chat)) return null;
    return chat;
  });
});

final chatMessagesProvider = StreamProvider.family<List<ChatMessage>, String>((
  ref,
  chatId,
) {
  final user = ref.watch(firebaseAuthUserProvider).value;
  if (user == null) {
    return Stream.value([]);
  }
  final repo = ref.read(chatRepositoryProvider);
  return repo.watchChatMessages(chatId, limit: 100);
});

final chatTypingProvider = StreamProvider.family<Map<String, DateTime>, String>(
  (ref, chatId) {
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
  },
);

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
