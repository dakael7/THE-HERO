class ChatMessage {
  final String messageId;
  final String chatId;
  final String senderId;
  final String text;
  final DateTime sentAt;
  final DateTime? editedAt;
  final DateTime? readAt;
  final bool deleted;
  final int version;

  ChatMessage({
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

  bool get isRead => readAt != null;

  ChatMessage copyWith({
    String? messageId,
    String? chatId,
    String? senderId,
    String? text,
    DateTime? sentAt,
    DateTime? editedAt,
    DateTime? readAt,
    bool? deleted,
    int? version,
  }) {
    return ChatMessage(
      messageId: messageId ?? this.messageId,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      text: text ?? this.text,
      sentAt: sentAt ?? this.sentAt,
      editedAt: editedAt ?? this.editedAt,
      readAt: readAt ?? this.readAt,
      deleted: deleted ?? this.deleted,
      version: version ?? this.version,
    );
  }
}
