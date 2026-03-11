import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_model.dart';
import '../models/chat_message_model.dart';

abstract class ChatRemoteDataSource {
  Stream<List<ChatModel>> watchUserChats(String userId);
  Stream<List<ChatMessageModel>> watchChatMessages(
    String chatId, {
    int limit = 50,
  });
  Future<void> sendTextMessage({
    required String chatId,
    required String senderId,
    required String text,
  });

  Future<void> setTyping({
    required String chatId,
    required String userId,
    required bool isTyping,
  });

  Future<void> ensureChatExists(ChatModel chat);
  Future<void> markMessagesAsRead({
    required String chatId,
    required String userId,
  });
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

    Stream<List<ChatModel>> streamFromQuery(Query<Map<String, dynamic>> query) {
      return query.snapshots().map(
        (snapshot) => snapshot.docs
            .map((doc) => ChatModel.fromJson({'chatId': doc.id, ...doc.data()}))
            .toList(),
      );
    }

    try {
      await for (final chats in streamFromQuery(
        baseQuery.orderBy('lastMessageAt', descending: true),
      )) {
        yield chats;
      }
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        yield <ChatModel>[];
        return;
      }
      try {
        await for (final chats in streamFromQuery(baseQuery)) {
          yield chats;
        }
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          yield <ChatModel>[];
          return;
        }
        rethrow;
      }
    } catch (e) {
      await for (final chats in streamFromQuery(baseQuery)) {
        yield chats;
      }
    }
  }

  @override
  Future<void> setTyping({
    required String chatId,
    required String userId,
    required bool isTyping,
  }) async {
    final chatRef = _firestore.collection('chats').doc(chatId);
    final nowServer = FieldValue.serverTimestamp();
    final fieldPath = FieldPath(<String>['typing', userId]);

    try {
      if (isTyping) {
        await chatRef.update({fieldPath: nowServer});
      } else {
        await chatRef.update({fieldPath: FieldValue.delete()});
      }
    } on FirebaseException catch (e) {
      // If the chat document doesn't exist yet, create it with merge.
      if (e.code == 'not-found') {
        if (isTyping) {
          await chatRef.set(
            {
              'typing': {userId: nowServer},
            },
            SetOptions(merge: true),
          );
        } else {
          await chatRef.set(
            {
              'typing': {userId: FieldValue.delete()},
            },
            SetOptions(merge: true),
          );
        }
        return;
      }
      if (e.code == 'permission-denied') return;
      rethrow;
    }
  }

  @override
  Stream<List<ChatMessageModel>> watchChatMessages(
    String chatId, {
    int limit = 50,
  }) {
    try {
      return _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('sentAt', descending: false)
          .limit(limit)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (doc) => ChatMessageModel.fromJson({
                    'messageId': doc.id,
                    ...doc.data(),
                  }),
                )
                .toList(),
          )
          .handleError((error) {
            if (error is FirebaseException &&
                error.code == 'permission-denied') {
              return;
            }
            throw error;
          });
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
          'lastMessageSenderId': senderId,
          'lastMessageAt': nowServer,
          'unreadCount': FieldValue.increment(1),
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

      final nowServer = FieldValue.serverTimestamp();
      final data = chat.toJson();

      if (existing.exists) {
        // Only update names if the new value is a real name (not a fallback).
        // This prevents a viewer who can't resolve a name from overwriting
        // the correct name already stored by the original participant.
        final existingData = existing.data() ?? {};
        final generic = {
          'Hero',
          'Comprador',
          'Rider',
          'Cliente',
          'Vendedor',
          '',
        };

        String? pickName(String key, String? incoming) {
          if (incoming == null || generic.contains(incoming.trim())) {
            return existingData[key]?.toString();
          }
          return incoming;
        }

        final resolvedBuyerName = pickName(
          'buyerName',
          data['buyerName'] as String?,
        );
        final resolvedRiderName = pickName(
          'riderName',
          data['riderName'] as String?,
        );

        final updateData = <String, dynamic>{
          'updatedAt': nowServer,
          'participantIds': data['participantIds'],
        };

        final type = (data['type'] as String?) ?? '';
        if (type == 'hero_rider') {
          updateData['sellerId'] = FieldValue.delete();
        }
        if (type == 'hero_seller') {
          updateData['riderId'] = FieldValue.delete();
        }
        if (resolvedBuyerName != null) {
          updateData['buyerName'] = resolvedBuyerName;
        }
        if (resolvedRiderName != null) {
          updateData['riderName'] = resolvedRiderName;
        }

        await chatRef.set(updateData, SetOptions(merge: true));
      } else {
        // Chat doesn't exist, create it
        await chatRef.set({
          ...data,
          'createdAt': nowServer,
          'updatedAt': nowServer,
          'lastMessageAt': nowServer,
        });
      }
    } catch (e) {
      throw Exception('Error al crear chat: $e');
    }
  }

  @override
  Future<void> markMessagesAsRead({
    required String chatId,
    required String userId,
  }) async {
    try {
      final chatRef = _firestore.collection('chats').doc(chatId);
      final messagesRef = chatRef.collection('messages');

      final unreadSnapshot = await messagesRef
          .where('readAt', isNull: true)
          .get();
      if (unreadSnapshot.docs.isEmpty) return;

      final unreadMessages = unreadSnapshot.docs.where((doc) {
        final data = doc.data();
        final senderId = (data['senderId'] as String?) ?? '';
        return senderId.isNotEmpty && senderId != userId;
      }).toList();

      if (unreadMessages.isEmpty) return;

      // Update all unread messages with readAt timestamp
      final batch = _firestore.batch();
      final nowServer = FieldValue.serverTimestamp();

      for (final doc in unreadMessages) {
        batch.update(doc.reference, {'readAt': nowServer});
      }

      // Reset unreadCount in chat document
      batch.update(chatRef, {'unreadCount': 0, 'updatedAt': nowServer});

      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition' || e.code == 'permission-denied') {
        return;
      }
      rethrow;
    } catch (e) {
      throw Exception('Error al marcar mensajes como leídos: $e');
    }
  }
}
