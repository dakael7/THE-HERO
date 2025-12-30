import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_model.dart';
import '../models/chat_message_model.dart';

abstract class ChatRemoteDataSource {
  Stream<List<ChatModel>> watchUserChats(String userId);
  Stream<List<ChatMessageModel>> watchChatMessages(String chatId, {int limit = 50});
  Future<void> sendTextMessage({
    required String chatId,
    required String senderId,
    required String text,
  });

  Future<void> ensureChatExists(ChatModel chat);
}

class ChatRemoteDataSourceImpl implements ChatRemoteDataSource {
  final FirebaseFirestore _firestore;

  ChatRemoteDataSourceImpl({required FirebaseFirestore firestore})
      : _firestore = firestore;

  @override
  Stream<List<ChatModel>> watchUserChats(String userId) async* {
    final baseQuery = _firestore
        .collection('chats')
        .where('participantIds', arrayContains: userId);

    Stream<List<ChatModel>> streamFromQuery(
      Query<Map<String, dynamic>> query,
    ) {
      return query.snapshots().map(
            (snapshot) => snapshot.docs
                .map(
                  (doc) => ChatModel.fromJson({
                    'chatId': doc.id,
                    ...doc.data(),
                  }),
                )
                .toList(),
          );
    }

    try {
      await for (final chats in streamFromQuery(
        baseQuery.orderBy('lastMessageAt', descending: true),
      )) {
        yield chats;
      }
    } catch (e) {
      await for (final chats in streamFromQuery(baseQuery)) {
        yield chats;
      }
    }
  }

  @override
  Stream<List<ChatMessageModel>> watchChatMessages(String chatId,
      {int limit = 50}) {
    try {
      return _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('sentAt', descending: false)
          .limit(limit)
          .snapshots()
          .map((snapshot) => snapshot.docs
              .map((doc) => ChatMessageModel.fromJson({
                    'messageId': doc.id,
                    ...doc.data(),
                  }))
              .toList());
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
      final chatRef = _firestore.collection('chats').doc(chatId);
      final messagesRef = chatRef.collection('messages');

      final messageDoc = messagesRef.doc();

      await _firestore.runTransaction((transaction) async {
        final nowServer = FieldValue.serverTimestamp();

        transaction.set(messageDoc, {
          'messageId': messageDoc.id,
          'chatId': chatId,
          'senderId': senderId,
          'text': text,
          'sentAt': nowServer,
          'editedAt': null,
          'readAt': null,
          'deleted': false,
          'version': 1,
        });

        transaction.update(chatRef, {
          'lastMessageText': text,
          'lastMessageAt': nowServer,
          'updatedAt': nowServer,
        });
      });
    } catch (e) {
      throw Exception('Error al enviar mensaje: $e');
    }
  }

  @override
  Future<void> ensureChatExists(ChatModel chat) async {
    try {
      final chatRef = _firestore.collection('chats').doc(chat.chatId);
      final existing = await chatRef.get();
      if (existing.exists) return;

      final nowServer = FieldValue.serverTimestamp();
      final data = chat.toJson();

      await chatRef.set({
        ...data,
        'createdAt': nowServer,
        'updatedAt': nowServer,
        'lastMessageAt': nowServer,
      });
    } catch (e) {
      throw Exception('Error al crear chat: $e');
    }
  }
}
