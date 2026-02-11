import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/notification.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final String? action;
  final String? imageUrl;
  final String priority;
  final DateTime createdAt;
  final bool read;

  NotificationModel({
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

  factory NotificationModel.fromJson(Map<String, dynamic> json, String id) {
    return NotificationModel(
      id: id,
      userId: json['userId'] as String? ?? '',
      type: json['type'] as String? ?? 'system',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>? ?? {},
      action: json['action'] as String?,
      imageUrl: json['imageUrl'] as String?,
      priority: json['priority'] as String? ?? 'normal',
      createdAt: (json['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      read: json['read'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'type': type,
      'title': title,
      'body': body,
      'data': data,
      'action': action,
      'imageUrl': imageUrl,
      'priority': priority,
      'createdAt': Timestamp.fromDate(createdAt),
      'read': read,
    };
  }

  AppNotification toEntity() {
    return AppNotification(
      id: id,
      userId: userId,
      type: type,
      title: title,
      body: body,
      data: data,
      action: action,
      imageUrl: imageUrl,
      priority: priority,
      createdAt: createdAt,
      read: read,
    );
  }
}
