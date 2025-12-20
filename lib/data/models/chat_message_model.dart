import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

import '../../domain/entities/chat_message.dart';

class ChatMessageModel {
  final String messageId;
  final String chatId;
  final String senderId;
  final String text;
  final firestore.Timestamp sentAt;
  final firestore.Timestamp? editedAt;
  final firestore.Timestamp? readAt;
  final bool deleted;
  final int version;

  ChatMessageModel({
    required this.messageId,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.editedAt,
    this.readAt,
    this.deleted = false,
    this.version = 1,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      messageId: json['messageId'] as String? ?? '',
      chatId: json['chatId'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      text: json['text'] as String? ?? '',
      sentAt: json['sentAt'] as firestore.Timestamp? ?? firestore.Timestamp.now(),
      editedAt: json['editedAt'] as firestore.Timestamp?,
      readAt: json['readAt'] as firestore.Timestamp?,
      deleted: json['deleted'] as bool? ?? false,
      version: json['version'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'chatId': chatId,
      'senderId': senderId,
      'text': text,
      'sentAt': sentAt,
      'editedAt': editedAt,
      'readAt': readAt,
      'deleted': deleted,
      'version': version,
    };
  }

  ChatMessage toEntity() {
    return ChatMessage(
      messageId: messageId,
      chatId: chatId,
      senderId: senderId,
      text: text,
      sentAt: sentAt.toDate(),
      editedAt: editedAt?.toDate(),
      readAt: readAt?.toDate(),
      deleted: deleted,
      version: version,
    );
  }

  factory ChatMessageModel.fromEntity(ChatMessage entity) {
    return ChatMessageModel(
      messageId: entity.messageId,
      chatId: entity.chatId,
      senderId: entity.senderId,
      text: entity.text,
      sentAt: firestore.Timestamp.fromDate(entity.sentAt),
      editedAt: entity.editedAt != null ? firestore.Timestamp.fromDate(entity.editedAt!) : null,
      readAt: entity.readAt != null ? firestore.Timestamp.fromDate(entity.readAt!) : null,
      deleted: entity.deleted,
      version: entity.version,
    );
  }
}
