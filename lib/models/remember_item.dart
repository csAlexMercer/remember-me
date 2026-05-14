import 'package:cloud_firestore/cloud_firestore.dart';

class RememberItem {
  final String id;
  final String userId;
  final String title;
  final String description;
  final int priority;
  final bool isAsleep;
  final DateTime createdAt;
  final DateTime? lastReminderSent;
  final int reminderCount;
  final DateTime? nextScheduledReminder;

  RememberItem({
    required this.id,
    required this.userId,
    required this.title,
    this.description = '',
    required this.priority,
    this.isAsleep = false,
    required this.createdAt,
    this.lastReminderSent,
    this.reminderCount = 0,
    this.nextScheduledReminder,
  });

  factory RememberItem.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return RememberItem(
      id: doc.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      priority: data['priority'] ?? 0,
      isAsleep: data['isAsleep'] ?? false,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      lastReminderSent: data['lastReminderSent'] != null 
          ? (data['lastReminderSent'] as Timestamp).toDate() 
          : null,
      reminderCount: data['reminderCount'] ?? 0,
      nextScheduledReminder: data['nextScheduledReminder'] != null 
          ? (data['nextScheduledReminder'] as Timestamp).toDate() 
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'title': title,
      'description': description,
      'priority': priority,
      'isAsleep': isAsleep,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastReminderSent': lastReminderSent != null ? Timestamp.fromDate(lastReminderSent!) : null,
      'reminderCount': reminderCount,
      'nextScheduledReminder': nextScheduledReminder != null ? Timestamp.fromDate(nextScheduledReminder!) : null,
    };
  }

  RememberItem copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    int? priority,
    bool? isAsleep,
    DateTime? createdAt,
    DateTime? lastReminderSent,
    int? reminderCount,
    DateTime? nextScheduledReminder,
  }) {
    return RememberItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      isAsleep: isAsleep ?? this.isAsleep,
      createdAt: createdAt ?? this.createdAt,
      lastReminderSent: lastReminderSent ?? this.lastReminderSent,
      reminderCount: reminderCount ?? this.reminderCount,
      nextScheduledReminder: nextScheduledReminder ?? this.nextScheduledReminder,
    );
  }
}
