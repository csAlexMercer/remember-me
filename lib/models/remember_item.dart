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

  /// Whether this item qualifies as high priority in the UI.
  bool get isHighPriority => priority >= 70;

  /// Whether this item should receive notification reminders.
  bool get shouldNotify => priority >= 60;

  /// Calculate the initial delay (D0) based on priority tier.
  /// Returns null if priority is below the notification threshold.
  Duration? get initialDelay {
    if (priority >= 90) return const Duration(hours: 8);
    if (priority >= 80) return const Duration(hours: 12);
    if (priority >= 70) return const Duration(hours: 24);
    if (priority >= 60) return const Duration(hours: 48);
    return null; // Below notification threshold
  }

  /// Calculate the next reminder delay using the Multiplier Effect.
  /// D{n+1} = D0 * (1.5 ^ reminderCount)
  /// Returns null if priority is below the notification threshold.
  Duration? get nextReminderDelay {
    final d0 = initialDelay;
    if (d0 == null) return null;

    final multiplier = _pow(1.5, reminderCount);
    final delayMinutes = (d0.inMinutes * multiplier).round();
    return Duration(minutes: delayMinutes);
  }

  /// Calculate the next scheduled DateTime from now using the multiplier effect.
  DateTime? calculateNextReminderDate() {
    final delay = nextReminderDelay;
    if (delay == null) return null;
    return DateTime.now().add(delay);
  }

  /// Simple power function for doubles.
  static double _pow(double base, int exponent) {
    double result = 1.0;
    for (int i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }

  /// Generate a stable notification ID from the Firestore document ID.
  int get notificationId => id.hashCode.abs();

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
      'lastReminderSent': lastReminderSent != null
          ? Timestamp.fromDate(lastReminderSent!)
          : null,
      'reminderCount': reminderCount,
      'nextScheduledReminder': nextScheduledReminder != null
          ? Timestamp.fromDate(nextScheduledReminder!)
          : null,
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
      nextScheduledReminder:
          nextScheduledReminder ?? this.nextScheduledReminder,
    );
  }
}
