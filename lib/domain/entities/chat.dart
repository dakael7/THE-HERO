import 'chat_type.dart';

class Chat {
  final String chatId;
  final ChatType type;
  final String buyerId;
  final String? riderId;
  final String? sellerId;
  final String? orderId;
  final String? offerId;
  final String lastMessageText;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;
  final int version;

  Chat({
    required this.chatId,
    required this.type,
    required this.buyerId,
    this.riderId,
    this.sellerId,
    this.orderId,
    this.offerId,
    this.lastMessageText = '',
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageAt,
    this.version = 1,
  });

  List<String> get participantIds {
    final ids = <String>[buyerId];
    if (riderId != null && riderId!.isNotEmpty) ids.add(riderId!);
    if (sellerId != null && sellerId!.isNotEmpty) ids.add(sellerId!);
    return ids;
  }

  Chat copyWith({
    String? chatId,
    ChatType? type,
    String? buyerId,
    String? riderId,
    String? sellerId,
    String? orderId,
    String? offerId,
    String? lastMessageText,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastMessageAt,
    int? version,
  }) {
    return Chat(
      chatId: chatId ?? this.chatId,
      type: type ?? this.type,
      buyerId: buyerId ?? this.buyerId,
      riderId: riderId ?? this.riderId,
      sellerId: sellerId ?? this.sellerId,
      orderId: orderId ?? this.orderId,
      offerId: offerId ?? this.offerId,
      lastMessageText: lastMessageText ?? this.lastMessageText,
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

    return '${type.jsonValue}_${buyerId}_${otherId}_${contextId}';
  }
}
