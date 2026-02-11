import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

import '../../domain/entities/chat.dart';
import '../../domain/entities/chat_type.dart';

class ChatModel {
  final String chatId;
  final String type;
  final String buyerId;
  final String? buyerName;
  final String? riderId;
  final String? riderName;
  final String? sellerId;
  final List<String> participantIds;
  final String? orderId;
  final String? offerId;
  final String lastMessageText;
  final String? lastMessageSenderId;
  final int unreadCount;
  final firestore.Timestamp createdAt;
  final firestore.Timestamp updatedAt;
  final firestore.Timestamp? lastMessageAt;
  final int version;

  ChatModel({
    required this.chatId,
    required this.type,
    required this.buyerId,
    this.buyerName,
    this.riderId,
    this.riderName,
    this.sellerId,
    required this.participantIds,
    this.orderId,
    this.offerId,
    this.lastMessageText = '',
    this.lastMessageSenderId,
    this.unreadCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageAt,
    this.version = 1,
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    final buyerId =
        (json['buyerId'] as String?) ?? (json['heroId'] as String?) ?? '';
    final riderId = json['riderId'] as String?;
    final sellerId = json['sellerId'] as String?;
    final rawParticipantIds = json['participantIds'];
    final participantIds = rawParticipantIds is List
        ? rawParticipantIds.map((e) => e.toString()).toList()
        : <String>[
            if (buyerId.isNotEmpty) buyerId,
            if (riderId != null && riderId.isNotEmpty) riderId,
            if (sellerId != null && sellerId.isNotEmpty) sellerId,
          ];

    return ChatModel(
      chatId: json['chatId'] as String? ?? '',
      type: json['type'] as String? ?? 'hero_rider',
      buyerId: buyerId,
      buyerName: json['buyerName'] as String? ?? '',
      riderId: riderId,
      riderName: json['riderName'] as String?,
      sellerId: sellerId,
      participantIds: participantIds,
      orderId: json['orderId'] as String?,
      offerId: json['offerId'] as String?,
      lastMessageText: json['lastMessageText'] as String? ?? '',
      lastMessageSenderId: json['lastMessageSenderId'] as String?,
      unreadCount: (json['unreadCount'] as int?) ?? 0,
      createdAt:
          json['createdAt'] as firestore.Timestamp? ??
          firestore.Timestamp.now(),
      updatedAt:
          json['updatedAt'] as firestore.Timestamp? ??
          firestore.Timestamp.now(),
      lastMessageAt: json['lastMessageAt'] as firestore.Timestamp?,
      version: json['version'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chatId': chatId,
      'type': type,
      'buyerId': buyerId,
      'buyerName': buyerName,
      'heroId': buyerId,
      'riderId': riderId,
      'riderName': riderName,
      'sellerId': sellerId,
      'participantIds': participantIds,
      'orderId': orderId,
      'offerId': offerId,
      'lastMessageText': lastMessageText,
      'lastMessageSenderId': lastMessageSenderId,
      'unreadCount': unreadCount,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'lastMessageAt': lastMessageAt,
      'version': version,
    };
  }

  Chat toEntity() {
    return Chat(
      chatId: chatId,
      type: ChatType.fromString(type),
      buyerId: buyerId,
      buyerName: buyerName,
      riderId: riderId,
      riderName: riderName,
      sellerId: sellerId,
      orderId: orderId,
      offerId: offerId,
      lastMessageText: lastMessageText,
      lastMessageSenderId: lastMessageSenderId,
      unreadCount: unreadCount,
      createdAt: createdAt.toDate(),
      updatedAt: updatedAt.toDate(),
      lastMessageAt: lastMessageAt?.toDate(),
      version: version,
    );
  }

  factory ChatModel.fromEntity(Chat entity) {
    return ChatModel(
      chatId: entity.chatId,
      type: entity.type.jsonValue,
      buyerId: entity.buyerId,
      buyerName: entity.buyerName,
      riderId: entity.riderId,
      riderName: entity.riderName,
      sellerId: entity.sellerId,
      participantIds: entity.participantIds,
      orderId: entity.orderId,
      offerId: entity.offerId,
      lastMessageText: entity.lastMessageText,
      lastMessageSenderId: entity.lastMessageSenderId,
      unreadCount: entity.unreadCount,
      createdAt: firestore.Timestamp.fromDate(entity.createdAt),
      updatedAt: firestore.Timestamp.fromDate(entity.updatedAt),
      lastMessageAt: entity.lastMessageAt != null
          ? firestore.Timestamp.fromDate(entity.lastMessageAt!)
          : null,
      version: entity.version,
    );
  }
}
