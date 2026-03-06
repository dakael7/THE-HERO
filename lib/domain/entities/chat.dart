import 'chat_type.dart';

class Chat {
  final String chatId;
  final ChatType type;
  final String buyerId;
  final String? buyerName;
  final String? riderId;
  final String? riderName;
  final String? sellerId;
  final String? orderId;
  final String? offerId;
  final String lastMessageText;
  final String? lastMessageSenderId;
  final int unreadCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;
  final int version;

  Chat({
    required this.chatId,
    required this.type,
    required this.buyerId,
    this.buyerName,
    this.riderId,
    this.riderName,
    this.sellerId,
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

  List<String> get participantIds {
    switch (type) {
      case ChatType.heroRider:
        final r = (riderId ?? '').trim();
        return <String>[buyerId, if (r.isNotEmpty) r];
      case ChatType.heroSeller:
        final s = (sellerId ?? '').trim();
        return <String>[buyerId, if (s.isNotEmpty) s];
    }
  }

  Chat copyWith({
    String? chatId,
    ChatType? type,
    String? buyerId,
    String? buyerName,
    String? riderId,
    String? riderName,
    String? sellerId,
    String? orderId,
    String? offerId,
    String? lastMessageText,
    String? lastMessageSenderId,
    int? unreadCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastMessageAt,
    int? version,
  }) {
    return Chat(
      chatId: chatId ?? this.chatId,
      type: type ?? this.type,
      buyerId: buyerId ?? this.buyerId,
      buyerName: buyerName ?? this.buyerName,
      riderId: riderId ?? this.riderId,
      riderName: riderName ?? this.riderName,
      sellerId: sellerId ?? this.sellerId,
      orderId: orderId ?? this.orderId,
      offerId: offerId ?? this.offerId,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      unreadCount: unreadCount ?? this.unreadCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      version: version ?? this.version,
    );
  }

  static String generateChatId({
    required ChatType type,
    required String buyerId,
    String? riderId,
    String? sellerId,
    String? orderId,
    String? offerId,
  }) {
    if (buyerId.isEmpty) {
      throw ArgumentError('buyerId es requerido');
    }

    if (type == ChatType.heroRider) {
      final id = (orderId ?? '').trim();
      if (id.isEmpty) {
        throw ArgumentError('orderId es requerido para chats hero_rider');
      }
      final r = (riderId ?? '').trim();
      if (r.isEmpty) {
        throw ArgumentError('riderId es requerido para chats hero_rider');
      }

      final b = buyerId.trim();
      if (b.isEmpty) {
        throw ArgumentError('buyerId es requerido para chats hero_rider');
      }

      return '${type.jsonValue}_${b}_${r}_order_$id';
    }

    final otherId = type == ChatType.heroRider ? riderId : sellerId;
    if (otherId == null || otherId.isEmpty) {
      throw ArgumentError(
        type == ChatType.heroRider
            ? 'riderId es requerido para chats hero_rider'
            : 'sellerId es requerido para chats hero_seller',
      );
    }

    final contextId = (orderId != null && orderId.isNotEmpty)
        ? orderId
        : (offerId != null && offerId.isNotEmpty)
        ? offerId
        : null;

    if (contextId == null || contextId.isEmpty) {
      throw ArgumentError('orderId u offerId es requerido');
    }

    return '${type.jsonValue}_${buyerId}_${otherId}_$contextId';
  }
}
