// lib/models/notification_item.dart
import 'package:flutter/material.dart';

enum NotificationType { lessonAdded, lessonCancelled, lessonRestored, examReminder, info }

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final NotificationType type;
  final DateTime? date;   // дата лекции (для lessonAdded/Cancelled/Restored)
  bool isRead;

  NotificationItem({
    required this.id, required this.title, required this.body,
    required this.timestamp, this.type = NotificationType.info,
    this.date, this.isRead = false,
  });

  IconData get icon {
    switch (type) {
      case NotificationType.lessonAdded:     return Icons.add_circle_rounded;
      case NotificationType.lessonCancelled: return Icons.cancel_rounded;
      case NotificationType.lessonRestored:  return Icons.restore_rounded;
      case NotificationType.examReminder:    return Icons.quiz_rounded;
      case NotificationType.info:            return Icons.info_outline_rounded;
    }
  }

  Color get color {
    switch (type) {
      case NotificationType.lessonAdded:     return const Color(0xFF16A34A);
      case NotificationType.lessonCancelled: return const Color(0xFFDC2626);
      case NotificationType.lessonRestored:  return const Color(0xFF2563EB);
      case NotificationType.examReminder:    return const Color(0xFFC62828);
      case NotificationType.info:            return const Color(0xFF6B7280);
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'body': body,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'type': type.name, 'isRead': isRead,
    if (date != null) 'date': date!.millisecondsSinceEpoch,
  };

  factory NotificationItem.fromJson(Map<String, dynamic> json) => NotificationItem(
    id:        json['id'] as String? ?? '',
    title:     json['title'] as String? ?? '',
    body:      json['body'] as String? ?? '',
    timestamp: DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as int?) ?? 0),
    type:      NotificationType.values.firstWhere(
      (e) => e.name == (json['type'] as String? ?? 'info'),
      orElse: () => NotificationType.info,
    ),
    date: json['date'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['date'] as int)
        : null,
    isRead: (json['isRead'] as bool?) ?? false,
  );
}
