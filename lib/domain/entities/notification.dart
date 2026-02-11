class AppNotification {
  final String id;
  final String userId;
  final String type; // 'order_status', 'nearby_order', 'system', 'chat'
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final String? action; // 'open_order', 'open_chat', 'open_screen'
  final String? imageUrl;
  final String priority; // 'high', 'normal', 'low'
  final DateTime createdAt;
  final bool read;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.action,
    this.imageUrl,
    this.priority = 'normal',
    required this.createdAt,
    this.read = false,
  });

  AppNotification copyWith({
    String? id,
    String? userId,
    String? type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    String? action,
    String? imageUrl,
    String? priority,
    DateTime? createdAt,
    bool? read,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      action: action ?? this.action,
      imageUrl: imageUrl ?? this.imageUrl,
      priority: priority ?? this.priority,
      createdAt: createdAt ?? this.createdAt,
      read: read ?? this.read,
    );
  }
}
